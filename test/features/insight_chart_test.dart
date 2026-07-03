import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/insight/insight_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 InsightPage 周热量折线图渲染。
/// meal_log 表 loggedAt 必填，foodItemId 是 FK → 需先插 food_item。
/// 测试种子今天 + 昨天的 meal_log（落在 InsightPage 硬编码的 monday-sunday 本周内）。
void main() {
  testWidgets('周热量折线图渲染', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [recognize.databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);

    // 先插 food_item（meal_log.foodItemId 是 FK）
    final foodId = await db
        .into(db.foodItems)
        .insert(
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

    // 种子本周 meal_log（今天 + 昨天）
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final today = fmt(now);
    // 用 subtract 避免月初 day-1 越界
    final yesterday = fmt(now.subtract(const Duration(days: 1)));

    await db
        .into(db.mealLogs)
        .insert(
          MealLogsCompanion.insert(
            date: today,
            mealType: 'lunch',
            foodItemId: foodId,
            actualServingG: 200,
            actualCalories: 500,
            actualProteinG: 30,
            actualFatG: 20,
            actualCarbsG: 50,
            loggedAt: 1000,
          ),
        );
    await db
        .into(db.mealLogs)
        .insert(
          MealLogsCompanion.insert(
            date: yesterday,
            mealType: 'lunch',
            foodItemId: foodId,
            actualServingG: 180,
            actualCalories: 450,
            actualProteinG: 27,
            actualFatG: 18,
            actualCarbsG: 45,
            loggedAt: 2000,
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InsightPage()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 验证 fl_chart 渲染
    expect(find.byType(LineChart), findsWidgets);
  });
}
