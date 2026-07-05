import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/seed/food_category_defaults.dart';

/// AI 兜底哨兵路径（foodItemId=0）下，用品类校准后的 per100g 计算 actualNutrition。
///
/// 三路径（recognize_page / multi_dish_page / offline_queue_controller）共用此方法，
/// 保证 actualCalories 与食物库 per100g 一致，避免数据脱节（M16.6 修复）。
///
/// 逻辑：
/// 1. 有包装数据且包装换算宏量非全 0 → 用 packagePer100（精确值，不走品类校准）
/// 2. 无包装数据 / 包装换算宏量全 0 → 用 FoodCategoryDefaults.calibrate 校准 per100g
/// 3. actualCalories/ProteinG/FatG/CarbsG = 校准后 per100g * servingG / 100
///
/// 返回 [CalibratedNutrition]：
/// - per100g 字段用于写食物库（food_item）
/// - actualXxx 字段用于写 meal_log
class CalibratedNutritionCalculator {
  CalibratedNutritionCalculator._();

  /// 计算 per100g（写库用）+ actualNutrition（写 meal_log 用）
  ///
  /// [recognitionResult] AI 视觉识别结果（含包装数据、品类、mid 重量）
  /// [aiFallback] 来自 _aiFallbackNutrition，foodItemId=0，calories 对应 mid 份量
  /// [servingG] 用户调整后的份量（前台）或 AI mid（后台）
  static CalibratedNutrition compute({
    required VisionRecognitionResult recognitionResult,
    required NutritionResult aiFallback,
    required double servingG,
  }) {
    final r = recognitionResult;
    final mid = r.estimatedWeightGMid;
    // mid → per100g 反算系数：aiFallback.calories 对应 mid 份量，per100g = calories * 100 / mid
    // 防除零：mid <= 0 时 per100Ratio = 0（per100g 全部归 0）
    final per100Ratio = mid > 0 ? 100.0 / mid : 0.0;

    // v1.9：包装食品 OCR 优先路径——有包装营养表数据时按包装换算，
    // 跳过品类校准（包装数据是精确值，不需要校准）
    final packagePer100 = r.hasPackageNutrition
        ? r.computePackageNutritionPer100g(
            // 哨兵分支 aiFallback 来自 _aiFallbackNutrition，
            // aiFallback.proteinG 等于 r.estimatedProteinG ?? 0，直传即可
            estimatedProteinG: r.estimatedProteinG,
            estimatedFatG: r.estimatedFatG,
            estimatedCarbsG: r.estimatedCarbsG,
          )
        : null;
    // v1.10：判断包装换算宏量是否全 0（含糖饮料 AI 漏填宏量特征）
    final packageMacrosAllZero = packagePer100 != null &&
        packagePer100.$2 == 0 &&
        packagePer100.$3 == 0 &&
        packagePer100.$4 == 0;

    final (caloriesPer100g, proteinPer100g, fatPer100g, carbsPer100g) =
        (packagePer100 != null && !packageMacrosAllZero)
            ? packagePer100
            : FoodCategoryDefaults.calibrate(
                // AI per100g = aiFallback.calories * 100 / mid（aiFallback.calories 对应 mid 份量）
                aiCaloriesPer100g: aiFallback.calories * per100Ratio,
                aiProteinPer100g: aiFallback.proteinG * per100Ratio,
                aiFatPer100g: aiFallback.fatG * per100Ratio,
                aiCarbsPer100g: aiFallback.carbsG * per100Ratio,
                category: r.foodCategory,
              );

    // 统一：actualXxx = 校准后 per100g * servingG / 100
    // 保证 meal_log.actualCalories 与 food_item.caloriesPer100g 数据一致
    return CalibratedNutrition(
      caloriesPer100g: caloriesPer100g,
      proteinPer100g: proteinPer100g,
      fatPer100g: fatPer100g,
      carbsPer100g: carbsPer100g,
      actualCalories: caloriesPer100g * servingG / 100,
      actualProteinG: proteinPer100g * servingG / 100,
      actualFatG: fatPer100g * servingG / 100,
      actualCarbsG: carbsPer100g * servingG / 100,
    );
  }
}

/// 校准后的营养值结果。
///
/// - per100g 字段：写入 food_item 表（食物库）
/// - actualXxx 字段：写入 meal_log 表（实际摄入）
///
/// 不变量：actualXxx = 对应 per100g * servingG / 100
class CalibratedNutrition {
  final double caloriesPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;
  final double actualCalories;
  final double actualProteinG;
  final double actualFatG;
  final double actualCarbsG;

  const CalibratedNutrition({
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
    required this.actualCalories,
    required this.actualProteinG,
    required this.actualFatG,
    required this.actualCarbsG,
  });
}
