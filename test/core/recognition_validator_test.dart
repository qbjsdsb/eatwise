// 识别结果校验器单元测试（批次 1）
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
      expect(v.correctedCalories, isNull);
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

  group('营养素自洽性校验', () {
    test('自洽（偏差<10%）不修正', () {
      // cal=277, expected=4*0+9*0+4*69=276, 偏差 0.36%
      final v = RecognitionValidator.validate(validResult());
      expect(v.correctedCalories, isNull);
      expect(v.reasons, isEmpty);
    });

    test('不自洽（偏差>10%）修正为 4p+9f+4c', () {
      // cal=500, expected=276, 偏差 44.8% → 修正为 276
      final v = RecognitionValidator.validate(validResult(cal: 500));
      expect(v.correctedCalories, 276);
      expect(v.reasons.any((r) => r.contains('营养素不自洽')), isTrue);
    });

    test('calories=0 但有宏量营养素 → 修正', () {
      final v = RecognitionValidator.validate(validResult(cal: 0));
      expect(v.correctedCalories, 276);
      expect(v.reasons.any((r) => r.contains('calories=0')), isTrue);
    });

    test('纯碳水食物自洽（可乐 cal=277, c=69.25）', () {
      // 2 罐 660g 可乐，约 277 kcal，碳水 69g：4*69=276 ≈ 277 ✓
      final v = RecognitionValidator.validate(validResult(
        cal: 277,
        protein: 0,
        fat: 0,
        carbs: 69,
      ));
      expect(v.correctedCalories, isNull);
    });

    test('高蛋白食物自洽（鸡胸肉 cal=165, p=31, f=3.6, c=0）', () {
      // 4*31 + 9*3.6 + 4*0 = 124 + 32.4 = 156.4, 偏差 5.2% < 10% ✓
      final v = RecognitionValidator.validate(validResult(
        cal: 165,
        protein: 31,
        fat: 3.6,
        carbs: 0,
      ));
      expect(v.correctedCalories, isNull);
    });

    test('高脂肪食物自洽（油 cal=889, p=0, f=99.9, c=0）', () {
      // 4*0 + 9*99.9 + 4*0 = 899.1, 偏差 1.1% < 10% ✓
      final v = RecognitionValidator.validate(validResult(
        cal: 889,
        protein: 0,
        fat: 99.9,
        carbs: 0,
      ));
      expect(v.correctedCalories, isNull);
    });

    test('calories 偏高 9% 不修正（边界容忍）', () {
      // expected=276, cal=276*1.09=300.84, 偏差 9% < 10% ✓
      final v = RecognitionValidator.validate(validResult(cal: 300));
      // expected=276, |276-300|/300 = 0.08 = 8% < 10% ✓
      expect(v.correctedCalories, isNull);
    });

    test('calories 偏高 11% 修正（超容忍）', () {
      // expected=276, cal=248, |276-248|/248 = 11.3% > 10% → 修正
      final v = RecognitionValidator.validate(validResult(cal: 248));
      expect(v.correctedCalories, 276);
    });
  });

  group('旧 prompt 兼容', () {
    test('无 estimatedCalories（v1.0-v1.3）跳过自洽校验', () {
      final v = RecognitionValidator.validate(validResult(cal: null));
      expect(v.isValid, isTrue);
      expect(v.correctedCalories, isNull);
      expect(v.reasons, isEmpty);
    });

    test('无 estimatedCalories 但字段不合理仍触发重试', () {
      final v = RecognitionValidator.validate(
          validResult(cal: null, dishName: ''));
      expect(v.needsRetry, isTrue);
      expect(v.correctedCalories, isNull);
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

  // v1.10：宏量营养素反推修正（cal>0 但三宏量全 0 → 按品类默认比例反推）
  // 解决"盒装菊花茶有 cal 但碳水=0"问题
  group('v1.10 宏量反推修正（cal>0 三宏量全 0）', () {
    VisionRecognitionResult macroAllZeroResult({
      required String foodCategory,
      required double cal,
      double mid = 250,
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
        foodCategory: foodCategory,
        estimatedCalories: cal,
        estimatedProteinG: 0,
        estimatedFatG: 0,
        estimatedCarbsG: 0,
      );
    }

    test('tea 品类：cal=43 三宏量全 0 → 按比例反推', () {
      // tea 默认 (43, 0.1, 0, 10.6)
      // scale = 43/43 = 1
      // 反推：p=0.1*1=0.1, f=0*1=0, c=10.6*1=10.6
      final v = RecognitionValidator.validate(macroAllZeroResult(
        foodCategory: 'tea',
        cal: 43,
      ));
      expect(v.correctedProteinG, closeTo(0.1, 0.001));
      expect(v.correctedFatG, 0);
      expect(v.correctedCarbsG, closeTo(10.6, 0.001));
      expect(v.reasons.any((r) => r.contains('按品类') && r.contains('tea')), isTrue);
    });

    test('tea 品类：cal=86（2 倍）→ 反推按 2 倍缩放', () {
      // scale = 86/43 = 2
      // 反推：p=0.1*2=0.2, f=0*2=0, c=10.6*2=21.2
      final v = RecognitionValidator.validate(macroAllZeroResult(
        foodCategory: 'tea',
        cal: 86,
      ));
      expect(v.correctedProteinG, closeTo(0.2, 0.001));
      expect(v.correctedFatG, 0);
      expect(v.correctedCarbsG, closeTo(21.2, 0.001));
    });

    test('protein_drink 品类：cal=60 → 反推按默认比例', () {
      // protein_drink 默认 (60, 3, 1.5, 5)
      // scale = 60/60 = 1
      final v = RecognitionValidator.validate(macroAllZeroResult(
        foodCategory: 'protein_drink',
        cal: 60,
      ));
      expect(v.correctedProteinG, closeTo(3, 0.001));
      expect(v.correctedFatG, closeTo(1.5, 0.001));
      expect(v.correctedCarbsG, closeTo(5, 0.001));
    });

    test('energy_drink 品类：cal=45 → 反推按默认比例', () {
      // energy_drink 默认 (45, 0, 0, 11)
      final v = RecognitionValidator.validate(macroAllZeroResult(
        foodCategory: 'energy_drink',
        cal: 45,
      ));
      expect(v.correctedProteinG, 0);
      expect(v.correctedFatG, 0);
      expect(v.correctedCarbsG, closeTo(11, 0.001));
    });

    test('carbonated 品类：cal=43 → 反推 carbs=10.6', () {
      // 验证现有品类也走反推路径（v1.10 修复覆盖所有有默认值的品类）
      final v = RecognitionValidator.validate(macroAllZeroResult(
        foodCategory: 'carbonated',
        cal: 43,
      ));
      expect(v.correctedProteinG, 0); // carbonated 默认蛋白 0
      expect(v.correctedFatG, 0);
      expect(v.correctedCarbsG, closeTo(10.6, 0.001));
    });

    test('solid 品类（无默认值）：不反推，correctedXxxG = null', () {
      // solid 不在 defaults 表中，无法按品类反推
      final v = RecognitionValidator.validate(macroAllZeroResult(
        foodCategory: 'solid',
        cal: 200,
      ));
      expect(v.correctedProteinG, isNull);
      expect(v.correctedFatG, isNull);
      expect(v.correctedCarbsG, isNull);
      // 也不应该在 reasons 中提到"按品类反推"
      expect(v.reasons.any((r) => r.contains('按品类')), isFalse);
    });

    test('water 品类（默认 cal=0）：不反推（def.\$1 > 0 条件不满足）', () {
      // water 默认 (0, 0, 0, 0)，def.$1=0，跳过反推
      final v = RecognitionValidator.validate(macroAllZeroResult(
        foodCategory: 'water',
        cal: 50, // 异常但走不到反推
      ));
      expect(v.correctedProteinG, isNull);
      expect(v.correctedFatG, isNull);
      expect(v.correctedCarbsG, isNull);
    });

    test('cal=0 三宏量全 0：不反推（cal > 0 条件不满足）', () {
      final v = RecognitionValidator.validate(macroAllZeroResult(
        foodCategory: 'tea',
        cal: 0,
      ));
      expect(v.correctedProteinG, isNull);
      expect(v.correctedFatG, isNull);
      expect(v.correctedCarbsG, isNull);
    });

    test('cal>0 但有部分宏量非 0：v1.10 修复后填充缺失项（不再跳过）', () {
      // v1.10 修复 BUG-2：部分宏量非 0 时也填充缺失项，避免自洽校验错误修正 cal
      // 蛋白=5 但脂肪/碳水=0，填充 fat/carbs，保留 protein=5
      // tea 默认 (43, 0.1, 0, 10.6)，scale = 43/43 = 1
      // 填充后：p=5（保留 AI 值），f=0*1=0，c=10.6*1=10.6
      final result = VisionRecognitionResult(
        dishName: 'test',
        brand: '',
        estimatedWeightGLow: 250,
        estimatedWeightGMid: 250,
        estimatedWeightGHigh: 250,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.10',
        foodCategory: 'tea',
        estimatedCalories: 43,
        estimatedProteinG: 5, // 非 0，保留
        estimatedFatG: 0, // 缺失，填充
        estimatedCarbsG: 0, // 缺失，填充
      );
      final v = RecognitionValidator.validate(result);
      // protein 保留 AI 值 5（非 0 不覆盖）
      expect(v.correctedProteinG, 5);
      // fat 填充为 0（品类默认 fat=0）
      expect(v.correctedFatG, 0);
      // carbs 填充为 10.6（品类默认 carbs=10.6 × scale=1）
      expect(v.correctedCarbsG, closeTo(10.6, 0.001));
      // 关键：不再错误修正 cal（v1.10 BUG-2 修复目标）
      expect(v.correctedCalories, isNull);
    });

    test('cal=null（旧 prompt 兼容）：不反推', () {
      final result = VisionRecognitionResult(
        dishName: 'test',
        brand: '',
        estimatedWeightGLow: 250,
        estimatedWeightGMid: 250,
        estimatedWeightGHigh: 250,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.0',
        foodCategory: 'tea',
        estimatedCalories: null, // 旧 prompt 无此字段
        estimatedProteinG: 0,
        estimatedFatG: 0,
        estimatedCarbsG: 0,
      );
      final v = RecognitionValidator.validate(result);
      expect(v.correctedProteinG, isNull);
      expect(v.correctedFatG, isNull);
      expect(v.correctedCarbsG, isNull);
    });

    test('菊花茶关键场景：cal=65 三宏量全 0 → 反推 carbs', () {
      // 模拟 AI 漏填 estimated_carbs_g 的菊花茶场景
      // tea 默认 (43, 0.1, 0, 10.6)
      // scale = 65/43 ≈ 1.512
      // 反推：p=0.1*1.512≈0.151, f=0, c=10.6*1.512≈16.03
      final v = RecognitionValidator.validate(macroAllZeroResult(
        foodCategory: 'tea',
        cal: 65,
      ));
      expect(v.correctedProteinG, closeTo(0.151, 0.01));
      expect(v.correctedFatG, 0);
      expect(v.correctedCarbsG, closeTo(16.03, 0.05));
      expect(v.correctedCarbsG! > 0, isTrue); // 关键：碳水不为 0
    });
  });

  // v1.10 BUG-2 边界场景：填充缺失项后跳过 cal 自洽修正
  // 验证"触发填充时信任 AI 整菜 cal 估算"的核心修复逻辑
  group('v1.10 BUG-2 边界场景（填充后跳过 cal 自洽修正）', () {
    /// 可指定各宏量的测试结果构造器（macroAllZeroResult 只能全 0，此 helper 更灵活）
    VisionRecognitionResult macroPartialResult({
      required String foodCategory,
      required double cal,
      double protein = 0,
      double fat = 0,
      double carbs = 0,
      String? promptVersion = 'v1.10',
    }) {
      return VisionRecognitionResult(
        dishName: 'test',
        brand: '',
        estimatedWeightGLow: 250,
        estimatedWeightGMid: 250,
        estimatedWeightGHigh: 250,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: promptVersion!,
        foodCategory: foodCategory,
        estimatedCalories: cal,
        estimatedProteinG: protein,
        estimatedFatG: fat,
        estimatedCarbsG: carbs,
      );
    }

    test('solid 品类 + cal=200 + 三宏量全 0：不填充，走 cal 自洽校验（expected=0 不修正）', () {
      // solid 无默认值 → 不填充 → didFill=false → 进入自洽校验
      // expected = 0，cal=200，但 expected=0 时可能是酒精/纤维等非 Atwater 来源，保留 cal
      final v = RecognitionValidator.validate(macroPartialResult(
        foodCategory: 'solid',
        cal: 200,
      ));
      expect(v.correctedProteinG, isNull);
      expect(v.correctedFatG, isNull);
      expect(v.correctedCarbsG, isNull);
      expect(v.correctedCalories, isNull,
          reason: 'expected=0 时保留 AI cal（可能是酒精/纤维等非 Atwater 来源）');
    });

    test('water 品类 + cal=50 + 三宏量全 0：不填充（def.\$1=0），expected=0 不修正', () {
      // water 默认 (0,0,0,0)，def.$1=0 → 不填充
      // didFill=false → 进入自洽校验，expected=0，保留 cal=50
      final v = RecognitionValidator.validate(macroPartialResult(
        foodCategory: 'water',
        cal: 50,
      ));
      expect(v.correctedProteinG, isNull);
      expect(v.correctedFatG, isNull);
      expect(v.correctedCarbsG, isNull);
      expect(v.correctedCalories, isNull);
    });

    test('protein_drink + cal=60 + protein=3 + fat=0 + carbs=0：填充 fat/carbs，保留 AI cal', () {
      // protein_drink 默认 (60, 3, 1.5, 5)
      // scale = 60/60 = 1
      // p=3 (保留), f=1.5 (填充), c=5 (填充)
      // didFill=true → 跳过 cal 自洽修正
      final v = RecognitionValidator.validate(macroPartialResult(
        foodCategory: 'protein_drink',
        cal: 60,
        protein: 3,
      ));
      expect(v.correctedProteinG, 3); // 保留 AI 值
      expect(v.correctedFatG, closeTo(1.5, 0.001)); // 填充
      expect(v.correctedCarbsG, closeTo(5, 0.001)); // 填充
      expect(v.correctedCalories, isNull,
          reason: 'BUG-2 修复：触发填充时跳过 cal 自洽修正，信任 AI 整菜 cal=60');
    });

    test('protein_drink + cal=120 + protein=6 + fat=0 + carbs=0：填充按 scale 缩放', () {
      // scale = 120/60 = 2
      // p=6 (保留), f=1.5*2=3 (填充), c=5*2=10 (填充)
      final v = RecognitionValidator.validate(macroPartialResult(
        foodCategory: 'protein_drink',
        cal: 120,
        protein: 6,
      ));
      expect(v.correctedProteinG, 6); // 保留
      expect(v.correctedFatG, closeTo(3, 0.001)); // 1.5 * 2
      expect(v.correctedCarbsG, closeTo(10, 0.001)); // 5 * 2
      expect(v.correctedCalories, isNull);
    });

    test('energy_drink + cal=45 + protein=0 + fat=0 + carbs=11：等于品类默认值，不触发填充', () {
      // energy_drink 默认 (45, 0, 0, 11)
      // scale = 45/45 = 1
      // p=0 (品类默认 0, 与 AI 一致), f=0 (品类默认 0, 一致), c=11 (品类默认 11, 一致)
      // 三项都与 AI 一致 → 不触发填充（if p!=protein || f!=fat || c!=carbs 全 false）
      // didFill=false → 进入自洽校验
      // expected = 4*0 + 9*0 + 4*11 = 44，cal=45，偏差 2.2% < 10% → 不修正
      final v = RecognitionValidator.validate(macroPartialResult(
        foodCategory: 'energy_drink',
        cal: 45,
        carbs: 11,
      ));
      expect(v.correctedProteinG, isNull,
          reason: 'AI 值与品类默认一致，无需填充');
      expect(v.correctedFatG, isNull);
      expect(v.correctedCarbsG, isNull);
      expect(v.correctedCalories, isNull,
          reason: '自洽校验偏差 2.2% < 10%，不修正');
    });

    test('对称性：tea + 仅 protein 非 0 → 填充 fat/carbs', () {
      // tea 默认 (43, 0.1, 0, 10.6)
      // scale = 43/43 = 1
      // p=0.1 (品类默认, 但 AI 给的是 5) → 保留 5
      // f=0 (品类默认 0), c=10.6 (品类默认 10.6, 填充)
      final v = RecognitionValidator.validate(macroPartialResult(
        foodCategory: 'tea',
        cal: 43,
        protein: 5,
      ));
      expect(v.correctedProteinG, 5); // 保留
      expect(v.correctedFatG, 0); // 填充（品类默认 0）
      expect(v.correctedCarbsG, closeTo(10.6, 0.001)); // 填充
      expect(v.correctedCalories, isNull);
    });

    test('对称性：tea + 仅 carbs 非 0 → 填充 protein（fat 默认 0 不变）', () {
      // tea 默认 (43, 0.1, 0, 10.6)
      // scale = 43/43 = 1
      // p=0.1 (品类默认, 填充), f=0 (品类默认 0, 不变), c=10.6 (AI 给的, 保留)
      // 触发填充（p != protein: 0.1 != 0），三个 correctedXxxG 都被赋值
      final v = RecognitionValidator.validate(macroPartialResult(
        foodCategory: 'tea',
        cal: 43,
        carbs: 10.6,
      ));
      expect(v.correctedProteinG, closeTo(0.1, 0.001)); // 填充
      expect(v.correctedFatG, 0); // 品类默认 0（被赋值，因为 if 块执行了）
      expect(v.correctedCarbsG, closeTo(10.6, 0.001)); // 保留 AI 值
      // protein 被填充，didFill=true → 跳过 cal 自洽修正
      expect(v.correctedCalories, isNull);
    });

    test('对称性：tea + 仅 fat 非 0（异常）→ 填充 protein/carbs', () {
      // tea 默认 (43, 0.1, 0, 10.6)
      // scale = 43/43 = 1
      // p=0.1 (填充), f=0 (品类默认 0, 但 AI 给 2 → 保留 2), c=10.6 (填充)
      final v = RecognitionValidator.validate(macroPartialResult(
        foodCategory: 'tea',
        cal: 43,
        fat: 2, // 异常：茶饮通常无脂肪
      ));
      expect(v.correctedProteinG, closeTo(0.1, 0.001)); // 填充
      expect(v.correctedFatG, 2); // 保留 AI 值（即使异常）
      expect(v.correctedCarbsG, closeTo(10.6, 0.001)); // 填充
      expect(v.correctedCalories, isNull);
    });

    test('cal=null + 部分宏量非 0（旧 prompt 兼容）：不填充不修正', () {
      // 旧 prompt 无 estimated_calories，cal=null
      // 不进入填充分支（cal != null 条件不满足）
      // 不进入自洽校验
      // 注意：copyWith 不能显式置空 nullable 字段（用 ?? 保留原值），需直接构造
      final result = VisionRecognitionResult(
        dishName: 'test',
        brand: '',
        estimatedWeightGLow: 250,
        estimatedWeightGMid: 250,
        estimatedWeightGHigh: 250,
        foodComponents: const [],
        cookingMethod: 'raw',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.0',
        foodCategory: 'tea',
        estimatedCalories: null, // 旧 prompt 无此字段
        estimatedProteinG: 5,
        estimatedFatG: 0,
        estimatedCarbsG: 0,
      );
      final v = RecognitionValidator.validate(result);
      expect(v.correctedProteinG, isNull);
      expect(v.correctedFatG, isNull);
      expect(v.correctedCarbsG, isNull);
      expect(v.correctedCalories, isNull);
    });

    test('回归：cal=0 + 三宏量全 0：不填充，不修正（cal<=0 && expected=0 不触发）', () {
      final v = RecognitionValidator.validate(macroPartialResult(
        foodCategory: 'tea',
        cal: 0,
      ));
      expect(v.correctedProteinG, isNull);
      expect(v.correctedFatG, isNull);
      expect(v.correctedCarbsG, isNull);
      expect(v.correctedCalories, isNull);
    });

    test('回归：cal=0 + 有宏量（protein=5）：不填充（cal>0 条件不满足），修正 cal', () {
      // cal=0, protein=5, fat=0, carbs=0
      // 不触发填充（cal>0 条件不满足）
      // didFill=false → 进入自洽校验
      // expected = 4*5 + 0 + 0 = 20
      // cal<=0 && expected>0 → 修正 cal=20
      final v = RecognitionValidator.validate(macroPartialResult(
        foodCategory: 'tea',
        cal: 0,
        protein: 5,
      ));
      expect(v.correctedProteinG, isNull,
          reason: 'cal=0 不触发填充');
      expect(v.correctedFatG, isNull);
      expect(v.correctedCarbsG, isNull);
      expect(v.correctedCalories, 20,
          reason: 'cal=0 但有宏量，修正为 expected=20');
    });

    test('关键回归：BUG-2 修复后不再错误修正 cal（蛋白饮料场景）', () {
      // BUG-2 原始场景：protein_drink protein=3 但 carbs=0 漏填，cal=60
      // 修复前：不反推，自洽校验 expected=4*3+0+0=12，偏差 80% → 错误修正 cal=12
      // 修复后：填充 fat/carbs，didFill=true → 跳过自洽修正，保留 cal=60
      final v = RecognitionValidator.validate(macroPartialResult(
        foodCategory: 'protein_drink',
        cal: 60,
        protein: 3,
      ));
      expect(v.correctedCalories, isNull,
          reason: 'BUG-2 修复核心：不再错误修正 cal=60 为 12');
      expect(v.correctedProteinG, 3); // 保留
      expect(v.correctedFatG, closeTo(1.5, 0.001)); // 填充
      expect(v.correctedCarbsG, closeTo(5, 0.001)); // 填充
    });
  });
}
