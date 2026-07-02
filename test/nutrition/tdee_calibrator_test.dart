// test/nutrition/tdee_calibrator_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/data/repositories/weight_log_repository.dart';
import 'package:eatwise/features/profile/nutrition_calculator.dart';
import 'package:eatwise/nutrition/tdee_calibrator.dart';
import 'package:flutter_test/flutter_test.dart';

WeightLog _w(String date, double kg) {
  // 构造测试用 WeightLog（绕过 DB 插入）
  return WeightLog(id: 0, date: date, weightKg: kg);
}

void main() {
  late EatWiseDatabase db;
  late TdeeCalibrator calibrator;

  setUp(() {
    db = EatWiseDatabase(NativeDatabase.memory());
    calibrator = TdeeCalibrator(db);
  });
  tearDown(() => db.close());

  group('calibrate（纯算法，不写 DB）', () {
    test('数据不足 5 点 → 不触发', () {
      final result = calibrator.calibrate(
        weights: [_w('2026-06-01', 70), _w('2026-06-08', 69.8)],
        goalRateKgPerWeek: -0.5,
      );
      expect(result.adjustmentKcal, 0);
      expect(result.reason, contains('数据不足'));
    });

    test('偏差 ≤ 0.3 kg/周 → 不触发', () {
      // 4 周 5 点，实际 -0.5 kg/周（与目标一致）
      final result = calibrator.calibrate(
        weights: [
          _w('2026-06-01', 70.0),
          _w('2026-06-08', 69.5),
          _w('2026-06-15', 69.0),
          _w('2026-06-22', 68.5),
          _w('2026-06-29', 68.0),
        ],
        goalRateKgPerWeek: -0.5,
      );
      expect(result.adjustmentKcal, 0);
      expect(result.reason, contains('阈值内'));
    });

    test('实际减重比目标慢 → 建议减少热量目标（负 adjustment）', () {
      // 目标 -0.5 kg/周，实际 -0.1 kg/周（减得太慢）→ 偏差 +0.4 > 0.3 → 减目标
      final result = calibrator.calibrate(
        weights: [
          _w('2026-06-01', 70.0),
          _w('2026-06-08', 69.9),
          _w('2026-06-15', 69.8),
          _w('2026-06-22', 69.7),
          _w('2026-06-29', 69.6),
        ],
        goalRateKgPerWeek: -0.5,
      );
      // actualRate = -0.1, deviation = -0.1 - (-0.5) = 0.4 > 0.3
      // rawAdjustment = -0.4 * 7700 / 7 ≈ -440，clamp 到 -100
      expect(result.adjustmentKcal, lessThan(0));
      expect(result.adjustmentKcal, greaterThanOrEqualTo(-100));
    });

    test('单次微调不超过 ±100 kcal', () {
      // 极端偏差也应 clamp 到 ±100
      final result = calibrator.calibrate(
        weights: [
          _w('2026-06-01', 70.0),
          _w('2026-06-08', 72.0), // 异常点（差 2 kg）会被过滤
          _w('2026-06-15', 70.5),
          _w('2026-06-22', 71.0),
          _w('2026-06-29', 71.5),
        ],
        goalRateKgPerWeek: -1.0, // 目标减 1 kg/周，实际在增
      );
      expect(result.adjustmentKcal.abs(), lessThanOrEqualTo(100));
    });

    test('异常点（差 > 2 kg）被过滤', () {
      final result = calibrator.calibrate(
        weights: [
          _w('2026-06-01', 70.0),
          _w('2026-06-08', 75.0), // 异常 +5 kg
          _w('2026-06-15', 70.2),
          _w('2026-06-22', 70.0),
          _w('2026-06-29', 69.8),
        ],
        goalRateKgPerWeek: -0.3,
      );
      // 过滤后剩 4 点（首+3个正常），仍 < 5 → 不触发
      expect(result.adjustmentKcal, 0);
    });
  });

  group('runAndApply（写 DB + 重算 dailyCalorieTarget）', () {
    test('触发 adjustment 后 dailyCalorieTarget 重算含新 adjustment', () async {
      // 种子 5 点体重（最近 28 天内，首尾差 27 天满足 ≥4 周）
      // 实际 -0.1 kg/周 vs 目标 -0.5 kg/周 → 偏差 0.4 > 0.3 → 触发负 adjustment
      final weightRepo = WeightLogRepository(db);
      final profileRepo = ProfileRepository(db);
      final now = DateTime.now();
      String fmt(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      await weightRepo.insert(date: fmt(now.subtract(const Duration(days: 27))), weightKg: 70.0);
      await weightRepo.insert(date: fmt(now.subtract(const Duration(days: 20))), weightKg: 69.9);
      await weightRepo.insert(date: fmt(now.subtract(const Duration(days: 13))), weightKg: 69.8);
      await weightRepo.insert(date: fmt(now.subtract(const Duration(days: 6))), weightKg: 69.7);
      await weightRepo.insert(date: fmt(now), weightKg: 69.6);

      // 设置 profile：cut + goalRate=-0.5（触发减脂校准）
      await profileRepo.update(goal: 'cut', goalRateKgPerWeek: -0.5);

      final result = await calibrator.runAndApply(enabled: true);
      expect(result.adjustmentKcal, lessThan(0), reason: '应触发负 adjustment');

      // 验证 dailyCalorieTarget 重算：profile 含新 adjustment
      final profile = await profileRepo.get();
      expect(profile.tdeeAdjustmentKcal, lessThan(0), reason: 'tdeeAdjustmentKcal 应已写入');

      // 用新 adjustment 重算期望值
      final bmr = NutritionCalculator.bmrMifflin(
        weightKg: profile.weightKg,
        heightCm: profile.heightCm,
        age: profile.age,
        gender: Gender.male,
      );
      final tdee = NutritionCalculator.tdee(bmr: bmr, activityLevel: profile.activityLevel);
      final expectedTarget = NutritionCalculator.dailyCalorieTarget(
        tdee: tdee,
        goal: Goal.cut,
        tdeeAdjustmentKcal: profile.tdeeAdjustmentKcal,
        goalRateKgPerWeek: -0.5,
        gender: Gender.male,
      );
      expect(profile.dailyCalorieTarget, expectedTarget,
          reason: 'dailyCalorieTarget 应等于含新 adjustment 的重算值');
    });

    test('未触发 adjustment（偏差在阈值内）时 dailyCalorieTarget 不变', () async {
      final weightRepo = WeightLogRepository(db);
      final profileRepo = ProfileRepository(db);
      final now = DateTime.now();
      String fmt(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      // 实际 -0.5 kg/周 与目标一致 → 偏差 0 ≤ 0.3 → 不触发
      await weightRepo.insert(date: fmt(now.subtract(const Duration(days: 27))), weightKg: 70.0);
      await weightRepo.insert(date: fmt(now.subtract(const Duration(days: 20))), weightKg: 69.5);
      await weightRepo.insert(date: fmt(now.subtract(const Duration(days: 13))), weightKg: 69.0);
      await weightRepo.insert(date: fmt(now.subtract(const Duration(days: 6))), weightKg: 68.5);
      await weightRepo.insert(date: fmt(now), weightKg: 68.0);

      // 设置 profile：cut + goalRate=-0.5（与实际速率一致，偏差 0 → 不触发）
      await profileRepo.update(goal: 'cut', goalRateKgPerWeek: -0.5);

      final profileBefore = await profileRepo.get();
      final targetBefore = profileBefore.dailyCalorieTarget;

      final result = await calibrator.runAndApply(enabled: true);
      expect(result.adjustmentKcal, 0);

      final profileAfter = await profileRepo.get();
      expect(profileAfter.dailyCalorieTarget, targetBefore,
          reason: '未触发时 dailyCalorieTarget 应保持不变');
    });
  });
}
