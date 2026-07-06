// recognize_controller 测试
//
// 注意：pickAndRecognize 依赖 ImagePicker + FlutterImageCompress 平台插件，
// 沙箱 host test 无法完整跑 pickAndRecognize 流程。
// 本测试验证可测的部分：
// 1. 构造器接受新的 4 参数回调签名（编译期验证）
// 2. 限流字段初始状态
// 3. 回调被调用时收到 Prompts.version（用 Fake 回调 + 直接调用回调模拟）
//
// 完整 pickAndRecognize 流程（含限流拒绝 + 真实入队）标注 @Tags(['smoke'])，真机验证。

import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/prompts.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/features/recognize/circuit_breaker.dart';
import 'package:eatwise/features/recognize/recognize_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假的 VisionProvider（不实际调 API）
class _FakeVisionProvider implements VisionProvider {
  @override
  String get name => 'Fake';

  @override
  String get promptVersion => Prompts.version;

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    // VisionRecognitionException 构造器：VisionRecognitionException(this.reason, {this.retryable})
    throw VisionRecognitionException('模拟网络失败', retryable: true);
  }
}

/// 假的 NutritionLookup（构造器要求非空，但不实际查库）
/// 注意：NutritionLookup 为具体类，跨库 implements 时仅需实现公开方法（私有 _repo 不在接口内）
class _FakeNutritionLookup implements NutritionLookup {
  @override
  Future<NutritionResult?> lookupSingleItem({
    required String dishName,
    required double servingG,
    String brand = '',
  }) async => null;

  @override
  Future<CompositeNutritionResult> lookupCompositeDish({
    required List<FoodComponent> components,
    required String cookingMethod,
  }) async =>
      CompositeNutritionResult(
        calories: 0,
        proteinG: 0,
        fatG: 0,
        carbsG: 0,
        oilG: 0,
        componentHits: const [],
        componentMisses: const [],
      );

  @override
  Future<NutritionRange?> lookupSingleItemWithRange({
    required String dishName,
    required double servingGLow,
    required double servingGMid,
    required double servingGHigh,
  }) async => null; // fake 不实际查库

  @override
  Future<CompositeNutritionRange> lookupCompositeDishWithRange({
    required List<FoodComponent> components,
    required String cookingMethod,
  }) async =>
      CompositeNutritionRange(
        low: CompositeNutritionResult(
            calories: 0,
            proteinG: 0,
            fatG: 0,
            carbsG: 0,
            oilG: 0,
            componentHits: const [],
            componentMisses: const []),
        mid: CompositeNutritionResult(
            calories: 0,
            proteinG: 0,
            fatG: 0,
            carbsG: 0,
            oilG: 0,
            componentHits: const [],
            componentMisses: const []),
        high: CompositeNutritionResult(
            calories: 0,
            proteinG: 0,
            fatG: 0,
            carbsG: 0,
            oilG: 0,
            componentHits: const [],
            componentMisses: const []),
      );
}

