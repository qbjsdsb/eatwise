import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

class InsightRepository {
  final EatWiseDatabase _db;
  InsightRepository(this._db);

  /// 查询是否已有该周期汇总（去重用）
  Future<InsightSummary?> find(
    String periodType,
    String periodStart,
    String periodEnd,
  ) {
    return (_db.insightSummaries.select()..where(
          (i) =>
              i.periodType.equals(periodType) &
              i.periodStart.equals(periodStart) &
              i.periodEnd.equals(periodEnd),
        ))
        .getSingleOrNull();
  }

  /// 插入新汇总
  Future<int> insert({
    required String periodType,
    required String periodStart,
    required String periodEnd,
    required String summaryText,
  }) {
    return _db
        .into(_db.insightSummaries)
        .insert(
          InsightSummariesCompanion.insert(
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            summaryText: summaryText,
            generatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  /// 编辑汇总文本（用户手动修改）
  Future<void> updateText(int id, String text) async {
    await (_db.insightSummaries.update()..where((i) => i.id.equals(id))).write(
      InsightSummariesCompanion(
        summaryText: Value(text),
        isEdited: const Value(1),
      ),
    );
  }

  /// 强制重新生成（删旧插新）
  Future<int> regenerate({
    required String periodType,
    required String periodStart,
    required String periodEnd,
    required String summaryText,
  }) async {
    final old = await find(periodType, periodStart, periodEnd);
    if (old != null) {
      await (_db.insightSummaries.delete()..where((i) => i.id.equals(old.id)))
          .go();
    }
    return insert(
      periodType: periodType,
      periodStart: periodStart,
      periodEnd: periodEnd,
      summaryText: summaryText,
    );
  }
}
