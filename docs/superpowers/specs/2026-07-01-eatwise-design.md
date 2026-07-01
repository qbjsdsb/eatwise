# EatWise 设计文档

> 项目代号：EatWise
> 形态：Flutter 跨平台 App（iOS + Android）
> 定位：个人自用的拍照识别食物热量 + 营养记录 + AI 周/月汇总建议工具
> 日期：2026-07-01
> 状态：已确认（待编写实现计划）

---

## 1. 项目概述

### 1.1 解决的问题

现有卡路里记录 App（薄荷健康、MyFitnessPal、Yazio）存在三个共同缺陷：
1. 食物拍照识别能力弱，主要靠手动搜索
2. 记录与"我的长期减脂/增肌计划"联动差，只显示今日热量
3. 缺少基于个人近期数据的阶段性 AI 建议

EatWise 通过「拍照识别 → 份量校准 → 营养计算 → 长期趋势 → AI 汇总建议」闭环解决上述问题。

### 1.2 核心价值主张

- 拍一张食物照片即可记录，模型识别菜名+估份量，营养数据来自权威食物库而非模型直出（准确度从 ±20% 提升到 ±5%）
- 基于身高/体重/目标自动计算每日热量与宏量营养素目标（公式依据 ACSM/ISSN/NIH/WHO 权威标准）
- 周/月趋势图 + AI 阶段性建议（依据近 7 天数据生成中文建议）
- 数据本地 AES 加密存储，可导出/导入 JSON 备份，换机不丢

### 1.3 非目标（YAGNI - 明确不做）

- 不做多用户/账号体系/云同步（个人自用）
- 不做社交/分享/排行榜
- 不做运动同步（Apple Health / Google Fit，依赖重）
- 不做推送提醒（MVP 不做）
- 不做详细维生素/矿物质雷达图（MVP 只追踪热量+三大宏量）
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
  └─ JSON 导出/导入                           ← 换机/备份
```

### 2.2 技术选型与依据

| 层 | 选型 | 依据 |
|---|---|---|
| 框架 | Flutter | UI 一致性高、双端一套代码、拍照/图表/本地数据库生态成熟 |
| 数据库 | drift ≥ 2.32 | pub.dev likes 2.23K，类型安全，响应式 Stream，全平台支持 |
| 数据库加密 | sqlite3 build hooks (source: sqlite3mc, SQLite3MultipleCiphers) | drift 2.32+ 官方现行推荐；sqlcipher_flutter_libs 已 EOL（0.7.0 起不再生效），故弃用 |
| 密钥存储 | flutter_secure_storage | iOS Keychain / Android Keystore 底层；32 字节密钥无大小限制；minSdk 23+ 保证 AndroidKeyStore 可用，无 StrongBox 时仍由 TrustZone/TEE 硬件保护 |
| 拍照 | image_picker | flutter.dev 官方一方包 |
| 图片预处理 | flutter_image_compress 2.4+ | 显式 keepExif:false 剥离 EXIF（image_picker 压缩丢 EXIF 是副作用非契约，不可依赖）；支持 autoCorrectionAngle 方向校正 |
| 图表 | fl_chart | Flutter 生态事实标准 |
| 网络状态(前台) | connectivity_plus | 前台实时 UI 反馈（离线 Banner、网络恢复立即同步当前会话） |
| 后台任务 | workmanager | 后台兜底回补；配置 Constraints(networkType: CONNECTED)；connectivity_plus 在 App 后台时无法可靠触发（Android 7+ 系统限制） |
| 视觉大模型 | Qwen-VL (qwen3-vl-flash 起步) | 中文食物识别实测案例多；兼容 OpenAI SDK；0.15/1.5 元每百万 token；90天100万 token 免费。注：function calling 无 tool_choice=required，不能强制 schema，改用 response_format=json_object + few-shot |
| 备选视觉模型 | GLM-4V-Plus | 新用户送 2500 万 token，免费额度最大，作容灾 |
| 文本大模型 | GLM-4-Flash | 完全免费，文本生成建议够用 |
| HTTP 客户端 | openai_dart | 纯 Dart、类型安全，显式支持 OpenAI-compatible APIs，baseUrl 指向百炼即可 |
| 离线队列 | drift pending_recognition 表 | 简单 FIFO，个人单端无需复杂冲突解决 |

### 2.3 大模型调用架构

```
拍照 → flutter_image_compress(keepExif:false + 压缩) → Vision API 调用
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

