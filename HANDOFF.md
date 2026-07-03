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

**工作区状态**：clean（食物热量计算优化第一波已提交，未发布 release，等用户确认）
**最近 commit**：
- `47fd22c` feat: 食物热量计算优化第一波——可食部分系数+组分份量交叉验证+液体密度换算（建议1+3+7）
- `c2510cb` feat: 识别智能化——图片预检+字段校验+营养素自洽+包装容量优先+反馈闭环（批次 1-3）
- `50d4cac` fix: 第四轮深度审查修复——主题色绿/常用食物无名/原图丢失/复合菜滑块/防重入
- `baba3e1` feat: 项目分析与建议（prompt v1.5 + 反馈卡死修复 + 转手动入口）

**已发布**：
- v0.10.0 已发布（2026-07-03，第二次 release 成功，APK 已上传）
- 识别智能化批次 1-3 **未发布**（用户要求先告知，不发布 release）

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

**验证**：flutter analyze No issues + flutter test 302 passed/3 skipped/0 failed

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

**未完成/待办**（按优先级）：
1. ⬜ 用户验收测试（真机装 APK 验证第一波优化效果，等用户确认后发布 release）
2. 🔧 第二波（待用户确认后启动）：建议 2（强制路径顺序：库命中→AI 整菜估算→OFF 云查→AI 兜底）+ 建议 4（餐前/餐后双拍对比 DietDelta 思路）
3. 🔧 第三波（待用户确认后启动）：建议 6（接入 USDA FoodData Central API 替代部分 OFF 云查，免费但需 API key）
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
- 三件套叠加顺序：识别 → 密度换算（ml→g）→ 字段校验 → 组分交叉验证（mid 缩放）→ 查库反算（×edibleFactor）

### 3.6 主题色
- themeSeedProvider（NotifierProvider<int>）+ secure_config_store 持久化
- 默认莫奈《睡莲》青绿 0xFF5B8C7B，12 色预设 kThemePresets
- main.dart runApp 前快速读，首帧即用正确主题色避免闪烁

### 3.7 启动流程（main.dart）
- runZonedGuarded 包整个 main
- 单一 ProviderContainer（UI 与初始化共用，不 dispose）
- themeSeed 快速读 → initSentryAndRunApp（appConfig 失败降级跳过 Sentry）→ runApp
- UI 起来后异步：appConfig / Workmanager / OfflineQueue（fire-and-forget）/ ImageCleanup（读用户保留期）

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
