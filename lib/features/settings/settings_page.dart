// lib/features/settings/settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/config/app_version_provider.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/util/date_format.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/backup/auto_backup.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _qwenKeyCtrl = TextEditingController();
  final _qwenUrlCtrl = TextEditingController();
  final _glmKeyCtrl = TextEditingController();
  final _glmUrlCtrl = TextEditingController();
  final _sentryDsnCtrl = TextEditingController();
  bool _sentryEnabled = false;
  bool _tdeeAutoCalib = true;
  String? _lastBackupTime;
  bool _loading = true;
  int? _monthlyCount;
  double? _estimatedCost;
  static const _costPerRecognition = 0.001;  // 估算：单次约 0.001 元（500 token × 0.15/百万）
  static const _costWarningThreshold = 5.0;  // 5 元/月提示
  int _imageRetentionDays = 30;  // T48 保留期
  bool _backupOverdue = false;  // T55：14 天未备份提示
  bool _isSaving = false; // 防重入：保存期间禁用 FAB，避免双击重复写库
  bool _dirty = false; // 用户是否改过任意字段（PopScope 未保存确认用）

  /// 标记 dirty。加载期间（_loading=true）跳过，避免初始赋值触发误标记。
  void _markDirty() {
    if (_loading || _dirty) return;
    setState(() => _dirty = true);
  }

  @override
  void initState() {
    super.initState();
    // controller 监听在 _loadSettings 之前注册；_markDirty 用 _loading 守门
    _qwenKeyCtrl.addListener(_markDirty);
    _qwenUrlCtrl.addListener(_markDirty);
    _glmKeyCtrl.addListener(_markDirty);
    _glmUrlCtrl.addListener(_markDirty);
    _sentryDsnCtrl.addListener(_markDirty);
    _loadSettings();
  }

  @override
  void dispose() {
    _qwenKeyCtrl.dispose();
    _qwenUrlCtrl.dispose();
    _glmKeyCtrl.dispose();
    _glmUrlCtrl.dispose();
    _sentryDsnCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final config = await ref.read(appConfigProvider.future);
      _qwenKeyCtrl.text = config.qwenApiKey;
      _qwenUrlCtrl.text = config.qwenBaseUrl;
      _glmKeyCtrl.text = config.glmApiKey;
      _glmUrlCtrl.text = config.glmBaseUrl;
      _sentryDsnCtrl.text = config.sentryDsn;
      _sentryEnabled = config.sentryEnabled;
      _tdeeAutoCalib = config.tdeeAutoCalib;

      final lastBackup = await AutoBackup.lastBackupTime();
      _lastBackupTime = lastBackup != null ? formatYmd(lastBackup) : null;

      // T55：超过 14 天未备份提示（从未备份不提示，仅显示"从未"）
      if (lastBackup != null) {
        final daysSince = DateTime.now().difference(lastBackup).inDays;
        _backupOverdue = daysSince > 14;
      } else {
        _backupOverdue = false;
      }

      final store = ref.read(secureConfigStoreProvider);
      _monthlyCount = await store.getCurrentMonthCount();
      _estimatedCost = _monthlyCount! * _costPerRecognition;
      _imageRetentionDays = await store.getImageRetentionDays();
    } catch (_) {
      // 防御性兜底：沙箱/真机异常均不传播（真机正常路径不进此分支）
      _lastBackupTime = null;
      _monthlyCount = 0;
      _estimatedCost = 0.0;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingState());
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmDiscardChanges(context) && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: const Text('设置')),
          SliverList(
            delegate: SliverChildListDelegate([
              SectionTitle('主题色'),
              GroupCard(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: _themePalette(),
                ),
              ]),
              SectionTitle('AI 模型'),
              GroupCard(dividerIndent: 16, children: [
                TextField(
                  controller: _qwenKeyCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Qwen API Key', border: InputBorder.none),
                  obscureText: true,
                ),
                TextField(
                  controller: _qwenUrlCtrl,
                  decoration: InputDecoration(
                      labelText: 'Qwen Base URL (留空用默认)',
                      hintText: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
                      border: InputBorder.none),
                ),
                TextField(
                  controller: _glmKeyCtrl,
                  decoration: const InputDecoration(
                      labelText: 'GLM API Key', border: InputBorder.none),
                  obscureText: true,
                ),
                TextField(
                  controller: _glmUrlCtrl,
                  decoration: InputDecoration(
                      labelText: 'GLM Base URL (留空用默认)',
                      hintText: 'https://open.bigmodel.cn/api/paas/v4',
                      border: InputBorder.none),
                ),
              ]),
              SectionTitle('监控与校准'),
              GroupCard(dividerIndent: 16, children: [
                SwitchListTile(
                  title: const Text('启用 Sentry 上报'),
                  subtitle: const Text('崩溃和未处理异常自动上报（经脱敏）'),
                  value: _sentryEnabled,
                  onChanged: (v) {
                    setState(() => _sentryEnabled = v);
                    _markDirty();
                  },
                ),
                SwitchListTile(
                  title: const Text('TDEE 自适应校准'),
                  subtitle: const Text('连续 4 周体重偏差 > 0.3 kg/周时自动微调每日目标'),
                  value: _tdeeAutoCalib,
                  onChanged: (v) {
                    setState(() => _tdeeAutoCalib = v);
                    _markDirty();
                  },
                ),
                TextField(
                  controller: _sentryDsnCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Sentry DSN', border: InputBorder.none),
                ),
              ]),
              SectionTitle('图片管理'),
              GroupCard(children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text('原图保留期'),
                  trailing: SizedBox(
                    width: 150,
                    child: DropdownMenu<int>(
                      initialSelection: _imageRetentionDays,
                      expandedInsets: EdgeInsets.zero,
                      onSelected: (v) {
                        setState(() => _imageRetentionDays = v ?? 30);
                        _markDirty();
                      },
                      dropdownMenuEntries: const [
                        DropdownMenuEntry(value: 7, label: '7 天'),
                        DropdownMenuEntry(value: 30, label: '30 天（默认）'),
                        DropdownMenuEntry(value: 0, label: '永久保留'),
                      ],
                    ),
                  ),
                ),
              ]),
              SectionTitle('使用情况'),
              GroupCard(children: [
                ListTile(
                  leading: const LeadingIconContainer(Icons.analytics_outlined),
                  title: const Text('本月识别次数'),
                  trailing: Text('$_monthlyCount 次'),
                ),
                GroupCard.divider(context),
                ListTile(
                  leading: const LeadingIconContainer(Icons.payments_outlined),
                  title: const Text('估算花费'),
                  trailing: Text('${_estimatedCost!.toStringAsFixed(3)} 元'),
                ),
                if (_estimatedCost! >= _costWarningThreshold)
                  WarningBanner(
                      '本月花费已达 ${_estimatedCost!.toStringAsFixed(2)} 元，建议在厂商控制台设置月度费用上限'),
              ]),
              SectionTitle('备份状态'),
              GroupCard(children: [
                ListTile(
                  leading: const LeadingIconContainer(Icons.backup),
                  title: const Text('上次自动备份'),
                  trailing: Text(_lastBackupTime ?? '从未',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
                if (_backupOverdue)
                  const WarningBanner('已超过 14 天未备份，建议立即导出备份'),
              ]),
              SectionTitle('关于'),
              GroupCard(dividerIndent: 16, children: [
                ListTile(
                  leading: const LeadingIconContainer(Icons.info_outline_rounded),
                  title: const Text('关于慢慢吃'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showAbout,
                ),
                ListTile(
                  leading: const LeadingIconContainer(Icons.privacy_tip_outlined),
                  title: const Text('隐私政策'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showPrivacyPolicy,
                ),
              ]),
              const SizedBox(height: 80),
            ]),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _save,
        icon: _isSaving
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimaryContainer),
              )
            : const Icon(Icons.save),
        label: const Text('保存设置'),
      ),
    ),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return; // 防重入
    setState(() => _isSaving = true);
    try {
      final store = ref.read(secureConfigStoreProvider);
      await store.setQwenApiKey(_qwenKeyCtrl.text.trim());
      await store.setQwenBaseUrl(_qwenUrlCtrl.text.trim().isEmpty ? null : _qwenUrlCtrl.text.trim());
      await store.setGlmApiKey(_glmKeyCtrl.text.trim());
      await store.setGlmBaseUrl(_glmUrlCtrl.text.trim().isEmpty ? null : _glmUrlCtrl.text.trim());
      await store.setSentryDsn(_sentryDsnCtrl.text.trim().isEmpty ? null : _sentryDsnCtrl.text.trim());
      await store.setSentryEnabled(_sentryEnabled);
      await store.setTdeeAutoCalib(_tdeeAutoCalib);
      await store.setImageRetentionDays(_imageRetentionDays);

      // 刷新 appConfigProvider：让依赖它的 qwenApiKeyProvider 等重新计算
      // （reload() 只改实例字段，Riverpod 不感知 → 必须 invalidate）
      ref.invalidate(appConfigProvider);
      await ref.read(appConfigProvider.future);  // 触发重新 load

      if (mounted) {
        showAppToast(context, '设置已保存');
        _dirty = false; // 清 dirty 让 PopScope 放行 programmatic pop
        Navigator.of(context).pop();
      }
    } catch (e) {
      // secure_storage IO 失败等异常：提示用户，不静默卡死
      if (mounted) {
        showAppToast(context, '保存失败：$e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showPrivacyPolicy() async {
    final text = await rootBundle.loadString('assets/privacy_policy.md');
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('隐私政策'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: Text(text)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _showAbout() async {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    // M13：版本号从 appVersionProvider 动态读取（替代硬编码 '0.16.0'）
    final version = ref.read(appVersionProvider).maybeWhen(
          data: (v) => v,
          orElse: () => '...',
        );
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('关于慢慢吃'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('慢慢吃 v$version'),
            const SizedBox(height: 8),
            const Text('拍照识别食物热量 + 营养记录 + AI 汇总建议'),
            const SizedBox(height: 8),
            Text('营养目标依据 ACSM/ISSN/NIH/WHO 标准', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 主题色板：点选即时换肤 + 持久化
  Widget _themePalette() {
    final currentSeed = ref.watch(themeSeedProvider);
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: kThemePresets.map((preset) {
        final (argb, name) = preset;
        return _colorDot(Color(argb), name, argb == currentSeed, () async {
          // 同步换肤（即时响应）
          ref.read(themeSeedProvider.notifier).set(argb);
          // 持久化（失败不阻塞当次换肤，但提示用户下次启动会回退）
          try {
            final store = ref.read(secureConfigStoreProvider);
            await store.setThemeSeed(argb);
            if (!mounted) return;
            showAppToast(context, '已切换主题：$name');
          } catch (_) {
            if (!mounted) return;
            showAppToast(context, '主题已临时切换，但保存失败，下次启动将恢复');
          }
        });
      }).toList(),
    );
  }

  Widget _colorDot(
      Color color, String name, bool selected, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    // M3：用 Material + InkWell 提供 ripple 反馈（GestureDetector 无 state layer，
    // 违反 M3"可点击元素必须有 ripple"规范）
    return Tooltip(
      message: name,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: cs.onSurface, width: 3)
                  : null,
            ),
            child: selected
                ? Icon(Icons.check,
                    // 浅色种子时白色 check 对比度不足，按色块亮度动态选黑/白（WCAG AA）
                    color: color.computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white,
                    size: 20)
                : null,
          ),
        ),
      ),
    );
  }
}
