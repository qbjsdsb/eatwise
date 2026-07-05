# 减小库值重要性——AI 绝对优先（M16.9）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把食物库（food_item）值在营养计算中的重要性占比大幅降低——查库命中分支（foodItemId > 0）改为 **AI 估算绝对优先**，库值仅作 sanity check 兜底（AI 离谱时兜底）；同步修复复合菜残留路径（multi_dish_page composite 分支 + calibration_page 老 ratio 逻辑），让三路径真正统一。

**Architecture:** 单点核心改动 + 路径同步——(1) 重写 `CalibratedNutritionCalculator.compute` 查库命中分支：AI 估算有效（per100g ∈ [0, 900]）时始终用 AI 反算 per100g 写库 + 用 AI 值记 meal_log；AI 无效（null / 负 / >900）时用库值兜底。(2) `multi_dish_page._computeLookupHitCalibrated` 扩展支持 compositeNutrition，复合菜组分累加库值 vs AI 整菜估算走差异检测。(3) `calibration_page` L465-474 残留 else 分支加注释 + 兜底用库值（此路径在 M16.8 后不应触发，因主路径已传 aiFallbackNutrition）。(4) 三路径（recognize_page / multi_dish_page / offline_queue_controller）自动继承新逻辑（共用 calculator）。(5) 严肃 commit + push + tag v0.18.8。

**Tech Stack:** Flutter 3.x / Riverpod / Drift / TDD（RED→GREEN→REFACTOR）

---

## 当前状态分析（M16.8 之后）

### 核心决策点：`calibrated_nutrition_calculator.dart` L49-97

当前逻辑（M16.8 差异检测，阈值 50%）：

```dart
if (lookupHitNutrition != null && lookupHitNutrition.foodItemId > 0) {
  final dbPer100Calories = lookupHitNutrition.calories * per100Ratio;
  final aiPer100Calories = aiFallback.calories * per100Ratio;
  // ... 其他宏量同理
  final diffRatio = dbPer100Calories > 0
      ? (aiPer100Calories - dbPer100Calories).abs() / dbPer100Calories
      : (aiPer100Calories > 0 ? 1.0 : 0.0);
  if (diffRatio > 0.5) {
    // 偏差大：用 AI 反算 per100g 写库 + 用 AI 值记录
    return CalibratedNutrition(..., shouldUpdateFoodItem: true);
  } else {
    // 偏差小：用库 per100g（库值胜出）
    return CalibratedNutrition(..., shouldUpdateFoodItem: false);
  }
}
```

**问题**：阈值 50% 太宽松——AI 估算 250 vs 库值 160（偏差 56%）才用 AI；AI 估算 200 vs 库值 160（偏差 25%）仍用库值。用户感知"AI 准但记录不对"仍存在于偏差 20%-50% 区间。

### 残留路径 1：`calibration_page.dart` L465-474

```dart
// 查库命中但无 aiFallback（旧调用方）：DB per100g 已是真实值，按 servingG/mid 比例换算
final mid = r.estimatedWeightGMid;
final ratio = mid > 0 ? servingG / mid : 1.0;
return (n.calories * ratio, n.proteinG * ratio, n.fatG * ratio, n.carbsG * ratio);
```

M16.8 主路径已传 `aiFallbackNutrition`（recognize_page L466-467 / L663-664），此 else 分支理论上不触发。但代码残留，无差异检测。

### 残留路径 2：`multi_dish_page.dart` L478-486 / L510-518（复合菜 composite 分支）

```dart
if (widget.mainComposite != null) {
  final n = widget.mainComposite!;
  return (n.calories * ratio, n.proteinG * ratio, n.fatG * ratio, n.carbsG * ratio);
}
```

复合菜 `lookupCompositeDish` 返回组分累加库值，无差异检测。AI 整菜估算（r.estimatedCalories）完全被丢弃。

### 残留路径 3：`offline_queue_controller.dart` L212-219（无 AI 估算旧 prompt）

```dart
} else if (nutrition != null) {
  // 无 AI 估算（旧 prompt）：保留原 ratio 逻辑
  foodItemId = nutrition.foodItemId;
  actualCalories = nutrition.calories;
  // ...
}
```

此分支为旧 prompt（v1.4 之前）兼容，新 prompt 不走。保留不动。

---

## Proposed Changes

### 决策表

| 场景 | 当前行为（M16.8） | 新行为（M16.9 AI 绝对优先） |
|------|------|------|
| 单品查库命中 + AI 有效 | 偏差 > 50% 用 AI；≤ 50% 用库值 | **始终用 AI**（写库 + 记录） |
| 单品查库命中 + AI 无效（null/负/>900 per100g） | 不存在此场景 | **用库值兜底**（不写库） |
| 复合菜查库命中（组分累加）+ AI 有效 | 用组分累加库值（无差异检测） | **始终用 AI 整菜估算**（记录，不写库 per100g） |
| 复合菜查库命中 + AI 无效 | 用组分累加库值 | **用组分累加库值**（兜底） |
| 单品查库未命中 + AI 估算（哨兵） | 品类校准 + upsertAiRecognized | 不变 |
| 改菜名重试 + 查库命中 | M16.8 已走差异检测 | 继承新逻辑（AI 绝对优先） |

