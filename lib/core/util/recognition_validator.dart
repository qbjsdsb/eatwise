// 识别结果校验器（重构：AI 绝对优先 + warnings 检测不修改）
//
// 设计变更（v2）：
// 1. 字段合理性（dishName 非空、confidence 在 [0,1]、weight>0、区间不倒置）
//    —— 不合理触发 needsRetry，让 controller 重试 1 次（模型偶发错误）
// 2. 物理约束检测（Atwater 偏差/宏量缺失/密度异常/宏量上限）
//    —— 不修改 AI 估算值，仅输出 warnings 提示用户核对
// 3. 组分份量交叉验证（sum(components) vs mid 偏差>15% 按 mid 缩放）
//    —— 信任 mid（AI 整菜估算），不是覆盖 AI 估算
//
// 删除的旧逻辑：
// - Atwater 自洽修正（4p+9f+4c≠cal > 10% → 用宏量反推覆盖 cal）
// - 宏量反推（cal>0 但宏量缺失 → 按品类默认比例填充）
// - cal≤0 但 expected>0 → 用宏量反推覆盖
//
// 设计依据：AI 估算值绝对不被静默修改（用户感知"reasoning 显示值=记录值"）。
// 物理约束改为 warnings 提示，用户作为最终兜底（UI 显示警告 + 手动编辑入口）。
import '../../ai/vision_provider.dart';

class RecognitionValidator {
  RecognitionValidator._();

