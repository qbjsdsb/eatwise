import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/core/util/date_format.dart';
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
    final foodId = await db.into(db.foodItems).insert(
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

  // ===== 编辑能力扩展测试（P0 第一批：date/mealType/foodItemId + 部分更新）=====

  group('updateMealLog 扩展字段（date/mealType/foodItemId）', () {
    test('只改 date，其他字段保持原值', () async {
      final mealId = await seedFoodAndMeal(
        date: '2026-07-02',
        serving: 100,
        calories: 50,
        protein: 1.0,
        fat: 0.2,
        carbs: 13.5,
      );

      await repo.updateMealLog(id: mealId, date: '2026-07-05');

      // 原日期应查不到
      expect((await repo.getMealsByDate('2026-07-02')).length, 0);
      // 新日期能查到，且其他字段未变
      final meals = await repo.getMealsByDate('2026-07-05');
      expect(meals.length, 1);
      expect(meals.first.actualServingG, 100);
      expect(meals.first.actualCalories, 50);
      expect(meals.first.actualProteinG, 1.0);
      expect(meals.first.mealType, 'breakfast');
    });

    test('只改 mealType，其他字段保持原值', () async {
      final mealId = await seedFoodAndMeal(
        mealType: 'breakfast',
        serving: 150,
        calories: 75,
      );

      await repo.updateMealLog(id: mealId, mealType: 'lunch');

      final meals = await repo.getMealsByDate('2026-07-02');
      expect(meals.length, 1);
      expect(meals.first.mealType, 'lunch');
      // 份量/热量不应被改动
      expect(meals.first.actualServingG, 150);
      expect(meals.first.actualCalories, 75);
    });

    test('换食物 foodItemId，份量/营养保持原值（UI 层负责重算）', () async {
      final mealId = await seedFoodAndMeal(
        serving: 200,
        calories: 100,
        protein: 5.0,
      );
      // 新建另一个食物用于替换
      final newFoodId = await db.into(db.foodItems).insert(
            FoodItemsCompanion.insert(
              name: '替换食物',
              defaultServingG: 100,
              caloriesPer100g: 80,
              proteinPer100g: 4.0,
              fatPer100g: 0.5,
              carbsPer100g: 18.0,
              source: 'test',
              sourceVersion: 'v1',
              createdAt: 0,
            ),
          );

      await repo.updateMealLog(id: mealId, foodItemId: newFoodId);

      final meals = await repo.getMealsByDate('2026-07-02');
      expect(meals.length, 1);
      expect(meals.first.foodItemId, newFoodId);
      // 份量/营养未传 → 保留原值（UI 层换食物后会调重算，repo 只负责持久化）
      expect(meals.first.actualServingG, 200);
      expect(meals.first.actualCalories, 100);
      expect(meals.first.actualProteinG, 5.0);
    });

    test('同时改 date + mealType + 份量 + 营养（全字段）', () async {
      final mealId = await seedFoodAndMeal(
        date: '2026-07-02',
        mealType: 'breakfast',
        serving: 100,
        calories: 50,
        protein: 1.0,
        fat: 0.2,
        carbs: 13.5,
      );

      await repo.updateMealLog(
        id: mealId,
        date: '2026-07-05',
        mealType: 'dinner',
        actualServingG: 250,
        actualCalories: 125,
        actualProteinG: 2.5,
        actualFatG: 0.5,
        actualCarbsG: 33.75,
      );

      final meals = await repo.getMealsByDate('2026-07-05');
      expect(meals.length, 1);
      expect(meals.first.mealType, 'dinner');
      expect(meals.first.actualServingG, 250);
      expect(meals.first.actualCalories, 125);
      expect(meals.first.actualProteinG, 2.5);
      expect(meals.first.actualFatG, 0.5);
      expect(meals.first.actualCarbsG, 33.75);
    });

    test('什么都不传 → 不修改任何字段', () async {
      final mealId = await seedFoodAndMeal(
        serving: 100,
        calories: 50,
        protein: 1.0,
        fat: 0.2,
        carbs: 13.5,
      );

      await repo.updateMealLog(id: mealId);

      final meals = await repo.getMealsByDate('2026-07-02');
      expect(meals.length, 1);
      expect(meals.first.actualServingG, 100);
      expect(meals.first.actualCalories, 50);
      expect(meals.first.mealType, 'breakfast');
    });
  });

  group('updateMealLog 哨兵防御（foodItemId<=0 拒绝写入）', () {
    test('foodItemId=0 抛 ArgumentError', () async {
      final mealId = await seedFoodAndMeal();
      expect(
        () => repo.updateMealLog(id: mealId, foodItemId: 0),
        throwsArgumentError,
      );
    });

    test('foodItemId=-1 抛 ArgumentError', () async {
      final mealId = await seedFoodAndMeal();
      expect(
        () => repo.updateMealLog(id: mealId, foodItemId: -1),
        throwsArgumentError,
      );
    });

    test('foodItemId=null（不传）→ 不触发校验，正常执行', () async {
      final mealId = await seedFoodAndMeal();
      // 只改份量，不传 foodItemId，不应抛错
      await repo.updateMealLog(id: mealId, actualServingG: 200);
      final meals = await repo.getMealsByDate('2026-07-02');
      expect(meals.first.actualServingG, 200);
    });

    test('抛错后记录未被修改（事务回滚 / 提前抛错）', () async {
      final mealId = await seedFoodAndMeal(serving: 100, calories: 50);
      // 抛错
      try {
        await repo.updateMealLog(id: mealId, foodItemId: 0);
      } catch (_) {}
      // 记录应保持原值
      final meals = await repo.getMealsByDate('2026-07-02');
      expect(meals.length, 1);
      expect(meals.first.actualServingG, 100);
      expect(meals.first.actualCalories, 50);
    });
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

  group('getMedianServing 历史份量中位数（B 智能份量校准）', () {
    test('无历史记录 → 返回 null', () async {
      final foodId = await seedFoodAndMeal(); // 插了 1 条，但下面查另一个 foodId
      final otherFoodId = foodId + 999; // 不存在的 foodItemId
      expect(await repo.getMedianServing(otherFoodId), isNull);
    });

    test('单条记录 → 返回该条份量', () async {
      await seedFoodAndMeal(serving: 150);
      // seedFoodAndMeal 每次插新食物，取最后插入的 foodId
      final foods = await db.foodItems.select().get();
      final lastFoodId = foods.last.id;
      expect(await repo.getMedianServing(lastFoodId), 150);
    });

    test('同 foodId 多条记录 → 返回中位数（奇数）', () async {
      // 直接插一个食物，再插多条 meal_log 关联同 foodId
      final foodId = await db.into(db.foodItems).insert(
            FoodItemsCompanion.insert(
              name: '测试食物X',
              defaultServingG: 100,
              caloriesPer100g: 50,
              proteinPer100g: 1,
              fatPer100g: 0.2,
              carbsPer100g: 13.5,
              source: 'test',
              sourceVersion: 'v1',
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      // 插 3 条 meal_log，份量 100/300/200 → 中位数 200
      for (final s in [100.0, 300.0, 200.0]) {
        await repo.insertMealLog(
          date: '2026-07-02',
          mealType: 'breakfast',
          foodItemId: foodId,
          actualServingG: s,
          actualCalories: 50 * s / 100,
          actualProteinG: 1 * s / 100,
          actualFatG: 0.2 * s / 100,
          actualCarbsG: 13.5 * s / 100,
        );
      }
      expect(await repo.getMedianServing(foodId), 200);
    });

    test('同 foodId 多条记录 → 返回中位数（偶数取中间两值平均）', () async {
      final foodId = await db.into(db.foodItems).insert(
            FoodItemsCompanion.insert(
              name: '测试食物Y',
              defaultServingG: 100,
              caloriesPer100g: 50,
              proteinPer100g: 1,
              fatPer100g: 0.2,
              carbsPer100g: 13.5,
              source: 'test',
              sourceVersion: 'v1',
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      // 插 4 条：100/200/300/400 → 中位数 (200+300)/2 = 250
      for (final s in [100.0, 400.0, 200.0, 300.0]) {
        await repo.insertMealLog(
          date: '2026-07-02',
          mealType: 'breakfast',
          foodItemId: foodId,
          actualServingG: s,
          actualCalories: 50 * s / 100,
          actualProteinG: 1 * s / 100,
          actualFatG: 0.2 * s / 100,
          actualCarbsG: 13.5 * s / 100,
        );
      }
      expect(await repo.getMedianServing(foodId), 250);
    });

    test('超过 20 条 → 只取最近 20 条（按时间倒序）', () async {
      final foodId = await db.into(db.foodItems).insert(
            FoodItemsCompanion.insert(
              name: '测试食物Z',
              defaultServingG: 100,
              caloriesPer100g: 50,
              proteinPer100g: 1,
              fatPer100g: 0.2,
              carbsPer100g: 13.5,
              source: 'test',
              sourceVersion: 'v1',
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      // 插 25 条，份量递增 100,200,...,2500
      // 最近 20 条是 600,700,...,2500（按 loggedAt 倒序取前 20）
      // loggedAt 用 DateTime.now().millisecondsSinceEpoch，同毫秒可能乱序，
      // 加 sleep 保证 loggedAt 递增（每条 +1ms）
      for (var i = 1; i <= 25; i++) {
        await repo.insertMealLog(
          date: '2026-07-02',
          mealType: 'breakfast',
          foodItemId: foodId,
          actualServingG: (i * 100).toDouble(),
          actualCalories: 50.0,
          actualProteinG: 1.0,
          actualFatG: 0.2,
          actualCarbsG: 13.5,
        );
        await Future.delayed(const Duration(milliseconds: 2));
      }
      // 最近 20 条份量：600,700,...,2500（共 20 个），中位数 = (600+2500)/2 到 (1500+1600)/2
      // 实际：第 6 到第 25 条（索引 5..24），份量 600..2500，中位数 = (600+2500)/2 到 (1500+1600)/2
      // 偶数 20 条，中位数 = (第10+第11)/2 = (1500+1600)/2 = 1550
      expect(await repo.getMedianServing(foodId), 1550);
    });
  });

  // 哨兵防御测试（HANDOFF 硬约束 2：foodItemId=0 是哨兵，写库前必须替换为真实 id）
  group('哨兵防御（foodItemId=0 拒绝写入）', () {
    test('foodItemId=0 抛 ArgumentError（防外键约束违规崩溃）', () {
      expect(
        () => repo.insertMealLog(
          date: '2026-07-02',
          mealType: 'breakfast',
          foodItemId: 0, // 哨兵值
          actualServingG: 100,
          actualCalories: 50,
          actualProteinG: 1.0,
          actualFatG: 0.2,
          actualCarbsG: 13.5,
        ),
        throwsArgumentError,
      );
    });

    test('foodItemId=-1 抛 ArgumentError（负值同样拒绝）', () {
      expect(
        () => repo.insertMealLog(
          date: '2026-07-02',
          mealType: 'breakfast',
          foodItemId: -1,
          actualServingG: 100,
          actualCalories: 50,
          actualProteinG: 1.0,
          actualFatG: 0.2,
          actualCarbsG: 13.5,
        ),
        throwsArgumentError,
      );
    });

    test('foodItemId=1（真实 id）正常写入', () async {
      // 先插入一条食物拿到真实 id
      final foodId = await db.into(db.foodItems).insert(
            FoodItemsCompanion.insert(
              name: '苹果',
              defaultServingG: 100,
              caloriesPer100g: 52,
              proteinPer100g: 0.3,
              fatPer100g: 0.2,
              carbsPer100g: 13.8,
              source: 'manual',
              sourceVersion: 'test',
              createdAt: 0,
            ),
          );
      await repo.insertMealLog(
        date: '2026-07-02',
        mealType: 'breakfast',
        foodItemId: foodId,
        actualServingG: 100,
        actualCalories: 52,
        actualProteinG: 0.3,
        actualFatG: 0.2,
        actualCarbsG: 13.8,
      );
      final meals = await repo.getMealsByDate('2026-07-02');
      expect(meals.length, 1);
      expect(meals.first.foodItemId, foodId);
    });
  });

  // H4 修复：getRecentMeals/getRecentFoodCounts/getMealTypeDistribution 无 endDate 上界
  // 用户预录未来餐次会污染推荐统计，应只统计 startDate..today 区间
  group('H4 recent 方法加 endDate 上界', () {
    test('getRecentMeals 不返回未来日期记录', () async {
      final today = formatYmd(DateTime.now());
      final tomorrow = formatYmd(DateTime.now().add(const Duration(days: 1)));
      // 今天记录
      final todayFoodId = await db.into(db.foodItems).insert(
            FoodItemsCompanion.insert(
              name: '今天食物',
              defaultServingG: 100,
              caloriesPer100g: 50,
              proteinPer100g: 1,
              fatPer100g: 0.2,
              carbsPer100g: 13.5,
              source: 'test',
              sourceVersion: 'test_v1',
              createdAt: 0,
            ),
          );
      await repo.insertMealLog(
        date: today,
        mealType: 'breakfast',
        foodItemId: todayFoodId,
        actualServingG: 100,
        actualCalories: 50,
        actualProteinG: 1,
        actualFatG: 0.2,
        actualCarbsG: 13.5,
      );
      // 明天（未来）记录
      final futureFoodId = await db.into(db.foodItems).insert(
            FoodItemsCompanion.insert(
              name: '未来食物',
              defaultServingG: 100,
              caloriesPer100g: 999,
              proteinPer100g: 99,
              fatPer100g: 99,
              carbsPer100g: 99,
              source: 'test',
              sourceVersion: 'test_v1',
              createdAt: 0,
            ),
          );
      await repo.insertMealLog(
        date: tomorrow,
        mealType: 'breakfast',
        foodItemId: futureFoodId,
        actualServingG: 100,
        actualCalories: 999,
        actualProteinG: 99,
        actualFatG: 99,
        actualCarbsG: 99,
      );

      final recent = await repo.getRecentMeals(days: 7);
      // 未来日期不应出现
      expect(recent.any((m) => m.date == tomorrow), false,
          reason: '未来日期不应计入 recent 统计');
      expect(recent.any((m) => m.date == today), true,
          reason: '今天记录应出现');
    });

    test('getRecentFoodCounts 不统计未来日期', () async {
      final tomorrow = formatYmd(DateTime.now().add(const Duration(days: 1)));
      final futureFoodId = await db.into(db.foodItems).insert(
            FoodItemsCompanion.insert(
              name: '未来食物2',
              defaultServingG: 100,
              caloriesPer100g: 100,
              proteinPer100g: 1,
              fatPer100g: 1,
              carbsPer100g: 1,
              source: 'test',
              sourceVersion: 'test_v1',
              createdAt: 0,
            ),
          );
      await repo.insertMealLog(
        date: tomorrow,
        mealType: 'breakfast',
        foodItemId: futureFoodId,
        actualServingG: 100,
        actualCalories: 100,
        actualProteinG: 1,
        actualFatG: 1,
        actualCarbsG: 1,
      );
      final counts = await repo.getRecentFoodCounts(days: 7);
      expect(counts[futureFoodId], isNull,
          reason: '未来日期的 foodItemCount 不应被统计');
    });
  });
}
