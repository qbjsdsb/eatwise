// 方案 D 回归测试：废弃品类校准 + 酒精饮料豁免 Atwater
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
//   4. 酒精饮料豁免 Atwater 校验（cal>expected 且品类是 alcohol/beer/wine）
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/core/util/recognition_validator.dart';
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

  group('方案 D：酒精饮料豁免 Atwater 校验', () {
    VisionRecognitionResult beerResult({
      required double cal,
      required double protein,
      required double fat,
      required double carbs,
      String category = 'beer',
    }) {
      return VisionRecognitionResult(
        dishName: '啤酒',
        brand: '',
        estimatedWeightGLow: 250,
        estimatedWeightGMid: 300,
        estimatedWeightGHigh: 350,
        foodComponents: const [],
        cookingMethod: 'drink',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.10',
        foodCategory: category,
        estimatedCalories: cal,
        estimatedProteinG: protein,
        estimatedFatG: fat,
        estimatedCarbsG: carbs,
      );
    }

    test('啤酒 cal=129 p=1.5 f=0 c=9.3（Atwater=43.8）不被错误修正', () {
      // 1 瓶 330ml 啤酒约 129 kcal（含酒精 7kcal/g 不在 Atwater 系数内）
      // 修复前：expected=4*1.5+9*0+4*9.3=43.2，偏差 66% > 10% → 修正为 43.2（丢失酒精热量）
      // 修复后：beer/wine/alcohol 品类豁免 Atwater，保留 AI cal=129
      final v = RecognitionValidator.validate(beerResult(
        cal: 129,
        protein: 1.5,
        fat: 0,
        carbs: 9.3,
      ));
      expect(v.correctedCalories, isNull,
          reason: '酒精饮料豁免 Atwater 校验，保留 AI cal');
    });

    test('葡萄酒（wine 品类）同样豁免', () {
      // 1 杯 150ml 葡萄酒约 125 kcal
      final v = RecognitionValidator.validate(beerResult(
        cal: 125,
        protein: 0.1,
        fat: 0,
        carbs: 4,
        category: 'wine',
      ));
      expect(v.correctedCalories, isNull);
    });

    test('酒精饮料豁免不影响"cal=0 但有宏量"分支（仍修正为 expected）', () {
      // 豁免只针对"cal>0 但 expected 严重不符"分支
      // cal=0 但有宏量 → 仍走"瞎算修正为 expected"逻辑
      final v = RecognitionValidator.validate(beerResult(
        cal: 0,
        protein: 5,
        fat: 0,
        carbs: 10,
      ));
      expect(v.correctedCalories, isNotNull, reason: 'cal=0 有宏量仍修正');
      expect(v.correctedCalories, 4 * 5 + 9 * 0 + 4 * 10);
    });

    test('非酒精饮料（soup）cal 严重不自洽仍修正', () {
      // 米粉汤 526 kcal + 16/13/75 自洽（偏差 9%），不修正——这是正常情况
      // 这里测一个真正不自洽的：cal=200 + 16/13/75（偏差 130%）→ 修正
      // 确保豁免只对酒精饮料生效，不误伤其他品类
      final v = RecognitionValidator.validate(VisionRecognitionResult(
        dishName: '汤',
        brand: '',
        estimatedWeightGLow: 540,
        estimatedWeightGMid: 570,
        estimatedWeightGHigh: 600,
        foodComponents: const [],
        cookingMethod: 'soup',
        isSingleItem: true,
        confidence: 0.85,
        promptVersion: 'v1.10',
        foodCategory: 'soup',
        estimatedCalories: 200,
        estimatedProteinG: 16,
        estimatedFatG: 13,
        estimatedCarbsG: 75,
      ));
      // expected = 4*16+9*13+4*75 = 481, cal=200, 偏差 140% → 修正为 481
      expect(v.correctedCalories, 481, reason: '非酒精饮料不自洽仍修正');
    });
  });
}