  /// 校验识别结果
  ///
  /// [result] 待校验的识别结果（主菜或附加菜）
  /// 返回 [RecognitionValidationResult]
  static RecognitionValidationResult validate(VisionRecognitionResult result) {
    final reasons = <String>[];
    final warnings = <String>[];
    var needsRetry = false;

    // 1. dishName 非空
    final nameTrimmed = result.dishName.trim();
    if (nameTrimmed.isEmpty) {
      reasons.add('dish_name 为空');
      needsRetry = true;
    }

    // 2. confidence 在 [0, 1]（NaN 也视为越界：NaN<0=false, NaN>1=false 会漏过，
    //    显式 isNaN 判断防 AI 返回非数值字符串解析为 NaN 时通过校验）
    final conf = result.confidence;
    if (conf.isNaN || conf < 0 || conf > 1) {
      reasons.add('confidence 越界: $conf');
      needsRetry = true;
    }

    // 3. estimatedWeightGMid > 0（NaN 同理显式判断）
    final mid = result.estimatedWeightGMid;
    if (mid.isNaN || mid <= 0) {
      reasons.add('estimated_weight_g_mid 非正: $mid');
      needsRetry = true;
    }

    // 4. 区间不倒置（low <= mid <= high），允许相等（单品 per_unit_g*quantity 精确值）
    //    NaN 比较全为 false 会漏过，已在上面校验 mid，low/high 的 NaN 由 fromJson 兜底
    if (result.estimatedWeightGLow > result.estimatedWeightGMid ||
        result.estimatedWeightGHigh < result.estimatedWeightGMid) {
      reasons.add('重量区间倒置: low=${result.estimatedWeightGLow}, '
          'mid=${result.estimatedWeightGMid}, high=${result.estimatedWeightGHigh}');
      needsRetry = true;
    }

    // 5. 物理约束检测（不修改值，仅输出 warnings）
    //    AI 估算值绝对保留，用户通过 UI 警告 + 手动编辑兜底
    final cal = result.estimatedCalories;
    if (cal != null) {
      final protein = result.estimatedProteinG ?? 0;
      final fat = result.estimatedFatG ?? 0;
      final carbs = result.estimatedCarbsG ?? 0;

      // 5a. 宏量全缺失检测（cal>0 但三宏量全 0）
      //     含糖饮料 AI 漏填全部宏量等场景，提示用户核对
      //     注意：p=0/f=0 但 carbs>0（如可乐）是合理的，不警告
      if (cal > 0 && protein == 0 && fat == 0 && carbs == 0) {
        warnings.add('AI 估算热量=${cal.toStringAsFixed(0)}kcal 但宏量全为 0，请核对');
      }

      // 5b. Atwater 自洽性检测（不修正，仅警告）
      //     酒精饮料豁免：酒精热量（7kcal/g）不在 Atwater 系数（4p+9f+4c）内
      final isAlcohol = result.foodCategory == 'beer' ||
          result.foodCategory == 'wine' ||
          result.foodCategory == 'alcohol';
      final expected = 4 * protein + 9 * fat + 4 * carbs;
      if (!isAlcohol && cal > 0 && expected > 0) {
        final diff = (expected - cal).abs();
        final ratio = diff / cal;
        if (ratio > 0.10) {
          warnings.add('宏量与热量不自洽：AI 估算 ${cal.toStringAsFixed(0)}kcal，'
              '宏量加和 ${expected.toStringAsFixed(0)}kcal（偏差 ${(ratio * 100).toStringAsFixed(1)}%），请核对');
        }
      }
      // 5c. cal≤0 但有宏量（异常但不修改，提示用户）
      if (cal <= 0 && expected > 0) {
        warnings.add('AI 估算 calories=$cal，但宏量加和=${expected.toStringAsFixed(0)}kcal，请核对');
      }

      // 5d. 密度异常检测（per100g > 900，物理上限约 900）
      //     纯脂肪油 889 kcal/100g 是物理上限，>900 多半是 AI 幻觉
      //     不覆盖 AI 值，提示用户核对
      if (mid > 0) {
        final per100g = cal * 100 / mid;
        if (per100g > 900) {
          warnings.add('密度异常高（${per100g.toStringAsFixed(0)}kcal/100g），请核对');
        }
      }

      // 5e. 宏量物理上限检测（蛋白+脂肪+碳水 > 100g/100g 不可能）
      //     食物每 100g 中宏量加和不可能 > 100g
      if (mid > 0) {
        final macroSumPer100 = (protein + fat + carbs) * 100 / mid;
        if (macroSumPer100 > 100) {
          warnings.add('宏量超出物理上限（蛋白+脂肪+碳水=${macroSumPer100.toStringAsFixed(0)}g/100g），请核对');
        }
      }
    }

    // 6. 建议 7：复合菜组分份量交叉验证（保留，信任 mid）
    // sum(components.estimated_g) 应 ≈ estimated_weight_g_mid（±15%）
    // AI 常出现"鸡蛋120g+番茄150g=270g"但整菜 mid=250g 的不自洽
    // 不自洽时按 mid 比例缩放各组分（mid 是 AI 整菜估算，相对可信）
    // v1.11：缩放时保留各组分营养字段（calories/proteinG/fatG/carbsG 同比缩放，per100g 不变）
    List<FoodComponent>? correctedComponents;
    if (!result.isSingleItem && result.foodComponents.isNotEmpty) {
      final sumG =
          result.foodComponents.fold(0.0, (s, c) => s + c.estimatedG);
      final mid = result.estimatedWeightGMid;
      if (sumG > 0 && mid > 0) {
        final ratio = mid / sumG;
        // 偏差超 15% → 缩放（±15% 内视为合理波动，不修正避免过度干预）
        if ((ratio - 1).abs() > 0.15) {
          correctedComponents = result.foodComponents
              .map((c) => c.scaled(ratio))
              .toList();
          reasons.add('组分份量不自洽: sum=${sumG.toStringAsFixed(0)}g, '
              'mid=${mid.toStringAsFixed(0)}g, 按 mid 缩放 ${ratio.toStringAsFixed(2)}x');
        }
      }
    }

    return RecognitionValidationResult(
      isValid: reasons.isEmpty,
      needsRetry: needsRetry,
      correctedComponents: correctedComponents,
      warnings: warnings,
      reasons: reasons,
    );
  }
}

/// 校验结果
class RecognitionValidationResult {
  /// 是否通过校验（无字段合理性问题）
  final bool isValid;

  /// 是否需要重试（字段严重不合理：dishName 空 / confidence 越界 / weight 非正 / 区间倒置）
  final bool needsRetry;

  /// 建议 7：组分份量交叉验证修正后的组分列表（null 表示无需修正或不适用）
  /// controller 用此值覆盖 VisionRecognitionResult.foodComponents
  /// 保留：这是信任 mid（AI 整菜估算），不是覆盖 AI 估算
  final List<FoodComponent>? correctedComponents;

  /// 物理约束警告（不修改 AI 估算值，提示用户核对）
  /// UI 在 reasoning 卡片下方显示警告横幅，用户可手动编辑营养值兜底
  final List<String> warnings;

  /// 校验失败原因（字段合理性，用于 Sentry 上报 + 调试日志）
  final List<String> reasons;

  const RecognitionValidationResult({
    required this.isValid,
    required this.needsRetry,
    required this.correctedComponents,
    required this.warnings,
    required this.reasons,
  });
}
