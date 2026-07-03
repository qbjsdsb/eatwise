import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/dashboard/today_meals_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证今日记录列表项显示食物名而非 ID
/// databaseProvider override 为内存 DB（绕过 path_provider 平台插件）
void main() {
  testWidgets('列表项显示食物名', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // 种子数据：插入食物 + 今日 meal_log
    final foodId = await db
        .into(db.foodItems)
        .insert(
          FoodItemsCompanion.insert(
            name: '宫保鸡丁',
            defaultServingG: 100,
            caloriesPer100g: 200,
            proteinPer100g: 15,
            fatPer100g: 10,
            carbsPer100g: 8,
            source: 'manual',
            sourceVersion: 'test',
            createdAt: 1000,
          ),
        );
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await db
        .into(db.mealLogs)
        .insert(
          MealLogsCompanion.insert(
            date: today,
            mealType: 'lunch',
            foodItemId: foodId,
            actualServingG: 150,
            actualCalories: 300,
            actualProteinG: 22.5,
            actualFatG: 15,
            actualCarbsG: 12,
            loggedAt: 2000,
          ),
        );

    final container = ProviderContainer(
      overrides: [recognize.databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TodayMealsPage()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 验证显示食物名"宫保鸡丁"，不显示"食物ID"
    expect(find.text('宫保鸡丁'), findsOneWidget);
    expect(find.textContaining('食物ID'), findsNothing);
  });
}
