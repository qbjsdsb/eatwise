import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

class FoodItemRepository {
  final EatWiseDatabase _db;

  FoodItemRepository(this._db);

  /// 按 name 或 aliases 多级模糊匹配（解决"可口可乐/可乐/cola"同物异名 + 品牌前缀/量词/typo）
  ///
  /// P1-2 brand 字段参与匹配：[brand] 非空时，先尝试 "brand+name"（如"喜茶多肉葡萄"）
  /// 精确匹配连锁品牌库条目（source='chain_brand'），命中则直接返回（优先级 0）。
  /// 未命中再走原 5 级 name/alias 匹配。brand 为空时行为不变（向后兼容）。
  ///
  /// M16.3 修复 P0：优先级 1/2 加脏数据过滤——营养素不可能值（>100g/100g）的条目
  /// 跳过，避免同名脏条目（如"米粉（贝因美）"CHO=450 经 _cleanName 后与 FCT"米粉"
  /// 撞名）被优先命中污染复合菜营养计算。脏数据通过 migration v4 已清理入库的，
  /// 此过滤是双保险防新脏数据。
  ///
  /// 6 级优先级（防假阳性，逐级降级）：
  /// 0. brand+name 精确（仅 brand 非空时，命中连锁品牌库条目）
  /// 1. name 精确（归一化后，跳过脏数据）
  /// 2. alias 精确（归一化后，跳过脏数据）
  /// 3. name 双向 contains + 长度约束（防"可乐"误命中"可乐鸡翅"）
  /// 4. alias 双向 contains + 长度约束
  /// 5. name 编辑距离 ≤1（仅短名 ≤8 字，typo 容错，如"可东"→"可乐"）
  ///
  /// 归一化：去空白 + 小写（中文不受影响）。1714 条全表遍历 <50ms。
  Future<FoodItem?> findByNameOrAlias(String name, {String brand = ''}) async {
    final query = _normalize(name);
    if (query.isEmpty) return null;

    final all = await _db.foodItems.select().get();
    if (all.isEmpty) return null;

    // 优先级 0：brand+name 精确匹配（P1-2，命中连锁品牌库条目）
    // 如 brand="喜茶"+name="多肉葡萄" → 精确查"喜茶多肉葡萄"
    // 比 name 精确优先级高，避免"奶茶"（通用条目）抢先命中"喜茶奶茶"
    final cleanBrand = brand.trim();
    if (cleanBrand.isNotEmpty) {
      final combined = _normalize('$cleanBrand$name');
      if (combined.isNotEmpty) {
        for (final item in all) {
          if (_normalize(item.name) == combined) return item;
        }
        // brand+name 也可能是某条目的 alias（如 alias="多肉葡萄"但用户传 brand+name）
        for (final item in all) {
          for (final a in _decodeAliases(item.aliasesJson)) {
            if (_normalize(a) == combined) return item;
          }
        }
      }
    }

    // 优先级 1：name 精确（M16.3：跳过脏数据条目）
    for (final item in all) {
      if (_normalize(item.name) == query && !_isDirtyFoodItem(item)) return item;
    }
    // 优先级 2：alias 精确（M16.3：跳过脏数据条目）
    for (final item in all) {
      if (_isDirtyFoodItem(item)) continue;
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
    // 优先级 5：name 编辑距离 ≤1（仅 typo 容错，如"可东"→"可乐"）
    // 加严约束（防"雪花"→"雪碧"假阳性）：
    //   ① query 长度 ≥3：2 字短名编辑距离 1 极易假阳性（雪花/雪碧、黄瓜/鸡蛋），禁用
    //   ② target 与 query 等长：编辑距离只容错单字 typo，不容错"长度不同的相近名"
    if (query.length >= 3 && query.length <= 8) {
      FoodItem? editHit;
      int best = 2;
      for (final item in all) {
        final n = _normalize(item.name);
        if (n.length != query.length) continue; // 等长才比，避免长短名互相干扰
        final d = _editDistance(query, n);
        if (d < best) {
          best = d;
          editHit = item;
        }
      }
      if (editHit != null) return editHit;
    }
    return null;
  }

  /// M16.3 修复 P0：检测食物条目是否为脏数据
  /// 营养素不可能值（每 100g）：
  /// - 蛋白质/脂肪/碳水 > 100（单值不可能超 100g/100g）
  /// - 热量 > 900（纯脂肪 9 kcal/g × 100g = 900，不可能更高）
  /// 违反任一规则视为脏数据，findByNameOrAlias 跳过避免污染营养计算
  bool _isDirtyFoodItem(FoodItem item) {
    if (item.proteinPer100g > 100) return true;
    if (item.fatPer100g > 100) return true;
    if (item.carbsPer100g > 100) return true;
    if (item.caloriesPer100g > 900) return true;
    return false;
  }

  /// 精确匹配（仅 name/alias 归一化后相等，不走模糊）。
  /// 供反馈回流 [addAlias] 使用：只有用户纠正名精确命中库中某条记录，
  /// 才把 AI 错误名作为该记录别名写入，避免模糊命中错对象导致反向错配
  /// （如"雪花啤酒"模糊命中"雪碧"后把"雪碧"写成雪碧的别名 → 永久错配）。
  Future<FoodItem?> findExactByNameOrAlias(String name) async {
    final query = _normalize(name);
    if (query.isEmpty) return null;
    final all = await _db.foodItems.select().get();
    for (final item in all) {
      if (_normalize(item.name) == query) return item;
    }
    for (final item in all) {
      for (final a in _decodeAliases(item.aliasesJson)) {
        if (_normalize(a) == query) return item;
      }
    }
    return null;
  }

  /// 归一化：全角→半角 + 去空白 + 小写
  /// 全角转换：避免 AI 返回全角数字/字母/括号导致精确匹配 miss 而降级模糊匹配
  /// （如"雪碧"全角 vs 半角，精确不命中 → 编辑距离误命中他菜）
  String _normalize(String s) {
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final code = s.codeUnitAt(i);
      if (code == 0x3000) {
        buf.write(' '); // 全角空格
      } else if ((code >= 0xFF10 && code <= 0xFF19) ||
          (code >= 0xFF21 && code <= 0xFF3A) ||
          (code >= 0xFF41 && code <= 0xFF5A)) {
        buf.writeCharCode(code - 0xFEE0); // 全角数字/字母→半角
      } else if (s[i] == '（') {
        buf.write('(');
      } else if (s[i] == '）') {
        buf.write(')');
      } else {
        buf.write(s[i]);
      }
    }
    return buf.toString().replaceAll(RegExp(r'\s'), '').toLowerCase();
  }

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

