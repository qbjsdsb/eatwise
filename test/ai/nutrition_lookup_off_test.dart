import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/off_provider.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可控的 Fake OffProvider：继承 OffProvider，重写 lookup 返回预设结果
class FakeOffProvider extends OffProvider {
  final OffResult? result;
  int callCount = 0;
  FakeOffProvider(this.result) : super(isOnline: () async => true);

  @override
  Future<OffResult?> lookup(String dishName) async {
    callCount++;
    return result;
  }
}

void main() {
  late EatWiseDatabase db;
  late FoodItemRepository repo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    repo = FoodItemRepository(db);
  });

  tearDown(() async => db.close());

  test('查库命中 → 不调 OFF', () async {
    // 预置一条库数据
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '番茄',
          defaultServingG: 100,
          caloriesPer100g: 18,
          proteinPer100g: 0.9,
          fatPer100g: 0.2,
          carbsPer100g: 3.9,
          source: 'china_fct',
          sourceVersion: 'test',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
    final off = FakeOffProvider(null);
    final lookup = NutritionLookup(repo, offProvider: off);

    final r = await lookup.lookupSingleItem(dishName: '番茄', servingG: 100);

    expect(r, isNotNull);
    expect(r!.calories, 18);
    expect(off.callCount, 0); // 库命中，OFF 未被调用
  });

  test('查库 miss + OFF 命中 → 落库 + 返回 OFF 结果', () async {
    final offResult = const OffResult(
      name: 'Coca Cola',
      brand: 'Coca-Cola',
      caloriesPer100g: 42,
      proteinPer100g: 0,
      fatPer100g: 0,
      carbsPer100g: 10.6,
      defaultServingG: 250,
    );
    final off = FakeOffProvider(offResult);
    final lookup = NutritionLookup(repo, offProvider: off);

    final r = await lookup.lookupSingleItem(dishName: '可乐', servingG: 250);

    expect(r, isNotNull);
    expect(r!.calories, closeTo(42 * 250 / 100, 0.01)); // 105
    expect(r.proteinG, 0);
    expect(r.fatG, 0);
    expect(r.carbsG, closeTo(10.6 * 250 / 100, 0.01)); // 26.5
    expect(off.callCount, 1);

    // 验证落库：source='off'，aliases 含菜名本身
    final saved = await (db.foodItems.select()
          ..where((f) => f.name.equals('可乐')))
        .getSingle();
    expect(saved.source, 'off');
    expect(saved.sourceVersion, 'off_v1');
    expect(saved.caloriesPer100g, 42);
    expect(saved.defaultServingG, 250);
    final aliases = jsonDecode(saved.aliasesJson!) as List;
    expect(aliases, contains('可乐'));
  });

  test('查库 miss + OFF miss → 返回 null', () async {
    final off = FakeOffProvider(null);
    final lookup = NutritionLookup(repo, offProvider: off);

    final r = await lookup.lookupSingleItem(dishName: '不存在的食物', servingG: 100);

    expect(r, isNull);
    expect(off.callCount, 1);
    // 不应落库
    final all = await db.foodItems.select().get();
    expect(all, isEmpty);
  });

  test('查库 miss + OFF 命中 → 第二次同名查库命中（不再调 OFF）', () async {
    final offResult = const OffResult(
      name: 'Cola',
      brand: '',
      caloriesPer100g: 42,
      proteinPer100g: 0,
      fatPer100g: 0,
      carbsPer100g: 10.6,
      defaultServingG: 100,
    );
    final off = FakeOffProvider(offResult);
    final lookup = NutritionLookup(repo, offProvider: off);

    // 第一次：miss → OFF → 落库
    final r1 = await lookup.lookupSingleItem(dishName: '可乐', servingG: 100);
    expect(r1, isNotNull);
    expect(off.callCount, 1);

    // 第二次：应直接查库命中（aliases 含'可乐'，精确命中），不再调 OFF
    final r2 = await lookup.lookupSingleItem(dishName: '可乐', servingG: 200);
    expect(r2, isNotNull);
    expect(r2!.calories, closeTo(42 * 200 / 100, 0.01)); // 84
    expect(off.callCount, 1); // 仍是 1，未再调
  });

  test('不注入 OFF → 行为同原逻辑（向后兼容）', () async {
    final lookup = NutritionLookup(repo); // 不传 offProvider

    final r = await lookup.lookupSingleItem(dishName: '不存在', servingG: 100);

    expect(r, isNull);
  });

  test('复合菜组分 miss 不触发 OFF（OFF 仅兜底单品）', () async {
    // 预置一个组分
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
    final off = FakeOffProvider(null);
    final lookup = NutritionLookup(repo, offProvider: off);

    final r = await lookup.lookupCompositeDish(
      components: [
        const FoodComponent(name: '鸡蛋', estimatedG: 100),
        const FoodComponent(name: '不存在的食材', estimatedG: 50),
      ],
      cookingMethod: 'boil',
    );

    expect(r.componentMisses, ['不存在的食材']);
    expect(off.callCount, 0); // 复合菜不触发 OFF（设计如此）
  });
}
