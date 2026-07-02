# EatWise 设计文档

> 项目代号：EatWise
> 形态：Flutter 跨平台 App（iOS + Android）
> 定位：个人自用的拍照识别食物热量 + 营养记录 + AI 周/月汇总建议工具
> 日期：2026-07-01
> 状态：Sprint 6 已实现

---

## 1. 项目概述

### 1.1 解决的问题

现有卡路里记录 App（薄荷健康、MyFitnessPal、Yazio）存在三个共同缺陷：
1. 食物拍照识别能力弱，主要靠手动搜索
2. 记录与"我的长期减脂/增肌计划"联动差，只显示今日热量
3. 缺少基于个人近期数据的阶段性 AI 建议

EatWise 通过「拍照识别 → 份量校准 → 营养计算 → 长期趋势 → AI 汇总建议」闭环解决上述问题。

### 1.2 核心价值主张

- 拍一张食物照片即可记录，模型识别菜名+估份量，营养数据来自权威食物库而非模型直出（单品 ±3-5%，复合菜 ±10-15%，纯图像估算 ±20%）
- 基于身高/体重/目标自动计算每日热量与宏量营养素目标（公式依据 ACSM/ISSN/NIH/WHO 权威标准）
- 周/月趋势图 + AI 阶段性建议（依据近 7 天数据生成中文建议）
- 数据本地 AES 加密存储，可导出/导入 JSON 备份，换机不丢

### 1.3 非目标（YAGNI - 明确不做）

- 不做多用户/账号体系/云同步（个人自用）
- 不做社交/分享/排行榜
- 不做运动同步（Apple Health / Google Fit，依赖重）
- 不做推送提醒（MVP 不做）
- 不做详细维生素/矿物质/膳食纤维追踪与雷达图（MVP 只追踪热量+三大宏量；food_item 可选存储 edible_percent 供可食部换算，但不作为展示功能）
- 不做付费/会员体系

---

## 2. 系统架构

### 2.1 整体架构

纯前端无后端架构：

```
Flutter App (iOS + Android, 一套代码)
  ├─ drift ≥ 2.32 + sqlite3mc (build hooks) ← AES 加密本地数据库
  ├─ flutter_secure_storage                  ← DB 密钥 + 大模型 API key
  ├─ connectivity_plus (前台实时)            ← 离线检测 + 前台 UI 反馈
  ├─ workmanager (后台兜底)                   ← 后台网络恢复时回补离线队列
  ├─ 本地食材库（中国食物成分表第6版 JSON）
  ├─ Qwen-VL API (首选) / GLM-4V-Plus (备选) ← 拍照识别菜名+份量+食材组分
  │   └─ response_format=json_object + few-shot（非 function calling，因无强制 schema）
  ├─ GLM-4-Flash API (免费文本模型)          ← AI 周/月汇总建议
  ├─ image_picker → flutter_image_compress   ← 拍照 → 显式剥离 EXIF + 压缩
  ├─ fl_chart                                ← 趋势图表
  ├─ sentry_flutter                          ← 错误监控（Crash 自动上报，脱敏业务数据）
  └─ JSON 导出/导入                           ← 换机/备份
```

### 2.2 技术选型与依据

| 层 | 选型 | 依据 |
|---|---|---|
| 框架 | Flutter | UI 一致性高、双端一套代码、拍照/图表/本地数据库生态成熟 |
| 数据库 | drift ≥ 2.32 | pub.dev likes 2.23K，类型安全，响应式 Stream，全平台支持 |
| 数据库加密 | sqlite3 build hooks (source: sqlite3mc, SQLite3MultipleCiphers) | drift 2.32+ 官方现行推荐；sqlcipher_flutter_libs 已 EOL（0.7.0 起不再生效），故弃用 |
| 密钥存储 | flutter_secure_storage | iOS Keychain / Android Keystore 底层；AES-256 (32 字节) 密钥在 Android Keystore 支持范围内（Keystore 支持 AES-128/256，HMAC ≤32 字节，非"无限制"）；minSdk 23+ 保证 AndroidKeyStore 可用，无 StrongBox 时仍由 TrustZone/TEE 硬件保护 |
| 拍照 | image_picker | flutter.dev 官方一方包 |
| 图片预处理 | flutter_image_compress | keepExif 参数自 0.6.1 起支持，默认 false 即剥离 EXIF（无需显式传 false；image_picker 未契约化保证 EXIF 保留，iOS 实现层会尝试复制但跨版本有回归风险，故业务层不依赖）；支持 autoCorrectionAngle 方向校正（默认 true，与 rotate 同时使用时注意历史冲突） |
| 图表 | fl_chart | Flutter 生态事实标准 |
| 网络状态(前台) | connectivity_plus | 前台实时 UI 反馈（离线 Banner、网络恢复立即同步当前会话） |
| 后台任务 | workmanager | 后台兜底回补；配置 Constraints(networkType: CONNECTED)；connectivity_plus 在 App 后台时无法可靠触发（Android 8.0 (API 26)+ 后台执行限制） |
| 视觉大模型 | Qwen-VL (qwen3-vl-flash 起步) | 中文食物识别实测案例多；兼容 OpenAI SDK；0.15/1.5 元每百万 token；90天100万 token 免费。注：function calling 无 tool_choice=required，不能强制 schema，改用 response_format=json_object + few-shot |
| 备选视觉模型 | GLM-4V-Plus | 新用户送 2000 万 token（20 million tokens 体验包），免费额度最大，作容灾。注：需核实该体验包是否对 GLM-4V-Plus 视觉模型通用（智谱不同模型免费额度策略可能差异） |
| 文本大模型 | GLM-4-Flash（模型名固定 glm-4-flash 或 glm-4-flash-250414） | 完全免费；注意勿误用 GLM-4-FlashX（0.1 元/百万 token，非免费变体，名称相近易混淆） |
| HTTP 客户端 | openai_dart ^7.0 | 纯 Dart、类型安全，显式支持 OpenAI-compatible APIs；百炼与智谱均兼容但 base_url 格式不同（百炼含 WorkspaceId，智谱结尾带斜杠），需分别封装 OpenAIClient 实例 |
| 错误监控 | sentry_flutter ^9.22 | pub.dev likes 1.07K，verified publisher sentry.io；免费层 5K errors/月够个人用；自动捕获 Flutter/Dart/Native 崩溃；支持服务端+客户端脱敏 |
| 离线队列 | drift pending_recognition 表 | 简单 FIFO，个人单端无需复杂冲突解决 |

