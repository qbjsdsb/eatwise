# 营养值不一致深度修复（M16.8）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复用户反馈"AI 解析准但记录数值不对"——查库命中分支（foodItemId > 0）完全忽略 AI 估算致与 reasoning 脱节；品类校准 4 项全替换与 file 注释矛盾；改菜名重试路径绕过统一写库方法。

**Architecture:** 三层修复——(1) 扩展 `CalibratedNutritionCalculator` 支持查库命中分支：AI 与库偏差 > 50% 用 AI 反算 per100g 更新库 + 用 AI 值记录；偏差 ≤ 50% 用库值。(2) 修改 `FoodCategoryDefaults.calibrate` 只替换 calories + 宏量 clamp（符合 file 注释）。(3) 三路径（recognize_page / multi_dish_page / offline_queue_controller）+ 改菜名重试路径全部统一走 `writeCalibratedMealLog`。

**Tech Stack:** Flutter 3.x / Riverpod / Drift / TDD（RED→GREEN→REFACTOR）

---

## 根因分析（来自研究报告）

### 根因 A（最可能）：查库命中分支忽略 AI 估算

**代码证据**：
- `lib/features/recognize/calibration_page.dart:437-446`：查库命中分支用 `n.calories * ratio`，`n.calories` 来自 `nutrition_lookup.dart:57-64` 的 `food.caloriesPer100g * mid * edibleFactor / 100`
- 整个表达式中没有 `r.estimatedCalories`——AI 估算完全被丢弃
- `recognize_page.writeCalibratedMealLog` 查库命中分支（L106-108）只设 `foodItemId = n.foodItemId`，`actualXxx` 保持 onConfirm 传入值（即 `n.* * ratio`）

**用户感知**：reasoning 显示 AI 估算（如"250 kcal"），但记录用库 per100g（如 160 kcal），用户感知"AI 准但记录不对"。

### 根因 B：品类校准 4 项全替换与 file 注释矛盾

**代码证据**：
- `lib/data/seed/food_category_defaults.dart:13` 注释："只校准 calories（最重要），蛋白/脂肪/碳水保留 AI 值"
- `lib/data/seed/food_category_defaults.dart:114-117` 实际：4 项全替换 `(d.$1, d.$2, d.$3, d.$4)`

**用户感知**：啤酒 AI 估 260 kcal/5g 蛋白/300g，触发校准后记录 129 kcal/1.5g 蛋白，蛋白被覆盖。

### 根因 C：改菜名重试路径绕过统一写库方法

**代码证据**：
- `lib/features/recognize/recognize_page.dart:614-641`：`_showNotFoundDialog` onConfirm 直接调 `mealRepo.insertMealLog`（L624），不调 `RecognizePage.writeCalibratedMealLog`
- 缺失字段：`recognitionConfidence` / `componentsSnapshotJson`

---

## File Structure

**新建文件**：
- 无（所有修改在现有文件）

**修改文件**：
- `lib/features/recognize/calibrated_nutrition_calculator.dart` — 扩展 compute 方法支持查库命中分支
- `lib/data/seed/food_category_defaults.dart` — calibrate 只替换 calories + clamp 宏量
- `lib/data/repositories/food_item_repository.dart` — 新增 updatePer100g 方法
- `lib/features/recognize/recognize_page.dart` — writeCalibratedMealLog 查库命中分支接入 calculator + 改菜名重试路径统一
- `lib/features/recognize/calibration_page.dart` — _computeSingleItemActual 查库命中分支接入 calculator
- `lib/features/recognize/multi_dish_page.dart` — _recordAll 查库命中分支接入 calculator
- `lib/features/offline/offline_queue_controller.dart` — 替换手写品类校准逻辑为调 calculator

**测试文件**：
- `test/features/calibrated_nutrition_calculator_test.dart` — 扩展查库命中分支测试
- `test/features/food_category_defaults_test.dart`（新建或扩展）— 品类校准只替换 calories 测试
- `test/features/recognize_page_test.dart` — 查库命中分支差异检测测试
- `test/features/multi_dish_page_test.dart` — 查库命中分支差异检测测试

---

## Task 1: RED 测试 — 品类校准只替换 calories + clamp 宏量

**Files:**
- Test: `test/features/food_category_defaults_test.dart`（新建或扩展）

- [ ] **Step 1: 写失败测试**

```dart
// test/features/food_category_defaults_test.dart
import 'package:eatwise/data/seed/food_category_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FoodCategoryDefaults.calibrate M16.8', () {
    test('beer 触发校准：只替换 calories，宏量保留 AI 值（带 clamp）', () {
      // AI 估啤酒 per100g = 200 kcal / 50g 蛋白 / 0g 脂肪 / 20g 碳水
      // defCal=43, ratio=200/43=4.65 > 2.0 触发校准
      final (cal, p, f, c) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 200,
        aiProteinPer100g: 50, // 离谱高，应被 clamp 到 100（但保留 AI 值不替换为 0.5）
        aiFatPer100g: 0,
        aiCarbsPer100g: 20,
        category: 'beer',
      );
      expect(cal, 43, reason: 'calories 用品类默认值');
      expect(p, 50, reason: '蛋白保留 AI 值（不替换为 0.5）');
      expect(f, 0, reason: '脂肪保留 AI 值');
      expect(c, 20, reason: '碳水保留 AI 值');
    });

    test('beer 不触发校准：4 项全保留 AI 值', () {
      // AI 估啤酒 per100g = 80 kcal（43×2=86 内，不触发）
      final (cal, p, f, c) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 80,
        aiProteinPer100g: 5,
        aiFatPer100g: 0,
        aiCarbsPer100g: 8,
        category: 'beer',
      );
      expect(cal, 80);
      expect(p, 5);
      expect(f, 0);
      expect(c, 8);
    });

    test('solid 无品类默认值：4 项 clamp 到合理区间', () {
      // solid 无默认值，AI 离谱估算应被 clamp
      final (cal, p, f, c) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 5000, // 超过 900 上限
        aiProteinPer100g: 150, // 超过 100 上限
        aiFatPer100g: 200,
        aiCarbsPer100g: 300,
        category: 'solid',
      );
      expect(cal, 900, reason: 'solid calories clamp 到 900');
      expect(p, 100, reason: '蛋白 clamp 到 100');
      expect(f, 100, reason: '脂肪 clamp 到 100');
      expect(c, 100, reason: '碳水 clamp 到 100');
    });

    test('beer 触发校准且 AI 宏量离谱：clamp 兜底', () {
      // AI 估啤酒 per100g = 200 kcal / 150g 蛋白（离谱）
      final (cal, p, f, c) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 200,
        aiProteinPer100g: 150,
        aiFatPer100g: -10, // 负值
        aiCarbsPer100g: 20,
        category: 'beer',
      );
      expect(cal, 43, reason: 'calories 用品类默认值');
      expect(p, 100, reason: '蛋白 clamp 到 100（保留 AI 值但限制离谱）');
      expect(f, 0, reason: '负值 clamp 到 0');
      expect(c, 20, reason: '碳水保留 AI 值');
    });
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/food_category_defaults_test.dart`
Expected: FAIL — `Expected: 50, Actual: 0.5`（当前 4 项全替换，蛋白被替换为 0.5）

