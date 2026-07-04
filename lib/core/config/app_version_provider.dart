// lib/core/config/app_version_provider.dart
//
// 应用版本号 provider（M13 修复）
//
// 替代 me_page / settings_page / sentry_init 三处硬编码 '0.16.0'，
// 从 PackageInfo 动态读取，pubspec.yaml bump 后自动同步无需改代码。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 完整版本号（version+buildNumber），用于 UI 展示
/// 格式：'0.16.0+17'（与 pubspec.yaml version: 0.16.0+17 一致）
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
});

/// 纯版本号（不含 buildNumber），用于 Sentry release 标签
/// 格式：'0.16.0'
final appVersionShortProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});
