// lib/features/dashboard/ai_rec_item.dart
// AI 推荐单项组件（从 dashboard_page.dart 拆出，M24 B5）
//
// StatefulWidget 维护"已反馈"状态，反馈按钮点开才显示（PopupMenuButton 三点菜单）。
// 数据通过构造注入，事件通过回调上拱，不直接访问父 State，保证 widget 独立可测。
import 'package:flutter/material.dart';

import '../../../core/widgets/m3_widgets.dart';
import '../../../nutrition/ai_recommendation_prompt.dart';

/// AI 推荐单项组件（StatefulWidget 维护"已反馈"状态）
///
/// 反馈按钮设计为点开才显示（PopupMenuButton 三点菜单），
/// 避免每条推荐占用过多垂直空间。反馈后图标变为已反馈状态。
class AiRecItem extends StatefulWidget {
  final AiRecommendation rec;
  final String mealType;
  final VoidCallback onTap;
  // rating: 1=不喜欢 / 2=一般 / 3=喜欢。返回 true=成功，false=失败
  final Future<bool> Function(int rating) onRate;

  const AiRecItem({
    super.key,
    required this.rec,
    required this.mealType,
    required this.onTap,
    required this.onRate,
  });

  @override
  State<AiRecItem> createState() => _AiRecItemState();
}

class _AiRecItemState extends State<AiRecItem> {
  // 已反馈的 rating（null=未反馈）。反馈后立即更新 UI，避免重复点。
  int? _ratedRating;
  bool _rating = false; // 防重入

  // 反馈选项配置
  static const _feedbackOptions = <_FeedbackOption>[
    _FeedbackOption(rating: 3, label: '喜欢', icon: Icons.thumb_up_outlined),
    _FeedbackOption(rating: 2, label: '一般', icon: Icons.thumbs_up_down_outlined),
    _FeedbackOption(rating: 1, label: '不喜欢', icon: Icons.thumb_down_outlined),
  ];

  Future<void> _handleRate(int rating) async {
    if (_rating || _ratedRating != null) return; // 防重入 + 已反馈不重复
    setState(() {
      _rating = true;
      _ratedRating = rating; // 乐观更新
    });
    try {
      final ok = await widget.onRate(rating);
      if (!mounted) return;
      if (!ok) {
        // 失败：重置 UI 状态，允许重试
        setState(() => _ratedRating = null);
      }
    } catch (_) {
      // onRate 内部已 try/catch，理论上不会冒泡；防御性兜底
      if (mounted) setState(() => _ratedRating = null);
    } finally {
      if (mounted) setState(() => _rating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rec = widget.rec;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const ExcludeSemantics(
              child: LeadingIconContainer(Icons.auto_awesome_rounded)),
          Expanded(
            child: InkWell(
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(rec.name,
                              style: tt.titleSmall,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        const ExcludeSemantics(
                            child: Icon(Icons.chevron_right, size: 18)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(rec.reason,
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${rec.estimatedCalories.toStringAsFixed(0)} kcal · 蛋白 ${rec.estimatedProtein.toStringAsFixed(0)} g',
                          style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]),
                        ),
                        // 已反馈时显示标签
                        if (_ratedRating != null) ...[
                          const SizedBox(width: 8),
                          _ratedChip(cs),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 三点菜单：点开才显示反馈选项
          PopupMenuButton<int>(
            icon: _rating
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : Icon(
                    _ratedRating != null
                        ? Icons.check_circle_outline
                        : Icons.more_vert,
                    size: 20,
                    color: _ratedRating != null
                        ? cs.primary
                        : cs.onSurfaceVariant,
                  ),
            tooltip: _rating
                ? '提交中'
                : _ratedRating != null
                    ? '已反馈'
                    : '反馈满意度',
            enabled: !_rating && _ratedRating == null,
            onSelected: (rating) => _handleRate(rating),
            itemBuilder: (context) => [
              for (final opt in _feedbackOptions)
                PopupMenuItem<int>(
                  value: opt.rating,
                  child: Row(
                    children: [
                      Icon(opt.icon, size: 18, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(opt.label),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 已反馈标签（小尺寸 chip）
  Widget _ratedChip(ColorScheme cs) {
    final label = _ratedRating == 3
        ? '已喜欢'
        : _ratedRating == 2
            ? '已评一般'
            : '已不喜欢';
    final color = _ratedRating == 3
        ? cs.primary
        : _ratedRating == 1
            ? cs.error
            : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}

/// 反馈选项配置（内部用）
class _FeedbackOption {
  final int rating;
  final String label;
  final IconData icon;

  const _FeedbackOption({
    required this.rating,
    required this.label,
    required this.icon,
  });
}
