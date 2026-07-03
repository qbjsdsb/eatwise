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
  IntColumn get tdeeAdjustmentKcal => integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer()(); // UTC 毫秒

  // 特殊人群适配（schema v2 新增，全部 nullable 向后兼容）
  // specialCondition：特殊生理状态，影响 TDEE 加成
  //   'none' / 'pregnancy'(孕期) / 'lactation'(哺乳期) / 'elderly'(老年≥65) / 'teenager'(青少年)
  // dietPreference：饮食偏好/限制，影响推荐（后续可过滤食物）
  //   'none' / 'vegetarian'(蛋奶素) / 'vegan'(纯素) / 'lactose_intolerant'(乳糖不耐) / 'gluten_free'(无麸质)
  // healthCondition：健康状况，影响宏量分配 + 风险提示
  //   'none' / 'diabetes'(糖尿病) / 'hypertension'(高血压) / 'kidney_issues'(肾病)
  TextColumn get specialCondition => text().nullable()();
  TextColumn get dietPreference => text().nullable()();
  TextColumn get healthCondition => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
