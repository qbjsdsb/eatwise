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
  // 注：主题色 themeSeed 由 themeSeedProvider + SecureConfigStore 单独管理，
  // 不放入 AppConfig 避免双源不同步（设置页切色只更 themeSeedProvider + 写 storage，
  // 不重载 appConfig）

  /// 从 secure_storage 加载全部配置（App 启动时调用一次）
  /// --dart-define 作为 fallback：若 secure_storage 无值则用 define 值并回写 storage
  ///
  /// 性能：flutter_secure_storage 每次 read 都是独立 platform channel + Keystore 解密，
  /// 串行 10+ 次会有 200-500ms 开销。这里用 Future.wait 并行读 7 个 key，
  /// 且复用已读结果判断是否需要首次注入回写（省掉原来 3 次重复 read）。
  Future<void> load() async {
    // 并行读取所有 key（原串行 10+ 次 platform channel → 并行启动）
    // 用"同时启动 + 分别 await"模式，类型安全且并行
    // （Future.wait 因 7 个 future 类型不同会退化为 List<Object?>，丢失类型信息）
    final qwenKeyFuture = _store.getQwenApiKey();
    final qwenUrlFuture = _store.getQwenBaseUrl();
    final glmKeyFuture = _store.getGlmApiKey();
    final glmUrlFuture = _store.getGlmBaseUrl();
    final sentryDsnFuture = _store.getSentryDsn();
    final sentryEnabledFuture = _store.getSentryEnabled();
    final tdeeAutoCalibFuture = _store.getTdeeAutoCalib();

    final qwenKeyRaw = await qwenKeyFuture;
    final qwenUrlRaw = await qwenUrlFuture;
    final glmKeyRaw = await glmKeyFuture;
    final glmUrlRaw = await glmUrlFuture;
    final sentryDsnRaw = await sentryDsnFuture;
    sentryEnabled = await sentryEnabledFuture;
    tdeeAutoCalib = await tdeeAutoCalibFuture;

    qwenApiKey = qwenKeyRaw ??
        const String.fromEnvironment('QWEN_API_KEY', defaultValue: '');
    qwenBaseUrl = qwenUrlRaw ??
        const String.fromEnvironment('QWEN_BASE_URL', defaultValue: '');
    glmApiKey = glmKeyRaw ??
        const String.fromEnvironment('GLM_API_KEY', defaultValue: '');
    glmBaseUrl = glmUrlRaw ??
        const String.fromEnvironment('GLM_BASE_URL', defaultValue: '');
    sentryDsn = sentryDsnRaw ??
        const String.fromEnvironment('SENTRY_DSN', defaultValue: '');

    // 首次注入：若 secure_storage 为空但 define 有值，回写 storage（后续不再依赖 define）
    // 复用上面已读结果判断 null，省掉原来的 3 次重复 read
    if (qwenKeyRaw == null && qwenApiKey.isNotEmpty) {
      await _store.setQwenApiKey(qwenApiKey);
    }
    if (glmKeyRaw == null && glmApiKey.isNotEmpty) {
      await _store.setGlmApiKey(glmApiKey);
    }
    if (sentryDsnRaw == null && sentryDsn.isNotEmpty) {
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
