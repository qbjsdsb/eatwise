import 'package:flutter/material.dart';

/// 本餐合计 + 全部记录按钮（从 multi_dish_page.dart 拆出，M24 B4）
///
/// 底部固定栏：显示合计热量 + 三宏量，以及"全部记录"按钮。
/// 按钮防重入由父 State 的 [isRecording] 控制（父 State 持有 _isRecording 标志）。
class TotalSummaryBar extends StatelessWidget {
  final double totalCal;
  final double totalProtein;
  final double totalFat;
  final double totalCarbs;
  final bool isRecording;
  final VoidCallback onRecord;

  const TotalSummaryBar({
    super.key,
    required this.totalCal,
    required this.totalProtein,
    required this.totalFat,
    required this.totalCarbs,
    required this.isRecording,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
            top: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant)),
      ),
      child: Column(
        children: [
          Text('本餐合计：${totalCal.toStringAsFixed(0)} kcal',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                      fontFeatures: const [
                        FontFeature.tabularFigures()
                      ])),
          Text(
              '蛋白质 ${totalProtein.toStringAsFixed(1)} g · 脂肪 ${totalFat.toStringAsFixed(0)} g · 碳水 ${totalCarbs.toStringAsFixed(0)} g',
              style: TextStyle(
                  fontFeatures: const [
                    FontFeature.tabularFigures()
                  ],
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              // 防重入：记录中禁用按钮
              onPressed: isRecording ? null : onRecord,
              child: isRecording
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimary))
                  : const Text('全部记录'),
            ),
          ),
        ],
      ),
    );
  }
}
