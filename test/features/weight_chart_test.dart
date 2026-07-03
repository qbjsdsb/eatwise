import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:eatwise/features/weight/weight_page.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证体重页加载体重 + 热量数据后渲染双轴图（不崩溃）。
/// weight_log 表只有 date/weightKg（无 loggedAt）；
/// meal_log 表 loggedAt 必填，foodItemId 是 FK → 需先插 food_item。
void main() {
  testWidgets('双轴图渲染（体重+热量）', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

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

    // 种子：2 条体重记录（weight_log 无 loggedAt 字段）
    await db
        .into(db.weightLogs)
        .insert(WeightLogsCompanion.insert(date: '2026-07-01', weightKg: 70.0));
    await db
        .into(db.weightLogs)
        .insert(WeightLogsCompanion.insert(date: '2026-07-02', weightKg: 69.5));

    // 种子：2 条 meal_log（同日期，loggedAt 必填）
    await db
        .into(db.mealLogs)
        .insert(
          MealLogsCompanion.insert(
            date: '2026-07-01',
            mealType: 'lunch',
            foodItemId: foodId,
            actualServingG: 200,
            actualCalories: 500,
            actualProteinG: 30,
            actualFatG: 20,
            actualCarbsG: 50,
            loggedAt: 1500,
          ),
        );
    await db
        .into(db.mealLogs)
        .insert(
          MealLogsCompanion.insert(
            date: '2026-07-02',
            mealType: 'lunch',
            foodItemId: foodId,
            actualServingG: 180,
            actualCalories: 450,
            actualProteinG: 27,
            actualFatG: 18,
            actualCarbsG: 45,
            loggedAt: 2500,
          ),
        );

    final container = ProviderContainer(
      overrides: [recognize.databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WeightPage()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 验证图表渲染（2 条体重记录 ≥ 2 阈值）
    expect(find.byType(LineChart), findsOneWidget);
  });
}