### 2.3 大模型调用架构

```
拍照 → flutter_image_compress(默认剥离 EXIF + 压缩) → Vision API 调用
                                        ├─ 首选: Qwen-VL (response_format=json_object + few-shot)
                                        └─ 容灾: GLM-4V-Plus (主选失败时降级)
返回 {菜名, 估量g区间, 食材组分[], 烹饪方式, 置信度}
                                        ↓
                              营养计算（两条路径）:
                              ├─ 单品(苹果/鸡蛋): 查食材库 → 热量密度×份量
                              └─ 复合菜(宫保鸡丁): 按食材组分分别查库累加
                                                 + 烹饪用油系数×份数
                              (营养数据来自库，非模型直出)
                                        ↓
                              校准页 → 写入今日记录
```

**关于结构化输出说明**：Qwen-VL 的 function calling 不支持 `tool_choice="required"`，schema 仅为"建议"非强制。故采用 `response_format={"type":"json_object"}` 强制合法 JSON 语法 + system prompt 写明完整 schema 描述 + 1-2 个 few-shot 示例的方案。下游对返回 JSON 做 schema 校验，字段缺失时触发重试或转手动录入。

### 2.4 工程架构

| 层 | 选型 | 依据 |
|---|---|---|
| 状态管理 | flutter_riverpod ^3.3 | pub.dev likes 2.87K；编译期安全，StreamProvider 直接订阅 drift `.watch()` 返回的 Stream；Notifier 体系适合中大型 App |
| 路由 | go_router ^17.2 | flutter.dev 一方包（likes 5.73K），声明式路由，支持深链接与 Web URL |
| 依赖注入 | Riverpod Provider | 复用 Riverpod Provider 体系做 DI，不额外引入 get_it，减少依赖 |
| 主题 | ThemeData + ColorScheme | Material 3 默认，不引入额外主题包 |

**分层规则**：
- `data/` 层只暴露 Repository 抽象接口，实现类注入 drift database 实例
- `features/` 层通过 Riverpod Provider 获取 Repository，UI 用 ConsumerWidget + AsyncValue 消费 drift Stream
- `ai/` 层定义 VisionProvider 抽象接口，QwenVlProvider / Glm4vProvider 为实现类，通过 Provider 注入
- `core/` 层放主题、错误处理、通用工具，无业务逻辑

---

## 3. 核心数据流

### 3.1 拍照识别闭环（主流程）

```
1. 用户点"+"按钮 → 选择拍照或从相册选图
2. 本地预处理（flutter_image_compress）：
   - EXIF/XMP/IPTC 元数据默认剥离（keepExif 默认 false，隐私保护）
   - autoCorrectionAngle 校正方向
   - 压缩到最大边 1024px、JPEG 质量 85%（控成本+降泄露信息量）
3. 检查网络：
   ├─ 在线：直接调 Vision API（步骤 4）
   └─ 离线：图片落盘 + 写 pending_recognition 表(pending) → 提示"待联网识别"
       （前台联网由 connectivity_plus 触发回补；后台联网由 workmanager 触发回补）
4. 调 Qwen-VL（response_format=json_object + few-shot 示例）
   返回: {dish_name, estimated_weight_g_low, estimated_weight_g_mid, estimated_weight_g_high,
          food_components[{name, estimated_g}], cooking_method, is_single_item, confidence}
   （is_single_item=true 表示是单品如苹果/鸡蛋，false 表示复合菜）
5. 营养数据查库（分两条路径）：
   ├─ 单品(is_single_item=true): 用 dish_name 查食材库
   │   ├─ 查到：取热量密度(kcal/100g) → 进校准页
   │   └─ 查不到：提示"菜名不对？手动改" → 改后重新查库 → 仍无则转手动录入
   └─ 复合菜(is_single_item=false): 用 food_components 逐项查食材库累加
       ├─ 各组分查到：热量=Σ(组分热量密度×组分估量/100) + 用油系数×烹饪方式
       └─ 某组分查不到：标注该组分"待确认"，用户可手动改组分名或手动输入该组分热量
6. 校准页（按置信度分级，平衡准确度与使用留存）：
   - 置信度 ≥ 0.85 且单品：允许"一键记录"跳过校准（默认用 estimated_weight_g_mid），降低高频使用摩擦
   - 置信度 < 0.6：强制校准，标注"待确认"
   - 中间区 (0.6-0.85)：默认进校准页，提供"信任 AI"快捷按钮
   - 默认填入 estimated_weight_g_mid（单品）或各组分 estimated_g（复合菜）
   - 单品：用户拖动滑块调整总份量（0-1000g），营养素实时重算
   - 复合菜：用户可调整各组分份量 + "用油量"滑块（默认取烹饪方式系数，可手动调）
7. 选餐次（早/午/晚/加餐）→ 写入 meal_log 表
8. 更新今日额度看板
9. 存入"我的食物库"（去重逻辑：按 name+source 查重，已存在则更新 default_serving_g）
```

**烹饪方式用油系数表**（默认值，用户可在校准页调整）：

| 烹饪方式 | 默认用油量(g/份) | 说明 |
|---|---|---|
| 蒸 | 0 | 无加油 |
| 煮 | 0 | 通常不加油（煮面/煮菜） |
| 凉拌 | 8 | 调味汁含油 |
| 烤 | 8 | 表面刷油 |
| 炒 | 12 | 标准炒菜用油 |
| 煎 | 15 | 煎制用油 |
| 炸 | 25 | 油炸吸油 |
| 红烧 | 10 | 炒糖色+少量油 |

注：此为粗估系数，实际用油量差异大，故提供滑块让用户调整。数据来源为家常菜烹饪经验值，非权威标准。

### 3.2 失败处理与降级

