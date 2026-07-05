import 'dart:async';

import 'package:drift/native.dart';
import 'package:eatwise/core/widgets/m3_widgets.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/insight/insight_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 InsightPage 周/月切换的 loading 状态 + AnimatedSwitcher 过渡（M24 Task A6）。
///
/// 用 Completer 控制 databaseProvider 完成时机，模拟慢查询以捕获 LoadingState 中间态。
/// 这是因为 _loadExisting 是 async，in-memory db 太快，不加 Completer 的话 loading
/// 状态在 pump 一帧内就结束了，无法断言。
void main() {
  testWidgets('切换周期时显示 LoadingState', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // 用 Completer 模拟慢查询：_loadExisting 内部 await databaseProvider.future 会挂起
    final dbCompleter = Completer<EatWiseDatabase>();
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) => dbCompleter.future),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: InsightPage()),
    ));
    await tester.pump(); // 首帧渲染：AppBar + SegmentedButton（_loadExisting 挂起）

    // 切换到月视图：触发 onSelectionChanged → setState(_chartLoading=true)
    await tester.tap(find.text('月'));
    await tester.pump(); // 重建一帧，_chartLoading=true 应显示 LoadingState

    // 断言：切换瞬间 LoadingState 出现
    // （_loadExisting 因 db Completer 未完成而挂起，_chartLoading 保持 true）
    expect(find.byType(LoadingState), findsWidgets);
  });

  testWidgets('加载完成后 AnimatedSwitcher 过渡', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // 先插 food_item（meal_log.foodItemId 是非空外键，硬约束 2）
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

    // 种子近 30 天内 meal_log（今天 + 昨天，确保切换到月视图后有 >=2 天数据让图表渲染）
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    await db.into(db.mealLogs).insert(MealLogsCompanion.insert(
          date: fmt(now),
          mealType: 'lunch',
          foodItemId: foodId,
          actualServingG: 200,
          actualCalories: 500,
          actualProteinG: 30,
          actualFatG: 20,
          actualCarbsG: 50,
          loggedAt: 1000,
        ));
    await db.into(db.mealLogs).insert(MealLogsCompanion.insert(
          date: fmt(now.subtract(const Duration(days: 1))),
          mealType: 'lunch',
          foodItemId: foodId,
          actualServingG: 180,
          actualCalories: 450,
          actualProteinG: 27,
          actualFatG: 18,
          actualCarbsG: 45,
          loggedAt: 2000,
        ));

    // 用 Completer 模拟慢查询
    final dbCompleter = Completer<EatWiseDatabase>();
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) => dbCompleter.future),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: InsightPage()),
    ));
    await tester.pump();

    // 切换到月视图：触发 LoadingState
    await tester.tap(find.text('月'));
    await tester.pump();
    expect(find.byType(LoadingState), findsWidgets);

    // 完成 db future：_loadExisting 推进到 finally，_chartLoading=false
    dbCompleter.complete(db);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 断言：LoadingState 消失
    expect(find.byType(LoadingState), findsNothing);
    // 断言：图表重新显示（热量折线图渲染，fl_chart LineChart）
    expect(find.byType(LineChart), findsWidgets);
    // 断言：用了 AnimatedSwitcher 做过渡
    expect(find.byType(AnimatedSwitcher), findsWidgets);
  });
}