### sanity check 阈值

- AI per100g calories 有效区间：**[0, 900]**
  - 上限 900：纯脂肪油 889，solid clamp 上限 900（`food_category_defaults.dart` L112）
  - AI per100g > 900 视为离谱（如 AI 把水估成 5000 kcal/100g）
- AI estimatedCalories 为 null：无 AI 估算（旧 prompt），走原 ratio 兜底
- AI per100g < 0：无效（不可能负热量，除水外）

### shouldUpdateFoodItem 逻辑（AI 绝对优先下）

- AI 有效 + diffRatio > 0.05（5% 差异）→ `shouldUpdateFoodItem = true`（避免无意义写库）
- AI 有效 + diffRatio ≤ 0.05 → `shouldUpdateFoodItem = false`（AI 与库一致，不写库）
- AI 无效 → `shouldUpdateFoodItem = false`（用库值兜底，不更新库）

---

## File Structure

**修改文件**：
- `lib/features/recognize/calibrated_nutrition_calculator.dart` — 查库命中分支重写为 AI 绝对优先
- `lib/features/recognize/multi_dish_page.dart` — `_computeLookupHitCalibrated` 扩展支持 compositeNutrition
- `lib/features/recognize/calibration_page.dart` — L465-474 残留 else 分支加注释 + 兜底用库值
- `pubspec.yaml` — bump 0.18.7+26 → 0.18.8+27
- `HANDOFF.md` — 回填 M16.9 章节

**测试文件**：
- `test/features/calibrated_nutrition_calculator_test.dart` — 重写查库命中分支测试（AI 绝对优先）+ 新增 sanity check 测试
- `test/features/multi_dish_page_test.dart` — 新增复合菜 AI 优先测试
- `test/features/recognize_page_test.dart` — 更新偏差小用 AI 测试（原"用库值"改为"用 AI"）

---

## Task 1: RED 测试 — AI 绝对优先 + sanity check 兜底

**Files:**
- Test: `test/features/calibrated_nutrition_calculator_test.dart`

- [ ] **Step 1: 重写查库命中分支测试**

替换原"偏差小用库值"测试，新增 AI 绝对优先 + sanity check 测试。在 `test/features/calibrated_nutrition_calculator_test.dart` 末尾追加（保留原有哨兵分支测试不动）：

```dart
  // M16.9：AI 绝对优先——查库命中分支重写
  // 原 M16.8 的"偏差小用库值"测试改为"偏差小也用 AI"（AI 绝对优先）
  group('M16.9 AI 绝对优先（查库命中分支）', () {
    const r = VisionRecognitionResult(
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
      foodCategory: 'solid',
    );
    final lookupHit = NutritionResult(
      foodItemId: 1,
      calories: 160, // 80 * 200 / 100（库 per100g=80）
      proteinG: 6,
      fatG: 10,
      carbsG: 12,
      oilG: 0,
    );
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 170, // AI 估 170，库值 160，偏差 6%（原 M16.8 用库值，M16.9 用 AI）
      proteinG: 7,
      fatG: 10,
      carbsG: 13,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );

    test('AI 与库偏差小（6%）也用 AI 估算（AI 绝对优先）', () {
      final calibrated = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiFallback,
        servingG: 200,
        lookupHitNutrition: lookupHit,
      );
      // AI per100g = 170 * 100 / 200 = 85
      expect(calibrated.caloriesPer100g, closeTo(85, 0.5),
          reason: 'AI 绝对优先：偏差小也用 AI 反算 per100g');
      expect(calibrated.actualCalories, closeTo(170, 0.5),
          reason: 'actualCalories 用 AI 估算值（170），不用库值（160）');
      expect(calibrated.actualProteinG, closeTo(7, 0.5),
          reason: '蛋白用 AI 估算值');
      expect(calibrated.foodItemId, 1, reason: 'foodItemId 保留查库命中 id');
      // 偏差 6% > 5% → shouldUpdateFoodItem=true（更新库 per100g 为 AI 反算值）
      expect(calibrated.shouldUpdateFoodItem, true,
          reason: '偏差 > 5% 时更新库 per100g');
    });

    test('AI 与库完全一致（diffRatio=0）用 AI 但不写库（避免无意义写库）', () {
      final aiSameAsDb = NutritionResult(
        foodItemId: 0,
        calories: 160, // 与库值完全一致
        proteinG: 6,
        fatG: 10,
        carbsG: 12,
        oilG: 0,
        source: NutritionSource.aiEstimate,
      );
      final calibrated = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiSameAsDb,
        servingG: 200,
        lookupHitNutrition: lookupHit,
      );
      expect(calibrated.caloriesPer100g, closeTo(80, 0.5),
          reason: 'AI per100g = 160 * 100 / 200 = 80（与库一致）');
      expect(calibrated.actualCalories, closeTo(160, 0.5));
      expect(calibrated.shouldUpdateFoodItem, false,
          reason: 'diffRatio=0 ≤ 5% 时不写库（无意义）');
    });

    test('AI per100g 离谱（>900）时用库值兜底 + 不更新库', () {
      // AI 估 2000 kcal（per100g = 2000 * 100 / 200 = 1000 > 900 离谱）
      final aiAbsurd = NutritionResult(
        foodItemId: 0,
        calories: 2000,
        proteinG: 50,
        fatG: 100,
        carbsG: 200,
        oilG: 0,
        source: NutritionSource.aiEstimate,
      );
      final calibrated = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiAbsurd,
        servingG: 200,
        lookupHitNutrition: lookupHit,
      );
      // 库 per100g = 160 * 100 / 200 = 80
      expect(calibrated.caloriesPer100g, closeTo(80, 0.5),
          reason: 'AI 离谱时用库 per100g 兜底');
      expect(calibrated.actualCalories, closeTo(160, 0.5),
          reason: 'actualCalories 用库值（160）');
      expect(calibrated.shouldUpdateFoodItem, false,
          reason: 'AI 离谱时不更新库');
    });

    test('AI per100g 负值时用库值兜底', () {
      final aiNegative = NutritionResult(
        foodItemId: 0,
        calories: -50, // 负值
        proteinG: 0,
        fatG: 0,
        carbsG: 0,
        oilG: 0,
        source: NutritionSource.aiEstimate,
      );
      final calibrated = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiNegative,
        servingG: 200,
        lookupHitNutrition: lookupHit,
      );
      expect(calibrated.caloriesPer100g, closeTo(80, 0.5),
          reason: 'AI 负值时用库 per100g 兜底');
      expect(calibrated.shouldUpdateFoodItem, false);
    });

    test('用户调滑块 servingG=100 时 actualCalories 按 AI per100g 缩放', () {
      final calibrated = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiFallback, // AI 170，per100g=85
        servingG: 100, // 用户调小一半
        lookupHitNutrition: lookupHit,
      );
      // AI per100g=85，servingG=100 → actualCalories = 85 * 100 / 100 = 85
      expect(calibrated.caloriesPer100g, closeTo(85, 0.5));
      expect(calibrated.actualCalories, closeTo(85, 0.5),
          reason: '用户调滑块后 actualCalories = AI per100g * servingG / 100');
    });
  });
```