| 失败类型 | 处理策略 |
|---|---|
| API 超时 | L1 重试 1 次（带 jitter 退避）→ L2 切 GLM-4V-Plus → L3 转手动录入 |
| 限流 429 | 尊重 Retry-After 头等待 → 仍失败转手动录入 |
| JSON 解析失败 | 修复后重发（malformed 必须带错误信息，不可盲目重试） |
| 幻觉菜名 | 提供手动改菜名入口 → 改后查库 → 仍无则手动录入 |
| 置信度 < 0.6 | 标注"待确认"，强制进校准页人工校验 |
| key 失效 401/403 | 引导到设置页重新配置 key |
| 连续 3 次失败 | 断路器短路 30s，避免烧预算 |

---

## 4. 数据模型

### 4.1 数据库总览

数据库：drift ≥ 2.32 + sqlite3mc（SQLite3MultipleCiphers，AES-256 加密）
密钥：首次启动生成随机 32 字节密钥，存 flutter_secure_storage
Schema 版本管理：drift schemaVersion + MigrationStrategy

**时区与日期处理约定**：
- 所有 `date` 字段（meal_log.date / weight_log.date / pending_recognition.date / insight_summary.period_*）存 'YYYY-MM-DD'，取**用户设备本地时区的自然日**（不引入固定时区，因个人自用不跨时区协作）
- 所有 `logged_at` / `created_at` / `processed_at` / `generated_at` 时间戳存 **UTC 毫秒**（INTEGER），便于跨时区换算
- UI 展示按本地时区渲染；深夜吃东西（如 23:50 拍照）按本地自然日记入当天，不算次日
- 出国旅游场景：用户切换设备时区后，新记录按新时区的自然日，历史记录不变；不做时区回溯重算

### 4.2 表结构

#### 4.2.1 profile（个人档案，单行表）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | 固定为 1（单用户单档案） |
| height_cm | REAL | 身高 |
| weight_kg | REAL | 当前体重（最新） |
| body_fat_pct | REAL NULL | 体脂率（可选，用于 Katch-McArdle 公式） |
| age | INTEGER | 年龄 |
| gender | TEXT | 'male' / 'female' |
| activity_level | REAL | 活动系数：1.2/1.375/1.55/1.725/1.9 |
| goal | TEXT | 'cut'(减脂) / 'bulk'(增肌) / 'maintain'(维持) |
| goal_rate_kg_per_week | REAL | 目标速率（减脂 0.5-1.0 kg/周、增肌 0.25-0.5% 体重/周）；与热量赤字/盈余联动：减脂赤字≈goal_rate×7700/7 kcal/天 |
| formula | TEXT | 'mifflin' / 'katch'（有体脂率时才可选 katch） |
| daily_calorie_target | INTEGER | 每日热量目标（kcal）=TDEE±赤字/盈余，受硬下限约束 |
| protein_g_per_kg | REAL | 蛋白质目标（g/kg 体重） |
| fat_g_per_kg | REAL | 脂肪目标（g/kg 体重） |
| carb_g_per_kg | REAL NULL | 碳水目标（g/kg 体重）；减脂/维持场景=剩余热量÷4÷体重（派生值，存缓存）；增肌场景用户设 4-7 |
| tdee_adjustment_kcal | INTEGER | TDEE 自适应微调值（默认 0）；见 5.5 节，连续体重偏差触发后累加此值；daily_calorie_target = TDEE ± 赤字/盈余 + tdee_adjustment_kcal |
| updated_at | INTEGER | 时间戳 |

#### 4.2.2 food_item（食物库 - 含识别入库和手动入库）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | 自增 |
| name | TEXT | 食物名称 |
| default_serving_g | REAL | 默认份量 |
| calories_per_100g | REAL | 每 100g 热量 |
| protein_per_100g | REAL | 每 100g 蛋白质 |
| fat_per_100g | REAL | 每 100g 脂肪 |
| carbs_per_100g | REAL | 每 100g 碳水 |
| aliases_json | TEXT NULL | 别名列表 JSON（如 `["西红柿","tomato"]`），查库时按 name OR aliases 匹配；导入食材库时人工补充常见别名（番茄/西红柿、土豆/马铃薯等 20-30 组） |
| edible_percent | REAL NULL | 可食部比例（0-100），默认 100；导入食材库时填充，供"带皮/带骨称重"场景可选换算 |
| source | TEXT | 'china_fct'(中国食物成分表) / 'usda' / 'off' / 'manual' / 'ai_recognized' |
| source_version | TEXT | 数据源版本（如 "china_fct_v6"） |
| confidence | REAL NULL | AI 识别置信度（仅 ai_recognized 来源） |
| components_json | TEXT NULL | 复合菜的组分拆解 JSON（仅复合菜） |
| thumbnail_path | TEXT NULL | 缩略图本地路径 |
| created_at | INTEGER | 创建时间 |

#### 4.2.3 meal_log（餐次记录）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | 自增 |
| date | TEXT | 日期 'YYYY-MM-DD'，取设备本地时区自然日（见 4.1 时区约定） |
| meal_type | TEXT | 'breakfast' / 'lunch' / 'dinner' / 'snack'；加餐多次时同日可多条 snack 记录，按 logged_at 时间戳排序展示 |
| food_item_id | INTEGER FK | 关联 food_item |
| actual_serving_g | REAL | 实际份量（克） |
| actual_calories | REAL | 实际热量（计算值） |
| actual_protein_g | REAL | 实际蛋白质 |
| actual_fat_g | REAL | 实际脂肪 |
| actual_carbs_g | REAL | 实际碳水 |
| original_image_path | TEXT NULL | 原图本地路径（仅拍照识别记录） |
| recognition_confidence | REAL NULL | 识别置信度（仅拍照记录） |
| components_snapshot_json | TEXT NULL | 复合菜本次记录的实际组分份量快照（含各组分 name/actual_g 及用油量 g），用户校准后冻结写入；与 food_item.components_json（默认值）分离，确保下次复用时用默认值而非上次校准值 |
| logged_at | INTEGER | 记录时间戳 |

#### 4.2.4 weight_log（体重记录）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | 自增 |
| date | TEXT | 日期 'YYYY-MM-DD'，取设备本地时区自然日（见 4.1 时区约定） |
| weight_kg | REAL | 体重 |

