import 'package:drift/drift.dart';
import 'food_item_table.dart';

/// 餐次记录表
class MealLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()(); // 'YYYY-MM-DD' 本地时区自然日
  TextColumn get mealType => text()(); // breakfast/lunch/dinner/snack
  IntColumn get foodItemId => integer().references(FoodItems, #id)();
  RealColumn get actualServingG => real()();
  RealColumn get actualCalories => real()();
  RealColumn get actualProteinG => real()();
  RealColumn get actualFatG => real()();
  RealColumn get actualCarbsG => real()();
  TextColumn get originalImagePath => text().nullable()();
  RealColumn get recognitionConfidence => real().nullable()();
  TextColumn get componentsSnapshotJson => text().nullable()();
  IntColumn get loggedAt => integer()(); // UTC 毫秒
}
