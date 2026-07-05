# M24 修复 M23 审查 P1 发现 Checklist

## Phase 1：快速修复

### A1 sentry_scrub.dart 补 event.tags 脱敏
- [ ] 失败测试已写：event.tags 含敏感 key 时脱敏 / 无敏感 key 时保留
- [ ] scrubBeforeSend 补 tags 脱敏逻辑（与 extra 同模式）
- [ ] flutter analyze 0 issues + 测试 pass
- [ ] sub-agent 二次审查 diff

### A2 dashboard _regenerateButton 触控目标 32→48dp
- [ ] 失败测试已写：触控目标 ≥48dp
- [ ] 移除 minimumSize: Size(0, 32) + tapTargetSize: shrinkWrap
- [ ] flutter analyze 0 issues + 测试 pass
- [ ] sub-agent 二次审查 diff

### A3 update release notes 展开/收起
- [ ] 失败测试已写：默认折叠显示前 10 行 + 展开按钮 / 点击展开显示完整内容
- [ ] 移除 maxLines:10 + overflow:ellipsis，改用 SingleChildScrollView + 展开/收起按钮
- [ ] flutter analyze 0 issues + 测试 pass
- [ ] sub-agent 二次审查 diff

### A4 food_library 搜索失败 toast
- [ ] 失败测试已写：_doSearch catch 显示 toast
- [ ] catch 内补 showAppToast(context, '搜索失败，请重试')
- [ ] flutter analyze 0 issues + 测试 pass
- [ ] sub-agent 二次审查 diff

### A5 备份导入弹窗补"离线队列 N 条将被清空"
- [ ] 失败测试已写：pending>0 时弹窗含离线队列提示 / pending=0 时弹窗不显示该行
- [ ] 弹窗触发前先 countPending()，根据 count 动态拼接 content
- [ ] flutter analyze 0 issues + 测试 pass
- [ ] sub-agent 二次审查 diff

### A6 insight 周/月切换 loading + AnimatedSwitcher
- [ ] 失败测试已写：切换周期时显示 LoadingState / 加载完成后 AnimatedSwitcher 过渡
- [ ] 新增 _chartLoading 标志 + AnimatedSwitcher 包裹图表区
- [ ] flutter analyze 0 issues + 测试 pass
- [ ] sub-agent 二次审查 diff

### A7 food_library 加载失败 ErrorState
- [ ] 失败测试已写：_loadFrequent catch 显示 ErrorState / 点击重试重新加载
- [ ] 新增 _loadError 标志 + ErrorState 分支（与 today_meals 同构）
- [ ] flutter analyze 0 issues + 测试 pass
- [ ] sub-agent 二次审查 diff

### A8 profile 加载失败 ErrorState
- [ ] 失败测试已写：_loadProfile catch 显示 ErrorState / 点击重试重新加载
- [ ] 新增 _loadError 标志 + ErrorState 分支（不显示空白表单）
- [ ] flutter analyze 0 issues + 测试 pass
- [ ] sub-agent 二次审查 diff

## Phase 2：架构重构

### B1 跨层依赖统一用 Repository Provider
- [ ] providers.dart 补齐缺失的 Repository Provider
- [ ] 11 个 feature 文件移除 import data/database/database.dart
- [ ] 4 个文件移除手动 new Repository，改用 ref.read(provider.future)
- [ ] grep `import.*data/database/database.dart` in lib/features/ = 0 匹配
- [ ] grep `FoodItemRepository(db)\|MealLogRepository(db)\|ProfileRepository(db)` in lib/features/ = 0 匹配
- [ ] flutter analyze 0 issues + flutter test 全量无回归
- [ ] 6 硬约束核查（特别是硬约束 5）
- [ ] sub-agent 二次审查 diff

