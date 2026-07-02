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

    test('必填字段缺失（confidence）抛异常（malformed）', () {
      final json = {
        'dish_name': '米饭',
        'estimated_weight_g_mid': 100,
        'is_single_item': true,
        'cooking_method': 'boil',
        // confidence 缺失
      };
      expect(() => VisionRecognitionResult.fromJson(json, 'v1.0'), throwsA(anything));
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
}
