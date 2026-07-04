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
    // v1.11：滚动窗口策略——periodStart = today-6, periodEnd = today（不再用自然周一二三四五六日）
    final repo = InsightRepository(db);
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 6));
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await repo.insert(
      periodType: 'weekly',
      periodStart: fmt(start),
      periodEnd: fmt(now),
      summaryText: '这是已有的汇总内容',
    );

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
      recognize.glmApiKeyProvider.overrideWith((ref) => 'fake-key'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: InsightPage()),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 验证已有汇总显示
    expect(find.textContaining('这是已有的汇总内容'), findsOneWidget);

    // 点"重新生成"按钮
    expect(find.text('重新生成'), findsOneWidget);
    // v1.11：覆盖率提示 + 汇总 Card 把按钮推到 600px 视口外，需手动滚动 ListView 再 tap
    // （scrollUntilVisible 会因 pump 时 setState 产生多匹配而抛 "Too many elements"）
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新生成'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

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

  /// M2 修复：SegmentedButton 快速切换 weekly→monthly→weekly 时，
  /// 旧 _loadExisting（monthly）的 setState 不应覆盖新切换后的 weekly 汇总。
  /// 根因：_loadExisting 是 async，切换时旧调用未完成，完成后 setState 旧结果覆盖新状态。
  /// 修复：加 _loadVersion 版本号守卫，版本不匹配时丢弃 setState。
  testWidgets('M2: 快速切换 weekly→monthly→weekly 时不会显示错配汇总', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // 种子：weekly 和 monthly 都有已有汇总
    final repo = InsightRepository(db);
    final now = DateTime.now();
    final weeklyStart = now.subtract(const Duration(days: 6));
    final monthlyStart = now.subtract(const Duration(days: 29));
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await repo.insert(
        periodType: 'weekly',
        periodStart: fmt(weeklyStart),
        periodEnd: fmt(now),
        summaryText: '这是周报内容');
    await repo.insert(
        periodType: 'monthly',
        periodStart: fmt(monthlyStart),
        periodEnd: fmt(now),
        summaryText: '这是月报内容');

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
      recognize.glmApiKeyProvider.overrideWith((ref) => 'fake-key'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: InsightPage()),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 快速切换 weekly → monthly → weekly
    await tester.tap(find.text('月'));
    await tester.pump(const Duration(milliseconds: 100)); // 不等 settle，模拟快速切换
    await tester.tap(find.text('周'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 验证最终显示 weekly 汇总（不应是 monthly 的"这是月报内容"）
    expect(find.textContaining('这是周报内容'), findsOneWidget,
        reason: '最终选中"周"，应显示周报内容');
    expect(find.textContaining('这是月报内容'), findsNothing,
        reason: '旧 monthly _loadExisting 的 setState 不应覆盖新 weekly 状态');
  });
}
