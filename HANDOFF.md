# 项目交接文档（Handoff）

> **用途**：沙箱会话不持久化，每天 AI 会"失忆"。
> 本文档是跨会话记忆载体，每个会话开始时 AI 必读，结束前 AI 必更新。
> **维护规则**：每次会话有实质进展就更新，保持"任何新 AI 读完此文档就能无缝接手"。

---

## 0. 新会话开启指令（给 AI 看的）

```
你是接手这个项目的新 AI。请按以下顺序操作：
1. 读本文件全文（HANDOFF.md）了解项目状态与约定
2. 读 .trae/rules/ 下的项目规则（若有）
3. 跑 `git log --oneline -20` 看最近提交
4. 跑 `git status` 看工作区状态
5. 问用户"今天要继续做什么"——不要主动改代码
```

---

## 1. 项目速览

- **项目名**：慢慢吃（EatWise）—— 拍照识别食物热量 + 营养记录 + AI 汇总建议
- **技术栈**：Flutter 3.44.4 / Dart / Riverpod / drift (SQLite) / Material 3 Expressive
- **当前版本**：0.10.0+10（pubspec.yaml）
- **当前分支**：v0.10.0-m3-merge（基于 v0.8.0，叠加 HEAD 的 AI 估热+主题色+Sentry）
- **关键约束**：
  - `meal_log.food_item_id` 是非空外键，PRAGMA foreign_keys=ON，foodItemId=0 哨兵写库前必须替换为真实 id
  - `android/app/build.gradle.kts` 必须保持 `isMinifyEnabled=false` + `isShrinkResources=false`（否则 R8 剥掉 sentry/workmanager 反射类致启动崩溃）
  - AI 兜底（foodItemId=0）需在前台 recognize_page、multi_dish_page、后台 offline_queue_controller 三条路径全部覆盖

---

## 2. 当前状态（每次会话结束更新）

**最后更新**：2026-07-03

**工作区状态**：clean（v0.11.0 已发布；v0.11.0 之后又提交了 6 个修复/优化但**未发布**，等用户验收后再决定是否打 v0.11.1）
**最近 commit**：
- `84cc29a` feat: 个人档案特殊人群适配（孕期/哺乳/老年/青少年/糖尿病/肾病/素食，schema v1→v2，未发布）
- `c6a76be` feat: 折线图美化与智能推荐算法升级（Y 轴 interval 防重叠+渐变填充+触摸 tooltip+推荐四维评分，未发布）
- `685fc9e` docs: 更新 HANDOFF——记录启动与首屏性能优化
- `d1e5970` perf: 启动与首屏加载性能优化（secure_storage 并行+首屏查询并行+N+1→批量+splash 配色，未发布）
- `fbcbf1e` fix: 修复 tab 页 dialog 按钮点击黑屏（嵌套 Navigator 误 pop 页面，未发布）
- `b97eb89` style: 今日明细页卡片式重构（缩略图+营养素圆点+餐次小计，未发布）
- `1f1fad0` fix: 校准页加多份识别警告横幅（避免一罐被识别成两罐时记录双倍克数，未发布）
- `ec5d452` docs: 更新 HANDOFF——v0.11.0 已发布
- `58db4e3` chore: 版本号 bump 到 0.11.0+11 准备发布 v0.11.0
- `add3c42` docs: 更新 HANDOFF——主页刷新修复（profile/weight→RefreshBus→dashboard）
- `b167574` fix: 个人档案/体重页保存后通知主页刷新（profile/weight→RefreshBus→dashboard）
- `62dd475` refactor: 提取 RecognitionPostProcessor 修复三路径行为分叉（第二波 2.0+2.1）
- `47fd22c` feat: 食物热量计算优化第一波——可食部分系数+组分份量交叉验证+液体密度换算（建议1+3+7）

**已发布**：
- v0.11.0 已发布（2026-07-03，包含识别智能化+食物热量优化第一波+第二波+主页刷新修复，APK 已上传）
  - Release: https://github.com/qbjsb/eatwise/releases/tag/v0.11.0
  - app-release.apk 73.1 MB / app-debug.apk 167.5 MB
  - workflow run: https://github.com/qbjsb/eatwise/actions/runs/28658030594（success）
