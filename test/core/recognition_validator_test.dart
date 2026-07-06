// 识别结果校验器单元测试（v2 重构后的剩余字段合理性 + 组分份量验证）
//
// v2 重构变更（详见 recognition_validator_v2_test.dart）：
// - 删除 "营养素自洽性校验" group（Atwater 修正已删，correctedCalories 不存在）
// - 删除 "v1.10 宏量反推修正" group（宏量反推已删，correctedProteinG/FatG/CarbsG 不存在）
// - 删除 "v1.10 BUG-2 边界场景" group（同上）
// - 删除 "旧 prompt 兼容" group（旧 prompt 兼容性已在 v2 测试覆盖）
//
// 保留：
// - "字段合理性校验" group（dishName/confidence/weight/区间 → needsRetry）
// - "组分份量交叉验证" group（sum(components) vs mid 偏差>15% 按 mid 缩放）
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/core/util/recognition_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 合法基准结果（2 罐可乐，营养素自洽：cal=277, 4*0+9*0+4*69=276，偏差 0.4%）
  VisionRecognitionResult validResult({
    String dishName = '可乐',
    double confidence = 0.9,
    double mid = 660,
    double low = 600,
    double high = 720,
    double? cal = 277,
    double? protein = 0,
    double? fat = 0,
    double? carbs = 69,
  }) {
    return VisionRecognitionResult(
      dishName: dishName,
      brand: '可口可乐',
      estimatedWeightGLow: low,
      estimatedWeightGMid: mid,
      estimatedWeightGHigh: high,
      foodComponents: const [],
      cookingMethod: 'raw',
      isSingleItem: true,
      confidence: confidence,
      promptVersion: 'v1.5',
      quantity: 2,
      unit: '罐',
      perUnitG: 330,
      estimatedCalories: cal,
      estimatedProteinG: protein,
      estimatedFatG: fat,
      estimatedCarbsG: carbs,
    );
  }

  group('字段合理性校验', () {
    test('合法结果通过校验', () {
      final v = RecognitionValidator.validate(validResult());
      expect(v.isValid, isTrue);
      expect(v.needsRetry, isFalse);
      expect(v.reasons, isEmpty);
    });

    test('dishName 为空触发重试', () {
      final v = RecognitionValidator.validate(validResult(dishName: ''));
      expect(v.needsRetry, isTrue);
      expect(v.reasons, contains('dish_name 为空'));
    });

    test('dishName 仅空格触发重试', () {
      final v = RecognitionValidator.validate(validResult(dishName: '   '));
      expect(v.needsRetry, isTrue);
    });

    test('confidence < 0 触发重试', () {
      final v = RecognitionValidator.validate(validResult(confidence: -0.1));
      expect(v.needsRetry, isTrue);
      expect(v.reasons.any((r) => r.contains('confidence 越界')), isTrue);
    });

    test('confidence > 1 触发重试', () {
      final v = RecognitionValidator.validate(validResult(confidence: 1.5));
      expect(v.needsRetry, isTrue);
    });

    test('confidence 边界 0 和 1 通过', () {
      expect(
          RecognitionValidator.validate(validResult(confidence: 0)).needsRetry,
          isFalse);
      expect(
          RecognitionValidator.validate(validResult(confidence: 1)).needsRetry,
          isFalse);
    });

    test('estimatedWeightGMid <= 0 触发重试', () {
      final v = RecognitionValidator.validate(validResult(mid: 0));
      expect(v.needsRetry, isTrue);
      expect(v.reasons.any((r) => r.contains('estimated_weight_g_mid 非正')),
          isTrue);
    });

    test('区间倒置 low > mid 触发重试', () {
      final v = RecognitionValidator.validate(validResult(low: 700, mid: 660));
      expect(v.needsRetry, isTrue);
      expect(v.reasons.any((r) => r.contains('重量区间倒置')), isTrue);
    });

    test('区间倒置 high < mid 触发重试', () {
      final v = RecognitionValidator.validate(validResult(high: 600, mid: 660));
      expect(v.needsRetry, isTrue);
    });

    test('区间相等（low==mid==high）通过（单品精确值）', () {
      final v = RecognitionValidator.validate(
          validResult(low: 660, mid: 660, high: 660));
      expect(v.needsRetry, isFalse);
    });
  });

  // 建议 7：复合菜组分份量交叉验证
  group('组分份量交叉验证', () {
    VisionRecognitionResult compositeResult({
      required double mid,
      required List<FoodComponent> components,
    }) {
      return VisionRecognitionResult(
        dishName: '番茄炒蛋',
        brand: '',
        estimatedWeightGLow: mid * 0.9,
        estimatedWeightGMid: mid,
        estimatedWeightGHigh: mid * 1.1,
        foodComponents: components,
        cookingMethod: 'stir-fry',
        isSingleItem: false,
        confidence: 0.85,
        promptVersion: 'v1.6',
      );
    }

    test('组份之和与 mid 偏差<15% 不修正', () {
      // sum=270, mid=250, ratio=0.926, 偏差 7.4% < 15% ✓
      final v = RecognitionValidator.validate(compositeResult(
        mid: 250,
        components: const [
          FoodComponent(name: '鸡蛋', estimatedG: 120),
          FoodComponent(name: '番茄', estimatedG: 150),
        ],
      ));
      expect(v.correctedComponents, isNull);
      expect(v.reasons.any((r) => r.contains('组分份量不自洽')), isFalse);
    });

    test('组份之和远大于 mid（偏差>15%）按 mid 缩放', () {
      // sum=400, mid=250, ratio=0.625, 偏差 37.5% > 15% → 缩放
      final v = RecognitionValidator.validate(compositeResult(
        mid: 250,
        components: const [
          FoodComponent(name: '鸡蛋', estimatedG: 200),
          FoodComponent(name: '番茄', estimatedG: 200),
        ],
      ));
      expect(v.correctedComponents, isNotNull);
      // 缩放后：200*0.625=125, 200*0.625=125
      expect(v.correctedComponents![0].estimatedG, closeTo(125, 0.01));
      expect(v.correctedComponents![1].estimatedG, closeTo(125, 0.01));
      // 缩放后总和 == mid
      final sum = v.correctedComponents!.fold(0.0, (s, c) => s + c.estimatedG);
      expect(sum, closeTo(250, 0.01));
    });

    test('组份之和远小于 mid（偏差>15%）按 mid 放大', () {
      // sum=150, mid=250, ratio=1.667, 偏差 66.7% > 15% → 放大
      final v = RecognitionValidator.validate(compositeResult(
        mid: 250,
        components: const [
          FoodComponent(name: '鸡蛋', estimatedG: 80),
          FoodComponent(name: '番茄', estimatedG: 70),
        ],
      ));
      expect(v.correctedComponents, isNotNull);
      expect(v.correctedComponents![0].estimatedG, closeTo(133.33, 0.01));
      expect(v.correctedComponents![1].estimatedG, closeTo(116.67, 0.01));
    });

    test('单品（isSingleItem=true）不触发组分校验', () {
      final v = RecognitionValidator.validate(validResult());
      expect(v.correctedComponents, isNull);
    });

    test('复合菜但组分空不触发校验', () {
      final v = RecognitionValidator.validate(VisionRecognitionResult(
        dishName: '神秘菜',
        brand: '',
        estimatedWeightGLow: 225,
        estimatedWeightGMid: 250,
        estimatedWeightGHigh: 275,
        foodComponents: const [],
        cookingMethod: 'stir-fry',
        isSingleItem: false,
        confidence: 0.8,
        promptVersion: 'v1.6',
      ));
      expect(v.correctedComponents, isNull);
    });

    test('组份之和=0 不触发校验（防除零）', () {
      final v = RecognitionValidator.validate(compositeResult(
        mid: 250,
        components: const [
          FoodComponent(name: 'A', estimatedG: 0),
          FoodComponent(name: 'B', estimatedG: 0),
        ],
      ));
      expect(v.correctedComponents, isNull);
    });

    test('mid=0 不触发校验（防除零）', () {
      final v = RecognitionValidator.validate(compositeResult(
        mid: 0,
        components: const [
          FoodComponent(name: 'A', estimatedG: 100),
        ],
      ));
      // mid=0 会被字段校验拦截（needsRetry），但不应该触发组分校验
      expect(v.correctedComponents, isNull);
    });

    test('缩放后组分名保持不变', () {
      final v = RecognitionValidator.validate(compositeResult(
        mid: 200,
        components: const [
          FoodComponent(name: '鸡蛋', estimatedG: 200),
          FoodComponent(name: '番茄', estimatedG: 200),
        ],
      ));
      expect(v.correctedComponents, isNotNull);
      expect(v.correctedComponents![0].name, '鸡蛋');
      expect(v.correctedComponents![1].name, '番茄');
    });
  });
}