---

## 3. 核心数据流

### 3.1 拍照识别闭环（主流程）

```
1. 用户点"+"按钮 → 选择拍照或从相册选图
2. 本地预处理（flutter_image_compress）：
   - keepExif:false 显式剥离全部 EXIF/XMP/IPTC 元数据（隐私保护）
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
6. 校准页（强制，不可跳过）：
   - 默认填入 estimated_weight_g_mid（单品）或各组分 estimated_g（复合菜）
   - 单品：用户拖动滑块调整总份量（0-1000g），营养素实时重算
   - 复合菜：用户可调整各组分份量 + "用油量"滑块（默认取烹饪方式系数，可手动调）
   - 置信度 < 0.6 时标注"待确认"
7. 选餐次（早/午/晚/加餐）→ 写入 meal_log 表
8. 更新今日额度看板
9. 存入"我的食物库"（去重逻辑：按 name+source 查重，已存在则更新 default_serving_g）
```

**烹饪方式用油系数表**（默认值，用户可在校准页调整）：

| 烹饪方式 | 默认用油量(g/份) | 说明 |
|---|---|---|
| 蒸 | 0 | 无加油 |
| 煮 | 3 | 少量油 |
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
| carb_g_per_kg | REAL NULL | 碳水目标（g/kg 体重）；减脂/维持场景=剩余热量热量÷4÷体重（派生值，存缓存）；增肌场景用户设 4-7 |
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
| date | TEXT | 日期 'YYYY-MM-DD' |
| meal_type | TEXT | 'breakfast' / 'lunch' / 'dinner' / 'snack' |
| food_item_id | INTEGER FK | 关联 food_item |
| actual_serving_g | REAL | 实际份量（克） |
| actual_calories | REAL | 实际热量（计算值） |
| actual_protein_g | REAL | 实际蛋白质 |
| actual_fat_g | REAL | 实际脂肪 |
| actual_carbs_g | REAL | 实际碳水 |
| original_image_path | TEXT NULL | 原图本地路径（仅拍照识别记录） |
| recognition_confidence | REAL NULL | 识别置信度（仅拍照记录） |
| logged_at | INTEGER | 记录时间戳 |

#### 4.2.4 weight_log（体重记录）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | 自增 |
| date | TEXT | 日期 'YYYY-MM-DD' |
| weight_kg | REAL | 体重 |

#### 4.2.5 pending_recognition（离线识别队列）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | 自增 |
| image_path | TEXT | 图片本地路径 |
| meal_type | TEXT | 用户拍照时选定的餐次 'breakfast'/'lunch'/'dinner'/'snack'，联网识别成功后写入 meal_log 时使用 |
| date | TEXT | 拍照日期 'YYYY-MM-DD'，识别回补后写入 meal_log 用此日期（避免跨日回补导致记录错位） |
| status | TEXT | 'pending' / 'done' / 'failed' |
| retry_count | INTEGER | 默认 0，上限 3 |
| result_food_item_id | INTEGER NULL FK | 识别成功后关联的 food_item |
| error_message | TEXT NULL | 失败原因（malformed/timeout/rate_limit/auth_fail），便于断路器分类处理 |
| created_at | INTEGER | 创建时间 |
| processed_at | INTEGER NULL | 识别完成时间 |

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

连续 2 周实际体重变化与公式预测偏差 > 0.5 kg/周时，自动微调 TDEE 基线（实测优于公式）。

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
│   → 用 dish_name 查食材库
│   → 命中：热量密度(kcal/100g) × 用户校准份量
│   └─ 未命中：手动改菜名→重查→仍无则手动录入
└─ 复合菜（is_single_item=false，如宫保鸡丁/番茄炒蛋）
    → 按模型返回的 food_components[] 逐项查食材库
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
| dietary_fiber_g | dietaryFiber | g/100g | `"—"`→null，`"Tr"`→0.05（微量） |
| edible_percent | edible | % | 用于可食部计算 |
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