#### 4.2.5 pending_recognition（离线识别队列）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | 自增 |
| image_path | TEXT | 图片本地路径 |
| meal_type | TEXT | 用户拍照时选定的餐次 'breakfast'/'lunch'/'dinner'/'snack'，联网识别成功后写入 meal_log 时使用 |
| date | TEXT | 拍照日期 'YYYY-MM-DD'，取设备本地时区自然日（见 4.1 时区约定）；识别回补后写入 meal_log 用此日期，避免离线拍照跨日回补导致记录错位（如昨晚 23:50 拍的算昨天） |
| status | TEXT | 'pending' / 'done' / 'failed' |
| retry_count | INTEGER | 默认 0，上限 3 |
| result_food_item_id | INTEGER NULL FK | 识别成功后关联的 food_item |
| error_message | TEXT NULL | 失败原因（malformed/timeout/rate_limit/auth_fail），便于断路器分类处理 |
| prompt_version | TEXT NULL | 识别时使用的 prompt 版本号（如 "v1.2"），见 11.2 节 prompt 版本管理；便于准确率退化时追溯 |
| created_at | INTEGER | 创建时间 |
| processed_at | INTEGER NULL | 识别完成时间 |

#### 4.2.6 insight_summary（AI 汇总建议）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | 自增 |
| period_type | TEXT | 'weekly' / 'monthly' |
| period_start | TEXT | 周期起始日期 'YYYY-MM-DD' |
| period_end | TEXT | 周期结束日期 'YYYY-MM-DD' |
| summary_text | TEXT | GLM-4-Flash 生成的中文建议（限 300 字）；用户可手动编辑沉淀为个人笔记 |
| is_edited | INTEGER | 用户是否手动编辑过（0/1）；编辑后点"重新生成"需二次确认，避免覆盖用户笔记 |
| generated_at | INTEGER | 生成/更新时间戳 |

注：唯一约束 period_type + period_start，避免重复调用 API 烧 token；离线时不生成，联网后按需生成。

#### 4.2.7 recognition_feedback（识别反馈，prompt 改进数据源）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | 自增 |
| meal_log_id | INTEGER FK ON DELETE CASCADE | 关联 meal_log（仅拍照识别记录可反馈）；用户删除餐次记录时关联反馈级联删除，避免孤儿记录 |
| is_correct | INTEGER | 1=识别正确，0=识别有误 |
| corrected_dish_name | TEXT NULL | 用户标注的正确菜名（is_correct=0 时填） |
| corrected_serving_g | REAL NULL | 用户标注的正确份量（克，is_correct=0 时填） |
| prompt_version | TEXT | 该次识别使用的 prompt 版本号（关联 pending_recognition.prompt_version），便于按版本统计准确率 |
| created_at | INTEGER | 反馈时间戳（UTC 毫秒） |

注：用于积累动态回归集，比静态 50 张照片更有价值。按 prompt_version 聚合准确率，退化时触发回归排查。导出时包含此表（用户标注数据）。

### 4.3 派生数据（不存储，实时聚合）

- `daily_summary`：从 meal_log 按 date 聚合（总热量、三大宏量总和、按餐次分组）
- `weekly_summary`：从 meal_log + weight_log 按周聚合
- `monthly_summary`：从 meal_log + weight_log 按月聚合

不存储派生数据避免数据不一致问题。

---

## 5. 营养计算模块

### 5.1 BMR（基础代谢率）公式

**默认 Mifflin-St Jeor**（美国营养与饮食学会 AND 官方推荐，Frankenfield 2005 系统综述显示 82% 人群落在 ±10% 内）：

```
男性: BMR = 10 × weight_kg + 6.25 × height_cm − 5 × age + 5
女性: BMR = 10 × weight_kg + 6.25 × height_cm − 5 × age − 161
```

**可选 Katch-McArdle**（仅当用户录入体脂率时启用，对精瘦/运动员人群更准）：

```
BMR = 370 + 21.6 × lean_body_mass_kg
lean_body_mass_kg = weight_kg × (1 − body_fat_pct / 100)
```

**明确弃用 Harris-Benedict 作默认**（系统性高估现代人群 BMR 约 5%）。

### 5.2 TDEE（每日总能量消耗）

```
TDEE = BMR × activity_level
```

活动系数档位（ACSM 标准）：
- 1.2：久坐（办公室工作，无运动）
- 1.375：轻度（每周 1-3 次轻度运动）
- 1.55：中度（每周 3-5 次中等运动）
- 1.725：高度（每周 6-7 次剧烈运动）
- 1.9：极高（体力工作 + 每日训练）

### 5.3 目标热量计算

| 目标 | 热量调整 | 速率 | 依据 |
|---|---|---|---|
| 减脂 cut | TDEE − 500（可调 300-750） | 每周 0.5-1.0 kg | NIH/NHLBI 临床指南 |
| 增肌 bulk | TDEE + 250（可调 200-500） | 每周增重 ≤0.25-0.5% 体重 | Iraki et al. 2019 共识 |
| 维持 maintain | TDEE | 0 | - |

**硬性安全约束**：
- 每日热量硬下限：女性 ≥ 1200 kcal，男性 ≥ 1500 kcal（中国国家卫健委指南）
- 每周减重 ≤ 1% 体重（AHA 标准），超出弹出风险警告（胆结石、肌肉流失、代谢适应）
- 增肌盈余 > 500 kcal/天时警告"主要增长脂肪而非肌肉"

### 5.4 宏量营养素分配

| 目标 | 蛋白质 (g/kg) | 脂肪 (g/kg) | 碳水 | 依据 |
|---|---|---|---|---|
| 减脂 cut | 2.3-2.6（默认 2.4） | 0.8-1.0（默认 0.9） | 填剩余热量 | ISSN 2017 立场声明（减脂期 2.3-3.1 保肌） |
| 增肌 bulk | 1.6-2.2（默认 1.8） | 0.8-1.2（默认 1.0） | 4-7 g/kg | Morton 2018 BJSM 荟萃（1.6 g/kg 后趋平台，95% CI 上限 2.2） |
| 维持 maintain | 1.2-1.6（默认 1.4） | 0.8-1.0 | 填剩余热量 | 2025-2030 美国膳食指南 |