  /// 批次 3：给指定 food_item 添加别名（去重，事务包裹）
  ///
  /// 用于反馈闭环回流：用户点"识别不准"并填正确菜名后，把 AI 错误识别名
  /// 作为正确菜的别名写入 aliasesJson。下次 AI 识别返回错误名时，
  /// findByNameOrAlias 命中别名，直接返回正确菜的营养数据（无需用户再纠正）。
  ///
  /// 去重规则：归一化后与 name + 现有别名比较，已存在则跳过（幂等）。
  ///
  /// 冲突检测（v3 新增，防反向错配第二道防线）：若该别名已是其他食物的
  /// name 或别名，则不写入。否则会把"AI 错误名"绑定到多个食物，下次精确
  /// 匹配会命中第一个 → 永久错配且无法自愈。findExactByNameOrAlias 是第一道
  /// 防线（调用方用精确匹配查"正确菜"），此为第二道（写入前再校验全局唯一）。
  Future<void> addAlias(int foodItemId, String alias) async {
    final cleanAlias = alias.trim();
    if (cleanAlias.isEmpty) return;
    final normalized = _normalize(cleanAlias);
    return _db.transaction(() async {
      final item = await (_db.foodItems.select()
            ..where((f) => f.id.equals(foodItemId)))
          .getSingleOrNull();
      if (item == null) return;
      // 去重：已是 name 或已有别名则跳过（归一化比较，防大小写/空格差异）
      if (_normalize(item.name) == normalized) return;
      final existing = _decodeAliases(item.aliasesJson);
      if (existing.any((a) => _normalize(a) == normalized)) return;

      // 冲突检测：遍历全表，若该别名已是其他食物的 name 或别名，拒绝写入
      // （防止反馈回流把同一个错误名绑到多个食物导致永久错配）
      final all = await _db.foodItems.select().get();
      for (final other in all) {
        if (other.id == foodItemId) continue; // 跳过自己
        if (_normalize(other.name) == normalized) return; // 已是其他食物 name
        final otherAliases = _decodeAliases(other.aliasesJson);
        if (otherAliases.any((a) => _normalize(a) == normalized)) return;
      }

      final updated = [...existing, cleanAlias];
      await (_db.foodItems.update()..where((f) => f.id.equals(foodItemId)))
          .write(FoodItemsCompanion(
        aliasesJson: Value(jsonEncode(updated)),
      ));
    });
  }

