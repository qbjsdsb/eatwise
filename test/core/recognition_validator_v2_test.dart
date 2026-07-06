// 识别结果校验器 v2 单元测试（重构：AI 绝对优先 + warnings 检测不修改）
//
// 验证：
// 1. AI 估算值不被静默修改（删除 Atwater 修正 + 宏量反推）
// 2. 物理约束检测输出 warnings（不修改值，提示用户核对）
// 3. 字段合理性校验保留（触发重试）
// 4. 组分份量缩放保留（信任 mid）
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/core/util/recognition_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 合法基准结果（营养素自洽：cal=277, 4*0+9*0+4*69=276，偏差 0.4%）
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
    String foodCategory = 'carbonated',
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
      promptVersion: 'v1.10',
      quantity: 2,
      unit: '罐',
      perUnitG: 330,
      estimatedCalories: cal,
      estimatedProteinG: protein,
      estimatedFatG: fat,
      estimatedCarbsG: carbs,
      foodCategory: foodCategory,
    );
  }

  group('AI 绝对优先 - 估算值不被静默修改', () {
    test('Atwater 偏差>10% 不修正 calories（保留 AI 值）', () {
      // AI 给 cal=400, p=20, f=10, c=30 → expected=4*20+9*10+4*30=290
      // 偏差 (400-290)/400=27.5% > 10%
      // 旧逻辑：correctedCalories=290（覆盖 AI 的 400）
      // 新逻辑：不修正，warnings 含"不自洽"提示用户核对
      final v = RecognitionValidator.validate(validResult(
        cal: 400,
        protein: 20,
        fat: 10,
        carbs: 30,
        foodCategory: 'solid',
      ));
      // 物理约束应输出 warning 提示用户核对
      expect(v.warnings.any((w) => w.contains('不自洽')), isTrue,
          reason: '物理不自洽时应输出 warning 提示用户核对');
    });

    test('cal≤0 但宏量非 0 不修正 calories（保留 AI 值）', () {
      // AI 给 cal=0, p=20, f=10, c=30 → expected=290
      // 旧逻辑：correctedCalories=290（用宏量反推覆盖）
      // 新逻辑：不修正，warnings 提示用户核对
      final v = RecognitionValidator.validate(validResult(
        cal: 0,
        protein: 20,
        fat: 10,
        carbs: 30,
        foodCategory: 'solid',
      ));
      expect(v.warnings.any((w) => w.contains('宏量')), isTrue,
          reason: 'cal=0 但有宏量时应输出 warning');
    });

    test('宏量缺失（cal>0 但部分宏量=0）不反推填充（保留 AI 值）', () {
      // AI 给 cal=150, p=0, f=0, c=0（含糖饮料 AI 漏填宏量）
      // 旧逻辑：correctedProteinG/FatG/CarbsG 按品类默认比例填充
      // 新逻辑：不反推，warnings 提示用户核对
      final v = RecognitionValidator.validate(validResult(
        cal: 150,
        protein: 0,
        fat: 0,
        carbs: 0,
        foodCategory: 'carbonated',
      ));
      expect(v.warnings.any((w) => w.contains('宏量')), isTrue,
          reason: '宏量缺失时应输出 warning 提示用户核对');
    });

    test('酒精饮料 Atwater 偏差大不修正（保留 AI 值）', () {
      // 啤酒 cal=129, p=1.5, f=0, c=9.3 → expected=43.8（偏差 66%）
      // 旧逻辑：酒精豁免，不修正（这是已修复的）
      // 新逻辑：所有品类都不修正，酒精也是
      final v = RecognitionValidator.validate(validResult(
        cal: 129,
        protein: 1.5,
        fat: 0,
        carbs: 9.3,
        foodCategory: 'beer',
      ));
      // 酒精豁免不应输出"不自洽"warning（酒精热量不在 Atwater 系数内，是合理的）
      expect(v.warnings.any((w) => w.contains('不自洽')), isFalse,
          reason: '酒精饮料热量来自酒精（7kcal/g），不在 Atwater 系数内，不应警告');
    });

    test('合法自洽结果无 warnings', () {
      // 可乐 cal=277, p=0, f=0, c=69 → expected=276，偏差 0.4% < 10%
      final v = RecognitionValidator.validate(validResult());
      expect(v.warnings, isEmpty, reason: '自洽结果不应有 warnings');
    });
  });

  group('字段合理性校验保留（触发重试）', () {
    test('dishName 为空触发重试', () {
      final v = RecognitionValidator.validate(validResult(dishName: ''));
      expect(v.needsRetry, isTrue);
      expect(v.reasons, contains('dish_name 为空'));
    });

    test('confidence 越界触发重试', () {
      final v = RecognitionValidator.validate(validResult(confidence: 1.5));
      expect(v.needsRetry, isTrue);
    });

    test('estimatedWeightGMid <= 0 触发重试', () {
      final v = RecognitionValidator.validate(validResult(mid: 0));
      expect(v.needsRetry, isTrue);
    });

    test('重量区间倒置触发重试', () {
      final v = RecognitionValidator.validate(
          validResult(low: 700, mid: 660, high: 720));
      expect(v.needsRetry, isTrue);
    });
  });

  group('组分份量缩放保留（信任 mid）', () {
    test('sum(components) vs mid 偏差>15% 按 mid 缩放', () {
      // mid=250, 组分 sum=270g（偏差 8% < 15%，不缩放）
      // mid=250, 组分 sum=320g（偏差 28% > 15%，缩放）
      final v = RecognitionValidator.validate(VisionRecognitionResult(
        dishName: '番茄炒蛋',
        brand: '',
        estimatedWeightGLow: 200,
        estimatedWeightGMid: 250,
        estimatedWeightGHigh: 300,
        foodComponents: const [
          FoodComponent(name: '番茄', estimatedG: 200),
          FoodComponent(name: '鸡蛋', estimatedG: 120),
        ],
        cookingMethod: 'stir-fry',
        isSingleItem: false,
        confidence: 0.85,
        promptVersion: 'v1.10',
        estimatedCalories: 200,
        estimatedProteinG: 10,
        estimatedFatG: 12,
        estimatedCarbsG: 8,
        foodCategory: 'solid',
      ));
      // sum=320, mid=250, ratio=250/320=0.78, 偏差 22% > 15% → 缩放
      expect(v.correctedComponents, isNotNull,
          reason: '组份缩放保留，这是信任 mid 不是覆盖 AI 估算');
      // 组分被缩放：番茄 200*0.78=156, 鸡蛋 120*0.78=94
      expect(v.correctedComponents![0].estimatedG, closeTo(156, 1));
      expect(v.correctedComponents![1].estimatedG, closeTo(94, 1));
    });
  });
}