- [ ] **Step 2: 运行测试验证失败**

Run: `export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/calibrated_nutrition_calculator_test.dart`
Expected: FAIL — 原 M16.8 逻辑偏差小用库值，新测试期望用 AI

- [ ] **Step 3: 删除原 M16.8 "偏差小用库值"测试**

在 `test/features/calibrated_nutrition_calculator_test.dart` 中找到 `M16.8: 查库命中 + AI 偏差小时 actualCalories 用库值 + 不更新库` 测试（约 L439-484），删除整个 test 块（被 M16.9 "AI 与库偏差小也用 AI"替代）。

同步更新 `test/features/recognize_page_test.dart` 中的 `M16.8: 查库命中 + AI 偏差小时 actualCalories 用库值 + 不更新库` 测试（约 L278-349）——改为 `M16.9: 查库命中 + AI 偏差小时 actualCalories 用 AI 估算（AI 绝对优先）`：

```dart
  test('M16.9: 查库命中 + AI 偏差小时 actualCalories 用 AI 估算（AI 绝对优先）', () async {
    // 库 per100g=80, AI 估 200g/170kcal（库值 160 vs AI 170，偏差 6%）
    // M16.9：AI 绝对优先，偏差小也用 AI 估算 + 更新库 per100g 为 AI 反算值（85）
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

    const r = VisionRecognitionResult(
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
      foodCategory: 'solid',
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
      source: NutritionSource.aiEstimate,
    );

    final actualCalories = await RecognizePage.writeCalibratedMealLog(
      foodRepo: foodRepo,
      mealRepo: mealRepo,
      result: r,
      singleNutrition: lookupHit,
      aiFallbackNutrition: aiFallback,
      compositeNutrition: null,
      mealType: 'lunch',
      servingG: 200,
      calories: 160,
      protein: 6,
      fat: 10,
      carbs: 12,
      componentsSnapshot: null,
      imagePath: null,
    );

    expect(actualCalories, closeTo(170, 0.5),
        reason: 'M16.9 AI 绝对优先：偏差小也用 AI 估算值（170）');

    // food_item.per100g 应被更新为 AI 反算值 85（= 170 * 100 / 200）
    final foods = await db.foodItems.select().get();
    expect(foods.first.caloriesPer100g, closeTo(85, 0.5),
        reason: '库 per100g 应被 AI 反算值（85）更新');

    // meal_log 应记 170（与 reasoning 一致）
    final meals = await db.mealLogs.select().get();
    expect(meals.first.actualCalories, closeTo(170, 0.5));
  });
```

- [ ] **Step 4: 同步更新 `multi_dish_page_test.dart` 和 `offline_queue_test.dart` 中偏差小测试**

