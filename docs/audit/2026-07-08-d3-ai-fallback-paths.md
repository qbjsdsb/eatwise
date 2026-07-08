# P0-D3: AI 兜底三路径一致性审查

> 项目：EatWise（慢慢吃）
> 范围：AI 兜底（foodItemId=0 哨兵）三条路径的哨兵替换 / per100g 反算 / actualCalories 计算 / 边界 case / 测试覆盖一致性审查
> 仅检查与报告，未修改任何代码

## 检查日期 / HEAD commit

- 检查日期：2026-07-08
- HEAD commit：`bb30873`（fix(build): 修复 build_runner 失败——sqlparser 0.44.5 override + 重新生成 database.g.dart）
- 当前分支：`trae/agent-wX1X6Q`，工作树 clean
- 基线版本：v0.33.0+46

## 三路径行为对比矩阵

| 检查项 | recognize_page | multi_dish_page | offline_queue_controller | 一致性 |
|---|---|---|---|---|
| 哨兵分支调用 upsertAiRecognized | ✓（recognize_page.dart:105） | ✓（multi_dish_page.dart:379, 453, 482） | ✓（offline_queue_controller.dart:327, 414, 473, 511, 527） | ✓ 一致 |
| 调用时机（在 insertMealLog 前） | ✓（line 105 在 line 169 前） | ✓（在 line 493 insertMealLog 前） | ✓（在 line 190 insertMealLog 前） | ✓ 一致 |
| 替换后用真实 id（非 0） | ✓（foodItemId = await upsertAiRecognized） | ✓ | ✓ | ✓ 一致 |
| 写库事务包裹 | ✗ 未包裹（upsert + insert 分别 await） | ✓（db.transaction 包裹 line 350-509） | ✓（_db.transaction 包裹 insertMealLog + markDone，line 189-204） | ✗ 不一致 |
| 防重入 | _isRecognizing | _isRecording | _processing | ✓ 一致 |
| upsert 失败时仍写库 | 否（await 抛异常跳过 insert） | 否（事务回滚） | 否（事务回滚） | ✓ 一致 |
| per100g 反算基于 estimatedWeightGMid | ✓（calculator 内部） | ✓（calculator 内部） | ✓（calculator 内部） | ✓ 一致 |
| actualCalories 单品哨兵取值 | onConfirm 传入值（含用户编辑） | calibrated.actualCalories（per100g×servingG/100） | calibrated.actualCalories（per100g×mid/100） | △ 设计差异 |
| actualCalories 复合菜 AI 优先 | 走 computeCompositeLookupHit（间接，via compositeNutrition 分支） | 走 computeCompositeLookupHit（_computeCompositeLookupHitCalibrated） | 走 computeCompositeLookupHit（line 495） | ✓ 一致 |
| 改菜名重试命中走差异检测 | ✓（line 767-790 走 writeCalibratedMealLog） | ✓（_handleRename setState _currentSingles[i]） | ✗ 后台无改菜名入口（设计如此） | △ 后台无入口 |
| 库未命中 + 无 AI 估算处理 | 弹 _showNotFoundDialog 引导手动录入 | _hitFlags=false 跳过该菜 | markFailed（permanent: false，可重试） | ✓ 三路径各自处理方式 |
| 复合菜组分全 miss + AI 估算 | compositeNutrition 分支走 upsertAiRecognized | 走 _computeCompositeLookupHitCalibrated | _processComposite 全 miss 分支走 upsertAiRecognized（line 414） | ✓ 一致 |
| 异常处理 | 调用方 _writeMealLog 不 catch（异常上浮到 onConfirm，UI 层未捕获） | catch 包裹（line 521-529 提示 + 事务回滚） | catch 包裹（line 217-237 markFailed） | △ recognize_page 无 UI 异常提示 |

## 哨兵替换实现细节

### 路径 1：recognize_page.dart — `RecognizePage.writeCalibratedMealLog`

文件：`/workspace/lib/features/recognize/recognize_page.dart:47-183`

3 个分支（line 77-167）：

1. **单品 + foodItemId==0 哨兵**（line 79-115）
   - 调 `CalibratedNutritionCalculator.compute(recognitionResult, aiFallback, servingG)`（line 86-90）
   - 调 `foodRepo.upsertAiRecognized(...)`（line 105-113），返回真实 id 赋给 `foodItemId`
   - **注意**：actualXxx 不取自 calibrated，而是保持 line 73-76 的 `calories/protein/fat/carbs`（onConfirm 传入值）。注释 line 67-72 说明这是 v2 改动 E：actualXxx 始终用 onConfirm 传入值（calibration_page._applyUserOverrides 算好）