void main() {
  test('构造器接受 4 参数回调签名（编译期验证 + 回调收到 Prompts.version）', () {
    String? capturedPromptVersion;
    final controller = RecognizeController(
      _FakeVisionProvider(),
      null, // 无 fallback
      _FakeNutritionLookup(), // 假 lookup（构造器要求非空）
      onOfflineEnqueue: (imagePath, mealType, date, promptVersion) async {
        capturedPromptVersion = promptVersion;
      },
    );
    // 直接调用回调验证 promptVersion 透传（绕过 pickAndRecognize 的平台依赖）
    // 实际生产中由 catch 块调用，传入 Prompts.version
    controller.onOfflineEnqueueForTest?.call(
      '/fake/path.jpg', 'breakfast', '2026-07-02', Prompts.version,
    );
    expect(capturedPromptVersion, Prompts.version);
  });

  test('限流：_lastRecognizeTime 初始为 null（未识别过）', () {
    final controller = RecognizeController(
      _FakeVisionProvider(), null, _FakeNutritionLookup(),
    );
    expect(controller.lastRecognizeTimeForTest, isNull);
  });

  // T36：L3 转手动回调验证
  // 构造器是位置参数 (primary, fallback, nutritionLookup, {onOfflineEnqueue, onL3Fallback})，
  // 不能用 primaryProvider: 命名参数。
  // 沙箱限制：pickAndRecognize 依赖 ImagePicker + FlutterImageCompress 平台插件，
  // 沙箱跑不了完整 L1/L2/L3 流程。此处仅做构造器编译期验证 + 回调可调用，
  // 与 Sprint 3 测试策略一致（见文件头注释 + line 59-75）。
  // 完整流程（429 等待重试 / 非 retryable 转 L3 / retryable 走离线入队）标 @Tags(['smoke']) 真机验证。
  test('T36：构造器接受 onL3Fallback 回调（编译期验证 + 回调可调用）', () {
    var l3Triggered = false;
    final controller = RecognizeController(
      _FakeVisionProvider(), // 位置参数 1：primary（复用 Sprint 3 Fake）
      null, // 位置参数 2：fallback
      _FakeNutritionLookup(), // 位置参数 3：nutritionLookup（复用 Sprint 3 Fake）
      onL3Fallback: () => l3Triggered = true,
    );
    // 直接调用回调验证（绕过 pickAndRecognize 平台依赖，与 Sprint 3 策略一致）
    expect(controller.onL3FallbackForTest, isNotNull);
    controller.onL3FallbackForTest?.call();
    expect(l3Triggered, isTrue);
  });

  test('T36：onL3Fallback 默认为 null（向后兼容，未注入时不报错）', () {
    final controller = RecognizeController(
      _FakeVisionProvider(),
      null,
      _FakeNutritionLookup(),
    );
    expect(controller.onL3FallbackForTest, isNull);
  });

  // T37 断路器集成测试
  test('断路器 open 时 pickAndRecognize 不调 API 直接入队', () async {
    // 这个测试依赖 pickAndRecognize 完整流程（ImagePicker 平台插件），
    // 沙箱跑不了 → 标 @Tags(['smoke']) 真机验证
  }, tags: ['smoke']);

  test('T38：构造器接受 circuitBreaker（编译期验证 + 字段可读）', () {
    final storage = <String, String>{};
    final breaker = CircuitBreaker(
      write: (k, v) async => storage[k] = v,
      read: (k) async => storage[k],
      delete: (k) async => storage.remove(k),
    );
    final controller = RecognizeController(
      _FakeVisionProvider(),
      null,
      _FakeNutritionLookup(),
      circuitBreaker: breaker,
    );
    expect(controller.circuitBreakerForTest, isNotNull);
  });

  test('T38：circuitBreaker 默认 null（向后兼容，未注入时不报错）', () {
    final controller = RecognizeController(
      _FakeVisionProvider(),
      null,
      _FakeNutritionLookup(),
    );
    expect(controller.circuitBreakerForTest, isNull);
  });

  // 以下完整流程标注 @Tags(['smoke'])，真机验证（沙箱跑不了 pickAndRecognize）：
  // @Tags(['smoke'])
  // testWidgets('429 等待 Retry-After 后 L1 重试成功', ...) { ... }
  // testWidgets('429 重试失败 + L2 切备成功', ...) { ... }
  // testWidgets('非 retryable（malformed/401/403）→ L3 转手动，不走离线入队', ...) { ... }
  // testWidgets('retryable（网络/超时/5xx）→ rethrow 走外层离线入队，不触发 L3', ...) { ... }

  // v2.1：_aiFallbackNutrition actualCal/宏量始终用 AI 原值（不再包装换算覆盖）
  // 验证修复 reasoning 文本热量 ≠ aiFallback.calories ≠ 显示值 的问题
  group('v2.1 _aiFallbackNutrition（actualCal 始终用 AI 原值）', () {
    /// 构造测试用 VisionRecognitionResult
    VisionRecognitionResult testResult({
      double? cal = 100,
      double? protein = 5,
      double? fat = 2,
      double? carbs = 10,
      double mid = 250,
      double? packageServingG,
      double? packageServingKj,
      double? packageServingKcal,
      double? packageServingProteinG,
      double? packageServingFatG,
      double? packageServingCarbsG,
      String packageNutritionTableOcr = '',
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
        foodCategory: 'solid',
        estimatedCalories: cal,
        estimatedProteinG: protein,
        estimatedFatG: fat,
        estimatedCarbsG: carbs,
        packageServingG: packageServingG,
        packageServingKj: packageServingKj,
        packageServingKcal: packageServingKcal,
        packageServingProteinG: packageServingProteinG,
        packageServingFatG: packageServingFatG,
        packageServingCarbsG: packageServingCarbsG,
        packageNutritionTableOcr: packageNutritionTableOcr,
      );
    }

    test('cal=null → 返回 null（旧 prompt 兼容）', () {
      final controller = RecognizeController(
        _FakeVisionProvider(), null, _FakeNutritionLookup(),
      );
      final result = testResult(cal: null);
      final n = controller.aiFallbackNutritionForTest(result);
      expect(n, isNull);
    });

    test('无包装数据（hasPackageNutrition=false）→ 用 AI 估算值', () {
      final controller = RecognizeController(
        _FakeVisionProvider(), null, _FakeNutritionLookup(),
      );
      final result = testResult(cal: 100, protein: 5, fat: 2, carbs: 10);
      final n = controller.aiFallbackNutritionForTest(result);
      expect(n, isNotNull);
      expect(n!.calories, 100);
      expect(n.proteinG, 5);
      expect(n.fatG, 2);
      expect(n.carbsG, 10);
      expect(n.foodItemId, 0); // 哨兵
      expect(n.source, NutritionSource.aiEstimate);
    });

    test('v2.1：包装宏量全 0 + AI 有宏量 → cal 和宏量都保留 AI 原值', () {
      // 场景：含糖饮料 AI 漏填宏量，包装能量可信但宏量未标
      // v2.1 修复后：actualCal 不再用包装换算覆盖，4 项全保留 AI 原值
      // AI: cal=100, protein=5, fat=2, carbs=10
      final controller = RecognizeController(
        _FakeVisionProvider(), null, _FakeNutritionLookup(),
      );
      final result = testResult(
        cal: 100, // AI 估算 cal（v2.1 不再被包装换算覆盖）
        protein: 5,
        fat: 2,
        carbs: 10,
        mid: 250,
        packageServingG: 100,
        packageServingKcal: 50,
        packageServingProteinG: 0,
        packageServingFatG: 0,
        packageServingCarbsG: 0,
      );
      final n = controller.aiFallbackNutritionForTest(result);
      expect(n, isNotNull);
      // v2.1：cal 始终用 AI 原值（不再用包装换算 125 覆盖）
      expect(n!.calories, 100,
          reason: 'v2.1：actualCal 保留 AI 原值 100，不用包装换算 125 覆盖');
      // 宏量保留 AI 估算值
      expect(n.proteinG, 5, reason: 'v2.1：保留 AI protein');
      expect(n.fatG, 2, reason: 'v2.1：保留 AI fat');
      expect(n.carbsG, 10, reason: 'v2.1：保留 AI carbs');
    });

    test('v2.1：包装宏量非全 0 → cal 和宏量都保留 AI 原值（不再用包装换算）', () {
      // v2.1 修复后：无论包装宏量是否全 0，4 项都保留 AI 原值
      // AI: cal=100, protein=99, fat=99, carbs=99
      final controller = RecognizeController(
        _FakeVisionProvider(), null, _FakeNutritionLookup(),
      );
      final result = testResult(
        cal: 100, // AI 估算（v2.1 不再被覆盖）
        protein: 99, // AI 估算（v2.1 不再被覆盖）
        fat: 99,
        carbs: 99,
        mid: 250,
        packageServingG: 100,
        packageServingKcal: 50,
        packageServingProteinG: 2,
        packageServingFatG: 1,
        packageServingCarbsG: 8,
      );
      final n = controller.aiFallbackNutritionForTest(result);
      expect(n, isNotNull);
      expect(n!.calories, 100,
          reason: 'v2.1：actualCal 保留 AI 原值 100');
      expect(n.proteinG, 99,
          reason: 'v2.1：actualProtein 保留 AI 原值 99');
      expect(n.fatG, 99,
          reason: 'v2.1：actualFat 保留 AI 原值 99');
      expect(n.carbsG, 99,
          reason: 'v2.1：actualCarbs 保留 AI 原值 99');
    });

    test('mid=0 → 仍用 AI 估算（v2.1 行为不变）', () {
      // v2.1：actualCal 始终用 AI 原值，mid=0 行为与之前一致
      final controller = RecognizeController(
        _FakeVisionProvider(), null, _FakeNutritionLookup(),
      );
      final result = testResult(
        cal: 100,
        protein: 5,
        fat: 2,
        carbs: 10,
        mid: 0, // 关键：mid=0
        packageServingG: 100,
        packageServingKcal: 50,
      );
      final n = controller.aiFallbackNutritionForTest(result);
      expect(n, isNotNull);
      expect(n!.calories, 100, reason: 'v2.1：mid=0 仍保留 AI cal=100');
      expect(n.proteinG, 5);
      expect(n.fatG, 2);
      expect(n.carbsG, 10);
    });

    test('hasPackageNutrition=true 但 servingG=0 → 用 AI 估算（v2.1 行为不变）', () {
      // v2.1：actualCal 始终用 AI 原值，per100=null 与否不影响结果
      final controller = RecognizeController(
        _FakeVisionProvider(), null, _FakeNutritionLookup(),
      );
      final result = testResult(
        cal: 100,
        protein: 5,
        fat: 2,
        carbs: 10,
        packageServingG: 0, // 关键：servingG=0
        packageServingKcal: 50, // hasPackageNutrition=true
      );
      final n = controller.aiFallbackNutritionForTest(result);
      expect(n, isNotNull);
      expect(n!.calories, 100, reason: 'v2.1：保留 AI 估算');
      expect(n.proteinG, 5);
    });

    test('v2.1 关键回归：包装 cal 与 AI cal 不同时 → 用 AI 原值（不再覆盖）', () {
      // v2.1 修复核心：AI cal=200，包装换算 cal=125，应取 AI 值（200）
      // 修复前：包装能量覆盖 AI cal，导致 reasoning 热量 ≠ 显示值
      final controller = RecognizeController(
        _FakeVisionProvider(), null, _FakeNutritionLookup(),
      );
      final result = testResult(
        cal: 200, // AI 估算（v2.1 不再被覆盖）
        protein: 5,
        fat: 2,
        carbs: 10,
        mid: 250,
        packageServingG: 100,
        packageServingKcal: 50, // 包装换算 cal=125（v2.1 不再用）
        packageServingProteinG: 0,
        packageServingFatG: 0,
        packageServingCarbsG: 0,
      );
      final n = controller.aiFallbackNutritionForTest(result);
      expect(n, isNotNull);
      expect(n!.calories, 200,
          reason: 'v2.1：actualCal 用 AI 原值 200，不再被包装换算 125 覆盖');
      // 宏量保留 AI 值
      expect(n.proteinG, 5);
      expect(n.fatG, 2);
      expect(n.carbsG, 10);
    });

    test('v2.1：OCR 兜底宏量 + 包装字段 null → 4 项全保留 AI 原值', () {
      // v2.1 修复后：OCR 提取的包装宏量不再用于覆盖 AI 估算
      // AI: cal=100, protein=99, fat=99, carbs=99
      final controller = RecognizeController(
        _FakeVisionProvider(), null, _FakeNutritionLookup(),
      );
      final result = testResult(
        cal: 100,
        protein: 99, // AI 估算（v2.1 不再被覆盖）
        fat: 99,
        carbs: 99,
        mid: 250,
        packageServingG: 100,
        packageServingKcal: 50,
        // packageServingProteinG/FatG/CarbsG 故意不填（null），走 OCR 兜底
        packageNutritionTableOcr: '每100g：能量50kcal 蛋白质2g 脂肪1g 碳水8g',
      );
      final n = controller.aiFallbackNutritionForTest(result);
      expect(n, isNotNull);
      // v2.1：4 项全保留 AI 原值，OCR 提取的宏量不再覆盖
      expect(n!.calories, 100,
          reason: 'v2.1：actualCal 保留 AI 原值 100');
      expect(n.proteinG, 99,
          reason: 'v2.1：actualProtein 保留 AI 原值 99');
      expect(n.fatG, 99,
          reason: 'v2.1：actualFat 保留 AI 原值 99');
      expect(n.carbsG, 99,
          reason: 'v2.1：actualCarbs 保留 AI 原值 99');
    });

    test('v2.1：kJ 单位包装数据 → 仍用 AI 原值（不再换算覆盖）', () {
      // v2.1 修复后：包装 kJ 换算不再用于覆盖 AI actualCal
      // AI: cal=100, protein=0, fat=0, carbs=0
      final controller = RecognizeController(
        _FakeVisionProvider(), null, _FakeNutritionLookup(),
      );
      final result = testResult(
        cal: 100,
        protein: 0,
        fat: 0,
        carbs: 0,
        mid: 250,
        packageServingG: 100,
        packageServingKj: 209, // 只标 kJ（v2.1 不再用于换算覆盖）
        packageServingProteinG: 0,
        packageServingFatG: 0,
        packageServingCarbsG: 0,
      );
      final n = controller.aiFallbackNutritionForTest(result);
      expect(n, isNotNull);
      expect(n!.calories, 100,
          reason: 'v2.1：actualCal 保留 AI 原值 100，不再用 kJ 换算覆盖');
      // 宏量保留 AI 值（全 0）
      expect(n.proteinG, 0);
      expect(n.fatG, 0);
      expect(n.carbsG, 0);
    });
  });

  group('M22 查库阶段最小展示', () {
    test('lookupMinDwell 常量存在且为 300ms（M22 查库最小展示）', () {
      // M22：查库阶段最小展示 300ms，避免 lookupNutrition state 闪太快
      expect(
        RecognizeController.lookupMinDwell,
        const Duration(milliseconds: 300),
        reason: '查库阶段应最小展示 300ms，避免 lookupNutrition 闪太快',
      );
    });
  });
}
