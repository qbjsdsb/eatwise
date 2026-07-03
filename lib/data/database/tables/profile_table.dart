import 'package:drift/drift.dart';

/// 个人档案表（单行表，id 固定为 1）
class Profiles extends Table {
  IntColumn get id => integer().clientDefault(() => 1)();
  RealColumn get heightCm => real()();
  RealColumn get weightKg => real()();
  RealColumn get bodyFatPct => real().nullable()();
  IntColumn get age => integer()();
  TextColumn get gender => text()(); // 'male' / 'female'
  RealColumn get activityLevel => real()(); // 1.2/1.375/1.55/1.725/1.9
  TextColumn get goal => text()(); // 'cut' / 'bulk' / 'maintain'
  RealColumn get goalRateKgPerWeek => real()();
  TextColumn get formula => text()(); // 'mifflin' / 'katch'
  IntColumn get dailyCalorieTarget => integer()();
  RealColumn get proteinGPerKg => real()();
  RealColumn get fatGPerKg => real()();
  RealColumn get carbGPerKg => real().nullable()();
  IntColumn get tdeeAdjustmentKcal =>
      integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer()(); // UTC 毫秒

  @override
  Set<Column> get primaryKey => {id};
}
