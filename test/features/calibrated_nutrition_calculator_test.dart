import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/features/recognize/calibrated_nutrition_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

/// CalibratedNutritionCalculator 测试
///
/// 验证 AI 兜底哨兵路径（foodItemId=0）下，三路径（recognize_page /
/// multi_dish_page / offline_queue_controller）共用统一辅助方法后，
/// actualCalories 与食物库 per100g 一致，避免"推理过程数值与最终记录数值不一致"。
///
/// 核心断言：actualXxx = 校准后 per100g * servingG / 100
/// - per100g 用于写食物库（food_item）
/// - actualXxx 用于写 meal_log
void main() {
  group('CalibratedNutritionCalculator', () {
    group('品类校准路径（无包装数据）', () {
      test('场景1：方案 D — beer 品类，actualCalories 与 AI 推理一致', () {
        // 方案 D（M25）：废弃品类校准，4 项全保留 AI 估算值
        // AI 估算啤酒整菜 600kcal（mid=300g），per100g=200（在 [0,900] 内不被覆盖）
        final r = VisionRecognitionResult(
          dishName: '啤酒',
          estimatedWeightGLow: 250,
          estimatedWeightGMid: 300,
          estimatedWeightGHigh: 350,
          foodComponents: const [],
          cookingMethod: '',
          isSingleItem: true,
          confidence: 0.9,
          promptVersion: 'v1.10',
          estimatedCalories: 600,
          estimatedProteinG: 2,
          estimatedFatG: 1,
          estimatedCarbsG: 15,
          foodCategory: 'beer',
        );
        final aiFallback = NutritionResult(
          foodItemId: 0,
          calories: 600,
          proteinG: 2,
          fatG: 1,
          carbsG: 15,
          oilG: 0,
          source: NutritionSource.aiEstimate,
        );

        final result = CalibratedNutritionCalculator.compute(
          recognitionResult: r,
          aiFallback: aiFallback,
          servingG: 300,
        );

        // 方案 D：per100g 保留 AI 反算值 200
        expect(result.caloriesPer100g, closeTo(200, 0.01));
        // actualCalories = 200 * 300 / 100 = 600（与 AI 推理一致）
        expect(result.actualCalories, closeTo(600, 0.01));
      });

      test('场景2：solid 不校准，actualCalories = AI per100g * servingG / 100', () {
        // solid 无品类默认值，AI 估算 550kcal/200g → per100g=275，校准只做 clamp 保留 275
        final r = VisionRecognitionResult(
          dishName: '炒饭',
          estimatedWeightGLow: 150,
          estimatedWeightGMid: 200,
          estimatedWeightGHigh: 250,
          foodComponents: const [],
          cookingMethod: 'stir-fry',
          isSingleItem: true,
          confidence: 0.85,
          promptVersion: 'v1.10',
          estimatedCalories: 550,
          estimatedProteinG: 10,
          estimatedFatG: 20,
          estimatedCarbsG: 50,
          foodCategory: 'solid',
        );
        final aiFallback = NutritionResult(
          foodItemId: 0,
          calories: 550,
          proteinG: 10,
          fatG: 20,
          carbsG: 50,
          oilG: 0,
          source: NutritionSource.aiEstimate,
        );

        final result = CalibratedNutritionCalculator.compute(
          recognitionResult: r,
          aiFallback: aiFallback,
          servingG: 200,
        );

        // solid 无默认值，per100g 保留 AI 估算 275
        expect(result.caloriesPer100g, 275);
        // actualCalories = 275 * 200 / 100 = 550
        expect(result.actualCalories, closeTo(550, 0.01));
      });

      test('场景4：方案 D — 用户调整滑块，actualCalories 按调整后 servingG 计算', () {
        // 方案 D：beer 品类，mid=300（AI 估算基于 300g），用户调整 servingG=200
        // per100g 仍按 mid 反算（不随用户调整偏差），actual 用 servingG
        final r = VisionRecognitionResult(
          dishName: '啤酒',
          estimatedWeightGLow: 250,
          estimatedWeightGMid: 300,
          estimatedWeightGHigh: 350,
          foodComponents: const [],
          cookingMethod: '',
          isSingleItem: true,
          confidence: 0.9,
          promptVersion: 'v1.10',
          estimatedCalories: 600,
          estimatedProteinG: 2,
          estimatedFatG: 1,
          estimatedCarbsG: 15,
          foodCategory: 'beer',
        );
        final aiFallback = NutritionResult(
          foodItemId: 0,
          calories: 600,
          proteinG: 2,
          fatG: 1,
          carbsG: 15,
          oilG: 0,
          source: NutritionSource.aiEstimate,
        );

        final result = CalibratedNutritionCalculator.compute(
          recognitionResult: r,
          aiFallback: aiFallback,
          servingG: 200, // 用户调小
        );

        // 方案 D：per100g 仍按 mid=300 反算（不随用户调整偏差），保留 AI 值 200
        expect(result.caloriesPer100g, closeTo(200, 0.01));
        // actualCalories = 200 * 200 / 100 = 400（按用户调整后的 servingG）
        expect(result.actualCalories, closeTo(400, 0.01));
      });

      test('场景5：方案 D — 宏量同步，actualMacros = per100g * servingG / 100', () {
        // 方案 D（M25）：4 项全保留 AI 值，只做物理 clamp
        // mid=300g, AI 估 600kcal/2g 蛋白/1g 脂肪/15g 碳水
        // AI per100g = (200, 0.667, 0.333, 5.0)，方案 D 保留全部
        final r = VisionRecognitionResult(
          dishName: '啤酒',
          estimatedWeightGLow: 250,
          estimatedWeightGMid: 300,
          estimatedWeightGHigh: 350,
          foodComponents: const [],
          cookingMethod: '',
          isSingleItem: true,
          confidence: 0.9,
          promptVersion: 'v1.10',
          estimatedCalories: 600,
          estimatedProteinG: 2,
          estimatedFatG: 1,
          estimatedCarbsG: 15,
          foodCategory: 'beer',
        );
        final aiFallback = NutritionResult(
          foodItemId: 0,
          calories: 600,
          proteinG: 2,
          fatG: 1,
          carbsG: 15,
          oilG: 0,
          source: NutritionSource.aiEstimate,
        );

        final result = CalibratedNutritionCalculator.compute(
          recognitionResult: r,
          aiFallback: aiFallback,
          servingG: 300,
        );

        // 方案 D：per100g 宏量保留 AI 反算值
        expect(result.proteinPer100g, closeTo(2 * 100 / 300, 0.001)); // 0.667
        expect(result.fatPer100g, closeTo(1 * 100 / 300, 0.001)); // 0.333
        expect(result.carbsPer100g, closeTo(15 * 100 / 300, 0.001)); // 5.0
        // actualMacros 与 per100g 同步：actualXxx = per100g * servingG / 100
        expect(result.actualProteinG, closeTo(2 * 100 / 300 * 300 / 100, 0.01)); // 2
        expect(result.actualFatG, closeTo(1 * 100 / 300 * 300 / 100, 0.01)); // 1
        expect(result.actualCarbsG, closeTo(15 * 100 / 300 * 300 / 100, 0.01)); // 15
        // 一致性断言：actualXxx 严格等于 per100g * servingG / 100
        expect(result.actualCalories,
            closeTo(result.caloriesPer100g * 300 / 100, 0.001));
        expect(result.actualProteinG,
            closeTo(result.proteinPer100g * 300 / 100, 0.001));
        expect(result.actualFatG,
            closeTo(result.fatPer100g * 300 / 100, 0.001));
        expect(result.actualCarbsG,
            closeTo(result.carbsPer100g * 300 / 100, 0.001));
      });
    });

    group('包装 OCR 路径', () {
      test('场景3：有包装数据，用 packagePer100 不走品类校准', () {
        // 包装标称：每 100g 50kcal，蛋白 1g，脂肪 2g，碳水 12.5g
        // packageServingG=100, packageServingKcal=50
        // packageServingProteinG=1, packageServingFatG=2, packageServingCarbsG=12.5
        // → packagePer100 = (50, 1, 2, 12.5)
        final r = VisionRecognitionResult(
          dishName: '可乐',
          estimatedWeightGLow: 150,
          estimatedWeightGMid: 200,
          estimatedWeightGHigh: 250,
          foodComponents: const [],
          cookingMethod: '',
          isSingleItem: true,
          confidence: 0.9,
          promptVersion: 'v1.10',
          estimatedCalories: 100,
          estimatedProteinG: 2,
          estimatedFatG: 4,
          estimatedCarbsG: 25,
          foodCategory: 'carbonated',
          packageServingG: 100,
          packageServingKcal: 50,
          packageServingProteinG: 1,
          packageServingFatG: 2,
          packageServingCarbsG: 12.5,
        );
        final aiFallback = NutritionResult(
          foodItemId: 0,
          calories: 100,
          proteinG: 2,
          fatG: 4,
          carbsG: 25,
          oilG: 0,
          source: NutritionSource.aiEstimate,
        );

        final result = CalibratedNutritionCalculator.compute(
          recognitionResult: r,
          aiFallback: aiFallback,
          servingG: 200,
        );

        // 包装换算 per100g（精确值，不走品类校准）
        expect(result.caloriesPer100g, closeTo(50, 0.01));
        expect(result.proteinPer100g, closeTo(1, 0.01));
        expect(result.fatPer100g, closeTo(2, 0.01));
        expect(result.carbsPer100g, closeTo(12.5, 0.01));
        // actualXxx = packagePer100 * servingG / 100
        expect(result.actualCalories, closeTo(50 * 200 / 100, 0.01)); // 100
        expect(result.actualProteinG, closeTo(1 * 200 / 100, 0.01)); // 2
        expect(result.actualFatG, closeTo(2 * 200 / 100, 0.01)); // 4
        expect(result.actualCarbsG, closeTo(12.5 * 200 / 100, 0.01)); // 25
      });

      test('场景3b：包装换算宏量全 0 → 回退品类校准', () {
        // 含糖饮料 AI 漏填宏量：包装 kcal 有值但 protein/fat/carbs 全 0
        // packagePer100 = (50, 0, 0, 0) → packageMacrosAllZero=true → 走品类校准
        // foodCategory=carbonated, AI per100g cal = 100*100/200 = 50
        // 50/43 ≈ 1.16 在 0.5-2 区间，calibrate 保留 50（但宏量 clamp）
        final r = VisionRecognitionResult(
          dishName: '菊花茶',
          estimatedWeightGLow: 150,
          estimatedWeightGMid: 200,
          estimatedWeightGHigh: 250,
          foodComponents: const [],
          cookingMethod: '',
          isSingleItem: true,
          confidence: 0.9,
          promptVersion: 'v1.10',
          estimatedCalories: 100,
          estimatedProteinG: 0,
          estimatedFatG: 0,
          estimatedCarbsG: 25,
          foodCategory: 'tea',
          packageServingG: 100,
          packageServingKcal: 50,
          // 包装字段全 null → computePackageNutritionPer100g 用 AI 反算 → 全 0
          packageServingProteinG: null,
          packageServingFatG: null,
          packageServingCarbsG: null,
        );
        final aiFallback = NutritionResult(
          foodItemId: 0,
          calories: 100,
          proteinG: 0,
          fatG: 0,
          carbsG: 25,
          oilG: 0,
          source: NutritionSource.aiEstimate,
        );

        final result = CalibratedNutritionCalculator.compute(
          recognitionResult: r,
          aiFallback: aiFallback,
          servingG: 200,
        );

        // 包装换算宏量全 0 → 回退品类校准
        // AI per100g cal = 100 * 100 / 200 = 50，tea 默认 43，50/43≈1.16 在区间内保留 50
        expect(result.caloriesPer100g, closeTo(50, 0.01));
        // actualCalories = 50 * 200 / 100 = 100（与 per100g 一致）
        expect(result.actualCalories, closeTo(100, 0.01));
      });
    });

    group('边界情况', () {
      test('mid=0 防除零：per100g=0，actualXxx=0', () {
        final r = VisionRecognitionResult(
          dishName: '未知',
          estimatedWeightGLow: 0,
          estimatedWeightGMid: 0,
          estimatedWeightGHigh: 0,
          foodComponents: const [],
          cookingMethod: '',
          isSingleItem: true,
          confidence: 0.5,
          promptVersion: 'v1.10',
          estimatedCalories: 100,
          foodCategory: 'solid',
        );
        final aiFallback = NutritionResult(
          foodItemId: 0,
          calories: 100,
          proteinG: 5,
          fatG: 5,
          carbsG: 10,
          oilG: 0,
          source: NutritionSource.aiEstimate,
        );

        final result = CalibratedNutritionCalculator.compute(
          recognitionResult: r,
          aiFallback: aiFallback,
          servingG: 100,
        );

        // mid=0 → per100Ratio=0 → AI per100g=0 → calibrate(0,...,'solid') → clamp 0
        expect(result.caloriesPer100g, 0);
        expect(result.actualCalories, 0);
      });

      test('一致性：所有路径 actualXxx = caloriesPer100g * servingG / 100', () {
        // 随机场景，验证 actualXxx 永远等于 per100g * servingG / 100
        final r = VisionRecognitionResult(
          dishName: '测试',
          estimatedWeightGLow: 100,
          estimatedWeightGMid: 150,
          estimatedWeightGHigh: 200,
          foodComponents: const [],
          cookingMethod: '',
          isSingleItem: true,
          confidence: 0.8,
          promptVersion: 'v1.10',
          estimatedCalories: 300,
          estimatedProteinG: 6,
          estimatedFatG: 9,
          estimatedCarbsG: 30,
          foodCategory: 'milk',
        );
        final aiFallback = NutritionResult(
          foodItemId: 0,
          calories: 300,
          proteinG: 6,
          fatG: 9,
          carbsG: 30,
          oilG: 0,
          source: NutritionSource.aiEstimate,
        );
        const servingG = 175.0;

        final result = CalibratedNutritionCalculator.compute(
          recognitionResult: r,
          aiFallback: aiFallback,
          servingG: servingG,
        );

        expect(result.actualCalories,
            closeTo(result.caloriesPer100g * servingG / 100, 0.001));
        expect(result.actualProteinG,
            closeTo(result.proteinPer100g * servingG / 100, 0.001));
        expect(result.actualFatG,
            closeTo(result.fatPer100g * servingG / 100, 0.001));
        expect(result.actualCarbsG,
            closeTo(result.carbsPer100g * servingG / 100, 0.001));
      });
    });
  });

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
        foodComponents: const [],
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
        source: NutritionSource.aiEstimate,
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
      expect(result.caloriesPer100g, closeTo(125, 0.1),
          reason: 'AI 反算 per100g = 250*100/200');
      expect(result.actualCalories, closeTo(250, 0.1), reason: '用 AI 估算值记录');
      expect(result.shouldUpdateFoodItem, isTrue, reason: '偏差大时应更新库 per100g');
      expect(result.foodItemId, 1, reason: '保留库命中的 foodItemId');
    });

    test('M16.9: 查库命中 + AI 偏差小（6%）也用 AI 估算（AI 绝对优先）', () {
      // 库 per100g=80, AI 估 200g/170kcal（库值 160 vs AI 170，偏差 6%）
      // M16.9：AI 绝对优先，偏差小也用 AI 反算 per100g + 更新库（diffRatio > 5%）
      final r = VisionRecognitionResult(
        dishName: '番茄炒蛋',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        estimatedCalories: 170,
        estimatedProteinG: 7,
        estimatedFatG: 10,
        estimatedCarbsG: 13,
        foodComponents: const [],
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
        source: NutritionSource.aiEstimate,
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
      // AI per100g = 170 * 100 / 200 = 85
      expect(result.caloriesPer100g, closeTo(85, 0.1),
          reason: 'M16.9 AI 绝对优先：偏差小也用 AI 反算 per100g');
      expect(result.actualCalories, closeTo(170, 0.1),
          reason: 'actualCalories 用 AI 估算值（170），不用库值（160）');
      expect(result.actualProteinG, closeTo(7, 0.1),
          reason: '蛋白用 AI 估算值');
      expect(result.foodItemId, 1, reason: 'foodItemId 保留查库命中 id');
      // 偏差 6% > 5% → shouldUpdateFoodItem=true（更新库 per100g 为 AI 反算值）
      expect(result.shouldUpdateFoodItem, isTrue,
          reason: 'M16.9 偏差 > 5% 时更新库 per100g');
    });

    test('M16.9: AI 与库完全一致（diffRatio=0）用 AI 但不写库（避免无意义写库）', () {
      final r = VisionRecognitionResult(
        dishName: '番茄炒蛋',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        estimatedCalories: 160,
        estimatedProteinG: 6,
        estimatedFatG: 10,
        estimatedCarbsG: 12,
        foodComponents: const [],
        cookingMethod: 'stir_fry',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.0',
      );
      final aiSameAsDb = NutritionResult(
        foodItemId: 0,
        calories: 160, // 与库值完全一致
        proteinG: 6,
        fatG: 10,
        carbsG: 12,
        oilG: 0,
        source: NutritionSource.aiEstimate,
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
        aiFallback: aiSameAsDb,
        servingG: 200,
        lookupHitNutrition: lookupHit,
      );
      expect(result.caloriesPer100g, closeTo(80, 0.1),
          reason: 'AI per100g = 160 * 100 / 200 = 80（与库一致）');
      expect(result.actualCalories, closeTo(160, 0.1));
      expect(result.shouldUpdateFoodItem, isFalse,
          reason: 'M16.9 diffRatio=0 ≤ 5% 时不写库（无意义）');
    });

    test('v2: AI per100g 离谱（>900）时始终用 AI 值 + 更新库', () {
      // v2 重构：删除 aiValid 离谱兜底，始终用 AI 反算 per100g 写库 + 用 AI 值记 meal_log
      // AI 离谱通过 validator warnings 提示用户手动纠正，不再用库值覆盖
      // AI 估 2000 kcal（per100g = 2000 * 100 / 200 = 1000 > 900 离谱）
      final r = VisionRecognitionResult(
        dishName: '水',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        estimatedCalories: 2000,
        estimatedProteinG: 50,
        estimatedFatG: 100,
        estimatedCarbsG: 200,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.0',
        foodCategory: 'water',
      );
      final aiAbsurd = NutritionResult(
        foodItemId: 0,
        calories: 2000,
        proteinG: 50,
        fatG: 100,
        carbsG: 200,
        oilG: 0,
        source: NutritionSource.aiEstimate,
      );
      final lookupHit = NutritionResult(
        foodItemId: 1,
        calories: 160, // 库 per100g=80
        proteinG: 6,
        fatG: 10,
        carbsG: 12,
        oilG: 0,
      );
      final result = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiAbsurd,
        servingG: 200,
        lookupHitNutrition: lookupHit,
      );
      // v2 新逻辑：始终用 AI 反算值
      expect(result.caloriesPer100g, closeTo(1000, 0.1),
          reason: 'v2 AI 离谱时仍用 AI per100g=1000，不用库值 80 兜底');
      expect(result.actualCalories, closeTo(2000, 0.1),
          reason: 'actualCalories 用 AI 值 2000');
      expect(result.shouldUpdateFoodItem, isTrue,
          reason: 'v2 AI 离谱也写库（让用户后续可见，库值跟随 AI）');
    });

    test('v2: AI per100g 负值时始终用 AI 值', () {
      // v2 重构：AI 负值不再用库值兜底（用户通过 warnings 手动纠正）
      final r = VisionRecognitionResult(
        dishName: '番茄炒蛋',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        estimatedCalories: -50,
        estimatedProteinG: 0,
        estimatedFatG: 0,
        estimatedCarbsG: 0,
        foodComponents: const [],
        cookingMethod: 'stir_fry',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.0',
        foodCategory: 'solid',
      );
      final aiNegative = NutritionResult(
        foodItemId: 0,
        calories: -50, // 负值
        proteinG: 0,
        fatG: 0,
        carbsG: 0,
        oilG: 0,
        source: NutritionSource.aiEstimate,
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
        aiFallback: aiNegative,
        servingG: 200,
        lookupHitNutrition: lookupHit,
      );
      // v2 新逻辑：始终用 AI 反算值（负值也照记，warnings 提示用户）
      expect(result.caloriesPer100g, closeTo(-25, 0.1),
          reason: 'v2 AI 负值时仍用 AI per100g=-25，不用库值兜底');
      expect(result.actualCalories, closeTo(-50, 0.1),
          reason: 'actualCalories 用 AI 值 -50');
      // diffRatio = (aiPer100Calories - dbPer100Calories).abs() / dbPer100Calories
      // = (-25 - 80).abs() / 80 = 1.3125 > 0 → shouldUpdateFoodItem = true
      expect(result.shouldUpdateFoodItem, isTrue);
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
        foodComponents: const [],
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
        source: NutritionSource.aiEstimate,
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
      expect(result.actualCalories, closeTo(125, 0.1),
          reason: '125 * 100 / 100 = 125');
      expect(result.actualProteinG, closeTo(5, 0.1),
          reason: '10 * 100 / 200 = 5 (AI 蛋白反算)');
    });

    test('查库命中 + AI 与库都为 0：用库值 0 + 不更新库', () {
      // 库 per100g=0（water）, AI 估 0 kcal
      final r = VisionRecognitionResult(
        dishName: '水',
        estimatedWeightGLow: 200,
        estimatedWeightGMid: 250,
        estimatedWeightGHigh: 300,
        estimatedCalories: 0,
        foodComponents: const [],
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
        source: NutritionSource.aiEstimate,
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

  group('CalibratedNutritionCalculator.computeCompositeLookupHit M18', () {
    // M18：抽取复合菜 AI 优先逻辑为公共方法 + 提高 AI 优先值
    // 复合菜 AI 有效时 per100g 从 0 占位改为 AI 反算值，让 AI 估算进入食物库
    NutritionResult aiFallback500({
      double calories = 500,
      double proteinG = 20,
      double fatG = 15,
      double carbsG = 50,
    }) =>
        NutritionResult(
          foodItemId: 0,
          calories: calories,
          proteinG: proteinG,
          fatG: fatG,
          carbsG: carbsG,
          oilG: 0,
          source: NutritionSource.aiEstimate,
        );

    test('M18: AI 有效时返回 AI 估算值 + per100g 存 AI 反算值（非 0 占位）', () {
      // aiFallback.calories=500, mid=200, servingG=200
      // aiPer100 = 500 * 100 / 200 = 250（有效 ∈ [0, 900]）
      // per100Ratio = 100 / 200 = 0.5
      // caloriesPer100g = 500 * 0.5 = 250（非 0 占位）
      // actualCalories = 500 * 200/200 = 500
      final result = CalibratedNutritionCalculator.computeCompositeLookupHit(
        aiFallback: aiFallback500(),
        servingG: 200,
        mid: 200,
      );
      expect(result, isNotNull, reason: 'AI 有效应返回非 null');
      expect(result!.actualCalories, closeTo(500, 0.01),
          reason: 'actualCalories 用 AI 估算值');
      expect(result.caloriesPer100g, closeTo(250, 0.01),
          reason: 'M18: per100g 存 AI 反算值（非 0 占位）');
      expect(result.proteinPer100g, closeTo(10, 0.01),
          reason: 'protein per100g = 20 * 100 / 200 = 10');
      expect(result.shouldUpdateFoodItem, isTrue,
          reason: 'M18: 始终写库，让 AI 值进入食物库');
    });

    test('v2: AI 离谱（per100g>900）时仍返回 AI 值（不再返回 null）', () {
      // v2 重构：删除 aiValid 检查，始终返回 AI 反算值
      // AI 离谱通过 validator warnings 提示用户手动纠正，调用方不再走 ratio 兜底
      // aiFallback.calories=2000, mid=200 → aiPer100 = 1000 > 900 离谱
      final result = CalibratedNutritionCalculator.computeCompositeLookupHit(
        aiFallback: aiFallback500(calories: 2000),
        servingG: 200,
        mid: 200,
      );
      expect(result, isNotNull, reason: 'v2 AI 离谱时仍返回 AI 值，不再返回 null');
      expect(result!.caloriesPer100g, closeTo(1000, 0.1),
          reason: 'per100g=2000*100/200=1000');
      expect(result.actualCalories, closeTo(2000, 0.1),
          reason: 'actualCalories=1000*200/100=2000');
      expect(result.shouldUpdateFoodItem, isTrue,
          reason: '复合菜始终写库，让 AI 值进入食物库');
    });

    test('M18: mid=0 时返回 null（防除零）', () {
      final result = CalibratedNutritionCalculator.computeCompositeLookupHit(
        aiFallback: aiFallback500(),
        servingG: 200,
        mid: 0,
      );
      expect(result, isNull, reason: 'mid=0 防除零返回 null');
    });

    test('M18: actualXxx 按 serving/mid 比例缩放', () {
      // aiFallback.calories=500, mid=200, servingG=100
      // ratio = 100 / 200 = 0.5
      // actualCalories = 500 * 0.5 = 250
      final result = CalibratedNutritionCalculator.computeCompositeLookupHit(
        aiFallback: aiFallback500(),
        servingG: 100,
        mid: 200,
      );
      expect(result, isNotNull);
      expect(result!.actualCalories, closeTo(250, 0.01),
          reason: '500 × 100/200 = 250');
      expect(result.actualProteinG, closeTo(10, 0.01),
          reason: '20 × 100/200 = 10');
    });
  });

  group('CalibratedNutritionCalculator.compute M18: 提高 AI 优先值', () {
    // M18：单品查库命中 shouldUpdateFoodItem 从 diffRatio > 5% 改为 > 0
    // 让 AI 估算持续纠正库，库值始终跟随 AI

    VisionRecognitionResult baseResult({
      required double estimatedCalories,
      double mid = 200,
    }) =>
        VisionRecognitionResult(
          dishName: '番茄炒蛋',
          estimatedWeightGLow: 180,
          estimatedWeightGMid: mid,
          estimatedWeightGHigh: 220,
          estimatedCalories: estimatedCalories,
          estimatedProteinG: 6,
          estimatedFatG: 10,
          estimatedCarbsG: 12,
          foodComponents: const [],
          cookingMethod: 'stir_fry',
          isSingleItem: true,
          confidence: 0.9,
          promptVersion: 'v1.0',
        );

    test('M18: AI 有效 + diffRatio=2% 时 shouldUpdateFoodItem=true（始终写库）', () {
      // 库 per100g=100（lookupHit.calories=200, mid=200 → dbPer100=100）
      // AI 估 204kcal（aiPer100=102, dbPer100=100, diffRatio=2% < 5%）
      // M16.9: shouldUpdateFoodItem=false（2% < 5%）
      // M18: shouldUpdateFoodItem=true（2% > 0，始终写库）
      final r = baseResult(estimatedCalories: 204);
      final aiFallback = NutritionResult(
        foodItemId: 0,
        calories: 204,
        proteinG: 6,
        fatG: 10,
        carbsG: 12,
        oilG: 0,
        source: NutritionSource.aiEstimate,
      );
      final lookupHit = NutritionResult(
        foodItemId: 1,
        calories: 200, // dbPer100 = 200 * 100 / 200 = 100
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
      expect(result.shouldUpdateFoodItem, isTrue,
          reason: 'M18: diffRatio=2% > 0，始终写库（原 M16.9 为 false，5% 阈值已移除）');
      expect(result.caloriesPer100g, closeTo(102, 0.1),
          reason: 'AI 反算 per100g = 204 * 100 / 200 = 102');
    });

    test('M18: AI 有效 + diffRatio=0% 时 shouldUpdateFoodItem=false（完全一致不写库）', () {
      // 库 per100g=100，AI 估 200kcal（aiPer100=100, dbPer100=100, diffRatio=0%）
      // M18: shouldUpdateFoodItem=false（0 不 > 0，完全一致无需写库）
      final r = baseResult(estimatedCalories: 200);
      final aiSameAsDb = NutritionResult(
        foodItemId: 0,
        calories: 200,
        proteinG: 6,
        fatG: 10,
        carbsG: 12,
        oilG: 0,
        source: NutritionSource.aiEstimate,
      );
      final lookupHit = NutritionResult(
        foodItemId: 1,
        calories: 200,
        proteinG: 6,
        fatG: 10,
        carbsG: 12,
        oilG: 0,
      );
      final result = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiSameAsDb,
        servingG: 200,
        lookupHitNutrition: lookupHit,
      );
      expect(result.shouldUpdateFoodItem, isFalse,
          reason: 'M18: diffRatio=0% 不 > 0，完全一致不写库（与 M16.9 一致）');
    });
  });
}
