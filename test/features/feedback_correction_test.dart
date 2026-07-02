import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/recognition_feedback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late RecognitionFeedbackRepository repo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    repo = RecognitionFeedbackRepository(db);
    // 种子 food_item + meal_log
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '米饭', defaultServingG: 100, caloriesPer100g: 116,
          proteinPer100g: 2.6, fatPer100g: 0.3, carbsPer100g: 25.9,
          source: 'manual', sourceVersion: 'test', createdAt: 1000));
    await db.into(db.mealLogs).insert(MealLogsCompanion.insert(
          date: '2026-07-02', mealType: 'lunch', foodItemId: 1,
          actualServingG: 100, actualCalories: 116, actualProteinG: 2.6,
          actualFatG: 0.3, actualCarbsG: 25.9, loggedAt: 1000));
  });
  tearDown(() async => db.close());

  test('T45：反馈含 correctedDishName/ServingG 写入成功', () async {
    await repo.insert(
      mealLogId: 1,
      isCorrect: false,
      correctedDishName: '面条',
      correctedServingG: 150.0,
      promptVersion: 'v1.0',
    );
    final has = await repo.hasFeedback(1);
    expect(has, isTrue);
    // 验证字段写入（需加查询方法或直接查表）
    final rows = await db.select(db.recognitionFeedbacks).get();
    expect(rows.length, 1);
    expect(rows.first.correctedDishName, '面条');
    expect(rows.first.correctedServingG, 150.0);
  });

  test('T45：准的反馈不传 correctedDishName/ServingG（null）', () async {
    await repo.insert(
      mealLogId: 1,
      isCorrect: true,
      promptVersion: 'v1.0',
    );
    final rows = await db.select(db.recognitionFeedbacks).get();
    expect(rows.first.correctedDishName, isNull);
    expect(rows.first.correctedServingG, isNull);
  });
}
