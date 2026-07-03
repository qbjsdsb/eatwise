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
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
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
        ));
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '鸡蛋',
          defaultServingG: 60,
          caloriesPer100g: 144,
          proteinPer100g: 13,
          fatPer100g: 9,
          carbsPer100g: 1.1,
          source: 'china_fct',
          sourceVersion: 'test',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
    lookup = NutritionLookup(FoodItemRepository(db));
  });

  tearDown(() async => db.close());

  test('单品查库：按 name 命中', () async {
    final result = await lookup.lookupSingleItem(dishName: '番茄', servingG: 200);
    expect(result, isNotNull);
    expect(result!.calories, closeTo(36, 0.01)); // 18 * 200 / 100
  });

  test('单品查库：按 aliases 命中（西红柿→番茄）', () async {
    final result = await lookup.lookupSingleItem(dishName: '西红柿', servingG: 100);
    expect(result, isNotNull);
    expect(result!.calories, 18);
  });

  test('单品查库：未命中返回 null', () async {
    final result = await lookup.lookupSingleItem(dishName: '不存在的食物', servingG: 100);
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

  // 建议 1：可食部分系数（ediblePercent）专项测试
  group('ediblePercent 可食部分系数', () {
    test('香蕉 edible=65%：200g 整重按可食 130g 反算', () async {
      // 插入香蕉：cal100=93, edible=65%（带皮）
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '香蕉',
            defaultServingG: 100,
            caloriesPer100g: 93,
            proteinPer100g: 1.4,
            fatPer100g: 0.2,
            carbsPer100g: 22.0,
            ediblePercent: const Value(65),
            source: 'china_fct',
            sourceVersion: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
      // 200g 带皮香蕉 → 可食 130g → 93 * 130/100 = 120.9
      final result = await lookup.lookupSingleItem(dishName: '香蕉', servingG: 200);
      expect(result, isNotNull);
      expect(result!.calories, closeTo(120.9, 0.01));
      expect(result.proteinG, closeTo(1.82, 0.01)); // 1.4 * 1.3
    });

    test('排骨 edible=50%：300g 整重按可食 150g 反算', () async {
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '排骨',
            defaultServingG: 100,
            caloriesPer100g: 278,
            proteinPer100g: 18.3,
            fatPer100g: 22.0,
            carbsPer100g: 1.0,
            ediblePercent: const Value(50),
            source: 'china_fct',
            sourceVersion: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
      // 300g 带骨排骨 → 可食 150g → 278 * 150/100 = 417
      final result = await lookup.lookupSingleItem(dishName: '排骨', servingG: 300);
      expect(result, isNotNull);
      expect(result!.calories, closeTo(417, 0.01));
    });

    test('ediblePercent=null（包装食品）按 100% 不缩放', () async {
      // 番茄在 setUp 插入时 ediblePercent=null → 200g 应按 200g 算
      final result = await lookup.lookupSingleItem(dishName: '番茄', servingG: 200);
      expect(result, isNotNull);
      expect(result!.calories, closeTo(36, 0.01)); // 18 * 200/100，不缩放
    });

    test('ediblePercent=100（可食部分=全部）不缩放', () async {
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '苹果',
            defaultServingG: 100,
            caloriesPer100g: 54,
            proteinPer100g: 0.3,
            fatPer100g: 0.2,
            carbsPer100g: 13.5,
            ediblePercent: const Value(100),
            source: 'china_fct',
            sourceVersion: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
      final result = await lookup.lookupSingleItem(dishName: '苹果', servingG: 200);
      expect(result, isNotNull);
      expect(result!.calories, closeTo(108, 0.01)); // 54 * 200/100
    });

    test('ediblePercent=0（异常数据）clamp 到 1% 防热量=0', () async {
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '异常食物',
            defaultServingG: 100,
            caloriesPer100g: 100,
            proteinPer100g: 10,
            fatPer100g: 1,
            carbsPer100g: 20,
            ediblePercent: const Value(0),
            source: 'china_fct',
            sourceVersion: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
      final result = await lookup.lookupSingleItem(dishName: '异常食物', servingG: 200);
      expect(result, isNotNull);
      // 200 * 1% = 2g 有效 → 100 * 2/100 = 2（不为 0，防数据丢失）
      expect(result!.calories, closeTo(2, 0.01));
    });

    test('复合菜组分不乘 ediblePercent（组分已是可食部分）', () async {
      // 鸡蛋 ediblePercent=null，但即使设为 87（带壳），组分也不应乘
      // 因为复合菜里的"鸡蛋 120g"是去壳后的蛋液重量
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '带壳鸡蛋',
            defaultServingG: 60,
            caloriesPer100g: 144,
            proteinPer100g: 13,
            fatPer100g: 9,
            carbsPer100g: 1.1,
            ediblePercent: const Value(87), // 带壳可食 87%
            source: 'china_fct',
            sourceVersion: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
      final result = await lookup.lookupCompositeDish(
        components: [FoodComponent(name: '带壳鸡蛋', estimatedG: 120)],
        cookingMethod: 'boil',
      );
      // 组分 120g 是去壳蛋液，不乘 87% → 144 * 120/100 = 172.8
      expect(result.calories, closeTo(172.8, 0.01));
    });
  });
}
