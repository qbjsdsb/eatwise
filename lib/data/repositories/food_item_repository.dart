import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

class FoodItemRepository {
  final EatWiseDatabase _db;

  FoodItemRepository(this._db);

  /// 按 name 或 aliases 精确匹配（解决"西红柿/番茄"同物异名）
  Future<FoodItem?> findByNameOrAlias(String name) async {
    // 先精确匹配 name
    final byName = await (_db.foodItems.select()
          ..where((f) => f.name.equals(name))
          ..limit(1))
        .getSingleOrNull();
    if (byName != null) return byName;

    // 再遍历查 aliases_json（SQLite 无原生 JSON 查询，应用层过滤）
    final all = await _db.foodItems.select().get();
    for (final item in all) {
      if (item.aliasesJson == null) continue;
      // 简单包含匹配（MVP 够用，数据量小）
      if (item.aliasesJson!.contains('"$name"')) {
        return item;
      }
    }
    return null;
  }

  /// 插入或更新（去重键 name + source）
  Future<int> upsertAiRecognized({
    required String name,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double fatPer100g,
    required double carbsPer100g,
    double? confidence,
    String? componentsJson,
  }) async {
    final existing = await (_db.foodItems.select()
          ..where((f) => f.name.equals(name) & f.source.equals('ai_recognized')))
        .getSingleOrNull();

    if (existing != null) {
      await (_db.foodItems.update()..where((f) => f.id.equals(existing.id))).write(
        FoodItemsCompanion(
          caloriesPer100g: Value(caloriesPer100g),
          proteinPer100g: Value(proteinPer100g),
          fatPer100g: Value(fatPer100g),
          carbsPer100g: Value(carbsPer100g),
          confidence: Value(confidence),
        ),
      );
      return existing.id;
    }

    return _db.into(_db.foodItems).insert(FoodItemsCompanion.insert(
          name: name,
          defaultServingG: 100,
          caloriesPer100g: caloriesPer100g,
          proteinPer100g: proteinPer100g,
          fatPer100g: fatPer100g,
          carbsPer100g: carbsPer100g,
          source: 'ai_recognized',
          sourceVersion: 'ai',
          confidence: Value(confidence),
          componentsJson: Value(componentsJson),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
  }

  /// 模糊搜索食物（名称 LIKE，MVP 够用，数据量 ≤3000 条）
  Future<List<FoodItem>> searchByName(String keyword, {int limit = 50}) {
    return (_db.foodItems.select()
          ..where((f) => f.name.like('%$keyword%'))
          ..orderBy([(f) => OrderingTerm.asc(f.name)])
          ..limit(limit))
        .get();
  }

  /// 按 id 查询（今日记录页反查食物名用）
  Future<FoodItem?> getById(int id) {
    return (_db.foodItems.select()..where((f) => f.id.equals(id)))
        .getSingleOrNull();
  }

  /// 查询常用食物（按 meal_log 引用次数降序，取 top N）
  /// 用于食物库首页"常吃"列表
  /// 两步查询：typed food_items + 引用次数，Dart 层合并排序（避免 raw SQL 列名匹配问题）
  Future<List<FoodItem>> listFrequent({int limit = 20}) async {
    final allFoods = await _db.foodItems.select().get();
    if (allFoods.isEmpty) return [];

    // 查 meal_logs 引用次数（GROUP BY food_item_id）
    final refCounts = <int, int>{};
    final countRows = await _db.customSelect(
      'SELECT food_item_id, COUNT(id) AS cnt '
      'FROM meal_logs '
      'GROUP BY food_item_id',
      readsFrom: {_db.mealLogs},
    ).get();
    for (final row in countRows) {
      refCounts[row.read<int>('food_item_id')] = row.read<int>('cnt');
    }

    // 合并 + 排序（引用次数降序，同次数按 name 升序）+ 截断
    allFoods.sort((a, b) {
      final cntA = refCounts[a.id] ?? 0;
      final cntB = refCounts[b.id] ?? 0;
      if (cntA != cntB) return cntB.compareTo(cntA);
      return a.name.compareTo(b.name);
    });
    return allFoods.take(limit).toList();
  }

  /// 更新默认份量
  Future<void> updateDefaultServing(int id, double servingG) async {
    await (_db.foodItems.update()..where((f) => f.id.equals(id)))
        .write(FoodItemsCompanion(defaultServingG: Value(servingG)));
  }

  /// 更新营养素（仅 ai_recognized / manual 来源允许，UI 层控制）
  Future<void> updateNutrients({
    required int id,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double fatPer100g,
    required double carbsPer100g,
  }) async {
    await (_db.foodItems.update()..where((f) => f.id.equals(id))).write(
      FoodItemsCompanion(
        caloriesPer100g: Value(caloriesPer100g),
        proteinPer100g: Value(proteinPer100g),
        fatPer100g: Value(fatPer100g),
        carbsPer100g: Value(carbsPer100g),
      ),
    );
  }

  /// 手动录入新食物（source='manual'）
  /// T10 手动录入页"查不到→自定义→存库"用
  Future<int> insertManual({
    required String name,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double fatPer100g,
    required double carbsPer100g,
    double defaultServingG = 100,
  }) async {
    return _db.into(_db.foodItems).insert(FoodItemsCompanion.insert(
          name: name,
          defaultServingG: defaultServingG,
          caloriesPer100g: caloriesPer100g,
          proteinPer100g: proteinPer100g,
          fatPer100g: fatPer100g,
          carbsPer100g: carbsPer100g,
          source: 'manual',
          sourceVersion: 'manual',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
  }
}