**关于蛋白质区间说明**：减脂 2.3-3.1 g/kg 是 ISSN 2017 完整科研区间（3.1 适用于极瘦人群+大赤字），表格默认 2.3-2.6 是覆盖大多数普通用户的实用区间。

**脂肪硬下限**：不低于总能量 20%（保护激素与脂溶性维生素吸收）。

**碳水计算说明**：减脂/维持场景碳水=（目标热量−蛋白热量−脂肪热量）/4，被动填剩余；增肌场景碳水主动设 4-7 g/kg 目标保训练表现，再反推总热量是否匹配。

**酒精**：纯酒精 7 kcal/g，单列"酒精热量"字段，不计入三大宏量，避免误导。

### 5.5 实际速率校准（自适应）

**判定条件**（需同时满足，避免单次称重波动误触发）：
- 观察窗口 ≥ 4 周（≥5 个体重点，统计意义充分）
- 实际体重变化速率与公式预测速率偏差 > 0.3 kg/周（4 周累计偏差 > 1.2 kg）
- 排除异常点：单次体重与前次差 > 2 kg 视为称重异常，标记不参与计算

**微调动作**：
- 自动微调 TDEE 基线（实测优于公式），微调值存入 `profile.tdee_adjustment_kcal`（默认 0，见 4.2.1），累加生效于 daily_calorie_target 计算
- 单次微调幅度上限 ±100 kcal，避免激进调整
- 微调后通知用户"已根据近 4 周实测调整每日目标 X kcal"

**手动覆盖**：用户可在档案页关闭自适应校准，或手动重置 tdee_adjustment_kcal 为 0

### 5.6 显示规范

- UI 显示"估算值 ± 区间"（Mifflin 误差约 ±10-15%），不伪装精确
- 宏量同时展示 g/kg 与克数两种表达
- 标注依据来源（如"依据 ISSN 2017 立场"），增强可追溯性

---

## 6. 食物数据库策略

### 6.1 关键澄清：数据集是"食材库"而非"菜品库"

**重要发现**：Sanotsu/china-food-composition-data 数据集经实际验证，**只含食材（1677 条：鸡肉/大米/奶酪等），不含中式菜品**（无番茄炒蛋、宫保鸡丁等成菜）。原设计的"菜名查库"仅对单品有效，复合菜必须依赖模型拆解组分后逐项查食材库累加。

这直接影响准确度：
- **单品**（苹果/鸡蛋/牛奶）：菜名→查食材库，误差约 ±3-5%
- **复合菜**（宫保鸡丁/番茄炒蛋）：模型拆组分→逐项查库累加，误差取决于组分拆解准确度，约 ±10-15%（仍优于纯图像估算 ±20%）

### 6.2 三层数据源架构

| 层 | 数据源 | 用途 | 许可证 | MVP 接入 |
|---|---|---|---|---|
| L1 食材 | 《中国食物成分表》第6版（Sanotsu/china-food-composition-data JSON） | 中式食材、地方食材营养基座 | **无 LICENSE（默认 All Rights Reserved）**，源自正式出版物 | ✅ 个人自用测试可导入 |
| L2 原料补充 | USDA FoodData Central | 原始食材精确营养素（70+ 营养素），补 L1 缺失项 | CC0 公共领域，可商用 | ✅ |
| L3 包装 | OpenFoodFacts（条码扫描） | 超市包装食品 | ODbL（开放数据库许可） | ⏸ 后续迭代 |
| L4 菜品 | （暂无开源中文菜品库） | 中式成菜标准份量 | - | ❌ 缺数据源 |

**版权风险声明**：L1 数据集无 LICENSE，源自《中国食物成分表标准版第6版》（北京大学医学出版社正式出版物），原作者亦声明"版权归原出版方"。
- **个人自用、不分发**：可导入作为测试种子数据，风险低
- **商用或公开分发**：必须取得原版权方授权，或改用 USDA FoodData Central（CC0，可商用）作为唯一数据源
- 本 MVP 明确为个人自用，使用 L1 作为食材库种子；若未来转为产品，需重新评估数据源

### 6.3 营养查询路径（分类型）

**核心原则**：营养数据来自食材库，而非模型直接吐数字。模型只负责"识别菜名 + 拆解食材组分 + 估份量"。

```
识别结果分两类处理：
├─ 单品（is_single_item=true，如苹果/鸡蛋/牛奶）
│   → 用 dish_name 查食材库（按 name OR aliases_json 匹配，解决"西红柿/番茄"等同物异名问题）
│   → 命中：热量密度(kcal/100g) × 用户校准份量
│   └─ 未命中：手动改菜名→重查→仍无则手动录入
└─ 复合菜（is_single_item=false，如宫保鸡丁/番茄炒蛋）
    → 按模型返回的 food_components[] 逐项查食材库（同样按 name OR aliases 匹配）
    → 命中项：累加 (组分热量密度 × 组分估量 / 100)
    → 加上用油系数 × 烹饪方式（见 3.1 烹饪用油系数表）
    └─ 未命中组分：标注"待确认"，用户手动改组分名或输入该组分热量
```

### 6.4 食材库导入与清洗规则

Sanotsu 数据集字段映射（验证自实际 JSON）：

| App 字段 | 数据集字段 | 单位 | 清洗规则 |
|---|---|---|---|
| name | foodName | - | 去除别名括号 `[干酪]`、`(代表值)` 后缀 |
| calories_per_100g | energyKCal | kcal/100g | 字符串转 double |
| protein_per_100g | protein | g/100g | 字符串转 double |
| fat_per_100g | fat | g/100g | 字符串转 double |
| carbs_per_100g | CHO | g/100g | 字符串转 double |
| edible_percent | edible | % | 可食部比例；MVP 校准页默认按用户输入的实际摄入克数计算，此字段供"带皮/带骨称重"场景可选换算（actual_intake_g = input_g × edible_percent / 100） |
| aliases_json | （人工补充） | - | 食材库不含别名，导入后人工补 20-30 组常见别名（番茄/西红柿、土豆/马铃薯、地瓜/红薯、猕猴桃/奇异果等）；写入 food_item.aliases_json |
| source | 固定 'china_fct' | - | - |
| source_version | 固定 'china_fct_v6_251206' | - | 取数据集目录名日期 |

