import 'package:eatwise/data/seed/food_category_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

/// FoodCategoryDefaults 品类默认值校准测试（P0-1/P0-2 + 方案 D M25）
///
/// 方案 D（M25）废弃品类校准：
///   - calibrate 不再用品类均值覆盖 AI 估算（米粉汤 bug 修复）
///   - 4 项全保留 AI 值，只做物理 clamp [0,900] + 宏量 [0,100]
///   - defaults 表保留（PostProcessor 宏量反推仍用）
void main() {
  group('FoodCategoryDefaults', () {
    test('啤酒默认值 43 kcal/100g', () {
      expect(FoodCategoryDefaults.caloriesPer100g('beer'), 43);
      expect(FoodCategoryDefaults.proteinPer100g('beer'), 0.5);
      expect(FoodCategoryDefaults.fatPer100g('beer'), 0);
      expect(FoodCategoryDefaults.carbsPer100g('beer'), 3.1);
    });

    test('solid 无默认值（差异太大，AI 估算优先）', () {
      expect(FoodCategoryDefaults.caloriesPer100g('solid'), isNull);
    });

    test('未知品类无默认值', () {
      expect(FoodCategoryDefaults.caloriesPer100g('unknown'), isNull);
    });

    test('calibrate 啤酒 AI 估算合理（50）保留 AI 值', () {
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 50,
        aiProteinPer100g: 0.5,
        aiFatPer100g: 0,
        aiCarbsPer100g: 3.5,
        category: 'beer',
      );
      expect(result.$1, 50); // 方案 D：保留 AI 值
    });

    test('方案 D：calibrate 啤酒 AI 估算离谱（200）保留 AI 值（不再用默认 43）', () {
      // 方案 D 改变行为：废弃品类校准，信任 AI 具体估算
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 200,
        aiProteinPer100g: 2,
        aiFatPer100g: 1,
        aiCarbsPer100g: 15,
        category: 'beer',
      );
      expect(result.$1, 200, reason: '方案 D：保留 AI 值');
      expect(result.$2, 2);
      expect(result.$3, 1);
      expect(result.$4, 15);
    });

    test('方案 D：calibrate 啤酒 AI 估算过低（10）保留 AI 值', () {
      // 方案 D：不再用默认值覆盖，保留 AI 值
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 10,
        aiProteinPer100g: 0.1,
        aiFatPer100g: 0,
        aiCarbsPer100g: 1,
        category: 'beer',
      );
      expect(result.$1, 10, reason: '方案 D：保留 AI 值');
    });

    test('calibrate solid 合理值（547 薯片）保留 AI 值', () {
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 547,
        aiProteinPer100g: 6,
        aiFatPer100g: 35,
        aiCarbsPer100g: 53,
        category: 'solid',
      );
      expect(result.$1, 547);
    });

    test('v1.9 Gap4: calibrate solid 离谱高热量（5000）clamp 到 900', () {
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 5000,
        aiProteinPer100g: 6,
        aiFatPer100g: 35,
        aiCarbsPer100g: 53,
        category: 'solid',
      );
      expect(result.$1, 900);
    });

    test('v1.9 Gap4: calibrate solid 负热量 clamp 到 0', () {
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: -100,
        aiProteinPer100g: 0,
        aiFatPer100g: 0,
        aiCarbsPer100g: 0,
        category: 'solid',
      );
      expect(result.$1, 0);
    });

    test('v1.9 Gap4: calibrate solid 蛋白/脂肪/碳水超 100 clamp 到 100', () {
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 500,
        aiProteinPer100g: 150,
        aiFatPer100g: 200,
        aiCarbsPer100g: 120,
        category: 'solid',
      );
      expect(result.$1, 500);
      expect(result.$2, 100);
      expect(result.$3, 100);
      expect(result.$4, 100);
    });

    test('v1.9 Gap4: calibrate solid 边界值 900 保留', () {
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 900,
        aiProteinPer100g: 0,
        aiFatPer100g: 100,
        aiCarbsPer100g: 0,
        category: 'solid',
      );
      expect(result.$1, 900);
      expect(result.$3, 100);
    });

    test('方案 D：calibrate 水 AI 估算 50 保留（不再被强制清零）', () {
      // 方案 D：不再用品类均值覆盖。水默认 0，但 AI 估 50 时保留 AI 值
      // 防离谱由 PostProcessor 重试 + reasoning 审查承担
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 50,
        aiProteinPer100g: 0,
        aiFatPer100g: 0,
        aiCarbsPer100g: 12,
        category: 'water',
      );
      expect(result.$1, 50, reason: '方案 D：保留 AI 值');
    });

    test('calibrate 碳酸饮料 AI 估算合理（43）保留', () {
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 43,
        aiProteinPer100g: 0,
        aiFatPer100g: 0,
        aiCarbsPer100g: 10.6,
        category: 'carbonated',
      );
      expect(result.$1, 43);
    });

    test('方案 D：calibrate 碳酸饮料 AI 估算 100 保留（不再用默认 43）', () {
      // 方案 D：保留 AI 值
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 100,
        aiProteinPer100g: 0,
        aiFatPer100g: 0,
        aiCarbsPer100g: 25,
        category: 'carbonated',
      );
      expect(result.$1, 100, reason: '方案 D：保留 AI 值');
    });

    test('calibrate 碳酸饮料 AI 估算 85 保留', () {
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 85,
        aiProteinPer100g: 0,
        aiFatPer100g: 0,
        aiCarbsPer100g: 21,
        category: 'carbonated',
      );
      expect(result.$1, 85);
    });
  });

  // v1.10：新增 3 个含糖饮料品类
  group('v1.10 新增品类（tea/protein_drink/energy_drink）', () {
    test('tea 默认值 43 kcal/100g（含糖茶饮，近似 carbonated）', () {
      expect(FoodCategoryDefaults.caloriesPer100g('tea'), 43);
      expect(FoodCategoryDefaults.proteinPer100g('tea'), 0.1);
      expect(FoodCategoryDefaults.fatPer100g('tea'), 0);
      expect(FoodCategoryDefaults.carbsPer100g('tea'), 10.6);
    });

    test('protein_drink 默认值 60 kcal/100g（豆奶/杏仁奶/蛋白饮料）', () {
      expect(FoodCategoryDefaults.caloriesPer100g('protein_drink'), 60);
      expect(FoodCategoryDefaults.proteinPer100g('protein_drink'), 3);
      expect(FoodCategoryDefaults.fatPer100g('protein_drink'), 1.5);
      expect(FoodCategoryDefaults.carbsPer100g('protein_drink'), 5);
    });

    test('energy_drink 默认值 45 kcal/100g（红牛/魔爪等功能饮料）', () {
      expect(FoodCategoryDefaults.caloriesPer100g('energy_drink'), 45);
      expect(FoodCategoryDefaults.proteinPer100g('energy_drink'), 0);
      expect(FoodCategoryDefaults.fatPer100g('energy_drink'), 0);
      expect(FoodCategoryDefaults.carbsPer100g('energy_drink'), 11);
    });

    test('calibrate tea AI 估算合理（26）保留（菊花茶包装换算值）', () {
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 26,
        aiProteinPer100g: 0,
        aiFatPer100g: 0,
        aiCarbsPer100g: 6.4,
        category: 'tea',
      );
      expect(result.$1, 26);
    });

    test('方案 D：calibrate tea AI 估算离谱（200）保留（不再用默认 43）', () {
      // 方案 D：保留 AI 值
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 200,
        aiProteinPer100g: 1,
        aiFatPer100g: 1,
        aiCarbsPer100g: 50,
        category: 'tea',
      );
      expect(result.$1, 200, reason: '方案 D：保留 AI 值');
    });

    test('方案 D：calibrate tea AI 估算过低（10）保留', () {
      // 方案 D：保留 AI 值
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 10,
        aiProteinPer100g: 0,
        aiFatPer100g: 0,
        aiCarbsPer100g: 2,
        category: 'tea',
      );
      expect(result.$1, 10, reason: '方案 D：保留 AI 值');
    });

    test('calibrate protein_drink AI 估算合理（55）保留', () {
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 55,
        aiProteinPer100g: 3,
        aiFatPer100g: 1.5,
        aiCarbsPer100g: 5,
        category: 'protein_drink',
      );
      expect(result.$1, 55);
    });

    test('calibrate energy_drink AI 估算合理（45）保留', () {
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 45,
        aiProteinPer100g: 0,
        aiFatPer100g: 0,
        aiCarbsPer100g: 11,
        category: 'energy_drink',
      );
      expect(result.$1, 45);
    });

    test('calibrate tea 自洽反推（cal>0 三宏量全 0 场景）保留 AI cal', () {
      // 此测试验证品类默认值正确，自洽反推逻辑在 recognition_validator 中实现
      final result = FoodCategoryDefaults.calibrate(
        aiCaloriesPer100g: 43,
        aiProteinPer100g: 0,
        aiFatPer100g: 0,
        aiCarbsPer100g: 0,
        category: 'tea',
      );
      expect(result.$1, 43, reason: '方案 D：保留 AI cal');
    });
  });
}
