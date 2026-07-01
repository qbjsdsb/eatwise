// lib/core/config/app_config.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'secure_config_store.dart';

/// 运行时配置（替代 Sprint 1/2 的 String.fromEnvironment 硬编码）
/// 读取优先级：secure_storage > --dart-define > 空串
///
/// 首次使用：用户在设置页输入 key → 写入 secure_storage
/// 兼容旧版：仍可用 --dart-define=QWEN_API_KEY=xxx 启动（作为 fallback）
class AppConfig {
  final SecureConfigStore _store;
  AppConfig(this._store);

  // 启动时一次性加载到内存（避免每次读 API 都 await）
  late String qwenApiKey;
  late String qwenBaseUrl;
  late String glmApiKey;
  late String glmBaseUrl;
  late String sentryDsn;
  late bool sentryEnabled;
  late bool tdeeAutoCalib;

  /// 从 secure_storage 加载全部配置（App 启动时调用一次）
  /// --dart-define 作为 fallback：若 secure_storage 无值则用 define 值并回写 storage
  Future<void> load() async {
    qwenApiKey = (await _store.getQwenApiKey()) ??
        const String.fromEnvironment('QWEN_API_KEY', defaultValue: '');
    qwenBaseUrl = (await _store.getQwenBaseUrl()) ??
        const String.fromEnvironment('QWEN_BASE_URL', defaultValue: '');
    glmApiKey = (await _store.getGlmApiKey()) ??
        const String.fromEnvironment('GLM_API_KEY', defaultValue: '');
    glmBaseUrl = (await _store.getGlmBaseUrl()) ??
        const String.fromEnvironment('GLM_BASE_URL', defaultValue: '');
    sentryDsn = await _store.getSentryDsn() ??
        const String.fromEnvironment('SENTRY_DSN', defaultValue: '');
    sentryEnabled = await _store.getSentryEnabled();
    tdeeAutoCalib = await _store.getTdeeAutoCalib();

    // 首次注入：若 secure_storage 为空但 define 有值，回写 storage（后续不再依赖 define）
    if ((await _store.getQwenApiKey()) == null && qwenApiKey.isNotEmpty) {
      await _store.setQwenApiKey(qwenApiKey);
    }
    if ((await _store.getGlmApiKey()) == null && glmApiKey.isNotEmpty) {
      await _store.setGlmApiKey(glmApiKey);
    }
    if ((await _store.getSentryDsn()) == null && sentryDsn.isNotEmpty) {
      await _store.setSentryDsn(sentryDsn);
    }
  }

  /// 设置页修改后重新加载
  Future<void> reload() => load();
}

final secureConfigStoreProvider = Provider<SecureConfigStore>(
  (ref) => SecureConfigStore(),
);

final appConfigProvider = FutureProvider<AppConfig>((ref) async {
  final store = ref.read(secureConfigStoreProvider);
  final config = AppConfig(store);
  await config.load();
  return config;
});
