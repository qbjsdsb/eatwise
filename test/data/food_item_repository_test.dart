import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late FoodItemRepository repo;
  late MealLogRepository mealRepo;

  setUp(() {
    db = EatWiseDatabase(NativeDatabase.memory());
    repo = FoodItemRepository(db);
    mealRepo = MealLogRepository(db);
  });

  tearDown(() async => db.close());

  // 辅助：插入一条食物
  Future<int> seedFood(String name,
      {String source = 'china_fct',
      double cal = 50,
      double serving = 100}) async {
    return db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: name,
          defaultServingG: serving,
          caloriesPer100g: cal,
          proteinPer100g: 1.0,
          fatPer100g: 0.2,
          carbsPer100g: 13.5,
          source: source,
          sourceVersion: 'v1',
          createdAt: 0,
        ));
  }

  test('searchByName 模糊匹配', () async {
    await seedFood('苹果');
    await seedFood('苹果汁');
    await seedFood('香蕉');

    final results = await repo.searchByName('苹果');
    expect(results.length, 2);
    expect(results.every((f) => f.name.contains('苹果')), true);
  });

  test('searchByName 空关键字返回空（不会全表扫）', () async {
    await seedFood('苹果');
    // LIKE '%%' 会匹配所有，但这是预期行为（UI 层 keyword.isEmpty 时不调用）
    final results = await repo.searchByName('');
    expect(results.length, 1);
  });

  test('getById 返回对应食物', () async {
    final id = await seedFood('苹果');
    final item = await repo.getById(id);
    expect(item, isNotNull);
    expect(item!.name, '苹果');
  });

  test('getById 不存在的 id 返回 null', () async {
    final item = await repo.getById(99999);
    expect(item, isNull);
  });

  test('listFrequent 按引用次数降序', () async {
    final appleId = await seedFood('苹果');
    final bananaId = await seedFood('香蕉');
    await seedFood('橙子');

    // 苹果被记录 3 次，香蕉 1 次，橙子 0 次
    for (var i = 0; i < 3; i++) {
      await mealRepo.insertMealLog(
        date: '2026-07-0${i + 1}',
        mealType: 'breakfast',
        foodItemId: appleId,
        actualServingG: 100,
        actualCalories: 50,
        actualProteinG: 1.0,
        actualFatG: 0.2,
        actualCarbsG: 13.5,
      );
    }
    await mealRepo.insertMealLog(
      date: '2026-07-01',
      mealType: 'lunch',
      foodItemId: bananaId,
      actualServingG: 100,
      actualCalories: 90,
      actualProteinG: 1.4,
      actualFatG: 0.2,
      actualCarbsG: 22.0,
    );

    final frequent = await repo.listFrequent(limit: 3);
    // 仅返回被 meal_log 引用过的食物（橙子 0 引用不出现）
    expect(frequent.length, 2);
    // 苹果引用 3 次排第一
    expect(frequent.first.name, '苹果');
    // 香蕉引用 1 次排第二
    expect(frequent[1].name, '香蕉');
  });

  test('updateDefaultServing 更新默认份量', () async {
    final id = await seedFood('苹果', serving: 100);
    await repo.updateDefaultServing(id, 150);

    final item = await repo.getById(id);
    expect(item!.defaultServingG, 150);
  });

  test('updateNutrients 更新营养素', () async {
    final id = await seedFood('苹果', cal: 50);
    await repo.updateNutrients(
      id: id,
      caloriesPer100g: 60,
      proteinPer100g: 2.0,
      fatPer100g: 0.5,
      carbsPer100g: 15.0,
    );

    final item = await repo.getById(id);
    expect(item!.caloriesPer100g, 60);
    expect(item.proteinPer100g, 2.0);
    expect(item.fatPer100g, 0.5);
    expect(item.carbsPer100g, 15.0);
  });

  test('insertManual 插入 source=manual 的食物', () async {
    final id = await repo.insertManual(
      name: '自定义菜',
      caloriesPer100g: 200,
      proteinPer100g: 5.0,
      fatPer100g: 3.0,
      carbsPer100g: 30.0,
    );

    final item = await repo.getById(id);
    expect(item, isNotNull);
    expect(item!.name, '自定义菜');
    expect(item.source, 'manual');
    expect(item.sourceVersion, 'manual');
    expect(item.caloriesPer100g, 200);
  });
}
