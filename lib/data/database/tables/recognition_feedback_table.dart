import 'package:drift/drift.dart';
import 'meal_log_table.dart';

/// 识别反馈表（prompt 改进数据源）
class RecognitionFeedbacks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get mealLogId =>
      integer().references(MealLogs, #id, onDelete: KeyAction.cascade)();
  IntColumn get isCorrect => integer()();
  TextColumn get correctedDishName => text().nullable()();
  RealColumn get correctedServingG => real().nullable()();
  TextColumn get promptVersion => text()();
  IntColumn get createdAt => integer()(); // UTC 毫秒
}
