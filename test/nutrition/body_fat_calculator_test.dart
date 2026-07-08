import 'package:flutter_test/flutter_test.dart';
import 'package:eatwise/nutrition/body_fat_calculator.dart';

void main() {
  group('BodyFatCalculator.calcBodyFat', () {
    // openScale 官方夹具（双源验证，误差 <1e-5）
    test('openScale 夹具1：男 30 180cm 80kg 500Ω → 23.32%', () {
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: true, age: 30, heightCm: 180, weightKg: 80, impedance: 500,
      );
      expect(bf, isNotNull);
      expect(bf!, closeTo(23.32, 0.05));
    });

    test('openScale 夹具2：女 28 165cm 60kg 520Ω → 30.36%', () {
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: false, age: 28, heightCm: 165, weightKg: 60, impedance: 520,
      );
      expect(bf, isNotNull);
      expect(bf!, closeTo(30.36, 0.05));
    });

    test('openScale 夹具3：男 45 175cm 95kg 430Ω → 32.42%', () {
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: true, age: 45, heightCm: 175, weightKg: 95, impedance: 430,
      );
      expect(bf, isNotNull);
      expect(bf!, closeTo(32.42, 0.05));
    });

    // 边界测试
    test('impedance=null → 返回 null（提前下秤，BIA 未完成）', () {
      expect(
        BodyFatCalculator.calcBodyFat(
          isMale: true, age: 30, heightCm: 180, weightKg: 80, impedance: null,
        ),
        isNull,
      );
    });

    test('impedance=0 → 返回 null（无效值）', () {
      expect(
        BodyFatCalculator.calcBodyFat(
          isMale: true, age: 30, heightCm: 180, weightKg: 80, impedance: 0,
        ),
        isNull,
      );
    });

    test('impedance<0 → 返回 null（无效值）', () {
      expect(
        BodyFatCalculator.calcBodyFat(
          isMale: true, age: 30, heightCm: 180, weightKg: 80, impedance: -10,
        ),
        isNull,
      );
    });

    test('weightKg=0 → 返回 null（除零保护）', () {
      expect(
        BodyFatCalculator.calcBodyFat(
          isMale: true, age: 30, heightCm: 180, weightKg: 0, impedance: 500,
        ),
        isNull,
      );
    });

    test('体脂率超 75 → clamp 到 75', () {
      // 极端输入构造超范围值（极高 impedance + 极低体重）
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: true, age: 80, heightCm: 150, weightKg: 30, impedance: 2999,
      );
      expect(bf, isNotNull);
      expect(bf!, lessThanOrEqualTo(75.0));
    });

    test('体脂率低于 5 → clamp 到 5', () {
      // 极低 impedance + 高体重构造低体脂
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: true, age: 20, heightCm: 190, weightKg: 120, impedance: 1,
      );
      expect(bf, isNotNull);
      expect(bf!, greaterThanOrEqualTo(5.0));
    });

    // 性别 + 年龄 + 体重分支覆盖
    test('女性 >49 岁（lbmSub=7.25 分支）', () {
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: false, age: 55, heightCm: 160, weightKg: 55, impedance: 500,
      );
      expect(bf, isNotNull);
      expect(bf! > 0, true);
    });

    test('女性 weight>60 + height>160（coeff=0.9888 分支）', () {
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: false, age: 30, heightCm: 170, weightKg: 65, impedance: 500,
      );
      expect(bf, isNotNull);
    });

    test('女性 weight<50 + height>160（coeff=1.0506 分支）', () {
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: false, age: 30, heightCm: 170, weightKg: 45, impedance: 500,
      );
      expect(bf, isNotNull);
    });

    test('男性 weight<61（coeff=0.98 分支）', () {
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: true, age: 30, heightCm: 170, weightKg: 55, impedance: 500,
      );
      expect(bf, isNotNull);
    });
  });
}
