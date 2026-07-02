// test/features/monthly_cost_test.dart
// T43 月度识别计数存储测试 + T44 设置页 UI 测试
//
// 注意：flutter_secure_storage 在沙箱无平台通道，用 setMockInitialValues
// 注入内存平台实现（flutter_secure_storage 10.3.1 自带 TestFlutterSecureStoragePlatform）。
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
    // 沙箱无平台通道，注入内存 mock 平台实现（计划预案：实施时核实）
    FlutterSecureStorage.setMockInitialValues({});
    store = SecureConfigStore();
  });

  test('月度计数初始为 0', () async {
    final count = await store.getMonthlyCount(2026, 7);
    expect(count, 0);
  });

  test('increment 后计数 +1', () async {
    await store.incrementMonthlyCount(2026, 7);
    expect(await store.getMonthlyCount(2026, 7), 1);
    await store.incrementMonthlyCount(2026, 7);
    expect(await store.getMonthlyCount(2026, 7), 2);
  });

  test('不同月份独立计数', () async {
    await store.incrementMonthlyCount(2026, 7);
    await store.incrementMonthlyCount(2026, 7);
    await store.incrementMonthlyCount(2026, 6);
    expect(await store.getMonthlyCount(2026, 7), 2);
    expect(await store.getMonthlyCount(2026, 6), 1);
  });

  testWidgets('T44：设置页显示本月识别次数', (tester) async {
    // SettingsPage._loadSettings 依次 await：
    //   1. ref.read(appConfigProvider.future) → 内部读 secureConfigStoreProvider
    //   2. AutoBackup.lastBackupTime() → 调 getApplicationDocumentsDirectory
    //   3. store.getCurrentMonthCount()
    // override secureConfigStoreProvider 即可让 appConfigProvider 走真实路径
    // （store 已带 FlutterSecureStorage 内存 mock）。path_provider 也需 mock，
    // 否则 lastBackupTime 的平台通道会挂起。
    await store.incrementMonthlyCount(2026, 7);

    PathProviderPlatform.instance = _MemoryPathProvider('/tmp/monthly_cost_test');

    // 放大测试视口：SettingsPage 的 ListView 是懒加载的，默认 800×600 视口
    // 无法完整显示「本月使用」区块（位于营养校准之后），需加高视口让所有
    // ListView 子项被 build，否则 find.text 找不到目标文本。
    await tester.binding.setSurfaceSize(const Size(800, 2400));

    final container = ProviderContainer(overrides: [
      secureConfigStoreProvider.overrideWithValue(store),
    ]);
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
    expect(find.text('本月识别次数'), findsOneWidget);
    expect(find.text('1 次'), findsOneWidget);
    expect(find.text('估算花费'), findsOneWidget);
    expect(find.text('0.001 元'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
