import 'package:drift/drift.dart';

/// AI 汇总建议表
class InsightSummaries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get periodType => text()(); // weekly/monthly
  TextColumn get periodStart => text()(); // 'YYYY-MM-DD'
  TextColumn get periodEnd => text()(); // 'YYYY-MM-DD'
  TextColumn get summaryText => text()();
  IntColumn get isEdited => integer().withDefault(const Constant(0))();
  IntColumn get generatedAt => integer()(); // UTC 毫秒
}
