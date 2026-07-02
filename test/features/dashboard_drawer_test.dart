// test/features/dashboard_drawer_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/dashboard/dashboard_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 首页测试（原 Drawer 测试已废弃，Drawer 改为底部导航后入口在 MainShell）
/// 验证首页状态卡片核心元素可见
void main() {
  testWidgets('首页状态卡片显示今日还可摄入', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
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
