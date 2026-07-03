import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/profile/profile_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 ProfilePage goal_rate 输入显示逻辑
/// - 减脂/增肌时显示「目标速率」输入
/// - 维持时不显示
/// databaseProvider override 为内存 DB（绕过 path_provider 平台插件）
void main() {
  testWidgets('减脂时显示 goal_rate 输入', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [recognize.databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // goal 是第 2 个 DropdownButtonFormField<String>（gender=第1, activity 是 double）
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('减脂').last);
    await tester.pumpAndSettle();

    // 验证 goal_rate 输入显示
    expect(find.textContaining('目标速率'), findsOneWidget);
  });

  testWidgets('维持时不显示 goal_rate 输入', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [recognize.databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 选 maintain（goal 是第 2 个 DropdownButtonFormField<String>）
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('维持').last);
    await tester.pumpAndSettle();

    // 验证 goal_rate 输入不显示
    expect(find.textContaining('目标速率'), findsNothing);
  });
}
