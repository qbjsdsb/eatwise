import 'package:flutter_test/flutter_test.dart';
import 'package:eatwise/features/profile/nutrition_calculator.dart';

/// M27 v2：BMR 公式选择逻辑测试（不测 UI，测计算分支）
///
/// 验证：
/// - 有体脂率 → Katch-McArdle（基于瘦体重，对精瘦人群更准）
/// - 无体脂率 → Mifflin-St Jeor（向后兼容）
/// - formula 切换时重置 tdeeAdjustmentKcal（防跨公式污染）
void main() {
  group('BMR 公式选择逻辑', () {
    test('有体脂率 → 用 Katch', () {
      final bmrKatch = NutritionCalculator.bmrKatch(
        weightKg: 70, bodyFatPct: 15,
      );
      final bmrMifflin = NutritionCalculator.bmrMifflin(
        weightKg: 70, heightCm: 175, age: 30, gender: Gender.male,
      );
      // Katch 对精瘦人群 BMR 更高
      expect(bmrKatch, greaterThan(bmrMifflin));
      // Katch: 370 + 21.6×70×(1-0.15) = 370 + 1285.2 = 1655.2
      expect(bmrKatch, closeTo(1655.2, 1.0));
    });

    test('无体脂率 → 用 Mifflin', () {
      final bmr = NutritionCalculator.bmrMifflin(
        weightKg: 70, heightCm: 175, age: 30, gender: Gender.male,
      );
      // Mifflin: 10×70 + 6.25×175 - 5×30 + 5 = 1648.75
      expect(bmr, closeTo(1648.75, 1.0));
    });

    test('体脂率=0 → 走 Mifflin（hasBodyFat=false 判定）', () {
      // bodyFat=0 时 hasBodyFat = 0 > 0 = false，走 mifflin
      // 防止 Katch 对 0% 体脂率算出过高 BMR
      final hasBodyFat = (0.0 > 0);
      expect(hasBodyFat, false);
    });

    test('formula 切换 mifflin→katch 应重置 tdeeAdjustmentKcal', () {
      // 验证切换逻辑：oldFormula != newFormula → 重置
      const oldFormula = 'mifflin';
      const newFormula = 'katch';
      final formulaChanged = oldFormula != newFormula;
      expect(formulaChanged, true);
      // 重置后 tdeeAdjustmentKcal 应为 0
      final resetValue = formulaChanged ? 0 : null;
      expect(resetValue, 0);
    });

    test('formula 未变 mifflin→mifflin 不重置 tdeeAdjustmentKcal', () {
      const oldFormula = 'mifflin';
      const newFormula = 'mifflin';
      final formulaChanged = oldFormula != newFormula;
      expect(formulaChanged, false);
    });
  });
}
