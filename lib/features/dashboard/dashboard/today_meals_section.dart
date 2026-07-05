// lib/features/dashboard/today_meals_section.dart
// 今日餐次 section（从 dashboard_page.dart 拆出，M24 B5）
//
// 显示今日餐次列表（按 breakfast/lunch/dinner/snack 顺序分组，含分割线）。
// 数据通过构造注入 DashboardData，事件通过回调上拱，不直接访问父 State，保证 widget 独立可测。
import 'package:flutter/material.dart';

import '../../../core/widgets/m3_widgets.dart';
import '../../../data/repositories/meal_log_repository.dart';
import 'dashboard_data.dart';

/// 今日餐次 section：按餐次分组渲染 meal_log 列表
///
/// 拆分前后行为零变更：原 _mealsSection + _mealIcon + _mealLabel + _formatTime 逻辑字节级迁移。
/// 空态（meals 为空）显示 EmptyState 引导去拍照，[onGoToRecognize] 回调由父 State 注入。
class TodayMealsSection extends StatelessWidget {
  final DashboardData data;
  final VoidCallback onGoToRecognize;

  const TodayMealsSection({
    super.key,
    required this.data,
    required this.onGoToRecognize,
  });

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d.meals.isEmpty) {
      return EmptyState(
        icon: Icons.restaurant_menu,
        title: '今日还没有记录',
        subtitle: '点下方拍照按钮开始记录',
        actionLabel: '去拍照',
        onAction: onGoToRecognize,
      );
    }
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final groups = <String, List<MealLog>>{};
    for (final m in d.meals) {
      groups.putIfAbsent(m.mealType, () => []).add(m);
    }
    final mealOrder = ['breakfast', 'lunch', 'dinner', 'snack'];
    // 先算出最后一个有记录的餐次
    final presentMealTypes =
        mealOrder.where((mt) => groups[mt] != null).toList();
    final lastPresentMt =
        presentMealTypes.isEmpty ? null : presentMealTypes.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle('今日餐次'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Column(
              children: [
                for (final mt in mealOrder)
                  if (groups[mt] != null)
                    for (final m in groups[mt]!) ...[
                      ListTile(
                        leading: LeadingIconContainer(_mealIcon(mt),
                            containerColor: cs.tertiaryContainer,
                            iconColor: cs.onTertiaryContainer),
                        title: Text(d.foodNames[m.foodItemId] ?? '食物'),
                        subtitle: Text(
                            '${_mealLabel(mt)} · ${_formatTime(m.loggedAt)}',
                            style: textTheme.labelSmall),
                        trailing: Text('${m.actualCalories.toStringAsFixed(0)} kcal',
                            style: textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ),
                      // 只在非"最后一条记录"时显示分割线
                      if (!(m == groups[mt]!.last && mt == lastPresentMt))
                        Divider(
                            height: 1,
                            indent: 56,
                            endIndent: 16,
                            color: cs.outlineVariant),
                    ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  IconData _mealIcon(String mt) => {
        'breakfast': Icons.free_breakfast_rounded,
        'lunch': Icons.lunch_dining_rounded,
        'dinner': Icons.dinner_dining_rounded,
        'snack': Icons.cookie_rounded,
      }[mt] ??
      Icons.restaurant_rounded;

  String _mealLabel(String mt) => {
        'breakfast': '早餐',
        'lunch': '午餐',
        'dinner': '晚餐',
        'snack': '加餐',
      }[mt] ??
      '加餐';

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