### B2 recognize_page._pickAndRecognize 拆分
- [ ] 现有测试覆盖度审查，缺测试先补
- [ ] 拆出 _pickImage / _runRecognize / _showResultAndWaitConfirm / _writeMealLog 子方法
- [ ] 主方法 _pickAndRecognize < 50 行
- [ ] flutter test 全量无回归
- [ ] 6 硬约束核查（硬约束 2/3 哨兵 + 三路径不能改逻辑）
- [ ] sub-agent 二次审查 diff

### B3 offline_queue_controller.processPending 拆分
- [ ] 现有测试覆盖度审查，缺测试先补
- [ ] 拆出 _processSingleItem / _processComposite 子方法
- [ ] 主方法 processPending < 80 行
- [ ] flutter test 全量无回归
- [ ] 6 硬约束核查（硬约束 2/3/4 三路径哨兵 + per100g mid 不能改逻辑）
- [ ] sub-agent 二次审查 diff

### B4 multi_dish_page 拆分
- [ ] 现有测试覆盖度审查，缺测试先补
- [ ] 拆出 _CalcNutritionWidget / _CompositeEditor / _AdditionalDishEditor / _DishCard
- [ ] 主文件 multi_dish_page.dart < 600 行
- [ ] flutter test 全量无回归
- [ ] 6 硬约束核查（硬约束 3 multi_dish_page 是 AI 兜底三路径之一）
- [ ] sub-agent 二次审查 diff

### B5 dashboard_page 拆分
- [ ] 现有测试覆盖度审查，缺测试先补
- [ ] 拆出 _StatusCardSection / _RecommendationSection / _TodayMealsSection / _RegenerateButton
- [ ] 主文件 dashboard_page.dart < 600 行
- [ ] flutter test 全量无回归
- [ ] 6 硬约束核查
- [ ] sub-agent 二次审查 diff

## Phase 3：验证 + 收尾

### C1 全量验证
- [ ] `flutter analyze` 全量 0 issues
- [ ] `flutter test` 全量 ≥ 1010 + 新增测试数 passed
- [ ] 6 条硬约束全量核查
- [ ] 文件行数核查（multi_dish_page < 600 / dashboard_page < 600 / _pickAndRecognize < 50 / processPending < 80）
- [ ] 跨层依赖核查（grep `import.*data/database/database.dart` in lib/features/ = 0）

### C2 版本 bump + HANDOFF 更新
- [ ] pubspec.yaml `0.21.0+33` → `0.22.0+34`
- [ ] HANDOFF.md 加 M24 章节（修复清单 + 验证结果 + 测试基线）
- [ ] git status 确认工作区状态

### C3 终审 + 交付
- [ ] sub-agent 终审全量 diff（对照 spec 每条 requirement 验证）
- [ ] 通知用户 M24 完成，等用户确认是否 push + tag v0.22.0

## TDD 纪律（每个 Task 强制）

- [ ] 每个 Task 先写失败测试，运行确认 fail（不是因为 typo 而是因为功能缺失）
- [ ] 写最小代码让测试 pass
- [ ] refactor 保持测试 pass
- [ ] 不写"先实现后补测试"

## 6 条硬约束（M24 全程不可违反）

- [ ] `android/app/build.gradle.kts` 保持 `isMinifyEnabled=false` + `isShrinkResources=false`
- [ ] `meal_log.food_item_id` 非空外键，foodItemId=0 哨兵写库前必须替换
- [ ] AI 兜底三路径全覆盖（recognize_page / multi_dish_page / offline_queue_controller）
- [ ] per100g 反算基于 `estimatedWeightGMid`（不能用 `servingG`）
- [ ] `SecureConfigStore` 无 `instance` 静态属性
- [ ] `initSentryAndRunApp` 参数是命名参数 `container:` + `app:`

## 反复检查纪律

- [ ] 每个 Task 完成后跑 flutter analyze + 相关测试 + 全量测试
- [ ] 每个 Task 完成后由 sub-agent 二次审查 diff
- [ ] 架构重构（B1-B5）完成后必须确认行为零回归（现有测试全过）
- [ ] M24 全部完成后 sub-agent 终审全量 diff
