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

/// 空态占位组件：图标 + 标题 + 副标题（可选） + 主操作按钮（可选）。
///
/// 统一 dashboard / today_meals 等页面"无数据"时的视觉与间距，避免每页各写一份
/// `Center(Column(Icon+Text+FilledButton))` 导致间距/字号漂移。
/// 间距遵循 MD3 规范：图标→标题 16，标题→副标题 8，副标题→按钮 16。外层 padding 32。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, style: tt.titleMedium?.copyWith(color: cs.onSurface)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.camera_alt_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 分组卡片：固定 `padding(horizontal:16) + Card + Column` 包装。
///
/// 统一 me / settings 等设置类页面的"分组卡片"样式，避免每页各写一份
/// `Padding(Card(Column(...)))` + 手动 Divider 间距漂移。
///
/// 分隔线策略：
/// - [dividerIndent] 非 null 时，子项之间自动插入分隔线（indent = 该值，endIndent = 16）。
///   适合子项均匀的场景（如纯 ListTile 列表）。
/// - [dividerIndent] 为 null（默认）时不自动插入，调用方按需用 [GroupCard.divider]
///   手动添加。适合"ListTile + 可选尾注"等不均匀场景（避免尾注前误插分隔线）。
class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.children,
    this.dividerIndent,
    this.dividerEndIndent = 16,
  });

  final List<Widget> children;
  final double? dividerIndent;
  final double dividerEndIndent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = dividerIndent == null
        ? children
        : _withDividers(children, cs.outlineVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(child: Column(children: items)),
    );
  }

  List<Widget> _withDividers(List<Widget> items, Color color) {
    if (items.length <= 1) return items;
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i < items.length - 1) {
        result.add(Divider(
          height: 1,
          indent: dividerIndent!,
          endIndent: dividerEndIndent,
          color: color,
        ));
      }
    }
    return result;
  }

  /// 独立分隔线（用于 [dividerIndent] 为 null 时的手动调用）。
  /// 默认 indent 16 对齐 ListTile contentPadding；带 leading 图标的列表传 56。
  static Widget divider(BuildContext context,
      {double indent = 16, double endIndent = 16}) {
    return Divider(
      height: 1,
      indent: indent,
      endIndent: endIndent,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// 餐次选择器：早餐/午餐/晚餐/加餐 四选一 SegmentedButton。
///
/// 统一 recognize / manual_entry 等页面的餐次选择 UI，避免重复定义 4 个 ButtonSegment
/// 导致标签文案/顺序漂移。餐次值固定为 'breakfast'/'lunch'/'dinner'/'snack'，
/// 与数据库 meal_log.meal_type 字段一致。
class MealTypeSelector extends StatelessWidget {
  const MealTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// 当前选中餐次：'breakfast' / 'lunch' / 'dinner' / 'snack'
  final String value;

  /// 选中变化回调，参数为新餐次
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'breakfast', label: Text('早餐')),
        ButtonSegment(value: 'lunch', label: Text('午餐')),
        ButtonSegment(value: 'dinner', label: Text('晚餐')),
        ButtonSegment(value: 'snack', label: Text('加餐')),
      ],
      selected: {value},
      onSelectionChanged: (v) => onChanged(v.first),
    );
  }
}

/// 未保存修改离开确认 dialog。返回 true 表示用户确认放弃修改。
///
/// 用于编辑页 PopScope：当 _dirty=true 且用户按返回时弹出，避免误操作丢失编辑。
/// 4 个编辑页（food_edit/settings/profile/calibration）共用，文案统一。
Future<bool> confirmDiscardChanges(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('放弃修改？'),
          content: const Text('你有未保存的修改，确定要离开吗？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('继续编辑')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('放弃')),
          ],
        ),
      ) ??
      false;
}

/// 通用确认对话框：title + content + 取消/确认 两按钮。
///
/// 用于删除/重新生成/导入等需要二次确认的操作，统一 AlertDialog 样板。
/// - [destructive]=true：确认按钮用 errorContainer 配色（删除等破坏性操作）
/// - [icon]：非 null 时显示在 title 上方（MD3 AlertDialog.icon 位，用 cs.error 色，
///   适合 warning_amber_rounded 等警示图标）
/// - 返回 true=确认，false/null=取消（null 兜底为 false）
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String content,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  IconData? icon,
  bool destructive = false,
}) async {
  final cs = Theme.of(context).colorScheme;
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: icon != null ? Icon(icon, color: cs.error) : null,
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: cs.errorContainer,
                      foregroundColor: cs.onErrorContainer)
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

/// 通用 toast 提示：封装 ScaffoldMessenger + SnackBar 样板。
///
/// 用于成功/失败/提示消息，替代各页散落的
/// `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(...)))`。
/// - [duration]：null 用默认 4s（与 SnackBar 默认一致）
void showAppToast(BuildContext context, String msg, {Duration? duration}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      duration: duration ?? const Duration(seconds: 4),
    ),
  );
}

/// 图表空数据占位：固定高度 120 + Card + show_chart 图标 + 文案。
///
/// 用于 weight_page 趋势图 / insight_page 折线图数据不足时的占位，
/// 与 EmptyState（全屏居中、48px 图标、可选 action）区分——此组件是图表区占位，
/// 高度受限、图标 32px、无 action。两页原各自手写实现，现统一抽象。
class EmptyChartHint extends StatelessWidget {
  const EmptyChartHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 120,
      child: Card(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.show_chart_rounded,
                  size: 32, color: cs.onSurfaceVariant),
              const SizedBox(height: 8),
              Text(text,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 警告横幅：error 色 Icon + 文案，用于 settings 页费用/备份超期等警告。
///
/// 统一 settings_page 内两处手写 Padding+Row 实现。MD3 风格用 error 色
/// （而非 tertiaryContainer），因这些是需用户关注的风险提示。
class WarningBanner extends StatelessWidget {
  const WarningBanner(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: cs.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: cs.error, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
