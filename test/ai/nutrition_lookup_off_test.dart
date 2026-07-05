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
  Future<OffResult?> lookup(String dishName, {String brand = ''}) async {
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

  // P1-3：OFF 命中营养按 ediblePercent 调整（与 DB 命中路径 _nutritionFromFood 行为一致）
  // 修复前：OFF 命中营养素 = per100g × servingG / 100，不乘 ediblePercent
  // 修复后：OFF 命中营养素 = per100g × servingG × (ediblePercent ?? 100) / 100 / 100
  //         生鲜食品（edible<100）乘 ediblePercent/100，加工食品（edible=100 或 null）不变
  group('P1-3 OFF 命中营养按 ediblePercent 调整', () {
    test('Test A: 香蕉 edible=65% OFF 命中 → 碳水乘 0.65', () async {
      // OFF 命中香蕉 per100g 碳水=22g，servingG=200g，edible=65%
      // 实际碳水 = 22 × 200 × 0.65 / 100 = 28.6g
      final offResult = const OffResult(
        name: 'Banana',
        brand: '',
        caloriesPer100g: 93,
        proteinPer100g: 1.4,
        fatPer100g: 0.2,
        carbsPer100g: 22.0,
        defaultServingG: 100,
        ediblePercent: 65,
      );
      final off = FakeOffProvider(offResult);
      final lookup = NutritionLookup(repo, offProvider: off);

      final r = await lookup.lookupSingleItem(dishName: '香蕉', servingG: 200);

      expect(r, isNotNull);
      // 修复后：碳水 = 22 × 200 × 0.65 / 100 = 28.6
      expect(r!.carbsG, closeTo(28.6, 0.01));
      // 热量 = 93 × 200 × 0.65 / 100 = 120.9
      expect(r.calories, closeTo(120.9, 0.01));
      // 蛋白 = 1.4 × 200 × 0.65 / 100 = 1.82
      expect(r.proteinG, closeTo(1.82, 0.01));
      // 脂肪 = 0.2 × 200 × 0.65 / 100 = 0.26
      expect(r.fatG, closeTo(0.26, 0.01));
    });

    test('Test B: 加工饼干 edible=100% OFF 命中 → 不变（行为同原逻辑）', () async {
      // OFF 命中饼干 per100g 碳水=70g，servingG=50g，edible=100%
      // 实际碳水 = 70 × 50 × 1.0 / 100 = 35g（与修复前一致）
      final offResult = const OffResult(
        name: 'Biscuit',
        brand: 'Oreo',
        caloriesPer100g: 480,
        proteinPer100g: 6,
        fatPer100g: 20,
        carbsPer100g: 70,
        defaultServingG: 50,
        ediblePercent: 100,
      );
      final off = FakeOffProvider(offResult);
      final lookup = NutritionLookup(repo, offProvider: off);

      final r = await lookup.lookupSingleItem(dishName: '饼干', servingG: 50);

      expect(r, isNotNull);
      // edible=100% → 不缩放，碳水 = 70 × 50 / 100 = 35
      expect(r!.carbsG, closeTo(35, 0.01));
      expect(r.calories, closeTo(240, 0.01)); // 480 × 50 / 100
    });

    test('Test C: OFF 命中 ediblePercent=null → 视为 100% 不乘', () async {
      // OFF 命中可乐 per100g 碳水=10.6g，servingG=250g，ediblePercent=null
      // 实际碳水 = 10.6 × 250 / 100 = 26.5g（与修复前一致）
      final offResult = const OffResult(
        name: 'Coca Cola',
        brand: 'Coca-Cola',
        caloriesPer100g: 42,
        proteinPer100g: 0,
        fatPer100g: 0,
        carbsPer100g: 10.6,
        defaultServingG: 250,
        // ediblePercent 不传，默认 null
      );
      final off = FakeOffProvider(offResult);
      final lookup = NutritionLookup(repo, offProvider: off);

      final r = await lookup.lookupSingleItem(dishName: '可乐', servingG: 250);

      expect(r, isNotNull);
      // null → 100% → 不缩放，碳水 = 10.6 × 250 / 100 = 26.5
      expect(r!.carbsG, closeTo(26.5, 0.01));
      expect(r.calories, closeTo(105, 0.01)); // 42 × 250 / 100
    });

    test('Test D: lookupSingleItemWithRange OFF 命中 + edible=65% 三档均乘 0.65', () async {
      // 区间查库 OFF 路径也要乘 ediblePercent（与 lookupSingleItem 一致）
      final offResult = const OffResult(
        name: 'Banana',
        brand: '',
        caloriesPer100g: 93,
        proteinPer100g: 1.4,
        fatPer100g: 0.2,
        carbsPer100g: 22.0,
        defaultServingG: 100,
        ediblePercent: 65,
      );
      final off = FakeOffProvider(offResult);
      final lookup = NutritionLookup(repo, offProvider: off);

      final range = await lookup.lookupSingleItemWithRange(
        dishName: '香蕉',
        servingGLow: 100,
        servingGMid: 200,
        servingGHigh: 300,
      );
      expect(range, isNotNull);
      // low: 22 × 100 × 0.65 / 100 = 14.3
      // mid: 22 × 200 × 0.65 / 100 = 28.6
      // high: 22 × 300 × 0.65 / 100 = 42.9
      expect(range!.low.carbsG, closeTo(14.3, 0.01));
      expect(range.mid.carbsG, closeTo(28.6, 0.01));
      expect(range.high.carbsG, closeTo(42.9, 0.01));
      // OFF 只调 1 次（M10 优化不退化）
      expect(off.callCount, 1);
    });
  });

  // M10 特征测试：lookupSingleItemWithRange OFF 路径安全网
  // 确保 M10 性能优化（查库 3 次→1 次）不改变 OFF 路径可观察行为。
  group('lookupSingleItemWithRange OFF 路径（M10 安全网）', () {
    test('DB miss + OFF 命中：三档基于同一 OFF 数据计算', () async {
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

      final range = await lookup.lookupSingleItemWithRange(
        dishName: '可乐',
        servingGLow: 200,
        servingGMid: 250,
        servingGHigh: 300,
      );
      expect(range, isNotNull);
      // OFF 路径不乘 ediblePercent（insertOff 不设 ediblePercent）
      // low: 42*200/100=84, mid: 42*250/100=105, high: 42*300/100=126
      expect(range!.low.calories, closeTo(84, 0.01));
      expect(range.mid.calories, closeTo(105, 0.01));
      expect(range.high.calories, closeTo(126, 0.01));
      // foodItemId 三档相同（同一 OFF 落库 id）
      expect(range.low.foodItemId, range.mid.foodItemId);
      expect(range.mid.foodItemId, range.high.foodItemId);
      // OFF 只调 1 次（M10 优化前后均如此，验证不退化）
      expect(off.callCount, 1);
    });

    test('DB miss + OFF miss → 返回 null', () async {
      final off = FakeOffProvider(null);
      final lookup = NutritionLookup(repo, offProvider: off);

      final range = await lookup.lookupSingleItemWithRange(
        dishName: '不存在的食物',
        servingGLow: 80,
        servingGMid: 100,
        servingGHigh: 120,
      );
      expect(range, isNull);
      expect(off.callCount, 1);
    });
  });
}
