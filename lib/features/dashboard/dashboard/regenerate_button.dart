// lib/features/dashboard/regenerate_button.dart
// 重试/换一批按钮（从 dashboard_page.dart 拆出，M24 B5）
//
// M23 P1 修复：移除 minimumSize + tapTargetSize，依赖 TextButton.icon 默认触控目标
// （Material 3 默认 ≥48dp，A2 修复后由 dashboard_page_test 守护 ≥48dp 不回归）。
// 数据通过构造注入，事件通过回调上拱，不直接访问父 State，保证 widget 独立可测。
import 'package:flutter/material.dart';

/// 重新生成按钮（AI 推荐区"换一批"/失败时"重试"按钮）
///
/// [isRetry]=true 时文案改"重试"，否则"换一批"。
/// [aiRegenerating]=true 时按钮 disabled + 显示菊花 + 文案"生成中…"。
class RegenerateButton extends StatelessWidget {
  final ColorScheme colorScheme;
  final bool aiRegenerating;
  final bool isRetry;
  final VoidCallback onPressed;

  const RegenerateButton({
    super.key,
    required this.colorScheme,
    required this.aiRegenerating,
    required this.isRetry,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: aiRegenerating ? null : onPressed,
      icon: aiRegenerating
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            )
          : const Icon(Icons.refresh_rounded, size: 18),
      label: Text(aiRegenerating
          ? '生成中…'
          : isRetry
              ? '重试'
              : '换一批'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
    );
  }
}
