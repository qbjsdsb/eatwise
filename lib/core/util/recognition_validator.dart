// 识别结果校验器（批次 1）
//
// 三层校验：
// 1. 字段合理性（dishName 非空、confidence 在 [0,1]、weight>0、区间不倒置）
//    —— 不合理触发 needsRetry，让 controller 重试 1 次（模型偶发错误）
// 2. 营养素自洽性（4*protein + 9*fat + 4*carb ≈ calories，误差 ±10%）
//    —— 不自洽返回 correctedCalories，controller 自动修正（宏量营养素相对可信，calories 易瞎算）
//    —— 参考：Atwater 系数（蛋白质 4 kcal/g、脂肪 9 kcal/g、碳水 4 kcal/g）
//
// 设计依据：营养素自洽校验是食品科学的基础约束，AI 瞎算 calories 时
// 用宏量营养素反推比"重试赌运气"更稳定（重试可能再次瞎算）。
import '../../ai/vision_provider.dart';

class RecognitionValidator {
  RecognitionValidator._();

  /// 营养素自洽性误差容忍度（±10%）
  static const double _calorieTolerance = 0.10;

  /// 校验识别结果
  ///
  /// [result] 待校验的识别结果（主菜或附加菜）
  /// 返回 [RecognitionValidationResult]
  static RecognitionValidationResult validate(VisionRecognitionResult result) {
    final reasons = <String>[];
    var needsRetry = false;

    // 1. dishName 非空
    final nameTrimmed = result.dishName.trim();
    if (nameTrimmed.isEmpty) {
      reasons.add('dish_name 为空');
      needsRetry = true;
    }

    // 2. confidence 在 [0, 1]
    if (result.confidence < 0 || result.confidence > 1) {
      reasons.add('confidence 越界: ${result.confidence}');
      needsRetry = true;
    }

    // 3. estimatedWeightGMid > 0
    if (result.estimatedWeightGMid <= 0) {
      reasons.add('estimated_weight_g_mid 非正: ${result.estimatedWeightGMid}');
      needsRetry = true;
    }

    // 4. 区间不倒置（low <= mid <= high），允许相等（单品 per_unit_g*quantity 精确值）
    if (result.estimatedWeightGLow > result.estimatedWeightGMid ||
        result.estimatedWeightGHigh < result.estimatedWeightGMid) {
      reasons.add('重量区间倒置: low=${result.estimatedWeightGLow}, '
          'mid=${result.estimatedWeightGMid}, high=${result.estimatedWeightGHigh}');
      needsRetry = true;
    }

    // 5. 营养素自洽性校验（仅当 AI 提供了 estimated_calories 时检查）
    //    旧 prompt（v1.0-v1.3）无此字段 → 跳过，向后兼容
    double? correctedCalories;
    final cal = result.estimatedCalories;
    if (cal != null) {
      final protein = result.estimatedProteinG ?? 0;
      final fat = result.estimatedFatG ?? 0;
      final carbs = result.estimatedCarbsG ?? 0;
      final expected = 4 * protein + 9 * fat + 4 * carbs;
      // calories 为 0 但有宏量营养素 → 瞎算，修正
      // calories > 0 但偏差超 ±10% → 修正
      if (cal <= 0 && expected > 0) {
        reasons.add('calories=0 但宏量营养素之和=$expected，修正为 $expected');
        correctedCalories = expected;
      } else if (cal > 0) {
        final diff = (expected - cal).abs();
        final ratio = diff / cal;
        if (ratio > _calorieTolerance) {
          reasons.add('营养素不自洽: calories=$cal, 期望=$expected (4p+9f+4c), '
              '偏差 ${(ratio * 100).toStringAsFixed(1)}%，修正为 $expected');
          correctedCalories = expected;
        }
      }
    }

    return RecognitionValidationResult(
      isValid: reasons.isEmpty,
      needsRetry: needsRetry,
      correctedCalories: correctedCalories,
      reasons: reasons,
    );
  }
}

/// 校验结果
class RecognitionValidationResult {
  /// 是否通过校验（无任何问题）
  final bool isValid;

  /// 是否需要重试（字段严重不合理：dishName 空 / confidence 越界 / weight 非正 / 区间倒置）
  final bool needsRetry;

  /// 营养素自洽性修正后的 calories（null 表示无需修正或不适用）
  /// controller 用此值覆盖 VisionRecognitionResult.estimatedCalories
  final double? correctedCalories;

  /// 校验失败原因（用于 Sentry 上报 + 调试日志）
  final List<String> reasons;

  const RecognitionValidationResult({
    required this.isValid,
    required this.needsRetry,
    required this.correctedCalories,
    required this.reasons,
  });
}