- v0.10.0 已发布（2026-07-03）

**未发布的六个修复（v0.11.0 之后）**：
1. **校准页多份识别警告**（`1f1fad0`）：用户反馈"一罐芬达显示两罐克数"。根因是 AI 偶发误判 quantity=2，校准页默认用 `estimatedWeightGMid`（已含 quantity 乘积）作初值，数量步进器在底部不显眼，用户未调整直接确认会写入双倍克数。修复方式：quantity>1 时在标题下方加 tertiaryContainer 警告横幅，提示用户检查数量。
2. **今日明细页卡片式重构**（`b97eb89`）：用户反馈"明细界面不够美观"。ListTile → Card 卡片布局：56x56 圆角缩略图、份量/热量 chip、三大宏量营养素彩色圆点、餐次分组带竖条+小计热量。纯 UI 层重构，不动写入逻辑。
3. **tab 页 dialog 按钮点击黑屏**（`fbcbf1e`）：用户反馈"识别准不准"的准/不准按钮、"关于"里的隐私政策按钮点击后黑屏，退出重进才恢复。根因：GoRouter 的 `StatefulShellRoute.indexedStack` 给每个 tab 配嵌套 Navigator，`showDialog` 默认 `useRootNavigator:true` 把 dialog push 到 root Navigator，但按钮 `Navigator.pop(context)` 用页面 context，`Navigator.of(context)` 找到 tab 嵌套 Navigator，把栈顶页面本身（MePage / RecordsTabPage）pop 掉了。修复 3 处（me_page._showPrivacy、today_meals_page._showEditDialog、today_meals_page._showFeedbackDialog 准/不准），统一改 `builder:(ctx)=>` + `Navigator.pop(ctx)`。**坑提醒：今后在 tab 页（dashboard/records/insight/me 分支下）写 dialog，关闭按钮必须用 dialog 的 ctx，不能用页面 context。**
4. **启动与首屏加载性能优化**（`d1e5970`）：用户反馈"点开软件要黑屏一两秒"。三个瓶颈：① main.dart 的 getThemeSeed 和 appConfig 两次独立 secure_storage 读取原串行，改提前触发 appConfigProvider 并行；② AppConfig.load() 原 10+ 次串行 platform channel read 改"同时启动 7 future + 分别 await"并行，并复用结果省 3 次重复 read；③ DashboardPage/TodayMealsPage 食物名反查 N+1 → FoodItemRepository.getByIds 批量 IN 查询，首屏三查询并行；④ Android launch_background 纯白底改 @color/splash_background 匹配 app 默认 surface 色（亮 #FCF9F9/暗 #1C1B1F）。**坑提醒：Future.wait 因多类型 future 会退化为 List<Object?>，并行不同类型 future 应用"同时启动 + 分别 await"模式保留类型。**
5. **折线图美化与智能推荐算法升级**（`c6a76be`）：用户反馈"折线图不够美观有数字重叠"+"智能推荐不够智能"。折线图：Y 轴固定 interval（热量 maxCal/4 取整 50 倍数 / 体重范围/4 至少 0.2）彻底消除重叠，参考线标签左对齐+padding(left:44) 避开 Y 轴 + 上下错开，边框只留左下，网格只水平虚线半透明，数据点变小+surface 描边，belowBarData 改 LinearGradient 渐变，加 lineTouchData 触摸 tooltip。推荐算法 v2：四维评分（相对缺口匹配 remaining/goal 比例取最缺宏量加权 / 历史频次 log2 压缩封顶 4 分 / 排除今日已吃 / 具体理由"补蛋白 32%"），新增 `MealLogRepository.getRecentFoodCounts`（最近 30 天引用次数）。**坑提醒：推荐算法蛋白缺口触发阈值用 hasProteinGap（remainingProtein>5）而非 ratio<0.3，无记录时 ratio=1.0 但仍应触发，否则高蛋白食物不被推荐（测试已覆盖）。**
6. **个人档案特殊人群适配**（`84cc29a`）：用户反馈"个人信息太简单，不能应用在不同人群"。profile 表 schema v1→v2 加 3 个 nullable 列（specialCondition/dietPreference/healthCondition，null 视为 'none' 向后兼容）。NutritionCalculator 按权威来源调整：孕期 +340 / 哺乳期 +500 kcal（IOM 2006）、老年蛋白 1.2g/kg 防肌少症（ISSN）、肾病蛋白 cap 0.8g/kg（KDOQI）、糖尿病碳水 cap 45%（ADA）。ProfilePage 加"特殊状况"段（3 个 DropdownMenu + 风险提示卡片）+ 活动量描述优化（步数/锻炼频率）+ 保存时孕期/哺乳/肾病减脂风险警告。JsonExporter/Importer 同步 3 字段导出导入；版本检查从严格相等放宽为只拒绝高于当前版本（支持旧备份恢复到新版本）。**坑提醒：JsonExporter 加新字段必须同步 JsonImporter 读取，否则备份恢复丢数据；DropdownMenu 测试用 find.byKey 定位，不要用 .last/.first（新增菜单会让索引漂移）。**
- 验证：`flutter analyze` No issues + `flutter test` 324 passed (3 skipped)。