搜索 `multi_dish_page_test.dart` 和 `offline_queue_test.dart` 中"偏差小"或"偏差 ≤ 50%"相关测试断言，更新为 M16.9 AI 绝对优先语义（偏差小也用 AI）。如果没有偏差小测试，跳过此步。

- [ ] **Step 5: 运行测试验证全部失败（除哨兵分支测试）**

Run: `flutter test test/features/calibrated_nutrition_calculator_test.dart test/features/recognize_page_test.dart`
Expected: FAIL — 新测试期望 AI 绝对优先，原实现是偏差小用库值

---

## Task 2: GREEN — 重写 CalibratedNutritionCalculator 查库命中分支

**Files:**
- Modify: `lib/features/recognize/calibrated_nutrition_calculator.dart` L49-97

- [ ] **Step 1: 重写查库命中分支为 AI 绝对优先 + sanity check 兜底**

替换 `lib/features/recognize/calibrated_nutrition_calculator.dart` L48-98 整段（从 `// M16.8：查库命中分支` 注释到 `}` 闭合 if 块）：

```dart
    // M16.9：查库命中分支（foodItemId > 0）—— AI 估算绝对优先
    // 策略：AI 估算有效（per100g ∈ [0, 900]）时始终用 AI 反算 per100g 写库 + 用 AI 值记 meal_log
    //       AI 估算无效（null / 负 / >900）时用库值兜底（不更新库）
    // shouldUpdateFoodItem：AI 有效 + diffRatio > 5% 时为 true（避免无意义写库）
    if (lookupHitNutrition != null && lookupHitNutrition.foodItemId > 0) {
      // lookupHit.calories 已是 per100g × mid / 100（参见 nutrition_lookup.dart）
      // 反算库 per100g = lookupHit.calories * 100 / mid = lookupHit.calories * per100Ratio
      final dbPer100Calories = lookupHitNutrition.calories * per100Ratio;
      final dbPer100Protein = lookupHitNutrition.proteinG * per100Ratio;
      final dbPer100Fat = lookupHitNutrition.fatG * per100Ratio;
      final dbPer100Carbs = lookupHitNutrition.carbsG * per100Ratio;

      // AI 估算 per100g = aiFallback.xxx * 100 / mid
      final aiPer100Calories = aiFallback.calories * per100Ratio;
      final aiPer100Protein = aiFallback.proteinG * per100Ratio;
      final aiPer100Fat = aiFallback.fatG * per100Ratio;
      final aiPer100Carbs = aiFallback.carbsG * per100Ratio;

      // sanity check：AI per100g 有效区间 [0, 900]
      // 上限 900：纯脂肪油 889，solid clamp 上限 900（food_category_defaults.dart L112）
      // AI per100g > 900 视为离谱（如 AI 把水估成 5000 kcal/100g）
      final aiValid = aiPer100Calories >= 0 && aiPer100Calories <= 900;

      if (!aiValid) {
        // AI 离谱：用库值兜底，不更新库
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

      // AI 绝对优先：始终用 AI 反算 per100g 写库 + 用 AI 值记 meal_log
      // shouldUpdateFoodItem：仅当 AI 与库有 > 5% 差异时才写库（避免无意义写库）
      final diffRatio = dbPer100Calories > 0
          ? (aiPer100Calories - dbPer100Calories).abs() / dbPer100Calories
          : (aiPer100Calories > 0 ? 1.0 : 0.0);
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
        shouldUpdateFoodItem: diffRatio > 0.05,
      );
    }
```

- [ ] **Step 2: 更新文件头部注释**

更新 `lib/features/recognize/calibrated_nutrition_calculator.dart` L1-25 注释，把"M16.8 差异检测"改为"M16.9 AI 绝对优先"：

```dart
/// AI 兜底哨兵路径（foodItemId=0）+ 查库命中路径（foodItemId>0）下，
/// 用品类校准后的 per100g 计算 actualNutrition。
///
/// M16.9：查库命中分支改为 AI 估算绝对优先——AI 估算有效（per100g ∈ [0, 900]）时
/// 始终用 AI 反算 per100g 写库 + 用 AI 值记 meal_log；AI 无效（null / 负 / >900）时
/// 用库值兜底。库值重要性大幅降低，仅作 sanity check 兜底。
///
/// 三路径（recognize_page / multi_dish_page / offline_queue_controller）共用此方法，
/// 保证 actualCalories 与 AI 估算一致（用户感知"AI 准=记录准"）。
///
/// 逻辑：
/// 1. 查库命中分支（lookupHitNutrition != null && foodItemId > 0）：
///    - AI 有效（per100g ∈ [0, 900]）：用 AI 反算 per100g 写库 + 用 AI 值记录
///      shouldUpdateFoodItem：diffRatio > 5% 时为 true（避免无意义写库）
///    - AI 无效：用库值兜底，不更新库
/// 2. AI 兜底哨兵分支（foodItemId == 0）：
///    - 有包装数据且包装换算宏量非全 0 → 用 packagePer100（精确值，不走品类校准）
///    - 无包装数据 / 包装换算宏量全 0 → 用 FoodCategoryDefaults.calibrate 校准 per100g
/// 3. actualCalories/ProteinG/FatG/CarbsG = 校准后 per100g * servingG / 100
```

