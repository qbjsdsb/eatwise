// lib/features/settings/settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
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
          ? '${lastBackup.year}-${lastBackup.month.toString().padLeft(2,'0')}-${lastBackup.day.toString().padLeft(2,'0')}'
          : null;
    } catch (_) {
      // 防御性兜底：沙箱/真机异常均不传播（真机正常路径不进此分支）
      _lastBackupTime = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- AI 模型配置 ---
          _sectionHeader('AI 模型配置'),
          TextField(
            controller: _qwenKeyCtrl,
            decoration: const InputDecoration(labelText: 'Qwen API Key', border: OutlineInputBorder()),
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
            decoration: const InputDecoration(labelText: 'GLM API Key', border: OutlineInputBorder()),
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
            decoration: const InputDecoration(labelText: 'Sentry DSN', border: OutlineInputBorder()),
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

          // --- 数据备份状态 ---
          _sectionHeader('数据备份'),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('上次自动备份'),
            trailing: Text(_lastBackupTime ?? '从未', style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(height: 16),

          // --- 隐私政策 ---
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('隐私政策'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showPrivacyPolicy,
          ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
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

  Future<void> _save() async {
    final store = ref.read(secureConfigStoreProvider);
    await store.setQwenApiKey(_qwenKeyCtrl.text.trim());
    await store.setQwenBaseUrl(_qwenUrlCtrl.text.trim().isEmpty ? null : _qwenUrlCtrl.text.trim());
    await store.setGlmApiKey(_glmKeyCtrl.text.trim());
    await store.setGlmBaseUrl(_glmUrlCtrl.text.trim().isEmpty ? null : _glmUrlCtrl.text.trim());
    await store.setSentryDsn(_sentryDsnCtrl.text.trim().isEmpty ? null : _sentryDsnCtrl.text.trim());
    await store.setSentryEnabled(_sentryEnabled);
    await store.setTdeeAutoCalib(_tdeeAutoCalib);

    // 重新加载 appConfig（让其他 Provider 感知新值）
    final config = await ref.read(appConfigProvider.future);
    await config.reload();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置已保存')));
      Navigator.of(context).pop();
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
}