2. **单品 + foodItemId>0 命中**（line 116-141）
   - `foodItemId = n.foodItemId`（line 117）
   - 若有 aiFallbackNutrition：调 calculator 差异检测，shouldUpdateFoodItem=true 时调 updatePer100g 纠正脏库（line 132-140）
   - actualXxx 仍用 onConfirm 传入值（不重算）

3. **复合菜 compositeNutrition**（line 143-163）
   - 调 `foodRepo.upsertAiRecognized(...)`（line 154-163），返回真实 id
   - 包装 OCR 优先（hasPackageNutrition 时 per100g 用包装换算值，否则 0）

4. **无营养数据**（line 164-167）
   - return null，不写库

写库（line 169-181）调 `mealRepo.insertMealLog(foodItemId: foodItemId, ...)`。**无事务包裹**：upsertAiRecognized 与 insertMealLog 是两个独立 await。

### 路径 2：multi_dish_page.dart — `_recordAll`

文件：`/workspace/lib/features/recognize/multi_dish_page.dart:334-530`

整个循环用 `db.transaction(() async { ... })` 包裹（line 350-509），任一菜失败整体回滚。每菜 4 分支：

1. **单品 + foodItemId==0 哨兵**（line 369-393）
   - 调 `CalibratedNutritionCalculator.compute(...)`（line 374-378）
   - 调 `foodRepo.upsertAiRecognized(...)`（line 379-387）
   - **用 calibrated.actualXxx 覆盖 cal/p/f/c**（line 390-393）：`cal = calibrated.actualCalories` 等
   - 与 recognize_page 不同：actualXxx 取自 calibrated 重算值

2. **单品 + foodItemId>0 命中**（line 394-420）
   - 调 `_computeLookupHitCalibrated(i, dish, serving)`（委托 NutritionPreview.computeLookupHitCalibrated）
   - calibrated != null 时 `foodItemId = calibrated.foodItemId` + 用 calibrated.actualXxx 覆盖（line 402-406）
   - shouldUpdateFoodItem=true 时调 updatePer100g（line 408-416）
   - calibrated == null 时 `foodItemId = n.foodItemId`（line 418）

3. **复合菜 composite**（line 421-478）
   - 调 `_computeCompositeLookupHitCalibrated(i, dish, serving)`（委托 NutritionPreview.computeCompositeLookupHitCalibrated）
   - 调 `foodRepo.upsertAiRecognized(...)`（line 453-478），per100g 用 AI 反算值（compositeCalibrated != null）或包装换算值或 0 占位
   - 用 compositeCalibrated.actualXxx 覆盖 cal/p/f/c（line 425-430）

4. **防御兜底**（line 479-491）
   - "理论不应到这里"——_hitFlags[i]=true 守卫已保证命中
   - 防御性 upsertAiRecognized（per100g=0），避免 insertMealLog FK 违规

### 路径 3：offline_queue_controller.dart — `_processSingleItem` / `_processComposite`

文件：`/workspace/lib/features/offline/offline_queue_controller.dart:135-554`

主流程 `_processOnePending`（line 135-238）调视觉 API + RecognitionPostProcessor，分发到子方法。**写库（insertMealLog + markDone）用 `_db.transaction` 包裹**（line 189-204），原子化防重复。

`_processSingleItem`（line 243-359）4 分支：

1. **库命中 + AI 估算**（line 267-299）
   - 构造 aiFallback = NutritionResult(foodItemId: 0, calories: result.estimatedCalories)（line 270-277）
   - 调 `CalibratedNutritionCalculator.compute(..., lookupHitNutrition: nutrition)`（line 278-283）
   - `foodItemId = calibrated.foodItemId`（来自 lookupHitNutrition.foodItemId，line 284）
   - shouldUpdateFoodItem=true 时调 updatePer100g（line 290-298）

2. **库命中 + 无 AI 估算**（line 300-307，旧 prompt）
   - `foodItemId = nutrition.foodItemId`
   - actualXxx = nutrition.* （库值 × mid/100 已在 NutritionLookup 内部算好）

