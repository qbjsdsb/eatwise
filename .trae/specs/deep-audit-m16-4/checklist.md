# Checklist

## P1 修复验证

- [x] P1-1: OFF User-Agent 含实际版本号（commit 93528fe，6 测试验证 mock PackageInfo 返回 0.18.2，User-Agent 包含 0.18.2）
- [x] P1-2: OFF serving_size 支持 ml（commit 93528fe，测试验证 "330 ml" → 330g，"30 g" → 30g 行为不变）
- [x] P1-3: OFF 命中营养按 ediblePercent 调整（commit 5b8886c，4 测试验证香蕉 edible=65% 碳水乘 0.65，加工饼干 edible=100% 不变）
- [x] P1-4: hasEnoughSamples 统计 4 维度（commit bf63ebb，3 测试验证仅有 texture 标签时返回 true）

## P2 修复验证

- [x] P2-1: getMedianServing 加 endDate 上界（commit a87cd7b，2 测试验证预录未来餐次不计入中位数）
- [x] P2-2: tdee_calibrator 用 round()（commit 83bdbfa，4 测试验证 -99.7 → -100）
- [x] P2-3: findByNameOrAlias 优先级 3/4 加脏数据过滤（commit 32e63d6，2 测试验证脏数据 contains 命中被跳过）
- [x] P2-4: fire-and-forget processPending 上报 Sentry（commit 00d1ccf，2 测试验证 catchError 内调 onError/Sentry.captureException）

## P3 修复验证

- [x] P3-1: multi_dish_page_test 精确断言（commit 193ae91，OR 容错 → 固定文案 '未命中' 精确断言）
- [x] P3-2: _writeBootLog 空 catch 加注释（commit 193ae91，`// 写 boot_log 本身失败，无可记录介质，忽略`）
- [x] P3-3: food_density densityOf 文档明确（commit 193ae91，加"调用方应先 isLiquidCategory 判断"）

## 全量验证

- [x] flutter analyze → No issues found（15.0s）
- [x] flutter test → 876 passed / 3 skipped / 0 failed（新增 20 个 TDD 测试：6 OFF + 4 ediblePercent + 3 hasEnoughSamples + 2 getMedianServing + 4 tdee round + 2 findByNameOrAlias + 2 processPending Sentry + 1 multi_dish 精确断言；原 856 + 20 = 876）
- [x] pubspec.yaml 版本号 0.18.2+21 → 0.18.3+22
- [x] HANDOFF.md M16.4 章节回填（第 1 节版本号 + 第 2 节当前状态 + M16.4 章节正文）
- [x] commit + push（不打 tag）

## 硬约束回归验证

- [x] 硬约束 #1: isMinifyEnabled=false + isShrinkResources=false 未被破坏（android/app/build.gradle.kts L62-63 完好）
- [x] 硬约束 #2: meal_log.food_item_id 非空 FK + 哨兵 0 防御未破坏（876 测试全过含 FK 关系测试）
- [x] 硬约束 #3: AI 兜底三路径（recognize_page/multi_dish_page/offline_queue_controller）未破坏（M16.4 未触及兜底分支，仅改 processPending 异常上报）
- [x] 硬约束 #4: per100g 反算基于 estimatedWeightGMid 未破坏（M16.4 未触及反算逻辑）
- [x] 硬约束 #5: SecureConfigStore 无 instance 静态属性未破坏（grep 无匹配，确认无 static instance / factory）
- [x] 硬约束 #6: initSentryAndRunApp 命名参数未破坏（sentry_init.dart L15-18 仍为 `required ProviderContainer container, required Widget app`）

## M16.2/M16.3 修复区域回归验证

- [x] 模糊检测阈值 25 + copyResize 512 未被破坏（M16.4 未触及 image_quality_checker.dart）
- [x] 断路器阈值 5 + open 60s + 429 不计失败 未被破坏（M16.4 未触及 circuit_breaker.dart）
- [x] vision_provider 超时 60s 未被破坏（M16.4 未触及 qwen_vl_provider.dart）
- [x] retryCount 阈值 5 + permanent: true 收窄 未被破坏（M16.4 未触及 pending_recognition_repository.dart）
- [x] image_picker imageQuality:85 + 限流 15s + 失败重置 未被破坏（M16.4 未触及 recognize_controller.dart）
- [x] schemaVersion 4 + migration v3→v4 清理脏数据 未被破坏（M16.4 未触及 database.dart）
- [x] findByNameOrAlias 优先级 1/2 _isDirtyFoodItem 过滤 未被破坏（M16.4 加了优先级 3/4 过滤，1/2 完好）
- [x] food_seed_importer 营养素不可能值校验 未被破坏（M16.4 未触及 food_seed_importer.dart）
