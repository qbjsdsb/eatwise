// lib/core/update/apk_installer.dart
//
// 触发 Android 系统包安装器。
//
// 通过 MethodChannel 调原生代码：
// - Dart 侧传 APK 文件路径
// - Kotlin 侧用 FileProvider.getUriForFile + Intent(ACTION_VIEW) + application/vnd.android.package-archive
// - 系统弹窗让用户确认安装
//
// Android 8+ 必须 REQUEST_INSTALL_PACKAGES 权限（已在 AndroidManifest 声明）
// Android 7+ 必须用 FileProvider 共享 file:// URI（已注册 FileProvider）

import 'package:flutter/services.dart';

class ApkInstaller {
  ApkInstaller._();

  static const channel = MethodChannel('com.eatwise.eatwise/apk_installer');

  /// 触发系统安装器安装指定路径的 APK。
  /// 抛 [PlatformException]：原生侧找不到包安装器 / FileProvider 配置错 / 路径无效
  static Future<void> triggerInstall(String apkPath) async {
    await channel.invokeMethod<void>('triggerInstall', apkPath);
  }
}
