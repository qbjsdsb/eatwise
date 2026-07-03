import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/data/repositories/recognition_feedback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late MealLogRepository repo;
  late RecognitionFeedbackRepository feedbackRepo;

  setUp(() {
    db = EatWiseDatabase(NativeDatabase.memory());
    repo = MealLogRepository(db);
    feedbackRepo = RecognitionFeedbackRepository(db);
  });

  tearDown(() async => db.close());

  // 插入一条食物 + 一条 meal_log 的辅助
  Future<int> seedFoodAndMeal({
    String date = '2026-07-02',
    String mealType = 'breakfast',
    double serving = 100,
    double calories = 50,
    double protein = 1.0,
    double fat = 0.2,
    double carbs = 13.5,
    double? confidence,
  }) async {
    final foodId = await db
        .into(db.foodItems)
        .insert(
          FoodItemsCompanion.insert(
            name: '测试食物',
            defaultServingG: 100,
            caloriesPer100g: calories,
            proteinPer100g: protein,
            fatPer100g: fat,
            carbsPer100g: carbs,
            source: 'test',
            sourceVersion: 'test_v1',
            createdAt: 0,
          ),
        );
    final mealId = await repo.insertMealLog(
      date: date,
      mealType: mealType,
      foodItemId: foodId,
      actualServingG: serving,
      actualCalories: calories,
      actualProteinG: protein,
      actualFatG: fat,
      actualCarbsG: carbs,
      recognitionConfidence: confidence,
    );
    return mealId;
  }

  test('updateMealLog 更新份量后按比例重算营养素', () async {
    final mealId = await seedFoodAndMeal(
      serving: 100,
      calories: 50,
      protein: 1.0,
      fat: 0.2,
      carbs: 13.5,
    );

    // 改份量为 200g（×2）
    await repo.updateMealLog(
      id: mealId,
      actualServingG: 200,
      actualCalories: 100, // 50 × 2
      actualProteinG: 2.0,
      actualFatG: 0.4,
      actualCarbsG: 27.0,
    );

    final meals = await repo.getMealsByDate('2026-07-02');
    expect(meals.length, 1);
    expect(meals.first.actualServingG, 200);
    expect(meals.first.actualCalories, 100);
    expect(meals.first.actualProteinG, 2.0);
  });

  test('deleteMealLog 后 recognition_feedback 级联删除', () async {
    final mealId = await seedFoodAndMeal(confidence: 0.95);

    // 写一条反馈
    await feedbackRepo.insert(
      mealLogId: mealId,
      isCorrect: true,
      promptVersion: 'v1.0',
    );
    expect(await feedbackRepo.hasFeedback(mealId), true);

    // 删除 meal_log，反馈应级联删除
    await repo.deleteMealLog(mealId);

    final meals = await repo.getMealsByDate('2026-07-02');
    expect(meals.length, 0);
    expect(await feedbackRepo.hasFeedback(mealId), false); // 级联删除
  });

  test('getMacrosByDate 返回四宏量总和', () async {
    await seedFoodAndMeal(
      mealType: 'breakfast',
      calories: 100,
      protein: 5.0,
      fat: 2.0,
      carbs: 20.0,
    );
    await seedFoodAndMeal(
      mealType: 'lunch',
      calories: 200,
      protein: 10.0,
      fat: 5.0,
      carbs: 30.0,
    );

    final macros = await repo.getMacrosByDate('2026-07-02');
    expect(macros.calories, 300);
    expect(macros.protein, 15.0);
    expect(macros.fat, 7.0);
    expect(macros.carbs, 50.0);
  });

  test('getRange 按日期区间+时间排序', () async {
    // 插入 3 天数据
    await seedFoodAndMeal(date: '2026-07-01', mealType: 'breakfast');
    await seedFoodAndMeal(date: '2026-07-02', mealType: 'lunch');
    await seedFoodAndMeal(date: '2026-07-03', mealType: 'dinner');

    // 查区间 07-01 ~ 07-02（含两端）
    final meals = await repo.getRange('2026-07-01', '2026-07-02');
    expect(meals.length, 2);
    // 按日期升序
    expect(meals.first.date, '2026-07-01');
    expect(meals.last.date, '2026-07-02');
  });
}
