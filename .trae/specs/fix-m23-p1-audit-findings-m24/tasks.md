# Tasks

## Phase 1：快速修复（8 项，~2h）

- [ ] Task A1: sentry_scrub.dart 补 event.tags 脱敏
  - [ ] SubTask A1.1: 写失败测试 `sentry_scrub_test.dart` 新增 "event.tags 含敏感 key 时脱敏" + "无敏感 key 时保留" 两个测试，运行确认 fail
  - [ ] SubTask A1.2: 在 scrubBeforeSend 第 25 行后补 tags 脱敏逻辑（与 extra 同模式，遍历 event.tags 删除命中 _isSensitiveKey 的 entry）
  - [ ] SubTask A1.3: 运行测试确认 pass + flutter analyze 0 issues
  - [ ] SubTask A1.4: sub-agent 二次审查 diff

- [ ] Task A2: dashboard _regenerateButton 触控目标 32→48dp
  - [ ] SubTask A2.1: 写失败测试 `dashboard_page_test.dart` 新增 "_regenerateButton 触控目标 ≥48dp" 测试，运行确认 fail
  - [ ] SubTask A2.2: 移除 dashboard_page.dart L519-520 的 `minimumSize: Size(0, 32)` + `tapTargetSize: MaterialTapTargetSize.shrinkWrap`
  - [ ] SubTask A2.3: 运行测试确认 pass + flutter analyze 0 issues
  - [ ] SubTask A2.4: sub-agent 二次审查 diff

- [ ] Task A3: update release notes 展开/收起
  - [ ] SubTask A3.1: 写失败测试 `update_page_test.dart` 新增 "默认折叠显示前 10 行 + 展开按钮" + "点击展开显示完整内容" 两个测试，运行确认 fail
  - [ ] SubTask A3.2: update_page.dart L213-214 移除 maxLines:10 + overflow:ellipsis，改用 StatefulWidget + _expanded 标志 + SingleChildScrollView + Text + 展开/收起按钮
  - [ ] SubTask A3.3: 运行测试确认 pass + flutter analyze 0 issues
  - [ ] SubTask A3.4: sub-agent 二次审查 diff

- [ ] Task A4: food_library 搜索失败 toast
  - [ ] SubTask A4.1: 写失败测试 `food_library_page_test.dart` 新增 "_doSearch catch 显示 toast" 测试，运行确认 fail
  - [ ] SubTask A4.2: food_library_page.dart L95-102 catch 内补 `showAppToast(context, '搜索失败，请重试')`
  - [ ] SubTask A4.3: 运行测试确认 pass + flutter analyze 0 issues
  - [ ] SubTask A4.4: sub-agent 二次审查 diff

- [ ] Task A5: 备份导入弹窗补"离线队列 N 条将被清空"
  - [ ] SubTask A5.1: 写失败测试 `backup_page_test.dart` 新增 "pending>0 时弹窗含离线队列提示" + "pending=0 时弹窗不显示该行" 两个测试，运行确认 fail
  - [ ] SubTask A5.2: backup_page.dart L155-161 _import 弹窗触发前先 `await ref.read(pendingRecognitionRepoProvider).countPending()`，根据 count 动态拼接 content
  - [ ] SubTask A5.3: 运行测试确认 pass + flutter analyze 0 issues
  - [ ] SubTask A5.4: sub-agent 二次审查 diff

- [ ] Task A6: insight 周/月切换 loading + AnimatedSwitcher
  - [ ] SubTask A6.1: 写失败测试 `insight_page_test.dart` 新增 "切换周期时显示 LoadingState" + "加载完成后 AnimatedSwitcher 过渡" 两个测试，运行确认 fail
  - [ ] SubTask A6.2: insight_page.dart 新增 `_chartLoading` 标志，onSelectionChanged 内置 true，_loadExisting 完成后置 false；图表区用 AnimatedSwitcher 包裹（LoadingState ↔ 图表，300ms 过渡）
  - [ ] SubTask A6.3: 运行测试确认 pass + flutter analyze 0 issues
  - [ ] SubTask A6.4: sub-agent 二次审查 diff

- [ ] Task A7: food_library 加载失败 ErrorState
  - [ ] SubTask A7.1: 写失败测试 `food_library_page_test.dart` 新增 "_loadFrequent catch 显示 ErrorState" + "点击重试重新加载" 两个测试，运行确认 fail
  - [ ] SubTask A7.2: food_library_page.dart 新增 `_loadError` 标志，L55-59 catch 内置 true，UI 加 `_loadError ? ErrorState(...) :` 分支（与 today_meals 同构）
  - [ ] SubTask A7.3: 运行测试确认 pass + flutter analyze 0 issues
  - [ ] SubTask A7.4: sub-agent 二次审查 diff

