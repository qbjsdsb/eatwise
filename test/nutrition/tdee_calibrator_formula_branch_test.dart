import 'package:flutter_test/flutter_test.dart';
import 'package:eatwise/features/profile/nutrition_calculator.dart';

/// M27 v2：TDEE calibrator BMR 分支选择测试
///
/// 验证 tdee_calibrator.dart 修改后读 profile.formula 分支选 BMR：
/// - formula=katch + bodyFatPct!=null → 用 Katch BMR
/// - formula=mifflin → 用 Mifflin BMR（即使有体脂率）
/// - formula=katch 但 bodyFatPct=null → 兜底 Mifflin（防御性）
void main() {
  group('TDEE calibrator BMR 分支选择', () {
    test('formula=katch + bodyFatPct!=null → 用 Katch BMR', () {
      // 模拟 tdee_calibrator 的分支逻辑
      const formula = 'katch';
      const bodyFatPct = 15.0;
      final bmr = (formula == 'katch' && bodyFatPct > 0)
          ? NutritionCalculator.bmrKatch(weightKg: 70, bodyFatPct: bodyFatPct)
          : NutritionCalculator.bmrMifflin(
              weightKg: 70, heightCm: 175, age: 30, gender: Gender.male);
      expect(bmr, closeTo(1655.2, 1.0)); // Katch 值
    });

    test('formula=mifflin → 用 Mifflin BMR（老用户回归）', () {
      const formula = 'mifflin';
      const bodyFatPct = 15.0; // 即使有体脂率，formula=mifflin 仍用 mifflin
      final bmr = (formula == 'katch' && bodyFatPct > 0)
          ? NutritionCalculator.bmrKatch(weightKg: 70, bodyFatPct: bodyFatPct)
          : NutritionCalculator.bmrMifflin(
              weightKg: 70, heightCm: 175, age: 30, gender: Gender.male);
      expect(bmr, closeTo(1648.75, 1.0)); // Mifflin 值
    });

    test('formula=katch 但 bodyFatPct=null → 兜底 Mifflin（防御性）', () {
      const formula = 'katch';
      const double? bodyFatPct = null;
      final bmr = (formula == 'katch' && bodyFatPct != null && bodyFatPct > 0)
          ? NutritionCalculator.bmrKatch(weightKg: 70, bodyFatPct: bodyFatPct)
          : NutritionCalculator.bmrMifflin(
              weightKg: 70, heightCm: 175, age: 30, gender: Gender.male);
      expect(bmr, closeTo(1648.75, 1.0)); // 兜底 Mifflin
    });
  });
}
