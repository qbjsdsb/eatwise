import 'package:eatwise/data/seed/food_category_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FoodCategoryDefaults.calibrate M16.8', () {
    test('beer 触发校准：只替换 calories，宏量保留 AI 值（带 clamp）', () {
      // AI 估啤酒 per100g = 200 kcal / 50g 蛋白 / 0g 脂肪 / 20g 碳水
      // defCal=43, ratio=200/43=4.65 > 2.0 触发校准
      final (cal, p, f, c) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 200,
        aiProteinPer100g: 50, // 离谱高，应被 clamp 到 100（但保留 AI 值不替换为 0.5）
        aiFatPer100g: 0,
        aiCarbsPer100g: 20,
        category: 'beer',
      );
      expect(cal, 43, reason: 'calories 用品类默认值');
      expect(p, 50, reason: '蛋白保留 AI 值（不替换为 0.5）');
      expect(f, 0, reason: '脂肪保留 AI 值');
      expect(c, 20, reason: '碳水保留 AI 值');
    });

    test('beer 不触发校准：4 项全保留 AI 值', () {
      // AI 估啤酒 per100g = 80 kcal（43×2=86 内，不触发）
      final (cal, p, f, c) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 80,
        aiProteinPer100g: 5,
        aiFatPer100g: 0,
        aiCarbsPer100g: 8,
        category: 'beer',
      );
      expect(cal, 80);
      expect(p, 5);
      expect(f, 0);
      expect(c, 8);
    });

    test('solid 无品类默认值：4 项 clamp 到合理区间', () {
      // solid 无默认值，AI 离谱估算应被 clamp
      final (cal, p, f, c) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 5000, // 超过 900 上限
        aiProteinPer100g: 150, // 超过 100 上限
        aiFatPer100g: 200,
        aiCarbsPer100g: 300,
        category: 'solid',
      );
      expect(cal, 900, reason: 'solid calories clamp 到 900');
      expect(p, 100, reason: '蛋白 clamp 到 100');
      expect(f, 100, reason: '脂肪 clamp 到 100');
      expect(c, 100, reason: '碳水 clamp 到 100');
    });

    test('beer 触发校准且 AI 宏量离谱：clamp 兜底', () {
      // AI 估啤酒 per100g = 200 kcal / 150g 蛋白（离谱）
      final (cal, p, f, c) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 200,
        aiProteinPer100g: 150,
        aiFatPer100g: -10, // 负值
        aiCarbsPer100g: 20,
        category: 'beer',
      );
      expect(cal, 43, reason: 'calories 用品类默认值');
      expect(p, 100, reason: '蛋白 clamp 到 100（保留 AI 值但限制离谱）');
      expect(f, 0, reason: '负值 clamp 到 0');
      expect(c, 20, reason: '碳水保留 AI 值');
    });
  });
}
