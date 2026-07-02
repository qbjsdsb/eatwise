import 'package:flutter/material.dart';

/// M3 公共组件：统一跨页面的视觉规范（leading 图标容器 + 章节标题）。

/// ListTile 的 leading 图标容器：40×40 圆形 tonal 色块 + 20px 图标。
///
/// 全 App 列表项 leading 统一用此组件，避免有的页面用裸 Icon、有的手写 Container。
/// 默认 secondaryContainer 配色，可传 [containerColor]/[iconColor] 自定义
/// （如餐次用 tertiaryContainer、推荐用 secondaryContainer）。
class LeadingIconContainer extends StatelessWidget {
  const LeadingIconContainer(
    this.icon, {
    super.key,
    this.containerColor,
    this.iconColor,
  });

  final IconData icon;
  final Color? containerColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: containerColor ?? cs.secondaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: iconColor ?? cs.onSecondaryContainer),
    );
  }
}

/// 章节标题：primary 色 + labelLarge 字号 + w600，统一跨页面分组标题样式。
///
/// 用 textTheme.labelLarge（14）替代各页面硬编码的 fontSize: 13，
/// 便于响应 textScaleFactor 和统一调参。
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
