import 'package:drift/drift.dart';

/// 体重记录表
class WeightLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()(); // 'YYYY-MM-DD' 本地时区自然日
  RealColumn get weightKg => real()();
}
