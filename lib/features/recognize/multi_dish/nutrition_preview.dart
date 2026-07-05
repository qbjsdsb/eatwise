import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/features/recognize/calibrated_nutrition_calculator.dart';
import 'package:eatwise/features/recognize/recognize_controller.dart';

/// 多菜列表页营养素预览计算（从 multi_dish_page.dart 拆出，M24 B4）
///
/// 包含：
/// - [calc]：计算某菜当前份量的营养素（基于查库结果按比例缩放）
/// - [computeLookupHitCalibrated]：查库命中分支差异检测
/// - [computeCompositeLookupHitCalibrated]：复合菜查库命中 + AI 整菜估算 AI 绝对优先
///
/// 逻辑与拆分前完全一致（字节级保留），仅从 _MultiDishPageState 方法迁移为静态方法，
/// 数据通过参数注入（不访问 StatefulWidget 状态），保证独立可测。
///
/// 硬约束：
/// - #2：foodItemId=0 哨兵替换逻辑在 _recordAll 中（调 CalibratedNutritionCalculator）
/// - #3：multi_dish_page 仍是 AI 兜底三路径之一
/// - #4：per100g 反算基于 estimatedWeightGMid（包装路径用 packageServingG 换算）
class NutritionPreview {
  NutritionPreview._();

  /// M16.8：查库命中分支差异检测计算（_calcNutrition 预览 + _recordAll 记录共用，
  /// 保证预览=记录）。
  ///
  /// 条件：currentSingle 非空 + foodItemId > 0（查库命中）+ aiFallback 非空 +
  ///       无包装营养表（包装是精确值，不走差异检测）。
  /// 返回 null 表示不满足条件，调用方走原逻辑（n.* * ratio）。
  static CalibratedNutrition? computeLookupHitCalibrated({
    required VisionRecognitionResult dish,
    required double serving,
    required NutritionResult? currentSingle,
    required NutritionResult? aiFallback,
  }) {
    // 包装营养表优先（精确值，不走差异检测）
    if (dish.hasPackageNutrition) return null;
    if (currentSingle == null || currentSingle.foodItemId <= 0) return null;
    if (aiFallback == null) return null;
    return CalibratedNutritionCalculator.compute(
      recognitionResult: dish,
      aiFallback: aiFallback,
      servingG: serving,
      lookupHitNutrition: currentSingle,
    );
  }

  /// M16.9：复合菜查库命中 + AI 整菜估算 → AI 绝对优先
  /// M18：抽取为 CalibratedNutritionCalculator.computeCompositeLookupHit 公共方法
  /// 三路径（recognize_page / multi_dish_page / offline_queue_controller）共用
  /// per100g 从 0 占位改为 AI 反算值，让 AI 估算进入食物库
  static CalibratedNutrition? computeCompositeLookupHitCalibrated({
    required VisionRecognitionResult dish,
    required double serving,
    required CompositeNutritionResult? composite,
    required NutritionResult? aiFallback,
  }) {
    // 包装营养表优先（精确值，不走差异检测）
    if (dish.hasPackageNutrition) return null;
    if (composite == null) return null;
    if (aiFallback == null) return null;
    // 委托公共方法：AI 有效返回 per100g=AI 反算值 + actualXxx；AI 无效返回 null
    return CalibratedNutritionCalculator.computeCompositeLookupHit(
      aiFallback: aiFallback,
      servingG: serving,
      mid: dish.estimatedWeightGMid,
    );
  }

