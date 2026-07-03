import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/insight_repository.dart';
import 'package:eatwise/features/insight/insight_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 InsightPage 重新生成二次确认：
/// - _summary 非空时点"重新生成"弹确认对话框
/// - 点取消 → 对话框关闭，不调用 _generate（_summary 保持原值）
void main() {
  testWidgets('已有汇总时点重新生成弹确认框，取消后汇总不变', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // 先插入一条已有汇总（模拟用户之前生成过）
    final repo = InsightRepository(db);
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await repo.insert(
      periodType: 'weekly',
      periodStart: fmt(monday),
      periodEnd: fmt(sunday),
      summaryText: '这是已有的汇总内容',
    );

    final container = ProviderContainer(
      overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
        recognize.glmApiKeyProvider.overrideWith((ref) => 'fake-key'),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InsightPage()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 验证已有汇总显示
    expect(find.textContaining('这是已有的汇总内容'), findsOneWidget);

    // 点"重新生成"按钮
    expect(find.text('重新生成'), findsOneWidget);
    await tester.tap(find.text('重新生成'));
    await tester.pumpAndSettle();

    // 验证确认对话框出现
    expect(find.text('重新生成'), findsWidgets); // 对话框标题也是"重新生成"
    expect(find.text('重新生成会覆盖当前汇总，是否继续？'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);

    // 点取消
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 验证对话框关闭，汇总内容保持不变
    expect(find.text('重新生成会覆盖当前汇总，是否继续？'), findsNothing);
    expect(find.textContaining('这是已有的汇总内容'), findsOneWidget);
  });
}
