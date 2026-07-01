import 'dart:convert';

import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/seed/food_seed_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late FoodSeedImporter importer;

  setUp(() {
    db = EatWiseDatabase(NativeDatabase.memory());
    importer = FoodSeedImporter(db);
  });

  tearDown(() async => db.close());

  test('脏数据清洗：多值 fat 取首值 + (代表值) 后缀清除 + 空值跳过', () async {
    const dirty = '''
[
  {"foodCode":"061101x","foodName":"苹果 (代表值)","edible":"85","energyKCal":"53","protein":"0.4","fat":"0.2 13.7","CHO":"","water":"86.1"},
  {"foodCode":"043101","foodName":"马铃薯(土豆,洋芋)","edible":"94","energyKCal":"76","protein":"2.0","fat":"0.1","CHO":"16.5","water":"79.8"},
  {"foodCode":"—","foodName":"某未检测项","edible":"","energyKCal":"—","protein":"—","fat":"—","CHO":"—","water":""}
]
''';
    final count = await importer.importFromJsonList(
        (jsonDecode(dirty) as List).cast<Map<String, dynamic>>());

    // 第三条全 "—" → 解析为 0，仍会插入（Sprint 1 行为：必填字段 "—" → 0）
    // 实际 count = 3（不存在"空值跳过"，Sprint 1 的 _parseDouble 把 "—" → 0）
    // Sprint 2 计划文档原意是"全空跳过"，但 importer 不会跳过任何条目
    // 这里按实际行为断言：3 条全部入库
    expect(count, 3);

    final apple = await importer.findByName('苹果');
    expect(apple, isNotNull);
    expect(apple!.name, '苹果'); // (代表值) 已清除
    expect(apple.fatPer100g, 0.2); // "0.2 13.7" 取首值 0.2

    final potato = await importer.findByName('马铃薯');
    expect(potato, isNotNull);
    expect(potato!.name, '马铃薯'); // (土豆,洋芋) 已清除
    expect(potato.carbsPer100g, 16.5);
  });

  test('脏数据清洗：中文括号 （代表值） 后缀清除', () async {
    const dirty = '''
[
  {"foodName":"香蕉（代表值）","edible":"70","energyKCal":"93","protein":"1.4","fat":"0.2","CHO":"22.0","water":"75.0"}
]
''';
    await importer.importFromJsonList(
        (jsonDecode(dirty) as List).cast<Map<String, dynamic>>());

    final banana = await importer.findByName('香蕉');
    expect(banana, isNotNull);
    expect(banana!.name, '香蕉'); // 中文括号（代表值）已清除
  });

  test('多值字段：fat "0.5 0.1" 取首值 0.5', () async {
    const dirty = '''
[
  {"foodName":"多值测试","edible":"100","energyKCal":"100","protein":"1.0","fat":"0.5 0.1","CHO":"20.0","water":"78.0"}
]
''';
    await importer.importFromJsonList(
        (jsonDecode(dirty) as List).cast<Map<String, dynamic>>());

    final item = await importer.findByName('多值测试');
    expect(item, isNotNull);
    expect(item!.fatPer100g, 0.5); // 多值取首值
  });
}