- [ ] **Step 3: 运行测试验证通过**

Run: `flutter test test/features/calibrated_nutrition_calculator_test.dart`
Expected: PASS — 所有查库命中分支测试通过（AI 绝对优先 + sanity check）

- [ ] **Step 4: 运行 recognize_page / multi_dish_page / offline_queue 测试**

Run: `flutter test test/features/recognize_page_test.dart test/features/multi_dish_page_test.dart test/features/offline_queue_test.dart`
Expected: PASS（M16.8 偏差大用 AI 测试仍通过；M16.9 偏差小用 AI 测试通过）

- [ ] **Step 5: Commit**

```bash
git add lib/features/recognize/calibrated_nutrition_calculator.dart test/features/calibrated_nutrition_calculator_test.dart test/features/recognize_page_test.dart test/features/multi_dish_page_test.dart test/features/offline_queue_test.dart
git commit -m "M16.9: AI 估算绝对优先——查库命中分支重写 + sanity check 兜底

减小食物库值在营养计算中的重要性占比：
- 查库命中分支（foodItemId>0）改为 AI 绝对优先
- AI 估算有效（per100g ∈ [0, 900]）时始终用 AI 反算 per100g 写库 + 用 AI 值记 meal_log
- AI 估算无效（null/负/>900）时用库值兜底（不更新库）
- shouldUpdateFoodItem：diffRatio > 5% 时为 true（避免无意义写库）

原 M16.8 差异检测阈值 50% 太宽松——偏差 20%-50% 区间仍用库值，
用户感知'AI 准但记录不对'。M16.9 让 AI 估算始终胜出（除离谱值），
库值降级为 sanity check 兜底。

测试：原'偏差小用库值'改为'偏差小也用 AI'；新增 sanity check（per100g>900/负值）兜底测试。
三路径（recognize_page/multi_dish_page/offline_queue）共用 calculator 自动继承新逻辑。"
```

---

## Task 3: RED 测试 — 复合菜分支接入 AI 绝对优先

**Files:**
- Test: `test/features/multi_dish_page_test.dart`

- [ ] **Step 1: 新增复合菜 AI 优先测试**

在 `test/features/multi_dish_page_test.dart` 末尾追加：

```dart
  testWidgets('M16.9: 复合菜查库命中 + AI 整菜估算有效时用 AI 值记录', (tester) async {
    // 复合菜 lookupCompositeDish 返回组分累加库值（如米饭+宫保鸡丁=400 kcal）
    // AI 整菜估算 estimatedCalories=500（偏差 25%，原 M16.8 用组分累加库值，M16.9 用 AI）
    // 期望：meal_log.actualCalories=500（AI 整菜估算），不写库 per100g（复合菜 per100g=0 占位）
    // ... 完整测试 setup（参考现有 multi_dish_page_test.dart 复合菜测试结构）
    // 关键断言：
    // expect(mealLog.actualCalories, closeTo(500, 0.5), reason: '复合菜 AI 绝对优先：用 AI 整菜估算');
    // expect(foodItem.caloriesPer100g, 0, reason: '复合菜 per100g 保持 0 占位，不更新');
  });
```

注：完整测试 setup 参考现有 `multi_dish_page_test.dart` 中复合菜测试结构（lookupCompositeDish mock + widget pump + 点击记录按钮）。如果复合菜测试 setup 过于复杂，可降级为对 `_computeLookupHitCalibrated` 的单元测试（扩展支持 compositeNutrition 后）。

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test test/features/multi_dish_page_test.dart`
Expected: FAIL — 当前复合菜分支用 n.calories * ratio（组分累加库值），未走 AI 优先

---

## Task 4: GREEN — multi_dish_page 复合菜分支接入 AI 优先

**Files:**
- Modify: `lib/features/recognize/multi_dish_page.dart`

- [ ] **Step 1: 扩展 `_computeLookupHitCalibrated` 支持 compositeNutrition**

读 `lib/features/recognize/multi_dish_page.dart` L363-377，扩展 `_computeLookupHitCalibrated` 支持 compositeNutrition 分支。在原方法后新增 `_computeCompositeLookupHitCalibrated`：

```dart
  /// M16.9：复合菜查库命中 + AI 整菜估算 → AI 绝对优先
  /// 比较 compositeNutrition.calories（组分累加库值）vs aiFallback.calories（AI 整菜估算）
  /// AI 有效时用 AI 整菜估算记 meal_log（不更新库 per100g，复合菜 per100g=0 占位）
  /// AI 无效时用组分累加库值兜底
  CalibratedNutrition? _computeCompositeLookupHitCalibrated(
      int index, VisionRecognitionResult dish, double serving) {
    // 包装营养表优先（精确值，不走差异检测）
    if (dish.hasPackageNutrition) return null;
    final composite = _getCompositeNutrition(index);
    if (composite == null) return null;
    final aiFallback = _getAiFallback(index);
    if (aiFallback == null) return null;
    // 复合菜 lookupCompositeDish 返回的 calories 已是组分累加值（对应 mid 份量）
    // AI aiFallback.calories 也是整菜估算（对应 mid 份量）
    // 直接比较 calories，不需要 per100g 反算（复合菜 per100g=0 占位）
    final aiCalories = aiFallback.calories;
    final dbCalories = composite.calories;
    // sanity check：AI 有效区间 [0, 900 * mid / 100]（per100g 上限 900 对应整菜热量）
    final mid = dish.estimatedWeightGMid;
    final aiPer100 = mid > 0 ? aiCalories * 100 / mid : aiCalories;
    final aiValid = aiPer100 >= 0 && aiPer100 <= 900;
    if (!aiValid) return null; // AI 无效，返回 null 让调用方走原 ratio 兜底
    // AI 绝对优先：用 AI 整菜估算记 meal_log（actualXxx 按 serving 比例缩放）
    final ratio = mid > 0 ? serving / mid : 1.0;
    return CalibratedNutrition(
      caloriesPer100g: 0, // 复合菜 per100g 保持 0 占位
      proteinPer100g: 0,
      fatPer100g: 0,
      carbsPer100g: 0,
      actualCalories: aiCalories * ratio,
      actualProteinG: aiFallback.proteinG * ratio,
      actualFatG: aiFallback.fatG * ratio,
      actualCarbsG: aiFallback.carbsG * ratio,
      foodItemId: 0, // 复合菜 foodItemId 由 _recordAll 的 upsertAiRecognized 处理
      shouldUpdateFoodItem: false, // 复合菜不更新库 per100g
    );
  }
