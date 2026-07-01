// test/nutrition/tdee_calibrator_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
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
}
