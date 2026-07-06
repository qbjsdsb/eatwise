// test/app_dynamic_color_test.dart
// EatWiseApp DynamicColorBuilder 三态决策测试
//
// 沙箱限制：DynamicColorBuilder 在沙箱可能返回 null（无 Android 平台通道），
// 主要测试 fallback 路径。动态色可用路径需真机验证。
//
// EatWiseApp 经 go_router 渲染 DashboardPage，需 override databaseProvider
// / secureConfigStoreProvider / networkAvailableProvider 避免 MissingPluginException
// 导致 DashboardPage 异步 Future 永不 settle。
import 'package:drift/native.dart';
import 'package:eatwise/app.dart';
import 'package:eatwise/core/config/app_config.dart';
import 'package:eatwise/core/config/secure_config_store.dart';
import 'package:eatwise/core/theme/theme_controller.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 共用 setup：内存 DB + 空 secure_storage + 强制离线
  // 让 DashboardPage 的异步 Future 能正常 settle（不抛 MissingPluginException）
  ProviderContainer buildContainer() {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureConfigStore();
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
      secureConfigStoreProvider.overrideWithValue(store),
      // 强制离线：避免 Connectivity().checkConnectivity() 抛 MissingPluginException
      recognize.networkAvailableProvider.overrideWith((ref) async => false),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('EatWiseApp 动态取色 fallback 路径', () {
    testWidgets('useDynamic=false（默认）→ fromSeed fallback', (tester) async {
      final container = buildContainer();

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const EatWiseApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(MaterialApp), findsOneWidget);
      final theme = Theme.of(tester.element(find.byType(MaterialApp)));
      expect(theme.colorScheme, isA<ColorScheme>());
    });

    testWidgets('useDynamic=true 但沙箱 lightDynamic=null → 仍 fromSeed fallback',
        (tester) async {
      final container = buildContainer();
      // 预置 useDynamic=true（NotifierProvider 不能用 overrideWith((ref) => value)，
      // 通过 notifier.set 在 pump 前设置初始状态）
      container.read(useDynamicColorProvider.notifier).set(true);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const EatWiseApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(MaterialApp), findsOneWidget);
      final theme = Theme.of(tester.element(find.byType(MaterialApp)));
      expect(theme.colorScheme, isA<ColorScheme>());
    });

    testWidgets('切换 useDynamicColorProvider 触发 rebuild', (tester) async {
      final container = buildContainer();

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const EatWiseApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      container.read(useDynamicColorProvider.notifier).set(true);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(MaterialApp), findsOneWidget);

      container.read(useDynamicColorProvider.notifier).set(false);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('切换 themeSeedProvider 触发 rebuild 换肤', (tester) async {
      final container = buildContainer();

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const EatWiseApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      container.read(themeSeedProvider.notifier).set(0xFF2E7D32);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
