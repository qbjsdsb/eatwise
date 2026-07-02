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
    for (var i = 1; i <= 5; i++) {
      await db.into(db.mealLogs).insert(MealLogsCompanion.insert(
            date: '2026-07-0$i', mealType: 'lunch', foodItemId: 1,
            actualServingG: 100, actualCalories: 116, actualProteinG: 2.6,
            actualFatG: 0.3, actualCarbsG: 25.9, loggedAt: i * 1000));
    }
  });
  tearDown(() async => db.close());

  test('T46：按 prompt_version 聚合准确率', () async {
    // v1.0：3 准 2 不准 → 准确率 0.6
    await repo.insert(mealLogId: 1, isCorrect: true, promptVersion: 'v1.0');
    await repo.insert(mealLogId: 2, isCorrect: true, promptVersion: 'v1.0');
    await repo.insert(mealLogId: 3, isCorrect: true, promptVersion: 'v1.0');
    await repo.insert(mealLogId: 4, isCorrect: false, promptVersion: 'v1.0');
    await repo.insert(mealLogId: 5, isCorrect: false, promptVersion: 'v1.0');

    final accuracy = await repo.getAccuracyByPromptVersion();
    expect(accuracy['v1.0']!['total'], 5);
    expect(accuracy['v1.0']!['correct'], 3);
    expect(accuracy['v1.0']!['accuracy'], 0.6);
  });

  test('T46：不同 prompt_version 独立聚合', () async {
    await repo.insert(mealLogId: 1, isCorrect: true, promptVersion: 'v1.0');
    await repo.insert(mealLogId: 2, isCorrect: false, promptVersion: 'v1.1');

    final accuracy = await repo.getAccuracyByPromptVersion();
    expect(accuracy['v1.0']!['accuracy'], 1.0);
    expect(accuracy['v1.1']!['accuracy'], 0.0);
  });

  test('T46：查询错判样本含 correctedDishName', () async {
    await repo.insert(mealLogId: 1, isCorrect: false, correctedDishName: '面条',
        correctedServingG: 150.0, promptVersion: 'v1.0');
    await repo.insert(mealLogId: 2, isCorrect: true, promptVersion: 'v1.0');

    final samples = await repo.getWrongSamples('v1.0');
    expect(samples.length, 1);
    expect(samples.first.mealLogId, 1);
    expect(samples.first.correctedDishName, '面条');
    expect(samples.first.correctedServingG, 150.0);
  });
}