3. **库未命中 + AI 估算**（line 308-339）哨兵分支
   - 调 `CalibratedNutritionCalculator.compute(...)`（无 lookupHitNutrition，line 319-323）
   - 调 `foodItemRepo.upsertAiRecognized(...)`（line 327-335），返回真实 id
   - **用 calibrated.actualXxx**（line 336-339）

4. **库未命中 + 无 AI 估算**（line 340-348）
   - markFailed（permanent: false，可重试），return null

`_processComposite`（line 364-554）3 分支：

1. **组分全 miss + AI 估算**（line 379-434）
   - 走包装 OCR 优先 / AI 反算 per100g
   - 调 `upsertAiRecognized(...)`（line 414-422）
   - actualXxx 用 AI 估算整菜值（line 430-434）

2. **组分全 miss + 无 AI 估算**（line 435-441）
   - markFailed，return null

3. **组分部分/全部命中**（line 442-543）
   - 包装 OCR 优先（line 470-486）：upsertAiRecognized 用包装换算 per100g + actualXxx = 包装换算
   - AI 优先（line 488-524）：调 `computeCompositeLookupHit`，upsertAiRecognized 用 AI 反算 per100g + actualXxx = aiCalibrated.actualXxx
   - 兜底（line 525-541）：upsertAiRecognized 用 per100g=0 + actualXxx = composite.*

## per100g 反算一致性

**硬约束 #4 满足**：三路径 per100g 反算都基于 `estimatedWeightGMid`，不用 `servingG`。

### 单品路径

`CalibratedNutritionCalculator.compute`（`/workspace/lib/features/recognize/calibrated_nutrition_calculator.dart:39-131`）：

- line 46-49：`final mid = r.estimatedWeightGMid; final per100Ratio = mid > 0 ? 100.0 / mid : 0.0;`
- 哨兵分支（line 87-115）：`aiFallback.calories * per100Ratio`（用 mid 反算），包装 OCR 优先时用 `r.computePackageNutritionPer100g(...)`
- 命中分支（line 55-85）：`dbPer100Calories = lookupHitNutrition.calories * per100Ratio`（用 mid 反算）+ `aiPer100Calories = aiFallback.calories * per100Ratio`

### 复合菜路径

`CalibratedNutritionCalculator.computeCompositeLookupHit`（line 153-183）：

- line 158：`if (mid <= 0) return null;`（防除零）
- line 160-165：`per100Ratio = 100.0 / mid; aiPer100Calories = aiFallback.calories * per100Ratio`（用 mid 反算）

### servingG 的角色（明确边界）

- **per100g 反算**：始终用 `mid = estimatedWeightGMid`（硬约束 #4 满足）
- **actualXxx 计算**：用 `servingG`（line 78, 124, 176 等）
  - recognize_page 前台：servingG 来自 calibration_page._servingG（用户调整，默认 = mid）
  - multi_dish_page 前台：servingG 来自 _servings[i]（用户调整，默认 = mid）
  - offline_queue 后台：servingG = mid（line 265, 281, 322）

`recognize_page.dart:93-94` 单品哨兵分支也用 mid 算 rawCalPer100（仅日志用途，line 94）：
```dart
final mid = result.estimatedWeightGMid;
final rawCalPer100 = mid > 0 ? n.calories * 100.0 / mid : 0.0;
```

### servingG 不用于 per100g 反算的验证

Grep "servingG" 在 lib/ 下，未发现任何 per100g 反算公式用 servingG。servingG 仅用于：
- actualXxx 缩放（per100g × servingG / 100）
- NutritionLookup.lookupSingleItem 内部按 servingG × ediblePercent 缩放（这是查询时的份量，不是反算 per100g）
- _calcNutrition 的 ratio = serving / mid（用于查库命中 + 无 aiFallback 时按比例缩放 n.*）

**结论**：硬约束 #4 三路径全部满足。

## actualCalories 计算一致性

### 单品路径

