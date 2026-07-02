// lib/nutrition/tdee_calibrator.dart
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/weight_log_repository.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/features/profile/nutrition_calculator.dart';

/// TDEE 自适应校准
/// 设计文档 5.5：
/// - 观察窗口 ≥ 4 周（≥5 个体重点）
/// - 实际速率与公式预测偏差 > 0.3 kg/周
/// - 排除异常点：单次与前次差 > 2 kg
/// - 单次微调幅度上限 ±100 kcal
class TdeeCalibrator {
  static const minWeeks = 4;
  static const minDataPoints = 5;
  static const deviationThresholdKgPerWeek = 0.3; // 偏差阈值
  static const abnormalDeltaKg = 2.0; // 异常点阈值
  static const maxAdjustmentKcal = 100; // 单次微调上限

  final EatWiseDatabase _db;
  TdeeCalibrator(this._db);

  /// 校准结果
  /// adjustmentKcal: 建议的 tdee_adjustment_kcal 增量（正=增目标，负=减目标）
  /// reason: 触发/未触发原因（UI 提示用）
  TdeeCalibrationResult calibrate({
    required List<WeightLog> weights,
    required double goalRateKgPerWeek, // 目标速率（减脂负值/增肌正值/维持0）
  }) {
    if (weights.length < minDataPoints) {
      return TdeeCalibrationResult(
        adjustmentKcal: 0,
        reason: '数据不足：需 ≥$minDataPoints 个体重点，当前 ${weights.length}',
      );
    }

    // 排除异常点：单次与前次差 > 2 kg
    final filtered = <WeightLog>[weights.first];
    for (var i = 1; i < weights.length; i++) {
      final delta = (weights[i].weightKg - weights[i - 1].weightKg).abs();
      if (delta <= abnormalDeltaKg) {
        filtered.add(weights[i]);
      }
    }
    if (filtered.length < minDataPoints) {
      return TdeeCalibrationResult(
        adjustmentKcal: 0,
        reason: '排除异常点后数据不足（剩余 ${filtered.length} 点）',
      );
    }

    // 计算实际周变化速率（线性回归斜率 × 7 天）
    // 用首尾差值 / 周数（简单线性，足够 MVP）
    final first = filtered.first;
    final last = filtered.last;
    final daysDiff = DateTime.parse(last.date).difference(DateTime.parse(first.date)).inDays;
    if (daysDiff < minWeeks * 7 - 1) { // 至少接近 4 周
      return TdeeCalibrationResult(
        adjustmentKcal: 0,
        reason: '观察窗口不足 $minWeeks 周（当前 ${daysDiff ~/ 7} 周）',
      );
    }
    final weightDeltaKg = last.weightKg - first.weightKg;
    final weeks = daysDiff / 7;
    final actualRateKgPerWeek = weightDeltaKg / weeks;

    // 偏差 = 实际速率 - 目标速率
    final deviation = actualRateKgPerWeek - goalRateKgPerWeek;
    if (deviation.abs() <= deviationThresholdKgPerWeek) {
      return TdeeCalibrationResult(
        adjustmentKcal: 0,
        reason: '实际速率与目标偏差 ${deviation.toStringAsFixed(2)} kg/周，在阈值内',
      );
    }

    // 微调：偏差 > 0（实际增重比目标快）→ 减少热量目标（负 adjustment）
    //       偏差 < 0（实际减重比目标快）→ 增加热量目标（正 adjustment）
    // 1 kg 体重 ≈ 7700 kcal，周偏差 × 7700 / 7 = 日热量调整
    final rawAdjustment = -deviation * 7700 / 7;
    // 限制单次 ±100 kcal
    final adjustment = rawAdjustment.clamp(-maxAdjustmentKcal.toDouble(), maxAdjustmentKcal.toDouble()).toInt();

    return TdeeCalibrationResult(
      adjustmentKcal: adjustment,
      reason: '实际速率 ${actualRateKgPerWeek.toStringAsFixed(2)} kg/周 vs 目标 ${goalRateKgPerWeek.toStringAsFixed(2)} kg/周，'
          '建议微调 ${adjustment > 0 ? "+" : ""}$adjustment kcal/天',
    );
  }

  /// 执行校准并写入 profile.tdee_adjustment_kcal（累加）+ 重算 dailyCalorieTarget
  /// 返回校准结果（用于 UI 提示）
  ///
  /// Sprint 7 修复：原实现只写 tdeeAdjustmentKcal 不重算 dailyCalorieTarget，
  /// 导致校准值成为死数据（dashboard 读 dailyCalorieTarget 不含 adjustment）。
  /// 现在：写 adjustment 后立即用新 adjustment 重算 dailyCalorieTarget，
  /// 让 dailyCalorieTarget 永远是含 adjustment 的最终生效值。
  Future<TdeeCalibrationResult> runAndApply({bool enabled = true}) async {
    if (!enabled) {
      return TdeeCalibrationResult(adjustmentKcal: 0, reason: '自适应校准已关闭');
    }

    final weightRepo = WeightLogRepository(_db);
    final profileRepo = ProfileRepository(_db);
    final weights = await weightRepo.getRangeForTdee(days: minWeeks * 7);
    final profile = await profileRepo.get();

    final result = calibrate(
      weights: weights,
      goalRateKgPerWeek: profile.goalRateKgPerWeek,
    );

    if (result.adjustmentKcal != 0) {
      // 累加到现有 tdee_adjustment_kcal
      final newAdjustment = profile.tdeeAdjustmentKcal + result.adjustmentKcal;

      // 重算 dailyCalorieTarget（含新 adjustment），让校准值立即生效
      final genderEnum =
          profile.gender == 'male' ? Gender.male : Gender.female;
      final goalEnum = profile.goal == 'cut'
          ? Goal.cut
          : profile.goal == 'bulk'
              ? Goal.bulk
              : Goal.maintain;
      final bmr = NutritionCalculator.bmrMifflin(
        weightKg: profile.weightKg,
        heightCm: profile.heightCm,
        age: profile.age,
        gender: genderEnum,
      );
      final tdee = NutritionCalculator.tdee(
          bmr: bmr, activityLevel: profile.activityLevel);
      final newTarget = NutritionCalculator.dailyCalorieTarget(
        tdee: tdee,
        goal: goalEnum,
        tdeeAdjustmentKcal: newAdjustment,
        goalRateKgPerWeek: profile.goalRateKgPerWeek,
        gender: genderEnum,
      );

      await profileRepo.update(
        tdeeAdjustmentKcal: newAdjustment,
        dailyCalorieTarget: newTarget,
      );
    }

    return result;
  }
}

class TdeeCalibrationResult {
  final int adjustmentKcal;
  final String reason;
  TdeeCalibrationResult({required this.adjustmentKcal, required this.reason});
}
