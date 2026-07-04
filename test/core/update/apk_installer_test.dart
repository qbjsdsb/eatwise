// ApkInstaller MethodChannel 测试（M16-F2）
//
// 验证 Dart 端 ApkInstaller.triggerInstall 通过 MethodChannel 调原生。
// 沙箱无平台通道，用 TestDefaultBinaryMessengerBinding 拦截 MethodChannel 调用。
import 'package:eatwise/core/update/apk_installer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApkInstaller', () {
    test('triggerInstall 调用 MethodChannel 触发安装', () async {
      // 拦截 MethodChannel 调用
      final handler = <Map<String, dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ApkInstaller.channel, (call) async {
        handler.add({
          'method': call.method,
          'args': call.arguments,
        });
        return null;
      });

      await ApkInstaller.triggerInstall('/tmp/x.apk');

      expect(handler.length, 1);
      expect(handler.first['method'], 'triggerInstall');
      expect(handler.first['args'], '/tmp/x.apk');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ApkInstaller.channel, null);
    });

    test('triggerInstall 失败抛 PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ApkInstaller.channel, (call) async {
        throw PlatformException(
            code: 'INSTALL_FAILED', message: 'installer not found');
      });

      expect(
        () => ApkInstaller.triggerInstall('/tmp/x.apk'),
        throwsA(isA<PlatformException>()),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ApkInstaller.channel, null);
    });
  });
}