| 分支 | recognize_page | multi_dish_page | offline_queue |
|---|---|---|---|
| 哨兵（foodItemId=0 + AI 估算） | onConfirm 传入的 calories（含用户编辑，calibration_page._applyUserOverrides 后） | calibrated.actualCalories = per100g × servingG / 100 | calibrated.actualCalories = per100g × mid / 100 |
| 命中 + AI 估算 | onConfirm 传入的 calories（calibration_page 内部走差异检测算 AI 值） | _computeLookupHitCalibrated.actualCalories = aiPer100 × servingG / 100 | calibrated.actualCalories = aiPer100 × mid / 100 |
| 命中 + 无 AI 估算 | onConfirm 传入值（calibration_page 用 n.* × ratio） | _calcNutrition 返回 n.* × ratio | nutrition.* （库值 × mid/100） |
| 无 AI + 无库 | return null 不写库 | _hitFlags=false 跳过该菜 | markFailed 不写库 |

**v0.27.0 修复一致性**：
- recognize_page：v2 改动 E（line 67-72）—— actualXxx 用 onConfirm 传入值，不重算覆盖
- multi_dish_page：line 390-393 用 calibrated.actualXxx 覆盖（与 v0.27.0 修复路径一致——AI 估算值不被静默修改）
- offline_queue：line 336-339 用 calibrated.actualXxx

**潜在差异**：recognize_page 哨兵分支的 actualCalories 取 onConfirm 传入值（含用户编辑），而 multi_dish_page / offline_queue 取 calibrated.actualCalories（按 servingG 缩放）。这是设计差异（recognize_page 支持 nutrition 值直接编辑，multi_dish / offline_queue 不支持）。在 servingG=mid 且无用户编辑场景下三值一致。

### 复合菜路径

| 分支 | recognize_page | multi_dish_page | offline_queue |
|---|---|---|---|
| 包装 OCR 优先 | packagePer100 × servingG / 100（calibration_page 内部） | 走 _calcNutrition 包装分支（per100 × serving / 100） | packagePer100 × actualServingG / 100（line 483-486） |
| 复合菜 AI 优先 | compositeNutrition 分支 upsertAiRecognized + 实际 actualCalories 来自 onConfirm | _computeCompositeLookupHitCalibrated.actualCalories = aiPer100 × servingG / 100 | computeCompositeLookupHit.actualCalories = aiPer100 × mid / 100 |
| 组分累加库值（无 AI） | compositeNutrition 分支 | _calcNutrition mainComposite.calories × ratio | composite.* （组分累加） |

**v0.27.0 修复在复合菜路径也已落地**：M16.9 三路径都用 `computeCompositeLookupHit`（line 153-183）保证 AI 估算绝对优先，actualCalories 与 AI 推理值一致。

## 边界 case 分析

### 1. AI 返回 foodItemId=0 但食物名为空

`FoodItemRepository.upsertAiRecognized`（`/workspace/lib/data/repositories/food_item_repository.dart:267-345`）：

- line 277：`final cleanName = name.trim().isEmpty ? '未命名菜品' : name.trim();`
- 兜底为"未命名菜品"，不污染列表
- 三路径都依赖 upsertAiRecognized 兜底，**行为一致 ✓**

### 2. AI 返回 foodItemId>0 但实际不存在（外键违规）

- recognize_page line 117：`foodItemId = n.foodItemId;` 直接用，无校验
- multi_dish_page line 418：`foodItemId = n.foodItemId;` 直接用
- offline_queue line 284, 303：`foodItemId = calibrated.foodItemId / nutrition.foodItemId` 直接用

**无防御**：若查库命中后该 food_item 被并发删除，insertMealLog 会触发 SQLite FK 约束违规崩溃。

但实际 `foodItemId > 0` 来自 `NutritionLookup.lookupSingleItem`，它内部 `findByNameOrAlias` 命中时返回的就是当前库中的真实 rowid，理论不会出现"查库命中但 id 不存在"。**风险仅限并发删除场景**（用户在识别过程中其他线程删了该 food_item）。

`MealLogRepository.insertMealLog`（line 28-30）有哨兵防御：
```dart
if (foodItemId <= 0) {
  throw ArgumentError('foodItemId 必须为真实 id，不能是 0 哨兵');
}
```
但只防 0，不防 id>0 但不存在。**P2 风险**。

### 3. 复合菜中部分组分 foodItemId=0 部分有 id

复合菜路径不保留组分 id：

- `NutritionLookup.lookupCompositeDish` 返回 `CompositeNutritionResult`（组分累加值 + oilG）
- 三路径都直接 `upsertAiRecognized` 创建整菜的 `ai_recognized` 食物（componentsJson 存组分快照，不存组分 id）
- 行为一致 ✓

### 4. 后台回补时 AI 二次识别仍返回 foodItemId=0

