import 'package:flutter/material.dart';

/// M3 公共组件：统一跨页面的视觉规范（leading 图标容器 + 章节标题）。

/// ListTile 的 leading 图标容器：40×40 圆形 tonal 色块 + 20px 图标。
///
/// 全 App 列表项 leading 统一用此组件，避免有的页面用裸 Icon、有的手写 Container。
/// 默认 primaryContainer 配色（跟随 seed 色相），可传 [containerColor]/[iconColor] 自定义。
/// 不用 secondaryContainer——tonalSpot 下虽跟随 primary，但显式 primary 系更稳定。
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
        color: containerColor ?? cs.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: iconColor ?? cs.onPrimaryContainer),
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
      // 左右对称 16：与下方 Card 的 EdgeInsets.all(16)/symmetric(horizontal:16) 左缘对齐，
      // 避免"标题相对卡片右移 8px"造成界面整体偏右的观感（6 页面 14 处复用）
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
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