```

- [ ] **Step 2: 修改 `_calcNutrition` 复合菜分支调用新方法**

读 `lib/features/recognize/multi_dish_page.dart` L478-486（主菜 composite 分支）和 L510-518（附加菜 composite 分支），在 `n.calories * ratio` 前先调 `_computeCompositeLookupHitCalibrated`：

```dart
      // M16.9：复合菜查库命中 + AI 整菜估算 → AI 绝对优先
      final compositeCalibrated = _computeCompositeLookupHitCalibrated(0, dish, serving);
      if (compositeCalibrated != null) {
        return (
          compositeCalibrated.actualCalories,
          compositeCalibrated.actualProteinG,
          compositeCalibrated.actualFatG,
          compositeCalibrated.actualCarbsG,
        );
      }
      if (widget.mainComposite != null) {
        final n = widget.mainComposite!;
        return (n.calories * ratio, n.proteinG * ratio, n.fatG * ratio, n.carbsG * ratio);
      }
```

附加菜分支（L510-518）同理处理。

- [ ] **Step 3: 同步修改 `_recordAll` 复合菜分支**

读 `lib/features/recognize/multi_dish_page.dart` L659+（composite 分支），在 upsertAiRecognized 前检查 `_computeCompositeLookupHitCalibrated` 是否返回非 null，若是则用 AI 值覆盖 cal/p/f/c：

```dart
          } else if (composite != null) {
            // M16.9：复合菜查库命中 + AI 整菜估算 → AI 绝对优先
            final compositeCalibrated = _computeCompositeLookupHitCalibrated(i, dish, serving);
            if (compositeCalibrated != null) {
              cal = compositeCalibrated.actualCalories;
              p = compositeCalibrated.actualProteinG;
              f = compositeCalibrated.actualFatG;
              c = compositeCalibrated.actualCarbsG;
            }
            // 复合菜：upsert ai_recognized（per100g=0 占位，components_json 存组分快照）
            foodItemId = await foodRepo.upsertAiRecognized(...);
          }
```

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test test/features/multi_dish_page_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/recognize/multi_dish_page.dart test/features/multi_dish_page_test.dart
git commit -m "M16.9: 复合菜分支接入 AI 绝对优先

复合菜 lookupCompositeDish 返回组分累加库值，原 M16.8 无差异检测，
AI 整菜估算（r.estimatedCalories）完全被丢弃。

修复：
- 新增 _computeCompositeLookupHitCalibrated：复合菜查库命中 + AI 有效时
  用 AI 整菜估算记 meal_log（不更新库 per100g，复合菜 per100g=0 占位）
- _calcNutrition + _recordAll 复合菜分支调用新方法
- AI 无效时返回 null，调用方走原 ratio 兜底（组分累加库值）

sanity check：AI per100g > 900 或 < 0 视为离谱，用组分累加库值兜底。"
```

---

## Task 5: calibration_page 残留路径加注释 + 兜底

**Files:**
- Modify: `lib/features/recognize/calibration_page.dart` L465-474

- [ ] **Step 1: 加注释说明此路径不应触发 + 兜底用库值**

读 `lib/features/recognize/calibration_page.dart` L465-474，更新注释（不改逻辑，因 M16.8 主路径已传 aiFallbackNutrition，此 else 分支不应触发）：