- 按餐次分组（早/午/晚/加餐）展示
- 每条记录可编辑份量、删除
- 拍照识别记录显示原图缩略图 + 置信度标识

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
  - 离线时不生成，联网后再算

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
- iOS 设置 `KeychainAccessibility.first_unlock_this_device`（禁止 iCloud 同步）
- Android 关闭 `android:allowBackup`（防 ADB 备份泄露）
- 厂商控制台设置月度费用上限（防 key 泄露被刷爆）
- 检测 401/403 集中报错时提示"key 可能已失效"
- 上线前用 `flutter build --obfuscate --split-debug-info` 代码混淆

### 8.3 图片隐私预处理（强制）

上传大模型 API 前必须经 flutter_image_compress 本地处理（不可依赖 image_picker 压缩副作用）：
- keepExif:false 显式剥离全部 EXIF/XMP/IPTC 元数据（含 GPS、设备序列号、时间戳）
- autoCorrectionAngle 校正方向（剥离 EXIF 后横拍照片方向可能错乱）
- 压缩到最大边 1024px、JPEG 质量 85%（省 token + 降泄露信息量）
- 用户可在 App 内裁剪框选食物主体后再上传（减少背景泄露）

### 8.4 隐私告知

- App 内置简洁隐私政策：明确数据存储位置（本地）、图片传第三方大模型厂商（披露厂商及链接）、用户删除权
- 免责声明：计算值为估算，非医疗诊断；孕产妇、慢病患者、青少年需医生指导

### 8.5 权限声明

- iOS：Info.plist 添加 NSPhotoLibraryUsageDescription、NSCameraUsageDescription
- Android 13+：用 READ_MEDIA_IMAGES 而非 READ_EXTERNAL_STORAGE

---

## 9. 备份与迁移

### 9.1 JSON 导出/导入

- 导出：含 schemaVersion 字段的 JSON 包（profile + food_items + meal_logs + weight_logs）
- 导出文件可选 AES 加密（密钥从 secure_storage 取）
- 导入：走 drift 迁移链，老版本数据自动升级到当前 schema
- 用户可放任意云盘/iCloud Drive 自行托管

### 9.2 图片存储

- 图片存 `getApplicationDocumentsDirectory()`（系统备份机制覆盖）
- 导出 JSON 不含图片原图（体积过大），仅含路径引用

### 9.3 换机流程

1. 旧机：导出 JSON → 放云盘
2. 新机：装 App → 导入 JSON → 数据恢复（图片不迁移，记录保留路径引用）

---

## 10. 离线支持

### 10.1 离线识别队列

- 拍照时用户已选 meal_type + date，连同 image_path 写入 pending_recognition 表（status=pending）
- **前台触发**：connectivity_plus 监听网络恢复（仅 App 在前台时可靠，Android 7+ 后台被系统限制）
- **后台兜底**：workmanager 配置 Constraints(networkType: NetworkType.CONNECTED)，系统在网络恢复时调度任务执行回补（非实时，由系统决定时机，iOS 用 BGProcessingTask）
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

- 用 function calling / tool use 定义 analyze_food 工具
- schema 扁平（嵌套 ≤ 3 层）
- 下游做 JSON schema 校验，拒绝不合法响应

### 11.3 成本控制

- 图片压缩到 1024px（控 token）
- 月度费用上限：厂商控制台 + App 内显示"本月识别次数/累计花费"
- 超阈值提示用户
- 本地限流：每分钟最多 5 次识别

---

## 12. 测试策略

### 12.1 单元测试

- 营养计算公式（BMR/TDEE/宏量分配，覆盖 cut/bulk/maintain 三场景 + 男/女 + 有/无体脂率）
- 食物库查询与复合菜组分累加
- JSON 导出/导入序列化
- 大模型 JSON 解析容错（malformed/refusal/字段缺失）

