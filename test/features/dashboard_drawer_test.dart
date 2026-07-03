// test/features/dashboard_drawer_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/dashboard/dashboard_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dashboard Drawer 测试
/// 验证 Drawer 7 个入口文本可见
/// databaseProvider override 为内存 DB（绕过 path_provider 平台插件）
void main() {
  testWidgets('Dashboard Drawer 含 7 个功能入口', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(
      overrides: [recognize.databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    // 等 FutureBuilder 加载（内存 DB 种子 profile 存在，应快速完成）
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 打开 Drawer（Scaffold 有 drawer 时 AppBar 自动显示汉堡按钮，tooltip 为 'Open navigation menu'）
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    // 验证 7 个入口文本
    expect(find.text('个人档案'), findsOneWidget);
    expect(find.text('体重记录'), findsOneWidget);
    expect(find.text('AI 周报'), findsOneWidget);
    expect(find.text('食物库'), findsOneWidget);
    expect(find.text('手动录入'), findsOneWidget);
    expect(find.text('数据备份'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
