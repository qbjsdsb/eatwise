import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/insight/insight_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 问题2 增强 UI 渲染测试：验证新增的统计卡片/餐次环图/三宏柱图/偏好食物/周环比
/// 能在 InsightPage 中正确渲染。
///
/// 种子策略：
/// - 插 1 个 food_item（meal_log.foodItemId 是 FK）
/// - 插 3 天 meal_log（今天 + 昨天 + 前天），每天含 4 种 mealType（早/午/晚/加餐）
/// - 让餐次分布环图、三宏柱图、统计卡片、偏好食物列表都能渲染
///
/// 滚动策略：InsightPage body 是 ListView，新增组件在热量/体重折线图之后，
/// 需用 scrollUntilVisible 滚动到对应组件才渲染（ListView 只渲染 viewport 内 widget）。
void main() {
  late EatWiseDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    // 先插 food_item（meal_log.foodItemId 是 FK）
    final foodId = await db.into(db.foodItems).insert(
          FoodItemsCompanion.insert(
            name: '测试食物',
            defaultServingG: 100,
            caloriesPer100g: 250,
            proteinPer100g: 15,
            fatPer100g: 10,
            carbsPer100g: 25,
            source: 'manual',
            sourceVersion: 'test',
            createdAt: 1000,
          ),
        );
    // 种子 3 天 meal_log，每天 4 种 mealType
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    for (var d = 0; d < 3; d++) {
      final date = fmt(now.subtract(Duration(days: d)));
      for (final mealType in ['breakfast', 'lunch', 'dinner', 'snack']) {
        await db.into(db.mealLogs).insert(MealLogsCompanion.insert(
              date: date,
              mealType: mealType,
              foodItemId: foodId,
              actualServingG: 100,
              actualCalories: 250,
              actualProteinG: 15,
              actualFatG: 10,
              actualCarbsG: 25,
              loggedAt: 1000 + d * 100,
            ));
      }
    }
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pumpInsightPage(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: InsightPage()),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  testWidgets('周报：统计卡片渲染（连续记录/平均超额/目标达成/体重变化）',
      (tester) async {
    await pumpInsightPage(tester);
    // 滚动到"周期概览"（在热量/体重折线图之后）
    await tester.scrollUntilVisible(find.text('周期概览'), 200);
    expect(find.text('周期概览'), findsOneWidget);
    expect(find.text('连续记录'), findsOneWidget);
    expect(find.text('平均 kcal/天'), findsOneWidget);
    expect(find.text('目标达成'), findsOneWidget);
    // 体重变化 tile：无体重数据时 label 是"体重变化(kg)"
    expect(find.text('体重变化(kg)'), findsOneWidget);
    // 连续记录至少 3 天（种子了 3 天）
    expect(find.text('3 天'), findsOneWidget);
  });

  testWidgets('周报：餐次分布环图渲染（PieChart）', (tester) async {
    await pumpInsightPage(tester);
    await tester.scrollUntilVisible(find.text('餐次分布'), 200);
    expect(find.text('餐次分布'), findsOneWidget);
    expect(find.byType(PieChart), findsOneWidget);
    // 种子了 4 种 mealType，应显示 4 个 badge（早/午/晚/加餐 各 750kcal）
    expect(find.textContaining('早餐'), findsOneWidget);
    expect(find.textContaining('午餐'), findsOneWidget);
    expect(find.textContaining('晚餐'), findsOneWidget);
    expect(find.textContaining('加餐'), findsOneWidget);
    // 总摄入 3000 kcal（3 天 * 4 餐 * 250kcal）
    expect(find.textContaining('总摄入 3000 kcal'), findsOneWidget);
  });

  testWidgets('周报：三宏达成率柱图渲染（BarChart）', (tester) async {
    await pumpInsightPage(tester);
    await tester.scrollUntilVisible(find.text('三宏达成率'), 200);
    expect(find.text('三宏达成率'), findsOneWidget);
    // 验证 BarChart 渲染（周环比也会用 BarChart，所以 findsWidgets）
    expect(find.byType(BarChart), findsWidgets);
    // 副标题"实色=记录日均值，半透明=目标值"
    expect(find.text('实色=记录日均值，半透明=目标值'), findsOneWidget);
  });

  testWidgets('周报：偏好食物 Top5 列表渲染', (tester) async {
    await pumpInsightPage(tester);
    await tester.scrollUntilVisible(find.text('常吃食物 Top 1'), 200);
    expect(find.text('常吃食物 Top 1'), findsOneWidget);
    // 种子只有 1 种食物，排名徽章"1"
    expect(find.text('1'), findsOneWidget);
    // 食物名
    expect(find.text('测试食物'), findsOneWidget);
    // 频次（3 天 * 4 餐 = 12 次）
    expect(find.text('12 次'), findsOneWidget);
  });

  testWidgets('周报：无周环比卡片（仅月报显示）', (tester) async {
    await pumpInsightPage(tester);
    // 滚动到底部确保看到所有组件
    await tester.scrollUntilVisible(find.byType(FilledButton), 200);
    // 周报不应显示"周环比"标题
    expect(find.text('周环比'), findsNothing);
  });

  testWidgets('月报：切换到月报后周环比卡片渲染', (tester) async {
    await pumpInsightPage(tester);
    // 点击 SegmentedButton 的"月"
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // 滚动到"周环比"
    await tester.scrollUntilVisible(find.text('周环比'), 200);
    expect(find.text('周环比'), findsOneWidget);
    // 副标题
    expect(find.textContaining('每周日均热量'), findsOneWidget);
  });

  testWidgets('月报：切换后统计卡片仍渲染', (tester) async {
    await pumpInsightPage(tester);
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.scrollUntilVisible(find.text('周期概览'), 200);
    expect(find.text('周期概览'), findsOneWidget);
    expect(find.text('连续记录'), findsOneWidget);
  });
}
