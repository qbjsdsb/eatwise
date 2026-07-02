import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

class FoodItemRepository {
  final EatWiseDatabase _db;

  FoodItemRepository(this._db);

  /// 按 name 或 aliases 多级模糊匹配（解决"可口可乐/可乐/cola"同物异名 + 品牌前缀/量词/typo）
  ///
  /// 5 级优先级（防假阳性，逐级降级）：
  /// 1. name 精确（归一化后）
  /// 2. alias 精确（归一化后）
  /// 3. name 双向 contains + 长度约束（防"可乐"误命中"可乐鸡翅"）
  /// 4. alias 双向 contains + 长度约束
  /// 5. name 编辑距离 ≤1（仅短名 ≤8 字，typo 容错，如"可东"→"可乐"）
  ///
  /// 归一化：去空白 + 小写（中文不受影响）。1714 条全表遍历 <50ms。
  Future<FoodItem?> findByNameOrAlias(String name) async {
    final query = _normalize(name);
    if (query.isEmpty) return null;

    final all = await _db.foodItems.select().get();
    if (all.isEmpty) return null;

    // 优先级 1：name 精确
    for (final item in all) {
      if (_normalize(item.name) == query) return item;
    }
    // 优先级 2：alias 精确
    for (final item in all) {
      for (final a in _decodeAliases(item.aliasesJson)) {
        if (_normalize(a) == query) return item;
      }
    }
    // 优先级 3：name 双向 contains（取长度差最小者）
    FoodItem? containsHit;
    int containsDiff = 1 << 30;
    for (final item in all) {
      final n = _normalize(item.name);
      final diff = _containsLenDiff(query, n);
      if (diff != null && diff < containsDiff) {
        containsDiff = diff;
        containsHit = item;
      }
    }
    if (containsHit != null) return containsHit;
    // 优先级 4：alias 双向 contains（首个命中即可）
    for (final item in all) {
      for (final a in _decodeAliases(item.aliasesJson)) {
        if (_containsLenDiff(query, _normalize(a)) != null) return item;
      }
    }
    // 优先级 5：name 编辑距离 ≤1（仅短名 typo 容错，如"可东"→"可乐"）
    // 阈值 1 非 2：避免 2 字短名互相假阳性（如"黄瓜"→"鸡肉"编辑距离恰好 2）
    if (query.length <= 8) {
      FoodItem? editHit;
      int best = 2;
      for (final item in all) {
        final d = _editDistance(query, _normalize(item.name));
        if (d < best) {
          best = d;
          editHit = item;
        }
      }
      if (editHit != null) return editHit;
    }
    return null;
  }

  /// 归一化：去空白 + 小写
  String _normalize(String s) => s.replaceAll(RegExp(r'\s'), '').toLowerCase();

  /// 解析 aliasesJson 为字符串列表（容错）
  List<String> _decodeAliases(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final l = jsonDecode(json);
      if (l is List) return l.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }

  /// 双向 contains + 长度约束（防假阳性）
  /// 返回长度差（小者优先）；不满足约束返回 null
  /// 约束：长度差 ≤2 且 较长者 ≤ 较短者×2+1（防"可乐"命中"可乐鸡翅肉"等过长名）
  int? _containsLenDiff(String query, String target) {
    if (query.isEmpty || target.isEmpty) return null;
    final qInT = target.contains(query);
    final tInQ = query.contains(target);
    if (!qInT && !tInQ) return null;
    final diff = (target.length - query.length).abs();
    final shorter = target.length > query.length ? query.length : target.length;
    final longer = target.length > query.length ? target.length : query.length;
    if (diff > 2 || longer > shorter * 2 + 1) return null;
    return diff;
  }

  /// 莱文斯坦编辑距离（标准 DP）
  int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = a.length, n = b.length;
    final prev = List<int>.generate(n + 1, (j) => j);
    final curr = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      }
      prev.setRange(0, n + 1, curr);
    }
    return prev[n];
  }

  /// 插入或更新（去重键 name + source）
  /// 事务包裹：select-then-insert 原子化，防并发产生重复记录
  Future<int> upsertAiRecognized({
    required String name,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double fatPer100g,
    required double carbsPer100g,
    double? confidence,
    String? componentsJson,
  }) async {
    return _db.transaction(() async {
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
    });
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

  /// 查询全部食物（推荐算法用，遍历全库按缺口评分）
  /// 排除 source='ai_recognized'（复合菜，无 per100g 密度，不适合推荐）
  Future<List<FoodItem>> listAllForRecommendation() async {
    return (_db.foodItems.select()
          ..where((f) => f.source.isNotIn(['ai_recognized']))
          ..orderBy([(f) => OrderingTerm.asc(f.name)]))
        .get();
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
  /// aliases：可选别名列表（如模型返回的原始菜名，用于自动学习，下次识别同名自动命中）
  Future<int> insertManual({
    required String name,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double fatPer100g,
    required double carbsPer100g,
    double defaultServingG = 100,
    List<String>? aliases,
  }) async {
    return _db.into(_db.foodItems).insert(FoodItemsCompanion.insert(
          name: name,
          defaultServingG: defaultServingG,
          caloriesPer100g: caloriesPer100g,
          proteinPer100g: proteinPer100g,
          fatPer100g: fatPer100g,
          carbsPer100g: carbsPer100g,
          aliasesJson: Value(
              aliases == null || aliases.isEmpty ? null : jsonEncode(aliases)),
          source: 'manual',
          sourceVersion: 'manual',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
  }

  /// OFF 云查命中落库（source='off'）
  /// aliases 传入菜名本身，下次同名精确命中（避免重复云查）
  Future<int> insertOff({
    required String name,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double fatPer100g,
    required double carbsPer100g,
    double defaultServingG = 100,
    List<String>? aliases,
  }) async {
    return _db.into(_db.foodItems).insert(FoodItemsCompanion.insert(
          name: name,
          defaultServingG: defaultServingG,
          caloriesPer100g: caloriesPer100g,
          proteinPer100g: proteinPer100g,
          fatPer100g: fatPer100g,
          carbsPer100g: carbsPer100g,
          aliasesJson: Value(
              aliases == null || aliases.isEmpty ? null : jsonEncode(aliases)),
          source: 'off',
          sourceVersion: 'off_v1',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
  }
}
