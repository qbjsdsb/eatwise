import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/core/util/date_format.dart';

// M24 Task B1：feature 层不再直接 import database.dart，WeightLog 类型从此处走
export 'package:eatwise/data/database/database.dart' show WeightLog;

class WeightLogRepository {
  final EatWiseDatabase _db;
  WeightLogRepository(this._db);

  /// 插入体重记录（同一天多次记录各存一条，UI 取最新）
  Future<int> insert({required String date, required double weightKg}) {
    return _db.into(_db.weightLogs).insert(WeightLogsCompanion.insert(
          date: date,
          weightKg: weightKg,
        ));
  }

  /// 单条查询（编辑 dialog 初始值用）
  Future<WeightLog?> getById(int id) {
    return (_db.weightLogs.select()..where((w) => w.id.equals(id)))
        .getSingleOrNull();
  }

  /// 部分更新体重记录（[weightKg]/[date] 任一非 null 才更新该字段，null 跳过）
  /// 用于编辑 dialog：用户可能只改体重值不改日期，或只改日期不改值
  Future<void> update({
    required int id,
    double? weightKg,
    String? date,
  }) async {
    await (_db.weightLogs.update()..where((w) => w.id.equals(id))).write(
      WeightLogsCompanion(
        weightKg: weightKg == null ? const Value.absent() : Value(weightKg),
        date: date == null ? const Value.absent() : Value(date),
      ),
    );
  }

  /// 删除单条体重记录（输错纠错用）
  Future<void> delete(int id) async {
    await (_db.weightLogs.delete()..where((w) => w.id.equals(id))).go();
  }

  /// 查询某区间体重记录（折线图用，按日期升序）
  ///
  /// L5：同日多条去重保留最新（按 id 升序后覆盖，最大 id = 后插入 = 用户最新值），
  /// 与 getRangeForTdee 行为一致。折线图同日多条会显示多个点跳变，去重后
  /// 每日只显示一个点（最新体重）。
  Future<List<WeightLog>> getRange(String startDate, String endDate) async {
    final all = await (_db.weightLogs.select()
          ..where((w) => w.date.isBetweenValues(startDate, endDate))
          ..orderBy([
            (w) => OrderingTerm.asc(w.date),
            (w) => OrderingTerm.asc(w.id), // 同日多条按插入顺序，保证 byDate 覆盖取最新
          ]))
        .get();
    // 同日多条取最后一条（asc(id) 后到的 id 大，覆盖前到的）
    final byDate = <String, WeightLog>{};
    for (final w in all) {
      byDate[w.date] = w; // 后覆盖前，保留同日最新
    }
    return byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  /// 查询最近 N 天体重（首页快速预览）
  Future<List<WeightLog>> getRecent({int days = 30}) async {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: days));
    final startDate = formatYmd(start);
    final endDate = formatYmd(now);
    return getRange(startDate, endDate);
  }

  /// 查询最近 N 天的体重记录（TDEE 校准用）
  /// 同一天多次记录取最后一次（最新体重）
  Future<List<WeightLog>> getRangeForTdee({int days = 28}) async {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: days));
    final startDate = formatYmd(start);
    final endDate = formatYmd(now);

    final all = await (_db.weightLogs.select()
          ..where((w) => w.date.isBetweenValues(startDate, endDate))
          ..orderBy([
            (w) => OrderingTerm.asc(w.date),
            (w) => OrderingTerm.asc(w.id), // 同日多条按插入顺序，保证 byDate 覆盖取最新
          ]))
        .get();

    // 同一天多条取最后一条（按 id 降序即插入顺序，同日最后插入的最新）
    final byDate = <String, WeightLog>{};
    for (final w in all) {
      byDate[w.date] = w; // 后覆盖前，保留同日最新
    }
    return byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }
}
