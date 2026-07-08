import 'package:drift/drift.dart';
import 'food_item_table.dart';

/// 离线识别队列表
@TableIndex(name: 'idx_pending_recognitions_status', columns: {#status})
class PendingRecognitions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get imagePath => text()();
  TextColumn get mealType => text()();
  TextColumn get date => text()(); // 'YYYY-MM-DD' 本地时区自然日
  TextColumn get status => text()(); // pending/done/failed
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  IntColumn get resultFoodItemId => integer().nullable().references(FoodItems, #id)();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get promptVersion => text().nullable()();
  IntColumn get createdAt => integer()(); // UTC 毫秒
  IntColumn get processedAt => integer().nullable()(); // UTC 毫秒
}
