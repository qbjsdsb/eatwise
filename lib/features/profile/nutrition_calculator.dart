/// 营养计算模块（纯函数，无 UI，无副作用）
/// 依据设计文档 5.1-5.4 节
/// 公式来源：Mifflin-St Jeor (Frankenfield 2005)、Katch-McArdle、ISSN 2017、Morton 2018
/// 特殊人群调整来源：IOM 2006（孕期/哺乳期能量加成）、ISSN 老年推荐、KDOQI 肾病蛋白限制
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

  /// 特殊生理状态的能量加成（kcal/天）
  /// 来源：IOM 2006（Institute of Medicine, Dietary Reference Intakes）
  /// - pregnancy：+340 kcal（2nd-3rd trimester 中值；1st trimester 通常无需加）
  ///   简化处理：用户选了"孕期"即按 2nd-3rd 加成（多数用户建档时已过早期）
  /// - lactation：+500 kcal（哺乳期前 6 个月，IOM 推荐）
  /// - elderly/teenager：0 kcal 加成（通过宏量分配调整，见 macros()）
  /// null/'none' → 0（向后兼容：旧数据无此字段视为无加成）
  static int specialConditionCalorieAdjustment(String? specialCondition) {
    switch (specialCondition) {
      case 'pregnancy':
        return 340;
      case 'lactation':
        return 500;
      default:
        return 0;
    }
  }

  /// 每日目标热量（受硬下限约束）
  /// 减脂：TDEE - goalRate×7700/7（可调 300-750 kcal/天，对应 0.3-0.7 kg/周）
  /// 增肌：TDEE + goalRate×7700/7（可调 200-500 kcal/天，对应 0.18-0.45 kg/周）
  /// 维持：TDEE
  /// goalRateKgPerWeek=0 时回退旧逻辑（-500/+250）保持兼容
  /// 硬下限：女性 ≥ 1200，男性 ≥ 1500
  /// 特殊人群：孕期/哺乳期在 TDEE 基础上加成（在 deficit/surplus 之前加，
  ///   避免减脂目标把孕期加成抵消掉——孕期不应减脂，但保留计算灵活性）
  static int dailyCalorieTarget({
    required double tdee,
    required Goal goal,
    required int tdeeAdjustmentKcal,
    double goalRateKgPerWeek = 0,
    Gender? gender,
    String? specialCondition,
  }) {
    final specialAdj = specialConditionCalorieAdjustment(specialCondition);
    final tdeeWithSpecial = tdee + specialAdj;
    int raw;
    switch (goal) {
      case Goal.cut:
        final deficit = goalRateKgPerWeek > 0
            ? (goalRateKgPerWeek * 7700 / 7).round()
            : 500;
        raw = (tdeeWithSpecial - deficit + tdeeAdjustmentKcal).round();
        break;
      case Goal.bulk:
        final surplus = goalRateKgPerWeek > 0
            ? (goalRateKgPerWeek * 7700 / 7).round()
            : 250;
        raw = (tdeeWithSpecial + surplus + tdeeAdjustmentKcal).round();
        break;
      case Goal.maintain:
        raw = (tdeeWithSpecial + tdeeAdjustmentKcal).round();
        break;
    }
    // 硬下限
    if (gender == Gender.female && raw < 1200) raw = 1200;
    if (gender == Gender.male && raw < 1500) raw = 1500;
    return raw;
  }

  /// 校验目标速率是否安全
  /// 返回 null=安全，非 null=警告文案
  /// 减脂：每周减重 > 1% 体重 → 警告（设计 5.3）
  /// 增肌：盈余 > 500 kcal/天 → 警告（设计 5.3）
  /// 减脂速率建议 0.3-0.7 kg/周，增肌建议 0.18-0.45 kg/周
  static String? validateGoalRate({
    required double goalRateKgPerWeek,
    required double weightKg,
    required Goal goal,
  }) {
    if (goalRateKgPerWeek <= 0) return null;
    switch (goal) {
      case Goal.cut:
        // 每周减重 > 1% 体重 → 警告
        if (goalRateKgPerWeek > weightKg * 0.01) {
          return '减脂速率 ${(goalRateKgPerWeek * 1000).round()} g/周超过体重 1%（${(weightKg * 10).round()} g/周），'
              '可能流失肌肉，建议降至 0.3-0.7 kg/周';
        }
        return null;
      case Goal.bulk:
        // 盈余 > 500 kcal/天 → 警告
        final surplusKcal = goalRateKgPerWeek * 7700 / 7;
        if (surplusKcal > 500) {
          return '增肌盈余 ${surplusKcal.round()} kcal/天超过 500，'
              '易囤积脂肪，建议降至 200-500 kcal/天（0.18-0.45 kg/周）';
        }
        return null;
      case Goal.maintain:
        return null;
    }
  }

  /// 宏量营养素分配
  ///
  /// 特殊人群调整（覆盖 goal 默认值，权威来源）：
  /// - elderly（≥65）：蛋白提高到 1.0-1.2g/kg 防肌少症（ISSN 老年推荐；
  ///   cut 时仍用 2.4 不降，因为老年减脂更要保肌肉）
  /// - teenager：维持期蛋白 1.0-1.4g/kg（生长需求略高于成人维持）
  /// - diabetes：碳水占比 cap 45%（ADA 糖尿病医学营养治疗，控血糖）
  /// - kidney_issues：蛋白 cap 0.8g/kg（KDOQI 慢性肾病 3-5 期；
  ///   cut 时的 2.4g/kg 对肾病负担过重，强制降到 0.8）
  /// - pregnancy/lactation：蛋白 +25g/天（IOM 孕期 71g、哺乳期 71g 推荐）
  ///   实现方式：在 goal 基础上蛋白 g/kg 适度上调
  /// - hypertension：钠 < 2300mg/天（此处不直接调宏量，仅 UI 提示）
  ///
  /// 返回 (proteinG, fatG, carbG, 蛋白g/kg, 脂肪g/kg, 碳水g/kg)
  /// 调用方需把 g/kg 写入 profile 供 dashboard 反算
  static Macros macros({
    required int dailyCalorieTarget,
    required double weightKg,
    required Goal goal,
    String? specialCondition,
    String? healthCondition,
  }) {
    double proteinGPerKg;
    double fatGPerKg;
    double? carbGPerKg;

    // 基础值（按 goal）
    switch (goal) {
      case Goal.cut:
        proteinGPerKg = 2.4; // ISSN 2017，减脂期 2.3-2.6 默认 2.4
        fatGPerKg = 0.9; // 0.8-1.0 默认 0.9
        break;
      case Goal.bulk:
        proteinGPerKg = 1.8; // Morton 2018，1.6-2.2 默认 1.8
        fatGPerKg = 1.0; // 0.8-1.2 默认 1.0
        carbGPerKg = 5.0; // 4-7 g/kg 取中值
        break;
      case Goal.maintain:
        proteinGPerKg = 1.4; // 1.2-1.6 默认 1.4
        fatGPerKg = 0.9; // 0.8-1.0 默认 0.9
        break;
    }

    // 特殊生理状态覆盖
    if (specialCondition == 'elderly') {
      // 老年人防肌少症：维持/增肌期蛋白提高到 1.2g/kg（cut 仍 2.4 不降）
      if (goal != Goal.cut) proteinGPerKg = proteinGPerKg < 1.2 ? 1.2 : proteinGPerKg;
    } else if (specialCondition == 'teenager') {
      // 青少年生长需求：维持期蛋白略提
      if (goal == Goal.maintain) proteinGPerKg = 1.4;
    } else if (specialCondition == 'pregnancy' || specialCondition == 'lactation') {
      // 孕期/哺乳期：蛋白适度上调（IOM 推荐 71g/天，约 1.1g/kg for 65kg）
      if (proteinGPerKg < 1.1) proteinGPerKg = 1.1;
    }

    // 健康状况覆盖（最高优先级，安全考虑）
    if (healthCondition == 'kidney_issues') {
      // 肾病：蛋白强制 cap 0.8g/kg（KDOQI），即使减脂也不超过
      // 否则 2.4g/kg 加重肾负担
      if (proteinGPerKg > 0.8) proteinGPerKg = 0.8;
    }
    // 糖尿病：碳水占比 cap 45%（通过 carbGPerKg 不主动设，让 carb 填剩余，
    // 但在最终 carbG 计算后若超 45% 热量占比则下调）
    // 此处先记录，下方计算时处理

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

    // 糖尿病碳水 cap 45% 热量占比（ADA 推荐 45% 上下限）
    // carbCal = carbG * 4，若 > dailyCalorieTarget * 0.45 则下调
    if (healthCondition == 'diabetes' && dailyCalorieTarget > 0) {
      final maxCarbCal = dailyCalorieTarget * 0.45;
      final maxCarbG = maxCarbCal / 4;
      if (carbG > maxCarbG) carbG = maxCarbG;
    }

    return Macros(
      proteinG: proteinG,
      fatG: fatG,
      carbG: carbG,
      proteinGPerKg: proteinGPerKg,
      fatGPerKg: fatGPerKg,
    );
  }
}

enum Gender { male, female }

enum Goal { cut, bulk, maintain }

class Macros {
  final double proteinG;
  final double fatG;
  final double carbG;
  // g/kg 密度（写入 profile 供 dashboard 反算；特殊人群调整后的实际值）
  final double proteinGPerKg;
  final double fatGPerKg;

  const Macros({
    required this.proteinG,
    required this.fatG,
    required this.carbG,
    required this.proteinGPerKg,
    required this.fatGPerKg,
  });
}
