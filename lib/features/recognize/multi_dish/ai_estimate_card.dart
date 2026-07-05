import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:flutter/material.dart';

/// M18 Task2: AI 估算卡片 UI（从 multi_dish_page.dart 拆出，M24 B4）
///
/// 显示置信度 + 来源徽章 + AI vs 库值对比 + reasoning 折叠面板，
/// 与 calibration_page 风格一致，让用户验证 AI 精度。
///
/// 显示规则：
/// - 行 1（置信度 + 来源徽章）：所有命中菜品显示
///   - 置信度 < 60% 显示"待确认"红色警告
///   - 来源徽章：AI 优先（查库命中 + AI 有效）/ 库匹配（查库命中 + AI 无效）/ AI 估算（哨兵）
/// - 行 2（AI vs 库值对比）：仅查库命中时显示
/// - 行 3（reasoning 折叠面板）：reasoning 非空时显示
class AiEstimateCard extends StatelessWidget {
  final VisionRecognitionResult dish;
  final NutritionResult? single;
  final CompositeNutritionResult? composite;
  final NutritionResult? aiFallback;

  const AiEstimateCard({
    super.key,
    required this.dish,
    required this.single,
    required this.composite,
    required this.aiFallback,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bodySmall = Theme.of(context).textTheme.bodySmall!;

    // 判断来源
    final bool isAiSentinel =
        single != null && single!.foodItemId == 0 && composite == null;
    final bool isLookupHit =
        (single != null && single!.foodItemId > 0) || composite != null;
    final bool isAiPriority =
        isLookupHit && aiFallback != null && _isAiValid(dish, aiFallback!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 行 1: AI 估算 + 置信度 + 来源徽章
        Row(
          children: [
            Icon(Icons.insights_outlined, size: 14, color: cs.primary),
            const SizedBox(width: 4),
            Text('AI 估算', style: bodySmall),
            const SizedBox(width: 8),
            // 置信度：< 60% 显示"待确认"红色警告，否则显示百分比
            if (dish.confidence < 0.6)
              Text('待确认',
                  style: bodySmall.copyWith(
                    color: cs.error,
                    fontWeight: FontWeight.w600,
                  ))
            else
              Text('置信度 ${(dish.confidence * 100).toStringAsFixed(0)}%',
                  style: bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  )),
            const SizedBox(width: 8),
            _buildSourceBadge(context, isAiSentinel, isAiPriority),
          ],
        ),
        // 行 2: AI vs 库值对比（仅查库命中 + 有 AI 估算时显示）
        if (isLookupHit && aiFallback != null) ...[
          const SizedBox(height: 4),
          _buildAiVsDbComparison(context, dish, aiFallback!, single, composite),
        ],
        // 行 3: reasoning 折叠面板（reasoning 非空时显示）
        if (dish.reasoning != null && dish.reasoning!.isNotEmpty) ...[
          const SizedBox(height: 4),
          _buildReasoningExpansionTile(context, dish.reasoning!),
        ],
      ],
    );
  }

  /// M18: 来源徽章
  /// - AI 估算（哨兵）：橙色 tertiaryContainer
  /// - AI 优先（查库命中 + AI 有效）：紫色 primaryContainer
  /// - 库匹配（查库命中 + AI 无效）：蓝色 secondaryContainer
  Widget _buildSourceBadge(
      BuildContext context, bool isAiSentinel, bool isAiPriority) {
    final cs = Theme.of(context).colorScheme;
    final (label, bgColor, fgColor) = isAiSentinel
        ? ('AI 估算', cs.tertiaryContainer, cs.onTertiaryContainer)
        : isAiPriority
            ? ('AI 优先', cs.primaryContainer, cs.onPrimaryContainer)
            : ('库匹配', cs.secondaryContainer, cs.onSecondaryContainer);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: fgColor, fontWeight: FontWeight.w500)),
    );
  }

  /// M18: AI vs 库值对比行
  /// 显示 AI 反算 per100g vs 库 per100g + 偏差百分比
  /// 偏差 > 50% 时红色高亮（AI 估算与库值差异显著，提示用户关注）
  Widget _buildAiVsDbComparison(
    BuildContext context,
    VisionRecognitionResult dish,
    NutritionResult aiFallback,
    NutritionResult? single,
    CompositeNutritionResult? composite,
  ) {
    final cs = Theme.of(context).colorScheme;
    final bodySmall = Theme.of(context).textTheme.bodySmall!;
    final mid = dish.estimatedWeightGMid;
    if (mid <= 0) return const SizedBox.shrink();
    final aiPer100 = aiFallback.calories * 100 / mid;
    final dbPer100 = single != null
        ? single.calories * 100 / mid
        : (composite != null ? composite.calories * 100 / mid : 0.0);
    final diff = dbPer100 > 0
        ? ((aiPer100 - dbPer100) / dbPer100 * 100).abs()
        : 0.0;
    final diffStr = diff > 50
        ? '⚠ 偏差 ${diff.toStringAsFixed(0)}%'
        : '偏差 ${diff.toStringAsFixed(0)}%';
    return Text(
      'AI: ${aiPer100.toStringAsFixed(0)} kcal/100g · 库: ${dbPer100.toStringAsFixed(0)} ($diffStr)',
      style: bodySmall.copyWith(
        fontSize: 11,
        color: diff > 50 ? cs.error : cs.onSurfaceVariant,
      ),
    );
  }

  /// M18: reasoning 折叠面板（与 calibration_page 风格一致）
  /// 默认折叠避免占空间，用户主动展开查看 AI 推理过程
  Widget _buildReasoningExpansionTile(BuildContext context, String reasoning) {
    final cs = Theme.of(context).colorScheme;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      dense: true,
      title: Row(
        children: [
          Icon(Icons.psychology_outlined, size: 16, color: cs.primary),
          const SizedBox(width: 4),
          Text('AI 推理过程',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            reasoning,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontSize: 11),
          ),
        ),
      ],
    );
  }

  /// M18: AI 估算有效性判断（与 CalibratedNutritionCalculator.computeCompositeLookupHit 一致）
  /// AI per100g ∈ [0, 900] 且 mid > 0 时有效
  bool _isAiValid(VisionRecognitionResult dish, NutritionResult aiFallback) {
    final mid = dish.estimatedWeightGMid;
    if (mid <= 0) return false;
    final aiPer100 = aiFallback.calories * 100 / mid;
    return aiPer100 >= 0 && aiPer100 <= 900;
  }
}
