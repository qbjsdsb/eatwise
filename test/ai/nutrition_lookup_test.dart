import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late NutritionLookup lookup;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    // 预置测试数据
    await db
        .into(db.foodItems)
        .insert(
          FoodItemsCompanion.insert(
            name: '番茄',
            defaultServingG: 100,
            caloriesPer100g: 18,
            proteinPer100g: 0.9,
            fatPer100g: 0.2,
            carbsPer100g: 3.9,
            aliasesJson: Value('["西红柿","tomato"]'),
            source: 'china_fct',
            sourceVersion: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    await db
        .into(db.foodItems)
        .insert(
          FoodItemsCompanion.insert(
            name: '鸡蛋',
            defaultServingG: 60,
            caloriesPer100g: 144,
            proteinPer100g: 13,
            fatPer100g: 9,
            carbsPer100g: 1.1,
            source: 'china_fct',
            sourceVersion: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    lookup = NutritionLookup(FoodItemRepository(db));
  });

  tearDown(() async => db.close());

  test('单品查库：按 name 命中', () async {
    final result = await lookup.lookupSingleItem(dishName: '番茄', servingG: 200);
    expect(result, isNotNull);
    expect(result!.calories, closeTo(36, 0.01)); // 18 * 200 / 100
  });

  test('单品查库：按 aliases 命中（西红柿→番茄）', () async {
    final result = await lookup.lookupSingleItem(
      dishName: '西红柿',
      servingG: 100,
    );
    expect(result, isNotNull);
    expect(result!.calories, 18);
  });

  test('单品查库：未命中返回 null', () async {
    final result = await lookup.lookupSingleItem(
      dishName: '不存在的食物',
      servingG: 100,
    );
    expect(result, isNull);
  });

  test('复合菜：组分累加 + 炒菜用油', () async {
    final result = await lookup.lookupCompositeDish(
      components: [
        FoodComponent(name: '鸡蛋', estimatedG: 120),
        FoodComponent(name: '番茄', estimatedG: 150),
      ],
      cookingMethod: 'stir-fry',
    );

    expect(result.componentMisses, isEmpty);
    expect(result.componentHits.length, 2);
    // 鸡蛋 144*1.2=172.8 + 番茄 18*1.5=27 = 199.8 + 油 889*0.12=106.68 = 306.48
    expect(result.calories, closeTo(306.48, 0.5));
    expect(result.oilG, 12); // 炒 12g
  });

  test('复合菜：组分部分未命中', () async {
    final result = await lookup.lookupCompositeDish(
      components: [
        FoodComponent(name: '鸡蛋', estimatedG: 100),
        FoodComponent(name: '不存在的食材', estimatedG: 50),
      ],
      cookingMethod: 'boil',
    );

    expect(result.componentMisses, ['不存在的食材']);
    expect(result.componentHits.length, 1);
    expect(result.oilG, 0); // 煮 0g 油
  });
}