- [ ] Task A8: profile 加载失败 ErrorState
  - [ ] SubTask A8.1: 写失败测试 `profile_page_test.dart` 新增 "_loadProfile catch 显示 ErrorState" + "点击重试重新加载" 两个测试，运行确认 fail
  - [ ] SubTask A8.2: profile_page.dart 新增 `_loadError` 标志，L74-78 catch 内置 true，build 中加 `_loadError ? ErrorState(...) :` 分支（不显示空白表单）
  - [ ] SubTask A8.3: 运行测试确认 pass + flutter analyze 0 issues
  - [ ] SubTask A8.4: sub-agent 二次审查 diff

## Phase 2：架构重构（5 项，~13h）

- [ ] Task B1: 跨层依赖统一用 Repository Provider
  - [ ] SubTask B1.1: 在 `lib/features/recognize/providers.dart` 补齐缺失的 Repository Provider（profileRepoProvider / weightLogRepoProvider / pendingRecognitionRepoProvider 等若缺）
  - [ ] SubTask B1.2: 11 个 feature 文件移除 `import 'package:eatwise/data/database/database.dart'`，类型 import 改从 repository 文件导出
  - [ ] SubTask B1.3: dashboard_page.dart / offline_queue_controller.dart / food_library_page.dart 等 4 个文件移除 `FoodItemRepository(db)` / `MealLogRepository(db)` / `ProfileRepository(db)` 直接构造，改用 `ref.read(recognize.xxxRepoProvider.future)`
  - [ ] SubTask B1.4: grep `import.*data/database/database.dart` in lib/features/ 确认 0 匹配
  - [ ] SubTask B1.5: grep `FoodItemRepository(db)\|MealLogRepository(db)\|ProfileRepository(db)` in lib/features/ 确认 0 匹配
  - [ ] SubTask B1.6: flutter analyze 0 issues + flutter test 全量无回归
  - [ ] SubTask B1.7: 6 硬约束核查（特别是硬约束 5 SecureConfigStore 无 instance）
  - [ ] SubTask B1.8: sub-agent 二次审查 diff

- [ ] Task B2: recognize_page._pickAndRecognize 拆分
  - [ ] SubTask B2.1: 补 `recognize_page_test.dart` 现有测试覆盖度审查，若关键分支无测试则先补测试守护（拆分前先建安全网）
  - [ ] SubTask B2.2: 拆出 `_pickImage()` 子方法（选图 + 压缩 + 状态切换）
  - [ ] SubTask B2.3: 拆出 `_runRecognize()` 子方法（识别 + 容灾链路）
  - [ ] SubTask B2.4: 拆出 `_showResultAndWaitConfirm()` 子方法（展示结果 + 等待用户确认）
  - [ ] SubTask B2.5: 拆出 `_writeMealLog()` 子方法（写库 + 离线入队）
  - [ ] SubTask B2.6: 主方法 _pickAndRecognize 改为编排，方法体 < 50 行
  - [ ] SubTask B2.7: flutter test 全量无回归 + 6 硬约束核查（硬约束 2/3 foodItemId 哨兵替换 + AI 三路径不能因拆分改逻辑）
  - [ ] SubTask B2.8: sub-agent 二次审查 diff

- [ ] Task B3: offline_queue_controller.processPending 拆分
  - [ ] SubTask B3.1: 补 `offline_queue_test.dart` 现有测试覆盖度审查，若关键分支无测试则先补测试守护
  - [ ] SubTask B3.2: 拆出 `_processSingleItem(p)` 子方法（单品路径 L162-260，含 foodItemId=0 哨兵 + 包装 OCR 优先 + AI 估算兜底）
  - [ ] SubTask B3.3: 拆出 `_processComposite(p)` 子方法（复合菜路径 L261-432，含组分份量校准 + 包装 OCR + 哨兵替换）
  - [ ] SubTask B3.4: 主方法 processPending 改为遍历 + 分发，方法体 < 80 行
  - [ ] SubTask B3.5: flutter test 全量无回归 + 6 硬约束核查（硬约束 2/3/4 三路径哨兵 + per100g 基于 mid 不能因拆分改逻辑）
  - [ ] SubTask B3.6: sub-agent 二次审查 diff