- [ ] **Step 3: 修改 calibrate 只替换 calories + clamp 宏量**

修改 `lib/data/seed/food_category_defaults.dart` L92-119：

```dart
  /// 校准 AI 估算的 per100g 营养值。
  ///
  /// M16.8：只校准 calories（最重要），宏量保留 AI 值（加 clamp 兜底防离谱）。
  /// 规则：
  /// - AI caloriesPer100g 偏离品类默认值 2 倍以上（高或低）→ calories 用默认值，宏量保留 AI 值
  /// - 不触发校准 → 4 项全保留 AI 值
  /// - solid/未知品类 → 4 项 clamp 到合理区间（无品类默认值，仅防离谱）
  /// - 宏量 clamp：蛋白/脂肪/碳水 ∈ [0, 100]（不可能超 100g/100g）
  ///
  /// [aiCaloriesPer100g] AI 估算的每 100g 热量
  /// [category] food_category（beer/wine/carbonated/solid 等）
  /// 返回 (calories, protein, fat, carbs) 每 100g
  static (double, double, double, double) calibrate({
    required double aiCaloriesPer100g,
    required double aiProteinPer100g,
    required double aiFatPer100g,
    required double aiCarbsPer100g,
    required String category,
  }) {
    // 宏量 clamp 兜底（所有分支共用）：不可能超 100g/100g，不允许负值
    final clampedProtein = aiProteinPer100g.clamp(0.0, 100.0);
    final clampedFat = aiFatPer100g.clamp(0.0, 100.0);
    final clampedCarbs = aiCarbsPer100g.clamp(0.0, 100.0);

    final defCal = defaults[category]?.$1;
    // 无默认值的品类（solid 等）：仅 clamp，不加品类默认值校准
    if (defCal == null) {
      return (
        aiCaloriesPer100g.clamp(0.0, 900.0),
        clampedProtein,
        clampedFat,
        clampedCarbs,
      );
    }
    // 偏离 2 倍以上（高或低）→ calories 用默认值，宏量保留 AI 值（带 clamp）
    // defCal=0（water）时 AI 任何正值都算偏离
    final ratio = defCal > 0 ? aiCaloriesPer100g / defCal : (aiCaloriesPer100g > 0 ? 999.0 : 1.0);
    if (ratio > 2.0 || ratio < 0.5) {
      return (defCal, clampedProtein, clampedFat, clampedCarbs);
    }
    // 不触发校准：4 项全保留 AI 值（带 clamp）
    return (aiCaloriesPer100g.clamp(0.0, 900.0), clampedProtein, clampedFat, clampedCarbs);
  }
```

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test test/features/food_category_defaults_test.dart`
Expected: PASS — 4 个测试全过

- [ ] **Step 5: 运行现有 calibrate 相关测试确认无回归**

Run: `flutter test test/features/calibrated_nutrition_calculator_test.dart`
Expected: PASS — 8 个原有测试可能需要更新断言（beer 校准后蛋白保留 AI 值，不再替换为 0.5）

如果原有测试失败，更新断言：啤酒校准场景的 actualProteinG 应基于 AI 蛋白反算（而非 0.5）。

- [ ] **Step 6: Commit**

```bash
git add lib/data/seed/food_category_defaults.dart test/features/food_category_defaults_test.dart test/features/calibrated_nutrition_calculator_test.dart
git commit -m "M16.8: 品类校准只替换 calories + 宏量 clamp（符合 file 注释）"
```

---

## Task 2: RED 测试 — CalibratedNutritionCalculator 支持查库命中分支

**Files:**
- Test: `test/features/calibrated_nutrition_calculator_test.dart`（扩展）

- [ ] **Step 1: 写失败测试**

在 `test/features/calibrated_nutrition_calculator_test.dart` 末尾追加：

```dart
  group('CalibratedNutritionCalculator.compute 查库命中分支 M16.8', () {
    test('查库命中 + AI 与库偏差 > 50%：用 AI 反算 per100g + 标记更新库', () {
      // 库有"番茄炒蛋" per100g=80（脏数据），AI 估 200g/250kcal/10g蛋白/15g脂肪/20g碳水
      // 库值 = 80 * 200 / 100 = 160 kcal
      // AI 估算 = 250 kcal
      // 偏差 = |250-160|/160 = 56% > 50% → 用 AI 反算 per100g
      // AI per100g = 250 * 100 / 200 = 125 kcal/100g
      // servingG = mid = 200
      // actualCalories = 125 * 200 / 100 = 250
      final r = VisionRecognitionResult(
        dishName: '番茄炒蛋',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        estimatedCalories: 250,
        estimatedProteinG: 10,
        estimatedFatG: 15,
        estimatedCarbsG: 20,
        foodComponents: [],
        cookingMethod: 'stir_fry',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.0',
      );
      final aiFallback = NutritionResult(
        foodItemId: 0,
        calories: 250,
        proteinG: 10,
        fatG: 15,
        carbsG: 20,
        oilG: 0,
      );
      final lookupHit = NutritionResult(
        foodItemId: 1, // 库命中
        calories: 160, // 80 * 200 / 100
        proteinG: 6,
        fatG: 10,
        carbsG: 12,
        oilG: 0,
      );
      final result = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiFallback,
        servingG: 200,
        lookupHitNutrition: lookupHit, // 新参数
      );
      expect(result.caloriesPer100g, closeTo(125, 0.1), reason: 'AI 反算 per100g = 250*100/200');
      expect(result.actualCalories, closeTo(250, 0.1), reason: '用 AI 估算值记录');
      expect(result.shouldUpdateFoodItem, isTrue, reason: '偏差大时应更新库 per100g');
      expect(result.foodItemId, 1, reason: '保留库命中的 foodItemId');
    });

    test('查库命中 + AI 与库偏差 ≤ 50%：用库 per100g + 不更新库', () {
      // 库 per100g=80, AI 估 200g/170kcal（库值 160 vs AI 170，偏差 6% < 50%）
      // 用库值：actualCalories = 80 * 200 / 100 = 160
      final r = VisionRecognitionResult(
        dishName: '番茄炒蛋',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        estimatedCalories: 170,
        estimatedProteinG: 7,
        estimatedFatG: 10,
        estimatedCarbsG: 13,
        foodComponents: [],
        cookingMethod: 'stir_fry',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.0',
      );
      final aiFallback = NutritionResult(
        foodItemId: 0,
        calories: 170,
        proteinG: 7,
        fatG: 10,
        carbsG: 13,
        oilG: 0,
      );
      final lookupHit = NutritionResult(
        foodItemId: 1,
        calories: 160, // 80 * 200 / 100
        proteinG: 6,
        fatG: 10,
        carbsG: 12,
        oilG: 0,
      );
      final result = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiFallback,
        servingG: 200,
        lookupHitNutrition: lookupHit,
      );
      expect(result.caloriesPer100g, closeTo(80, 0.1), reason: '用库 per100g');
      expect(result.actualCalories, closeTo(160, 0.1), reason: '用库值记录');
      expect(result.shouldUpdateFoodItem, isFalse, reason: '偏差小不更新库');
      expect(result.foodItemId, 1);
    });

    test('查库命中 + 用户调整滑块：actualXxx 按新 servingG 缩放', () {
      // 库 per100g=80, AI 估 200g/250kcal（偏差大用 AI 反算 per100g=125）
      // 用户调滑块 servingG=100
      // actualCalories = 125 * 100 / 100 = 125
      final r = VisionRecognitionResult(
        dishName: '番茄炒蛋',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        estimatedCalories: 250,
        estimatedProteinG: 10,
        estimatedFatG: 15,
        estimatedCarbsG: 20,
        foodComponents: [],
        cookingMethod: 'stir_fry',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.0',
      );
      final aiFallback = NutritionResult(
        foodItemId: 0,
        calories: 250,
        proteinG: 10,
        fatG: 15,
        carbsG: 20,
        oilG: 0,
      );
      final lookupHit = NutritionResult(
        foodItemId: 1,
        calories: 160,
        proteinG: 6,
        fatG: 10,
        carbsG: 12,
        oilG: 0,
      );
      final result = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiFallback,
        servingG: 100, // 用户调小
        lookupHitNutrition: lookupHit,
      );
      expect(result.caloriesPer100g, closeTo(125, 0.1));
      expect(result.actualCalories, closeTo(125, 0.1), reason: '125 * 100 / 100 = 125');
      expect(result.actualProteinG, closeTo(5, 0.1), reason: '10 * 100 / 200 = 5 (AI 蛋白反算)');
    });

    test('查库命中 + AI 与库都为 0：用库值 0 + 不更新库', () {
      // 库 per100g=0（water）, AI 估 0 kcal
      final r = VisionRecognitionResult(
        dishName: '水',
        estimatedWeightGLow: 200,
        estimatedWeightGMid: 250,
        estimatedWeightGHigh: 300,
        estimatedCalories: 0,
        foodComponents: [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.95,
        promptVersion: 'v1.0',
        foodCategory: 'water',
      );
      final aiFallback = NutritionResult(
        foodItemId: 0,
        calories: 0,
        proteinG: 0,
        fatG: 0,
        carbsG: 0,
        oilG: 0,
      );
      final lookupHit = NutritionResult(
        foodItemId: 1,
        calories: 0,
        proteinG: 0,
        fatG: 0,
        carbsG: 0,
        oilG: 0,
      );
      final result = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiFallback,
        servingG: 250,
        lookupHitNutrition: lookupHit,
      );
      expect(result.caloriesPer100g, 0);
      expect(result.actualCalories, 0);
      expect(result.shouldUpdateFoodItem, isFalse, reason: '库值 0 + AI 0 无需更新');
    });
  });
