// test/data/food_seed_importer_alias_test.dart
import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/seed/food_seed_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EatWiseDatabase db;
  late FoodSeedImporter importer;

  setUp(() {
    // seedOnCreate=false：测试期望空 DB，跳过 wasCreated 的种子自动导入
    db = EatWiseDatabase(NativeDatabase.memory(), seedOnCreate: false);
    importer = FoodSeedImporter(db);
  });
  tearDown(() => db.close());

  test('supplementAliases 为番茄/马铃薯等写入 aliasesJson', () async {
    // 先插入几条食物
    const json = '''
[
  {"foodCode":"1","foodName":"番茄","edible":"97","energyKCal":"19","protein":"0.9","fat":"0.2","CHO":"4.0","water":"94"},
  {"foodCode":"2","foodName":"马铃薯","edible":"94","energyKCal":"76","protein":"2.0","fat":"0.1","CHO":"16.5","water":"79"},
  {"foodCode":"3","foodName":"鸡肉","edible":"66","energyKCal":"167","protein":"19.3","fat":"9.4","CHO":"1.3","water":"69"}
]
''';
    await importer.importFromJsonList(
        (jsonDecode(json) as List).cast<Map<String, dynamic>>());

    // 补充别名
    await importer.supplementAliases();

    final tomato = await importer.findByName('番茄');
    expect(tomato, isNotNull);
    expect(tomato!.aliasesJson, isNotNull);
    final aliases = jsonDecode(tomato.aliasesJson!) as List;
    expect(aliases, contains('西红柿'));

    final potato = await importer.findByName('马铃薯');
    expect(potato!.aliasesJson, isNotNull);
    expect((jsonDecode(potato.aliasesJson!) as List), contains('土豆'));
  });

  test('aliasesJson 为 null 时 supplementAliases 不报错', () async {
    // 无匹配项时不报错
    await importer.supplementAliases();
    // 无食物时正常通过
    expect((await db.foodItems.select().get()).length, 0);
  });

  test('assets/sanotsu_common.json 完整导入 ≥ 300 条', () async {
    final count = await importer.importFromAssets();
    expect(count, greaterThanOrEqualTo(300),
        reason: '完整常吃分类应 ≥300 条，实际 $count');
  });
}
