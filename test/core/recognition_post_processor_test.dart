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

  group('process 完整链路 - 营养素自洽（v2：保留 AI 值 + warnings 提示）', () {
    test('v2: calories 不自洽（偏差>10%）保留 AI 值 + warnings 含不自洽提示', () {
      // expected = 4*0+9*460+4*0 = 4140, cal=5000, 偏差 17.2%
      // v2 改动 A：删除 Atwater 修正，保留 AI 值 5000 + warnings 提示用户核对
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
      // v2：AI 值绝对优先，不被 Atwater 修正覆盖
      expect(result.estimatedCalories, 5000,
          reason: 'v2 改动 A：AI 值 5000 不被 Atwater 修正为 4140');
      // warnings 应含"宏量与热量不自洽"提示
      expect(result.warnings.any((w) => w.contains('不自洽')), isTrue,
          reason: 'v2 改动 A：偏差>10% 应输出 warnings 提示用户核对');
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

  group('process 完整链路 - additionalDishes 修正（v2：保留 AI 值 + warnings）', () {
    test('v2: 附加菜 calories 不自洽 → 保留 AI 值 + warnings 提示', () {
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
      // v2 改动 A：附加菜 AI 值绝对优先，不被 Atwater 修正覆盖
      expect(result.additionalDishes.first.estimatedCalories, 5000,
          reason: 'v2：附加菜 AI 值 5000 不被 Atwater 修正为 4140');
      // warnings 应含"不自洽"提示（透传到附加菜）
      expect(
          result.additionalDishes.first.warnings
              .any((w) => w.contains('不自洽')),
          isTrue,
          reason: 'v2：附加菜偏差>10% 应输出 warnings 提示');
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

    test('v2: 密度换算不影响 warnings 检测（换算后保留 AI 值 + warnings 提示）', () {
      // 油瓶 mid=500ml→460g，calories 不自洽
      // v2 改动 A：删除 Atwater 修正，密度换算后仍保留 AI 值 9999 + warnings 提示
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
      // v2：AI 值绝对优先，密度换算后仍保留 AI 值 9999（不被 Atwater 修正为 4140）
      expect(result.estimatedCalories, 9999,
          reason: 'v2：AI 值 9999 不被 Atwater 修正');
      expect(result.estimatedWeightGMid, closeTo(460, 0.1));
      // warnings 应含"不自洽"提示
      expect(result.warnings.any((w) => w.contains('不自洽')), isTrue,
          reason: 'v2：偏差>10% 应输出 warnings 提示用户核对');
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

  // v1.10：3 个新字段 packageServingProteinG/FatG/CarbsG 透传完整性
  // 修复 bug：applyDensityConversion + correctAdditionalDishes 两处重建遗漏
  group('v1.10 package_serving_protein_g/fat_g/carbs_g 透传', () {
    test('密度换算路径：3 个新字段在重建后保留（500ml 食用油）', () {
      // 触发密度换算：液体 + package_label + density≠1.0（油密度 0.92）
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
        promptVersion: 'v1.10',
        quantity: 1,
        unit: '瓶',
        perUnitG: 500,
        weightSource: 'package_label',
        foodCategory: 'oil',
        estimatedCalories: 4094,
        estimatedProteinG: 0,
        estimatedFatG: 460,
        estimatedCarbsG: 0,
        reasoning: '500ml 食用油，密度 0.92 真实约 460g',
        packageNutritionTableOcr: '每100g 889kcal 蛋白质0g 脂肪99.9g 碳水0g',
        packageServingG: 100,
        packageServingKj: 3720,
        packageServingKcal: 889,
        packageServingProteinG: 0,
        packageServingFatG: 99.9,
        packageServingCarbsG: 0,
        packageTotalG: 500,
        packageServingsPerPack: 5,
      );
      final result = RecognitionPostProcessor.process(original);
      // 密度换算后 mid 变 460
      expect(result.estimatedWeightGMid, closeTo(460, 0.1));
      // v1.10 新增 3 字段必须保留（不能因重建丢失）
      expect(result.packageServingProteinG, 0);
      expect(result.packageServingFatG, 99.9);
      expect(result.packageServingCarbsG, 0);
      // 旧 package_* 字段也保留
      expect(result.packageNutritionTableOcr, '每100g 889kcal 蛋白质0g 脂肪99.9g 碳水0g');
      expect(result.packageServingG, 100);
      expect(result.packageServingKj, 3720);
      expect(result.packageServingKcal, 889);
      expect(result.packageTotalG, 500);
      expect(result.packageServingsPerPack, 5);
    });

    test('additionalDishes 修正路径：3 个新字段在重建后保留', () {
      // 主菜 + 附加菜，附加菜 calories 不自洽触发 correctAdditionalDishes 重建
      // 主菜带 v1.10 新字段，验证重建后保留
      final original = VisionRecognitionResult(
        dishName: '米饭',
        estimatedWeightGLow: 180,
        estimatedWeightGMid: 200,
        estimatedWeightGHigh: 220,
        foodComponents: const [],
        cookingMethod: 'steam',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.10',
        reasoning: '一碗米饭约 200g',
        packageNutritionTableOcr: '每100g 116kcal 蛋白质2.6g 脂肪0.3g 碳水25.9g',
        packageServingG: 100,
        packageServingKj: 485,
        packageServingKcal: 116,
        packageServingProteinG: 2.6,
        packageServingFatG: 0.3,
        packageServingCarbsG: 25.9,
        packageTotalG: 200,
        packageServingsPerPack: 2,
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
            promptVersion: 'v1.10',
            estimatedCalories: 9999, // 严重不自洽触发修正
            estimatedProteinG: 20,
            estimatedFatG: 15,
            estimatedCarbsG: 10,
          ),
        ],
      );
      final result = RecognitionPostProcessor.process(original);
      // 主菜 v1.10 新字段必须保留（correctAdditionalDishes 重建主菜）
      expect(result.dishName, '米饭');
      expect(result.reasoning, '一碗米饭约 200g');
      expect(result.packageServingProteinG, 2.6);
      expect(result.packageServingFatG, 0.3);
      expect(result.packageServingCarbsG, 25.9);
      // 旧 package_* 字段也保留
      expect(result.packageNutritionTableOcr, '每100g 116kcal 蛋白质2.6g 脂肪0.3g 碳水25.9g');
      expect(result.packageServingG, 100);
      expect(result.packageServingKj, 485);
      expect(result.packageServingKcal, 116);
      expect(result.packageTotalG, 200);
      expect(result.packageServingsPerPack, 2);
    });

    test('菊花茶端到端：3 字段 + 密度换算 + additionalDishes 全保留', () {
      // 菊花茶 + 第二杯不同饮料（附加菜），主菜触发密度换算（tea 密度=1.0 不换算）
      // 但附加菜 calories 不自洽触发 correctAdditionalDishes 重建
      // 验证：主菜 v1.10 新字段在两次重建链路后仍保留
      final original = VisionRecognitionResult(
        dishName: '菊花茶',
        brand: '',
        estimatedWeightGLow: 245,
        estimatedWeightGMid: 250,
        estimatedWeightGHigh: 255,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.10',
        quantity: 1,
        unit: '盒',
        perUnitG: 250,
        weightSource: 'package_label',
        foodCategory: 'tea', // 密度=1.0，不换算
        estimatedCalories: 65,
        estimatedProteinG: 0,
        estimatedFatG: 0,
        estimatedCarbsG: 16,
        reasoning: '盒装菊花茶饮料，碳水必标',
        packageNutritionTableOcr: '每份250ml 能量272kJ 蛋白质0g 脂肪0g 碳水16g',
        packageServingG: 250,
        packageServingKj: 272,
        packageServingKcal: 0,
        packageServingProteinG: 0,
        packageServingFatG: 0,
        packageServingCarbsG: 16,
        packageTotalG: 250,
        packageServingsPerPack: 1,
        additionalDishes: [
          VisionRecognitionResult(
            dishName: '可乐',
            estimatedWeightGLow: 490,
            estimatedWeightGMid: 500,
            estimatedWeightGHigh: 510,
            foodComponents: const [],
            cookingMethod: 'raw',
            isSingleItem: true,
            confidence: 0.85,
            promptVersion: 'v1.10',
            quantity: 1,
            unit: '瓶',
            perUnitG: 500,
            weightSource: 'package_label',
            foodCategory: 'carbonated',
            estimatedCalories: 9999, // 严重不自洽触发 correctAdditionalDishes 重建
            estimatedProteinG: 0,
            estimatedFatG: 0,
            estimatedCarbsG: 105,
          ),
        ],
      );
      final result = RecognitionPostProcessor.process(original);
      // 主菜 v1.10 新字段必须保留（correctAdditionalDishes 重建主菜）
      expect(result.dishName, '菊花茶');
      expect(result.packageServingProteinG, 0);
      expect(result.packageServingFatG, 0);
      expect(result.packageServingCarbsG, 16); // 关键：碳水字段保留
      expect(result.packageServingG, 250);
      expect(result.packageServingKj, 272);
      // 关键场景：包装换算 per100g 碳水非 0（v1.10 修复目标）
      expect(result.hasPackageNutrition, isTrue);
      final per100 = result.computePackageNutritionPer100g(
        estimatedProteinG: result.estimatedProteinG,
        estimatedFatG: result.estimatedFatG,
        estimatedCarbsG: result.estimatedCarbsG,
      );
      expect(per100, isNotNull);
      expect(per100!.$4, closeTo(6.4, 0.001)); // 16*100/250=6.4
      expect(per100.$4 > 0, isTrue); // 碳水不为 0
    });
  });
}
