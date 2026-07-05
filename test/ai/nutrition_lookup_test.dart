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

  // M10 特征测试：lookupSingleItemWithRange 行为安全网（重构查库 3 次→1 次用）
  // 这些测试文档化现有行为，确保 M10 性能优化不改变可观察行为。
  group('lookupSingleItemWithRange 特征测试（M10 安全网）', () {
    test('DB 命中：三档基于同一 food 计算，比例 = servingG 比例', () async {
      final range = await lookup.lookupSingleItemWithRange(
        dishName: '番茄',
        servingGLow: 80,
        servingGMid: 100,
        servingGHigh: 120,
      );
      expect(range, isNotNull);
      // 番茄：cal100=18, protein=0.9, fat=0.2, carbs=3.9, edible=null(100%)
      // low: 18*80/100=14.4, mid: 18*100/100=18, high: 18*120/100=21.6
      expect(range!.low.calories, closeTo(14.4, 0.01));
      expect(range.mid.calories, closeTo(18, 0.01));
      expect(range.high.calories, closeTo(21.6, 0.01));
      // 比例一致（同一 food per100g × 不同 servingG）
      expect(range.low.proteinG / range.mid.proteinG, closeTo(80 / 100, 0.001));
      expect(range.mid.proteinG / range.high.proteinG,
          closeTo(100 / 120, 0.001));
      // foodItemId 三档相同（同一 food）
      expect(range.low.foodItemId, range.mid.foodItemId);
      expect(range.mid.foodItemId, range.high.foodItemId);
    });

    test('DB miss → 返回 null（无 OFF 注入）', () async {
      final range = await lookup.lookupSingleItemWithRange(
        dishName: '不存在的食物',
        servingGLow: 80,
        servingGMid: 100,
        servingGHigh: 120,
      );
      expect(range, isNull);
    });

    test('ediblePercent 食物三档：effectiveG 按可食部分缩放', () async {
      // 香蕉 edible=65%
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
      final range = await lookup.lookupSingleItemWithRange(
        dishName: '香蕉',
        servingGLow: 100,
        servingGMid: 200,
        servingGHigh: 300,
      );
      expect(range, isNotNull);
      // low: 100*0.65=65g → 93*65/100=60.45
      // mid: 200*0.65=130g → 93*130/100=120.9
      // high: 300*0.65=195g → 93*195/100=181.35
      expect(range!.low.calories, closeTo(60.45, 0.01));
      expect(range.mid.calories, closeTo(120.9, 0.01));
      expect(range.high.calories, closeTo(181.35, 0.01));
    });

    test('复合菜占位记录（componentsJson != null）→ 返回 null', () async {
      // 插入一个复合菜占位记录（per100g=0, componentsJson 非空）
      // lookupSingleItem 对这类记录返回 null（视为未命中，防 0 热量污染）
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '番茄炒蛋',
            defaultServingG: 250,
            caloriesPer100g: 0,
            proteinPer100g: 0,
            fatPer100g: 0,
            carbsPer100g: 0,
            componentsJson:
                const Value('[{"name":"鸡蛋","estimated_g":120}]'),
            source: 'composite',
            sourceVersion: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
      final range = await lookup.lookupSingleItemWithRange(
        dishName: '番茄炒蛋',
        servingGLow: 200,
        servingGMid: 250,
        servingGHigh: 300,
      );
      expect(range, isNull,
          reason: '复合菜占位记录不应被单品区间查库命中');
    });
  });

  // M16.5 修复 P0：复合菜占位记录污染 lookupCompositeDish
  // 现象：用户从 v0.18.2 升级到 v0.18.3 后，AI 推理正确的复合菜（如米粉汤）
  //       UI 显示蛋白/脂肪/碳水全 0。
  // 根因：lookupSingleItem 有 componentsJson != null 保护（视为未命中返回 null），
  //       但 lookupCompositeDish 没有同样保护。组分名 contains 命中历史 ai_recognized
  //       占位记录（per100g=0, componentsJson 非空）→ 0 * g / 100 = 0 → 复合菜营养全 0。
  // 场景：用户上次吃"米粉汤"创建占位记录"米粉汤"（per100g=0）。这次识别"米粉汤"
  //       复合菜，组分"米粉"通过优先级 3 contains 命中"米粉汤"占位 → 0 计算。
  group('M16.5 P0：复合菜占位记录不应污染 lookupCompositeDish', () {
    test('组分 contains 命中复合菜占位记录时应视为 miss，不用 0 值计算', () async {
      // 模拟用户历史识别"米粉汤"创建的 ai_recognized 占位记录
      // per100g=0（实际热量在 meal_log.componentsSnapshotJson），componentsJson 非空
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '米粉汤',
            defaultServingG: 350,
            caloriesPer100g: 0,
            proteinPer100g: 0,
            fatPer100g: 0,
            carbsPer100g: 0,
            componentsJson:
                const Value('[{"name":"米粉","estimated_g":80}]'),
            source: 'ai_recognized',
            sourceVersion: 'ai',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));

      // DB 里没有"米粉"正常数据，组分"米粉"会 contains 命中"米粉汤"占位
      // 当前 bug：用占位记录的 0 值计算 → 营养全 0
      // 期望：跳过占位记录，"米粉"加入 misses
      final result = await lookup.lookupCompositeDish(
        components: [FoodComponent(name: '米粉', estimatedG: 80)],
        cookingMethod: 'boil',
      );

      expect(result.componentMisses, contains('米粉'),
          reason: '组分命中复合菜占位记录（per100g=0, componentsJson 非空）时应视为 miss');
      expect(result.componentHits, isEmpty,
          reason: '占位记录不应作为营养计算源被加入 componentHits');
    });

    test('组分名与占位记录名相同时（精确命中）也应跳过', () async {
      // 边界场景：用户上次吃"麻婆豆腐"创建占位记录 name="麻婆豆腐"（per100g=0）
      // 这次识别"麻婆豆腐"复合菜，组分名 AI 错误返回"麻婆豆腐"（而非"豆腐"）
      // 优先级 1 精确命中占位记录 → 当前 bug：用 0 值计算
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '麻婆豆腐',
            defaultServingG: 300,
            caloriesPer100g: 0,
            proteinPer100g: 0,
            fatPer100g: 0,
            carbsPer100g: 0,
            componentsJson:
                const Value('[{"name":"豆腐","estimated_g":150}]'),
            source: 'ai_recognized',
            sourceVersion: 'ai',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));

      final result = await lookup.lookupCompositeDish(
        components: [FoodComponent(name: '麻婆豆腐', estimatedG: 150)],
        cookingMethod: 'stir-fry',
      );

      expect(result.componentMisses, contains('麻婆豆腐'),
          reason: '精确命中复合菜占位记录也应视为 miss');
      expect(result.componentHits, isEmpty);
    });

    test('占位记录被跳过后，其他正常组分仍能命中并计算', () async {
      // 混合场景：组分"米粉"contains 命中占位记录"米粉汤"（跳过），
      // 组分"鸡蛋"精确命中正常数据（计算）。验证跳过占位记录不影响其他组分。
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '米粉汤',
            defaultServingG: 350,
            caloriesPer100g: 0,
            proteinPer100g: 0,
            fatPer100g: 0,
            carbsPer100g: 0,
            componentsJson:
                const Value('[{"name":"米粉","estimated_g":80}]'),
            source: 'ai_recognized',
            sourceVersion: 'ai',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));

      final result = await lookup.lookupCompositeDish(
        components: [
          FoodComponent(name: '米粉', estimatedG: 80),
          FoodComponent(name: '鸡蛋', estimatedG: 120), // setUp 插入的正常数据
        ],
        cookingMethod: 'boil',
      );

      // "米粉"跳过（miss），"鸡蛋"命中（hit）
      expect(result.componentMisses, contains('米粉'));
      expect(result.componentHits.length, 1);
      expect(result.componentHits.first.name, '鸡蛋');
      // 鸡蛋 144 * 120/100 = 172.8，无油（boil）
      expect(result.calories, closeTo(172.8, 0.01));
      expect(result.proteinG, closeTo(15.6, 0.01)); // 13 * 120/100
    });
  });

  // M16.5 修复 P0-2：M16.3 migration 后的全 0 脏数据污染 lookupCompositeDish
  // 现象：M16.3 migration v3→v4 把脏数据（>100 / >900）置 0，但条目未删除。
  //       _isDirtyFoodItem 只检查 >100 不检查 ==0，migration 后的 0 值条目通过过滤。
  //       lookupCompositeDish 命中这些 0 值条目 → 0 * g / 100 = 0 → 营养全 0。
  // 修复策略：lookupCompositeDish 命中"全 0 营养条目"（蛋白/脂肪/碳水/热量都为 0）
  //         时视为 miss。水/茶等合法 0 营养食物跳过对复合菜计算无影响（0*g/100=0）。
  group('M16.5 P0-2：全 0 营养条目不应污染 lookupCompositeDish', () {
    test('组分命中 migration 后的全 0 脏数据时应视为 miss', () async {
      // 模拟 M16.3 migration 把脏数据（4 字段都 >100/>900）置 0 后的条目
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '米粉',
            defaultServingG: 100,
            caloriesPer100g: 0,
            proteinPer100g: 0,
            fatPer100g: 0,
            carbsPer100g: 0,
            source: 'china_fct',
            sourceVersion: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));

      final result = await lookup.lookupCompositeDish(
        components: [FoodComponent(name: '米粉', estimatedG: 80)],
        cookingMethod: 'boil',
      );

      expect(result.componentMisses, contains('米粉'),
          reason: '全 0 营养条目（migration 后脏数据）不应作为营养计算源');
      expect(result.componentHits, isEmpty);
    });

    test('部分字段为 0 但非全 0 的条目仍正常计算（非脏数据）', () async {
      // 边界场景：蛋白质 0（合法，如纯淀粉类食物）但碳水非 0
      // 这种条目不是 migration 后的全 0 脏数据，应正常计算
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '纯淀粉',
            defaultServingG: 100,
            caloriesPer100g: 381,
            proteinPer100g: 0.1,
            fatPer100g: 0,
            carbsPer100g: 91.3,
            source: 'china_fct',
            sourceVersion: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));

      final result = await lookup.lookupCompositeDish(
        components: [FoodComponent(name: '纯淀粉', estimatedG: 50)],
        cookingMethod: 'boil',
      );

      expect(result.componentHits.length, 1);
      // 381 * 50/100 = 190.5
      expect(result.calories, closeTo(190.5, 0.01));
      expect(result.carbsG, closeTo(45.65, 0.01)); // 91.3 * 50/100
    });
  });
}