**识别智能化批次 1-3 修复清单**（本次 commit，用户选择"全部融入"）：
- 批次 1 图片预检 + 字段校验：
  - 新建 `lib/core/util/recognition_validator.dart`——字段合理性校验（dishName/confidence/weight/区间）+ 营养素自洽校验（4p+9f+4c≈cal，±10%）
  - recognize_controller 集成校验：字段不合理→重试 1 次；营养素不自洽→自动用宏量营养素反推修正 calories
  - 修复 image_quality_checker.dart 类型错误（laplacianValues num→double）
  - 20 个校验器单元测试全过
- 批次 2 prompt v1.6 + 包装容量优先：
  - prompt v1.6：包装食品必须读取包装标签净含量（weight_source=package_label），不靠视觉估算
  - 营养素自洽约束：要求 AI 用 4p+9f+4c 反算 calories，偏差<5%
  - VisionRecognitionResult 新增 weightSource 字段 + fromJson 解析（向后兼容旧 prompt）
  - 示例 1-3 加 weight_source 字段 + 自洽性标注
- 批次 3 反馈闭环回流 aliasesJson：
  - FoodItemRepository 新增 addAlias 方法（事务包裹 + 归一化去重）
  - today_meals_page._showFeedbackDialog 加别名回流：用户纠正菜名后，把 AI 错误名作为正确菜的别名
  - 下次 AI 识别返回错误名时，findByNameOrAlias 命中别名，直接返回正确菜营养数据
  - 6 个 addAlias 单元测试全过

**验证**：flutter analyze No issues + flutter test 324 passed/3 skipped/0 failed

**食物热量计算优化第一波修复清单**（commit 47fd22c，等用户验收后发布 release）：
- 建议 1 ediblePercent 可食部分系数：
  - `nutrition_lookup.lookupSingleItem` 库命中分支 + `recognize_page._nutritionFromFoodItem` 反算点都加 `edibleFactor = (food.ediblePercent ?? 100).clamp(1,100) / 100`
  - `effectiveG = servingG * edibleFactor`，反算用真实可食克数（如香蕉 65%、带骨排骨 50%）
  - 复合菜 `lookupCompositeDish` 不乘（组分已是可食克数）
  - 6 个专项测试（香蕉/排骨/null/100%/0% clamp/复合菜不乘）全过
- 建议 7 复合菜组分份量交叉验证：
  - `RecognitionValidationResult` 新增 `correctedComponents` 字段
  - `sum(components.estimatedG)` 与 `estimatedWeightGMid` 偏差>15% 时按 mid 比例缩放
  - `recognize_controller._validateAndMaybeRetry` 主菜 + 附加菜两条路径都覆盖（在校验后、查库前）
  - 防除零（sumG=0/mid=0 不触发）+ 缩放后保留组分名
  - 8 个专项测试全过