**这是正常路径**：后台 `_processSingleItem` 的"库未命中 + AI 估算"分支（line 308-339）专门处理此场景，调 upsertAiRecognized 替换。

**重试上限**：
- pending_recognition_repository.markFailed 累加 retryCount
- retryCount 达上限标 failed 永久不重试（注释见 offline_queue_controller.dart:113-115）
- 网络异常 / 视觉 API 失败：catch 块 markFailed（line 236）
- 库未命中 + 无 AI 估算：markFailed（permanent: false，可重试，line 345-347）
- 图片缺失：markFailed（permanent: true，不重试，line 145）

### 5. upsertAiRecognized 失败时是否仍写库

- recognize_page：`await foodRepo.upsertAiRecognized(...)`（line 105）—— 抛异常时跳过后续 insertMealLog，不写库（**无事务但有 await 短路**）
- multi_dish_page：事务包裹，upsert 失败事务回滚
- offline_queue：upsert 在事务外（_processSingleItem 返回 _ProcessResult，事务在 _processOnePending 内 line 189）—— upsert 失败抛异常被 line 217 catch，markFailed，不写 meal_log ✓

## upsertAiRecognized 实现审查

文件：`/workspace/lib/data/repositories/food_item_repository.dart:267-345`

### 返回值是真实 id

- 新建分支（line 328-343）：`return _db.into(_db.foodItems).insert(...)` —— drift insert 返回 rowid（>0）
- 更新分支（line 291-306）：`return existing.id;` —— 已存在的 id

✓ 返回值始终是真实 id（>0）

### 幂等性

- 同名 + source='ai_recognized' 查询命中时走 update 分支（line 291-307）
- 每次更新会覆盖 caloriesPer100g / proteinPer100g / fatPer100g / carbsPer100g / confidence / componentsJson
- **副作用**：连续识别同一菜品两次，第二次的 AI 估算会覆盖第一次。设计行为（让 AI 持续纠正库），非 bug

✓ 幂等

### 并发安全

- 整个方法用 `_db.transaction(() async { ... })` 包裹（line 286-344）
- select-then-insert 原子化，防并发产生重复记录
- `_mergeAliasSafely` 内部又调 `_db.foodItems.select().get()`（line 368）读全表，事务内嵌套读
- drift 默认事务串行化（SQLite BEGIN IMMEDIATE），无死锁风险

✓ 并发安全

### brand 别名处理

- line 280-284：构造 `brandAlias = "$brand$name"`
- 更新分支调 `_mergeAliasSafely`（line 294）合并 brandAlias + 冲突检测
- 新建分支 line 314-326：brandAlias 冲突检测，已占用则不加入 initAliases

✓ 防反向错配（与 addAlias 一致）

## 测试覆盖评估

### 哨兵防御测试

`/workspace/test/data/meal_log_repository_test.dart:212-241, 421-435`：
- `foodItemId=0 抛 ArgumentError`（insertMealLog + updateMealLog 两处）
- 验证 MealLogRepository 层哨兵防御

### 外键约束测试

`/workspace/test/integration/sprint1_e2e_test.dart:228-244`：
- 验证 PRAGMA foreign_keys=ON 生效
- foodItemId=999999（不存在）应触发 FK 违规

### 三路径哨兵替换测试

| 路径 | 测试文件 | 测试 case |
|---|---|---|
| recognize_page | `/workspace/test/features/recognize_page_test.dart` | line 37-98 查库命中 / line 106-193 v2 偏差大 / line 195-274 v2 偏差小 / line 280-352 recognitionConfidence+componentsSnapshot。**哨兵分支场景（foodItemId=0）由 calibrated_nutrition_calculator_test.dart 间接覆盖**（line 33-35 注释说明） |
| multi_dish_page | `/workspace/test/features/multi_dish_page_test.dart` | line 262-343 查库命中 + AI 偏差大 / line 350-570 复合菜 AI 优先 / **line 580-665 包装 OCR 哨兵路径**（foodItemId=0 + 包装数据） |
| offline_queue | `/workspace/test/features/offline_queue_test.dart` | **line 406-528 安全网测试 4 个分支**：单品库未命中+AI估算 → 哨兵替换 / 单品库未命中+无AI → markFailed / 复合菜全miss+AI估算 → 哨兵替换 / 复合菜全miss+无AI → markFailed |
| offline_queue 复合菜 | `/workspace/test/features/offline_queue_composite_test.dart` | 复合菜回补写入 meal_log（不再静默丢弃）+ GLM fallback 注入 |

