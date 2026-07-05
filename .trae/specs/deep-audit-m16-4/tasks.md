# Tasks

- [x] Task 1: P1-1 OFF User-Agent 动态版本号（commit 93528fe）
  - [x] SubTask 1.1: 写失败测试 `test/ai/off_provider_test.dart` 加 case：User-Agent 含实际版本号（mock PackageInfo）
  - [x] SubTask 1.2: 运行测试验证失败（User-Agent 仍是 0.4.0）
  - [x] SubTask 1.3: 修改 `lib/ai/off_provider.dart` User-Agent 用 `PackageInfo.fromPlatform()` 动态读取
  - [x] SubTask 1.4: 运行测试验证通过
  - [x] SubTask 1.5: commit

- [x] Task 2: P1-2 OFF serving_size 支持 ml（commit 93528fe，与 Task 1 合并）
  - [x] SubTask 2.1: 写失败测试 `test/ai/off_provider_test.dart` 加 case：serving_size="330 ml" → 330g
  - [x] SubTask 2.2: 运行测试验证失败（ml 不被解析，回退 100）
  - [x] SubTask 2.3: 修改 `lib/ai/off_provider.dart` 正则 `r'(\d+(?:\.\d+)?)\s*(g|ml)'`，ml 按密度 1.0 兜底为 g
  - [x] SubTask 2.4: 运行测试验证通过
  - [x] SubTask 2.5: commit

- [x] Task 3: P1-3 OFF 命中营养按 ediblePercent 调整（commit 5b8886c）
  - [x] SubTask 3.1: 写失败测试 `test/ai/nutrition_lookup_off_test.dart` 加 case：香蕉 edible=65% OFF 命中 → 碳水乘 0.65
  - [x] SubTask 3.2: 运行测试验证失败（OFF 命中不乘 ediblePercent）
  - [x] SubTask 3.3: 修改 `lib/ai/nutrition_lookup.dart` OFF 命中路径：营养素 × ediblePercent / 100（与 DB 命中路径一致）
  - [x] SubTask 3.4: 运行测试验证通过
  - [x] SubTask 3.5: commit

- [x] Task 4: P1-4 hasEnoughSamples 统计 4 维度（commit bf63ebb）
  - [x] SubTask 4.1: 写失败测试 `test/nutrition/user_preference_learner_test.dart` 加 case：仅有 texture 标签时返回 true
  - [x] SubTask 4.2: 运行测试验证失败（total 只算 taste+style）
  - [x] SubTask 4.3: 修改 `lib/nutrition/user_preference_learner.dart` hasEnoughSamples 加 textureFreq + priceTierFreq
  - [x] SubTask 4.4: 运行测试验证通过
  - [x] SubTask 4.5: commit

- [x] Task 5: P2-1 getMedianServing 加 endDate 上界（commit a87cd7b）
  - [x] SubTask 5.1: 写失败测试 `test/data/meal_log_repository_test.dart` 加 case：预录未来餐次不污染中位数
  - [x] SubTask 5.2: 运行测试验证失败（未来记录被统计）
  - [x] SubTask 5.3: 修改 `lib/data/repositories/meal_log_repository.dart` getMedianServing 加 `date <= today` 过滤
  - [x] SubTask 5.4: 运行测试验证通过
  - [x] SubTask 5.5: commit

- [x] Task 6: P2-2 tdee_calibrator 用 round()（commit 83bdbfa）
  - [x] SubTask 6.1: 写失败测试 `test/nutrition/tdee_calibrator_test.dart` 加 case：rawAdjustment=-99.7 → -100
  - [x] SubTask 6.2: 运行测试验证失败（实际 -99）
  - [x] SubTask 6.3: 修改 `lib/nutrition/tdee_calibrator.dart` `.toInt()` → `.round()`（提取 clampAndRound 静态方法便于测试）
  - [x] SubTask 6.4: 运行测试验证通过
  - [x] SubTask 6.5: commit

- [x] Task 7: P2-3 findByNameOrAlias 优先级 3/4 加脏数据过滤（commit 32e63d6）
  - [x] SubTask 7.1: 写失败测试 `test/data/food_item_repository_test.dart` 加 case：优先级 3 contains 命中脏数据时跳过
  - [x] SubTask 7.2: 运行测试验证失败（脏数据被 contains 命中返回）
  - [x] SubTask 7.3: 修改 `lib/data/repositories/food_item_repository.dart` 优先级 3/4 加 `_isDirtyFoodItem` 过滤
  - [x] SubTask 7.4: 运行测试验证通过
  - [x] SubTask 7.5: commit

- [x] Task 8: P2-4 fire-and-forget processPending 上报 Sentry（commit 00d1ccf）
  - [x] SubTask 8.1: 写失败测试 `test/features/offline_queue_test.dart` 加 case：processPending 抛异常时调 Sentry.captureException
  - [x] SubTask 8.2: 运行测试验证失败（catchError 吞异常不调 Sentry）
  - [x] SubTask 8.3: 修改 `lib/features/offline/offline_queue_controller.dart` 注入 onError 回调（默认 Sentry.captureException），3 处调用点同步
  - [x] SubTask 8.4: 运行测试验证通过
  - [x] SubTask 8.5: commit

- [x] Task 9: P3-1 multi_dish_page_test 精确断言（commit 193ae91）
  - [x] SubTask 9.1: 修改 `test/features/multi_dish_page_test.dart:146-148` OR 容错 → 固定文案 '未命中' 精确断言
  - [x] SubTask 9.2: 运行测试验证通过
  - [x] SubTask 9.3: commit

- [x] Task 10: P3-2 _writeBootLog 空 catch 加注释（commit 193ae91）
  - [x] SubTask 10.1: 修改 `lib/main.dart:31` 空 catch 块加注释 `// 写 boot_log 本身失败，无可记录介质，忽略`
  - [x] SubTask 10.2: commit

- [x] Task 11: P3-3 food_density 文档明确（commit 193ae91）
  - [x] SubTask 11.1: 修改 `lib/ai/food_density.dart:36-40` densityOf 文档加"调用方应先 isLiquidCategory 判断；solid 返回 1.0 仅作占位"
  - [x] SubTask 11.2: commit

- [x] Task 12: 全量验证 + bump 版本 + HANDOFF + commit + push
  - [x] SubTask 12.1: 跑 `flutter analyze` 确认 No issues（已验证）
  - [x] SubTask 12.2: 跑 `flutter test` 确认全量通过（876 passed / 3 skipped / 0 failed）
  - [x] SubTask 12.3: bump `pubspec.yaml` 0.18.2+21 → 0.18.3+22
  - [x] SubTask 12.4: 更新 HANDOFF.md（M16.4 章节回填 + 当前状态更新）
  - [x] SubTask 12.5: commit + push（不打 tag，等用户验证）

# Task Dependencies

- Task 1-11 互相独立，可并行（实际执行：Batch 1 并行 Task 1+2/3/4/5/6，Batch 2 并行 Task 7/8/9+10+11）
- Task 12 依赖 Task 1-11 全部完成
