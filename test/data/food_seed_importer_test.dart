import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/seed/food_seed_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;

  setUp(() {
    db = EatWiseDatabase(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('解析 Sanotsu JSON：字段映射正确', () {
    final json = jsonDecode(File('test/fixtures/sanotsu_sample.json').readAsStringSync())
        as List<dynamic>;
    final items = FoodSeedImporter.parseJson(json.cast<Map<String, dynamic>>());

    expect(items.length, 4);

    // 番茄：去除 [西红柿] 后缀
    expect(items[0].name.value, '番茄');
    expect(items[0].caloriesPer100g.value, 18);
    expect(items[0].ediblePercent.value, 97);

    // 马铃薯：去除 (土豆,洋芋) 后缀
    expect(items[1].name.value, '马铃薯');
    expect(items[1].carbsPer100g.value, 16.5);

    // 花生油："—" → 0（protein_per_100g 非空，用 _parseDouble），"Tr" → 0.05
    expect(items[2].name.value, '花生油');
    expect(items[2].proteinPer100g.value, 0); // "—" → 0（非空字段）
    expect(items[2].carbsPer100g.value, 0.05);

    // 苹果：edible 空串 → null
    expect(items[3].name.value, '苹果');
    expect(items[3].ediblePercent.value, isNull);
  });

  test('导入到数据库：去重 + source 标注', () async {
    final json = jsonDecode(File('test/fixtures/sanotsu_sample.json').readAsStringSync())
        as List<dynamic>;
    final importer = FoodSeedImporter(db);

    final count = await importer.importFromJsonList(json.cast<Map<String, dynamic>>());
    expect(count, 4);

    final items = await db.foodItems.select().get();
    expect(items.length, 4);
    expect(items.every((i) => i.source == 'china_fct'), true);
    expect(items.every((i) => i.sourceVersion == 'china_fct_v6_251206'), true);
  });

  test('别名补充：番茄补充 aliases=["西红柿","tomato"]', () async {
    final json = jsonDecode(File('test/fixtures/sanotsu_sample.json').readAsStringSync())
        as List<dynamic>;
    final importer = FoodSeedImporter(db);
    await importer.importFromJsonList(json.cast<Map<String, dynamic>>());
    await importer.supplementAliases();

    final tomato = await (db.foodItems.select()
          ..where((f) => f.name.equals('番茄')))
        .getSingle();
    expect(tomato.aliasesJson, isNotNull);
    final aliases = jsonDecode(tomato.aliasesJson!) as List;
    expect(aliases, containsAll(['西红柿', 'tomato']));
  });

  test('重复导入：同 name+source 去重，更新而非新增', () async {
    final json = jsonDecode(File('test/fixtures/sanotsu_sample.json').readAsStringSync())
        as List<dynamic>;
    final importer = FoodSeedImporter(db);

    await importer.importFromJsonList(json.cast<Map<String, dynamic>>());
    await importer.importFromJsonList(json.cast<Map<String, dynamic>>());

    final items = await db.foodItems.select().get();
    expect(items.length, 4); // 仍是 4 条，非 8 条
  });
}
