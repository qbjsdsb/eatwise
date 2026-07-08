import 'package:drift/drift.dart';

/// 食物库表（含识别入库和手动入库）
@TableIndex(name: 'idx_food_items_name', columns: {#name})
@TableIndex(name: 'idx_food_items_source', columns: {#source})
class FoodItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  RealColumn get defaultServingG => real()();
  RealColumn get caloriesPer100g => real()();
  RealColumn get proteinPer100g => real()();
  RealColumn get fatPer100g => real()();
  RealColumn get carbsPer100g => real()();
  TextColumn get aliasesJson => text().nullable()();
  RealColumn get ediblePercent => real().nullable()();
  TextColumn get source => text()(); // china_fct/usda/off/manual/ai_recognized
  TextColumn get sourceVersion => text()();
  RealColumn get confidence => real().nullable()();
  TextColumn get componentsJson => text().nullable()();
  TextColumn get thumbnailPath => text().nullable()();
  IntColumn get createdAt => integer()(); // UTC 毫秒
}
