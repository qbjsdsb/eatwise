import 'package:eatwise/data/seed/food_category_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FoodCategoryDefaults.calibrate 方案 D（M25 废弃品类校准）', () {
    test('beer 离谱估算（per100g=200）：方案 D 保留 AI 值（不再用默认 43 覆盖）', () {
      // 方案 D 改变行为：废弃品类校准，4 项全保留 AI 估算值（只做物理 clamp）
      // 修复前：cal=43（被默认值覆盖），宏量保留
      // 修复后：cal=200（保留 AI 值），宏量保留
      final (cal, p, f, c) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 200,
        aiProteinPer100g: 50, // 离谱高，应被 clamp 到 100
        aiFatPer100g: 0,
        aiCarbsPer100g: 20,
        category: 'beer',
      );
      expect(cal, 200, reason: '方案 D：calories 保留 AI 值');
      expect(p, 50, reason: '蛋白保留 AI 值（在 [0,100] 内）');
      expect(f, 0, reason: '脂肪保留 AI 值');
      expect(c, 20, reason: '碳水保留 AI 值');
    });

    test('beer 合理估算（80）：保留 AI 值', () {
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

    test('solid 离谱估算：clamp 到 [0,900]', () {
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

    test('beer 离谱估算 + AI 宏量离谱：clamp 兜底', () {
      // 方案 D：calories 保留 AI 值（不被默认值覆盖），但宏量仍 clamp
      final (cal, p, f, c) = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 200,
        aiProteinPer100g: 150,
        aiFatPer100g: -10,
        aiCarbsPer100g: 20,
        category: 'beer',
      );
      expect(cal, 200, reason: '方案 D：calories 保留 AI 值');
      expect(p, 100, reason: '蛋白 clamp 到 100');
      expect(f, 0, reason: '负值 clamp 到 0');
      expect(c, 20, reason: '碳水保留 AI 值');
    });
  });
}
