// 识别结果后处理器单元测试（第二波：三路径一致性）
//
// 覆盖 RecognitionPostProcessor.process 完整链路：
// 1. 密度换算（建议 3）：包装液体 ml→g
// 2. 营养素自洽修正（批次 1）：4p+9f+4c≠cal 反推
// 3. 组分份量交叉验证（建议 7）：sum vs mid 缩放
// 4. additionalDishes 修正
// 5. 链式执行：换算 → 校验 → 修正顺序正确
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/core/util/recognition_post_processor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('process 完整链路 - 密度换算', () {
    test('500ml 食用油 → mid 460g（密度 0.92）', () {
      final original = VisionRecognitionResult(
        dishName: '食用油',
        brand: '金龙鱼',
        estimatedWeightGLow: 485,
        estimatedWeightGMid: 500,
        estimatedWeightGHigh: 515,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
        quantity: 1,
        unit: '瓶',
        perUnitG: 500,
        weightSource: 'package_label',
        foodCategory: 'oil',
        estimatedCalories: 4094,
        estimatedProteinG: 0,
        estimatedFatG: 460,
        estimatedCarbsG: 0,
      );
      final result = RecognitionPostProcessor.process(original);
      expect(result.estimatedWeightGMid, closeTo(460, 0.1));
      expect(result.perUnitG, closeTo(460, 0.1));
      // 区间 ±3%
      expect(result.estimatedWeightGLow, closeTo(446.2, 0.1));
      expect(result.estimatedWeightGHigh, closeTo(473.8, 0.1));
    });

    test('250ml 蜂蜜 → mid 355g（密度 1.42）', () {
      final original = VisionRecognitionResult(
        dishName: '蜂蜜',
        estimatedWeightGLow: 240,
        estimatedWeightGMid: 250,
        estimatedWeightGHigh: 260,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
        quantity: 1,
        unit: '瓶',
        perUnitG: 250,
        weightSource: 'package_label',
        foodCategory: 'honey',
      );
      final result = RecognitionPostProcessor.process(original);
      expect(result.estimatedWeightGMid, closeTo(355, 0.1));
      expect(result.perUnitG, closeTo(355, 0.1));
    });

    test('500ml 可乐（密度 1.0）不换算', () {
      final original = VisionRecognitionResult(
        dishName: '可乐',
        estimatedWeightGLow: 490,
        estimatedWeightGMid: 500,
        estimatedWeightGHigh: 510,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
        quantity: 1,
        unit: '瓶',
        perUnitG: 500,
        weightSource: 'package_label',
        foodCategory: 'carbonated',
      );
      final result = RecognitionPostProcessor.process(original);
      expect(result.estimatedWeightGMid, 500);
      expect(result.perUnitG, 500);
    });

    test('散装菜（ai_estimate）即使液体类别也不换算', () {
      final original = VisionRecognitionResult(
        dishName: '牛奶',
        estimatedWeightGLow: 240,
        estimatedWeightGMid: 250,
        estimatedWeightGHigh: 260,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
        quantity: 1,
        unit: '杯',
        perUnitG: 250,
        weightSource: 'ai_estimate', // 散装，视觉估算已是克数
        foodCategory: 'milk',
      );
      final result = RecognitionPostProcessor.process(original);
      expect(result.estimatedWeightGMid, 250);
    });

    test('2 瓶 500ml 油 → mid 920g（quantity=2）', () {
      final original = VisionRecognitionResult(
        dishName: '食用油',
        estimatedWeightGLow: 970,
        estimatedWeightGMid: 1000,
        estimatedWeightGHigh: 1030,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
        quantity: 2,
        unit: '瓶',
        perUnitG: 500,
        weightSource: 'package_label',
        foodCategory: 'oil',
      );
      final result = RecognitionPostProcessor.process(original);
      // realPerUnitG = 500 * 0.92 = 460, realMid = 460 * 2 = 920
      expect(result.perUnitG, closeTo(460, 0.1));
      expect(result.estimatedWeightGMid, closeTo(920, 0.1));
    });
  });

  group('process 完整链路 - 营养素自洽修正', () {
    test('calories 不自洽（偏差>10%）反推修正', () {
      // expected = 4*0+9*460+4*0 = 4140, cal=5000, 偏差 17.2% → 修正
      final original = VisionRecognitionResult(
        dishName: '油',
        estimatedWeightGLow: 460,
        estimatedWeightGMid: 460,
        estimatedWeightGHigh: 460,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
        estimatedCalories: 5000,
        estimatedProteinG: 0,
        estimatedFatG: 460,
        estimatedCarbsG: 0,
      );
      final result = RecognitionPostProcessor.process(original);
      expect(result.estimatedCalories, 4140);
    });

    test('calories 自洽（偏差<10%）不修正', () {
      // expected = 4*0+9*460+4*0 = 4140, cal=4094, 偏差 1.1% ✓
      final original = VisionRecognitionResult(
        dishName: '油',
        estimatedWeightGLow: 460,
        estimatedWeightGMid: 460,
        estimatedWeightGHigh: 460,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
        estimatedCalories: 4094,
        estimatedProteinG: 0,
        estimatedFatG: 460,
        estimatedCarbsG: 0,
      );
      final result = RecognitionPostProcessor.process(original);
      expect(result.estimatedCalories, 4094);
    });
  });

  group('process 完整链路 - 组分份量交叉验证', () {
    test('sum(components) 远大于 mid → 按 mid 缩放', () {
      // sum=270g, mid=200g, ratio=0.74, 偏差 26% > 15% → 缩放
      final original = VisionRecognitionResult(
        dishName: '番茄炒蛋',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        foodComponents: const [
          FoodComponent(name: '鸡蛋', estimatedG: 120),
          FoodComponent(name: '番茄', estimatedG: 150),
        ],
        cookingMethod: 'stir-fry',
        isSingleItem: false,
        confidence: 0.85,
        promptVersion: 'v1.7',
      );
      final result = RecognitionPostProcessor.process(original);
      // ratio = 200/270 ≈ 0.7407
      // 鸡蛋 120*0.7407 ≈ 88.89, 番茄 150*0.7407 ≈ 111.11
      expect(result.foodComponents[0].estimatedG, closeTo(88.89, 0.1));
      expect(result.foodComponents[1].estimatedG, closeTo(111.11, 0.1));
      // 名称保留
      expect(result.foodComponents[0].name, '鸡蛋');
      expect(result.foodComponents[1].name, '番茄');
    });

    test('sum(components) 偏差<15% 不缩放', () {
      // sum=210g, mid=200g, ratio=0.95, 偏差 5% < 15% ✓
      final original = VisionRecognitionResult(
        dishName: '番茄炒蛋',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        foodComponents: const [
          FoodComponent(name: '鸡蛋', estimatedG: 100),
          FoodComponent(name: '番茄', estimatedG: 110),
        ],
        cookingMethod: 'stir-fry',
        isSingleItem: false,
        confidence: 0.85,
        promptVersion: 'v1.7',
      );
      final result = RecognitionPostProcessor.process(original);
      expect(result.foodComponents[0].estimatedG, 100);
      expect(result.foodComponents[1].estimatedG, 110);
    });

    test('单品不触发组分交叉验证', () {
      final original = VisionRecognitionResult(
        dishName: '苹果',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
      );
      final result = RecognitionPostProcessor.process(original);
      expect(result.foodComponents, isEmpty);
    });
  });

  group('process 完整链路 - additionalDishes 修正', () {
    test('附加菜 calories 不自洽 → 修正', () {
      final additional = VisionRecognitionResult(
        dishName: '油',
        estimatedWeightGLow: 460,
        estimatedWeightGMid: 460,
        estimatedWeightGHigh: 460,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
        estimatedCalories: 5000, // 不自洽
        estimatedProteinG: 0,
        estimatedFatG: 460,
        estimatedCarbsG: 0,
      );
      final original = VisionRecognitionResult(
        dishName: '主菜',
        estimatedWeightGLow: 200,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 200,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
        additionalDishes: [additional],
      );
      final result = RecognitionPostProcessor.process(original);
      expect(result.additionalDishes.first.estimatedCalories, 4140);
    });

    test('附加菜密度换算（500ml 油 → 460g）', () {
      final additional = VisionRecognitionResult(
        dishName: '食用油',
        estimatedWeightGLow: 485,
        estimatedWeightGMid: 500,
        estimatedWeightGHigh: 515,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
        quantity: 1,
        unit: '瓶',
        perUnitG: 500,
        weightSource: 'package_label',
        foodCategory: 'oil',
      );
      final original = VisionRecognitionResult(
        dishName: '主菜',
        estimatedWeightGLow: 200,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 200,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
        additionalDishes: [additional],
      );
      final result = RecognitionPostProcessor.process(original);
      expect(result.additionalDishes.first.estimatedWeightGMid, closeTo(460, 0.1));
    });

    test('无附加菜时返回原结果（无重建）', () {
      final original = VisionRecognitionResult(
        dishName: '苹果',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
      );
      final result = RecognitionPostProcessor.process(original);
      expect(result.additionalDishes, isEmpty);
    });
  });

  group('process 完整链路 - 链式执行顺序', () {
    test('密度换算 → 组分交叉验证：换算后 mid 参与组分缩放判断', () {
      // 油瓶 mid=500ml，换算后 mid=460g
      // 组分（不合理场景：油有组分）sum=300g, ratio=460/300=1.53, 偏差 53% → 缩放
      // 验证：缩放用的是换算后的 mid（460），不是原 mid（500）
      final original = VisionRecognitionResult(
        dishName: '调合油',
        estimatedWeightGLow: 485,
        estimatedWeightGMid: 500, // ml
        estimatedWeightGHigh: 515,
        foodComponents: const [
          FoodComponent(name: '组分A', estimatedG: 150),
          FoodComponent(name: '组分B', estimatedG: 150),
        ],
        cookingMethod: 'raw',
        isSingleItem: false,
        confidence: 0.9,
        promptVersion: 'v1.7',
        quantity: 1,
        unit: '瓶',
        perUnitG: 500,
        weightSource: 'package_label',
        foodCategory: 'oil',
      );
      final result = RecognitionPostProcessor.process(original);
      // 换算后 mid=460，sum=300，ratio=460/300≈1.533
      // 组分A 150*1.533≈230, 组分B 150*1.533≈230
      expect(result.estimatedWeightGMid, closeTo(460, 0.1));
      expect(result.foodComponents[0].estimatedG, closeTo(230, 0.5));
      expect(result.foodComponents[1].estimatedG, closeTo(230, 0.5));
    });

    test('密度换算 → 营养素自洽：换算后不影响自洽判断（用宏量营养素反推）', () {
      // 油瓶 mid=500ml→460g，calories 不自洽
      // 验证：自洽判断用 estimatedFatG（460g）反推，不受 mid 换算影响
      final original = VisionRecognitionResult(
        dishName: '食用油',
        estimatedWeightGLow: 485,
        estimatedWeightGMid: 500,
        estimatedWeightGHigh: 515,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
        quantity: 1,
        unit: '瓶',
        perUnitG: 500,
        weightSource: 'package_label',
        foodCategory: 'oil',
        estimatedCalories: 9999, // 严重不自洽
        estimatedProteinG: 0,
        estimatedFatG: 460,
        estimatedCarbsG: 0,
      );
      final result = RecognitionPostProcessor.process(original);
      // expected = 4*0+9*460+4*0 = 4140
      expect(result.estimatedCalories, 4140);
      expect(result.estimatedWeightGMid, closeTo(460, 0.1));
    });
  });

  group('applyDensityConversion 单独调用', () {
    test('返回新对象（换算发生时）', () {
      final original = VisionRecognitionResult(
        dishName: '油',
        estimatedWeightGLow: 485,
        estimatedWeightGMid: 500,
        estimatedWeightGHigh: 515,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
        quantity: 1,
        unit: '瓶',
        perUnitG: 500,
        weightSource: 'package_label',
        foodCategory: 'oil',
      );
      final result =
          RecognitionPostProcessor.applyDensityConversion(original);
      expect(identical(result, original), isFalse);
      expect(result.estimatedWeightGMid, closeTo(460, 0.1));
    });

    test('返回原对象（无换算时，避免无谓重建）', () {
      final original = VisionRecognitionResult(
        dishName: '苹果',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.7',
      );
      final result =
          RecognitionPostProcessor.applyDensityConversion(original);
      expect(identical(result, original), isTrue);
    });
  });

  group('v1.9 reasoning + package_* 字段透传', () {
    test('process 后 reasoning 字段不丢失（密度换算路径）', () {
      // 500ml 食用油触发密度换算 → 重建主菜
      // 验证 reasoning + package_* 字段在重建后仍保留
      final original = VisionRecognitionResult(
        dishName: '食用油',
        brand: '金龙鱼',
        estimatedWeightGLow: 485,
        estimatedWeightGMid: 500,
        estimatedWeightGHigh: 515,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.9',
        quantity: 1,
        unit: '瓶',
        perUnitG: 500,
        weightSource: 'package_label',
        foodCategory: 'oil',
        estimatedCalories: 4094,
        estimatedProteinG: 0,
        estimatedFatG: 460,
        estimatedCarbsG: 0,
        reasoning: '500ml 金龙鱼食用油，密度 0.92 真实约 460g',
        packageNutritionTableOcr: '每100g 889kcal',
        packageServingG: 100,
        packageServingKj: 3720,
        packageServingKcal: 889,
        packageTotalG: 500,
        packageServingsPerPack: 5,
      );
      final result = RecognitionPostProcessor.process(original);
      // 密度换算后 mid 变 460，但 reasoning + package_* 必须保留
      expect(result.estimatedWeightGMid, closeTo(460, 0.1));
      expect(result.reasoning, '500ml 金龙鱼食用油，密度 0.92 真实约 460g');
      expect(result.packageNutritionTableOcr, '每100g 889kcal');
      expect(result.packageServingG, 100);
      expect(result.packageServingKj, 3720);
      expect(result.packageServingKcal, 889);
      expect(result.packageTotalG, 500);
      expect(result.packageServingsPerPack, 5);
    });

    test('process 后 reasoning 字段不丢失（additionalDishes 修正路径）', () {
      // 主菜 + 附加菜，附加菜 calories 不自洽触发 correctAdditionalDishes 重建
      // 验证主菜的 reasoning + package_* 在重建后仍保留
      final original = VisionRecognitionResult(
        dishName: '米饭',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        foodComponents: const [],
        cookingMethod: 'steam',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.9',
        reasoning: '一碗米饭约 200g，以 11cm 饭碗为参照',
        packageNutritionTableOcr: '',
        additionalDishes: [
          VisionRecognitionResult(
            dishName: '宫保鸡丁',
            estimatedWeightGLow: 240,
            estimatedWeightGMid: 250,
            estimatedWeightGHigh: 260,
            foodComponents: const [],
            cookingMethod: 'stir-fry',
            isSingleItem: false,
            confidence: 0.85,
            promptVersion: 'v1.9',
            estimatedCalories: 9999, // 严重不自洽触发修正
            estimatedProteinG: 20,
            estimatedFatG: 15,
            estimatedCarbsG: 10,
          ),
        ],
      );
      final result = RecognitionPostProcessor.process(original);
      // 主菜 reasoning 必须保留（correctAdditionalDishes 重建主菜）
      expect(result.reasoning, '一碗米饭约 200g，以 11cm 饭碗为参照');
      expect(result.dishName, '米饭');
    });

    test('process 后 reasoning 为 null 时仍为 null（旧 prompt 兼容）', () {
      final original = VisionRecognitionResult(
        dishName: '苹果',
        estimatedWeightGLow: 150,
        estimatedWeightGMid: 180,
        estimatedWeightGHigh: 220,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.8',
        // reasoning + package_* 全部缺失（v1.8 旧响应）
      );
      final result = RecognitionPostProcessor.process(original);
      expect(result.reasoning, isNull);
      expect(result.packageNutritionTableOcr, '');
      expect(result.packageServingG, isNull);
      expect(result.hasPackageNutrition, isFalse);
    });
  });
}
