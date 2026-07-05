# Tasks

## 调查与设计

- [x] Task 1: 验证根因假设——写失败测试确认三路径 actualCalories 计算不一致
  - [x] SubTask 1.1: 在 test/features/recognize_page_test.dart（或新建）加测试：AI 兜底哨兵路径下，beer 品类校准后 actualCalories 应 = 43 * servingG / 100（当前实际 = 600 * ratio，失败）
  - [x] SubTask 1.2: 在 test/features/multi_dish_page_test.dart 加测试：同样场景，actualCalories 应与 recognize_page 一致
  - [x] SubTask 1.3: 在 test/features/offline_queue_controller_test.dart 加测试：同样场景，actualCalories 应 = 43 * mid / 100（当前已通过，作为参考基准）
  - [x] SubTask 1.4: 运行三个测试，确认 recognize_page / multi_dish_page 测试失败（RED），offline_queue_controller 测试通过

## 修复实施

- [x] Task 2: 提取统一的 actualCalories 计算辅助方法（避免三路径重复逻辑）
  - [x] SubTask 2.1: 在 recognize_controller.dart 或新建 utility 文件，提取 `computeCalibratedActualNutrition` 方法：输入 (NutritionResult n, VisionRecognitionResult r, double servingG)，返回 (calories, protein, fat, carbs) 用品类校准后 per100g 计算
  - [x] SubTask 2.2: 单元测试覆盖：beer 品类校准 / solid 不校准 / 包装 OCR 路径 / 宏量保留 AI 值

- [x] Task 3: recognize_page onConfirm 回调改用统一辅助方法
  - [x] SubTask 3.1: 修改 lib/features/recognize/recognize_page.dart L318-385，AI 兜底哨兵分支（n.foodItemId == 0）下，actualCalories/ProteinG/FatG/CarbsG 用 Task 2 的辅助方法计算
  - [x] SubTask 3.2: 验证 Task 1.1 的测试通过（GREEN）

- [x] Task 4: multi_dish_page _recordAll 改用统一辅助方法
  - [x] SubTask 4.1: 修改 lib/features/recognize/multi_dish_page.dart L594-604 + L657-669，AI 兜底哨兵分支用 Task 2 的辅助方法
  - [x] SubTask 4.2: 验证 Task 1.2 的测试通过（GREEN）

- [x] Task 5: CalibrationPage _confirmWithServing 单品哨兵路径预览同步
  - [x] SubTask 5.1: 修改 lib/features/recognize/calibration_page.dart L662-731，单品 AI 兜底（_currentNutrition.foodItemId == 0）路径下，onConfirm 传入的 calories/protein/fat/carbs 用品类校准后 per100g 计算（与 recognize_page 写库逻辑一致）
  - [x] SubTask 5.2: 修改 _buildNutritionPreview L390-404，单品 AI 兜底路径预览也用校准后值（与 _confirmWithServing 一致）
  - [x] SubTask 5.3: 加测试：CalibrationPage 单品哨兵路径预览值 = onConfirm 传入值（GREEN）

## 验证

- [x] Task 6: 全量回归验证
  - [x] SubTask 6.1: flutter analyze 无问题
  - [x] SubTask 6.2: flutter test 全部通过（881 + 新增测试）
  - [x] SubTask 6.3: 确认 6 条硬约束全部满足（build.gradle.kts / foodItemId 哨兵 / AI 兜底三路径 / per100g 反算基于 mid / SecureConfigStore / initSentryAndRunApp）
  - [x] SubTask 6.4: 确认 M16.2/M16.3/M16.4/M16.5 修复区域无回归

- [x] Task 7: 发布准备
  - [x] SubTask 7.1: bump pubspec.yaml 版本号 0.18.4+23 → 0.18.5+24
  - [x] SubTask 7.2: 更新 HANDOFF.md 第 2 节当前状态 + 新增 M16.6 章节
  - [x] SubTask 7.3: commit + push + tag v0.18.5 触发 GitHub Actions build APK

# Task Dependencies

- Task 2 依赖 Task 1（先 RED 验证根因）
- Task 3 / Task 4 / Task 5 依赖 Task 2（用统一辅助方法）
- Task 6 依赖 Task 3 / Task 4 / Task 5（全部修复后回归）
- Task 7 依赖 Task 6（验证通过后发布）
- Task 3 / Task 4 / Task 5 可并行（三路径独立）
