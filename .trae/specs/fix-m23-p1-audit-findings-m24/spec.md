# M24 修复 M23 审查 P1 发现 Spec

## Why

M23 全面细致审查（2026-07-05）已完成，发现 67 项问题（0 P0 / 13 P1 / 54 P2），6 条硬约束全部满足。本 spec 处理全部 13 项 P1，目标是"P1 清零"——修复错误态覆盖不完整、架构层次违反、长方法/超长文件、安全脱敏盲区四大方向，让代码健康度从 B+ 提升到 A-。

用户决策：全部 13 项 P1 在 M24 一次性修完，要求"严谨仔细，反复检查"。

## What Changes

### A. 快速修复（8 项，~2h）

- **A1 sentry_scrub.dart 补 event.tags 脱敏**（P1 #13，15 分钟）：注释承诺脱敏 tags 但代码漏处理，补 tags 脱敏逻辑（与 extra 同模式）
- **A2 dashboard _regenerateButton 触控目标 32→48dp**（P1 #6，5 分钟）：移除 minimumSize: Size(0, 32) + tapTargetSize: shrinkWrap
- **A3 update release notes 展开/收起**（P1 #5，15 分钟）：移除 maxLines:10 + overflow:ellipsis，改用 SingleChildScrollView + 展开/收起按钮
- **A4 food_library 搜索失败 toast**（P1 #3，15 分钟）：_doSearch catch 内补 showAppToast('搜索失败，请重试')
- **A5 备份导入弹窗补"离线队列 N 条将被清空"**（P1 #7，30 分钟）：backup_page _import 弹窗动态显示 pending_recognitions 条数
- **A6 insight 周/月切换 loading + AnimatedSwitcher**（P1 #1，30 分钟）：新增 _chartLoading 标志，切换时显示 LoadingState，AnimatedSwitcher 300ms 过渡
- **A7 food_library 加载失败 ErrorState**（P1 #2，30 分钟）：新增 _loadError 标志，catch 内置 true，UI 显示 ErrorState + 重试按钮
- **A8 profile 加载失败 ErrorState**（P1 #4，30 分钟）：新增 _loadError 标志，build 中显示 ErrorState + 重试按钮

### B. 架构重构（5 项，~13h）

- **B1 跨层依赖统一用 Repository Provider**（P1 #8，2h）：11 个 feature 文件移除 `import data/database/database.dart`，统一用 `recognize.foodItemRepoProvider` / `mealLogRepoProvider` / `profileRepoProvider` 等 Provider 注入；类型 import 改为从 repository 文件导出
- **B2 _pickAndRecognize 拆分**（P1 #11，2h）：recognize_page.dart L380-568 拆为 `_pickImage` / `_runRecognize` / `_showResultAndWaitConfirm` / `_writeMealLog` 四个子方法，主方法只做编排
- **B3 processPending 拆分**（P1 #12，3h）：offline_queue_controller.dart L97-493 拆为 `_processSingleItem(p)` / `_processComposite(p)` 两个子方法，主方法只做遍历和分发
- **B4 multi_dish_page 拆分**（P1 #9，4h）：986 行拆出 `_CalcNutritionWidget` / `_CompositeEditor` / `_AdditionalDishEditor` 等 widget，主文件聚焦编排
- **B5 dashboard_page 拆分**（P1 #10，4h）：948 行按 section 拆出 `_StatusCardSection` / `_RecommendationSection` / `_TodayMealsSection` 等 widget，主文件聚焦布局

### C. 验证

- **C1 flutter analyze 通过**：0 issues
- **C2 flutter test 全过**：现有 1010 测试 + 新增测试全过
- **C3 6 条硬约束仍满足**：build.gradle minify=false / meal_log.food_item_id 非空 FK / AI 三路径 / per100g 基于 mid / SecureConfigStore 无 instance / initSentryAndRunApp 命名参数
- **C4 pubspec.yaml 版本 bump**：0.21.0+33 → 0.22.0+34（minor bump 因架构重构）
- **C5 HANDOFF.md 更新**：M24 章节记录

## Impact

- **Affected code**:
  - `lib/core/error/sentry_scrub.dart`（A1）
  - `lib/features/dashboard/dashboard_page.dart`（A2 + B5）
  - `lib/features/update/update_page.dart`（A3）
  - `lib/features/food_library/food_library_page.dart`（A4 + A7）
  - `lib/features/backup/backup_page.dart`（A5）
  - `lib/features/insight/insight_page.dart`（A6）
  - `lib/features/profile/profile_page.dart`（A8）
  - 11 个 feature 文件（B1 跨层依赖）
  - `lib/features/recognize/recognize_page.dart`（B2）
  - `lib/features/offline/offline_queue_controller.dart`（B3）
  - `lib/features/recognize/multi_dish_page.dart`（B4）
  - 新增 widget 文件（B4/B5 拆分产物）
- **Affected tests**: 新增/更新对应测试
- **Affected docs**: HANDOFF.md M24 章节
- **影响范围**: 架构重构（B1-B5）改动面大，需严格 TDD + 逐项验证 + 回归测试