  /// 计算某菜当前份量的营养素（基于查库结果按比例缩放）
  /// 单品和复合菜都按 ratio = serving / estimatedWeightGMid 缩放
  ///
  /// [index] 0=主菜，>0=附加菜（index-1 对应 additionalItems）
  /// [mainComposite] 主菜的复合菜查库结果（仅 index==0 用）
  /// [additionalItems] 附加菜列表（仅 index>0 用，取 additionalItems[index-1].compositeNutrition）
  static (double, double, double, double) calc({
    required int index,
    required VisionRecognitionResult dish,
    required double serving,
    required NutritionResult? currentSingle,
    required NutritionResult? aiFallback,
    required CompositeNutritionResult? composite,
    required CompositeNutritionResult? mainComposite,
    required List<MultiDishItem> additionalItems,
  }) {
    // 防除零：estimatedWeightGMid <= 0 时 ratio=1（用原值）
    final mid = dish.estimatedWeightGMid;
    final ratio = mid > 0 ? serving / mid : 1.0;
    // v1.9：有包装营养表数据时，按包装 per100g 换算（精确值），跳过库值/AI 估算
    // 包装换算热量 = per100g × serving / 100（直接用份量，与单品 ratio 缩放结果一致）
    // v1.10：包装换算宏量全 0 但 cal>0（含糖饮料 AI 漏填宏量）→ 不返回 0，继续走下游路径
    if (dish.hasPackageNutrition) {
      final per100 = dish.computePackageNutritionPer100g(
        estimatedProteinG: dish.estimatedProteinG,
        estimatedFatG: dish.estimatedFatG,
        estimatedCarbsG: dish.estimatedCarbsG,
      );
      // v1.10：仅当宏量非全 0 才用包装换算结果（含糖饮料兜底走下游 n.* ratio）
      if (per100 != null && (per100.$2 > 0 || per100.$3 > 0 || per100.$4 > 0)) {
        return (
          per100.$1 * serving / 100,
          per100.$2 * serving / 100,
          per100.$3 * serving / 100,
          per100.$4 * serving / 100,
        );
      }
    }
    if (index == 0) {
      // 主菜
      // M16.8：查库命中 + aiFallback → 差异检测（与 _recordAll 一致，保证预览=记录）
      final calibrated = computeLookupHitCalibrated(
        dish: dish,
        serving: serving,
        currentSingle: currentSingle,
        aiFallback: aiFallback,
      );
      if (calibrated != null) {
        return (
          calibrated.actualCalories,
          calibrated.actualProteinG,
          calibrated.actualFatG,
          calibrated.actualCarbsG,
        );
      }
      // 改菜名后用 currentSingle（rename 后实时刷新）
      if (currentSingle != null) {
        return (
          currentSingle.calories * ratio,
          currentSingle.proteinG * ratio,
          currentSingle.fatG * ratio,
          currentSingle.carbsG * ratio,
        );
      }
      // M16.9：复合菜查库命中 + AI 整菜估算 → AI 绝对优先
      final compositeCalibrated = computeCompositeLookupHitCalibrated(
        dish: dish,
        serving: serving,
        composite: composite,
        aiFallback: aiFallback,
      );
      if (compositeCalibrated != null) {
        return (
          compositeCalibrated.actualCalories,
          compositeCalibrated.actualProteinG,
          compositeCalibrated.actualFatG,
          compositeCalibrated.actualCarbsG,
        );
      }
      if (mainComposite != null) {
        return (
          mainComposite.calories * ratio,
          mainComposite.proteinG * ratio,
          mainComposite.fatG * ratio,
          mainComposite.carbsG * ratio,
        );
      }
    } else {
      // additionalDishes（index-1 对应 additionalItems）
      // M16.8：查库命中 + aiFallback → 差异检测（与 _recordAll 一致，保证预览=记录）
      final calibrated = computeLookupHitCalibrated(
        dish: dish,
        serving: serving,
        currentSingle: currentSingle,
        aiFallback: aiFallback,
      );
      if (calibrated != null) {
        return (
          calibrated.actualCalories,
          calibrated.actualProteinG,
          calibrated.actualFatG,
          calibrated.actualCarbsG,
        );
      }
      // 改菜名后用 currentSingle（rename 后实时刷新）
      if (currentSingle != null) {
        return (
          currentSingle.calories * ratio,
          currentSingle.proteinG * ratio,
          currentSingle.fatG * ratio,
          currentSingle.carbsG * ratio,
        );
      }
      // M16.9：复合菜查库命中 + AI 整菜估算 → AI 绝对优先
      final compositeCalibrated = computeCompositeLookupHitCalibrated(
        dish: dish,
        serving: serving,
        composite: composite,
        aiFallback: aiFallback,
      );
      if (compositeCalibrated != null) {
        return (
          compositeCalibrated.actualCalories,
          compositeCalibrated.actualProteinG,
          compositeCalibrated.actualFatG,
          compositeCalibrated.actualCarbsG,
        );
      }
      final item = additionalItems[index - 1];
      if (item.compositeNutrition != null) {
        final n = item.compositeNutrition!;
        return (
          n.calories * ratio,
          n.proteinG * ratio,
          n.fatG * ratio,
          n.carbsG * ratio,
        );
      }
    }
    return (0, 0, 0, 0);
  }
}
