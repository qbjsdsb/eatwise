import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;

  setUp(() {
    db = EatWiseDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('profile 单行初始化', () async {
    final profile = await (db.select(
      db.profiles,
    )..where((p) => p.id.equals(1))).getSingle();
    expect(profile.heightCm, 170);
    expect(profile.gender, 'male');
    expect(profile.tdeeAdjustmentKcal, 0);
  });

  test('food_item 插入与查询', () async {
    final id = await db
        .into(db.foodItems)
        .insert(
          FoodItemsCompanion.insert(
            name: '苹果',
            defaultServingG: 200,
            caloriesPer100g: 52,
            proteinPer100g: 0.3,
            fatPer100g: 0.2,
            carbsPer100g: 14,
            source: 'china_fct',
            sourceVersion: 'test_v1',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    final item = await (db.select(
      db.foodItems,
    )..where((f) => f.id.equals(id))).getSingle();
    expect(item.name, '苹果');
    expect(item.caloriesPer100g, 52);
    expect(item.ediblePercent, isNull);
  });

  test('meal_log 外键关联 food_item', () async {
    final foodId = await db
        .into(db.foodItems)
        .insert(
          FoodItemsCompanion.insert(
            name: '鸡蛋',
            defaultServingG: 60,
            caloriesPer100g: 144,
            proteinPer100g: 13,
            fatPer100g: 9,
            carbsPer100g: 1.1,
            source: 'manual',
            sourceVersion: 'manual',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    final mealId = await db
        .into(db.mealLogs)
        .insert(
          MealLogsCompanion.insert(
            date: '2026-07-01',
            mealType: 'breakfast',
            foodItemId: foodId,
            actualServingG: 60,
            actualCalories: 86.4,
            actualProteinG: 7.8,
            actualFatG: 5.4,
            actualCarbsG: 0.66,
            loggedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    final meal = await (db.select(
      db.mealLogs,
    )..where((m) => m.id.equals(mealId))).getSingle();
    expect(meal.foodItemId, foodId);
    expect(meal.actualCalories, 86.4);
  });

  test('recognition_feedback 级联删除：删除 meal_log 时 feedback 同步删除', () async {
    final foodId = await db
        .into(db.foodItems)
        .insert(
          FoodItemsCompanion.insert(
            name: '测试',
            defaultServingG: 100,
            caloriesPer100g: 100,
            proteinPer100g: 10,
            fatPer100g: 5,
            carbsPer100g: 20,
            source: 'manual',
            sourceVersion: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    final mealId = await db
        .into(db.mealLogs)
        .insert(
          MealLogsCompanion.insert(
            date: '2026-07-01',
            mealType: 'lunch',
            foodItemId: foodId,
            actualServingG: 100,
            actualCalories: 100,
            actualProteinG: 10,
            actualFatG: 5,
            actualCarbsG: 20,
            loggedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    await db
        .into(db.recognitionFeedbacks)
        .insert(
          RecognitionFeedbacksCompanion.insert(
            mealLogId: mealId,
            isCorrect: 0,
            correctedDishName: const Value('正确菜名'),
            promptVersion: 'v1.0',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );

    expect((await db.recognitionFeedbacks.select().get()).length, 1);

    await db.mealLogs.deleteWhere((m) => m.id.equals(mealId));

    expect((await db.recognitionFeedbacks.select().get()).length, 0);
  });
}