**数据集所有字段值是字符串**（OCR 产物），导入时必须 `double.parse()` 并处理 `"—"`/`"Tr"`/空串等缺失值标记。

### 6.5 数据源优先级

冲突时优先级：中国食物成分表(L1) > USDA(L2) > OpenFoodFacts(L3)

每个营养数值保留 source + source_version 字段标注，便于溯源。

### 6.6 food_item 表去重与唯一性

- **去重键**：name + source（同名同源视为已存在，更新 default_serving_g；同名不同源视为不同条目）
- AI 识别入库的条目 source='ai_recognized'，与食材库条目（source='china_fct'）分开存储，避免污染权威数据
- 用户手动录入条目 source='manual'
- **复合菜名称归一化**：AI 识别菜名可能略有差异（如"宫保鸡丁" vs "宫爆鸡丁"），入库前做名称归一化（去空格、统一用字映射表）；归一化后仍不确定时提供"合并到已有条目"UI，避免食物库膨胀

---

## 7. 功能模块

### 7.1 个人档案模块

- 输入：身高、体重、年龄、性别、活动量、目标、目标速率、体脂率（可选）
- 输出：BMR、TDEE、每日热量目标、三大宏量目标
- 公式选择逻辑：无体脂率默认 Mifflin；有体脂率可选 Katch-McArdle
- 安全约束校验（见 5.3）

### 7.2 拍照识别模块

见第 3 节核心数据流。

### 7.3 今日记录模块

- 按餐次分组（早/午/晚/加餐）展示，加餐多条按时间戳排序
- 每条记录可编辑份量、删除
- 拍照识别记录显示原图缩略图 + 置信度标识
- 拍照识别记录提供"识别准/不准"反馈入口（左滑或长按），不准时让用户标注正确菜名+份量，写入 recognition_feedback 表（见 4.2.7），用于 prompt 改进

### 7.4 今日额度看板

- 环形进度条：已摄入 / 目标热量
- 三大宏量进度条：蛋白质 / 脂肪 / 碳水（已摄入 / 目标）
- 余额预警：剩余热量 < 0 时红色提示
- 显示估算区间（±10-15%）

### 7.5 食物库模块

- 常吃食物列表（按使用频率排序）
- 搜索（按名称）
- 复用：点击直接加入今日记录（免重复调 API）
- 编辑默认份量
- 标注数据来源（中国食物成分表/USDA/手动/AI识别）

### 7.6 手动录入模块（兜底）

- 搜本地食物库 → 选份量 → 加入记录
- 查不到：自定义输入 名称 + 热量 + 蛋白/脂肪/碳水 → 存入食物库 → 加入记录

### 7.7 体重记录模块

- 记录体重（日期 + 体重）
- 趋势图（fl_chart 折线图）
- 与热量摄入趋势对比展示

### 7.8 长期趋势 + AI 汇总模块

- 周视图：7 天热量折线图 + 平均摄入 + 与目标差距 + 体重趋势
- 月视图：30 天热量折线图 + 周环比 + 体重趋势
- AI 汇总建议：
  - 调 GLM-4-Flash（免费文本模型）
  - 传入近 7 天每日总热量 + 三大宏量 + 体重变化 + 目标
  - 返回中文阶段性建议（限 300 字）
  - 生成结果存入 insight_summary 表（见 4.2.6），避免重复调用烧 token
  - 用户可手动编辑建议文本（is_edited=1），编辑后"重新生成"需二次确认
  - 离线时不生成，联网后按需生成

---

## 8. 安全与隐私

### 8.1 数据库加密

- drift ≥ 2.32 + sqlite3mc（SQLite3MultipleCiphers），AES-256 加密
- 密钥首次启动随机生成 32 字节，存 flutter_secure_storage
- iOS 底层 Keychain（可结合 Secure Enclave）
- Android 底层 Keystore（可走 TrustZone/StrongBox）

### 8.2 API key 安全

- **绝不硬编码**到 Dart 代码或 pubspec.yaml
- 存 flutter_secure_storage
- iOS 设置 `KeychainAccessibility.first_unlock_this_device`（`ThisDeviceOnly` 后缀本身即禁止 iCloud Keychain 同步与备份恢复），并显式设置 `IOSOptions(synchronizable: false)` 双重保险
- Android 关闭 `android:allowBackup`（防 ADB 备份泄露）
- 厂商控制台设置月度费用上限（防 key 泄露被刷爆）
- 检测 401/403 集中报错时提示"key 可能已失效"
- 上线前用 `flutter build --obfuscate --split-debug-info` 代码混淆

### 8.3 图片隐私预处理（强制）

上传大模型 API 前必须经 flutter_image_compress 本地处理（keepExif 默认 false 即剥离 EXIF；image_picker 未契约化保证 EXIF 保留，故不依赖其副作用）：
- EXIF/XMP/IPTC 元数据默认被剥离（keepExif 默认 false，含 GPS、设备序列号、时间戳）
- autoCorrectionAngle 校正方向（剥离 EXIF 后横拍照片方向可能错乱）
- 压缩到最大边 1024px、JPEG 质量 85%（省 token + 降泄露信息量）
- 用户可在 App 内裁剪框选食物主体后再上传（减少背景泄露）

### 8.4 隐私告知

- App 内置简洁隐私政策：明确数据存储位置（本地）、图片传第三方大模型厂商（披露厂商及链接）、用户删除权
- 免责声明：计算值为估算，非医疗诊断；孕产妇、慢病患者、青少年需医生指导

### 8.5 权限声明

- iOS：Info.plist 添加 NSPhotoLibraryUsageDescription、NSCameraUsageDescription
- Android 13+：用 READ_MEDIA_IMAGES 而非 READ_EXTERNAL_STORAGE
- 注：MVP 不申请通知权限；若未来加入饮食提醒（非目标，后期迭代），Android 13+ 需补 POST_NOTIFICATIONS，iOS 需补 UserNotifications 权限申请逻辑

---

## 9. 备份与迁移

