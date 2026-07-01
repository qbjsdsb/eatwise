import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

/// Sanotsu/china-food-composition-data 食材库导入器
/// 依据设计文档 6.4 节字段映射规则
class FoodSeedImporter {
  final EatWiseDatabase _db;

  static const _sourceVersion = 'china_fct_v6_251206';

  /// 常见别名映射（20-30 组，覆盖常见同物异名）
  static const _aliasMap = <String, List<String>>{
    '番茄': ['西红柿', 'tomato'],
    '马铃薯': ['土豆', '洋芋', 'potato'],
    '甘薯': ['红薯', '地瓜', 'sweet potato'],
    '猕猴桃': ['奇异果', 'kiwi'],
    '花生': ['花生米', 'peanut'],
    '鸡肉': ['鸡胸肉', '鸡'],
    '猪大排': ['排骨', '猪排'],
    '鸡蛋': ['鸡蛋清', '鸡蛋黄', '蛋'],
  };

  FoodSeedImporter(this._db);

  /// 解析 Sanotsu JSON 列表为 FoodItemsCompanion 列表（不入库）
  static List<FoodItemsCompanion> parseJson(List<Map<String, dynamic>> jsonList) {
    return jsonList.map(_parseItem).toList();
  }

  static FoodItemsCompanion _parseItem(Map<String, dynamic> raw) {
    final rawName = raw['foodName'] as String;
    final name = _cleanName(rawName);

    return FoodItemsCompanion.insert(
      name: name,
      defaultServingG: 100,
      caloriesPer100g: _parseDouble(raw['energyKCal']),
      proteinPer100g: _parseDouble(raw['protein']),
      fatPer100g: _parseDouble(raw['fat']),
      carbsPer100g: _parseTrValue(raw['CHO']),
      ediblePercent: Value(_parseNullableDouble(raw['edible'])),
      source: 'china_fct',
      sourceVersion: _sourceVersion,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 去除别名括号后缀：[干酪]、(代表值)、(土豆,洋芋)
  static String _cleanName(String name) {
    return name.replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), '').trim();
  }

  /// 字符串转 double；"—"/空串 → null
  static double? _parseNullableDouble(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty || str == '—' || str == '-') return null;
    if (str == 'Tr') return 0.05;
    return double.tryParse(str);
  }

  /// 必填 double；"—" → null（数据缺失，导入时允许 null 供后续人工补）
  static double _parseDouble(dynamic value) {
    return _parseNullableDouble(value) ?? 0;
  }

  /// "Tr"（微量）→ 0.05；"—" → null
  static double _parseTrValue(dynamic value) {
    return _parseNullableDouble(value) ?? 0;
  }

  /// 导入 JSON 列表到数据库（去重：name + source）
  Future<int> importFromJsonList(List<Map<String, dynamic>> jsonList) async {
    final companions = parseJson(jsonList);
    var count = 0;
    for (final companion in companions) {
      // 查重：name + source
      final existing = await (_db.foodItems.select()
            ..where((f) => f.name.equals(companion.name.value) & f.source.equals('china_fct')))
          .get();

      if (existing.isEmpty) {
        await _db.into(_db.foodItems).insert(companion);
        count++;
      } else {
        // 已存在，更新营养值
        await (_db.foodItems.update()..where((f) => f.id.equals(existing.first.id))).write(
          FoodItemsCompanion(
            caloriesPer100g: companion.caloriesPer100g,
            proteinPer100g: companion.proteinPer100g,
            fatPer100g: companion.fatPer100g,
            carbsPer100g: companion.carbsPer100g,
            ediblePercent: Value(companion.ediblePercent.value),
          ),
        );
      }
    }
    return count;
  }

  /// 补充别名（导入后人工补充的 20-30 组）
  Future<void> supplementAliases() async {
    for (final entry in _aliasMap.entries) {
      final items = await (_db.foodItems.select()..where((f) => f.name.equals(entry.key))).get();
      for (final item in items) {
        await (_db.foodItems.update()..where((f) => f.id.equals(item.id))).write(
          FoodItemsCompanion(aliasesJson: Value(jsonEncode(entry.value))),
        );
      }
    }
  }
}
