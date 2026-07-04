// app_version_provider 测试（M13）
//
// 验证 appVersionProvider 从 PackageInfo 读取版本号（替代三处硬编码）。
// 沙箱无平台通道时用 PackageInfo.setMockInitialValues 注入内存 mock。
import 'package:eatwise/core/config/app_version_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  group('M13 appVersionProvider', () {
    setUp(() {
      // mock 平台返回的 PackageInfo（沙箱无平台通道，必须 mock）
      PackageInfo.setMockInitialValues(
        appName: '慢慢吃',
        packageName: 'com.example.eatwise',
        version: '0.16.0',
        buildNumber: '17',
        buildSignature: '',
        installerStore: null,
      );
    });

    test('M13: appVersionProvider 返回 version+buildNumber 格式', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final version = await container.read(appVersionProvider.future);
      // 期望格式：'0.16.0+17'（与 pubspec.yaml version: 0.16.0+17 一致）
      expect(version, '0.16.0+17');
    });

    test('M13: appVersionShortProvider 返回纯版本号（不含 buildNumber）',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final version = await container.read(appVersionShortProvider.future);
      // 期望纯版本号：'0.16.0'（用于 Sentry release 标签）
      expect(version, '0.16.0');
    });

    test('M13: mock 不同版本号时 provider 返回新值（验证动态读取）', () async {
      // 模拟 pubspec bump 后版本号变化
      PackageInfo.setMockInitialValues(
        appName: '慢慢吃',
        packageName: 'com.example.eatwise',
        version: '0.17.0',
        buildNumber: '18',
        buildSignature: '',
        installerStore: null,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final version = await container.read(appVersionProvider.future);
      expect(version, '0.17.0+18',
          reason: 'pubspec bump 后 provider 应自动同步，无需改代码');
    });
  });
}
