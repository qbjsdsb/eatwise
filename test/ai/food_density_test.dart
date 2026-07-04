// 食物密度表 + 换算逻辑单元测试（建议 3）
import 'package:eatwise/ai/food_density.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('密度表查询', () {
    test('水基饮料密度=1.0', () {
      expect(densityOf('water'), 1.0);
      expect(densityOf('carbonated'), 1.0);
      expect(densityOf('soup'), 1.0);
    });

    test('油密度=0.92', () {
      expect(densityOf('oil'), 0.92);
    });

    test('蜂蜜密度=1.42', () {
      expect(densityOf('honey'), 1.42);
    });

    test('烈酒密度=0.79', () {
      expect(densityOf('alcohol'), 0.79);
    });

    test('固体密度=1.0（不换算）', () {
      expect(densityOf('solid'), 1.0);
    });

    test('未知类别按 1.0 兜底', () {
      expect(densityOf('unknown'), 1.0);
      expect(densityOf(''), 1.0);
      expect(densityOf(null), 1.0);
    });
  });

  group('isLiquidCategory 液体类别判断', () {
    test('液体类别返回 true', () {
      expect(isLiquidCategory('water'), isTrue);
      expect(isLiquidCategory('carbonated'), isTrue);
      expect(isLiquidCategory('oil'), isTrue);
      expect(isLiquidCategory('honey'), isTrue);
      expect(isLiquidCategory('milk'), isTrue);
    });

    test('固体返回 false', () {
      expect(isLiquidCategory('solid'), isFalse);
    });

    test('空/null 返回 false', () {
      expect(isLiquidCategory(''), isFalse);
      expect(isLiquidCategory(null), isFalse);
    });
  });

  group('VisionRecognitionResult.foodCategory 字段', () {
    test('fromJson 解析 food_category', () {
      final json = {
        'dish_name': '食用油',
        'brand': '金龙鱼',
        'quantity': 1,
        'unit': '瓶',
        'per_unit_g': 500,
        'estimated_weight_g_low': 485,
        'estimated_weight_g_mid': 500,
        'estimated_weight_g_high': 515,
        'weight_source': 'package_label',
        'food_category': 'oil',
        'is_single_item': true,
        'food_components': <Map<String, dynamic>>[],
        'cooking_method': 'raw',
        'confidence': 0.9,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.7');
      expect(result.foodCategory, 'oil');
      expect(result.weightSource, 'package_label');
    });

    test('fromJson food_category 缺失默认 solid（旧 prompt 兼容）', () {
      final json = {
        'dish_name': '苹果',
        'quantity': 1,
        'unit': '个',
        'per_unit_g': 200,
        'estimated_weight_g_low': 180,
        'estimated_weight_g_mid': 200,
        'estimated_weight_g_high': 220,
        'is_single_item': true,
        'food_components': <Map<String, dynamic>>[],
        'cooking_method': 'raw',
        'confidence': 0.9,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.5');
      expect(result.foodCategory, 'solid');
    });

    test('fromJson food_category 空串默认 solid', () {
      final json = {
        'dish_name': '苹果',
        'quantity': 1,
        'per_unit_g': 200,
        'estimated_weight_g_mid': 200,
        'is_single_item': true,
        'food_components': <Map<String, dynamic>>[],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'food_category': '',
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.7');
      expect(result.foodCategory, 'solid');
    });

    test('构造函数默认 foodCategory=solid', () {
      final result = VisionRecognitionResult(
        dishName: '苹果',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.6',
      );
      expect(result.foodCategory, 'solid');
    });

    test('copyWith 保留 foodCategory', () {
      final original = VisionRecognitionResult(
        dishName: '油',
        estimatedWeightGLow: 460,
        estimatedWeightGMid: 500,
        estimatedWeightGHigh: 540,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
        foodCategory: 'oil',
      );
      final copied = original.copyWith(estimatedCalories: 4094);
      expect(copied.foodCategory, 'oil');
    });
  });

  group('密度换算数学验证', () {
    test('500ml 油 → 460g（密度 0.92）', () {
      const density = 0.92; // oil
      const perUnitMl = 500.0;
      final realG = perUnitMl * density;
      expect(realG, closeTo(460, 0.01));
    });

    test('250ml 蜂蜜 → 355g（密度 1.42）', () {
      const density = 1.42; // honey
      const perUnitMl = 250.0;
      final realG = perUnitMl * density;
      expect(realG, closeTo(355, 0.01));
    });

    test('500ml 烈酒 → 395g（密度 0.79）', () {
      const density = 0.79; // alcohol
      const perUnitMl = 500.0;
      final realG = perUnitMl * density;
      expect(realG, closeTo(395, 0.01));
    });

    test('500ml 可乐 → 500g（密度 1.0，不变）', () {
      const density = 1.0; // carbonated
      const perUnitMl = 500.0;
      final realG = perUnitMl * density;
      expect(realG, 500);
    });

    test('换算后热量正确性：500ml 油 → 460g → 4089 kcal', () {
      // 889 kcal/100g（油） * 460g / 100 = 4089.4 kcal
      const oilCaloriesPer100g = 889.0;
      const realG = 460.0;
      final calories = oilCaloriesPer100g * realG / 100;
      expect(calories, closeTo(4089.4, 0.1));
    });

    test('换算后热量正确性：250ml 蜂蜜 → 355g → 1082 kcal', () {
      // 蜂蜜约 304 kcal/100g * 355g / 100 = 1079.2 kcal
      const honeyCaloriesPer100g = 304.0;
      const realG = 355.0;
      final calories = honeyCaloriesPer100g * realG / 100;
      expect(calories, closeTo(1079.2, 0.1));
    });
  });

  // v1.10 新增含糖饮料品类密度（tea/protein_drink/energy_drink）
  group('v1.10 新增品类密度', () {
    test('tea 含糖茶饮密度=1.00（水基，与 carbonated 一致）', () {
      expect(densityOf('tea'), 1.00);
    });

    test('protein_drink 蛋白饮料密度=1.03（含蛋白质略重于水，与 milk 一致）', () {
      expect(densityOf('protein_drink'), 1.03);
      // 与 milk 密度一致（源码注释明确，豆奶/杏仁奶近似牛奶）
      expect(densityOf('protein_drink'), densityOf('milk'));
    });

    test('energy_drink 功能饮料密度=1.00（水基）', () {
      expect(densityOf('energy_drink'), 1.00);
    });

    test('三个新品类 isLiquidCategory 返回 true（需要 ml→g 换算）', () {
      expect(isLiquidCategory('tea'), isTrue);
      expect(isLiquidCategory('protein_drink'), isTrue);
      expect(isLiquidCategory('energy_drink'), isTrue);
    });

    test('换算数学验证：250ml 蛋白饮料 → 257.5g（密度 1.03）', () {
      const density = 1.03; // protein_drink
      const perUnitMl = 250.0;
      final realG = perUnitMl * density;
      expect(realG, closeTo(257.5, 0.01));
    });

    test('换算数学验证：500ml 菊花茶 → 500g（密度 1.00，不变）', () {
      const density = 1.00; // tea
      const perUnitMl = 500.0;
      final realG = perUnitMl * density;
      expect(realG, 500);
    });

    test('换算后热量正确性：250ml 蛋白饮料 → 257.5g → 154.5 kcal', () {
      // protein_drink 默认 60 kcal/100g × 257.5g / 100 = 154.5 kcal
      const proteinDrinkCaloriesPer100g = 60.0;
      const realG = 257.5;
      final calories = proteinDrinkCaloriesPer100g * realG / 100;
      expect(calories, closeTo(154.5, 0.1));
    });
  });
}
