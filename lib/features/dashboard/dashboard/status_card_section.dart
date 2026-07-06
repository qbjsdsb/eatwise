// lib/features/dashboard/dashboard/status_card_section.dart
// 状态卡 section（从 dashboard_page.dart 拆出，M24 B5）
//
// 显示今日热量剩余/超量 + 进度条（含溢出段）+ 三宏（蛋白/脂肪/碳水）进度条。
// 数据通过构造注入 DashboardData，不直接访问父 State，保证 widget 独立可测。
//
// 超量显示（全面改）：当 cal > target 时——
// - 标题文案切换"今日还可摄入"→"今日已超" + 颜色变 error
// - 大数字加 "+" 前缀（如 "+200"）+ error 色
// - 副标题切换为"已超 X kcal (Y%) · 已摄入 A / B"
// - 进度条分两段：主段 error 色满格 + 溢出段 onErrorContainer 色按比例延伸（封顶 30% 宽）
// - 三宏同步：进度条满格保留宏色 + 文案追加 "(超 Zg)" 用 error 色
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/widgets/m3_widgets.dart';
import 'dashboard_data.dart';

/// 状态卡 section：今日热量剩余/超量 + 进度条 + 三宏进度
///
/// 超量时全维度切换文案 + 颜色 + 溢出段，避免用户误读"还可摄入"。
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
    final overflowKcal = overflow ? -remain : 0.0;
    final overflowPct = (overflow && d.target > 0)
        ? (overflowKcal / d.target * 100)
        : 0.0;
    final pct = d.target > 0 ? (d.cal / d.target).clamp(0.0, 1.0) : 0.0;
    // 溢出段 flex：按溢出比例，封顶 30（避免溢出段占太多）
    final overflowFlex = overflow
        ? min((overflowPct).round().clamp(1, 30), 30)
        : 0;
    final mainColor = overflow ? cs.error : cs.onPrimaryContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: HeroCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    overflow
                        ? Icons.warning_amber_rounded
                        : Icons.local_fire_department_rounded,
                    color: mainColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  overflow ? '今日已超' : '今日还可摄入',
                  style: textTheme.labelLarge?.copyWith(color: mainColor),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              overflow
                  ? '+${overflowKcal.toStringAsFixed(0)}'
                  : remain.toStringAsFixed(0),
              style: textTheme.displaySmall?.copyWith(
                color: mainColor,
                fontWeight: FontWeight.w400,
                height: 1.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              overflow
                  ? '已超 ${overflowKcal.toStringAsFixed(0)} kcal (${overflowPct.toStringAsFixed(0)}%) · 已摄入 ${d.cal.toStringAsFixed(0)} / ${d.target}'
                  : 'kcal · 已摄入 ${d.cal.toStringAsFixed(0)} / ${d.target}',
              style: textTheme.bodySmall?.copyWith(
                color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 12),
            // 进度条：未超量用单段 LinearProgressIndicator；
            // 超量用 Row 两段（主段 error 满格 + 溢出段 onErrorContainer 按 flex 延伸）
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: overflow
                  ? Row(
                      children: [
                        Expanded(
                          flex: 100,
                          child: Container(
                            color: cs.error,
                            height: 8,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          flex: overflowFlex,
                          child: Container(
                            color: cs.onErrorContainer,
                            height: 8,
                          ),
                        ),
                      ],
                    )
                  : LinearProgressIndicator(
                      value: pct,
                      backgroundColor:
                          cs.onPrimaryContainer.withValues(alpha: 0.12),
                      color: cs.onPrimaryContainer,
                      minHeight: 8,
                    ),
            ),
            const SizedBox(height: 16),
            // 三宏用 MD3 三角色（tertiary/secondary/primary），跟随 seed 变化且色弱友好。
            // primaryContainer 深底上用 onTertiaryContainer/onSecondaryContainer/onPrimaryContainer
            // 保证对比度（容器色配对色），与 today_meals 跨页统一。
            // 超量时：进度条满格保留宏色（三个宏都变红会混淆），文案追加"(超 Zg)"用 error 色
            _miniMacro(context, '蛋白', d.protein, d.proteinGoal,
                MacroColors.protein(cs), cs.onTertiaryContainer, cs.error),
            _miniMacro(context, '脂肪', d.fat, d.fatGoal, MacroColors.fat(cs),
                cs.onSecondaryContainer, cs.error),
            _miniMacro(context, '碳水', d.carbs, d.carbGoal,
                MacroColors.carb(cs), cs.onPrimaryContainer, cs.error),
          ],
        ),
      ),
    );
  }

  Widget _miniMacro(BuildContext context, String label, double value,
      double goal, Color barColor, Color labelColor, Color errorColor) {
    final textTheme = Theme.of(context).textTheme;
    final pct = goal > 0 ? (value / goal).clamp(0.0, 1.0) : 0.0;
    final macroOverflow = value > goal && goal > 0;
    final overG = macroOverflow ? (value - goal) : 0.0;
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
            width: macroOverflow ? 110 : 80,
            child: Text(
              macroOverflow
                  ? '${value.toStringAsFixed(0)}/${goal.toStringAsFixed(0)} g 超${overG.toStringAsFixed(0)}'
                  : '${value.toStringAsFixed(0)}/${goal.toStringAsFixed(0)} g',
              textAlign: TextAlign.right,
              style: textTheme.labelSmall?.copyWith(
                color: macroOverflow ? errorColor : labelColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