- 建议 3 食物密度表 ml→g 换算：
  - 新建 `lib/ai/food_density.dart`——14 个类别密度表（油 0.92/蜂蜜 1.42/烈酒 0.79 等）+ `densityOf`/`isLiquidCategory` 辅助函数
  - prompt v1.7 新增 `food_category` 字段（water/carbonated/juice/milk/cream/oil/honey/sauce/alcohol/beer/wine/yogurt/soup/solid）
  - `VisionRecognitionResult` 新增 `foodCategory` 字段 + `copyWith` 扩展 + fromJson 解析（向后兼容默认 solid）
  - `recognize_controller._applyDensityConversion + _convertDensityForDish` 在校验前换算：仅对 `weight_source=package_label` + 液体类别换算，密度=1.0（水基）跳过
  - 换算公式：`realPerUnitG = perUnitG * density`，`realMid = realPerUnitG * quantity`，区间 ±3%
  - 20 个专项测试全过

**第二波修复清单**（commit 62dd475，三路径一致性 + 重试 bug 修复）：
- 提取 `lib/core/util/recognition_post_processor.dart`：
  - `process()` 完整链路：密度换算 → 字段校验 → 营养素自洽修正 → 组分份量交叉验证 → additionalDishes 修正
  - `applyDensityConversion` / `correctAdditionalDishes` 可单独调用
  - 纯静态方法，不持有状态，不依赖 provider/imageBase64
- 修复问题1（第一波盲区）：offline_queue_controller 后台回补完全没走校验链路
  - 包装液体未做 ml→g 密度换算（500ml 油 mid=500 而非 460）
  - 营养素不自洽未修正、组分份量不自洽未缩放
  - 导致前后台行为分叉：同张图不同网络条件下热量不一致
  - 修复：recognize 成功后调 `RecognitionPostProcessor.process(result)`
- 修复问题2（重试跳过换算 bug）：recognize_controller._validateAndMaybeRetry
  - 原代码重试成功后用未换算的 retryResult（油 500ml 重试后 mid 仍是 500 而非 460）
  - 修复：首次 + 重试结果都走 `RecognitionPostProcessor.process`
- controller 净减 98 行（4 个方法移到 PostProcessor，import + 简化调用）
- 17 个 PostProcessor 单元测试 + 1 个离线回补密度换算专项测试，全过
- 更新 1 个原有离线测试期望值（组分份量缩放后 actualServingG 180→250，新行为正确）

**主页刷新修复清单**（commit b167574，profile/weight 保存后通知 dashboard）：
- 问题：用户在 profile_page 录入体重身高年龄（重算 BMR/TDEE/目标）或在 weight_page 记录体重后，主页每日目标/宏量目标不更新
- 根因1：profile_page._save() pop 后没调 RefreshBus.notify()（dashboard 唯一刷新入口是 RefreshBus 监听）
- 根因2：weight_page._save() 只调本页 _load()，没调 RefreshBus.notify()
- 根因3：weight_page 只写 weight_logs 表，不同步 profile.weightKg（即使刷新，宏量目标 proteinGPerKg*weightKg 仍用旧体重）
- 修复：profile_page pop 后 + weight_page _save 末尾都加 RefreshBus.instance.notify()；weight_page insert 后同步 ProfileRepository.update(weightKg: weight)
- 设计决策：weight_page 不同步重算 dailyCalorieTarget（BMR 重算只在用户主动编辑档案时做，日常体重波动通过 TDEE 校准 adjustmentKcal 微调）
- 4 个 widget 测试全过（ProfilePage/WeightPage notify + weightKg 同步 + weight_logs 不影响）

