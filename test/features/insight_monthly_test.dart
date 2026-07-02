import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/insight/insight_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 InsightPage 周/月切换：默认周视图有'周'/'月'按钮，点击'月'切换不崩溃。
void main() {
  testWidgets('切换到月视图', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: InsightPage()),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 默认周视图：'周'和'月'按钮都存在
    expect(find.text('周'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);

    // 点击"月"切换
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 验证切换成功（不崩溃，InsightPage 仍渲染）
    expect(find.byType(InsightPage), findsOneWidget);
    // 切换后'周'/'月'按钮仍在
    expect(find.text('周'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);
  });
}