### 12.2 数据库测试

- drift schema 迁移测试（`drift_dev make-migrations` + `verifySelf` schema diff）
- 加密数据库读写
- 每次发布前跑迁移测试

### 12.3 集成测试

- 拍照 → 校准 → 记录 → 看板更新的端到端流程
- 离线队列回补流程
- 失败降级流程（主模型失败 → 备模型 → 手动录入）

### 12.4 Prompt 回归测试

- 收集 50-100 张真实食物照片作为回归集
- 每次 prompt 调整后跑一遍看准确率是否退化
- 覆盖：单品（苹果）、家常菜（番茄炒蛋）、复合菜（宫保鸡丁）、餐厅菜、包装食品

---

## 13. 开发计划范围

本设计文档涵盖 MVP 全部功能，单个实现计划可覆盖：

1. 项目脚手架（Flutter 初始化 + 依赖配置 + 目录结构）
2. 数据层（drift 2.32+ + sqlite3mc 加密 + 5 张表 + 迁移 + food_item 唯一约束）
3. 营养计算模块（BMR/TDEE/宏量公式 + 单元测试，覆盖 cut/bulk/maintain × 男女 × 有无体脂率）
4. 本地食材库导入（Sanotsu JSON → 字段映射 + 类型转换 + 缺失值清洗，按 6.4 规则）
5. 拍照识别模块（flutter_image_compress 预处理 + Qwen-VL 调用 response_format=json_object + few-shot + GLM-4V-Plus 容灾）
6. 营养查库层（单品查库 / 复合菜组分累加 + 烹饪用油系数表）
7. 校准页 UI（单品滑块 / 复合菜组分滑块 + 用油量滑块）
8. 今日记录 + 看板
9. 食物库模块（含 name+source 去重）
10. 手动录入（兜底）
11. 体重记录 + 趋势图
12. AI 汇总建议（GLM-4-Flash）
13. JSON 导出/导入（含 schemaVersion 走 drift 迁移链）
14. 离线队列（pending_recognition 表 + connectivity_plus 前台触发 + workmanager 后台触发）
15. 安全配置（加密 + 权限声明 + 隐私政策 + API key 厂商费用上限）

---

## 14. 参考依据

### 14.1 营养标准

- Mifflin-St Jeor 公式：Frankenfield 2005 J Am Diet Assoc 系统综述（AND 官方推荐）
- 减脂赤字 500-1000 kcal/周减 0.5-1kg：NIH/NHLBI 临床指南、WHO、CDC、NHS、AHA、NICE、中国国家卫健委《成人肥胖食养指南(2024年版)》
- 蛋白质减脂 2.3-3.1 g/kg：ISSN 2017 立场声明（Jäger et al., J Int Soc Sports Nutr 2017）
- 蛋白质增肌 1.6-2.2 g/kg：Morton et al. 2018 BJSM 荡萃分析
- 增肌盈余 200-300 kcal：Iraki et al. 2019 共识

### 14.2 大模型选型

- Qwen-VL：阿里云百炼，中文食物识别实测案例多，JSON 原生支持，0.15/1.5 元每百万 token
- GLM-4V-Plus：智谱 AI，新用户送 2500 万 token，作容灾

### 14.3 开源参考

- OpenNutriTracker（Flutter，GPL-3.0）：数据模型 + AES 加密架构参考
- Sanotsu/china-food-composition-data：《中国食物成分表》第6版 JSON
- openfoodfacts-dart（Apache-2.0）：包装食品条码扫码 SDK
- DietVision（MIT）：双拍照+参照物的体积估算方案参考

### 14.4 准确性依据

- 纯图像估算法对复合菜误差 15-20%；菜名查库法误差 3-5%（Nutrient Metrics 2026 独立测试）
- 大模型估份量 MAPE 约 36-37%（Performance Evaluation of 3 LLMs, PMC12513282）
- 两步推理（识别+查库）优于一步直接问（CVPR 2025 W）