**未完成/待办**（按优先级）：
1. ⬜ 用户真机验收 v0.11.0（装 APK 验证识别智能化+食物热量优化+主页刷新修复效果）
2. 🔧 第三波（待用户确认后启动）：建议 6（接入 USDA FoodData Central API 替代部分 OFF 云查，免费但需 API key）—— 但需先评估 OFF 中文命中率，USDA 是英文 API 中文菜名需翻译层
3. ⏸️ 建议 4 餐前/餐后双拍对比（DietDelta 思路）：用户明确暂不做
4. 🔧 重构性优化（风险较高，不阻塞当前版本）：
   - 路由方式统一（GoRouter vs Navigator.push 混用）
   - 版本号从 PackageInfo 读取（替代硬编码）
   - dashboard/today_meals N+1 查询优化（getByIds）
   - 测试覆盖增强：AI 兜底、foodItemId=0 哨兵 FK 约束、getThemeSeed 单元测试
   - Sentry appRunner 标准化 + FlutterError.onError 链式调用
   - 后台回补补 fallback provider + circuitBreaker + incrementMonthlyCount

---

## 3. 关键架构决策（不要轻易改）

### 3.1 AI 估热 + 本地库校验两层架构
- 库命中 → 用库值（NutritionSource.database）
- 库未命中 + AI 有 estimatedCalories → AI 兜底（foodItemId=0 哨兵，source=aiEstimate）
- 库未命中 + AI 无估算 → 走未命中弹窗转手动录入
- 复合菜组分全 miss → 转 AI 兜底走单品路径（v0.10.0 新增）

### 3.2 foodItemId=0 哨兵机制
- AI 兜底 NutritionResult.foodItemId=0（recognize_controller._aiFallbackNutrition）
- 写 meal_log 前必须调 upsertAiRecognized 创建真实 food_item 替换哨兵
- 三条路径已全部覆盖：recognize_page 单品、multi_dish_page 主菜+附加菜、offline_queue_controller

### 3.3 复合菜存储
- per100g=0 占位（实际热量在 meal_log.componentsSnapshotJson）
- nutrition_lookup.lookupSingleItem 过滤 componentsJson!=null 的记录（防 0 卡污染）
- listAllForRecommendation 排除 source='ai_recognized'

### 3.4 prompt 版本 v1.7
- v1.4：合并 v1.3（多菜多份 quantity/unit/perUnitG）+ v1.1（营养字段 estimated_calories 等）
- v1.6：包装容量优先（weight_source=package_label）+ 营养素自洽约束（4p+9f+4c≈cal，±5%）
- v1.7：新增 food_category 字段（water/carbonated/juice/milk/cream/oil/honey/sauce/alcohol/beer/wine/yogurt/soup/solid），用于包装液体 ml→g 密度换算
- 旧 prompt 响应无 food_category/weight_source 时默认 solid/ai_estimate（不换算、走视觉估算），向后兼容

### 3.5 per100g 反算 + 可食部分 + 密度换算三件套
- per100g 反算公式：`caloriesPer100g * effectiveG / 100`
- `effectiveG = servingG * edibleFactor`（建议 1）：edibleFactor 来自 FCT 数据 `ediblePercent` 字段（如香蕉 65%、带骨排骨 50%）
- 复合菜组分克数已是可食克数，不乘 edibleFactor
- 包装液体密度换算（建议 3）：`effectiveG = perUnitG * density * quantity`，仅 weight_source=package_label + 液体类别触发
- 三件套叠加顺序：识别 → **RecognitionPostProcessor.process**（密度换算→字段校验→营养素自洽→组分交叉验证→additionalDishes 修正）→ 查库反算（×edibleFactor）
- 第二波关键：三条路径（前台识别/重试/离线回补）都走 PostProcessor.process，行为一致

### 3.6 主题色
- themeSeedProvider（NotifierProvider<int>）+ secure_config_store 持久化
- 默认莫奈《睡莲》青绿 0xFF5B8C7B，12 色预设 kThemePresets
- main.dart runApp 前快速读，首帧即用正确主题色避免闪烁

### 3.7 启动流程（main.dart）
- runZonedGuarded 包整个 main
- 单一 ProviderContainer（UI 与初始化共用，不 dispose）
- themeSeed 快速读 → initSentryAndRunApp（appConfig 失败降级跳过 Sentry）→ runApp
- UI 起来后异步：appConfig / Workmanager / OfflineQueue（fire-and-forget）/ ImageCleanup（读用户保留期）