```

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test test/features/calibrated_nutrition_calculator_test.dart`
Expected: FAIL — `lookupHitNutrition` 参数不存在，编译错误

- [ ] **Step 3: 扩展 CalibratedNutritionCalculator.compute 支持查库命中分支**

修改 `lib/features/recognize/calibrated_nutrition_calculator.dart`：

```dart
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/seed/food_category_defaults.dart';

/// AI 兜底哨兵路径（foodItemId=0）+ 查库命中路径（foodItemId>0）下，
/// 用品类校准后的 per100g 计算 actualNutrition。
///
/// M16.8 扩展：查库命中分支增加差异检测——AI 估算与库 per100g × mid / 100 偏差 > 50%
/// 时用 AI 反算 per100g（更新库 + 用 AI 值记录）；偏差 ≤ 50% 用库值。
///
/// 三路径（recognize_page / multi_dish_page / offline_queue_controller）共用此方法，
/// 保证 actualCalories 与食物库 per100g 一致，避免数据脱节。
class CalibratedNutritionCalculator {
  CalibratedNutritionCalculator._();

  /// 计算 per100g（写库用）+ actualNutrition（写 meal_log 用）
  ///
  /// [recognitionResult] AI 视觉识别结果（含包装数据、品类、mid 重量）
  /// [aiFallback] 来自 _aiFallbackNutrition，foodItemId=0，calories 对应 mid 份量
  /// [servingG] 用户调整后的份量（前台）或 AI mid（后台）
  /// [lookupHitNutrition] 查库命中时的 NutritionResult（foodItemId > 0）；null 表示库未命中走 AI 兜底
  static CalibratedNutrition compute({
    required VisionRecognitionResult recognitionResult,
    required NutritionResult aiFallback,
    required double servingG,
    NutritionResult? lookupHitNutrition,
  }) {
    final r = recognitionResult;
    final mid = r.estimatedWeightGMid;
    final per100Ratio = mid > 0 ? 100.0 / mid : 0.0;

    // M16.8：查库命中分支（foodItemId > 0）—— 差异检测决定信任 AI 还是库
    if (lookupHitNutrition != null && lookupHitNutrition.foodItemId > 0) {
      // 库值 = lookupHit.calories（已是 per100g × mid / 100）
      // 库 per100g = lookupHit.calories / mid × 100
      final dbPer100Calories = mid > 0 ? lookupHitNutrition.calories * per100Ratio : 0.0;
      final dbPer100Protein = mid > 0 ? lookupHitNutrition.proteinG * per100Ratio : 0.0;
      final dbPer100Fat = mid > 0 ? lookupHitNutrition.fatG * per100Ratio : 0.0;
      final dbPer100Carbs = mid > 0 ? lookupHitNutrition.carbsG * per100Ratio : 0.0;

      // AI 估算 per100g = aiFallback.calories × 100 / mid
      final aiPer100Calories = aiFallback.calories * per100Ratio;
      final aiPer100Protein = aiFallback.proteinG * per100Ratio;
      final aiPer100Fat = aiFallback.fatG * per100Ratio;
      final aiPer100Carbs = aiFallback.carbsG * per100Ratio;

      // 差异检测：|AI - 库| / 库 > 0.5 → 用 AI 反算
      // 库值 0 时若 AI 非 0 也算偏差大（用 AI 反算）
      final diffRatio = dbPer100Calories > 0
          ? (aiPer100Calories - dbPer100Calories).abs() / dbPer100Calories
          : (aiPer100Calories > 0 ? 1.0 : 0.0);

      if (diffRatio > 0.5) {
        // 偏差大：用 AI 反算 per100g，标记更新库
        return CalibratedNutrition(
          caloriesPer100g: aiPer100Calories,
          proteinPer100g: aiPer100Protein,
          fatPer100g: aiPer100Fat,
          carbsPer100g: aiPer100Carbs,
          actualCalories: aiPer100Calories * servingG / 100,
          actualProteinG: aiPer100Protein * servingG / 100,
          actualFatG: aiPer100Fat * servingG / 100,
          actualCarbsG: aiPer100Carbs * servingG / 100,
          foodItemId: lookupHitNutrition.foodItemId,
          shouldUpdateFoodItem: true,
        );
      } else {
        // 偏差小：用库 per100g
        return CalibratedNutrition(
          caloriesPer100g: dbPer100Calories,
          proteinPer100g: dbPer100Protein,
          fatPer100g: dbPer100Fat,
          carbsPer100g: dbPer100Carbs,
          actualCalories: dbPer100Calories * servingG / 100,
          actualProteinG: dbPer100Protein * servingG / 100,
          actualFatG: dbPer100Fat * servingG / 100,
          actualCarbsG: dbPer100Carbs * servingG / 100,
          foodItemId: lookupHitNutrition.foodItemId,
          shouldUpdateFoodItem: false,
        );
      }
    }

    // AI 兜底哨兵分支（foodItemId == 0）：原 M16.6 逻辑
    // 包装 OCR 优先 → 品类校准兜底
    final packagePer100 = r.hasPackageNutrition
        ? r.computePackageNutritionPer100g(
            estimatedProteinG: r.estimatedProteinG,
            estimatedFatG: r.estimatedFatG,
            estimatedCarbsG: r.estimatedCarbsG,
          )
        : null;
    final packageMacrosAllZero = packagePer100 != null &&
        packagePer100.$2 == 0 &&
        packagePer100.$3 == 0 &&
        packagePer100.$4 == 0;

    final (caloriesPer100g, proteinPer100g, fatPer100g, carbsPer100g) =
        (packagePer100 != null && !packageMacrosAllZero)
            ? packagePer100
            : FoodCategoryDefaults.calibrate(
                aiCaloriesPer100g: aiFallback.calories * per100Ratio,
                aiProteinPer100g: aiFallback.proteinG * per100Ratio,
                aiFatPer100g: aiFallback.fatG * per100Ratio,
                aiCarbsPer100g: aiFallback.carbsG * per100Ratio,
                category: r.foodCategory,
              );

    return CalibratedNutrition(
      caloriesPer100g: caloriesPer100g,
      proteinPer100g: proteinPer100g,
      fatPer100g: fatPer100g,
      carbsPer100g: carbsPer100g,
      actualCalories: caloriesPer100g * servingG / 100,
      actualProteinG: proteinPer100g * servingG / 100,
      actualFatG: fatPer100g * servingG / 100,
      actualCarbsG: carbsPer100g * servingG / 100,
      foodItemId: 0, // 哨兵，调用方需 upsertAiRecognized 替换
      shouldUpdateFoodItem: false, // 哨兵分支由 upsertAiRecognized 处理
    );
  }
}

class CalibratedNutrition {
  final double caloriesPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;
  final double actualCalories;
  final double actualProteinG;
  final double actualFatG;
  final double actualCarbsG;
  /// M16.8：查库命中时的 foodItemId（> 0）；AI 兜底哨兵分支为 0
  final int foodItemId;
  /// M16.8：是否需要更新库 per100g（查库命中 + AI 偏差大时为 true）
  final bool shouldUpdateFoodItem;

  const CalibratedNutrition({
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
    required this.actualCalories,
    required this.actualProteinG,
    required this.actualFatG,
    required this.actualCarbsG,
    this.foodItemId = 0,
    this.shouldUpdateFoodItem = false,
  });
}
```

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test test/features/calibrated_nutrition_calculator_test.dart`
Expected: PASS — 12 个测试全过（8 原有 + 4 新增）

- [ ] **Step 5: Commit**

```bash
git add lib/features/recognize/calibrated_nutrition_calculator.dart test/features/calibrated_nutrition_calculator_test.dart
git commit -m "M16.8: CalibratedNutritionCalculator 支持查库命中分支差异检测"
```

---

## Task 3: food_item_repository 增加 updatePer100g 方法

**Files:**
- Modify: `lib/data/repositories/food_item_repository.dart`

- [ ] **Step 1: 写失败测试**

新建 `test/data/food_item_repository_update_per100g_test.dart`：

```dart
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late FoodItemRepository repo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    repo = FoodItemRepository(db);
    // 预置食物
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
      name: '番茄炒蛋',
      defaultServingG: 100,
      caloriesPer100g: 80, // 脏数据
      proteinPer100g: 6,
      fatPer100g: 10,
      carbsPer100g: 12,
      source: 'china_fct',
      sourceVersion: 'test',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  });

  tearDown(() async => db.close());

  test('updatePer100g 按 foodItemId 更新 4 项 per100g（不动其他字段）', () async {
    await repo.updatePer100g(
      foodItemId: 1,
      caloriesPer100g: 125, // AI 反算的新值
      proteinPer100g: 5,
      fatPer100g: 7.5,
      carbsPer100g: 10,
    );
    final food = await repo.findById(1);
    expect(food!.caloriesPer100g, 125);
    expect(food.proteinPer100g, 5);
    expect(food.fatPer100g, 7.5);
    expect(food.carbsPer100g, 10);
    // 其他字段不动
    expect(food.name, '番茄炒蛋');
    expect(food.defaultServingG, 100);
    expect(food.source, 'china_fct');
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test test/data/food_item_repository_update_per100g_test.dart`
Expected: FAIL — `updatePer100g 方法未定义`

- [ ] **Step 3: 实现 updatePer100g 方法**

读 `lib/data/repositories/food_item_repository.dart` 找到 class FoodItemRepository，添加方法：

```dart
  /// M16.8：按 foodItemId 更新 4 项 per100g（不动其他字段）
  /// 
  /// 用途：查库命中 + AI 偏差大时，用 AI 反算 per100g 纠正脏库。
  /// 仅更新营养字段，保留 name/source/version/created_at 等元数据。
  Future<void> updatePer100g({
    required int foodItemId,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double fatPer100g,
    required double carbsPer100g,
  }) async {
    await (db.foodItems.update()..where((f) => f.id.equals(foodItemId))).write(
      FoodItemsCompanion(
        caloriesPer100g: Value(caloriesPer100g),
        proteinPer100g: Value(proteinPer100g),
        fatPer100g: Value(fatPer100g),
        carbsPer100g: Value(carbsPer100g),
      ),
    );
  }
```

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test test/data/food_item_repository_update_per100g_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/food_item_repository.dart test/data/food_item_repository_update_per100g_test.dart
git commit -m "M16.8: FoodItemRepository 增加 updatePer100g 方法"
```

---

## Task 4: recognize_page writeCalibratedMealLog 接入查库命中分支

**Files:**
- Modify: `lib/features/recognize/recognize_page.dart`
- Test: `test/features/recognize_page_test.dart`（扩展）

- [ ] **Step 1: 写失败测试**

在 `test/features/recognize_page_test.dart` 追加：

```dart
  testWidgets('M16.8: 查库命中 + AI 偏差大时 actualCalories 用 AI 估算 + 更新库 per100g', (tester) async {
    // 库有"番茄炒蛋" per100g=80（脏数据）
    // AI 估 200g/250kcal（库值 160 vs AI 250，偏差 56% > 50%）
    // 期望：meal_log.actualCalories=250，food_item.caloriesPer100g 更新为 125
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
      name: '番茄炒蛋',
      defaultServingG: 100,
      caloriesPer100g: 80,
      proteinPer100g: 6,
      fatPer100g: 10,
      carbsPer100g: 12,
      source: 'china_fct',
      sourceVersion: 'test',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    final r = VisionRecognitionResult(
      dishName: '番茄炒蛋',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      estimatedCalories: 250,
      estimatedProteinG: 10,
      estimatedFatG: 15,
      estimatedCarbsG: 20,
      foodComponents: [],
      cookingMethod: 'stir_fry',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.0',
    );
    final lookupHit = NutritionResult(
      foodItemId: 1,
      calories: 160, // 80 * 200 / 100
      proteinG: 6,
      fatG: 10,
      carbsG: 12,
      oilG: 0,
    );
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 250,
      proteinG: 10,
      fatG: 15,
      carbsG: 20,
      oilG: 0,
    );

    final actualCalories = await RecognizePage.writeCalibratedMealLog(
      container: container,
      recognitionResult: r,
      singleNutrition: lookupHit,
      aiFallbackNutrition: aiFallback,
      compositeNutrition: null,
      servingG: 200,
      mealType: 'lunch',
      imagePath: null,
    );

    expect(actualCalories, closeTo(250, 0.5), reason: '查库命中 + AI 偏差大时用 AI 估算值');

    // food_item.per100g 应被更新为 AI 反算值 125
    final food = await db.foodItems.where().getSingle();
    expect(food.caloriesPer100g, closeTo(125, 0.5), reason: '库 per100g 应被 AI 反算值更新');

    // meal_log 应记 250
    final meals = await db.mealLogs.select().get();
    expect(meals.length, 1);
    expect(meals.first.actualCalories, closeTo(250, 0.5));
  });

  testWidgets('M16.8: 查库命中 + AI 偏差小时 actualCalories 用库值 + 不更新库', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
      name: '番茄炒蛋',
      defaultServingG: 100,
      caloriesPer100g: 80,
      proteinPer100g: 6,
      fatPer100g: 10,
      carbsPer100g: 12,
      source: 'china_fct',
      sourceVersion: 'test',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    final r = VisionRecognitionResult(
      dishName: '番茄炒蛋',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      estimatedCalories: 170, // AI 估 170，库值 160，偏差 6% < 50%
      estimatedProteinG: 7,
      estimatedFatG: 10,
      estimatedCarbsG: 13,
      foodComponents: [],
      cookingMethod: 'stir_fry',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.0',
    );
    final lookupHit = NutritionResult(
      foodItemId: 1,
      calories: 160,
      proteinG: 6,
      fatG: 10,
      carbsG: 12,
      oilG: 0,
    );
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 170,
      proteinG: 7,
      fatG: 10,
      carbsG: 13,
      oilG: 0,
    );

    final actualCalories = await RecognizePage.writeCalibratedMealLog(
      container: container,
      recognitionResult: r,
      singleNutrition: lookupHit,
      aiFallbackNutrition: aiFallback,
      compositeNutrition: null,
      servingG: 200,
      mealType: 'lunch',
      imagePath: null,
    );

    expect(actualCalories, closeTo(160, 0.5), reason: '偏差小用库值');

    final food = await db.foodItems.where().getSingle();
    expect(food.caloriesPer100g, 80, reason: '库 per100g 不更新');
  });
```

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test test/features/recognize_page_test.dart`
Expected: FAIL — 当前查库命中分支用 `n.calories * ratio`，actualCalories=160 不是 250

- [ ] **Step 3: 修改 writeCalibratedMealLog 查库命中分支**

读 `lib/features/recognize/recognize_page.dart` 当前 `writeCalibratedMealLog` 实现，修改查库命中分支（foodItemId > 0）调 `CalibratedNutritionCalculator.compute` 并传 `lookupHitNutrition`：

```dart
  @visibleForTesting
  static Future<double> writeCalibratedMealLog({
    required ProviderContainer container,
    required VisionRecognitionResult recognitionResult,
    required NutritionResult? singleNutrition,
    required NutritionResult? aiFallbackNutrition,
    required CompositeNutritionResult? compositeNutrition,
    required double servingG,
    required String mealType,
    required String? imagePath,
  }) async {
    final mealRepo = await container.read(mealLogRepoProvider.future);
    final foodRepo = await container.read(foodItemRepoProvider.future);

    int foodItemId;
    double actualCalories, actualProteinG, actualFatG, actualCarbsG;
    String? componentsSnapshotJson;

    // M16.8：查库命中分支也走 CalibratedNutritionCalculator（差异检测）
    if (singleNutrition != null && singleNutrition.foodItemId > 0 && aiFallbackNutrition != null) {
      final calibrated = CalibratedNutritionCalculator.compute(
        recognitionResult: recognitionResult,
        aiFallback: aiFallbackNutrition,
        servingG: servingG,
        lookupHitNutrition: singleNutrition,
      );
      foodItemId = calibrated.foodItemId;
      actualCalories = calibrated.actualCalories;
      actualProteinG = calibrated.actualProteinG;
      actualFatG = calibrated.actualFatG;
      actualCarbsG = calibrated.actualCarbsG;
      // M16.8：偏差大时更新库 per100g
      if (calibrated.shouldUpdateFoodItem) {
        await foodRepo.updatePer100g(
          foodItemId: calibrated.foodItemId,
          caloriesPer100g: calibrated.caloriesPer100g,
          proteinPer100g: calibrated.proteinPer100g,
          fatPer100g: calibrated.fatPer100g,
          carbsPer100g: calibrated.carbsPer100g,
        );
      }
    } else if (singleNutrition != null && singleNutrition.foodItemId > 0) {
      // 无 aiFallback（异常路径）：保留原 ratio 逻辑
      foodItemId = singleNutrition.foodItemId;
      final mid = recognitionResult.estimatedWeightGMid;
      final ratio = mid > 0 ? servingG / mid : 1.0;
      actualCalories = singleNutrition.calories * ratio;
      actualProteinG = singleNutrition.proteinG * ratio;
      actualFatG = singleNutrition.fatG * ratio;
      actualCarbsG = singleNutrition.carbsG * ratio;
    } else if (aiFallbackNutrition != null && aiFallbackNutrition.foodItemId == 0) {
      // AI 兜底哨兵分支（M16.6 原逻辑）
      final calibrated = CalibratedNutritionCalculator.compute(
        recognitionResult: recognitionResult,
        aiFallback: aiFallbackNutrition,
        servingG: servingG,
      );
      foodItemId = await foodRepo.upsertAiRecognized(
        name: recognitionResult.dishName,
        caloriesPer100g: calibrated.caloriesPer100g,
        proteinPer100g: calibrated.proteinPer100g,
        fatPer100g: calibrated.fatPer100g,
        carbsPer100g: calibrated.carbsPer100g,
        foodCategory: recognitionResult.foodCategory,
      );
      actualCalories = calibrated.actualCalories;
      actualProteinG = calibrated.actualProteinG;
      actualFatG = calibrated.actualFatG;
      actualCarbsG = calibrated.actualCarbsG;
    } else if (compositeNutrition != null) {
      // 复合菜分支（保持原逻辑）
      final packagePer100 = recognitionResult.hasPackageNutrition
          ? recognitionResult.computePackageNutritionPer100g(
              estimatedProteinG: recognitionResult.estimatedProteinG,
              estimatedFatG: recognitionResult.estimatedFatG,
              estimatedCarbsG: recognitionResult.estimatedCarbsG,
            )
          : null;
      final componentsSnapshot = jsonEncode({
        'components': compositeNutrition.componentHits.map((c) => {
          'name': c.name,
          'servingG': c.servingG,
          'calories': c.calories,
          'proteinG': c.proteinG,
          'fatG': c.fatG,
          'carbsG': c.carbsG,
        }).toList(),
      });
      componentsSnapshotJson = componentsSnapshot;
      foodItemId = await foodRepo.upsertAiRecognized(
        name: recognitionResult.dishName,
        caloriesPer100g: packagePer100?.$1 ?? 0,
        proteinPer100g: packagePer100?.$2 ?? 0,
        fatPer100g: packagePer100?.$3 ?? 0,
        carbsPer100g: packagePer100?.$4 ?? 0,
        foodCategory: recognitionResult.foodCategory,
        componentsJson: componentsSnapshot,
      );
      final mid = recognitionResult.estimatedWeightGMid;
      final ratio = mid > 0 ? servingG / mid : 1.0;
      actualCalories = compositeNutrition.calories * ratio;
      actualProteinG = compositeNutrition.proteinG * ratio;
      actualFatG = compositeNutrition.fatG * ratio;
      actualCarbsG = compositeNutrition.carbsG * ratio;
    } else {
      // 兜底：不应该到这里
      foodItemId = 0;
      actualCalories = 0;
      actualProteinG = 0;
      actualFatG = 0;
      actualCarbsG = 0;
    }

    await mealRepo.insertMealLog(
      date: todayYmd(),
      mealType: mealType,
      foodItemId: foodItemId,
      actualServingG: servingG,
      actualCalories: actualCalories,
      actualProteinG: actualProteinG,
      actualFatG: actualFatG,
      actualCarbsG: actualCarbsG,
      originalImagePath: imagePath,
      recognitionConfidence: recognitionResult.confidence,
      componentsSnapshotJson: componentsSnapshotJson,
    );

    return actualCalories;
  }
```

注意：实际修改时需保留原 writeCalibratedMealLog 的所有参数和现有逻辑（如 componentsSnapshotJson 在复合菜分支的赋值），上面的代码是完整替换参考。需根据当前实际代码调整。

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test test/features/recognize_page_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/recognize/recognize_page.dart test/features/recognize_page_test.dart
git commit -m "M16.8: recognize_page 查库命中分支接入差异检测 + 更新库 per100g"
```

---

## Task 5: CalibrationPage 查库命中分支预览与 onConfirm 同步

**Files:**
- Modify: `lib/features/recognize/calibration_page.dart`
- Test: `test/features/calibration_page_test.dart`（扩展）

- [ ] **Step 1: 写失败测试**

在 `test/features/calibration_page_test.dart` 追加查库命中 + AI 偏差大场景的预览测试：

```dart
  testWidgets('M16.8: 查库命中 + AI 偏差大预览用 AI 估算值（与记录一致）', (tester) async {
    // 库"番茄炒蛋" per100g=80，AI 估 200g/250kcal（偏差大）
    // 预览应显示 250（AI 估算），不是 160（库值）
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
      name: '番茄炒蛋',
      defaultServingG: 100,
      caloriesPer100g: 80,
      proteinPer100g: 6,
      fatPer100g: 10,
      carbsPer100g: 12,
      source: 'china_fct',
      sourceVersion: 'test',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));

    final r = VisionRecognitionResult(
      dishName: '番茄炒蛋',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      estimatedCalories: 250,
      estimatedProteinG: 10,
      estimatedFatG: 15,
      estimatedCarbsG: 20,
      foodComponents: [],
      cookingMethod: 'stir_fry',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.0',
    );
    final lookupHit = NutritionResult(
      foodItemId: 1,
      calories: 160,
      proteinG: 6,
      fatG: 10,
      carbsG: 12,
      oilG: 0,
    );
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 250,
      proteinG: 10,
      fatG: 15,
      carbsG: 20,
      oilG: 0,
    );

    double? capturedCalories;
    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: r,
        singleNutrition: lookupHit,
        aiFallbackNutrition: aiFallback,
        mealType: 'lunch',
        onConfirm: (servingG, cal, p, f, c) async {
          capturedCalories = cal;
        },
      ),
    ));
    await tester.pumpAndSettle();

    // 预览应显示 250（AI 估算）
    expect(find.textContaining('250'), findsWidgets,
        reason: '查库命中 + AI 偏差大预览应显示 AI 估算值 250');

    // 点确认
    final confirmBtn = find.text('确认');
    if (confirmBtn.evaluate().isNotEmpty) {
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();
      expect(capturedCalories, closeTo(250, 0.5), reason: 'onConfirm 传值应与预览一致');
    }
  });
```

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test test/features/calibration_page_test.dart`
Expected: FAIL — 当前查库命中分支用 `n.calories * ratio`，预览显示 160 不是 250

- [ ] **Step 3: 修改 calibration_page._computeSingleItemActual 查库命中分支**

读 `lib/features/recognize/calibration_page.dart` 的 `_computeSingleItemActual` 方法，修改查库命中分支（foodItemId > 0）调 `CalibratedNutritionCalculator.compute` 传 `lookupHitNutrition`：

```dart
  (double, double, double, double) _computeSingleItemActual(double servingG) {
    final n = _currentNutrition!;
    final r = widget.recognitionResult;

    // M16.8：查库命中分支也走差异检测（与 recognize_page 写库一致）
    if (n.foodItemId > 0 && widget.aiFallbackNutrition != null) {
      final calibrated = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: widget.aiFallbackNutrition!,
        servingG: servingG,
        lookupHitNutrition: n,
      );
      return (
        calibrated.actualCalories,
        calibrated.actualProteinG,
        calibrated.actualFatG,
        calibrated.actualCarbsG,
      );
    }

    // 兜底：原 ratio 逻辑（无 aiFallback 时）
    final mid = r.estimatedWeightGMid;
    final ratio = mid > 0 ? servingG / mid : 1.0;
    return (
      n.calories * ratio,
      n.proteinG * ratio,
      n.fatG * ratio,
      n.carbsG * ratio,
    );
  }
```

注意：`_computeSingleItemActual` 当前的 AI 兜底分支（foodItemId == 0）已经在 M16.6 调 CalibratedNutritionCalculator，保留不动。本次只改查库命中分支。

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test test/features/calibration_page_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/recognize/calibration_page.dart test/features/calibration_page_test.dart
git commit -m "M16.8: CalibrationPage 查库命中分支预览与记录同步用差异检测"
```

---

## Task 6: multi_dish_page _recordAll 查库命中分支接入差异检测

**Files:**
- Modify: `lib/features/recognize/multi_dish_page.dart`
- Test: `test/features/multi_dish_page_test.dart`（扩展）

- [ ] **Step 1: 写失败测试**

在 `test/features/multi_dish_page_test.dart` 追加：

```dart
  testWidgets('M16.8: 查库命中 + AI 偏差大时 actualCalories 用 AI 估算 + 更新库', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // 库"番茄炒蛋" per100g=80（脏数据）
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
      name: '番茄炒蛋',
      defaultServingG: 100,
      caloriesPer100g: 80,
      proteinPer100g: 6,
      fatPer100g: 10,
      carbsPer100g: 12,
      source: 'china_fct',
      sourceVersion: 'test',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    final r = VisionRecognitionResult(
      dishName: '番茄炒蛋',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      estimatedCalories: 250, // AI 估 250，库值 160，偏差 56% > 50%
      estimatedProteinG: 10,
      estimatedFatG: 15,
      estimatedCarbsG: 20,
      foodComponents: [],
      cookingMethod: 'stir_fry',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.0',
    );
    final lookupHit = NutritionResult(
      foodItemId: 1,
      calories: 160,
      proteinG: 6,
      fatG: 10,
      carbsG: 12,
      oilG: 0,
    );
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 250,
      proteinG: 10,
      fatG: 15,
      carbsG: 20,
      oilG: 0,
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: MultiDishPage(
        mainDish: r,
        mainSingle: lookupHit,
        mainAiFallback: aiFallback, // 新参数（M16.8）
        additionalItems: [],
        mealType: 'lunch',
      )),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部记录'));
    await tester.pumpAndSettle();

    final meals = await db.mealLogs.select().get();
    expect(meals.length, 1);
    expect(meals.first.actualCalories, closeTo(250, 0.5),
        reason: '查库命中 + AI 偏差大时用 AI 估算值');

    final food = await db.foodItems.where().getSingle();
    expect(food.caloriesPer100g, closeTo(125, 0.5),
        reason: '库 per100g 应被 AI 反算值更新');
  });
```

注意：测试中 `mainAiFallback` 是新参数，需先在 MultiDishPage 加。如果加参数改动过大，可以改为通过 ProviderContainer override recognize_controller 的方式注入 aiFallback（取决于现有架构）。读 `multi_dish_page.dart` 当前构造参数确认。

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test test/features/multi_dish_page_test.dart`
Expected: FAIL — 当前查库命中分支用 `_calcNutrition`（库值 × ratio），actualCalories=160 不是 250

- [ ] **Step 3: 修改 multi_dish_page _recordAll 查库命中分支**

读 `lib/features/recognize/multi_dish_page.dart` 的 `_recordAll` 和 `_calcNutrition`，修改查库命中分支调 `CalibratedNutritionCalculator.compute` 传 `lookupHitNutrition`。

如果 multi_dish_page 当前没有 `aiFallbackNutrition` 参数，需要从 recognize_page 传入（修改构造参数 + 调用方）。

```dart
  // _recordAll 内查库命中分支（_currentSingles[i].foodItemId > 0）
  if (n.foodItemId > 0 && widget.aiFallbackForIndex != null) {
    final aiFallback = widget.aiFallbackForIndex!(i);
    if (aiFallback != null) {
      final calibrated = CalibratedNutritionCalculator.compute(
        recognitionResult: dish,
        aiFallback: aiFallback,
        servingG: serving,
        lookupHitNutrition: n,
      );
      // 用 calibrated.actualXxx 写 meal_log
      // 若 calibrated.shouldUpdateFoodItem，调 foodRepo.updatePer100g
      // ...
    }
  }
```

注意：实际实现需根据 multi_dish_page 当前结构调整。关键是不破坏现有 `_calcNutrition` 的预览逻辑（预览也要同步用差异检测，否则预览与记录又会脱节）。

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test test/features/multi_dish_page_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/recognize/multi_dish_page.dart test/features/multi_dish_page_test.dart
git commit -m "M16.8: multi_dish_page 查库命中分支接入差异检测"
```

---

## Task 7: offline_queue_controller 接入 CalibratedNutritionCalculator

**Files:**
- Modify: `lib/features/offline/offline_queue_controller.dart`

- [ ] **Step 1: 写失败测试**

在 `test/features/offline_queue_test.dart` 追加查库命中 + AI 偏差大场景：

```dart
  test('M16.8: 离线回补查库命中 + AI 偏差大时用 AI 估算 + 更新库', () async {
    // 库"番茄炒蛋" per100g=80，AI 估 200g/250kcal
    // 离线回补时应与前台一致：actualCalories=250, food_item.caloriesPer100g=125
    // ... 完整测试 setup 参考现有 offline_queue_test.dart
    expect(mealLog.actualCalories, closeTo(250, 0.5));
    expect(foodItem.caloriesPer100g, closeTo(125, 0.5));
  });
```

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test test/features/offline_queue_test.dart`
Expected: FAIL

- [ ] **Step 3: 修改 offline_queue_controller 替换手写品类校准**

读 `lib/features/offline/offline_queue_controller.dart` L200-310，把手写的品类校准逻辑替换为调 `CalibratedNutritionCalculator.compute`，查库命中分支也传 `lookupHitNutrition`。

```dart
  // 替换 L201-249 的手写逻辑
  final calibrated = CalibratedNutritionCalculator.compute(
    recognitionResult: r,
    aiFallback: aiFallback,
    servingG: mid, // 后台用 mid 不调整
    lookupHitNutrition: nutrition, // 查库命中时传
  );
  // 用 calibrated.actualXxx 写 meal_log
  // 若 calibrated.shouldUpdateFoodItem，调 foodRepo.updatePer100g
  // 若 calibrated.foodItemId == 0（哨兵），调 upsertAiRecognized
```

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test test/features/offline_queue_test.dart test/features/offline_queue_composite_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/offline/offline_queue_controller.dart test/features/offline_queue_test.dart
git commit -m "M16.8: offline_queue_controller 接入 CalibratedNutritionCalculator 三路径统一"
```

---

## Task 8: recognize_page.dart:624 改菜名重试路径改调 writeCalibratedMealLog

**Files:**
- Modify: `lib/features/recognize/recognize_page.dart`（_showNotFoundDialog onConfirm）

- [ ] **Step 1: 写失败测试**

在 `test/features/recognize_page_test.dart` 追加：

```dart
  testWidgets('M16.8: 改菜名重试命中库时补齐 recognitionConfidence + componentsSnapshotJson', (tester) async {
    // 改菜名重试命中库后，meal_log 应有 recognitionConfidence 和 componentsSnapshotJson 字段
    // ... 完整测试 setup
    expect(mealLog.recognitionConfidence, isNotNull, reason: '改菜名重试也应记录识别置信度');
  });
```

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test test/features/recognize_page_test.dart`
Expected: FAIL — 当前改菜名重试路径不传 recognitionConfidence

- [ ] **Step 3: 修改 _showNotFoundDialog onConfirm 改调 writeCalibratedMealLog**

读 `lib/features/recognize/recognize_page.dart` L614-641，把内联 `mealRepo.insertMealLog` 改为调 `RecognizePage.writeCalibratedMealLog`：

```dart
  onConfirm: (servingG, calories, protein, fat, carbs, {componentsSnapshot}) async {
    final actualCalories = await RecognizePage.writeCalibratedMealLog(
      container: ref,
      recognitionResult: result, // 改菜名后的 recognitionResult
      singleNutrition: nutrition, // 查库命中
      aiFallbackNutrition: aiFallback, // AI 兜底（如果有）
      compositeNutrition: null,
      servingG: servingG,
      mealType: mealType,
      imagePath: imagePath,
    );
    // ... toast 提示
  },
```

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test test/features/recognize_page_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/recognize/recognize_page.dart test/features/recognize_page_test.dart
git commit -m "M16.8: 改菜名重试路径改调 writeCalibratedMealLog 补齐字段"
```

---

## Task 9: 全量回归验证

**Files:**
- 无修改，仅验证

- [ ] **Step 1: flutter analyze**

Run: `export PATH=/tmp/flutter/bin:$PATH && flutter analyze`
Expected: No issues found

- [ ] **Step 2: flutter test 全量**

Run: `flutter test`
Expected: All tests passed（911 + 新增 ~12 测试）

- [ ] **Step 3: 验证 6 条硬约束**

1. build.gradle.kts `isMinifyEnabled=false` + `isShrinkResources=false` 未变
2. meal_log.food_item_id 哨兵写库前调 upsertAiRecognized（M16.8 查库命中分支 foodItemId > 0 不需 upsert）
3. AI 兜底三路径全覆盖（recognize_page / multi_dish_page / offline_queue_controller 都用 CalibratedNutritionCalculator）
4. per100g 反算基于 estimatedWeightGMid（calculator 内部 `mid = r.estimatedWeightGMid`）
5. SecureConfigStore 无 instance 静态属性
6. initSentryAndRunApp 命名参数

- [ ] **Step 4: 验证 M16.2~M16.7 修复区域无回归**

确认相关测试全过：calibrated_nutrition_calculator_test / recognize_page_test / multi_dish_page_test / calibration_page_test / offline_queue_test / decimal_input_keyboard_test / icon_button_accessibility_test / manual_switch_confirmation_test / typography_ellipsis_test

---

## Task 10: 发布准备

**Files:**
- Modify: `pubspec.yaml`
- Modify: `HANDOFF.md`

- [ ] **Step 1: bump 版本**

`pubspec.yaml`: `0.18.6+25` → `0.18.7+26`

- [ ] **Step 2: 更新 HANDOFF.md**

更新第 2 节当前状态 + 新增 M16.8 章节

- [ ] **Step 3: commit + push + tag**

```bash
git add pubspec.yaml HANDOFF.md
git commit -m "M16.8: 营养值不一致深度修复（v0.18.7）—— 查库命中差异检测 + 品类校准只替换 calories + 三路径统一"
git push origin trae/agent-wX1X6Q
git tag v0.18.7
git push origin v0.18.7
```

---

## Self-Review

### 1. Spec coverage

- ✅ 根因 A（查库命中忽略 AI）：Task 2/4/5/6/7 全部接入差异检测
- ✅ 根因 B（品类校准 4 项全替换）：Task 1 修改 calibrate 只替换 calories
- ✅ 根因 C（改菜名重试绕过）：Task 8 改调 writeCalibratedMealLog
- ✅ 三路径统一：Task 4/6/7 都用 CalibratedNutritionCalculator
- ✅ 预览=记录：Task 5 CalibrationPage 同步用差异检测

### 2. Placeholder scan

- 无 "TBD" / "TODO" / "implement later"
- Task 6 Step 3 的"实际实现需根据 multi_dish_page 当前结构调整"——这是因为 multi_dish_page 是否有 aiFallback 参数需读代码确认，不是 placeholder，是实施时的灵活指引

### 3. Type consistency

- `CalibratedNutrition` 增加 `foodItemId` 和 `shouldUpdateFoodItem` 字段，在 Task 2 定义，Task 4/5/6/7 使用——一致
- `CalibratedNutritionCalculator.compute` 增加 `lookupHitNutrition` 可选参数——一致
- `FoodItemRepository.updatePer100g` 方法签名——Task 3 定义，Task 4/6/7 调用——一致
- `writeCalibratedMealLog` 参数——Task 4 定义，Task 8 调用——一致

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-05-fix-nutrition-value-mismatch-m16-8.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
