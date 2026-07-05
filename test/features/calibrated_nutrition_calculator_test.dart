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
      test('场景1：beer 品类校准，actualCalories 用校准后 per100g 计算', () {
        // AI 估算啤酒整菜 600kcal（mid=300g），per100g=200 偏离 beer 默认 43 的 4.65 倍 → 校准
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

        // 写库 per100g 用校准后的 beer 默认值 43
        expect(result.caloriesPer100g, 43);
        // actualCalories = 43 * 300 / 100 = 129（非未校准的 600）
        expect(result.actualCalories, closeTo(129, 0.01));
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

      test('场景4：用户调整滑块，actualCalories 按调整后 servingG 计算', () {
        // beer, mid=300（AI 估算基于 300g），用户调整 servingG=200
        // per100g 仍按 mid 反算并校准（不随用户调整偏差），actual 用 servingG
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

        // per100g 仍按 mid=300 反算并校准为 43（密度不随用户调整反向偏差）
        expect(result.caloriesPer100g, 43);
        // actualCalories = 43 * 200 / 100 = 86（按用户调整后的 servingG）
        expect(result.actualCalories, closeTo(86, 0.01));
      });

      test('场景5：宏量同步，actualMacros = 校准后 per100g * servingG / 100', () {
        // M16.8：beer 触发校准只替换 calories，宏量保留 AI 值（带 clamp）
        // mid=300g, AI 估 600kcal/2g 蛋白/1g 脂肪/15g 碳水
        // AI per100g = (200, 0.667, 0.333, 5.0)，cal 偏离 beer 43 触发校准
        // 校准后 per100g = (43, 0.667, 0.333, 5.0)，actualMacros 必须用同一 per100g
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

        // 校准后 per100g 宏量（保留 AI 反算值，不替换为品类默认 0.5/0/3.1）
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
}