### 9.1 JSON 导出/导入

- 导出：含 schemaVersion 字段的 JSON 包（profile + food_items + meal_logs + weight_logs + insight_summaries + recognition_feedbacks）；pending_recognition 为临时队列不导出
- 导出文件可选 AES 加密（密钥从 secure_storage 取）
- 导入：走 drift 迁移链，老版本数据自动升级到当前 schema
- 用户可放任意云盘/iCloud Drive 自行托管

### 9.2 图片存储

- 图片存 `getApplicationDocumentsDirectory()`（系统备份机制覆盖）
- 导出 JSON 不含图片原图（体积过大），仅含路径引用

### 9.3 换机流程

1. 旧机：导出 JSON → 放云盘
2. 新机：装 App → 导入 JSON → 数据恢复
3. 图片处理：图片不迁移，导入时检测 `meal_log.original_image_path` 与 `food_item.thumbnail_path` 对应文件是否存在；不存在则置空并标记失效，UI 显示"原图未迁移"占位符，避免死链 404

### 9.4 图片存储清理

**问题**：每张原图 1024px JPEG 85% 约 200-500KB，每天 3-5 张，半年累积 ~300MB，一年 ~600MB，会吃满手机存储。

**清理策略**：
- 默认保留近 30 天原图，更早的 `meal_log.original_image_path` 自动删除（仅保留 `food_item.thumbnail_path` 128px 缩略图用于历史记录展示）
- 用户可在设置里选保留期：7 天 / 30 天（默认）/ 永久保留
- 触发时机：复用 workmanager 后台任务，每周执行一次清理；App 启动时若发现待清理项 > 50 个则前台异步清理
- 清理前校验：仅删除 `original_image_path`，不删 `food_item.thumbnail_path`；不删 `pending_recognition.image_path`（未识别完的不能删）

### 9.5 自动备份

**问题**：手动导出易忘，换机/丢机时数据全没。

**策略**：
- 每周日凌晨（用户设备本地时区）由 workmanager 后台任务自动导出 JSON 到 `getApplicationDocumentsDirectory()/backups/`，文件名 `eatwise_backup_YYYYMMDD.json`（可选 AES 加密）
- 保留最近 4 份，更早的自动删除
- 可选：用户在设置里指定一个额外复制目录（如 iCloud Drive / Google Drive 在本地的映射路径），导出后复制一份过去
- 设置页显示"上次自动备份时间"，超过 14 天未成功备份则看板提示

---

## 10. 离线支持

### 10.1 离线识别队列

- 拍照时用户已选 meal_type + date，连同 image_path 写入 pending_recognition 表（status=pending）
- **前台触发**：connectivity_plus 监听网络恢复（仅 App 在前台时可靠，Android 8.0 (API 26)+ 后台执行限制；Android 7 仅限制 manifest 注册的 CONNECTIVITY_ACTION 广播，动态注册仍可收到）
- **后台兜底**：workmanager 配置 Constraints(networkType: NetworkType.CONNECTED)，系统在网络恢复时调度任务执行回补（非实时，由系统决定时机）；iOS 默认用 Background Fetch (BGAppRefreshTask)，长任务可显式注册 BGProcessingTask（需在 AppDelegate 注册并声明 BGTaskSchedulerPermittedIdentifiers）
- 联网后按 FIFO 批量调用识别 API
- UI 上对 pending 项显示"待识别"角标
- 识别完成自动转"已完成"，用 pending 表里的 meal_type + date 写入 meal_log

### 10.2 失败重试

- 重试上限 3 次
- 超过 3 次标 status=failed
- UI 提示用户可手动重试或删除

### 10.3 本地读取

- 所有 UI 永远读本地 drift（~1ms）
- 仅拍照识别和 AI 汇总需联网

---

## 11. 错误处理与成本控制

### 11.1 大模型错误分类处理

| 错误类型 | 处理 |
|---|---|
| malformed output | 带错误信息修复后重发 |
| refusal（内容安全过滤） | 不重试（重试就是付费再听一次"no"） |
| timeout | jitter 退避重试 1 次 → 降级 |
| rate limit 429 | 尊重 Retry-After 头 |
| 连续 3 次失败 | 断路器短路 30s |

### 11.2 结构化输出保障

- 采用 `response_format={"type":"json_object"}` 强制合法 JSON 语法（**不使用 function calling**——Qwen-VL 的 function calling 不支持 `tool_choice="required"`，schema 仅为建议非强制，见 2.3 节说明）
- system prompt 写明完整 schema 描述 + 1-2 个 few-shot 示例
- schema 扁平（嵌套 ≤ 3 层）
- 下游做 JSON schema 校验，字段缺失时触发重试或转手动录入，拒绝不合法响应
- **Prompt 版本管理**：prompts.dart 文件头注释标注版本号（如 `// prompt v1.2 - 2026-07-15`），每次调用识别 API 时把 prompt_version 写入 pending_recognition 表；准确率退化时可按版本号追溯是哪次改动引入

### 11.3 成本控制

- 图片压缩到 1024px（控 token）
- 月度费用上限：厂商控制台 + App 内显示"本月识别次数/累计花费"
- 超阈值提示用户
- 本地限流：每分钟最多 2 次识别（防误触连点烧 token；Qwen-VL 免费额度 90 天 100 万 token，正常日均 3-5 次足够）

### 11.4 错误监控（Sentry）

- 接入 sentry_flutter ^9.22，自动捕获 Flutter 错误（FlutterError.onError）、Dart 未处理异常（runZonedGuarded）、Native 崩溃（Android Java/C、iOS Obj-C）
- 免费层 5K errors/月够个人自用
- **脱敏规则**（关键，避免业务数据上报）：
  - 启用 Sentry 服务端默认 Data Scrubbing
  - 客户端 `beforeSend` 钩子剥离业务字段：食物名、份量、体重、热量、API key、图片路径
  - 仅保留异常类型、堆栈、设备型号、App 版本
- DSN 存 flutter_secure_storage（不入库不入代码），用户可在设置里开关上报
- Release 版本用 `flutter build --split-debug-info` 产物配合 Sentry symbols 解符号

---

## 12. 测试策略

### 12.1 单元测试

