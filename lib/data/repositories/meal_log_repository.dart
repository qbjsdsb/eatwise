import 'package:eatwise/data/database/database.dart';
import 'package:drift/drift.dart';

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
    final cutoffDate =
        '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';
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

  /// 更新某条 meal_log 的份量（校准后修正，按比例重算营养素）
  Future<void> updateMealLog({
    required int id,
    required double actualServingG,
    required double actualCalories,
    required double actualProteinG,
    required double actualFatG,
    required double actualCarbsG,
  }) async {
    await (_db.mealLogs.update()..where((m) => m.id.equals(id))).write(
      MealLogsCompanion(
        actualServingG: Value(actualServingG),
        actualCalories: Value(actualCalories),
        actualProteinG: Value(actualProteinG),
        actualFatG: Value(actualFatG),
        actualCarbsG: Value(actualCarbsG),
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
}
