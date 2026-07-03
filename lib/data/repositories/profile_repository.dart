import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

/// 个人档案 Repository（profile 是单行表，id 固定 1）
class ProfileRepository {
  final EatWiseDatabase _db;
  ProfileRepository(this._db);

  /// 读取唯一 profile 行（id=1）
  Future<Profile> get() {
    return (_db.profiles.select()..where((p) => p.id.equals(1))).getSingle();
  }

  /// 更新 profile（部分字段）
  /// 注意：dailyCalorieTarget / proteinGPerKg / fatGPerKg / carbGPerKg
  /// 由 ProfilePage 调 NutritionCalculator 重算后传入，本方法不重算
  Future<void> update({
    double? heightCm,
    double? weightKg,
    double? bodyFatPct,
    int? age,
    String? gender,
    double? activityLevel,
    String? goal,
    double? goalRateKgPerWeek,
    String? formula,
    int? dailyCalorieTarget,
    double? proteinGPerKg,
    double? fatGPerKg,
    double? carbGPerKg,
    int? tdeeAdjustmentKcal,
  }) async {
    final companion = ProfilesCompanion(
      heightCm: heightCm != null ? Value(heightCm) : const Value.absent(),
      weightKg: weightKg != null ? Value(weightKg) : const Value.absent(),
      bodyFatPct: bodyFatPct != null ? Value(bodyFatPct) : const Value.absent(),
      age: age != null ? Value(age) : const Value.absent(),
      gender: gender != null ? Value(gender) : const Value.absent(),
      activityLevel: activityLevel != null
          ? Value(activityLevel)
          : const Value.absent(),
      goal: goal != null ? Value(goal) : const Value.absent(),
      goalRateKgPerWeek: goalRateKgPerWeek != null
          ? Value(goalRateKgPerWeek)
          : const Value.absent(),
      formula: formula != null ? Value(formula) : const Value.absent(),
      dailyCalorieTarget: dailyCalorieTarget != null
          ? Value(dailyCalorieTarget)
          : const Value.absent(),
      proteinGPerKg: proteinGPerKg != null
          ? Value(proteinGPerKg)
          : const Value.absent(),
      fatGPerKg: fatGPerKg != null ? Value(fatGPerKg) : const Value.absent(),
      carbGPerKg: carbGPerKg != null ? Value(carbGPerKg) : const Value.absent(),
      tdeeAdjustmentKcal: tdeeAdjustmentKcal != null
          ? Value(tdeeAdjustmentKcal)
          : const Value.absent(),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    );
    await (_db.profiles.update()..where((p) => p.id.equals(1))).write(
      companion,
    );
  }
}
