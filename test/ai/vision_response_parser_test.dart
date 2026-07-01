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
  });
}