## ADDED Requirements

### Requirement: A1 sentry_scrub.dart 补 event.tags 脱敏

#### Scenario: event.tags 含敏感 key 时脱敏
- **WHEN** Sentry 事件含 `event.tags = {'api_key': 'sk-xxx', 'food_name': 'rice'}` 且 key/value 命中 `_isSensitiveKey` 关键词
- **THEN** scrubBeforeSend 应删除对应 tag entry，与 event.extra 脱敏行为一致

#### Scenario: event.tags 无敏感 key 时保留
- **WHEN** event.tags 含 `{'os_version': '14', 'device': 'pixel'}` 等非敏感字段
- **THEN** scrubBeforeSend 保留原值不变

### Requirement: A2 dashboard _regenerateButton 触控目标 ≥48dp

#### Scenario: 触控目标合规
- **WHEN** 渲染 _regenerateButton
- **THEN** 按钮最小触控尺寸 ≥48×48dp，移除 `minimumSize: Size(0, 32)` 与 `tapTargetSize: MaterialTapTargetSize.shrinkWrap`

### Requirement: A3 update release notes 支持展开/收起

#### Scenario: 默认折叠显示前 N 行
- **WHEN** release notes 内容超过 10 行
- **THEN** 默认显示前 10 行 + "展开全文"按钮

#### Scenario: 点击展开显示完整内容
- **WHEN** 用户点击"展开全文"
- **THEN** 切换为 SingleChildScrollView + Text（无 maxLines），按钮变为"收起"

### Requirement: A4 food_library 搜索失败显示 toast

#### Scenario: 搜索 DB 异常时显示 toast
- **WHEN** _doSearch catch 异常
- **THEN** 调用 `showAppToast(context, '搜索失败，请重试')` 并清空 _searchResults + 关 _searchLoading

### Requirement: A5 备份导入弹窗显示离线队列条数

#### Scenario: 有 pending 记录时弹窗告知
- **WHEN** 用户触发备份导入 + pending_recognitions 表 count > 0
- **THEN** 确认弹窗内容含"⚠️ 离线队列中 N 条待识别记录将被清空"提示

#### Scenario: 无 pending 记录时弹窗不显示该行
- **WHEN** pending_recognitions 表 count == 0
- **THEN** 弹窗内容保持原 6 项列表，不显示离线队列提示

### Requirement: A6 insight 周/月切换显示 loading

#### Scenario: 切换周期时显示 loading
- **WHEN** 用户点击 SegmentedButton 切换周/月
- **THEN** 图表区显示 LoadingState，_chartLoading=true

#### Scenario: 加载完成后平滑过渡
- **WHEN** _loadExisting 完成
- **THEN** _chartLoading=false，AnimatedSwitcher 300ms 过渡显示图表

### Requirement: A7 food_library 加载失败显示 ErrorState

#### Scenario: _loadFrequent 异常时显示 ErrorState
- **WHEN** _loadFrequent catch 异常
- **THEN** _loadError=true，UI 显示 ErrorState + 重试按钮（与 dashboard/today_meals 同构）

#### Scenario: 点击重试按钮重新加载
- **WHEN** 用户点击 ErrorState 中的重试按钮
- **THEN** 重置 _loadError=false + _initialLoading=true + 重新调 _loadFrequent

### Requirement: A8 profile 加载失败显示 ErrorState

#### Scenario: 档案加载失败时显示 ErrorState
- **WHEN** _loadProfile catch 异常
- **THEN** _loadError=true，build 中显示 ErrorState + 重试按钮（不显示空白表单）

#### Scenario: 点击重试按钮重新加载
- **WHEN** 用户点击 ErrorState 中的重试按钮
- **THEN** 重置 _loadError=false + _loading=true + 重新调 _loadProfile

### Requirement: B1 跨层依赖统一用 Repository Provider

#### Scenario: feature 层不直接 import data/database
- **WHEN** 审查 `lib/features/**/*.dart` 文件 import 列表
- **THEN** 无 `import 'package:eatwise/data/database/database.dart'` 语句（类型 import 改从 repository 文件导出）

#### Scenario: feature 层不手动 new Repository
- **WHEN** 审查 `lib/features/**/*.dart` 文件
- **THEN** 无 `FoodItemRepository(db)` / `MealLogRepository(db)` / `ProfileRepository(db)` 等直接构造调用，统一用 `ref.read(recognize.xxxRepoProvider.future)`

### Requirement: B2 recognize_page._pickAndRecognize 拆分

#### Scenario: 主方法只做编排
- **WHEN** 审查 _pickAndRecognize 方法
- **THEN** 方法体 < 50 行，仅调用 _pickImage / _runRecognize / _showResultAndWaitConfirm / _writeMealLog 子方法

#### Scenario: 行为不变
- **WHEN** 拆分后跑 recognize_page_test 全部测试
- **THEN** 所有现有断言通过，行为零回归

### Requirement: B3 offline_queue_controller.processPending 拆分

