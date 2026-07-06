// 识别结果校验器（批次 1）
//
// 三层校验：
// 1. 字段合理性（dishName 非空、confidence 在 [0,1]、weight>0、区间不倒置）
//    —— 不合理触发 needsRetry，让 controller 重试 1 次（模型偶发错误）
// 2. 营养素自洽性（4*protein + 9*fat + 4*carb ≈ calories，误差 ±10%）
//    —— 不自洽返回 correctedCalories，controller 自动修正（宏量营养素相对可信，calories 易瞎算）
//    —— 参考：Atwater 系数（蛋白质 4 kcal/g、脂肪 9 kcal/g、碳水 4 kcal/g）
// 3. v1.10：宏量营养素反推修正（cal>0 但三宏量全 0 → 按品类默认比例反推）
//    —— 解决"盒装菊花茶有 cal 但碳水=0"问题：含糖饮料碳水必标，AI 漏填时按品类反推
//
// 设计依据：营养素自洽校验是食品科学的基础约束，AI 瞎算 calories 时
// 用宏量营养素反推比"重试赌运气"更稳定（重试可能再次瞎算）。
import '../../ai/vision_provider.dart';
import '../../data/seed/food_category_defaults.dart';

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

    // 5. 营养素自洽性校验（仅当 AI 提供了 estimated_calories 时检查）
    //    旧 prompt（v1.0-v1.3）无此字段 → 跳过，向后兼容
    double? correctedCalories;
    // v1.10：宏量营养素反推修正（cal>0 但宏量缺失 → 按品类默认比例反推/填充）
    // 解决"盒装菊花茶有 cal 但碳水=0"问题：含糖饮料碳水必标，AI 漏填时按品类反推
    double? correctedProteinG;
    double? correctedFatG;
    double? correctedCarbsG;
    final cal = result.estimatedCalories;
    if (cal != null) {
      final protein = result.estimatedProteinG ?? 0;
      final fat = result.estimatedFatG ?? 0;
      final carbs = result.estimatedCarbsG ?? 0;

      // v1.10：宏量营养素缺失/为 0 时，先用品类默认比例填充缺失项
      // 典型场景：
      //   a) 三宏量全 0（含糖茶饮 AI 漏填全部）→ 全量反推
      //   b) 部分宏量非 0（蛋白饮料 protein=3 但 carbs=0 漏填）→ 仅填充缺失项
      // 这样避免部分宏量漏填时自洽校验错误修正 cal（BUG-2 修复）
      if (cal > 0 && (protein == 0 || fat == 0 || carbs == 0)) {
        final def = FoodCategoryDefaults.defaults[result.foodCategory];
        if (def != null && def.$1 > 0) {
          final scale = cal / def.$1;
          // 仅填充为 0 的项（非 0 项保留 AI 值，避免覆盖正确数据）
          final p = protein == 0 ? def.$2 * scale : protein;
          final f = fat == 0 ? def.$3 * scale : fat;
          final c = carbs == 0 ? def.$4 * scale : carbs;
          // 仅当至少有一项被填充（非 0）才回写，避免无意义覆盖
          if (p != protein || f != fat || c != carbs) {
            correctedProteinG = p;
            correctedFatG = f;
            correctedCarbsG = c;
            reasons.add('宏量营养素缺失但 calories=$cal，按品类 '
                '${result.foodCategory} 默认比例填充缺失项: '
                'p=${p.toStringAsFixed(1)}, '
                'f=${f.toStringAsFixed(1)}, '
                'c=${c.toStringAsFixed(1)}');
          }
        }
      }

      // 自洽校验：仅在未触发填充时执行
      // 触发填充意味着 AI 宏量数据不完整（部分漏填），品类填充值仅是"猜测"，
      // 用猜测值 + AI 部分值重算 expected 来覆盖 cal 不可靠（BUG-2 修复核心）。
      // 且填充前提是 cal>0，AI 已给出整菜 cal 估算，应信任 AI 的 cal。
      // 注意：cal<=0 但有宏量的修正分支不受影响（填充要求 cal>0，不会进入此场景）。
      final didFill = correctedProteinG != null ||
          correctedFatG != null ||
          correctedCarbsG != null;
      if (!didFill) {
        final expected = 4 * protein + 9 * fat + 4 * carbs;
        // calories 为 0 但有宏量营养素 → 瞎算，修正
        // calories > 0 但偏差超 ±10% → 修正（仅当 expected>0 才修正，
        //   expected=0 时可能是酒精饮料/纤维等非 Atwater 来源，强制清零会丢热量）
        if (cal <= 0 && expected > 0) {
          reasons.add('calories=0 但宏量营养素之和=$expected，修正为 $expected');
          correctedCalories = expected;
        } else if (cal > 0 && expected > 0) {
          // 方案 D（M25）：酒精饮料豁免 Atwater 校验
          // 啤酒/葡萄酒/烈酒的 calories 主要来自酒精（7 kcal/g），不在 Atwater 系数（4p+9f+4c）内。
          // 例：1 瓶 330ml 啤酒 cal=129, p=1.5, f=0, c=9.3, expected=43.8
          // 修复前：偏差 66% > 10% → 修正为 43.8（丢失 85 kcal 酒精热量）
          // 修复后：beer/wine/alcohol 品类豁免，保留 AI cal
          final isAlcohol = result.foodCategory == 'beer' ||
              result.foodCategory == 'wine' ||
              result.foodCategory == 'alcohol';
          if (isAlcohol) {
            // 酒精饮料：保留 AI cal，不修正（酒精热量不在 Atwater 系数内）
            // 不添加 reason，避免 Sentry 噪音
          } else {
            final diff = (expected - cal).abs();
            final ratio = diff / cal;
            if (ratio > _calorieTolerance) {
              reasons.add('营养素不自洽: calories=$cal, 期望=$expected (4p+9f+4c), '
                  '偏差 ${(ratio * 100).toStringAsFixed(1)}%，修正为 $expected');
              correctedCalories = expected;
            }
          }
        }
        // expected == 0 且 cal > 0：可能是酒精饮料（7 kcal/g 不在 Atwater 系数内）、
        // 糖醇、膳食纤维等，无法用宏量校验，保留 AI 的 calories 不修正
      }
    }

    // 建议 7：复合菜组分份量交叉验证
    // sum(components.estimated_g) 应 ≈ estimated_weight_g_mid（±15%）
    // AI 常出现"鸡蛋120g+番茄150g=270g"但整菜 mid=250g 的不自洽
    // 不自洽时按 mid 比例缩放各组分（mid 是 AI 整菜估算，相对可信）
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
              .map((c) => FoodComponent(
                  name: c.name, estimatedG: c.estimatedG * ratio))
              .toList();
          reasons.add('组分份量不自洽: sum=${sumG.toStringAsFixed(0)}g, '
              'mid=${mid.toStringAsFixed(0)}g, 按 mid 缩放 ${ratio.toStringAsFixed(2)}x');
        }
      }
    }

    return RecognitionValidationResult(
      isValid: reasons.isEmpty,
      needsRetry: needsRetry,
      correctedCalories: correctedCalories,
      correctedComponents: correctedComponents,
      correctedProteinG: correctedProteinG,
      correctedFatG: correctedFatG,
      correctedCarbsG: correctedCarbsG,
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

  /// 建议 7：组分份量交叉验证修正后的组分列表（null 表示无需修正或不适用）
  /// controller 用此值覆盖 VisionRecognitionResult.foodComponents
  final List<FoodComponent>? correctedComponents;

  /// v1.10：宏量营养素反推修正（cal>0 但三宏量全 0 时按品类默认比例反推）
  /// controller 用此值覆盖 VisionRecognitionResult.estimatedProteinG/FatG/CarbsG
  final double? correctedProteinG;
  final double? correctedFatG;
  final double? correctedCarbsG;

  /// 校验失败原因（用于 Sentry 上报 + 调试日志）
  final List<String> reasons;

  const RecognitionValidationResult({
    required this.isValid,
    required this.needsRetry,
    required this.correctedCalories,
    required this.correctedComponents,
    this.correctedProteinG,
    this.correctedFatG,
    this.correctedCarbsG,
    required this.reasons,
  });
}
