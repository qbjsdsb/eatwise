import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Sanotsu/china-food-composition-data 食材库导入器
/// 依据设计文档 6.4 节字段映射规则
class FoodSeedImporter {
  final EatWiseDatabase _db;

  static const _sourceVersion = 'china_fct_v6_251206';

  /// 常见别名映射（20-30 组，覆盖常见同物异名）
  /// Sprint 3 T18：扩充至 22 组（合并计划中重复的 '茄子' key）
  static const _aliasMap = <String, List<String>>{
    // 蔬菜类
    '番茄': ['西红柿', 'tomato'],
    '马铃薯': ['土豆', '洋芋', 'potato'],
    '甘薯': ['红薯', '地瓜', 'sweet potato'],
    '胡萝卜': ['红萝卜', 'carrot'],
    '辣椒': ['尖椒', 'chili'],
    '茄子': ['矮瓜', 'eggplant'],
    '白菜': ['大白菜', '黄芽白'],
    '油菜': ['上海青', '青菜'],
    '黄瓜': ['青瓜', 'cucumber'],
    // 水果类
    '猕猴桃': ['奇异果', 'kiwi'],
    '草莓': ['士多啤梨', 'strawberry'],
    '葡萄': ['提子', 'grape'],
    '菠萝': ['凤梨', 'pineapple'],
    '柚': ['柚子', '文旦'],
    // 谷薯豆类
    '玉米': ['苞谷', '苞米', 'corn'],
    '大豆': ['黄豆', 'soybean'],
    '花生': ['花生米', 'peanut'],
    // 肉蛋奶类
    '鸡肉': ['鸡胸肉', '鸡'],
    '猪大排': ['排骨', '猪排'],
    '鸡蛋': ['鸡蛋清', '鸡蛋黄', '蛋'],
    '牛乳': ['牛奶', 'milk'],
    // 水产类
    '草鱼': ['鲩鱼'],
    '对虾': ['大虾', '明虾'],
    // 调味/油脂
    '芝麻': ['胡麻', 'sesame'],
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

  /// 去除别名括号后缀：[干酪]、(代表值)、(土豆,洋芋)、（代表值）
  /// Sprint 2 T0：扩展支持中文括号 （），原 Sprint 1 只支持 [] ()
  static String _cleanName(String name) {
    return name
        .replaceAll(RegExp(r'\s*[\[\(（][^\]\)）]*[\]\)）]\s*'), '')
        .trim();
  }

  /// 字符串转 double；"—"/空串 → null
  /// Sprint 2 T0：扩展支持多值字段（如 fat:"0.2 13.7" → 0.2，取第一个空格前的值）
  /// Sanotsu 完整版 fat 字段偶尔挤入"脂肪+饱和脂肪"两值
  static double? _parseNullableDouble(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty || str == '—' || str == '-') return null;
    if (str == 'Tr') return 0.05; // 微量
    // 多值字段取第一个空格前的值（兼容单值场景）
    final firstValue = str.split(RegExp(r'\s+')).first;
    return double.tryParse(firstValue);
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

  /// 按名称查食物（Sprint 2 T0：测试用）
  Future<FoodItem?> findByName(String name) {
    return (_db.foodItems.select()..where((f) => f.name.equals(name)))
        .getSingleOrNull();
  }

  /// 从 assets/sanotsu_common.json 导入常吃食物种子数据
  /// Sprint 2 T0：App 首次启动时若 food_items 表为空则调用此方法
  ///
  /// assets 文件来源：Sanotsu/china-food-composition-data 仓库常吃分类
  /// （Sprint 2 因 GitHub API 限流，先用 12 条常吃食物种子，完整版留作增强）
  Future<int> importFromAssets() async {
    final jsonStr = await rootBundle.loadString('assets/sanotsu_common.json');
    final jsonList = (jsonDecode(jsonStr) as List).cast<Map<String, dynamic>>();
    return importFromJsonList(jsonList);
  }

  /// 首次安装批量导入（batch 事务，跳过查重，性能优）
  /// 仅在 food_items 表为空时调用（database wasCreated）。
  /// importFromJsonList 逐条 select 查重 + insert，1664 条要 3300+ 次 SQL，
  /// 首次启动卡 5-10s；本方法用 batch 一次事务提交，<1s。
  /// 首次导入表必然空，无需查重。
  Future<int> importFromAssetsFirstTime() async {
    final jsonStr = await rootBundle.loadString('assets/sanotsu_common.json');
    final jsonList = (jsonDecode(jsonStr) as List).cast<Map<String, dynamic>>();
    final companions = parseJson(jsonList);
    await _db.batch((b) {
      for (final c in companions) {
        b.insert(_db.foodItems, c);
      }
    });
    return companions.length;
  }

  /// 首次安装批量导入品牌饮料/零食（assets/brand_foods.json）
  /// 50 条高频品牌食品（可乐/雪碧/果汁/奶茶/薯片等，USDA 公开值），
  /// 每条自带 aliases 数组（可口可乐/百事可乐/cola 等品牌别名）。
  /// 补足 FCT 数据源无饮料类的缺口。
  Future<int> importBrandFoodsFirstTime() async {
    final jsonStr = await rootBundle.loadString('assets/brand_foods.json');
    final jsonList = (jsonDecode(jsonStr) as List).cast<Map<String, dynamic>>();
    await _db.batch((b) {
      for (final raw in jsonList) {
        final aliases = (raw['aliases'] as List?)?.cast<String>() ?? const [];
        b.insert(_db.foodItems, FoodItemsCompanion.insert(
          name: raw['name'] as String,
          defaultServingG: (raw['defaultServingG'] as num).toDouble(),
          caloriesPer100g: (raw['caloriesPer100g'] as num).toDouble(),
          proteinPer100g: (raw['proteinPer100g'] as num).toDouble(),
          fatPer100g: (raw['fatPer100g'] as num).toDouble(),
          carbsPer100g: (raw['carbsPer100g'] as num).toDouble(),
          aliasesJson: Value(aliases.isEmpty ? null : jsonEncode(aliases)),
          source: 'usda_brand',
          sourceVersion: 'usda_brand_v1',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    });
    return jsonList.length;
  }
}