### CalibratedNutritionCalculator 测试

- `/workspace/test/features/calibrated_nutrition_calculator_test.dart`（21 个测试）：覆盖单品哨兵 / 命中 / 包装 OCR / 复合菜 AI 优先 等分支
- `/workspace/test/features/calibrated_nutrition_calculator_v2_test.dart`：v2 重构后的行为契约（AI 绝对优先 / 用户手动编辑覆盖 / warnings 透传）

### per100g 反算测试

`offline_queue_test.dart:436-441`：
```dart
// 硬约束 4 关键断言：per100g 反算基于 estimatedWeightGMid=150
expect(foodItem.caloriesPer100g, closeTo(200, 0.5));
```
显式断言 per100g 反算用 mid。

### 测试覆盖缺口

1. **recognize_page 哨兵分支（foodItemId=0）端到端测试缺失**：line 33-35 注释说"由 calibrated_nutrition_calculator_test.dart 间接覆盖"，但 writeCalibratedMealLog 在哨兵分支调 calculator 后只取 per100g（不取 actualXxx），actualXxx 来自 onConfirm 传入值。这个分支差异没有直接测试覆盖。

2. **recognize_page.writeCalibratedMealLog 无事务包裹的场景未测**：upsertAiRecognized 成功但 insertMealLog 失败时，会留下脏 food_item 记录。无测试验证此场景。

3. **foodItemId>0 但实际不存在的并发删场景未测**：理论风险但难复现。

## 发现的问题

### P0（阻断级）

无。

### P1（高优先级）

**P1-1：recognize_page.writeCalibratedMealLog 缺少事务包裹**

- 位置：`/workspace/lib/features/recognize/recognize_page.dart:105-181`
- 现状：`upsertAiRecognized`（line 105）与 `insertMealLog`（line 169）是两个独立 await，无 `_db.transaction` 包裹
- 对比：multi_dish_page._recordAll（line 350-509）和 offline_queue_controller._processOnePending（line 189-204）都用事务包裹 upsert + insert
- 风险：若 upsert 成功但 insert 失败（FK 约束违规 / 磁盘满 / 进程被杀），会留下脏 food_item 记录（source='ai_recognized'）
- 缓解：`_isDirtyFoodItem`（food_item_repository.dart:121-127）在 findByNameOrAlias 时跳过营养素不可能值的脏数据，但不防"营养素合理但 meal_log 未写入"的脏记录
- 影响：食物库逐渐累积未引用的 ai_recognized 条目，listFrequent 会过滤（仅返 meal_log 引用过的），但 searchByName 会返回
- 建议修复：用 `_db.transaction` 包裹 line 105-181 整段，与 multi_dish_page / offline_queue 对齐

### P2（中优先级）

**P2-1：AI 返回 foodItemId>0 但实际不存在时无外键违规防御**

- 位置：三路径 `foodItemId = n.foodItemId` 处（recognize_page:117 / multi_dish_page:418 / offline_queue:284, 303）
- 现状：直接用 NutritionLookup 返回的 foodItemId，不校验存在性
- 风险：并发删除场景（识别过程中其他线程删了该 food_item），insertMealLog 触发 FK 违规崩溃
- 概率：低（用户在识别过程中删食物的场景罕见）
- 缓解：MealLogRepository.insertMealLog 仅防 foodItemId<=0，不防 id>0 但不存在
- 建议：可在 insertMealLog 前加 `await foodRepo.getById(foodItemId)` 校验，但增加 DB 往返。或在 catch 块提示用户重试

**P2-2：三路径哨兵分支 actualCalories 取值来源不同（设计差异）**

- recognize_page 哨兵分支：actualCalories = onConfirm 传入值（含用户营养值编辑）
- multi_dish_page 哨兵分支：actualCalories = calibrated.actualCalories（per100g × servingG / 100）
- offline_queue 哨兵分支：actualCalories = calibrated.actualCalories（per100g × mid / 100）
- 影响：servingG=mid 且无用户编辑时三值一致；recognize_page 支持营养值直接编辑（_userOverrides），multi_dish / offline_queue 不支持
- 性质：设计差异（multi_dish_page 是简化版 UI，无营养值编辑入口），非 bug
- 建议：在 HANDOFF.md 或代码注释中明确此设计差异，避免未来误改

