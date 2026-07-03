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
          {'name': '番茄', 'estimated_g': 150},
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
      expect(result.estimatedWeightGLow, 100); // 回退 Mid
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
      expect(result.estimatedWeightGHigh, 100); // 回退 Mid
    });

    test('必填字段缺失（dishName）抛异常（malformed）', () {
      final json = {
        'estimated_weight_g_mid': 100,
        'is_single_item': true,
        'cooking_method': 'boil',
        'confidence': 0.9,
        // dish_name 缺失
      };
      expect(
        () => VisionRecognitionResult.fromJson(json, 'v1.0'),
        throwsA(anything),
      );
    });

    test('必填字段缺失（confidence）抛异常（malformed）', () {
      final json = {
        'dish_name': '米饭',
        'estimated_weight_g_mid': 100,
        'is_single_item': true,
        'cooking_method': 'boil',
        // confidence 缺失
      };
      expect(
        () => VisionRecognitionResult.fromJson(json, 'v1.0'),
        throwsA(anything),
      );
    });

    test('字段类型错误：estimated_weight_g_mid 为字符串抛异常（as num 失败）', () {
      final json = {
        'dish_name': '米饭',
        'estimated_weight_g_mid': '100', // 字符串，as num 失败
        'is_single_item': true,
        'cooking_method': 'boil',
        'confidence': 0.9,
      };
      expect(
        () => VisionRecognitionResult.fromJson(json, 'v1.0'),
        throwsA(anything),
      );
    });

    test('v1.1 营养字段正确解析', () {
      final json = {
        'dish_name': '苹果',
        'estimated_weight_g_mid': 180,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
        'estimated_calories': 94,
        'estimated_protein_g': 0.5,
        'estimated_fat_g': 0.6,
        'estimated_carbs_g': 25,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.1');
      expect(result.estimatedCalories, 94.0);
      expect(result.estimatedProteinG, 0.5);
      expect(result.estimatedFatG, 0.6);
      expect(result.estimatedCarbsG, 25.0);
    });

    test('旧 schema(v1.0) 缺营养字段时为 null（向后兼容）', () {
      final json = {
        'dish_name': '苹果',
        'estimated_weight_g_mid': 180,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.0');
      expect(result.estimatedCalories, isNull);
      expect(result.estimatedProteinG, isNull);
      expect(result.estimatedFatG, isNull);
      expect(result.estimatedCarbsG, isNull);
    });

    test('v1.1 营养字段为 int 时正确转 double', () {
      final json = {
        'dish_name': '米饭',
        'estimated_weight_g_mid': 150,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'boil',
        'confidence': 0.9,
        'estimated_calories': 200, // int
        'estimated_protein_g': 4,
        'estimated_fat_g': 1,
        'estimated_carbs_g': 44,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.1');
      expect(result.estimatedCalories, 200.0);
      expect(result.estimatedProteinG, 4.0);
    });
  });
}
