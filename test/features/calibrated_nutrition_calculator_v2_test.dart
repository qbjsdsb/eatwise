// CalibratedNutritionCalculator v2 单元测试（重构：删除 AI 离谱兜底）
//
// 验证改动 B：
// 1. AI per100g>900 不再用库值兜底（始终用 AI 值，warnings 提示用户核对）
// 2. 复合菜 AI per100g>900 不再返回 null（始终返回 AI 值）
// 3. shouldUpdateFoodItem 逻辑保留（diffRatio>0 时纠正库）
// 4. 米粉汤回归（AI per100g=92.3 正常场景不被破坏）
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/features/recognize/calibrated_nutrition_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 构造查库命中 + AI 离谱估算场景
  // mid=100g, AI cal=5000 → per100g=5000（>900 离谱）
  // 库 per100g=100 → lookupHit.calories=100（mid=100 时 calories=per100g*mid/100=100）
  VisionRecognitionResult aiOutrageousResult({
    double mid = 100,
    double aiCal = 5000,
  }) {
    return VisionRecognitionResult(
      dishName: '测试菜',
      brand: '',
      estimatedWeightGLow: mid * 0.9,
      estimatedWeightGMid: mid,
      estimatedWeightGHigh: mid * 1.1,
      foodComponents: const [],
      cookingMethod: 'raw',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.10',
      foodCategory: 'solid',
      estimatedCalories: aiCal,
      estimatedProteinG: 50,
      estimatedFatG: 50,
      estimatedCarbsG: 50,
    );
  }

  group('改动 B：删除 AI 离谱兜底（库值不再覆盖 AI）', () {
    test('AI per100g=5000 + 库命中：始终用 AI 值，不再用库值兜底', () {
      // mid=100g, AI cal=5000 → per100g=5000（>900 离谱）
      // 库 per100g=100 → lookupHit.calories=100（mid=100 时 calories=per100g*mid/100=100）
      // 旧逻辑：aiValid=false → 用库 per100g=100，actualCalories=100*100/100=100
      // 新逻辑：始终用 AI → actualCalories=5000*100/100=5000
      final r = aiOutrageousResult();
      final aiFallback = NutritionResult(
        foodItemId: 0,
        calories: 5000,
        proteinG: 50,
        fatG: 50,
        carbsG: 50,
        oilG: 0,
        source: NutritionSource.aiEstimate,
      );
      final lookupHit = NutritionResult(
        foodItemId: 123,
        calories: 100, // mid=100 时 calories=per100g*mid/100=100
        proteinG: 1,
        fatG: 1,
        carbsG: 20,
        oilG: 0,
        source: NutritionSource.database,
      );
      final result = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiFallback,
        servingG: 100,
        lookupHitNutrition: lookupHit,
      );
      // 新逻辑：始终用 AI 值
      expect(result.caloriesPer100g, closeTo(5000, 0.1),
          reason: 'AI per100g=5000 不被库值 100 覆盖');
      expect(result.actualCalories, closeTo(5000, 0.1),
          reason: 'actualCalories 用 AI 值 5000，不用库值 100');
      expect(result.foodItemId, 123,
          reason: 'foodItemId 仍是库命中的 123');
      // shouldUpdateFoodItem：AI 与库 diffRatio>0 时为 true（让 AI 持续纠正库）
      expect(result.shouldUpdateFoodItem, isTrue,
          reason: 'AI 离谱值也应进入库（让用户后续可见，库值跟随 AI）');
    });

    test('复合菜 AI per100g=5000：始终返回 AI 值，不再返回 null', () {
      // mid=100, AI cal=5000 → per100g=5000（>900 离谱）
      // 旧逻辑：aiValid=false → 返回 null，调用方走 ratio 兜底
      // 新逻辑：始终返回 AI 值
      final aiFallback = NutritionResult(
        foodItemId: 0,
        calories: 5000,
        proteinG: 50,
        fatG: 50,
        carbsG: 50,
        oilG: 0,
        source: NutritionSource.aiEstimate,
      );
      final result = CalibratedNutritionCalculator.computeCompositeLookupHit(
        aiFallback: aiFallback,
        servingG: 100,
        mid: 100,
      );
      expect(result, isNotNull, reason: 'AI 离谱不再返回 null');
      expect(result!.caloriesPer100g, closeTo(5000, 0.1));
      expect(result.actualCalories, closeTo(5000, 0.1));
      expect(result.foodItemId, 0, reason: '复合菜哨兵分支 foodItemId=0');
      expect(result.shouldUpdateFoodItem, isTrue,
          reason: '复合菜始终写库，让 AI 值进入食物库');
    });

    test('复合菜 mid=0 仍返回 null（防除零）', () {
      // mid=0 防除零保留，不删除
      final aiFallback = NutritionResult(
        foodItemId: 0,
        calories: 500,
        proteinG: 5,
        fatG: 5,
        carbsG: 50,
        oilG: 0,
        source: NutritionSource.aiEstimate,
      );
      final result = CalibratedNutritionCalculator.computeCompositeLookupHit(
        aiFallback: aiFallback,
        servingG: 100,
        mid: 0,
      );
      expect(result, isNull, reason: 'mid=0 防除零返回 null 保留');
    });
  });

  group('改动 B 回归：AI 正常场景不被破坏', () {
    test('米粉汤 AI per100g=92.3 + 库命中：用 AI 反算 per100g 写库', () {
      // 米粉汤 mid=570, AI cal=526 → per100g=92.3（正常区间）
      // 库 per100g=80 → lookupHit.calories=80*570/100=456
      // 期望：始终用 AI 值，per100g=92.3, actualCalories=526
      final r = VisionRecognitionResult(
        dishName: '米粉汤',
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
      final lookupHit = NutritionResult(
        foodItemId: 456,
        calories: 456, // per100g=80 × mid=570 / 100 = 456
        proteinG: 10,
        fatG: 5,
        carbsG: 60,
        oilG: 0,
        source: NutritionSource.database,
      );
      final result = CalibratedNutritionCalculator.compute(
        recognitionResult: r,
        aiFallback: aiFallback,
        servingG: 570,
        lookupHitNutrition: lookupHit,
      );
      expect(result.caloriesPer100g, closeTo(92.3, 0.1),
          reason: 'per100g 用 AI 反算值 526*100/570 ≈ 92.3');
      expect(result.actualCalories, closeTo(526, 0.5),
          reason: 'actualCalories 用 AI 值 526');
      expect(result.actualProteinG, closeTo(16, 0.1));
      expect(result.actualFatG, closeTo(13, 0.1));
      expect(result.actualCarbsG, closeTo(75, 0.1));
      expect(result.foodItemId, 456);
      expect(result.shouldUpdateFoodItem, isTrue,
          reason: 'AI per100g=92.3 与库 80 diffRatio>0，触发库更新');
    });

    test('米粉汤 + 用户调整滑块 servingG=400：actualCalories 按比例缩放', () {
      final r = VisionRecognitionResult(
        dishName: '米粉汤',
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
      // actualCalories = 92.3 * 400 / 100 ≈ 369
      expect(result.actualCalories, closeTo(369, 1));
      expect(result.foodItemId, 0, reason: '无库命中走哨兵分支');
    });
  });
}