  /// 插入或更新（去重键 name + source）
  /// 事务包裹：select-then-insert 原子化，防并发产生重复记录
  /// name 空串兜底为"未命名菜品"，避免 AI 返回空 dish_name 时落库空名记录污染列表
  ///
  /// P0-3 brand 持久化：[brand] 非空时，把 "品牌+菜名"（如"雪花啤酒"）存为 alias，
  /// 下次 AI 返回完整品牌名时精确命中别名，不重复估。brand 与 name 相同/为空则不存。
  /// 冲突检测：brand+name 若已是其他食物的 name/alias，跳过（防反向错配，与 addAlias 一致）。
  Future<int> upsertAiRecognized({
    required String name,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double fatPer100g,
    required double carbsPer100g,
    double? confidence,
    String? componentsJson,
    String brand = '',
  }) async {
    final cleanName = name.trim().isEmpty ? '未命名菜品' : name.trim();
    final cleanBrand = brand.trim();
    // 构造 brand+name 别名（如"雪花啤酒"），用于精确命中
    String? brandAlias;
    if (cleanBrand.isNotEmpty && cleanBrand != cleanName) {
      final combined = '$cleanBrand$cleanName';
      if (combined != cleanName) brandAlias = combined;
    }

    return _db.transaction(() async {
      final existing = await (_db.foodItems.select()
            ..where((f) => f.name.equals(cleanName) & f.source.equals('ai_recognized')))
          .getSingleOrNull();

      if (existing != null) {
        // 更新营养素 + 合并 brand 别名（去重 + 冲突检测）
        final existingAliases = _decodeAliases(existing.aliasesJson);
        final mergedAliases = await _mergeAliasSafely(existingAliases, brandAlias, existing.name, existing.id);
        await (_db.foodItems.update()..where((f) => f.id.equals(existing.id))).write(
          FoodItemsCompanion(
            caloriesPer100g: Value(caloriesPer100g),
            proteinPer100g: Value(proteinPer100g),
            fatPer100g: Value(fatPer100g),
            carbsPer100g: Value(carbsPer100g),
            confidence: Value(confidence),
            componentsJson: Value(componentsJson),
            aliasesJson: Value(mergedAliases == null ? null : jsonEncode(mergedAliases)),
          ),
        );
        return existing.id;
      }

      // 新建记录：brand 别名先做冲突检测（防与已有食物 name/alias 冲突）
      List<String>? initAliases;
      // 把 brandAlias 提升为 non-null 局部变量，避免跨事务闭包的 flow analysis 失效
      // （Dart 3.10+ 更严格的 null safety 检查：闭包内的 if (x != null) 不能提升外部 ?）
      final brandAliasNonNull = brandAlias;
      if (brandAliasNonNull != null) {
        final all = await _db.foodItems.select().get();
        final occupied = <String>{};
        for (final other in all) {
          occupied.add(_normalize(other.name));
          for (final a in _decodeAliases(other.aliasesJson)) {
            occupied.add(_normalize(a));
          }
        }
        if (!occupied.contains(_normalize(brandAliasNonNull))) {
          initAliases = [brandAliasNonNull];
        }
      }

      return _db.into(_db.foodItems).insert(FoodItemsCompanion.insert(
            name: cleanName,
            defaultServingG: 100,
            caloriesPer100g: caloriesPer100g,
            proteinPer100g: proteinPer100g,
            fatPer100g: fatPer100g,
            carbsPer100g: carbsPer100g,
            aliasesJson: Value(initAliases == null || initAliases.isEmpty
                ? null
                : jsonEncode(initAliases)),
            source: 'ai_recognized',
            sourceVersion: 'ai',
            confidence: Value(confidence),
            componentsJson: Value(componentsJson),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
    });
  }

  /// 合并别名（去重 + 冲突检测），用于 upsert 更新已有记录时追加 brand 别名。
  /// 返回合并后的别名列表（可能为空 null），调用方写库前判断。
  /// 冲突检测：新别名若已是其他食物的 name/alias，不加入（防反向错配）。
  Future<List<String>?> _mergeAliasSafely(
    List<String> existingAliases,
    String? newAlias,
    String selfName,
    int selfId,
  ) async {
    if (newAlias == null || newAlias.isEmpty) {
      return existingAliases.isEmpty ? null : existingAliases;
    }
    final normalizedNew = _normalize(newAlias);
    // 已是自身 name 或已有别名 → 不重复加
    if (_normalize(selfName) == normalizedNew) {
      return existingAliases.isEmpty ? null : existingAliases;
    }
    if (existingAliases.any((a) => _normalize(a) == normalizedNew)) {
      return existingAliases.isEmpty ? null : existingAliases;
    }
    // 冲突检测：遍历全表（事务内已锁），若已是其他食物 name/alias 不加
    final all = await _db.foodItems.select().get();
    for (final other in all) {
      if (other.id == selfId) continue;
      if (_normalize(other.name) == normalizedNew) {
        return existingAliases.isEmpty ? null : existingAliases;
      }
      for (final a in _decodeAliases(other.aliasesJson)) {
        if (_normalize(a) == normalizedNew) {
          return existingAliases.isEmpty ? null : existingAliases;
        }
      }
    }
    return [...existingAliases, newAlias];
  }

  /// 模糊搜索食物（名称 + 别名 LIKE，v1.9 支持品牌名搜索）
  /// food_item 表无 brand 字段（brand 在 VisionRecognitionResult 内存层），
  /// 但 brand 会通过 upsertAiRecognized 写入 aliasesJson（别名存品牌名），
  /// 所以搜品牌名能命中别名。例：搜"农夫山泉"能找到 aliases 含"农夫山泉"的食物。
  Future<List<FoodItem>> searchByName(String keyword, {int limit = 50}) {
    final kw = '%$keyword%';
    return (_db.foodItems.select()
          ..where((f) => f.name.like(kw) | f.aliasesJson.like(kw))
          ..orderBy([(f) => OrderingTerm.asc(f.name)])
          ..limit(limit))
        .get();
  }

  /// 按 id 查询（今日记录页反查食物名用）
  Future<FoodItem?> getById(int id) {
    return (_db.foodItems.select()..where((f) => f.id.equals(id)))
        .getSingleOrNull();
  }

  /// 批量按 id 查询（首屏/明细页反查食物名，避免 N+1 逐条 getById）
  /// 用 SQL `id IN (...)` 一次查回，N 条 meal 只需 1 次 DB 往返
  Future<List<FoodItem>> getByIds(List<int> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (_db.foodItems.select()..where((f) => f.id.isIn(ids))).get();
  }

  /// 查询常用食物（按 meal_log 引用次数降序，取 top N）
  /// 用于食物库首页"常吃"列表
  /// 仅返回被 meal_log 引用过的食物（refCount > 0），避免种子库 0 引用项混入
  Future<List<FoodItem>> listFrequent({int limit = 20}) async {
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
    if (refCounts.isEmpty) return [];

    // 仅查被引用过的 food_items（避免全表载入 0 引用种子项）
    final referencedIds = refCounts.keys.toList();
    final foods = await (_db.foodItems.select()
          ..where((f) => f.id.isIn(referencedIds)))
        .get();
    if (foods.isEmpty) return [];

    // 排序（引用次数降序，同次数按 name 升序）+ 截断
    foods.sort((a, b) {
      final cntA = refCounts[a.id] ?? 0;
      final cntB = refCounts[b.id] ?? 0;
      if (cntA != cntB) return cntB.compareTo(cntA);
      return a.name.compareTo(b.name);
    });
    return foods.take(limit).toList();
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
  ///
  /// 冲突检测（与 addAlias 一致，防反向错配）：写入前遍历全表，剔除已是其他食物
  /// name/alias 的别名。否则同一 AI 错误名会绑到多个食物，findByNameOrAlias 精确
  /// 命中第一个 → 永久错配无法自愈。
  Future<int> insertManual({
    required String name,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double fatPer100g,
    required double carbsPer100g,
    double defaultServingG = 100,
    List<String>? aliases,
  }) async {
    // aliases 冲突检测：剔除已是其他食物 name/alias 的别名（与 addAlias 第二道防线一致）
    List<String>? safeAliases;
    if (aliases != null && aliases.isNotEmpty) {
      final normalizedSelf = _normalize(name);
      final all = await _db.foodItems.select().get();
      final occupied = <String>{};
      for (final other in all) {
        occupied.add(_normalize(other.name));
        for (final a in _decodeAliases(other.aliasesJson)) {
          occupied.add(_normalize(a));
        }
      }
      safeAliases = aliases
          .where((a) {
            final n = _normalize(a);
            // 跳过与自身 name 相同的（自引用防护）+ 已被占用的（冲突检测）
            return n != normalizedSelf && !occupied.contains(n);
          })
          .toList();
      if (safeAliases.isEmpty) safeAliases = null;
    }
    return _db.into(_db.foodItems).insert(FoodItemsCompanion.insert(
          name: name,
          defaultServingG: defaultServingG,
          caloriesPer100g: caloriesPer100g,
          proteinPer100g: proteinPer100g,
          fatPer100g: fatPer100g,
          carbsPer100g: carbsPer100g,
          aliasesJson: Value(safeAliases == null || safeAliases.isEmpty
              ? null
              : jsonEncode(safeAliases)),
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
