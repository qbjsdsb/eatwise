import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

// M24 Task B1：feature 层不再直接 import database.dart，Profile 类型从此处走
export 'package:eatwise/data/database/database.dart' show Profile;

/// 个人档案 Repository（profile 是单行表，id 固定 1）
class ProfileRepository {
  final EatWiseDatabase _db;
  ProfileRepository(this._db);

  /// 读取唯一 profile 行（id=1）
  /// 防御性兜底：正常路径 profile 行在 DB 首次创建时已 seed（database.dart beforeOpen），
  /// 但若 DB 损坏/测试空库导致行缺失，getSingle() 会抛 StateError。
  /// 改为 getSingleOrNull + 重建默认行，保证调用方永不崩溃。
  Future<Profile> get() async {
    final existing = await (_db.profiles.select()..where((p) => p.id.equals(1)))
        .getSingleOrNull();
    if (existing != null) return existing;

    // 行缺失：重建默认 profile（与 database.dart beforeOpen seed 值一致）
    await _db.into(_db.profiles).insert(ProfilesCompanion.insert(
          id: const Value(1),
          heightCm: 170,
          weightKg: 70,
          age: 30,
          gender: 'male',
          activityLevel: 1.375,
          goal: 'maintain',
          goalRateKgPerWeek: 0,
          formula: 'mifflin',
          dailyCalorieTarget: 2000,
          proteinGPerKg: 1.4,
          fatGPerKg: 0.9,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
    final reloaded = await (_db.profiles.select()..where((p) => p.id.equals(1)))
        .getSingleOrNull();
    // insert 成功后行必定存在；极端竞态下仍为 null 则返回内存默认值（永不抛 StateError）
    return reloaded ??
        Profile(
          id: 1,
          heightCm: 170,
          weightKg: 70,
          age: 30,
          gender: 'male',
          activityLevel: 1.375,
          goal: 'maintain',
          goalRateKgPerWeek: 0,
          formula: 'mifflin',
          dailyCalorieTarget: 2000,
          proteinGPerKg: 1.4,
          fatGPerKg: 0.9,
          tdeeAdjustmentKcal: 0,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
  }

  /// 更新 profile（部分字段）
  /// 注意：dailyCalorieTarget / proteinGPerKg / fatGPerKg / carbGPerKg
  /// 由 ProfilePage 调 NutritionCalculator 重算后传入，本方法不重算
  ///
  /// 特殊人群字段（specialCondition/dietPreference/healthCondition）：
  /// 用 sentinel 区分"不更新"（absent）和"显式清空"（设为 'none'）。
  /// null 参数 = 不更新该字段；非 null（含 'none'）= 写入该值。
  ///
  /// M7 已知限制：bodyFatPct / carbGPerKg 这两个 nullable 数值字段，
  /// null 参数 = 不更新（Value.absent），无法显式置空。
  /// 原因：drift 的 Value.absent 语义是"不更新"，Value(null) 才是"置空"，
  /// 当前实现把 null 一律映射为 Value.absent（见下方 `?? : Value.absent()`），
  /// 丢失置空语义。若用户清空体脂率/碳水系数，UI 应传 0 或默认值而非 null，
  /// 否则 DB 保留旧值，用户会困惑"清空后看到旧值"。
  /// （tdeeAdjustmentKcal 是 NOT NULL 字段，无此问题；String 字段用 'none' sentinel。）
  /// 如需支持显式置空，需引入 sentinel 对象或 Optional 包装，成本较高收益低，暂不实施。
  ///
  /// M27 v2 例外：bodyFatPct 已提供 clearBodyFatPct() 方法支持显式置空
  /// （BMR 自动升级需在用户清空体脂率时回退 Mifflin 公式）。
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
    String? specialCondition,
    String? dietPreference,
    String? healthCondition,
  }) async {
    final companion = ProfilesCompanion(
      heightCm: heightCm != null ? Value(heightCm) : const Value.absent(),
      weightKg: weightKg != null ? Value(weightKg) : const Value.absent(),
      bodyFatPct: bodyFatPct != null ? Value(bodyFatPct) : const Value.absent(),
      age: age != null ? Value(age) : const Value.absent(),
      gender: gender != null ? Value(gender) : const Value.absent(),
      activityLevel:
          activityLevel != null ? Value(activityLevel) : const Value.absent(),
      goal: goal != null ? Value(goal) : const Value.absent(),
      goalRateKgPerWeek: goalRateKgPerWeek != null
          ? Value(goalRateKgPerWeek)
          : const Value.absent(),
      formula: formula != null ? Value(formula) : const Value.absent(),
      dailyCalorieTarget: dailyCalorieTarget != null
          ? Value(dailyCalorieTarget)
          : const Value.absent(),
      proteinGPerKg:
          proteinGPerKg != null ? Value(proteinGPerKg) : const Value.absent(),
      fatGPerKg: fatGPerKg != null ? Value(fatGPerKg) : const Value.absent(),
      carbGPerKg:
          carbGPerKg != null ? Value(carbGPerKg) : const Value.absent(),
      tdeeAdjustmentKcal: tdeeAdjustmentKcal != null
          ? Value(tdeeAdjustmentKcal)
          : const Value.absent(),
      specialCondition: specialCondition != null
          ? Value(specialCondition)
          : const Value.absent(),
      dietPreference: dietPreference != null
          ? Value(dietPreference)
          : const Value.absent(),
      healthCondition: healthCondition != null
          ? Value(healthCondition)
          : const Value.absent(),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    );
    await (_db.profiles.update()..where((p) => p.id.equals(1))).write(companion);
  }

  /// 显式置空 bodyFatPct（M27 v2：用户清空体脂率时调用）
  ///
  /// 因 update() 的 null=不更新（Value.absent）设计无法置空 nullable 字段，
  /// 需专门方法。用户清空体脂率 → formula 应回退 mifflin。
  /// 见 update() 的 M7 已知限制注释。
  Future<void> clearBodyFatPct() async {
    await (_db.profiles.update()..where((p) => p.id.equals(1)))
        .write(const ProfilesCompanion(bodyFatPct: Value(null)));
  }
}
