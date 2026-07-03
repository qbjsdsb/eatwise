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

/// 章节标题：primary 色 + titleSmall 字号 + w600，统一跨页面分组标题样式。
///
/// 用 textTheme.titleSmall（14, medium）→ w600，作为分组章节标题。
/// 曾用 labelLarge（14）但语义偏"标签"，titleSmall 更贴合"标题"语义。
/// 支持 [trailing]：可选尾部 widget（如显示分组小计热量），让需要 trailing 的页面
/// 复用同一组件而非另起炉灶（today_meals 餐次分组标题曾手写"色块+标题+sum"破坏统一）。
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 左右对称 16：与下方 Card 的 EdgeInsets.all(16)/symmetric(horizontal:16) 左缘对齐，
      // 避免"标题相对卡片右移 8px"造成界面整体偏右的观感（6 页面 14 处复用）
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Text(
            text,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            DefaultTextStyle(
              style: Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
              child: trailing!,
            ),
          ],
        ],
      ),
    );
  }
}

/// 宏量营养素语义色（蛋白/脂肪/碳水跨页统一配色）。
///
/// 用 MD3 ColorScheme 三个角色（tertiary/secondary/primary），跟随 seed 变化，
/// 色弱友好（三个不同色相），避免硬编码 MD2 调色板（0xFF4CAF50 等）破坏主题一致性。
/// - 蛋白 = tertiary（强调，蛋白是健身人群最关注的宏量）
/// - 脂肪 = secondary
/// - 碳水 = primary
class MacroColors {
  const MacroColors._();

  static Color protein(ColorScheme cs) => cs.tertiary;
  static Color fat(ColorScheme cs) => cs.secondary;
  static Color carb(ColorScheme cs) => cs.primary;
}