- [ ] Task B4: multi_dish_page 拆分（986 行 → < 600 行）
  - [ ] SubTask B4.1: 补 `multi_dish_page_test.dart` 现有测试覆盖度审查，若关键分支无测试则先补测试守护
  - [ ] SubTask B4.2: 拆出 `_CalcNutritionWidget`（独立 widget，接收 dishes + currentSingles + composites + hitFlags，回调输出营养计算结果）
  - [ ] SubTask B4.3: 拆出 `_CompositeEditor` widget（复合菜编辑器，独立可测）
  - [ ] SubTask B4.4: 拆出 `_AdditionalDishEditor` widget（附加菜编辑器）
  - [ ] SubTask B4.5: 拆出 `_DishCard` widget（菜品卡片，含 sourceBadge + 营养素行）
  - [ ] SubTask B4.6: 主文件 multi_dish_page.dart 聚焦编排，行数 < 600
  - [ ] SubTask B4.7: flutter test 全量无回归 + 6 硬约束核查（硬约束 3 multi_dish_page 是 AI 兜底三路径之一，哨兵分支不能因拆分改逻辑）
  - [ ] SubTask B4.8: sub-agent 二次审查 diff

- [ ] Task B5: dashboard_page 拆分（948 行 → < 600 行）
  - [ ] SubTask B5.1: 补 `dashboard_page_test.dart` 现有测试覆盖度审查，若关键分支无测试则先补测试守护
  - [ ] SubTask B5.2: 拆出 `_StatusCardSection` widget（状态卡：今日热量 + 宏营养 + 周期对比）
  - [ ] SubTask B5.3: 拆出 `_RecommendationSection` widget（推荐区：AI 推荐 + v4 兜底 + 反馈）
  - [ ] SubTask B5.4: 拆出 `_TodayMealsSection` widget（餐次列表区）
  - [ ] SubTask B5.5: 拆出 `_RegenerateButton` widget（A2 触控目标修复后独立 widget）
  - [ ] SubTask B5.6: 主文件 dashboard_page.dart 聚焦布局，行数 < 600
  - [ ] SubTask B5.7: flutter test 全量无回归 + 6 硬约束核查
  - [ ] SubTask B5.8: sub-agent 二次审查 diff

## Phase 3：验证 + 收尾

- [ ] Task C1: 全量验证
  - [ ] SubTask C1.1: `flutter analyze` 全量 0 issues
  - [ ] SubTask C1.2: `flutter test` 全量 ≥ 1010 + 新增测试数 passed
  - [ ] SubTask C1.3: 6 条硬约束全量核查（grep build.gradle minify / foodItemId 哨兵三路径 / per100g mid / SecureConfigStore instance / initSentryAndRunApp 命名参数）
  - [ ] SubTask C1.4: 文件行数核查（multi_dish_page < 600 / dashboard_page < 600 / _pickAndRecognize < 50 / processPending < 80）
  - [ ] SubTask C1.5: 跨层依赖核查（grep `import.*data/database/database.dart` in lib/features/ = 0 匹配）

- [ ] Task C2: 版本 bump + HANDOFF 更新
  - [ ] SubTask C2.1: pubspec.yaml `version: 0.21.0+33` → `0.22.0+34`
  - [ ] SubTask C2.2: HANDOFF.md 加 M24 章节（修复清单 + 验证结果 + 测试基线）
  - [ ] SubTask C2.3: git status 确认工作区状态，准备 commit

- [ ] Task C3: 终审 + 交付
  - [ ] SubTask C3.1: sub-agent 终审全量 diff（对照 spec 每条 requirement 验证）
  - [ ] SubTask C3.2: 通知用户 M24 完成，等用户确认是否 push + tag v0.22.0

# Task Dependencies

- Phase 1（A1-A8）之间无依赖，可并行执行（但每个 Task 内 SubTask 串行）
- Phase 2 顺序：B1 → B2/B3（并行）→ B4 → B5
  - B1 跨层依赖统一是 B2/B3 拆分的基础（拆分后子方法需用 Provider 而非 new Repo）
  - B2/B3 之间无依赖，可并行
  - B4 multi_dish_page 风险更高（识别主路径），先于 B5 dashboard_page
- Phase 3（C1/C2/C3）必须在 Phase 1 + Phase 2 全部完成后执行
- 每个 Task 的 SubTask X.4/X.8 sub-agent 二次审查是强制 gate