### 3.8 特殊人群营养适配（schema v2）
- profile 表加 3 个 nullable 列：specialCondition（生理状态）/dietPreference（饮食偏好）/healthCondition（健康状况）
- schema v1→v2 migration：`onUpgrade` 中 `m.addColumn` 加列，旧数据保持 null 视为 'none'（向后兼容）
- NutritionCalculator 调整权威来源：IOM 2006（孕期 +340 / 哺乳期 +500 kcal）、ISSN 老年蛋白 1.2g/kg、KDOQI 肾病蛋白 cap 0.8g/kg、ADA 糖尿病碳水 cap 45%
- 特殊人群调整在 goal 默认值之上覆盖：elderly 提蛋白（cut 不降）、kidney_issues 强制 cap、pregnancy/lactation 蛋白至少 1.1g/kg
- 能量加成在 deficit/surplus 之前加（避免减脂目标抵消孕期加成）
- JsonImporter 版本兼容：只拒绝高于当前的版本，允许旧备份导入（旧 JSON 缺新字段用 `as String?` 兜底 null）

---

## 4. 已知陷阱（踩过的坑）

1. **APK 打不开**：build.gradle.kts 丢失 R8 禁用配置 → native 启动崩溃。必须保持 `isMinifyEnabled=false` + `isShrinkResources=false`
2. **SecureConfigStore.instance 不存在**：v0.8.0 用 `SecureConfigStore()` 构造函数，没有静态 instance。main.dart 用 `container.read(secureConfigStoreProvider)`
3. **initSentryAndRunApp 参数名**：是 `container:` + `app:`（命名参数），不是位置参数
4. **multi_dish_page take(5) 截断**：附加菜超 5 道静默丢弃，当前未提示用户（待优化）
5. **滑块 max 与 perUnitG*20 边界**：perUnitG 极大/极小时滑块与步进器可能不同步（待优化）
6. **测试 mock 需补 getThemeSeed stub**：AppConfig.load() 新增了 getThemeSeed() 调用，mock SecureConfigStore 的测试必须 stub
7. **复合菜组分克数已是可食克数，不能再乘 ediblePercent**：`lookupCompositeDish` 反算时不要加 edibleFactor（与单品 `lookupSingleItem` 不同），否则双重缩放
8. **密度换算只对 weight_source=package_label + 液体类别触发**：散装菜（ai_estimate）即使 foodCategory=milk 也不换算（视觉估算已是克数）；水基（密度=1.0）跳过避免无谓重建
9. **三路径必须走 RecognitionPostProcessor.process**：前台识别（recognize_controller）、重试结果、离线回补（offline_queue_controller）三条路径的 recognize 结果都必须经过 PostProcessor.process，否则行为分叉（第二波修复的关键约束）。重试结果若跳过 process 会导致密度换算被跳过（油 500ml 重试后 mid 仍是 500 而非 460）
10. **profile/weight 页保存后必须调 RefreshBus.notify()**：dashboard 唯一刷新入口是 RefreshBus 监听（main_shell FAB 也用此机制）。profile_page._save 和 weight_page._save 末尾都必须 notify，否则主页每日目标/宏量目标不更新。weight_page 还需同步 profile.weightKg（否则宏量目标 proteinGPerKg*weightKg 仍用旧体重）
11. **dashboard 用裸 FutureBuilder+setState，无响应式 provider**：当前 dashboard 不 watch 任何 profile provider，完全靠 RefreshBus 触发 _refresh() 重查库。若未来新增其他修改 profile 的入口，也必须调 RefreshBus.notify()
12. **JsonExporter/Importer 新增字段必须同步**：profile 表加列后，JsonExporter._profileToJson 要导出新字段，JsonImporter._profileFromJson 要读取新字段（用 `as String?` 兼容旧 JSON 无此字段）。否则备份恢复丢数据。本次 schema v2 漏导出 3 个特殊人群字段，已补修复
13. **DropdownMenu 测试用 find.byKey 定位**：不要用 `find.byType(DropdownMenu<String>).last` 或 `.first`，因为新增菜单会让索引漂移。本次 profile_page 新增 3 个 DropdownMenu 导致 .last 从 goal 漂移到饮食偏好菜单，测试失效。修复：给 goal 菜单加 `key: const Key('goal_dropdown')`，测试用 `find.byKey`
14. **JsonImporter 版本检查只拒绝高于当前**：`if (schemaVersion > _db.schemaVersion)` 而非严格相等，允许旧版本备份导入新版本 DB（向后兼容，老用户升级后可恢复旧备份）。旧 JSON 缺新字段由 _profileFromJson 用 `as String?` 兜底为 null

