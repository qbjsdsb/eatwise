import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late FoodItemRepository repo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    repo = FoodItemRepository(db);
    // 预置食物"番茄炒蛋"（脏库 per100g=80）
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '番茄炒蛋',
          defaultServingG: 100,
          caloriesPer100g: 80, // 脏数据
          proteinPer100g: 6,
          fatPer100g: 10,
          carbsPer100g: 12,
          source: 'china_fct',
          sourceVersion: 'test',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
  });

  tearDown(() async => db.close());

  test('updatePer100g 按 foodItemId 更新 4 项 per100g（不动其他字段）', () async {
    await repo.updatePer100g(
      foodItemId: 1,
      caloriesPer100g: 125, // AI 反算的新值
      proteinPer100g: 5,
      fatPer100g: 7.5,
      carbsPer100g: 10,
    );
    final food = await repo.getById(1);
    expect(food!.caloriesPer100g, 125);
    expect(food.proteinPer100g, 5);
    expect(food.fatPer100g, 7.5);
    expect(food.carbsPer100g, 10);
    // 其他字段不动
    expect(food.name, '番茄炒蛋');
    expect(food.defaultServingG, 100);
    expect(food.source, 'china_fct');
  });
}