```dart
    // M16.9：查库命中但无 aiFallback——此分支在 M16.8 后不应触发
    // （主路径 recognize_page L466-467 / L663-664 已传 aiFallbackNutrition）
    // 兜底：按 servingG/mid 比例换算库值（保留原 ratio 逻辑）
    // 防除零：AI 返回 estimatedWeightGMid <= 0 时 ratio=1（用原值，不按比例换算）
    // 若未来有调用方未传 aiFallbackNutrition，此处仍是安全兜底
    final mid = r.estimatedWeightGMid;
    final ratio = mid > 0 ? servingG / mid : 1.0;
    return (
      n.calories * ratio,
      n.proteinG * ratio,
      n.fatG * ratio,
      n.carbsG * ratio,
    );
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/recognize/calibration_page.dart
git commit -m "M16.9: calibration_page 残留 else 分支加注释说明

M16.8 主路径已传 aiFallbackNutrition，此 else 分支不应触发。
保留原 ratio 兜底逻辑作为安全网，加注释说明。
不改逻辑。"
```

---

## Task 6: 全量回归验证

**Files:**
- 无修改，仅验证

- [ ] **Step 1: flutter analyze**

Run: `export PATH=/tmp/flutter/bin:$PATH && flutter analyze`
Expected: No issues found

- [ ] **Step 2: flutter test 全量**

Run: `flutter test --exclude-tags smoke`
Expected: All tests passed（923 + M16.9 新增 ~6 测试 - 删除 1 个 M16.8 偏差小测试 ≈ 928）

- [ ] **Step 3: 验证 6 条硬约束**

1. build.gradle.kts `isMinifyEnabled=false` + `isShrinkResources=false` 未变
2. meal_log.food_item_id 哨兵写库前调 upsertAiRecognized（M16.9 查库命中分支 foodItemId > 0 不需 upsert）
3. AI 兜底三路径全覆盖（recognize_page / multi_dish_page / offline_queue_controller 都用 CalibratedNutritionCalculator）
4. per100g 反算基于 estimatedWeightGMid（calculator 内部 `mid = r.estimatedWeightGMid`）
5. SecureConfigStore 无 instance 静态属性
6. initSentryAndRunApp 命名参数

- [ ] **Step 4: 验证 M16.2~M16.8 修复区域无回归**

确认相关测试全过：calibrated_nutrition_calculator_test / recognize_page_test / multi_dish_page_test / calibration_page_test / offline_queue_test / food_category_defaults_test / food_item_repository_update_per100g_test

---

## Task 7: 发布准备（严肃 commit + push + tag v0.18.8）

**Files:**
- Modify: `pubspec.yaml`
- Modify: `HANDOFF.md`

- [ ] **Step 1: bump 版本**

`pubspec.yaml`: `0.18.7+26` → `0.18.8+27`

- [ ] **Step 2: 更新 HANDOFF.md**

更新第 2 节"当前状态" + 新增 M16.9 章节（参考 M16.8 章节结构）：
- 触发：用户要求"把库值在这个项目中的重要性占比减小很多"
- 策略：AI 绝对优先（查库命中分支重写）+ 复合菜残留路径同步修复
- 核心改动：calibrated_nutrition_calculator 查库命中分支 AI 绝对优先 + sanity check 兜底
- 复合菜：_computeCompositeLookupHitCalibrated 新方法
- 验证：flutter analyze No issues + flutter test 全过 + 6 条硬约束满足
- 待用户执行：装 v0.18.8 APK 验证

- [ ] **Step 3: 严肃 commit**

```bash
git add pubspec.yaml HANDOFF.md
git commit -m "M16.9: 减小库值重要性——AI 绝对优先（v0.18.8）—— 查库命中分支重写 + 复合菜残留路径修复

用户要求"把库值在这个项目中的重要性占比减小很多"。

核心改动：
- 查库命中分支（foodItemId>0）改为 AI 估算绝对优先
  - AI 有效（per100g ∈ [0, 900]）时始终用 AI 反算 per100g 写库 + 用 AI 值记 meal_log
  - AI 无效（null/负/>900）时用库值兜底（不更新库）
  - shouldUpdateFoodItem：diffRatio > 5% 时为 true（避免无意义写库）
- 复合菜分支（multi_dish_page composite）接入 AI 绝对优先
  - 新增 _computeCompositeLookupHitCalibrated
  - AI 整菜估算有效时用 AI 值记 meal_log（不更新库 per100g，复合菜 per100g=0 占位）
- calibration_page 残留 else 分支加注释说明（M16.8 后不应触发）

库值重要性大幅降低：从'偏差 ≤ 50% 用库值'降级为'仅 AI 离谱时兜底'。
三路径（recognize_page/multi_dish_page/offline_queue）共用 calculator 自动继承新逻辑。

验证：flutter analyze No issues + flutter test 全过；
6 条硬约束全部满足；M16.2~M16.8 修复区域无回归。

bump 0.18.7+26 → 0.18.8+27 + HANDOFF 回填 M16.9 章节。"
```

- [ ] **Step 4: 严肃 push**

```bash
git push origin trae/agent-wX1X6Q
```

- [ ] **Step 5: 严肃打 tag + push tag**

```bash
git tag v0.18.8
git push origin v0.18.8
```

