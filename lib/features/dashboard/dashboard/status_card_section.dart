// lib/features/dashboard/status_card_section.dart
// 状态卡 section（从 dashboard_page.dart 拆出，M24 B5）
//
// 显示今日热量剩余 + 进度条 + 三宏（蛋白/脂肪/碳水）进度条。
// 数据通过构造注入 DashboardData，不直接访问父 State，保证 widget 独立可测。
import 'package:flutter/material.dart';

import '../../../core/widgets/m3_widgets.dart';
import 'dashboard_data.dart';

/// 状态卡 section：今日还可摄入热量 + 进度条 + 三宏进度
///
/// 拆分前后行为零变更：原 _statusCard + _miniMacro 逻辑字节级迁移到此 widget。
class StatusCardSection extends StatelessWidget {
  final DashboardData data;

  const StatusCardSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final d = data;
    final remain = d.target - d.cal;
    final overflow = remain < 0;
    final pct = d.target > 0 ? (d.cal / d.target).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: HeroCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: Icon(Icons.local_fire_department_rounded,
                      color: cs.onPrimaryContainer, size: 20),
                ),
                const SizedBox(width: 8),
                Text('今日还可摄入',
                    style: textTheme.labelLarge?.copyWith(
                        color: cs.onPrimaryContainer)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              overflow ? (-remain).toStringAsFixed(0) : remain.toStringAsFixed(0),
              style: textTheme.displaySmall?.copyWith(
                color: overflow ? cs.error : cs.onPrimaryContainer,
                fontWeight: FontWeight.w400,
                height: 1.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text('kcal · 已摄入 ${d.cal.toStringAsFixed(0)} / ${d.target}',
                style: textTheme.bodySmall?.copyWith(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: cs.onPrimaryContainer.withValues(alpha: 0.12),
                color: overflow ? cs.error : cs.onPrimaryContainer,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 16),
            // 三宏用 MD3 三角色（tertiary/secondary/primary），跟随 seed 变化且色弱友好。
            // primaryContainer 深底上用 onTertiaryContainer/onSecondaryContainer/onPrimaryContainer
            // 保证对比度（容器色配对色），与 today_meals 跨页统一。
            _miniMacro(context, '蛋白', d.protein, d.proteinGoal,
                MacroColors.protein(cs), cs.onTertiaryContainer),
            _miniMacro(context, '脂肪', d.fat, d.fatGoal,
                MacroColors.fat(cs), cs.onSecondaryContainer),
            _miniMacro(context, '碳水', d.carbs, d.carbGoal,
                MacroColors.carb(cs), cs.onPrimaryContainer),
          ],
        ),
      ),
    );
  }

  Widget _miniMacro(BuildContext context, String label, double value, double goal,
      Color barColor, Color labelColor) {
    final textTheme = Theme.of(context).textTheme;
    final pct = goal > 0 ? (value / goal).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
              width: 40,
              child: Text(label,
                  style: textTheme.bodySmall?.copyWith(color: labelColor))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: barColor.withValues(alpha: 0.12),
                color: barColor,
                minHeight: 6,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
                '${value.toStringAsFixed(0)}/${goal.toStringAsFixed(0)} g',
                textAlign: TextAlign.right,
                style: textTheme.labelSmall?.copyWith(
                    color: labelColor,
                    fontFeatures: const [FontFeature.tabularFigures()]))),
        ],
      ),
    );
  }
}
