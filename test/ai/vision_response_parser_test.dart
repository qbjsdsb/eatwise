import 'package:eatwise/ai/vision_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VisionRecognitionResult.fromJson', () {
    test('正常单品响应解析', () {
      final json = {
        'dish_name': '苹果',
        'estimated_weight_g_low': 150,
        'estimated_weight_g_mid': 180,
        'estimated_weight_g_high': 220,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.0');

      expect(result.dishName, '苹果');
      expect(result.estimatedWeightGMid, 180);
      expect(result.isSingleItem, true);
      expect(result.foodComponents, isEmpty);
      expect(result.confidence, 0.9);
      expect(result.promptVersion, 'v1.0');
    });

    test('复合菜响应解析（含组分）', () {
      final json = {
        'dish_name': '番茄炒蛋',
        'estimated_weight_g_low': 200,
        'estimated_weight_g_mid': 250,
        'estimated_weight_g_high': 300,
        'is_single_item': false,
        'food_components': [
          {'name': '鸡蛋', 'estimated_g': 120},
          {'name': '番茄', 'estimated_g': 150}
        ],
        'cooking_method': 'stir-fry',
        'confidence': 0.85,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.0');

      expect(result.isSingleItem, false);
      expect(result.foodComponents.length, 2);
      expect(result.foodComponents[0].name, '鸡蛋');
      expect(result.foodComponents[0].estimatedG, 120);
    });

    test('food_components 字段缺失时默认空数组', () {
      final json = {
        'dish_name': '苹果',
        'estimated_weight_g_low': 150,
        'estimated_weight_g_mid': 180,
        'estimated_weight_g_high': 220,
        'is_single_item': true,
        'cooking_method': 'raw',
        'confidence': 0.9,
        // food_components 缺失
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.0');
      expect(result.foodComponents, isEmpty);
    });

    test('字段类型为 int 时正确转 double', () {
      final json = {
        'dish_name': '米饭',
        'estimated_weight_g_low': 100,
        'estimated_weight_g_mid': 150,
        'estimated_weight_g_high': 200,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'boil',
        'confidence': 1, // int 而非 double
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.0');
      expect(result.confidence, 1.0);
      expect(result.estimatedWeightGMid, 150.0);
    });

    test('字段缺失：estimated_weight_g_low 缺失时回退 Mid（设计 5.6）', () {
      final json = {
        'dish_name': '米饭',
        'estimated_weight_g_mid': 100,
        'is_single_item': true,
        'cooking_method': 'boil',
        'confidence': 0.9,
        // estimated_weight_g_low 缺失
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.0');
      expect(result.estimatedWeightGMid, 100);
      expect(result.estimatedWeightGLow, 100);  // 回退 Mid
    });

    test('字段缺失：estimated_weight_g_high 缺失时回退 Mid', () {
      final json = {
        'dish_name': '米饭',
        'estimated_weight_g_mid': 100,
        'is_single_item': true,
        'cooking_method': 'boil',
        'confidence': 0.9,
        // estimated_weight_g_high 缺失
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.0');
      expect(result.estimatedWeightGHigh, 100);  // 回退 Mid
    });

    test('必填字段缺失（dishName）抛异常（malformed）', () {
      final json = {
        'estimated_weight_g_mid': 100,
        'is_single_item': true,
        'cooking_method': 'boil',
        'confidence': 0.9,
        // dish_name 缺失
      };
      expect(() => VisionRecognitionResult.fromJson(json, 'v1.0'), throwsA(anything));
    });

    test('confidence 缺失时兜底 0.5（H1 修复：模型偶发漏返不崩溃）', () {
      final json = {
        'dish_name': '米饭',
        'estimated_weight_g_mid': 100,
        'is_single_item': true,
        'cooking_method': 'boil',
        // confidence 缺失
      };
      // H1 修复前：as num 强转抛 _TypeError；修复后兜底 0.5
      final result = VisionRecognitionResult.fromJson(json, 'v1.0');
      expect(result.confidence, 0.5);
    });

    test('字段类型错误：estimated_weight_g_mid 为字符串抛异常（as num 失败）', () {
      final json = {
        'dish_name': '米饭',
        'estimated_weight_g_mid': '100',  // 字符串，as num 失败
        'is_single_item': true,
        'cooking_method': 'boil',
        'confidence': 0.9,
      };
      expect(() => VisionRecognitionResult.fromJson(json, 'v1.0'), throwsA(anything));
    });
  });

  group('v1.2 一桌多菜解析（additional_dishes）', () {
    test('单菜响应：additional_dishes 缺失 → 空数组 + isMultiDish=false', () {
      final json = {
        'dish_name': '可乐',
        'estimated_weight_g_mid': 330,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        // additional_dishes 缺失（v1.0/v1.1 旧响应）
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.2');
      expect(result.additionalDishes, isEmpty);
      expect(result.isMultiDish, false);
    });

    test('单菜响应：additional_dishes 为空数组 → isMultiDish=false', () {
      final json = {
        'dish_name': '可乐',
        'estimated_weight_g_mid': 330,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'additional_dishes': [],
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.2');
      expect(result.additionalDishes, isEmpty);
      expect(result.isMultiDish, false);
    });

    test('多菜响应：additional_dishes 含 2 个菜 → isMultiDish=true', () {
      final json = {
        'dish_name': '宫保鸡丁',
        'estimated_weight_g_mid': 250,
        'is_single_item': false,
        'food_components': [
          {'name': '鸡肉', 'estimated_g': 150}
        ],
        'cooking_method': 'stir-fry',
        'confidence': 0.85,
        'additional_dishes': [
          {
            'dish_name': '米饭',
            'estimated_weight_g_mid': 200,
            'is_single_item': true,
            'food_components': [],
            'cooking_method': 'steam',
            'confidence': 0.9,
            'additional_dishes': []
          },
          {
            'dish_name': '清炒西兰花',
            'estimated_weight_g_mid': 150,
            'is_single_item': false,
            'food_components': [
              {'name': '西兰花', 'estimated_g': 150}
            ],
            'cooking_method': 'stir-fry',
            'confidence': 0.8,
            'additional_dishes': []
          },
        ],
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.2');

      expect(result.dishName, '宫保鸡丁');
      expect(result.isMultiDish, true);
      expect(result.additionalDishes.length, 2);

      // 第一个 additionalDish
      expect(result.additionalDishes[0].dishName, '米饭');
      expect(result.additionalDishes[0].isSingleItem, true);
      expect(result.additionalDishes[0].estimatedWeightGMid, 200);

      // 第二个 additionalDish
      expect(result.additionalDishes[1].dishName, '清炒西兰花');
      expect(result.additionalDishes[1].isSingleItem, false);
      expect(result.additionalDishes[1].foodComponents.length, 1);
    });

    test('子菜的 additional_dishes 强制为空（不递归嵌套）', () {
      final json = {
        'dish_name': '主菜',
        'estimated_weight_g_mid': 200,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'additional_dishes': [
          {
            'dish_name': '配菜',
            'estimated_weight_g_mid': 100,
            'is_single_item': true,
            'food_components': [],
            'cooking_method': 'raw',
            'confidence': 0.8,
            // 即使子菜又写了 additional_dishes，解析后也强制为空（from 时如果传了会递归，
            // 但 prompt 规则要求子菜 additional_dishes 为空，这里测规范响应）
            'additional_dishes': []
          },
        ],
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.2');
      expect(result.additionalDishes[0].additionalDishes, isEmpty);
    });

    test('brand 字段在多菜响应中正确解析（主菜 + 子菜）', () {
      final json = {
        'dish_name': '可乐',
        'brand': '可口可乐',
        'estimated_weight_g_mid': 330,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'additional_dishes': [
          {
            'dish_name': '薯片',
            'brand': '乐事',
            'estimated_weight_g_mid': 50,
            'is_single_item': true,
            'food_components': [],
            'cooking_method': 'raw',
            'confidence': 0.85,
            'additional_dishes': []
          },
        ],
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.2');
      expect(result.brand, '可口可乐');
      expect(result.additionalDishes[0].brand, '乐事');
    });
  });

  group('v1.3 同物多份解析（quantity/per_unit_g/unit）', () {
    test('正常多份响应：两罐可乐 quantity=2 → isMultiQuantity=true', () {
      final json = {
        'dish_name': '可乐',
        'estimated_weight_g_mid': 660,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'quantity': 2,
        'unit': '罐',
        'per_unit_g': 330,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.3');

      expect(result.quantity, 2);
      expect(result.unit, '罐');
      expect(result.perUnitG, 330);
      expect(result.isMultiQuantity, true);
      expect(result.estimatedWeightGMid, 660); // = perUnitG × quantity
    });

    test('旧响应无 quantity/per_unit_g/unit → 默认值 + 向后兼容', () {
      final json = {
        'dish_name': '苹果',
        'estimated_weight_g_mid': 180,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        // quantity/per_unit_g/unit 均缺失（v1.0/v1.1/v1.2 旧响应）
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.3');

      expect(result.quantity, 1);
      expect(result.unit, '份');
      expect(result.perUnitG, 180); // 反推 mid/quantity = 180/1
      expect(result.isMultiQuantity, false);
    });

    test('quantity=1 → isMultiQuantity=false', () {
      final json = {
        'dish_name': '可乐',
        'estimated_weight_g_mid': 330,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'quantity': 1,
        'unit': '罐',
        'per_unit_g': 330,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.3');
      expect(result.quantity, 1);
      expect(result.isMultiQuantity, false);
    });

    test('quantity=0 越界 → 清洗为 1（防 mid/0=Infinity 崩溃）', () {
      final json = {
        'dish_name': '可乐',
        'estimated_weight_g_mid': 330,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'quantity': 0, // 非法
        'unit': '罐',
        'per_unit_g': 330,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.3');
      expect(result.quantity, 1); // 清洗为 1
      expect(result.perUnitG, 330);
      expect(result.isMultiQuantity, false);
    });

    test('quantity=负数 越界 → 清洗为 1', () {
      final json = {
        'dish_name': '可乐',
        'estimated_weight_g_mid': 330,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'quantity': -3, // 非法
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.3');
      expect(result.quantity, 1);
    });

    test('quantity=100 超上限 → 清洗为 20（步进器上限）', () {
      final json = {
        'dish_name': '饺子',
        'estimated_weight_g_mid': 2000,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'boil',
        'confidence': 0.85,
        'quantity': 100, // 超 20 上限
        'per_unit_g': 20,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.3');
      expect(result.quantity, 20); // 清洗为上限
      expect(result.isMultiQuantity, true);
    });

    test('per_unit_g 缺失时反推 mid/quantity', () {
      final json = {
        'dish_name': '可乐',
        'estimated_weight_g_mid': 990,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'quantity': 3,
        // per_unit_g 缺失 → 反推 990/3=330
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.3');
      expect(result.quantity, 3);
      expect(result.perUnitG, 330); // mid/quantity 反推
    });

    test('unit 为空串 → 默认"份"', () {
      final json = {
        'dish_name': '可乐',
        'estimated_weight_g_mid': 330,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'quantity': 1,
        'unit': '', // 空串
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.3');
      expect(result.unit, '份');
    });

    test('unit 缺失 → 默认"份"', () {
      final json = {
        'dish_name': '可乐',
        'estimated_weight_g_mid': 330,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        // unit 缺失
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.3');
      expect(result.unit, '份');
    });

    test('多份 + 多菜组合：主菜多份 + additionalDishes 正常', () {
      final json = {
        'dish_name': '可乐',
        'estimated_weight_g_mid': 660,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'quantity': 2,
        'unit': '罐',
        'per_unit_g': 330,
        'additional_dishes': [
          {
            'dish_name': '薯片',
            'estimated_weight_g_mid': 100,
            'is_single_item': true,
            'food_components': [],
            'cooking_method': 'raw',
            'confidence': 0.85,
            'quantity': 2,
            'unit': '包',
            'per_unit_g': 50,
          },
        ],
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.3');

      expect(result.quantity, 2);
      expect(result.isMultiQuantity, true);
      expect(result.isMultiDish, true);
      expect(result.additionalDishes[0].quantity, 2);
      expect(result.additionalDishes[0].perUnitG, 50);
      expect(result.additionalDishes[0].isMultiQuantity, true);
    });
  });

  group('v1.9 CoT 推理 + 包装营养表 OCR 解析', () {
    test('reasoning 字段正常解析', () {
      final json = {
        'dish_name': '啤酒',
        'brand': '雪花',
        'estimated_weight_g_mid': 500,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'reasoning': '看到绿色瓶身第一反应是雪碧，但仔细读瓶身文字是雪花，是啤酒不是雪碧',
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.9');
      expect(result.reasoning,
          '看到绿色瓶身第一反应是雪碧，但仔细读瓶身文字是雪花，是啤酒不是雪碧');
    });

    test('reasoning 字段缺失（旧 prompt v1.8 兼容）→ null', () {
      final json = {
        'dish_name': '苹果',
        'estimated_weight_g_mid': 180,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        // reasoning 缺失
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.8');
      expect(result.reasoning, isNull);
    });

    test('reasoning 字段为空串 → null（兜底，避免下游展示空字符串）', () {
      final json = {
        'dish_name': '苹果',
        'estimated_weight_g_mid': 180,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'reasoning': '',
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.9');
      expect(result.reasoning, isNull);
    });

    test('包装营养表 6 个字段正常解析（珍宝珠酸条案例）', () {
      final json = {
        'dish_name': '酸条',
        'brand': '珍宝珠',
        'estimated_weight_g_mid': 57.6,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.95,
        'estimated_calories': 325,
        'estimated_protein_g': 0,
        'estimated_fat_g': 0,
        'estimated_carbs_g': 80,
        'package_nutrition_table_ocr': '每份10.5g 能量170kJ 蛋白质0g 脂肪0g 碳水10g',
        'package_serving_g': 10.5,
        'package_serving_kj': 170,
        'package_serving_kcal': 0,
        'package_total_g': 57.6,
        'package_servings_per_pack': 8,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.9');
      expect(result.packageNutritionTableOcr,
          '每份10.5g 能量170kJ 蛋白质0g 脂肪0g 碳水10g');
      expect(result.packageServingG, 10.5);
      expect(result.packageServingKj, 170);
      expect(result.packageServingKcal, 0);
      expect(result.packageTotalG, 57.6);
      expect(result.packageServingsPerPack, 8);
      // hasPackageNutrition getter：任一 serving_* > 0 即 true
      expect(result.hasPackageNutrition, isTrue);
    });

    test('包装字段全部缺失（散装/无包装食品）→ 默认值 + hasPackageNutrition=false', () {
      final json = {
        'dish_name': '苹果',
        'estimated_weight_g_mid': 180,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        // 6 个 package_* 字段全部缺失（v1.8 旧响应）
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.9');
      expect(result.packageNutritionTableOcr, '');
      expect(result.packageServingG, isNull);
      expect(result.packageServingKj, isNull);
      expect(result.packageServingKcal, isNull);
      expect(result.packageTotalG, isNull);
      expect(result.packageServingsPerPack, isNull);
      expect(result.hasPackageNutrition, isFalse);
    });

    test('包装字段为 int 类型时正确转 double', () {
      final json = {
        'dish_name': '酸条',
        'estimated_weight_g_mid': 57,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'package_serving_g': 10, // int 而非 double
        'package_serving_kj': 170,
        'package_total_g': 57,
        'package_servings_per_pack': 8,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.9');
      expect(result.packageServingG, 10.0);
      expect(result.packageServingKj, 170.0);
      expect(result.packageTotalG, 57.0);
      expect(result.packageServingsPerPack, 8.0);
    });

    test('包装字段为字符串数字时 as num 失败抛异常（malformed）', () {
      final json = {
        'dish_name': '酸条',
        'estimated_weight_g_mid': 57,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'package_serving_g': '10.5', // 字符串，as num 失败
      };
      expect(() => VisionRecognitionResult.fromJson(json, 'v1.9'),
          throwsA(anything));
    });

    test('copyWith 透传 reasoning 字段（v1.9 新增）', () {
      final original = VisionRecognitionResult(
        dishName: '啤酒',
        brand: '雪花',
        estimatedWeightGLow: 490,
        estimatedWeightGMid: 500,
        estimatedWeightGHigh: 510,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.9',
        reasoning: '读瓶身文字是雪花不是雪碧',
        packageNutritionTableOcr: '每份10.5g 能量170kJ',
        packageServingG: 10.5,
        packageServingKj: 170,
      );
      // copyWith 修改其他字段，reasoning + package_* 应原样保留
      final modified = original.copyWith(estimatedCalories: 220);
      expect(modified.reasoning, '读瓶身文字是雪花不是雪碧');
      expect(modified.packageNutritionTableOcr, '每份10.5g 能量170kJ');
      expect(modified.packageServingG, 10.5);
      expect(modified.packageServingKj, 170);
      expect(modified.estimatedCalories, 220);
    });

    test('copyWith 显式覆盖 reasoning 字段', () {
      final original = VisionRecognitionResult(
        dishName: '啤酒',
        estimatedWeightGLow: 490,
        estimatedWeightGMid: 500,
        estimatedWeightGHigh: 510,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.9',
        reasoning: '旧推理',
      );
      final modified = original.copyWith(reasoning: '新推理');
      expect(modified.reasoning, '新推理');
    });
  });

  group('v1.9 computePackageNutritionPer100g 包装换算', () {
    /// 构造带包装字段的 VisionRecognitionResult 辅助函数
    VisionRecognitionResult buildResult({
      double mid = 100,
      double? servingG,
      double? servingKj,
      double? servingKcal,
      double? estimatedProteinG,
      double? estimatedFatG,
      double? estimatedCarbsG,
    }) {
      return VisionRecognitionResult(
        dishName: 'test',
        brand: '',
        estimatedWeightGLow: mid,
        estimatedWeightGMid: mid,
        estimatedWeightGHigh: mid,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.9',
        packageServingG: servingG,
        packageServingKj: servingKj,
        packageServingKcal: servingKcal,
        estimatedProteinG: estimatedProteinG,
        estimatedFatG: estimatedFatG,
        estimatedCarbsG: estimatedCarbsG,
      );
    }

    test('kcal 字段优先：serving_g=100 serving_kcal=50 → per100g=50', () {
      final result = buildResult(
        servingG: 100,
        servingKcal: 50,
        servingKj: 999, // 应被忽略，优先用 kcal
      );
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNotNull);
      expect(per100!.$1, closeTo(50, 0.001)); // 50 * 100 / 100 = 50
    });

    test('kJ 兜底换算：serving_g=10.5 serving_kj=170 → per100g≈386.95', () {
      // 珍宝珠酸条案例：每份10.5g, 170kJ
      // servingKcal = 170 / 4.184 ≈ 40.631
      // per100Calories = 40.631 * 100 / 10.5 ≈ 386.96
      final result = buildResult(
        mid: 57.6,
        servingG: 10.5,
        servingKj: 170,
        servingKcal: 0, // 0 视为无值，走 kJ 路径
      );
      expect(result.hasPackageNutrition, isTrue);
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNotNull);
      expect(per100!.$1, closeTo(386.96, 0.01));
    });

    test('kJ 兜底换算（kcal=null）：serving_kj>0 → 正确换算', () {
      final result = buildResult(
        servingG: 100,
        servingKj: 418.4, // 418.4 / 4.184 = 100 kcal
        servingKcal: null,
      );
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNotNull);
      expect(per100!.$1, closeTo(100, 0.001));
    });

    test('serving_g=0 → 返回 null（无法换算）', () {
      final result = buildResult(
        servingG: 0,
        servingKcal: 50,
      );
      // serving_g=0 时 hasPackageNutrition 取决于其他字段
      // 但 computePackageNutritionPer100g 应返回 null
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNull);
    });

    test('serving_g=null → 返回 null', () {
      final result = buildResult(
        servingG: null,
        servingKcal: 50,
      );
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNull);
    });

    test('kcal 和 kj 都为 0/null → 返回 null', () {
      final result = buildResult(
        servingG: 100,
        servingKcal: 0,
        servingKj: 0,
      );
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNull);
    });

    test('蛋白/脂肪/碳水按 AI 估算 per100 反算（mid=200 估算 10g → per100=5）', () {
      // mid=200g 的整菜，AI 估算含蛋白质 10g
      // per100Protein = 10 * 100 / 200 = 5 g/100g
      final result = buildResult(
        mid: 200,
        servingG: 100,
        servingKcal: 250,
        estimatedProteinG: 10,
        estimatedFatG: 5,
        estimatedCarbsG: 30,
      );
      final per100 = result.computePackageNutritionPer100g(
        estimatedProteinG: result.estimatedProteinG,
        estimatedFatG: result.estimatedFatG,
        estimatedCarbsG: result.estimatedCarbsG,
      );
      expect(per100, isNotNull);
      expect(per100!.$1, closeTo(250, 0.001)); // 250 * 100 / 100
      expect(per100.$2, closeTo(5, 0.001)); // 10 * 100 / 200
      expect(per100.$3, closeTo(2.5, 0.001)); // 5 * 100 / 200
      expect(per100.$4, closeTo(15, 0.001)); // 30 * 100 / 200
    });

    test('AI 估算为 null 时蛋白/脂肪/碳水 per100=0（不崩）', () {
      final result = buildResult(
        mid: 200,
        servingG: 100,
        servingKcal: 250,
        // estimatedProteinG/FatG/CarbsG 全部 null
      );
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNotNull);
      expect(per100!.$1, closeTo(250, 0.001));
      expect(per100.$2, 0);
      expect(per100.$3, 0);
      expect(per100.$4, 0);
    });

    test('mid=0 时蛋白/脂肪/碳水 per100=0（防除零）', () {
      // mid=0 时 per100Ratio=0，蛋白/脂肪/碳水结果为 0
      // 但 calories 仍按包装换算（不依赖 mid）
      final result = buildResult(
        mid: 0,
        servingG: 100,
        servingKcal: 250,
        estimatedProteinG: 10,
      );
      final per100 = result.computePackageNutritionPer100g(
        estimatedProteinG: 10,
      );
      expect(per100, isNotNull);
      expect(per100!.$1, closeTo(250, 0.001)); // 250 * 100 / 100
      expect(per100.$2, 0); // 10 * 0 = 0（mid=0 → per100Ratio=0）
    });

    test('hasPackageNutrition：仅 serving_kj>0 → false（M5：需 servingG 配合）', () {
      // M5 修复：与 computePackageNutritionPer100g 一致——
      // kj>0 但 servingG=0 时换算分母为 0 返回 null，getter 应一致返回 false
      final result = buildResult(
        servingG: 0,
        servingKj: 170,
        servingKcal: 0,
      );
      expect(result.hasPackageNutrition, isFalse);
    });

    test('hasPackageNutrition：仅 serving_kcal>0 → false（M5：需 servingG 配合）', () {
      // M5 修复：kcal>0 但 servingG=0 时换算分母为 0 返回 null，getter 应一致返回 false
      final result = buildResult(
        servingG: 0,
        servingKcal: 50,
      );
      expect(result.hasPackageNutrition, isFalse);
    });

    test('hasPackageNutrition：仅 serving_g>0 → false（M5：需能量配合）', () {
      // M5 修复：servingG>0 但 kj/kcal=0 时换算能量来源缺失返回 null，getter 应一致返回 false
      final result = buildResult(
        servingG: 10.5,
      );
      expect(result.hasPackageNutrition, isFalse);
    });

    test('hasPackageNutrition：所有 serving_* 为 0/null → false', () {
      final result = buildResult(
        servingG: 0,
        servingKj: 0,
        servingKcal: 0,
      );
      expect(result.hasPackageNutrition, isFalse);
    });

    test('hasPackageNutrition：所有 package_* 缺失 → false', () {
      final result = buildResult(); // 全部 package_* 为 null
      expect(result.hasPackageNutrition, isFalse);
    });

    test('v1.9 Gap3: 包装换算整菜热量 = per100g × mid / 100（珍宝珠酸条）', () {
      // 珍宝珠酸条 84g/8 条装：mid=84, serving_g=10.5, serving_kj=170
      // per100g = (170/4.184) * 100 / 10.5 = 386.96 kcal
      // 整菜热量 = 386.96 * 84 / 100 = 325.05 kcal ≈ AI 估算的 325
      // 验证 Gap3 修复：_aiFallbackNutrition 用包装换算整菜热量替代 AI 估算
      final result = buildResult(
        mid: 84,
        servingG: 10.5,
        servingKj: 170,
        servingKcal: 0,
        estimatedProteinG: 0,
        estimatedFatG: 0,
        estimatedCarbsG: 80,
      );
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNotNull);
      // 整菜热量 = per100g × mid / 100
      final wholeCalories = per100!.$1 * 84 / 100;
      expect(wholeCalories, closeTo(325, 0.5)); // 与 AI 估算的 325 一致
    });

    test('v1.9 Gap3: 包装换算整菜热量按 serving 缩放 = per100g × serving / 100', () {
      // 用户校准份量后：serving=42（半袋），整菜热量应按比例缩放
      // per100g=387, serving=42 → 387 * 42 / 100 = 162.5 kcal
      final result = buildResult(
        mid: 84,
        servingG: 10.5,
        servingKj: 170,
      );
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNotNull);
      const servingG = 42.0; // 用户校准为半袋
      final scaledCalories = per100!.$1 * servingG / 100;
      expect(scaledCalories, closeTo(162.5, 0.5)); // 325 / 2 ≈ 162.5
    });

    test('v1.9 Gap1: 复合菜有包装数据时 per100g 用包装换算值（非 0）', () {
      // 预包装速冻食品被识别为 composite 但有包装营养表
      // 复合菜分支应检查 hasPackageNutrition，用包装换算 per100g 替代 0
      final result = buildResult(
        mid: 300, // 速冻水饺一份 300g
        servingG: 100,
        servingKcal: 250, // 每份 250kcal
      );
      expect(result.hasPackageNutrition, isTrue);
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNotNull);
      expect(per100!.$1, closeTo(250, 0.001)); // 250 * 100 / 100 = 250
      // 复合菜分支应使用此值替代原来的 caloriesPer100g=0
    });

    test('v1.9 Gap3: mid=0 时包装换算整菜热量防除零', () {
      // mid=0 时整菜热量 = per100 * 0 / 100 = 0（防除零）
      // calories 仍按包装换算（不依赖 mid）
      final result = buildResult(
        mid: 0,
        servingG: 100,
        servingKcal: 250,
      );
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNotNull);
      expect(per100!.$1, closeTo(250, 0.001));
      final wholeCalories = per100.$1 * 0 / 100;
      expect(wholeCalories, 0); // mid=0 → 整菜热量 0
    });
  });

  // v1.10：包装每份宏量营养素字段解析 + 三层优先级换算
  group('v1.10 package_serving_protein_g/fat_g/carbs_g 字段解析', () {
    test('v1.10: 3 个新字段正常解析（菊花茶 250ml）', () {
      final json = {
        'dish_name': '菊花茶',
        'estimated_weight_g_mid': 250,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'package_serving_g': 250,
        'package_serving_kj': 272,
        'package_serving_kcal': 0,
        'package_serving_protein_g': 0,
        'package_serving_fat_g': 0,
        'package_serving_carbs_g': 16, // 关键：含糖饮料碳水必标
        'package_total_g': 250,
        'package_servings_per_pack': 1,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.10');
      expect(result.packageServingProteinG, 0);
      expect(result.packageServingFatG, 0);
      expect(result.packageServingCarbsG, 16);
      expect(result.hasPackageNutrition, isTrue);
    });

    test('v1.10: 3 个新字段缺失时为 null（v1.9 旧响应兼容）', () {
      final json = {
        'dish_name': '可乐',
        'estimated_weight_g_mid': 500,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'package_serving_g': 100,
        'package_serving_kj': 180,
        // v1.9 旧响应无 package_serving_protein_g 等 3 字段
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.9');
      expect(result.packageServingProteinG, isNull);
      expect(result.packageServingFatG, isNull);
      expect(result.packageServingCarbsG, isNull);
    });

    test('v1.10: 3 个新字段为 int 时正确转 double', () {
      final json = {
        'dish_name': '菊花茶',
        'estimated_weight_g_mid': 250,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'package_serving_g': 250,
        'package_serving_kcal': 65,
        'package_serving_protein_g': 0, // int
        'package_serving_fat_g': 0, // int
        'package_serving_carbs_g': 16, // int
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.10');
      expect(result.packageServingProteinG, 0.0);
      expect(result.packageServingFatG, 0.0);
      expect(result.packageServingCarbsG, 16.0);
    });
  });

  group('v1.10 computePackageNutritionPer100g 三层优先级', () {
    VisionRecognitionResult buildV110Result({
      required double servingG,
      double? servingKj,
      double? servingKcal,
      double? servingProteinG,
      double? servingFatG,
      double? servingCarbsG,
      String ocrText = '',
      double mid = 100,
      double? estimatedProteinG,
      double? estimatedFatG,
      double? estimatedCarbsG,
    }) {
      return VisionRecognitionResult(
        dishName: 'test',
        brand: '',
        estimatedWeightGLow: mid,
        estimatedWeightGMid: mid,
        estimatedWeightGHigh: mid,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.10',
        packageServingG: servingG,
        packageServingKj: servingKj,
        packageServingKcal: servingKcal,
        packageServingProteinG: servingProteinG,
        packageServingFatG: servingFatG,
        packageServingCarbsG: servingCarbsG,
        packageNutritionTableOcr: ocrText,
        estimatedProteinG: estimatedProteinG,
        estimatedFatG: estimatedFatG,
        estimatedCarbsG: estimatedCarbsG,
      );
    }

    test('第 1 层：包装字段优先（菊花茶 serving_carbs_g=16 → per100=6.4）', () {
      // 菊花茶 250ml/份，package_serving_carbs_g=16
      // per100Carbs = 16 * 100 / 250 = 6.4
      final result = buildV110Result(
        servingG: 250,
        servingKj: 272,
        servingProteinG: 0,
        servingFatG: 0,
        servingCarbsG: 16,
        ocrText: '每份250ml 能量272kJ 蛋白质0g 脂肪0g 碳水16g',
        // 即使 estimatedCarbsG 是错的，第 1 层优先用包装字段
        estimatedProteinG: 99,
        estimatedFatG: 99,
        estimatedCarbsG: 99,
      );
      final per100 = result.computePackageNutritionPer100g(
        estimatedProteinG: result.estimatedProteinG,
        estimatedFatG: result.estimatedFatG,
        estimatedCarbsG: result.estimatedCarbsG,
      );
      expect(per100, isNotNull);
      // servingKcal = 272/4.184 ≈ 65.009
      // per100Calories = 65.009 * 100 / 250 = 26.004
      expect(per100!.$1, closeTo(26, 0.1));
      expect(per100.$2, 0); // 蛋白 per100 = 0*100/250 = 0
      expect(per100.$3, 0); // 脂肪 per100 = 0*100/250 = 0
      expect(per100.$4, closeTo(6.4, 0.001)); // 碳水 per100 = 16*100/250 = 6.4
    });

    test('第 2 层：包装字段缺失时 OCR 正则提取兜底', () {
      // AI 漏填 package_serving_carbs_g（null），但 OCR 原文包含"碳水16g"
      final result = buildV110Result(
        servingG: 250,
        servingKj: 272,
        servingProteinG: null, // 漏填
        servingFatG: null, // 漏填
        servingCarbsG: null, // 漏填
        ocrText: '每份250ml 能量272kJ 蛋白质0g 脂肪0g 碳水16g',
        estimatedProteinG: 99, // 即使有 AI 估算，OCR 应优先
        estimatedFatG: 99,
        estimatedCarbsG: 99,
      );
      final per100 = result.computePackageNutritionPer100g(
        estimatedProteinG: result.estimatedProteinG,
        estimatedFatG: result.estimatedFatG,
        estimatedCarbsG: result.estimatedCarbsG,
      );
      expect(per100, isNotNull);
      expect(per100!.$2, 0); // OCR 提取 proteinG=0 → 0*100/250=0
      expect(per100.$3, 0); // OCR 提取 fatG=0 → 0*100/250=0
      expect(per100.$4, closeTo(6.4, 0.001)); // OCR 提取 carbsG=16 → 16*100/250=6.4
    });

    test('第 3 层：包装字段 + OCR 都缺失时 AI 估算反算', () {
      // AI 漏填 package_serving_* + OCR 原文为空 → 用 estimatedXxxG 反算
      final result = buildV110Result(
        servingG: 100,
        servingKcal: 50,
        servingProteinG: null,
        servingFatG: null,
        servingCarbsG: null,
        ocrText: '', // 无 OCR 数据
        mid: 200,
        estimatedProteinG: 10,
        estimatedFatG: 5,
        estimatedCarbsG: 30,
      );
      final per100 = result.computePackageNutritionPer100g(
        estimatedProteinG: 10,
        estimatedFatG: 5,
        estimatedCarbsG: 30,
      );
      expect(per100, isNotNull);
      expect(per100!.$1, closeTo(50, 0.001)); // 50 * 100 / 100
      expect(per100.$2, closeTo(5, 0.001)); // 10 * 100 / 200
      expect(per100.$3, closeTo(2.5, 0.001)); // 5 * 100 / 200
      expect(per100.$4, closeTo(15, 0.001)); // 30 * 100 / 200
    });

    test('第 1 层优先级覆盖第 2 层（包装字段 vs OCR 数据冲突）', () {
      // 包装字段 package_serving_carbs_g=20，OCR 提取 carbsG=16 → 用包装字段 20
      final result = buildV110Result(
        servingG: 100,
        servingKcal: 50,
        servingProteinG: 0,
        servingFatG: 0,
        servingCarbsG: 20, // 第 1 层
        ocrText: '碳水16g', // 第 2 层（应被忽略）
      );
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNotNull);
      expect(per100!.$4, 20); // 20 * 100 / 100 = 20，不是 16
    });

    test('v1.10 关键场景：菊花茶（包装字段路径）碳水非 0', () {
      // 用户反馈"菊花茶碳水缺失"的根因修复验证
      final result = buildV110Result(
        servingG: 250,
        servingKj: 272,
        servingProteinG: 0,
        servingFatG: 0,
        servingCarbsG: 16,
        ocrText: '每份250ml 能量272kJ 蛋白质0g 脂肪0g 碳水16g',
        mid: 250,
      );
      expect(result.hasPackageNutrition, isTrue);
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNotNull);
      // 关键断言：碳水 per100g 不为 0（v1.9 bug 是这里返回 0）
      expect(per100!.$4, closeTo(6.4, 0.001));
      expect(per100.$4 > 0, isTrue);
    });

    test('v1.10 关键场景：AI 漏填包装字段时 OCR 兜底碳水非 0', () {
      // AI 漏填 package_serving_carbs_g，但 OCR 包含"碳水16g"
      // 验证 OCR 兜底路径不会让碳水变 0
      final result = buildV110Result(
        servingG: 250,
        servingKj: 272,
        servingProteinG: null,
        servingFatG: null,
        servingCarbsG: null, // AI 漏填
        ocrText: '每份250ml 能量272kJ 蛋白质0g 脂肪0g 碳水16g',
        mid: 250,
      );
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNotNull);
      expect(per100!.$4, closeTo(6.4, 0.001));
      expect(per100.$4 > 0, isTrue);
    });

    test('v1.10 边界：3 字段为 0 时（含糖饮料蛋白/脂肪常为 0）仍走第 1 层', () {
      // 0 >= 0 满足条件，第 1 层命中，per100=0
      final result = buildV110Result(
        servingG: 250,
        servingKcal: 65,
        servingProteinG: 0,
        servingFatG: 0,
        servingCarbsG: 16,
      );
      final per100 = result.computePackageNutritionPer100g();
      expect(per100, isNotNull);
      expect(per100!.$2, 0); // 0*100/250=0（第 1 层命中，不是兜底）
      expect(per100.$3, 0);
      expect(per100.$4, closeTo(6.4, 0.001));
    });
  });

  group('v1.10 示例 8b 菊花茶端到端解析', () {
    test('从 prompts.dart 示例 8b 的 JSON 字段构造结果（关键参数齐全）', () {
      // 模拟 AI 返回示例 8b 的 JSON
      final json = {
        'reasoning': '盒装菊花茶饮料',
        'dish_name': '菊花茶',
        'brand': '',
        'quantity': 1,
        'unit': '盒',
        'per_unit_g': 250,
        'estimated_weight_g_low': 245,
        'estimated_weight_g_mid': 250,
        'estimated_weight_g_high': 255,
        'weight_source': 'package_label',
        'food_category': 'tea',
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'estimated_calories': 65,
        'estimated_protein_g': 0,
        'estimated_fat_g': 0,
        'estimated_carbs_g': 16,
        'package_nutrition_table_ocr': '每份250ml 能量272kJ 蛋白质0g 脂肪0g 碳水16g',
        'package_serving_g': 250,
        'package_serving_kj': 272,
        'package_serving_kcal': 0,
        'package_serving_protein_g': 0,
        'package_serving_fat_g': 0,
        'package_serving_carbs_g': 16,
        'package_total_g': 250,
        'package_servings_per_pack': 1,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.10');

      // 关键字段全部解析正确
      expect(result.dishName, '菊花茶');
      expect(result.foodCategory, 'tea');
      expect(result.weightSource, 'package_label');
      expect(result.estimatedWeightGMid, 250);
      expect(result.packageServingG, 250);
      expect(result.packageServingKj, 272);
      expect(result.packageServingCarbsG, 16);

      // 包装换算：per100g 碳水必须非 0（修复"菊花茶碳水缺失"的关键断言）
      expect(result.hasPackageNutrition, isTrue);
      final per100 = result.computePackageNutritionPer100g(
        estimatedProteinG: result.estimatedProteinG,
        estimatedFatG: result.estimatedFatG,
        estimatedCarbsG: result.estimatedCarbsG,
      );
      expect(per100, isNotNull);
      expect(per100!.$1, closeTo(26, 0.1)); // 65*100/250=26
      expect(per100.$4, closeTo(6.4, 0.001)); // 16*100/250=6.4
      expect(per100.$4 > 0, isTrue); // 关键：碳水不为 0
    });
  });

  // H1 修复：模型偶发漏返 cooking_method/is_single_item/confidence 时不崩溃
  group('H1 fromJson 关键字段缺失兜底', () {
    test('cooking_method/is_single_item/confidence 全缺时不崩溃', () {
      // 模拟 Qwen-VL 偶发漏返三个核心字段
      final json = {
        'dish_name': '番茄炒蛋',
        'estimated_weight_g_low': 100,
        'estimated_weight_g_mid': 150,
        'estimated_weight_g_high': 200,
        'food_components': [],
        // 故意漏掉 cooking_method / is_single_item / confidence
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.10');
      expect(result.cookingMethod, 'raw'); // 兜底默认
      expect(result.isSingleItem, true); // 兜底默认
      expect(result.confidence, 0.5); // 兜底默认
      expect(result.dishName, '番茄炒蛋'); // 正常解析
    });

    test('cooking_method 为 null 时不崩溃', () {
      final json = {
        'dish_name': '测试',
        'estimated_weight_g_mid': 100,
        'cooking_method': null, // 显式 null
        'is_single_item': true,
        'confidence': 0.8,
        'food_components': [],
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.10');
      expect(result.cookingMethod, 'raw');
    });
  });

  group('M5: hasPackageNutrition 与 computePackageNutritionPer100g 一致性', () {
    test('只有份量无能量时，getter 应返回 false（与 computePackageNutritionPer100g 一致）', () {
      // 边界场景：packageServingG=100 但 kj/kcal 都为 null
      // computePackageNutritionPer100g 会返回 null（servingKcal=0, kj=0 → return null）
      // hasPackageNutrition 也应返回 false，否则调用方误以为有包装数据却换算失败
      final result = VisionRecognitionResult(
        dishName: '测试',
        estimatedWeightGLow: 90,
        estimatedWeightGMid: 100,
        estimatedWeightGHigh: 110,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.10',
        packageServingG: 100, // 有份量
        packageServingKj: null, // 无能量
        packageServingKcal: null,
      );
      expect(result.hasPackageNutrition, false,
          reason: '只有份量无能量时，computePackageNutritionPer100g 返回 null，getter 应一致返回 false');
      expect(result.computePackageNutritionPer100g(), isNull);
    });

    test('有份量+kJ 时，getter 返回 true（与 computePackageNutritionPer100g 一致）', () {
      final result = VisionRecognitionResult(
        dishName: '测试',
        estimatedWeightGLow: 90,
        estimatedWeightGMid: 100,
        estimatedWeightGHigh: 110,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.10',
        packageServingG: 100,
        packageServingKj: 418,
        packageServingKcal: null,
      );
      expect(result.hasPackageNutrition, true);
      expect(result.computePackageNutritionPer100g(), isNotNull);
    });
  });

  group('M6: copyWith 支持修改 v1.9/v1.10 新增 package_* 字段', () {
    VisionRecognitionResult buildOriginal() => VisionRecognitionResult(
          dishName: '测试',
          estimatedWeightGLow: 90,
          estimatedWeightGMid: 100,
          estimatedWeightGHigh: 110,
          foodComponents: const [],
          cookingMethod: 'raw',
          isSingleItem: true,
          confidence: 0.9,
          promptVersion: 'v1.10',
          packageNutritionTableOcr: '原始 OCR',
          packageServingG: 100,
          packageServingKj: 418,
          packageServingKcal: 100,
          packageServingProteinG: 3,
          packageServingFatG: 1,
          packageServingCarbsG: 20,
          packageTotalG: 500,
          packageServingsPerPack: 5,
        );

    test('copyWith 可修改 packageNutritionTableOcr', () {
      final copied = buildOriginal().copyWith(packageNutritionTableOcr: '修正后 OCR');
      expect(copied.packageNutritionTableOcr, '修正后 OCR');
    });

    test('copyWith 可修改 packageServingG', () {
      final copied = buildOriginal().copyWith(packageServingG: 200);
      expect(copied.packageServingG, 200);
    });

    test('copyWith 可修改 packageServingKj', () {
      final copied = buildOriginal().copyWith(packageServingKj: 836);
      expect(copied.packageServingKj, 836);
    });

    test('copyWith 可修改 packageServingKcal', () {
      final copied = buildOriginal().copyWith(packageServingKcal: 200);
      expect(copied.packageServingKcal, 200);
    });

    test('copyWith 可修改 packageServingProteinG', () {
      final copied = buildOriginal().copyWith(packageServingProteinG: 6);
      expect(copied.packageServingProteinG, 6);
    });

    test('copyWith 可修改 packageServingFatG', () {
      final copied = buildOriginal().copyWith(packageServingFatG: 2);
      expect(copied.packageServingFatG, 2);
    });

    test('copyWith 可修改 packageServingCarbsG', () {
      final copied = buildOriginal().copyWith(packageServingCarbsG: 40);
      expect(copied.packageServingCarbsG, 40);
    });

    test('copyWith 可修改 packageTotalG', () {
      final copied = buildOriginal().copyWith(packageTotalG: 1000);
      expect(copied.packageTotalG, 1000);
    });

    test('copyWith 可修改 packageServingsPerPack', () {
      final copied = buildOriginal().copyWith(packageServingsPerPack: 10);
      expect(copied.packageServingsPerPack, 10);
    });

    test('copyWith 修改一个 package_* 字段时其他字段保持不变', () {
      final original = buildOriginal();
      final copied = original.copyWith(packageServingG: 200);
      expect(copied.packageNutritionTableOcr, '原始 OCR');
      expect(copied.packageServingKj, 418);
      expect(copied.packageServingKcal, 100);
      expect(copied.packageServingProteinG, 3);
      expect(copied.packageServingFatG, 1);
      expect(copied.packageServingCarbsG, 20);
      expect(copied.packageTotalG, 500);
      expect(copied.packageServingsPerPack, 5);
    });
  });
}
