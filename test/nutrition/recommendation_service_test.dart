import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/nutrition/recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;
  late MealLogRepository mealRepo;
  late ProfileRepository profileRepo;
  late RecommendationService service;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory(), seedOnCreate: false);
    foodRepo = FoodItemRepository(db);
    mealRepo = MealLogRepository(db);
    profileRepo = ProfileRepository(db);
    service = RecommendationService(foodRepo, mealRepo, profileRepo);

    // 预置 profile（默认 wasCreated 已插 id=1，目标 2000kcal，蛋白 98g）
    // 预置食物库：高蛋白/低蛋白/高热量/低热量各一条
    await _seedFood(db, name: '鸡胸肉', cal: 165, protein: 31, fat: 3.6, carbs: 0);
    await _seedFood(db, name: '鸡蛋', cal: 144, protein: 13, fat: 9, carbs: 1.1);
    await _seedFood(db, name: '可乐', cal: 42, protein: 0, fat: 0, carbs: 10.6);
    await _seedFood(db, name: '薯片', cal: 547, protein: 6, fat: 35, carbs: 53);
    await _seedFood(db, name: '白菜', cal: 17, protein: 1.5, fat: 0.1, carbs: 3.2);
    await _seedFood(db, name: '米饭', cal: 116, protein: 2.6, fat: 0.3, carbs: 25.9);
  });

  tearDown(() async => db.close());

  group('getDailyRemaining 当日剩余额度', () {
    test('无记录 → 剩余=目标', () async {
      final r = await service.getDailyRemaining('2026-07-02');
      expect(r.remainingCalories, 2000); // 目标 2000，已记录 0
      expect(r.remainingProtein, closeTo(98, 0.1)); // 1.4*70
      expect(r.consumedCalories, 0);
    });

    test('有记录 → 剩余=目标-已记录', () async {
      final foods = await db.foodItems.select().get();
      final chicken = foods.firstWhere((f) => f.name == '鸡胸肉');
      await mealRepo.insertMealLog(
        date: '2026-07-02',
        mealType: 'lunch',
        foodItemId: chicken.id,
        actualServingG: 100,
        actualCalories: 165,
        actualProteinG: 31,
        actualFatG: 3.6,
        actualCarbsG: 0,
      );
      final r = await service.getDailyRemaining('2026-07-02');
      expect(r.consumedCalories, 165);
      expect(r.remainingCalories, 2000 - 165);
      expect(r.consumedProtein, 31);
      expect(r.remainingProtein, closeTo(98 - 31, 0.1));
    });

    test('热量超标 → remainingCalories 为负', () async {
      final foods = await db.foodItems.select().get();
      final chips = foods.firstWhere((f) => f.name == '薯片');
      await mealRepo.insertMealLog(
        date: '2026-07-02',
        mealType: 'snack',
        foodItemId: chips.id,
        actualServingG: 500, // 500g 薯片 = 2735 kcal，超标
        actualCalories: 2735,
        actualProteinG: 30,
        actualFatG: 175,
        actualCarbsG: 265,
      );
      final r = await service.getDailyRemaining('2026-07-02');
      expect(r.isCalorieOver, true);
      expect(r.remainingCalories, lessThan(0));
    });

    test('蛋白质缺口判断', () async {
      // 无记录，剩余蛋白 98g > 5 → hasProteinGap=true
      final r = await service.getDailyRemaining('2026-07-02');
      expect(r.hasProteinGap, true);
    });
  });

  group('recommend 推荐算法', () {
    test('蛋白质缺口大 → 高蛋白食物排前', () async {
      final r = await service.getDailyRemaining('2026-07-02'); // 无记录，缺口大
      final recs = await service.recommend(remaining: r, limit: 5);

      expect(recs, isNotEmpty);
      // 鸡胸肉蛋白密度最高（31g/165kcal），应排第一
      expect(recs.first.food.name, '鸡胸肉');
    });

    test('热量已超标 → 低热量食物优先，高热量被惩罚', () async {
      // 构造热量超标场景
      final foods = await db.foodItems.select().get();
      final chips = foods.firstWhere((f) => f.name == '薯片');
      await mealRepo.insertMealLog(
        date: '2026-07-02',
        mealType: 'snack',
        foodItemId: chips.id,
        actualServingG: 500,
        actualCalories: 2735,
        actualProteinG: 30,
        actualFatG: 175,
        actualCarbsG: 265,
      );
      final r = await service.getDailyRemaining('2026-07-02');
      expect(r.isCalorieOver, true);

      final recs = await service.recommend(remaining: r, limit: 5);
      expect(recs, isNotEmpty);
      // 白菜（17kcal）应排在薯片（547kcal）前面
      final cabbageIdx = recs.indexWhere((e) => e.food.name == '白菜');
      final chipsIdx = recs.indexWhere((e) => e.food.name == '薯片');
      if (chipsIdx >= 0) {
        // 薯片可能被过滤（score<=0），如果存在则白菜应在前面
        expect(cabbageIdx, lessThan(chipsIdx));
      }
    });

    test('limit 截断', () async {
      final r = await service.getDailyRemaining('2026-07-02');
      final recs = await service.recommend(remaining: r, limit: 3);
      expect(recs.length, lessThanOrEqualTo(3));
    });

    test('空食物库 → 返回空列表', () async {
      // 删除所有食物
      await db.foodItems.delete().go();
      final r = await service.getDailyRemaining('2026-07-02');
      final recs = await service.recommend(remaining: r, limit: 5);
      expect(recs, isEmpty);
    });

    test('推荐理由非空', () async {
      final r = await service.getDailyRemaining('2026-07-02');
      final recs = await service.recommend(remaining: r, limit: 5);
      for (final rec in recs) {
        expect(rec.reason, isNotEmpty);
      }
    });

    test('异常食物（calories=0 且 protein=0）被过滤', () async {
      await _seedFood(db, name: '异常食物', cal: 0, protein: 0, fat: 0, carbs: 0);
      final r = await service.getDailyRemaining('2026-07-02');
      final recs = await service.recommend(remaining: r, limit: 10);
      expect(recs.any((e) => e.food.name == '异常食物'), isFalse);
    });
  });
}

/// 辅助：插入一条食物
Future<void> _seedFood(
  EatWiseDatabase db, {
  required String name,
  required double cal,
  required double protein,
  required double fat,
  required double carbs,
}) async {
  await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
        name: name,
        defaultServingG: 100,
        caloriesPer100g: cal,
        proteinPer100g: protein,
        fatPer100g: fat,
        carbsPer100g: carbs,
        source: 'test',
        sourceVersion: 'test_v1',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
}
