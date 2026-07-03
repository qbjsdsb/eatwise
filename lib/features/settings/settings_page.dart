// lib/features/settings/settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/theme_controller.dart';
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
  static const _costPerRecognition =
      0.001; // 估算：单次约 0.001 元（500 token × 0.15/百万）
  static const _costWarningThreshold = 5.0; // 5 元/月提示
  int _imageRetentionDays = 30; // T48 保留期
  bool _backupOverdue = false; // T55：14 天未备份提示
  bool _busy = false;

  @override
  void initState() {
    super.initState();
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
      _lastBackupTime = lastBackup != null
          ? '${lastBackup.year}-${lastBackup.month.toString().padLeft(2, '0')}-${lastBackup.day.toString().padLeft(2, '0')}'
          : null;

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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- 主题色 ---
          _sectionHeader('主题色'),
          _themePalette(),
          const SizedBox(height: 16),

          // --- AI 模型配置 ---
          _sectionHeader('AI 模型配置'),
          TextField(
            controller: _qwenKeyCtrl,
            decoration: const InputDecoration(
              labelText: 'Qwen API Key',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _qwenUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'Qwen Base URL (留空用默认)',
              hintText: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _glmKeyCtrl,
            decoration: const InputDecoration(
              labelText: 'GLM API Key',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _glmUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'GLM Base URL (留空用默认)',
              hintText: 'https://open.bigmodel.cn/api/paas/v4',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // --- 错误监控 ---
          _sectionHeader('错误监控'),
          SwitchListTile(
            title: const Text('启用 Sentry 上报'),
            subtitle: const Text('崩溃和未处理异常自动上报（经脱敏）'),
            value: _sentryEnabled,
            onChanged: (v) => setState(() => _sentryEnabled = v),
          ),
          TextField(
            controller: _sentryDsnCtrl,
            decoration: const InputDecoration(
              labelText: 'Sentry DSN',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // --- 营养校准 ---
          _sectionHeader('营养校准'),
          SwitchListTile(
            title: const Text('TDEE 自适应校准'),
            subtitle: const Text('连续 4 周体重偏差 > 0.3 kg/周时自动微调每日目标'),
            value: _tdeeAutoCalib,
            onChanged: (v) => setState(() => _tdeeAutoCalib = v),
          ),
          const SizedBox(height: 16),

          // --- 本月使用 ---
          _sectionHeader('本月使用'),
          ListTile(
            leading: const Icon(Icons.analytics_outlined),
            title: const Text('本月识别次数'),
            trailing: Text('$_monthlyCount 次'),
          ),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('估算花费'),
            trailing: Text('${_estimatedCost!.toStringAsFixed(3)} 元'),
          ),
          if (_estimatedCost! >= _costWarningThreshold)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '⚠️ 本月花费已达 ${_estimatedCost!.toStringAsFixed(2)} 元，建议在厂商控制台设置月度费用上限',
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),

          // --- 图片管理 ---
          _sectionHeader('图片管理'),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('原图保留期'),
            trailing: DropdownButton<int>(
              value: _imageRetentionDays,
              items: const [
                DropdownMenuItem(value: 7, child: Text('7 天')),
                DropdownMenuItem(value: 30, child: Text('30 天（默认）')),
                DropdownMenuItem(value: 0, child: Text('永久保留')),
              ],
              onChanged: (v) => setState(() => _imageRetentionDays = v ?? 30),
            ),
          ),
          const SizedBox(height: 16),

          // --- 数据备份状态 ---
          _sectionHeader('数据备份'),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('上次自动备份'),
            trailing: Text(
              _lastBackupTime ?? '从未',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_backupOverdue)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '⚠️ 已超过 14 天未备份，建议立即导出备份',
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),

          // --- 隐私政策 ---
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('隐私政策'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showPrivacyPolicy,
          ),

          // --- 关于 ---
          _sectionHeader('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于慢慢吃'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showAbout,
          ),
          const SizedBox(height: 16),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save),
            label: const Text('保存设置'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  /// 主题色色板：圆形色块网格，选中态带勾选，点选即时换肤 + 持久化。
  Widget _themePalette() {
    final current = ref.watch(themeSeedProvider);
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        for (final (argb, name) in kThemePresets)
          _colorDot(Color(argb), name, current == argb, () async {
            // 即时换肤：更新 provider → App 重建
            ref.read(themeSeedProvider.notifier).set(argb);
            // 持久化到 secure_storage
            await ref.read(secureConfigStoreProvider).setThemeSeed(argb);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已切换主题：$name'),
                  duration: const Duration(seconds: 1),
                ),
              );
            }
          }),
      ],
    );
  }

  Widget _colorDot(Color c, String name, bool selected, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Tooltip(
        message: name,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 3,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 24)
              : null,
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = ref.read(secureConfigStoreProvider);
      await store.setQwenApiKey(_qwenKeyCtrl.text.trim());
      await store.setQwenBaseUrl(
        _qwenUrlCtrl.text.trim().isEmpty ? null : _qwenUrlCtrl.text.trim(),
      );
      await store.setGlmApiKey(_glmKeyCtrl.text.trim());
      await store.setGlmBaseUrl(
        _glmUrlCtrl.text.trim().isEmpty ? null : _glmUrlCtrl.text.trim(),
      );
      await store.setSentryDsn(
        _sentryDsnCtrl.text.trim().isEmpty ? null : _sentryDsnCtrl.text.trim(),
      );
      await store.setSentryEnabled(_sentryEnabled);
      await store.setTdeeAutoCalib(_tdeeAutoCalib);
      await store.setImageRetentionDays(_imageRetentionDays);

      // 重新加载 appConfig（让其他 Provider 感知新值）
      final config = await ref.read(appConfigProvider.future);
      await config.reload();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('设置已保存')));
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAbout() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('关于慢慢吃'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('慢慢吃 v0.9.0'),
            const SizedBox(height: 8),
            const Text('拍照识别食物热量 + 营养记录 + AI 汇总建议'),
            const SizedBox(height: 8),
            Text(
              '营养目标依据 ACSM/ISSN/NIH/WHO 标准',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