**P2-3：recognize_page._writeMealLog 调用方无 catch，UI 异常未提示**

- 位置：`/workspace/lib/features/recognize/recognize_page.dart:595-633`
- 现状：`_writeMealLog` 内 `await RecognizePage.writeCalibratedMealLog(...)` 不 catch，异常上浮到 onConfirm 调用方（CalibrationPage），用户无错误反馈
- 对比：multi_dish_page._recordAll catch（line 521-529 提示"记录失败"）+ offline_queue catch（line 217-237 markFailed）
- 风险：upsert / insert 抛异常时用户看到的是"按钮无响应"，不知记录失败
- 建议：在 _writeMealLog 加 try-catch + showAppToast 提示，与 multi_dish_page 对齐

### P3（低优先级 / 信息性）

**P3-1：upsertAiRecognized 更新分支覆盖 per100g 丢失历史值**

- 位置：`/workspace/lib/data/repositories/food_item_repository.dart:295-305`
- 现状：update 分支直接覆盖 caloriesPer100g / proteinPer100g / fatPer100g / carbsPer100g
- 影响：连续识别同一菜品两次，第二次 AI 估算覆盖第一次。设计行为（让 AI 持续纠正库），非 bug
- 建议：无需修改，但可在 HANDOFF.md 注明

**P3-2：recognize_page 哨兵分支 debug 日志用 mid 算 rawCalPer100**

- 位置：`/workspace/lib/features/recognize/recognize_page.dart:93-99`
- 现状：仅日志用途，不影响写库
- 备注：与硬约束 #4 一致（用 mid 反算），仅日志输出

## 结论

### 整体一致性评估

**核心硬约束全部满足**：
- 硬约束 #2（meal_log.food_item_id 非空 FK）：三路径哨兵分支都调 upsertAiRecognized 替换为真实 id，MealLogRepository.insertMealLog 加哨兵防御（foodItemId<=0 抛 ArgumentError）
- 硬约束 #3（AI 兜底三路径全覆盖）：recognize_page / multi_dish_page / offline_queue_controller 三路径全部覆盖，哨兵替换逻辑无遗漏
- 硬约束 #4（per100g 反算基于 estimatedWeightGMid）：CalibratedNutritionCalculator.compute / computeCompositeLookupHit 内部统一用 mid 反算，servingG 仅用于 actualXxx 缩放

### v0.27.0 修复一致性

"AI 推理热量与显示值不一致"修复在三路径都已落地：
- 单品命中 + AI 偏差大：三路径都走 CalibratedNutritionCalculator.compute 的 lookupHit 分支（line 55-85），actualCalories = aiPer100 × servingG / 100
- 复合菜 AI 优先：三路径都走 computeCompositeLookupHit（line 153-183）
- actualXxx 不被静默修改：recognize_page 用 onConfirm 传入值（含 _applyUserOverrides）；multi_dish / offline_queue 用 calibrated.actualXxx

### 主要差距

1. **P1-1**：recognize_page.writeCalibratedMealLog 缺事务包裹，与 multi_dish_page / offline_queue 不一致。建议修复。
2. **P2-2**：三路径哨兵分支 actualCalories 取值来源不同（设计差异，非 bug）。
3. **P2-3**：recognize_page._writeMealLog 无异常提示，与 multi_dish_page 不一致。

### 测试覆盖评估

- 哨兵防御测试：✓ MealLogRepository 层覆盖
- 三路径哨兵替换测试：✓ offline_queue 4 分支全覆盖；multi_dish_page 包装 OCR 哨兵覆盖；recognize_page 哨兵分支由 calculator 测试间接覆盖
- per100g 反算测试：✓ offline_queue_test.dart:436-441 显式断言
- 外键约束测试：✓ sprint1_e2e_test.dart:228 验证 PRAGMA foreign_keys=ON

测试覆盖缺口：recognize_page 哨兵分支端到端测试缺失（P1-1 修复时应补测试）。

### 总评

**AI 兜底三路径核心逻辑一致性高**，硬约束 #2 / #3 / #4 全部满足，v0.27.0 修复三路径落地一致。主要 P1 问题是 recognize_page 缺事务包裹（与另两路径不一致），建议在下一次会话修复并补测试。其他 P2/P3 多为设计差异或边界 case，非阻断。
