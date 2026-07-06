// 识别结果后处理器（第二波：三路径一致性提取）
//
// 提取自 recognize_controller._applyDensityConversion/_convertDensityForDish/
// _listIdentical/_correctAdditionalDishes，让前台识别、重试、离线回补三条路径
// 共用同一套后处理逻辑，避免行为分叉（第一波盲区：离线回补完全没走校验链路）。
//
// 后处理四步（顺序敏感）：
// 1. 密度换算（建议 3）：包装液体 ml→g，perUnitG×density，重算 mid/区间
// 2. 字段校验（批次 1）：dishName/confidence/weight/区间 → needsRetry 标记
// 3. 物理约束检测（v2 重构）：Atwater 偏差/宏量缺失/密度异常 → warnings 提示（不修改值）
// 4. 组分份量交叉验证（建议 7）：sum(components) vs mid 偏差>15% 按 mid 缩放
//
// v2 重构变更：
// - 删除 Atwater 修正回写（correctedCalories）
// - 删除宏量反推回写（correctedProteinG/FatG/CarbsG）
// - 新增 warnings 透传（validation.warnings 设置到 result.warnings）
// - 保留组份缩放回写（correctedComponents，信任 mid）
//
// 设计：纯静态方法，不持有状态，不依赖 provider/imageBase64（重试在调用方）。
// 调用方：recognize_controller._validateAndMaybeRetry / offline_queue_controller.processPending
import 'package:flutter/foundation.dart';

import '../../ai/food_density.dart';
import '../../ai/vision_provider.dart';
import 'recognition_validator.dart';

class RecognitionPostProcessor {
  RecognitionPostProcessor._();

  /// 完整后处理：密度换算 → 校验（组份缩放 + warnings 透传，不修改 AI 估算值）
  ///
  /// 调用方在 recognize 成功后、查库前调用。
  /// 不含重试（重试需要 imageBase64 + provider，留在调用方）。
  /// needsRetry 由调用方单独调 [RecognitionValidator.validate] 判断。
  static VisionRecognitionResult process(VisionRecognitionResult original) {
    // 1. 密度换算（建议 3）
    var result = applyDensityConversion(original);

    // 2. 校验 + 组份缩放 + warnings 透传（v2：不修改 AI 估算值）
    final validation = RecognitionValidator.validate(result);
    if (validation.correctedComponents != null) {
      result = result.copyWith(foodComponents: validation.correctedComponents);
    }
    // v2：透传 warnings 到 result（UI 在 reasoning 卡片下方显示警告横幅）
    if (validation.warnings.isNotEmpty) {
      result = result.copyWith(warnings: validation.warnings);
    }

    // 3. additionalDishes 修正（组份缩放 + warnings 透传）
    result = correctAdditionalDishes(result);

    return result;
  }

  /// 建议 3：包装液体食品按密度换算 ml→g
  ///
  /// prompt v1.6 让 AI 读取包装净含量填 per_unit_g，但液体 ml 数值 ≠ g 数值：
  ///   - 食用油 1ml≈0.92g → 100ml 按 100g 算低估 8%
  ///   - 蜂蜜 1ml≈1.42g → 100ml 按 100g 算低估 42%
  ///   - 烈酒 1ml≈0.79g → 100ml 按 100g 算高估 21%
  ///
  /// 换算条件：weight_source=package_label（包装标签）+ food_category 是液体类别
  /// 换算后重算 perUnitG + estimatedWeightG*（按 quantity * realPerUnitG）
  /// 区间按 ±3% 估算（包装标注误差）
  ///
  /// 水基饮料（carbonated/water/soup 密度=1.0）换算后无变化，直接返回不重建
  static VisionRecognitionResult applyDensityConversion(
      VisionRecognitionResult original) {
    // 主菜换算
    final convertedMain = _convertDensityForDish(original);

    // 附加菜换算
    if (original.additionalDishes.isEmpty) return convertedMain;
    final convertedAdditional =
        original.additionalDishes.map(_convertDensityForDish).toList();

    // 主菜无变化 + 附加菜无变化 → 直接返回（避免无谓重建）
    // _convertDensityForDish 不换算时返回原引用，用 identical 比较即可
    if (identical(convertedMain, original) &&
        _listIdentical(convertedAdditional, original.additionalDishes)) {
      return original;
    }

    // 重建带换算后的附加菜
    // v1.9：透传 reasoning + 6 个 package_* 字段（OCR 数据不参与换算，原样保留）
    // v1.10：透传 3 个新字段 packageServingProteinG/FatG/CarbsG（含糖饮料碳水必标，
    //   丢失会导致 computePackageNutritionPer100g 第 1 层优先级失效，回退 OCR 正则）
    return convertedMain.copyWith(additionalDishes: convertedAdditional);
  }

  /// 单个 dish 的密度换算（仅包装液体）
  static VisionRecognitionResult _convertDensityForDish(
      VisionRecognitionResult r) {
    // 仅对包装标签 + 液体类别换算
    if (r.weightSource != 'package_label') return r;
    if (!isLiquidCategory(r.foodCategory)) return r;
    final density = densityOf(r.foodCategory);
    // 密度=1.0（水基饮料）无需换算
    if (density == 1.0) return r;
    // perUnitG 为 0 或负数不换算（防除零/异常）
    if (r.perUnitG <= 0) return r;

    final realPerUnitG = r.perUnitG * density;
    final realMid = realPerUnitG * r.quantity;
    // 区间按 ±3% 估算（包装标注误差）
    final realLow = realMid * 0.97;
    final realHigh = realMid * 1.03;

    debugPrint('[DensityConversion] ${r.dishName}(${r.foodCategory}) '
        'perUnitG: ${r.perUnitG}→${realPerUnitG.toStringAsFixed(1)}, '
        'mid: ${r.estimatedWeightGMid}→${realMid.toStringAsFixed(1)} '
        '(density=$density)');

    return r.copyWith(
      perUnitG: realPerUnitG,
      estimatedWeightGLow: realLow,
      estimatedWeightGMid: realMid,
      estimatedWeightGHigh: realHigh,
    );
  }

  /// 判断两个列表的元素是否引用相同（避免无谓重建）
  static bool _listIdentical(
      List<VisionRecognitionResult> a, List<VisionRecognitionResult> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// 批次 1 + 建议 7：校验并修正 additionalDishes（组份缩放 + warnings 透传，不修改 AI 估算值）
  static VisionRecognitionResult correctAdditionalDishes(
      VisionRecognitionResult result) {
    if (result.additionalDishes.isEmpty) return result;
    final corrected = <VisionRecognitionResult>[];
    var changed = false;
    for (final dish in result.additionalDishes) {
      final v = RecognitionValidator.validate(dish);
      if (v.reasons.isNotEmpty) {
        debugPrint(
            '[RecognitionValidator] 附加菜「${dish.dishName}」校验: ${v.reasons}');
      }
      var modified = dish;
      var dishChanged = false;
      // 建议 7：组分份量交叉验证修正（保留，信任 mid）
      if (v.correctedComponents != null) {
        modified = modified.copyWith(foodComponents: v.correctedComponents);
        dishChanged = true;
      }
      // v2：透传 warnings（不修改 AI 估算值）
      if (v.warnings.isNotEmpty) {
        modified = modified.copyWith(warnings: v.warnings);
        dishChanged = true;
      }
      if (dishChanged) changed = true;
      corrected.add(modified);
    }
    if (!changed) return result;
    // 重建 result 带修正后的 additionalDishes
    return result.copyWith(additionalDishes: corrected);
  }
}