#### Scenario: 主方法只做遍历和分发
- **WHEN** 审查 processPending 方法
- **THEN** 方法体 < 80 行，仅遍历 pending + 调 _processSingleItem / _processComposite 分发

#### Scenario: 单品/复合菜路径行为不变
- **WHEN** 拆分后跑 offline_queue_test 全部测试
- **THEN** 所有现有断言通过，行为零回归

### Requirement: B4 multi_dish_page 拆分

#### Scenario: 主文件行数 < 600
- **WHEN** 拆分后 `wc -l lib/features/recognize/multi_dish_page.dart`
- **THEN** 行数 < 600（从 986 降至 600 以下）

#### Scenario: 拆出 widget 独立可测
- **WHEN** 审查拆出的 _CalcNutritionWidget / _CompositeEditor 等
- **THEN** 每个 widget 可独立 widget test，无强耦合 StatefulWidget 状态

#### Scenario: 行为不变
- **WHEN** 拆分后跑 multi_dish_page_test 全部测试
- **THEN** 所有现有断言通过，行为零回归

### Requirement: B5 dashboard_page 拆分

#### Scenario: 主文件行数 < 600
- **WHEN** 拆分后 `wc -l lib/features/dashboard/dashboard_page.dart`
- **THEN** 行数 < 600（从 948 降至 600 以下）

#### Scenario: 拆出 section widget 独立可测
- **WHEN** 审查拆出的 _StatusCardSection / _RecommendationSection / _TodayMealsSection 等
- **THEN** 每个 widget 可独立 widget test，回调通过 props 传入不直接访问 StatefulWidget 状态

#### Scenario: 行为不变
- **WHEN** 拆分后跑 dashboard_page_test 全部测试
- **THEN** 所有现有断言通过，行为零回归

## MODIFIED Requirements

### Requirement: pubspec.yaml 版本

`version: 0.21.0+33` → `version: 0.22.0+34`（minor bump 因架构重构属重大变更）

## Assumptions & Decisions

1. **TDD 强制执行**：所有修复（含快速修复 + 架构重构）必须先写失败测试再实现，遵循 test-driven-development skill 的 Red-Green-Refactor
2. **架构重构零行为变更**：B1-B5 拆分必须保证行为不变，靠现有测试 + 新增测试守护。若拆分过程中发现现有测试覆盖不足，先补测试再拆
3. **6 条硬约束不可违反**：B3 拆分 processPending 时绝不能改 AI 兜底三路径逻辑 / per100g 反算 / 哨兵替换，只拆方法结构不改业务逻辑
4. **B4/B5 拆分顺序**：先 B4 multi_dish_page（986 行）后 B5 dashboard_page（948 行），因为 multi_dish_page 是识别主路径风险更高需更早验证
5. **B1 跨层依赖与 B2/B3 拆分顺序**：先 B1 统一 Provider 注入（建立测试基础）再 B2/B3 拆长方法（拆分后子方法需用 Provider 而非直接 new Repo）
6. **A6 insight loading 与 A7/A8 ErrorState 模式参考**：参考 dashboard_page / today_meals_page 现有 ErrorState 实现，保持跨页一致性
7. **A5 备份导入弹窗动态 pending 数**：弹窗触发前先查 `pendingRecognitionRepoProvider.countPending()`，异步获取后注入弹窗 content
8. **不引入新依赖**：本 spec 不引入 file_picker / 任何新 package，所有修复用现有依赖完成
9. **沙箱验证**：flutter analyze + flutter test 沙箱可跑，真机验证由用户侧完成
10. **回归测试基线**：M22 完成时 1010 passed，M24 完成后应 ≥ 1010 + 新增测试数，无原有测试 fail

## 6 条硬约束（M24 不可违反）

1. `android/app/build.gradle.kts` 保持 `isMinifyEnabled = false` + `isShrinkResources = false`
2. `meal_log.food_item_id` 是非空外键，AI 兜底 `foodItemId=0` 哨兵写库前必须调 `upsertAiRecognized` 替换
3. AI 兜底三路径必须全部覆盖：`recognize_page` / `multi_dish_page` / `offline_queue_controller`
4. per100g 反算必须基于 `estimatedWeightGMid`，不能用 `servingG`
5. `SecureConfigStore` 没有 `instance` 静态属性，用构造函数或 `container.read(secureConfigStoreProvider)`
6. `initSentryAndRunApp` 参数是命名参数 `container:` + `app:`

## 验证流程（反复检查）

每完成一个 Task 必须执行：

1. `flutter analyze` → 0 issues
2. `flutter test [相关测试文件]` → 全过
3. `flutter test` → 全量测试无回归
4. 6 条硬约束核查（grep 关键代码）
5. Sub-agent 二次审查（每个 Task 完成后由 sub-agent 读 diff 验证）

M24 全部完成后执行：

1. `flutter analyze` 全量 0 issues
2. `flutter test` 全量 ≥ 1010 + 新增测试数 passed
3. 6 条硬约束全量核查
4. pubspec.yaml 版本 bump
5. HANDOFF.md M24 章节更新
6. git commit（不 push 不打 tag，等用户指令）