- 营养计算公式（BMR/TDEE/宏量分配，覆盖 cut/bulk/maintain 三场景 + 男/女 + 有/无体脂率）
- 食物库查询与复合菜组分累加
- JSON 导出/导入序列化
- 大模型 JSON 解析容错（malformed/refusal/字段缺失）

### 12.2 数据库测试

- drift schema 迁移测试：用 `dart run drift_dev make-migrations` 生成 step-by-step 迁移文件 + 快照 + 测试代码；运行时用 `validateDatabaseSchema()`（drift_dev 2.34+ VerifySelf 扩展，包在 `if (kDebugMode)` 的 `beforeOpen` 回调里）校验 schema 一致性；单元测试用 `SchemaVerifier.migrateAndValidate()` 验证 onUpgrade 迁移结果（导入 `package:drift_dev/api/migrations_native.dart`）
- 加密数据库读写
- 每次发布前跑迁移测试

### 12.3 集成测试

- 拍照 → 校准 → 记录 → 看板更新的端到端流程
- 离线队列回补流程
- 失败降级流程（主模型失败 → 备模型 → 手动录入）

### 12.4 Prompt 回归测试

- 静态回归集：收集 50-100 张真实食物照片作为基线
- 动态回归集：从 recognition_feedback 表导出用户实际遇到的错判样本（见 4.2.7），比静态集更有价值，持续积累
- 每次 prompt 调整后跑一遍看准确率是否退化，按 prompt_version 对比（见 11.2）
- 覆盖：单品（苹果）、家常菜（番茄炒蛋）、复合菜（宫保鸡丁）、餐厅菜、包装食品

### 12.5 CI（GitHub Actions）

- 触发：push 到 main / 任意 PR
- 作业：
  1. `flutter analyze`（0 error 才通过，warning 允许）
  2. `flutter test`（单元测试 + drift schema 迁移测试必跑）
  3. `dart run build_runner build`（drift 代码生成一致性校验，确保提交的生成产物与 schema 同步）
- 失败阻止 PR 合并
- 不跑集成测试（需模拟器，CI 成本高），集成测试本地跑

---

## 13. 开发计划范围

本设计文档涵盖 MVP 全部功能，按风险优先分 3 个 Sprint 实施（每 Sprint 产出可独立验证的成果）：

**Sprint 1（验证最大风险：Qwen-VL 中文菜品识别 + JSON 稳定性）**
1. 项目脚手架（Flutter 初始化 + 依赖配置 + 目录结构）
2. 数据层（drift 2.32+ + sqlite3mc 加密 + 7 张表 + 迁移 + food_item 唯一约束）
3. 营养计算模块（BMR/TDEE/宏量公式 + 单元测试，覆盖 cut/bulk/maintain × 男女 × 有无体脂率）
4. 本地食材库导入（Sanotsu JSON → 字段映射 + 类型转换 + 缺失值清洗 + 别名补充，按 6.4 规则）
5. 拍照识别模块（flutter_image_compress 预处理 + Qwen-VL 调用 response_format=json_object + few-shot + GLM-4V-Plus 容灾 + prompt_version 记录）
6. 营养查库层（单品查库 / 复合菜组分累加 + name OR aliases 匹配 + 烹饪用油系数表）
7. 校准页 UI（单品滑块 / 复合菜组分滑块 + 用油量滑块 + 置信度分级跳过）
→ 跑通"拍一个苹果能记录热量"即 Sprint 1 成功

**Sprint 2（完整记录闭环 + 数据沉淀）**
8. 今日记录 + 看板 + 识别反馈入口（recognition_feedback 表）
9. 食物库模块（含 name+source 去重 + 别名查询）
10. 手动录入（兜底）
11. 体重记录 + 趋势图
12. AI 汇总建议（GLM-4-Flash + insight_summary 表存储）
13. JSON 导出/导入（含 schemaVersion 走 drift 迁移链）
14. 离线队列（pending_recognition 表 + connectivity_plus 前台触发 + workmanager 后台触发）

**Sprint 3（健壮性 + 工程化）**
15. 安全配置（加密 + 权限声明 + 隐私政策 + API key 厂商费用上限）
16. 存储与备份（图片清理 9.4 + 自动备份 9.5）
17. 错误监控（Sentry 接入 + 脱敏 11.4）
18. CI（GitHub Actions 12.5）

---

## 14. 参考依据

### 14.1 营养标准

- Mifflin-St Jeor 公式：Frankenfield 2005 J Am Diet Assoc 系统综述（AND 官方推荐）
- 减脂赤字 500-1000 kcal/天减 0.5-1kg/周：NIH/NHLBI 临床指南、WHO、CDC、NHS、AHA、NICE、中国国家卫健委《成人肥胖食养指南(2024年版)》
- 蛋白质减脂 2.3-3.1 g/kg：ISSN 2017 立场声明（Jäger et al., J Int Soc Sports Nutr 2017）
- 蛋白质增肌 1.6-2.2 g/kg：Morton et al. 2018 BJSM 荡萃分析
- 增肌盈余 200-300 kcal：Iraki et al. 2019 共识

### 14.2 大模型选型

- Qwen-VL：阿里云百炼，中文食物识别实测案例多，JSON 原生支持，0.15/1.5 元每百万 token
- GLM-4V-Plus：智谱 AI，新用户送 2000 万 token（20 million tokens 体验包），作容灾

### 14.3 开源参考

- OpenNutriTracker（Flutter，GPL-3.0）：数据模型 + AES 加密架构参考
- Sanotsu/china-food-composition-data：《中国食物成分表》第6版 JSON
- openfoodfacts-dart（Apache-2.0）：包装食品条码扫码 SDK（MVP 不接入，L3 后续迭代时使用，此处仅作选型参考）
- DietVision（MIT）：双拍照+参照物的体积估算方案参考

### 14.4 准确性依据

- 纯图像估算法对复合菜误差 15-20%；菜名查库法误差 3-5%（Nutrient Metrics 2026 独立测试）
- 大模型估份量 MAPE 约 36-37%（Performance Evaluation of 3 LLMs, PMC12513282）
- 两步推理（识别+查库）优于一步直接问（CVPR 2025 W）