- [ ] **Step 6: 验证 push 成功**

Run: `git log --oneline -5 && git tag -l v0.18.*`
Expected: 看到 v0.18.8 tag + 最新 commit 在 origin/trae/agent-wX1X6Q

---

## Assumptions & Decisions

### 决策 1：AI 绝对优先 + sanity check 兜底（用户选择）

- **AI 有效区间**：per100g ∈ [0, 900]
  - 上限 900：纯脂肪油 889，solid clamp 上限 900（`food_category_defaults.dart` L112）
  - AI per100g > 900 视为离谱（如 AI 把水估成 5000 kcal/100g）
- **shouldUpdateFoodItem 阈值**：diffRatio > 5%（避免无意义写库）
  - AI 与库完全一致时不写库
  - AI 与库有 5%+ 差异时更新库 per100g 为 AI 反算值

### 决策 2：复合菜分支接入 AI 优先（用户选择"同步修复"）

- 复合菜 `lookupCompositeDish` 返回组分累加库值
- AI 整菜估算（r.estimatedCalories）vs 组分累加库值
- AI 有效时用 AI 整菜估算记 meal_log（不更新库 per100g，复合菜 per100g=0 占位）
- AI 无效时用组分累加库值兜底

### 决策 3：offline_queue L212-219（无 AI 估算旧 prompt）保留不动

- 此分支为旧 prompt（v1.4 之前）兼容，新 prompt 不走
- 保留原 ratio 逻辑（库值 × mid / 100）

### 决策 4：calibration_page L465-474 残留 else 分支保留 + 加注释

- M16.8 主路径已传 aiFallbackNutrition，此 else 分支不应触发
- 保留原 ratio 兜底逻辑作为安全网
- 加注释说明（不改逻辑）

### 假设

1. AI 估算（r.estimatedCalories）在 prompt v1.9+ 始终存在（旧 prompt v1.4 之前无此字段，走 offline_queue L212-219 兼容分支）
2. 复合菜 AI 整菜估算（r.estimatedCalories）与组分累加库值可比较（都对应 mid 份量整菜热量）
3. 三路径调用方已正确传入 aiFallbackNutrition（M16.8 已修复主路径）

---

## Verification Steps

1. **单元测试**：`flutter test test/features/calibrated_nutrition_calculator_test.dart`
   - AI 绝对优先（偏差小也用 AI）✅
   - AI 与库一致不写库 ✅
   - AI 离谱（>900）用库值兜底 ✅
   - AI 负值用库值兜底 ✅
   - 用户调滑块 actualCalories 按 AI per100g 缩放 ✅

2. **集成测试**：`flutter test test/features/recognize_page_test.dart test/features/multi_dish_page_test.dart test/features/offline_queue_test.dart`
   - 三路径 AI 绝对优先一致 ✅
   - 复合菜 AI 优先 ✅

3. **全量回归**：`flutter test --exclude-tags smoke`
   - 923+ 测试全过 ✅
   - M16.2~M16.8 修复区域无回归 ✅

4. **静态分析**：`flutter analyze`
   - No issues found ✅

5. **硬约束**：6 条全部满足 ✅

6. **发布**：commit + push + tag v0.18.8 ✅

---

## Self-Review

### 1. Spec coverage

- ✅ 减小库值重要性：Task 2 重写查库命中分支为 AI 绝对优先
- ✅ 严肃 commit + push + tag：Task 7 完整发布流程
- ✅ 复合菜残留路径同步修复：Task 4 _computeCompositeLookupHitCalibrated
- ✅ 三路径统一：calculator 单点改动，三路径自动继承
- ✅ sanity check 兜底：Task 2 AI 无效时用库值

### 2. Placeholder scan

- 无 "TBD" / "TODO" / "implement later"
- Task 3 Step 1 的测试 setup 注明"参考现有 multi_dish_page_test.dart 复合菜测试结构"——这是合理的引用，不是 placeholder
- Task 4 Step 3 的"..."是省略号表示保留原 upsertAiRecognized 调用，不是 placeholder

### 3. Type consistency

- `CalibratedNutrition` 字段（foodItemId / shouldUpdateFoodItem）：Task 2 使用，与 M16.8 定义一致
- `_computeCompositeLookupHitCalibrated` 返回 `CalibratedNutrition?`：Task 4 定义，与 `_computeLookupHitCalibrated` 一致
- `shouldUpdateFoodItem` 语义：Task 2 定义（diffRatio > 5%），Task 4 复合菜分支始终 false（不更新库 per100g）——一致

### 4. 风险评估

- **风险 1**：AI 估算波动会频繁更新库 per100g
  - 缓解：shouldUpdateFoodItem 阈值 5%（diffRatio ≤ 5% 不写库）
- **风险 2**：AI 系统性偏差（如某品类总是高估）会污染库
  - 缓解：sanity check 上限 900 per100g（离谱值兜底用库值）
- **风险 3**：复合菜 AI 整菜估算 vs 组分累加不可比
  - 缓解：两者都对应 mid 份量整菜热量，可比；AI 无效时返回 null 兜底
