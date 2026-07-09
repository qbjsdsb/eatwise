// lib/core/config/secure_config_store.dart
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 安全配置存储封装
/// 统一管理 flutter_secure_storage 读写，iOS/Android 安全选项集中配置
///
/// 存储项：
/// - qwen_api_key / qwen_base_url：Qwen-VL 视觉模型
/// - glm_api_key / glm_base_url：GLM-4-Flash 文本模型 + GLM-4V-Plus 容灾
/// - sentry_dsn：Sentry 错误监控
/// - tdee_auto_calib：TDEE 自适应校准开关（'1'/'0'）
/// - sentry_enabled：Sentry 上报开关（'1'/'0'）
class SecureConfigStore {
  static const _qwenApiKey = 'qwen_api_key';
  static const _qwenBaseUrl = 'qwen_base_url';
  static const _glmApiKey = 'glm_api_key';
  static const _glmBaseUrl = 'glm_base_url';
  static const _sentryDsn = 'sentry_dsn';
  static const _sentryEnabled = 'sentry_enabled';
  static const _tdeeAutoCalib = 'tdee_auto_calib';

  final FlutterSecureStorage _storage;

  SecureConfigStore()
      : _storage = const FlutterSecureStorage(
          // iOS：首次解锁后可用 + 禁止 iCloud 同步（双重保险防备份恢复）
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
            synchronizable: false,
          ),
          // Android：10.x 默认 RSA OAEP + AES-GCM，minSdk 23+
          // （encryptedSharedPreferences 已废弃，默认即自动迁移到 custom ciphers）
        );

  @visibleForTesting
  SecureConfigStore.forTesting(FlutterSecureStorage storage) : _storage = storage;

  // --- Qwen ---
  Future<String?> getQwenApiKey() => _storage.read(key: _qwenApiKey);
  Future<void> setQwenApiKey(String? v) => _writeOrDelete(_qwenApiKey, v);

  Future<String?> getQwenBaseUrl() => _storage.read(key: _qwenBaseUrl);
  Future<void> setQwenBaseUrl(String? v) => _writeOrDelete(_qwenBaseUrl, v);

  // --- GLM ---
  Future<String?> getGlmApiKey() => _storage.read(key: _glmApiKey);
  Future<void> setGlmApiKey(String? v) => _writeOrDelete(_glmApiKey, v);

  Future<String?> getGlmBaseUrl() => _storage.read(key: _glmBaseUrl);
  Future<void> setGlmBaseUrl(String? v) => _writeOrDelete(_glmBaseUrl, v);

  // --- Sentry ---
  Future<String?> getSentryDsn() => _storage.read(key: _sentryDsn);
  Future<void> setSentryDsn(String? v) => _writeOrDelete(_sentryDsn, v);

  Future<bool> getSentryEnabled() async =>
      (await _storage.read(key: _sentryEnabled)) == '1';
  Future<void> setSentryEnabled(bool v) =>
      _storage.write(key: _sentryEnabled, value: v ? '1' : '0');

  // --- TDEE 自适应校准 ---
  Future<bool> getTdeeAutoCalib() async =>
      (await _storage.read(key: _tdeeAutoCalib)) != '0'; // 默认开启
  Future<void> setTdeeAutoCalib(bool v) =>
      _storage.write(key: _tdeeAutoCalib, value: v ? '1' : '0');

  // --- 通用 raw 读写（断路器/月度计数/保留期等用，key 自定义）---
  Future<void> writeRaw(String key, String value) => _storage.write(key: key, value: value);
  Future<String?> readRaw(String key) => _storage.read(key: key);
  Future<void> deleteRaw(String key) => _storage.delete(key: key);

  // --- 主题种子色（ARGB int 的十进制字符串，默认 M3 基线紫 0xFF6750A4）---
  static const _themeSeed = 'theme_seed';

  /// 读取主题种子色 ARGB int（默认 M3 基线紫，与 ThemeNotifier.build() 一致）
  Future<int> getThemeSeed() async {
    final v = await readRaw(_themeSeed);
    return int.tryParse(v ?? '') ?? 0xFF6750A4;
  }

  Future<void> setThemeSeed(int argb) => writeRaw(_themeSeed, argb.toString());

  // --- 是否跟随系统壁纸取色（'1'/'0'，默认 false）---
  static const _useDynamicColor = 'use_dynamic_color';

  /// 读取是否跟随系统壁纸取色（默认 false，与 UseDynamicColorNotifier.build() 一致）
  Future<bool> getUseDynamicColor() async =>
      (await readRaw(_useDynamicColor)) == '1';

  Future<void> setUseDynamicColor(bool v) =>
      writeRaw(_useDynamicColor, v ? '1' : '0');

  // --- T48 图片保留期（0=永久保留，默认 30）---
  static const _imageRetentionDays = 'image_retention_days';

  /// 读取图片保留期（0=永久保留，默认 30）
  Future<int> getImageRetentionDays() async {
    final v = await readRaw(_imageRetentionDays);
    return int.tryParse(v ?? '30') ?? 30;
  }

  Future<void> setImageRetentionDays(int days) async {
    await writeRaw(_imageRetentionDays, days.toString());
  }

  // --- T43 月度识别计数（按月归档，key: monthly_count_YYYYMM）---
  static const _monthlyCountPrefix = 'monthly_count_';

  /// 读取某月识别次数（key: monthly_count_YYYYMM）
  Future<int> getMonthlyCount(int year, int month) async {
    final key = '$_monthlyCountPrefix$year${month.toString().padLeft(2, '0')}';
    final v = await readRaw(key);
    return int.tryParse(v ?? '0') ?? 0;
  }

  /// 增加某月识别次数（+1）
  Future<void> incrementMonthlyCount(int year, int month) async {
    final key = '$_monthlyCountPrefix$year${month.toString().padLeft(2, '0')}';
    final current = await getMonthlyCount(year, month);
    await writeRaw(key, (current + 1).toString());
  }

  /// 读取本月识别次数
  Future<int> getCurrentMonthCount() async {
    final now = DateTime.now();
    return getMonthlyCount(now.year, now.month);
  }

  // --- 付费 API 调用计数（按月归档，key: monthly_api_calls_YYYYMM）---
  // 与"识别次数"区分：识别次数 = 用户视角成功识别次数；
  // API 调用次数 = 计费视角实际消耗的付费视觉 API 次数（含重试/L2 切备/校验重试）。
  // 估算费用基于本指标。GLM-4-Flash（免费）的调用不计入。
  static const _monthlyApiCallsPrefix = 'monthly_api_calls_';

  /// 读取某月付费 API 调用次数
  Future<int> getMonthlyApiCalls(int year, int month) async {
    final key =
        '$_monthlyApiCallsPrefix$year${month.toString().padLeft(2, '0')}';
    final v = await readRaw(key);
    return int.tryParse(v ?? '0') ?? 0;
  }

  /// 增加某月付费 API 调用次数（+1）
  Future<void> incrementMonthlyApiCalls(int year, int month) async {
    final key =
        '$_monthlyApiCallsPrefix$year${month.toString().padLeft(2, '0')}';
    final current = await getMonthlyApiCalls(year, month);
    await writeRaw(key, (current + 1).toString());
  }

  /// 读取本月付费 API 调用次数
  Future<int> getCurrentMonthApiCalls() async {
    final now = DateTime.now();
    return getMonthlyApiCalls(now.year, now.month);
  }

  // --- 辅助 ---
  Future<void> _writeOrDelete(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }
}