---

## 5. 常用命令

```bash
# 环境（沙箱每次需重设 PATH）
export PATH=/tmp/flutter/bin:$PATH

# 验证
flutter analyze
flutter test
flutter test test/features/settings_backup_overdue_test.dart  # 单个测试

# 构建（fat APK 全架构）
flutter build apk --release --no-tree-shake-icons

# Git
git log --oneline -10
git status
git tag --list 'v*'
```

---

## 6. 文件地图（关键文件）

```
lib/
├── main.dart                          # 启动：zone+Sentry+themeSeed+异步初始化
├── app.dart                           # M3 主题 + 4-tab StatefulShellRoute 路由
├── main_shell.dart                    # 底部导航壳 + FAB
├── ai/
│   ├── prompts.dart                   # v1.4 prompt
│   ├── vision_provider.dart           # VisionRecognitionResult（含 copyWith）
│   ├── vision_service.dart            # 视觉服务
│   ├── nutrition_lookup.dart          # NutritionLookup + NutritionSource 枚举
│   └── off_provider.dart              # Open Food Facts 云查
├── core/
│   ├── config/
│   │   ├── app_config.dart            # AppConfig.load() + appConfigProvider
│   │   └── secure_config_store.dart   # secure_storage 封装（含 themeSeed）
│   ├── theme/theme_controller.dart    # themeSeedProvider + kThemePresets
│   ├── util/
│   │   ├── image_quality_checker.dart # 模糊图预检（批次 1）
│   │   ├── recognition_validator.dart # 字段合理性 + 营养素自洽 + 组分交叉验证
│   │   └── recognition_post_processor.dart # 三路径共用后处理（密度换算+校验修正，第二波）
│   └── error/
│       ├── sentry_init.dart           # initSentryAndRunApp（appConfig 失败降级）
│       └── sentry_scrub.dart          # Sentry 脱敏
├── data/
│   ├── database/database.dart         # drift，PRAGMA foreign_keys=ON
│   └── repositories/
│       ├── food_item_repository.dart  # upsertAiRecognized（更新含 componentsJson）
│       └── meal_log_repository.dart   # insertMealLog
└── features/
    ├── recognize/
    │   ├── recognize_controller.dart  # AI 兜底 + 复合菜全 miss 转 AI
    │   ├── recognize_page.dart        # 哨兵处理 + 改菜名 copyWith
    │   ├── calibration_page.dart      # 校准 + 数量步进器 + 徽章
    │   └── multi_dish_page.dart       # 多菜 _hitFlags 含 componentHits 判定
    ├── offline/offline_queue_controller.dart  # 离线回补 AI 兜底 + fire-and-forget
    ├── settings/settings_page.dart    # 主题色板 + _isSaving
    ├── profile/profile_page.dart      # _busy + try-catch
    ├── weight/weight_page.dart        # _busy + _load try-catch
    ├── food_library/                  # food_edit_page + food_library_page
    ├── manual_entry/manual_entry_page.dart
    ├── backup/backup_page.dart        # 导入二次确认
    ├── me/me_page.dart
    ├── records/records_tab_page.dart
    ├── dashboard/dashboard_page.dart
    └── insight/insight_page.dart
```

---

## 7. 会话结束前 AI 必做

1. 更新本文件第 2 节"当前状态"（日期、commit、工作区、未完成项）
2. 如有新陷阱，补到第 4 节
3. 如有新架构决策，补到第 3 节
4. 确认 `git status` clean（或明确记录未提交的改动原因）
