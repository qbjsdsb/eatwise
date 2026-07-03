import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

class WeightLogRepository {
  final EatWiseDatabase _db;
  WeightLogRepository(this._db);

  /// 插入体重记录（同一天多次记录各存一条，UI 取最新）
  Future<int> insert({required String date, required double weightKg}) {
    return _db
        .into(_db.weightLogs)
        .insert(WeightLogsCompanion.insert(date: date, weightKg: weightKg));
  }

  /// 查询某区间体重记录（折线图用，按日期升序）
  Future<List<WeightLog>> getRange(String startDate, String endDate) {
    return (_db.weightLogs.select()
          ..where((w) => w.date.isBetweenValues(startDate, endDate))
          ..orderBy([(w) => OrderingTerm.asc(w.date)]))
        .get();
  }

  /// 查询最近 N 天体重（首页快速预览）
  Future<List<WeightLog>> getRecent({int days = 30}) async {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: days));
    final startDate =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final endDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return getRange(startDate, endDate);
  }

  /// 查询最近 N 天的体重记录（TDEE 校准用）
  /// 同一天多次记录取最后一次（最新体重）
  Future<List<WeightLog>> getRangeForTdee({int days = 28}) async {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: days));
    final startDate =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final endDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final all =
        await (_db.weightLogs.select()
              ..where((w) => w.date.isBetweenValues(startDate, endDate))
              ..orderBy([(w) => OrderingTerm.asc(w.date)]))
            .get();

    // 同一天多条取最后一条（按 id 降序即插入顺序，同日最后插入的最新）
    final byDate = <String, WeightLog>{};
    for (final w in all) {
      byDate[w.date] = w; // 后覆盖前，保留同日最新
    }
    return byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }
}
