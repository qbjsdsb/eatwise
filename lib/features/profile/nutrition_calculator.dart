/// 营养计算模块（纯函数，无 UI，无副作用）
/// 依据设计文档 5.1-5.4 节
/// 公式来源：Mifflin-St Jeor (Frankenfield 2005)、Katch-McArdle、ISSN 2017、Morton 2018
class NutritionCalculator {
  NutritionCalculator._();

  /// BMR - Mifflin-St Jeor 公式（AND 官方推荐）
  static double bmrMifflin({
    required double weightKg,
    required double heightCm,
    required int age,
    required Gender gender,
  }) {
    final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
    return gender == Gender.male ? base + 5 : base - 161;
  }

  /// BMR - Katch-McArdle 公式（需体脂率，对精瘦人群更准）
  static double bmrKatch({
    required double weightKg,
    required double bodyFatPct,
  }) {
    final leanMass = weightKg * (1 - bodyFatPct / 100);
    return 370 + 21.6 * leanMass;
  }

  /// TDEE = BMR × 活动系数
  static double tdee({
    required double bmr,
    required double activityLevel,
  }) {
    return bmr * activityLevel;
  }

  /// 每日目标热量（受硬下限约束）
  /// 减脂：TDEE - 500；增肌：TDEE + 250；维持：TDEE
  /// 硬下限：女性 ≥ 1200，男性 ≥ 1500
  static int dailyCalorieTarget({
    required double tdee,
    required Goal goal,
    required int tdeeAdjustmentKcal,
    Gender? gender,
  }) {
    int raw;
    switch (goal) {
      case Goal.cut:
        raw = (tdee - 500 + tdeeAdjustmentKcal).round();
        break;
      case Goal.bulk:
        raw = (tdee + 250 + tdeeAdjustmentKcal).round();
        break;
      case Goal.maintain:
        raw = (tdee + tdeeAdjustmentKcal).round();
        break;
    }
    // 硬下限
    if (gender == Gender.female && raw < 1200) raw = 1200;
    if (gender == Gender.male && raw < 1500) raw = 1500;
    return raw;
  }

  /// 宏量营养素分配
  static Macros macros({
    required int dailyCalorieTarget,
    required double weightKg,
    required Goal goal,
  }) {
    double proteinGPerKg;
    double fatGPerKg;
    double? carbGPerKg;

    switch (goal) {
      case Goal.cut:
        proteinGPerKg = 2.4; // ISSN 2017，减脂期 2.3-2.6 默认 2.4
        fatGPerKg = 0.9; // 0.8-1.0 默认 0.9
        // 碳水填剩余
        break;
      case Goal.bulk:
        proteinGPerKg = 1.8; // Morton 2018，1.6-2.2 默认 1.8
        fatGPerKg = 1.0; // 0.8-1.2 默认 1.0
        carbGPerKg = 5.0; // 4-7 g/kg 取中值
        break;
      case Goal.maintain:
        proteinGPerKg = 1.4; // 1.2-1.6 默认 1.4
        fatGPerKg = 0.9; // 0.8-1.0 默认 0.9
        // 碳水填剩余
        break;
    }

    final proteinG = proteinGPerKg * weightKg;
    final fatG = fatGPerKg * weightKg;
    final proteinCal = proteinG * 4;
    final fatCal = fatG * 9;

    double carbG;
    if (carbGPerKg != null) {
      // 增肌场景：碳水主动设 g/kg 目标
      carbG = carbGPerKg * weightKg;
    } else {
      // 减脂/维持：碳水 = 剩余热量 / 4
      carbG = (dailyCalorieTarget - proteinCal - fatCal) / 4;
      if (carbG < 0) carbG = 0; // 保护：热量不足时碳水不取负
    }

    return Macros(proteinG: proteinG, fatG: fatG, carbG: carbG);
  }
}

enum Gender { male, female }

enum Goal { cut, bulk, maintain }

class Macros {
  final double proteinG;
  final double fatG;
  final double carbG;

  const Macros({
    required this.proteinG,
    required this.fatG,
    required this.carbG,
  });
}
