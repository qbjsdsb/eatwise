import 'package:eatwise/features/profile/nutrition_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BMR Mifflin-St Jeor', () {
    test('男性', () {
      final bmr = NutritionCalculator.bmrMifflin(
        weightKg: 70,
        heightCm: 175,
        age: 30,
        gender: Gender.male,
      );
      // 10*70 + 6.25*175 - 5*30 + 5 = 700 + 1093.75 - 150 + 5 = 1648.75
      expect(bmr, closeTo(1648.75, 0.01));
    });

    test('女性', () {
      final bmr = NutritionCalculator.bmrMifflin(
        weightKg: 60,
        heightCm: 165,
        age: 25,
        gender: Gender.female,
      );
      // 10*60 + 6.25*165 - 5*25 - 161 = 600 + 1031.25 - 125 - 161 = 1345.25
      expect(bmr, closeTo(1345.25, 0.01));
    });
  });

  group('BMR Katch-McArdle', () {
    test('体脂率 20%', () {
      final bmr = NutritionCalculator.bmrKatch(
        weightKg: 70,
        bodyFatPct: 20,
      );
      // 370 + 21.6 * 70 * (1 - 0.2) = 370 + 21.6 * 56 = 370 + 1209.6 = 1579.6
      expect(bmr, closeTo(1579.6, 0.01));
    });
  });

  group('TDEE', () {
    test('久坐 1.2', () {
      final tdee = NutritionCalculator.tdee(bmr: 1648.75, activityLevel: 1.2);
      expect(tdee, closeTo(1978.5, 0.01));
    });

    test('中度 1.55', () {
      final tdee = NutritionCalculator.tdee(bmr: 1648.75, activityLevel: 1.55);
      expect(tdee, closeTo(2555.56, 0.01));
    });
  });

  group('目标热量', () {
    test('减脂 cut：TDEE - 500', () {
      final target = NutritionCalculator.dailyCalorieTarget(
        tdee: 2000,
        goal: Goal.cut,
        tdeeAdjustmentKcal: 0,
      );
      expect(target, 1500);
    });

    test('增肌 bulk：TDEE + 250', () {
      final target = NutritionCalculator.dailyCalorieTarget(
        tdee: 2000,
        goal: Goal.bulk,
        tdeeAdjustmentKcal: 0,
      );
      expect(target, 2250);
    });

    test('维持 maintain：TDEE', () {
      final target = NutritionCalculator.dailyCalorieTarget(
        tdee: 2000,
        goal: Goal.maintain,
        tdeeAdjustmentKcal: 0,
      );
      expect(target, 2000);
    });

    test('减脂女性硬下限 1200', () {
      final target = NutritionCalculator.dailyCalorieTarget(
        tdee: 1500,
        goal: Goal.cut,
        gender: Gender.female,
        tdeeAdjustmentKcal: 0,
      );
      expect(target, 1200); // 1500-500=1000，但硬下限 1200
    });

    test('减脂男性硬下限 1500', () {
      final target = NutritionCalculator.dailyCalorieTarget(
        tdee: 1700,
        goal: Goal.cut,
        gender: Gender.male,
        tdeeAdjustmentKcal: 0,
      );
      expect(target, 1500); // 1700-500=1200，但硬下限 1500
    });

    test('tdeeAdjustment 生效', () {
      final target = NutritionCalculator.dailyCalorieTarget(
        tdee: 2000,
        goal: Goal.maintain,
        tdeeAdjustmentKcal: -100,
      );
      expect(target, 1900);
    });
  });

  group('宏量分配', () {
    test('减脂默认', () {
      final macros = NutritionCalculator.macros(
        dailyCalorieTarget: 1500,
        weightKg: 70,
        goal: Goal.cut,
      );
      expect(macros.proteinG, closeTo(168, 0.1)); // 2.4 * 70
      expect(macros.fatG, closeTo(63, 0.1)); // 0.9 * 70
      // 碳水 = (1500 - 168*4 - 63*9) / 4 = (1500 - 672 - 567) / 4 = 261/4 = 65.25
      expect(macros.carbG, closeTo(65.25, 0.1));
    });

    test('增肌默认', () {
      final macros = NutritionCalculator.macros(
        dailyCalorieTarget: 2250,
        weightKg: 70,
        goal: Goal.bulk,
      );
      expect(macros.proteinG, closeTo(126, 0.1)); // 1.8 * 70
      expect(macros.fatG, closeTo(70, 0.1)); // 1.0 * 70
      expect(macros.carbG, closeTo(350, 0.1)); // 增肌碳水 5.0 g/kg * 70 = 350
    });
  });

  group('目标热量 goalRate 联动', () {
    test('dailyCalorieTarget 减脂接受 goalRate 联动', () {
      // goalRate=0.5 kg/周 → 赤字 0.5×7700/7=550 kcal → 2000-550=1450
      // 1450 < 男性硬下限 1500 → clamp 1500
      final result = NutritionCalculator.dailyCalorieTarget(
        tdee: 2000,
        goal: Goal.cut,
        tdeeAdjustmentKcal: 0,
        goalRateKgPerWeek: 0.5,
        gender: Gender.male,
      );
      expect(result, 1500);
    });

    test('dailyCalorieTarget 增肌接受 goalRate 联动', () {
      // goalRate=0.3 kg/周 → 盈余 0.3×7700/7=330 kcal
      final result = NutritionCalculator.dailyCalorieTarget(
        tdee: 2000,
        goal: Goal.bulk,
        tdeeAdjustmentKcal: 0,
        goalRateKgPerWeek: 0.3,
        gender: Gender.male,
      );
      expect(result, 2000 + 330); // 2330
    });

    test('dailyCalorieTarget goalRate=0 回退旧逻辑（兼容）', () {
      final result = NutritionCalculator.dailyCalorieTarget(
        tdee: 2000,
        goal: Goal.cut,
        tdeeAdjustmentKcal: 0,
        goalRateKgPerWeek: 0,
        gender: Gender.male,
      );
      expect(result, 2000 - 500); // 1500（旧逻辑 -500）
    });
  });

  group('validateGoalRate 风险警告', () {
    test('减脂超 1% 体重警告', () {
      final warning = NutritionCalculator.validateGoalRate(
        goalRateKgPerWeek: 1.0, // 1.0 kg/周
        weightKg: 70, // 1% = 0.7 kg，1.0 > 0.7 → 警告
        goal: Goal.cut,
      );
      expect(warning, isNotNull);
      expect(warning, contains('1%'));
    });

    test('增肌盈余超 500 警告', () {
      // 0.5 kg/周 → 0.5×7700/7=550 kcal > 500 → 警告
      final warning = NutritionCalculator.validateGoalRate(
        goalRateKgPerWeek: 0.5,
        weightKg: 70,
        goal: Goal.bulk,
      );
      expect(warning, isNotNull);
      expect(warning, contains('500'));
    });

    test('安全速率无警告', () {
      expect(
        NutritionCalculator.validateGoalRate(
          goalRateKgPerWeek: 0.5, weightKg: 70, goal: Goal.cut), // 0.5 < 0.7
        isNull,
      );
      expect(
        NutritionCalculator.validateGoalRate(
          goalRateKgPerWeek: 0.3, weightKg: 70, goal: Goal.bulk), // 330 < 500
        isNull,
      );
    });
  });
}
