// test/features/settings_completeness_test.dart
// T49 设置页补全测试：图片保留期选择 + 关于入口
//
// 注意：flutter_secure_storage 在沙箱无平台通道，用 setMockInitialValues
// 注入内存平台实现。SettingsPage._loadSettings 调 AutoBackup.lastBackupTime
// 需要 path_provider，沙箱无平台通道会挂起，需 mock。
import 'package:eatwise/core/config/app_config.dart';
import 'package:eatwise/core/config/secure_config_store.dart';
import 'package:eatwise/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// path_provider 内存 mock（SettingsPage._loadSettings 调 AutoBackup.lastBackupTime
// 需要 getApplicationDocumentsDirectory，沙箱无平台通道会挂起）
class _MemoryPathProvider extends PathProviderPlatform {
  final String basePath;
  _MemoryPathProvider(this.basePath);
  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

void main() {
  late SecureConfigStore store;

  setUp(() {
    // 沙箱无平台通道，注入内存 mock 平台实现
    FlutterSecureStorage.setMockInitialValues({});
    store = SecureConfigStore();
  });

  testWidgets('设置页含图片保留期选择', (tester) async {
    PathProviderPlatform.instance = _MemoryPathProvider(
      '/tmp/settings_completeness_test',
    );

    // 放大视口：SettingsPage 的 ListView 懒加载，保留期/关于区位于列表后段，
    // 默认 800×600 视口无法完整显示，需加高视口让所有子项被 build。
    await tester.binding.setSurfaceSize(const Size(800, 2400));

    final container = ProviderContainer(
      overrides: [secureConfigStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    // runAsync 让 _loadSettings 中的真实异步（secure_storage 读、目录检查）
    // 在真实事件循环中完成；pumpAndSettle 会等所有 frame 稳定。
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('保留期'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('设置页含关于入口', (tester) async {
    PathProviderPlatform.instance = _MemoryPathProvider(
      '/tmp/settings_completeness_test2',
    );

    await tester.binding.setSurfaceSize(const Size(800, 2400));

    final container = ProviderContainer(
      overrides: [secureConfigStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('关于'), findsWidgets);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
