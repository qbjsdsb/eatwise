import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/seed/food_category_defaults.dart';

/// AI 兜底哨兵路径（foodItemId=0）+ 查库命中路径（foodItemId>0）下，
/// 用品类校准后的 per100g 计算 actualNutrition。
///
/// v2 重构：删除 AI 离谱兜底（库值不再覆盖 AI）。
/// 查库命中分支始终用 AI 反算 per100g 写库 + 用 AI 值记 meal_log；
/// AI 离谱（per100g>900）时通过 validator warnings 提示用户手动纠正，
/// 不再用库值覆盖 AI 估算值（用户感知"AI 推理值=记录值"）。
/// shouldUpdateFoodItem 逻辑保留（diffRatio>0 时纠正库，让 AI 持续纠正库）。
///
/// 三路径（recognize_page / multi_dish_page / offline_queue_controller）共用此方法，
/// 保证 actualCalories 与 AI 估算一致（用户感知"AI 准=记录准"）。
///
/// 逻辑：
/// 1. 查库命中分支（lookupHitNutrition != null && foodItemId > 0）：
///    始终用 AI 反算 per100g 写库 + 用 AI 值记录
///    shouldUpdateFoodItem：diffRatio > 0 时为 true（避免无意义写库）
/// 2. AI 兜底哨兵分支（foodItemId == 0）：
///    - 有包装数据且包装换算宏量非全 0 → 用 packagePer100（精确值，不走品类校准）
///    - 无包装数据 / 包装换算宏量全 0 → 用 FoodCategoryDefaults.calibrate 校准 per100g
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
  /// [lookupHitNutrition] 查库命中时的 NutritionResult（foodItemId > 0）；
  ///   null 表示库未命中走 AI 兜底哨兵分支
  static CalibratedNutrition compute({
    required VisionRecognitionResult recognitionResult,
    required NutritionResult aiFallback,
    required double servingG,
    NutritionResult? lookupHitNutrition,
  }) {
    final r = recognitionResult;
    final mid = r.estimatedWeightGMid;
    // mid → per100g 反算系数：aiFallback.calories 对应 mid 份量，per100g = calories * 100 / mid
    // 防除零：mid <= 0 时 per100Ratio = 0（per100g 全部归 0）
    final per100Ratio = mid > 0 ? 100.0 / mid : 0.0;

    // M16.9：查库命中分支（foodItemId > 0）—— AI 估算绝对优先
    // v2 重构：删除 AI 离谱兜底（aiValid 检查），始终用 AI 反算 per100g 写库 + 用 AI 值记 meal_log
    // shouldUpdateFoodItem：AI 与库 diffRatio > 0 时为 true（让 AI 持续纠正库）
    // AI 离谱（per100g>900）时通过 validator warnings 提示用户手动纠正，不再用库值覆盖
    if (lookupHitNutrition != null && lookupHitNutrition.foodItemId > 0) {
      // lookupHit.calories 已是 per100g × mid / 100（参见 nutrition_lookup.dart）
      // 反算库 per100g = lookupHit.calories * 100 / mid = lookupHit.calories * per100Ratio
      final dbPer100Calories = lookupHitNutrition.calories * per100Ratio;

      // AI 估算 per100g = aiFallback.xxx * 100 / mid
      final aiPer100Calories = aiFallback.calories * per100Ratio;
      final aiPer100Protein = aiFallback.proteinG * per100Ratio;
      final aiPer100Fat = aiFallback.fatG * per100Ratio;
      final aiPer100Carbs = aiFallback.carbsG * per100Ratio;

      // AI 绝对优先：始终用 AI 反算 per100g 写库 + 用 AI 值记 meal_log
      // M18：shouldUpdateFoodItem 从 diffRatio > 5% 改为 > 0
      // 让 AI 估算持续纠正库（即便 2% 差异也写库），库值始终跟随 AI
      // diffRatio=0%（完全一致）时仍为 false，避免无意义写库
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
        shouldUpdateFoodItem: diffRatio > 0,
      );
    }

    // AI 兜底哨兵分支（foodItemId == 0）：原 M16.6 逻辑
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
      foodItemId: 0, // 哨兵，调用方需 upsertAiRecognized 替换为真实 id
      shouldUpdateFoodItem: false, // 哨兵分支由 upsertAiRecognized 处理
    );
  }

  /// 复合菜 AI 优先公共方法（M18：从 multi_dish_page 抽取）
  ///
  /// 三路径（recognize_page / multi_dish_page / offline_queue_controller）共用，
  /// 保证复合菜 actualCalories 与 AI 估算一致 + per100g 进入食物库。
  ///
  /// 与单品 [compute] 区别：复合菜无品类校准（组分累加 + AI 估算），
  /// per100g 直接用 AI 反算值（M16.9 时为 0 占位，M18 改为 AI 反算值让 AI 进入库）。
  ///
  /// v2 重构：删除 aiValid 检查，始终返回 AI 反算值。
  /// AI 离谱（per100g>900）时通过 validator warnings 提示用户手动纠正，
  /// 不再返回 null 让调用方走 ratio 兜底（用户感知"AI 推理值=记录值"）。
  ///
  /// 参数：
  /// - [aiFallback] 复合菜 AI 估算（foodItemId=0，calories 对应 mid 份量）
  /// - [servingG] 用户调整后的份量（前台）或 AI mid（后台）
  /// - [mid] AI 视觉识别重量中位数，per100g 反算基准
  ///
  /// 返回：
  /// - 非 null：AI 反算值，调用方应用 per100g 写库 + actualXxx 记 meal_log
  /// - null：mid<=0（防除零），调用方走原 ratio 兜底
  static CalibratedNutrition? computeCompositeLookupHit({
    required NutritionResult aiFallback,
    required double servingG,
    required double mid,
  }) {
    if (mid <= 0) return null; // 防除零

    final per100Ratio = 100.0 / mid;
    // AI 估算 per100g = aiFallback.xxx * 100 / mid
    final aiPer100Calories = aiFallback.calories * per100Ratio;
    final aiPer100Protein = aiFallback.proteinG * per100Ratio;
    final aiPer100Fat = aiFallback.fatG * per100Ratio;
    final aiPer100Carbs = aiFallback.carbsG * per100Ratio;

    // v2 重构：删除 aiValid 检查，始终返回 AI 反算值
    // AI 离谱（per100g>900）由 validator 输出 warnings，用户手动纠正
    // M18：per100g 用 AI 反算值（M16.9 时为 0 占位）
    // shouldUpdateFoodItem 始终 true：让 AI 值进入食物库
    return CalibratedNutrition(
      caloriesPer100g: aiPer100Calories,
      proteinPer100g: aiPer100Protein,
      fatPer100g: aiPer100Fat,
      carbsPer100g: aiPer100Carbs,
      actualCalories: aiPer100Calories * servingG / 100,
      actualProteinG: aiPer100Protein * servingG / 100,
      actualFatG: aiPer100Fat * servingG / 100,
      actualCarbsG: aiPer100Carbs * servingG / 100,
      foodItemId: 0, // 哨兵，调用方需 upsertAiRecognized 替换为真实 id
      shouldUpdateFoodItem: true, // M18：始终写库，让 AI 值进入食物库
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
