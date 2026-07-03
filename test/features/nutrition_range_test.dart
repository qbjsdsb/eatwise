// test/features/nutrition_range_test.dart
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
    lookup = NutritionLookup(FoodItemRepository(db));
    // 种子：米饭（116 kcal/100g）
    await db
        .into(db.foodItems)
        .insert(
          FoodItemsCompanion.insert(
            name: '米饭',
            defaultServingG: 100,
            caloriesPer100g: 116,
            proteinPer100g: 2.6,
            fatPer100g: 0.3,
            carbsPer100g: 25.9,
            source: 'manual',
            sourceVersion: 'test',
            createdAt: 1000,
          ),
        );
  });
  tearDown(() async => db.close());

  test('单品区间计算：Low < Mid < High', () async {
    final range = await lookup.lookupSingleItemWithRange(
      dishName: '米饭',
      servingGLow: 90,
      servingGMid: 100,
      servingGHigh: 110,
    );
    expect(range, isNotNull);
    expect(range!.low.calories, lessThan(range.mid.calories));
    expect(range.mid.calories, lessThan(range.high.calories));
    // Mid = 116 kcal（100g × 116/100）
    expect(range.mid.calories, closeTo(116, 0.1));
    // Low = 104.4（90g），High = 127.6（110g）
    expect(range.low.calories, closeTo(104.4, 0.1));
    expect(range.high.calories, closeTo(127.6, 0.1));
  });

  test('单品未命中返回 null', () async {
    final range = await lookup.lookupSingleItemWithRange(
      dishName: '不存在的食物',
      servingGLow: 90,
      servingGMid: 100,
      servingGHigh: 110,
    );
    expect(range, isNull);
  });

  test('复合菜区间计算：Low < Mid < High', () async {
    final range = await lookup.lookupCompositeDishWithRange(
      components: const [FoodComponent(name: '米饭', estimatedG: 100)],
      cookingMethod: 'steam',
    );
    expect(range.low.calories, lessThan(range.mid.calories));
    expect(range.mid.calories, lessThan(range.high.calories));
  });
}
