import 'package:eatwise/data/database/database.dart';
import 'package:drift/drift.dart';
import 'package:eatwise/core/util/date_format.dart';

class MealLogRepository {
  final EatWiseDatabase _db;

  MealLogRepository(this._db);

  Future<int> insertMealLog({
    required String date,
    required String mealType,
    required int foodItemId,
    required double actualServingG,
    required double actualCalories,
    required double actualProteinG,
    required double actualFatG,
    required double actualCarbsG,
    String? originalImagePath,
    double? recognitionConfidence,
    String? componentsSnapshotJson,
  }) async {
    // 哨兵防御：foodItemId=0 是 AI 兜底哨兵，写库前必须调 upsertAiRecognized 替换为真实 id，
    // 否则 SQLite FK 约束违规崩溃。提前抛清晰错误便于定位。
    if (foodItemId <= 0) {
      throw ArgumentError('foodItemId 必须为真实 id，不能是 0 哨兵');
    }
    return _db.into(_db.mealLogs).insert(MealLogsCompanion.insert(
          date: date,
          mealType: mealType,
          foodItemId: foodItemId,
          actualServingG: actualServingG,
          actualCalories: actualCalories,
          actualProteinG: actualProteinG,
          actualFatG: actualFatG,
          actualCarbsG: actualCarbsG,
          originalImagePath: Value(originalImagePath),
          recognitionConfidence: Value(recognitionConfidence),
          componentsSnapshotJson: Value(componentsSnapshotJson),
          loggedAt: DateTime.now().millisecondsSinceEpoch,
        ));
  }

  /// 查询某日全部记录
  Future<List<MealLog>> getMealsByDate(String date) {
    return (_db.mealLogs.select()..where((m) => m.date.equals(date))).get();
  }

  /// 查询 N 天前有原图路径的 meal_log（图片清理用）
  /// 返回 (id, originalImagePath) 列表
  Future<List<({int id, String originalImagePath})>> getOldImagePaths(
      int beforeDays) async {
    final cutoff =
        DateTime.now().subtract(Duration(days: beforeDays));
    final cutoffDate = formatYmd(cutoff);
    final rows = await (_db.mealLogs.select()
          ..where((m) =>
              m.date.isSmallerThanValue(cutoffDate) &
              m.originalImagePath.isNotNull()))
        .get();
    return rows
        .where(
            (m) => m.originalImagePath != null && m.originalImagePath!.isNotEmpty)
        .map((m) => (id: m.id, originalImagePath: m.originalImagePath!))
        .toList();
  }

  /// 清除某条 meal_log 的原图路径引用（文件删除后调用，置空避免死链）
  Future<void> clearImagePath(int id) async {
    await (_db.mealLogs.update()..where((m) => m.id.equals(id)))
        .write(const MealLogsCompanion(originalImagePath: Value(null)));
  }

  /// 查询某日总热量
  Future<double> getTotalCaloriesByDate(String date) async {
    final meals = await getMealsByDate(date);
    return meals.fold<double>(0.0, (sum, m) => sum + m.actualCalories);
  }

  /// 更新某条 meal_log 的部分字段（[MealLogs] 表）
  ///
  /// 全字段可选：传 null（或不传）跳过该字段更新，传非 null 才写入。
  /// 这样编辑 dialog 可只改 date/mealType 而不动营养值，或只改份量按比例重算，
  /// 或只换 foodItemId 而保留原份量。向后兼容现有调用方（传所有 5 个营养字段）。
  ///
  /// 哨兵防御：[foodItemId] 传 <=0 抛 ArgumentError（与 insertMealLog 一致），
  /// 防止 UI 层把 0 哨兵写入非空 FK 字段致崩溃。
  Future<void> updateMealLog({
    required int id,
    double? actualServingG,
    double? actualCalories,
    double? actualProteinG,
    double? actualFatG,
    double? actualCarbsG,
    String? date,
    String? mealType,
    int? foodItemId,
  }) async {
    if (foodItemId != null && foodItemId <= 0) {
      throw ArgumentError('foodItemId 必须为真实 id，不能是 0 哨兵');
    }
    await (_db.mealLogs.update()..where((m) => m.id.equals(id))).write(
      MealLogsCompanion(
        actualServingG:
            actualServingG == null ? const Value.absent() : Value(actualServingG),
        actualCalories:
            actualCalories == null ? const Value.absent() : Value(actualCalories),
        actualProteinG: actualProteinG == null
            ? const Value.absent()
            : Value(actualProteinG),
        actualFatG:
            actualFatG == null ? const Value.absent() : Value(actualFatG),
        actualCarbsG:
            actualCarbsG == null ? const Value.absent() : Value(actualCarbsG),
        date: date == null ? const Value.absent() : Value(date),
        mealType: mealType == null ? const Value.absent() : Value(mealType),
        foodItemId:
            foodItemId == null ? const Value.absent() : Value(foodItemId),
      ),
    );
  }

  /// 删除某条 meal_log（recognition_feedback 因 ON DELETE CASCADE 自动级联删除）
  Future<void> deleteMealLog(int id) async {
    await (_db.mealLogs.delete()..where((m) => m.id.equals(id))).go();
  }

