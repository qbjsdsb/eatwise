// lib/features/dashboard/recommendation_section.dart
// 智能推荐 section（从 dashboard_page.dart 拆出，M24 B5）
//
// 渐进增强结构：AI loading 时先显示 v4 + 加载提示，AI 返回后替换为 AI 推荐；
// AI 失败/空时保持 v4 + 错误提示。AI 推荐含满意度反馈（点开才显示）。
// 数据通过构造注入（含两个 Future），事件通过回调上拱，不直接访问父 State，保证 widget 独立可测。
import 'package:flutter/material.dart';

import '../../../core/widgets/m3_widgets.dart';
import '../../../nutrition/ai_recommendation_prompt.dart';
import '../../../nutrition/ai_recommendation_service.dart';
import '../../../nutrition/recommendation_service.dart';
import '../../manual_entry/manual_entry_page.dart';
import 'ai_rec_item.dart';
import 'dashboard_data.dart';
import 'regenerate_button.dart';

/// 智能推荐 section：AI 推荐（渐进增强）+ v4 本地兜底 + 满意度反馈
///
/// 拆分前后行为零变更：原 _recommendationSection + _aiLoadingHint + _aiErrorHint
/// + _aiRecommendations + _v4Recommendations + _regenerateButton 调用逻辑字节级迁移。
/// [aiRecFuture] / [recFuture] 由父 State 持有，触发重建时父 State 用 setState 替换 Future。
class RecommendationSection extends StatelessWidget {
  final DashboardData data;
  final Future<AiRecommendationResult>? aiRecFuture;
  final Future<List<RecommendedFood>>? recFuture;
  final bool aiRegenerating;
  final String mealType;
  final VoidCallback onRegenerate;
  final Future<bool> Function(
      AiRecommendation rec, int rating, String mealType) onRateRecommendation;
  final void Function(Widget page) onPushAndRefresh;

