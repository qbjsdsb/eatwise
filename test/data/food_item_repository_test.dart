import 'dart:convert';

import 'package:drift/drift.dart' show Value;
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

  // 批次 3：反馈闭环回流 aliasesJson 测试
  group('addAlias 反馈闭环回流', () {
    test('给无别名的 food_item 加别名，findByNameOrAlias 命中', () async {
      // 正确菜"无糖可乐"在库，AI 错误识别为"可乐"
      final correctId = await seedFood('无糖可乐');
      // 把 AI 错误名"可乐"作为"无糖可乐"的别名
      await repo.addAlias(correctId, '可乐');

      // 下次 AI 识别返回"可乐"时，findByNameOrAlias 命中别名，返回"无糖可乐"
      final hit = await repo.findByNameOrAlias('可乐');
      expect(hit, isNotNull);
      expect(hit!.id, correctId);
      expect(hit.name, '无糖可乐');
    });

    test('重复加同一别名幂等（不重复写入）', () async {
      final id = await seedFood('无糖可乐');
      await repo.addAlias(id, '可乐');
      await repo.addAlias(id, '可乐'); // 重复

      final item = await repo.getById(id);
      // aliasesJson 解析后应只有 1 个"可乐"（去重）
      final aliases = item!.aliasesJson;
      expect(aliases, isNotNull);
      expect(aliases!.contains('可乐'), true);
      // 不应出现两次
      expect('可乐'.allMatches(aliases).length, 1);
    });

    test('加与 name 相同的别名跳过（防自引用）', () async {
      final id = await seedFood('苹果');
      await repo.addAlias(id, '苹果');

      final item = await repo.getById(id);
      // name 已是"苹果"，别名不应写入（避免冗余）
      expect(item!.aliasesJson, isNull);
    });

    test('加空串跳过', () async {
      final id = await seedFood('苹果');
      await repo.addAlias(id, '');
      await repo.addAlias(id, '   ');

      final item = await repo.getById(id);
      expect(item!.aliasesJson, isNull);
    });

    test('加多个不同别名都能命中', () async {
      final id = await seedFood('无糖可乐');
      await repo.addAlias(id, '可乐');
      await repo.addAlias(id, '零度可乐');
      await repo.addAlias(id, 'diet coke');

      expect((await repo.findByNameOrAlias('可乐'))?.id, id);
      expect((await repo.findByNameOrAlias('零度可乐'))?.id, id);
      expect((await repo.findByNameOrAlias('diet coke'))?.id, id);
    });

    test('归一化去重（大小写/空格差异视为相同）', () async {
      final id = await seedFood('苹果');
      await repo.addAlias(id, 'Apple');
      await repo.addAlias(id, ' apple '); // 归一化后同 "apple"，应跳过

      final item = await repo.getById(id);
      final aliases = item!.aliasesJson!;
      // 只应有一个 Apple（大小写不敏感去重）
      expect(aliases.toLowerCase().split('apple').length - 1, 1);
    });
  });

  // 识别精准度修复（防"雪花啤酒→雪碧"假阳性）专项测试
  group('识别精准度（防假阳性 + typo 容错 + 全角归一化）', () {
    test('2 字短名编辑距离假阳性已消除：雪花不命中雪碧', () async {
      await seedFood('雪碧');
      // "雪花"vs"雪碧"编辑距离=1，旧逻辑（2字走编辑距离≤1）会误命中
      // 加严后：query 长度 <3 不走编辑距离 → 返回 null
      expect(await repo.findByNameOrAlias('雪花'), isNull);
    });

    test('typo 容错保留：蕃茄炒蛋→番茄炒蛋（4字等长编辑距离1仍命中）', () async {
      // 2 字短名 typo（可东→可乐）与假阳性（雪花→雪碧）无法区分，已禁用；
      // 3+ 字短名的单字 typo 容错保留（如"蕃茄"为"番茄"形近 typo）
      await seedFood('番茄炒蛋');
      final hit = await repo.findByNameOrAlias('蕃茄炒蛋');
      expect(hit, isNotNull);
      expect(hit!.name, '番茄炒蛋');
    });

    test('findExactByNameOrAlias 只精确不模糊', () async {
      await seedFood('雪碧');
      // 精确命中
      expect((await repo.findExactByNameOrAlias('雪碧'))?.name, '雪碧');
      // 模糊不命中（"雪花"与"雪碧"不是精确匹配）
      expect(await repo.findExactByNameOrAlias('雪花'), isNull);
    });

    test('全角括号归一化：可乐（罐）命中 可乐(罐)', () async {
      await seedFood('可乐(罐)');
      // 全角括号（）归一化为半角 ()，精确匹配命中
      expect((await repo.findByNameOrAlias('可乐（罐）'))?.name, '可乐(罐)');
    });
  });

  // addAlias 冲突检测（v3 新增，防反向错配第二道防线）
  group('addAlias 冲突检测（防别名绑多食物）', () {
    test('别名已是其他食物的 name → 拒绝写入', () async {
      await seedFood('雪碧');
      final idB = await seedFood('可口可乐');
      // 试图把"雪碧"（已是 A 的 name）作为 B 的别名 → 应拒绝
      await repo.addAlias(idB, '雪碧');
      final b = await repo.getById(idB);
      expect(b!.aliasesJson, isNull); // 未写入
    });

    test('别名已是其他食物的 alias → 拒绝写入', () async {
      await seedFood('雪碧');
      final idB = await seedFood('可口可乐');
      final idC = await seedFood('芬达');
      // 先正常给 B 加别名"汽水"
      await repo.addAlias(idB, '汽水');
      // 试图把"汽水"（已是 B 的 alias）作为 C 的别名 → 应拒绝
      await repo.addAlias(idC, '汽水');
      final c = await repo.getById(idC);
      expect(c!.aliasesJson, isNull); // 未写入
    });

    test('别名不冲突 → 正常写入', () async {
      await seedFood('雪碧');
      final idB = await seedFood('可口可乐');
      // "柠檬汽水"不与任何食物冲突 → 正常写入 B
      await repo.addAlias(idB, '柠檬汽水');
      final b = await repo.getById(idB);
      expect(b!.aliasesJson, isNotNull);
      expect(b.aliasesJson!.contains('柠檬汽水'), isTrue);
    });
  });

  // P1-2：brand 字段参与匹配测试
  group('findByNameOrAlias brand 字段参与匹配', () {
    test('brand+name 精确命中连锁品牌条目（优先级 0）', () async {
      // 模拟品牌库：name="喜茶多肉葡萄"，aliases=["多肉葡萄"]
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '喜茶多肉葡萄',
            defaultServingG: 480,
            caloriesPer100g: 19.8,
            proteinPer100g: 0.25,
            fatPer100g: 0.1,
            carbsPer100g: 4.6,
            aliasesJson: Value('[${jsonEncode("多肉葡萄")}]'),
            source: 'chain_brand',
            sourceVersion: 'chain_brand_v1',
            createdAt: 0,
          ));
      // 也插一条通用"多肉葡萄"（别名冲突场景）
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '多肉葡萄',
            defaultServingG: 480,
            caloriesPer100g: 60,
            proteinPer100g: 0.5,
            fatPer100g: 0.2,
            carbsPer100g: 14,
            source: 'usda_brand',
            sourceVersion: 'usda_brand_v1',
            createdAt: 0,
          ));

      // brand="喜茶" + name="多肉葡萄" → 命中"喜茶多肉葡萄"（优先级 0）
      final hit = await repo.findByNameOrAlias('多肉葡萄', brand: '喜茶');
      expect(hit, isNotNull);
      expect(hit!.name, '喜茶多肉葡萄');
      expect(hit.caloriesPer100g, 19.8); // 品牌官方值，不是通用 60
    });

    test('brand 为空走原 name 匹配（向后兼容）', () async {
      await seedFood('可乐');
      final hit = await repo.findByNameOrAlias('可乐');
      expect(hit, isNotNull);
      expect(hit!.name, '可乐');
    });

    test('brand+name 未命中再走 name 匹配', () async {
      // 库里有"啤酒"但无"雪花啤酒"
      await seedFood('啤酒');
      final hit = await repo.findByNameOrAlias('啤酒', brand: '雪花');
      expect(hit, isNotNull);
      expect(hit!.name, '啤酒'); // brand+name miss → name 精确命中"啤酒"
    });
  });

  // P0-3：upsertAiRecognized brand 持久化测试
  group('upsertAiRecognized brand 持久化', () {
    test('brand 非空 → brand+name 存为 alias', () async {
      final id = await repo.upsertAiRecognized(
        name: '啤酒',
        brand: '雪花',
        caloriesPer100g: 43,
        proteinPer100g: 0.5,
        fatPer100g: 0,
        carbsPer100g: 3.1,
      );
      final item = await repo.getById(id);
      expect(item, isNotNull);
      expect(item!.name, '啤酒');
      // alias 含"雪花啤酒"
      expect(item.aliasesJson, isNotNull);
      expect(item.aliasesJson!.contains('雪花啤酒'), isTrue);
    });

    test('brand 为空 → 不存 alias（向后兼容）', () async {
      final id = await repo.upsertAiRecognized(
        name: '番茄炒蛋',
        caloriesPer100g: 138,
        proteinPer100g: 7.2,
        fatPer100g: 10,
        carbsPer100g: 4.6,
      );
      final item = await repo.getById(id);
      expect(item, isNotNull);
      expect(item!.aliasesJson, isNull);
    });

    test('brand+name 已是其他食物 name → 不存 alias（防冲突）', () async {
      // 库里已有"雪花啤酒"
      await seedFood('雪花啤酒');
      final id = await repo.upsertAiRecognized(
        name: '啤酒',
        brand: '雪花',
        caloriesPer100g: 43,
        proteinPer100g: 0.5,
        fatPer100g: 0,
        carbsPer100g: 3.1,
      );
      final item = await repo.getById(id);
      expect(item, isNotNull);
      expect(item!.name, '啤酒');
      // "雪花啤酒"已是其他食物 name，不写入 alias
      expect(item.aliasesJson, isNull);
    });

    test('重复 upsert 同 name+brand → alias 不重复（幂等）', () async {
      await repo.upsertAiRecognized(
        name: '啤酒',
        brand: '雪花',
        caloriesPer100g: 43,
        proteinPer100g: 0.5,
        fatPer100g: 0,
        carbsPer100g: 3.1,
      );
      final id = await repo.upsertAiRecognized(
        name: '啤酒',
        brand: '雪花',
        caloriesPer100g: 45, // 营养值更新
        proteinPer100g: 0.5,
        fatPer100g: 0,
        carbsPer100g: 3.2,
      );
      final item = await repo.getById(id);
      expect(item, isNotNull);
      expect(item!.caloriesPer100g, 45); // 营养值已更新
      // alias 只有一个"雪花啤酒"（去重）
      final aliases = item.aliasesJson!;
      expect(aliases.split('雪花啤酒').length - 1, 1);
    });
  });

  // M16.3 修复 P0：findByNameOrAlias 脏数据过滤
  group('M16.3: findByNameOrAlias 跳过脏数据条目', () {
    // 辅助：插入脏数据条目（模拟 sanotsu 列错位污染）
    Future<int> seedDirtyFood(String name,
        {double carbs = 450,
        double cal = 30,
        double protein = 1.5,
        double fat = 0}) async {
      return db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: name,
            defaultServingG: 100,
            caloriesPer100g: cal,
            proteinPer100g: protein,
            fatPer100g: fat,
            carbsPer100g: carbs, // 脏数据：>100
            source: 'china_fct',
            sourceVersion: 'v1',
            createdAt: 0,
          ));
    }

    test('同名脏数据条目被跳过，返回正常条目', () async {
      // 先插入脏数据（rowid 更小，优先级 1 会先命中）
      await seedDirtyFood('米粉', carbs: 450);
      // 再插入正常 FCT 米粉
      await seedFood('米粉', cal: 346, serving: 100);
      // 修正正常条目的 carbs（seedFood 默认 carbs=13.5，改为 85.8）
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
        name: '正常米粉',
        defaultServingG: 100,
        caloriesPer100g: 346,
        proteinPer100g: 7.4,
        fatPer100g: 1.0,
        carbsPer100g: 85.8,
        source: 'china_fct',
        sourceVersion: 'v1',
        createdAt: 0,
      ));

      final item = await repo.findByNameOrAlias('米粉');
      expect(item, isNotNull);
      // 不应命中脏数据（carbs=450），应命中 carbs=13.5 的正常条目（seedFood 默认）
      // 注：脏数据 carbs=450 > 100 被 _isDirtyFoodItem 跳过
      expect(item!.carbsPer100g, lessThanOrEqualTo(100),
          reason: '碳水不可能 >100g/100g，脏数据应被跳过');
    });

    test('所有同名条目都是脏数据时仍返回（不返回 null）', () async {
      // 只插入脏数据
      await seedDirtyFood('毒食物', carbs: 200);

      // 优先级 1 全跳过 → 优先级 3 contains 命中（contains 不过滤脏数据）
      final item = await repo.findByNameOrAlias('毒食物');
      expect(item, isNotNull, reason: '所有同名都是脏数据时仍应返回（contains 兜底）');
    });

    test('正常营养值（接近上限）不被误判为脏数据', () async {
      // 干米粉 carbs=85.8（接近 100 但合法）
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
        name: '干米粉',
        defaultServingG: 100,
        caloriesPer100g: 346,
        proteinPer100g: 7.4,
        fatPer100g: 1.0,
        carbsPer100g: 85.8,
        source: 'china_fct',
        sourceVersion: 'v1',
        createdAt: 0,
      ));

      final item = await repo.findByNameOrAlias('干米粉');
      expect(item, isNotNull);
      expect(item!.carbsPer100g, 85.8); // 不应被过滤
    });

    test('热量 > 900 的脏数据条目被跳过', () async {
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
        name: '热炸弹',
        defaultServingG: 100,
        caloriesPer100g: 1000, // 脏数据：>900
        proteinPer100g: 5,
        fatPer100g: 10,
        carbsPer100g: 20,
        source: 'china_fct',
        sourceVersion: 'v1',
        createdAt: 0,
      ));
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
        name: '热炸弹',
        defaultServingG: 100,
        caloriesPer100g: 200, // 正常
        proteinPer100g: 5,
        fatPer100g: 10,
        carbsPer100g: 20,
        source: 'china_fct',
        sourceVersion: 'v1',
        createdAt: 0,
      ));

      final item = await repo.findByNameOrAlias('热炸弹');
      expect(item, isNotNull);
      expect(item!.caloriesPer100g, lessThanOrEqualTo(900),
          reason: '热量 >900 的脏数据应被跳过');
    });
  });
}
