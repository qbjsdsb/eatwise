// 方案 D 回归测试：废弃品类校准 + 物理 clamp 保留
//
// 背景：
//   - 米粉汤案例：AI 推理 526 kcal（合理），但 soup 品类校准把 per100g 打成 30，
//     显示成 171 kcal + 75g 碳水（物理不可能自洽）。
//   - 根因：FoodCategoryDefaults.calibrate 用"品类均值"覆盖"AI 具体估算"，
//     方向错误——AI 推理有 reasoning 依据，品类均值是模糊兜底。
//
// 方案 D 修复：
//   1. 废弃 calibrate 的品类校准逻辑（删除比值判断 + 默认值替换）
//   2. 保留 [0, 900] 物理 clamp（防 AI 把水估成 5000）
//   3. 保留宏量 clamp [0, 100]
//
// v2 重构变更：
// - 删除 "酒精饮料豁免 Atwater 校验" group（Atwater 修正已删，correctedCalories 不存在）
//   酒精豁免逻辑已在 recognition_validator_v2_test.dart 覆盖
//   （"酒精饮料 Atwater 偏差大不修正" test）
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/seed/food_category_defaults.dart';
import 'package:eatwise/features/recognize/calibrated_nutrition_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('方案 D：废弃品类校准', () {
    test('米粉汤关键场景：AI 526 kcal/570g（per100g=92.3）不被品类校准覆盖', () {
      // 复现用户报告：米粉汤 AI 推理 526 kcal + 16/13/75，soup 默认 30
      // 修复前：ratio=92.3/30=3.08>2 → cal=30，宏量保留 → 显示 171 kcal + 75g 碳水
      // 修复后：92.3 在 [0, 900] 内 → 保留 AI 值 92.3
      final (cal, p, f, c) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 92.3,
        aiProteinPer100g: 2.8,
        aiFatPer100g: 2.28,
        aiCarbsPer100g: 13.16,
        category: 'soup',
      );
      expect(cal, closeTo(92.3, 0.01), reason: '米粉汤 per100g 保留 AI 估算');
      expect(p, closeTo(2.8, 0.01));
      expect(f, closeTo(2.28, 0.01));
      expect(c, closeTo(13.16, 0.01));
    });

    test('soup 高变异场景：奶油蘑菇汤 per100g=120 保留（不被默认 30 覆盖）', () {
      // 奶油蘑菇汤实际 80-120 kcal/100g，远高于清汤默认 30
      final (cal, _, _, _) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 120,
        aiProteinPer100g: 3,
        aiFatPer100g: 8,
        aiCarbsPer100g: 10,
        category: 'soup',
      );
      expect(cal, closeTo(120, 0.01));
    });

    test('八宝粥 per100g=130 保留（主食类粥品，不被 soup 默认 30 覆盖）', () {
      final (cal, _, _, _) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 130,
        aiProteinPer100g: 4,
        aiFatPer100g: 2,
        aiCarbsPer100g: 25,
        category: 'soup',
      );
      expect(cal, closeTo(130, 0.01));
    });

    test('AI 离谱估算（5000 kcal/100g）仍被 clamp 到 900（防物理不可能值）', () {
      // 物理 clamp 保留——这是方案 D 的核心安全网
      final (cal, _, _, _) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 5000,
        aiProteinPer100g: 6,
        aiFatPer100g: 35,
        aiCarbsPer100g: 53,
        category: 'solid',
      );
      expect(cal, 900);
    });

    test('负值仍被 clamp 到 0', () {
      final (cal, _, _, _) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: -100,
        aiProteinPer100g: 0,
        aiFatPer100g: 0,
        aiCarbsPer100g: 0,
        category: 'soup',
      );
      expect(cal, 0);
    });

    test('宏量超 100 仍被 clamp 到 100', () {
      final (_, p, f, c) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 500,
        aiProteinPer100g: 150,
        aiFatPer100g: 200,
        aiCarbsPer100g: 120,
        category: 'solid',
      );
      expect(p, 100);
      expect(f, 100);
      expect(c, 100);
    });

    test('beer 离谱估算（per100g=200）不再被覆盖为默认值 43', () {
      // 方案 D 改变行为：不再用 43 覆盖。用户通过 reasoning 透明可审查 +
      // PostProcessor 重试机制兜底，不再用品类均值替换 AI 具体估算。
      final (cal, p, f, c) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 200,
        aiProteinPer100g: 2,
        aiFatPer100g: 1,
        aiCarbsPer100g: 15,
        category: 'beer',
      );
      expect(cal, closeTo(200, 0.01), reason: '方案 D：信任 AI 具体估算');
      expect(p, 2);
      expect(f, 1);
      expect(c, 15);
    });
  });

  group('方案 D：端到端 CalibratedNutritionCalculator 一致性', () {
    test('米粉汤完整链路：actualCalories=526（与 AI 推理一致）', () {
      // 复现用户截图：米粉汤 mid=570g, AI cal=526, p=16, f=13, c=75
      // 修复前：actualCalories=171（被品类校准）
      // 修复后：actualCalories=526（信任 AI）
      final r = VisionRecognitionResult(
        dishName: '米粉汤',
        estimatedWeightGLow: 540,
        estimatedWeightGMid: 570,
        estimatedWeightGHigh: 600,
        foodComponents: const [],
        cookingMethod: 'soup',
        isSingleItem: true,
        confidence: 0.85,
        promptVersion: 'v1.10',
        foodCategory: 'soup',
        estimatedCalories: 526,
        estimatedProteinG: 16,
        estimatedFatG: 13,
        estimatedCarbsG: 75,
      );
      final aiFallback = NutritionResult(
        foodItemId: 0,
        calories: 526,
        proteinG: 16,
        fatG: 13,
        carbsG: 75,
        oilG: 0,
        source: NutritionSource.aiEstimate,
      );
      final result = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiFallback,
        servingG: 570,
      );
      expect(result.caloriesPer100g, closeTo(92.3, 0.1),
          reason: 'per100g = 526*100/570 ≈ 92.3');
      expect(result.actualCalories, closeTo(526, 0.5),
          reason: 'actualCalories = 92.3 * 570 / 100 ≈ 526，与 AI 推理一致');
      expect(result.actualProteinG, closeTo(16, 0.1));
      expect(result.actualFatG, closeTo(13, 0.1));
      expect(result.actualCarbsG, closeTo(75, 0.1));
    });

    test('米粉汤 + 用户调整滑块 servingG=400：actualCalories 按比例缩放', () {
      // 用户吃少点，调整滑块到 400g
      final r = VisionRecognitionResult(
        dishName: '米粉汤',
        estimatedWeightGLow: 540,
        estimatedWeightGMid: 570,
        estimatedWeightGHigh: 600,
        foodComponents: const [],
        cookingMethod: 'soup',
        isSingleItem: true,
        confidence: 0.85,
        promptVersion: 'v1.10',
        foodCategory: 'soup',
        estimatedCalories: 526,
        estimatedProteinG: 16,
        estimatedFatG: 13,
        estimatedCarbsG: 75,
      );
      final aiFallback = NutritionResult(
        foodItemId: 0,
        calories: 526,
        proteinG: 16,
        fatG: 13,
        carbsG: 75,
        oilG: 0,
        source: NutritionSource.aiEstimate,
      );
      final result = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiFallback,
        servingG: 400,
      );
      // per100g 仍按 mid=570 反算（不随用户调整偏差）
      expect(result.caloriesPer100g, closeTo(92.3, 0.1));
      // actualCalories = 92.3 * 400 / 100 ≈ 369（按用户调整后的 servingG）
      expect(result.actualCalories, closeTo(369, 1));
    });
  });
}
