// test/features/dashboard_drawer_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/core/config/app_config.dart';
import 'package:eatwise/core/config/secure_config_store.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/dashboard/dashboard_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 首页测试（原 Drawer 测试已废弃，Drawer 改为底部导航后入口在 MainShell）
/// 验证首页状态卡片核心元素可见
void main() {
  testWidgets('首页状态卡片显示今日还可摄入', (tester) async {
    // 沙箱无 secure_storage 平台通道，注入内存 mock（v5 看板 initState 会
    // 调 appConfigProvider.future 检查 GLM key，不 mock 会抛 MissingPluginException
    // 导致 AI FutureBuilder 卡在 loading，CircularProgressIndicator 永不停止）
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureConfigStore();

    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
      secureConfigStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 验证状态卡片核心文本可见
    expect(find.text('今日还可摄入'), findsOneWidget);
    expect(find.text('kcal · 已摄入 0 / 2000'), findsOneWidget);
    // 宏量标签
    expect(find.text('蛋白'), findsOneWidget);
    expect(find.text('脂肪'), findsOneWidget);
    expect(find.text('碳水'), findsOneWidget);
  });
}
