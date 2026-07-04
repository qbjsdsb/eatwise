// test/features/image_cleanup_startup_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/core/util/date_format.dart';
import 'package:eatwise/data/backup/image_cleanup.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 测 ImageCleanup.runIfBacklogLarge 逻辑（不测 main.dart 启动集成，main 难单测）
  late EatWiseDatabase db;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    // 【第2轮修正】：meal_log.food_item_id 是 FK，先种子 food_item（id=1）
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '测试食物', defaultServingG: 100, caloriesPer100g: 100,
          proteinPer100g: 10, fatPer100g: 5, carbsPer100g: 20,
          source: 'manual', sourceVersion: 'test', createdAt: 1000));
  });
  tearDown(() async => db.close());

  // 【第2轮修正·重要】：日期必须用 5 月（2026-05-xx），不能用 6 月！
  // 原因：getOldImagePaths(30) 的 cutoff = now(2026-07-02) - 30 天 = 2026-06-02，
  //   where date < '2026-06-02'。6 月只有 30 天，原计划 '2026-06-31'..'2026-06-51' 无效，
  //   且 6 月仅 '2026-06-01' 1 项命中 cutoff，51 项只 1 项被 getOldImagePaths 返回，
  //   candidates.length=1 不 > 50 → 不触发清理，但测试期望"全部置空"→ 断言失败。
  // 改用 5 月：所有 '2026-05-xx' < '2026-06-02' 全命中（字符串比较 '5' < '6'），
  //   51 项全命中 → candidates.length=51 > 50 → 触发清理 → 全部置空 ✓
  //   （'2026-05-32'..'2026-05-51' 虽非真实日期，但 date 是 text 字段可存，字符串比较仍 < '2026-06-02'）

  test('T47：积压 ≤50 项不触发清理', () async {
    final mealRepo = MealLogRepository(db);
    for (var i = 0; i < 50; i++) {
      await mealRepo.insertMealLog(
        date: '2026-05-${(i + 1).toString().padLeft(2, '0')}',
        mealType: 'lunch', foodItemId: 1,
        actualServingG: 100, actualCalories: 100, actualProteinG: 10,
        actualFatG: 5, actualCarbsG: 20,
        originalImagePath: '/tmp/nonexistent_$i.jpg',
      );
    }
    // runIfBacklogLarge 不应触发 run（50 不 > 50）
    await ImageCleanup.runIfBacklogLarge(db);
    final meals = await db.select(db.mealLogs).get();
    expect(meals.where((m) => m.originalImagePath != null).length, 50);
  });

  test('T47：积压 >50 项触发清理', () async {
    final mealRepo = MealLogRepository(db);
    for (var i = 0; i < 51; i++) {
      await mealRepo.insertMealLog(
        date: '2026-05-${(i + 1).toString().padLeft(2, '0')}',
        mealType: 'lunch', foodItemId: 1,
        actualServingG: 100, actualCalories: 100, actualProteinG: 10,
        actualFatG: 5, actualCarbsG: 20,
        originalImagePath: '/tmp/nonexistent_$i.jpg',
      );
    }
    await ImageCleanup.runIfBacklogLarge(db);
    // 验证路径被清除（清理后 originalImagePath 置空）
    final meals = await db.select(db.mealLogs).get();
    expect(meals.where((m) => m.originalImagePath != null).length, 0);
  });

  // T48：自定义保留期 7 天
  // 用相对日期（基于 DateTime.now()）避免硬编码日期随时间失效。
  // retentionDays=7 → cutoff = today - 7
  // 8 天前 < cutoff → 清；6 天前 >= cutoff → 留
  test('T48：自定义保留期 7 天（8 天前清，6 天前留）', () async {
    final mealRepo = MealLogRepository(db);
    final now = DateTime.now();
    final oldDate = formatYmd(now.subtract(const Duration(days: 8))); // 8 天前
    final recentDate = formatYmd(now.subtract(const Duration(days: 6))); // 6 天前
    await mealRepo.insertMealLog(
      date: oldDate, // 8 天前
      mealType: 'lunch', foodItemId: 1,
      actualServingG: 100, actualCalories: 100, actualProteinG: 10,
      actualFatG: 5, actualCarbsG: 20,
      originalImagePath: '/tmp/nonexistent_old.jpg',
    );
    await mealRepo.insertMealLog(
      date: recentDate, // 6 天前
      mealType: 'lunch', foodItemId: 1,
      actualServingG: 100, actualCalories: 100, actualProteinG: 10,
      actualFatG: 5, actualCarbsG: 20,
      originalImagePath: '/tmp/nonexistent_recent.jpg',
    );

    await ImageCleanup.run(db, retentionDays: 7);

    final meals = await db.select(db.mealLogs).get();
    final oldMeal = meals.firstWhere((m) => m.date == oldDate);
    final recentMeal = meals.firstWhere((m) => m.date == recentDate);
    // 8 天前的被清理（路径置空）
    expect(oldMeal.originalImagePath, isNull);
    // 6 天前的保留
    expect(recentMeal.originalImagePath, '/tmp/nonexistent_recent.jpg');
  });

  // T48：保留期 0（永久保留）不清理
  test('T48：保留期 0（永久保留）不清理', () async {
    final mealRepo = MealLogRepository(db);
    // 种子 60 天前的数据（默认 30 天会清理，但 retentionDays=0 应跳过）
    for (var i = 0; i < 5; i++) {
      await mealRepo.insertMealLog(
        date: '2026-05-${(i + 1).toString().padLeft(2, '0')}',
        mealType: 'lunch', foodItemId: 1,
        actualServingG: 100, actualCalories: 100, actualProteinG: 10,
        actualFatG: 5, actualCarbsG: 20,
        originalImagePath: '/tmp/nonexistent_keep_$i.jpg',
      );
    }

    final deleted = await ImageCleanup.run(db, retentionDays: 0);
    // 永久保留：返回 0，不清理
    expect(deleted, 0);
    final meals = await db.select(db.mealLogs).get();
    expect(meals.where((m) => m.originalImagePath != null).length, 5);
  });
}
