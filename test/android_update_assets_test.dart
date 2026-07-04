// M16 Android 更新资源静态测试（F1）
//
// 验证 AndroidManifest 与 file_paths.xml 配置：
// - REQUEST_INSTALL_PACKAGES 权限（Android 8+ 安装 APK 必需）
// - FileProvider 注册（Android 7+ 共享 file:// URI 必需）
// - file_paths.xml 存在并配置 cache-path
//
// 仿 test/icon_assets_test.dart 模式：纯文件读取断言，不依赖 Android SDK。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('M16 Android 更新资源', () {
    final manifestPath = 'android/app/src/main/AndroidManifest.xml';
    final filePathsXmlPath = 'android/app/src/main/res/xml/file_paths.xml';

    test('AndroidManifest 含 REQUEST_INSTALL_PACKAGES 权限', () {
      final manifest = File(manifestPath).readAsStringSync();
      expect(
        manifest,
        contains('android.permission.REQUEST_INSTALL_PACKAGES'),
        reason: '应用内安装 APK 必须声明此权限（Android 8+）',
      );
    });

    test('AndroidManifest 注册了 FileProvider', () {
      final manifest = File(manifestPath).readAsStringSync();
      expect(manifest, contains('androidx.core.content.FileProvider'));
      expect(manifest, contains('android:authorities'));
      expect(manifest, contains('\${applicationId}.fileprovider'));
      expect(manifest, contains('android:grantUriPermissions="true"'));
    });

    test('file_paths.xml 存在并配置 cache-path', () {
      expect(File(filePathsXmlPath).existsSync(), true,
          reason: 'FileProvider 必须配置 file_paths.xml');
      final content = File(filePathsXmlPath).readAsStringSync();
      // cache-path 用于共享 getApplicationCacheDirectory() 下的 APK
      expect(content, contains('cache-path'));
      expect(content, contains('name="cache"'));
      expect(content, contains('path="."'));
    });
  });
}