  const RecommendationSection({
    super.key,
    required this.data,
    required this.aiRecFuture,
    required this.recFuture,
    required this.aiRegenerating,
    required this.mealType,
    required this.onRegenerate,
    required this.onRateRecommendation,
    required this.onPushAndRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final d = data;
    final remain = d.target - d.cal;
    final proteinRemain = d.proteinGoal - d.protein;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle('智能推荐'),
        // 隐私提示：AI 推荐会将档案与饮食数据发送到智谱 AI（D14 P1）
        // 轻量持久提示，不弹窗打扰；详细信息在设置页"隐私政策"
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'AI 推荐会将档案与饮食数据发送到智谱 AI，详见隐私政策',
            style: textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            proteinRemain > 5
                                ? '今日还差 ${proteinRemain.toStringAsFixed(0)} g 蛋白质'
                                : remain > 0
                                    ? '今日还可摄入 ${remain.toStringAsFixed(0)} kcal'
                                    : '今日热量已达标，推荐低卡食物',
                            style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ]),
                          ),
                        ),
                      ),
                      // 重新生成按钮：AI 推荐成功或曾失败时都显示（失败时文案改"重试"）
                      FutureBuilder<AiRecommendationResult>(
                        future: aiRecFuture,
                        builder: (context, aiSnap) {
                          // 加载中或未配置（无 error 且无数据）时不显示
                          if (aiSnap.connectionState !=
                              ConnectionState.done) {
                            return const SizedBox.shrink();
                          }
                          // key 未配置：无数据无 error，不显示按钮
                          if (!aiSnap.hasData) {
                            return const SizedBox.shrink();
                          }
                          final aiData = aiSnap.data!;
                          // key 未配置的静默回退（无 error）：不显示
                          if (aiData.recommendations.isEmpty &&
                              aiData.error == null) {
                            return const SizedBox.shrink();
                          }
                          // 成功或失败（带 error）都显示按钮，失败时文案改"重试"
                          return RegenerateButton(
                            colorScheme: cs,
                            aiRegenerating: aiRegenerating,
                            isRetry: aiData.hasError,
                            onPressed: onRegenerate,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // AI 推荐区（渐进增强：AI loading 时先显示 v4 + 加载提示，
                // AI 返回后替换为 AI 推荐；AI 失败/空时保持 v4 + 错误提示）
                FutureBuilder<AiRecommendationResult>(
                  future: aiRecFuture,
                  builder: (context, aiSnap) {
                    // AI loading 中：先显示 v4 本地推荐（秒出）+ 顶部加载提示
                    // 这是真正的渐进增强——用户不空等，v4 立即可点
                    if (aiSnap.connectionState != ConnectionState.done) {
                      return Column(
                        children: [
                          _aiLoadingHint(cs, textTheme),
                          _v4Recommendations(textTheme, cs),
                        ],
                      );
                    }
                    // AI 失败/空：回退 v4 本地推荐
                    if (aiSnap.hasError ||
                        !aiSnap.hasData ||
                        aiSnap.data!.recommendations.isEmpty) {
                      final err = aiSnap.hasData
                          ? aiSnap.data!.error
                          : (aiSnap.hasError ? 'AI 推荐失败' : null);
                      return Column(
                        children: [
                          if (err != null) _aiErrorHint(cs, err, textTheme),
                          _v4Recommendations(textTheme, cs),
                        ],
                      );
                    }
                    // AI 成功：显示 AI 推荐 + 满意度反馈
                    final aiRecs = aiSnap.data!.recommendations;
                    return _aiRecommendations(aiRecs, cs, mealType);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// AI loading 提示（渐进增强：v4 已秒出，AI 在后台生成）
  ///
  /// 用线性进度条 + 文案提示用户 AI 正在生成更精准推荐，
  /// 不用骨架屏（避免与下方 v4 推荐重复占位），保持视觉简洁。
  Widget _aiLoadingHint(ColorScheme cs, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: cs.primary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'AI 正在生成个性化推荐…',
              style: textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// AI 失败提示（小尺寸 errorContainer 行，告诉用户已切本地推荐）
  Widget _aiErrorHint(ColorScheme cs, String message, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(Icons.info_outline_rounded, size: 14, color: cs.error),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// AI 推荐列表（含满意度反馈，点开才显示）
  Widget _aiRecommendations(
      List<AiRecommendation> recs, ColorScheme cs, String mealType) {
    return Column(
      children: [
        for (final rec in recs) ...[
          Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
          // ValueKey(rec.name)：换一批后 rec.name 变化 → 强制新建 State，
          // 避免旧 _ratedRating 状态泄漏到新推荐
          AiRecItem(
            key: ValueKey(rec.name),
            rec: rec,
            mealType: mealType,
            onTap: () => onPushAndRefresh(ManualEntryPage(initialName: rec.name)),
            onRate: (rating) => onRateRecommendation(rec, rating, mealType),
          ),
        ],
      ],
    );
  }

  /// v4 本地推荐列表（AI 失败/loading 时兜底）
  Widget _v4Recommendations(TextTheme tt, ColorScheme cs) {
    return FutureBuilder<List<RecommendedFood>>(
      future: recFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('v4 推荐加载失败：${snap.error}');
          return const SizedBox.shrink();
        }
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final recs = snap.data!;
        return Column(
          children: [
            for (final rec in recs) ...[
              Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
              ListTile(
                leading: const LeadingIconContainer(Icons.restaurant_rounded),
                title: Text(rec.food.name),
                subtitle: Text(
                    '${rec.food.caloriesPer100g.toStringAsFixed(0)} kcal/100 g · 蛋白 ${rec.food.proteinPer100g.toStringAsFixed(1)} g',
                    style: tt.labelSmall?.copyWith(
                        fontFeatures: const [
                          FontFeature.tabularFigures()
                        ])),
                trailing: const ExcludeSemantics(
                    child: Icon(Icons.chevron_right)),
                onTap: () => onPushAndRefresh(
                    ManualEntryPage(initialName: rec.food.name)),
              ),
            ],
          ],
        );
      },
    );
  }
}
