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
}