  /// 查询某日三大宏量总和（看板用）
  Future<({double calories, double protein, double fat, double carbs})>
      getMacrosByDate(String date) async {
    final meals = await getMealsByDate(date);
    return (
      calories: meals.fold<double>(0.0, (s, m) => s + m.actualCalories),
      protein: meals.fold<double>(0.0, (s, m) => s + m.actualProteinG),
      fat: meals.fold<double>(0.0, (s, m) => s + m.actualFatG),
      carbs: meals.fold<double>(0.0, (s, m) => s + m.actualCarbsG),
    );
  }

  /// 查询某日期区间全部记录（周/月视图 + AI 汇总用）
  /// 'YYYY-MM-DD' 字典序与时间序一致，isBetweenValues 直接用
  Future<List<MealLog>> getRange(String startDate, String endDate) {
    return (_db.mealLogs.select()
          ..where((m) => m.date.isBetweenValues(startDate, endDate))
          ..orderBy([
            (m) => OrderingTerm.asc(m.date),
            (m) => OrderingTerm.asc(m.loggedAt)
          ]))
        .get();
  }

  /// 查询某食物的历史实际份量中位数（智能份量校准用）
  /// 取最近 20 次记录的 actualServingG，返回中位数；无历史返回 null。
  /// 用中位数而非均值：抗异常值（如偶尔记录 500g 大份，均值被拉偏，中位数稳定）。
  Future<double?> getMedianServing(int foodItemId) async {
    final rows = await (_db.mealLogs.select()
          ..where((m) => m.foodItemId.equals(foodItemId))
          ..orderBy([(m) => OrderingTerm.desc(m.loggedAt)])
          ..limit(20))
        .get();
    if (rows.isEmpty) return null;
    final servings = rows.map((m) => m.actualServingG).toList()..sort();
    final n = servings.length;
    if (n % 2 == 1) {
      return servings[n ~/ 2];
    }
    return (servings[n ~/ 2 - 1] + servings[n ~/ 2]) / 2;
  }

  /// 查询最近 N 天的全部 meal_log（v4 推荐算法用户偏好学习用）。
  /// 返回 `List<MealLog>`，调用方自行聚合。
  /// N 默认 30 天：与 getRecentFoodCounts 窗口一致，覆盖一个月饮食习惯。
  Future<List<MealLog>> getRecentMeals({int days = 30}) async {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: days));
    final startDate = formatYmd(start);
    return (_db.mealLogs.select()
          ..where((m) => m.date.isBiggerOrEqualValue(startDate))
          ..orderBy([(m) => OrderingTerm.desc(m.loggedAt)]))
        .get();
  }

  /// 查询最近 N 天各食物的引用次数（智能推荐加权用）。
  /// 返回 foodItemId → 引用次数。常吃的食物频次高，推荐时加分。
  /// N 默认 30 天：覆盖一个月饮食习惯，太短样本少，太长不反映近期偏好变化。
  Future<Map<int, int>> getRecentFoodCounts({int days = 30}) async {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: days));
    final startDate = formatYmd(start);
    final countRows = await _db.customSelect(
      'SELECT food_item_id, COUNT(id) AS cnt '
      'FROM meal_logs '
      'WHERE date >= ? '
      'GROUP BY food_item_id',
      variables: [Variable.withString(startDate)],
      readsFrom: {_db.mealLogs},
    ).get();
    final result = <int, int>{};
    for (final row in countRows) {
      result[row.read<int>('food_item_id')] = row.read<int>('cnt');
    }
    return result;
  }

  /// 学习每个食物在各 mealType（breakfast/lunch/dinner/snack）的历史分布。
  /// 推荐算法 v3 时段感知用：若某食物历史 70% 在早餐吃，当前是早餐时段则加分。
  ///
  /// 返回 `Map<foodItemId, Map<mealType, ratio>>`，ratio = 该 mealType 次数 / 该食物总次数。
  /// N 默认 60 天：比频次窗口长，时段分布需更多样本才稳定。
  /// 样本不足（总次数 < 2）的食物不返回，避免单次记录误判分布。
  Future<Map<int, Map<String, double>>> getMealTypeDistribution(
      {int days = 60}) async {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: days));
    final startDate = formatYmd(start);
    final rows = await _db.customSelect(
      'SELECT food_item_id, meal_type, COUNT(id) AS cnt '
      'FROM meal_logs '
      'WHERE date >= ? '
      'GROUP BY food_item_id, meal_type',
      variables: [Variable.withString(startDate)],
      readsFrom: {_db.mealLogs},
    ).get();
    // 先聚合每个食物各 mealType 的次数
    final raw = <int, Map<String, int>>{};
    for (final row in rows) {
      final fid = row.read<int>('food_item_id');
      final mt = row.read<String>('meal_type');
      final cnt = row.read<int>('cnt');
      (raw[fid] ??= {})[mt] = cnt;
    }
    // 转为 ratio，样本不足的丢弃
    final result = <int, Map<String, double>>{};
    raw.forEach((fid, counts) {
      final total = counts.values.fold<int>(0, (a, b) => a + b);
      if (total < 2) return; // 样本不足，跳过
      result[fid] = counts.map((k, v) => MapEntry(k, v / total));
    });
    return result;
  }
}
