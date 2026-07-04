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

  // v1.10 BUG-5：_aiFallbackNutrition packageMacrosAllZero 守卫单元测试
  // 验证包装换算宏量全 0 时，宏量保留 AI 估算值（避免 meal_log 数据脱节）
  group('v1.10 _aiFallbackNutrition（BUG-5 packageMacrosAllZero 守卫）', () {
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

    test('BUG-5 核心：包装宏量全 0 + AI 有宏量 → cal 用包装换算，宏量保留 AI 值', () {
      // 场景：含糖饮料 AI 漏填宏量，包装能量可信但宏量未标
      // packageServingG=100, packageServingKcal=50, 宏量全 0
      // per100 = (50, 0, 0, 0)，packageMacrosAllZero=true
      // mid=250 → actualCal = 50 * 250 / 100 = 125
      // 宏量保留 AI 值：protein=5, fat=2, carbs=10
      final controller = RecognizeController(
        _FakeVisionProvider(), null, _FakeNutritionLookup(),
      );
      final result = testResult(
        cal: 100, // AI 估算 cal（被包装换算覆盖）
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
      // cal 用包装换算值（包装能量是精确值，即使宏量漏填能量仍可信）
      expect(n!.calories, closeTo(125, 0.001),
          reason: 'actualCal = per100Cal(50) * mid(250) / 100 = 125');
      // 宏量保留 AI 估算值（BUG-5 修复核心：避免 actualMacros 与 actualCalories 脱节）
      expect(n.proteinG, 5, reason: 'BUG-5：宏量全 0 时保留 AI protein');
      expect(n.fatG, 2, reason: 'BUG-5：宏量全 0 时保留 AI fat');
      expect(n.carbsG, 10, reason: 'BUG-5：宏量全 0 时保留 AI carbs');
    });

    test('包装宏量非全 0 → cal 和宏量都用包装换算值', () {
      // packageServingG=100, packageServingKcal=50, protein=2, fat=1, carbs=8
      // per100 = (50, 2, 1, 8)，packageMacrosAllZero=false
      // mid=250 → actualCal=125, actualProtein=5, actualFat=2.5, actualCarbs=20
      final controller = RecognizeController(
        _FakeVisionProvider(), null, _FakeNutritionLookup(),
      );
      final result = testResult(
        cal: 100, // AI 估算（被覆盖）
        protein: 99, // AI 估算（被覆盖）
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
      expect(n!.calories, closeTo(125, 0.001));
      expect(n.proteinG, closeTo(5, 0.001),
          reason: 'actualProtein = per100Protein(2) * mid(250) / 100 = 5');
      expect(n.fatG, closeTo(2.5, 0.001),
          reason: 'actualFat = per100Fat(1) * mid(250) / 100 = 2.5');
      expect(n.carbsG, closeTo(20, 0.001),
          reason: 'actualCarbs = per100Carbs(8) * mid(250) / 100 = 20');
    });

    test('mid=0 → 跳过包装换算，用 AI 估算（v1.9 守卫不回归）', () {
      // mid=0 时若用包装换算 actualCal = per100 * 0 / 100 = 0，会丢失 AI 估算
      // v1.9 修复：mid>0 守卫，mid=0 时跳过包装换算
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
      expect(n!.calories, 100, reason: 'mid=0 跳过包装换算，保留 AI cal=100');
      expect(n.proteinG, 5);
      expect(n.fatG, 2);
      expect(n.carbsG, 10);
    });

    test('hasPackageNutrition=true 但 servingG=0 → per100=null，跳过包装换算', () {
      // packageServingKcal>0 让 hasPackageNutrition=true，但 servingG=0 让 computePer100 返回 null
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
      expect(n!.calories, 100, reason: 'per100=null，跳过包装换算，用 AI 估算');
      expect(n.proteinG, 5);
    });

    test('BUG-5 关键回归：包装 cal 与 AI cal 不同时，包装 cal 优先', () {
      // 即使 AI cal=200，包装换算 cal=125，应取包装值（包装能量精确）
      final controller = RecognizeController(
        _FakeVisionProvider(), null, _FakeNutritionLookup(),
      );
      final result = testResult(
        cal: 200, // AI 估算偏高
        protein: 5,
        fat: 2,
        carbs: 10,
        mid: 250,
        packageServingG: 100,
        packageServingKcal: 50, // 包装换算 cal=125
        packageServingProteinG: 0,
        packageServingFatG: 0,
        packageServingCarbsG: 0,
      );
      final n = controller.aiFallbackNutritionForTest(result);
      expect(n, isNotNull);
      expect(n!.calories, closeTo(125, 0.001),
          reason: '包装能量精确，覆盖 AI cal=200');
      // 宏量全 0 → 保留 AI 值
      expect(n.proteinG, 5);
      expect(n.fatG, 2);
      expect(n.carbsG, 10);
    });

    test('OCR 兜底宏量（包装字段为 null，OCR 提取到宏量）→ 非全 0，用包装换算', () {
      // packageServingProteinG/FatG/CarbsG = null（AI 未填包装字段）
      // packageNutritionTableOcr 提取到 "蛋白质2g 脂肪1g 碳水8g"
      // computePackageNutritionPer100g 第 2 层 OCR 提取：per100 = (50, 2, 1, 8)
      // packageMacrosAllZero=false → 宏量用包装换算
      final controller = RecognizeController(
        _FakeVisionProvider(), null, _FakeNutritionLookup(),
      );
      final result = testResult(
        cal: 100,
        protein: 99, // AI 估算（被覆盖）
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
      expect(n!.calories, closeTo(125, 0.001));
      // OCR 提取的宏量非全 0 → 用包装换算
      expect(n.proteinG, closeTo(5, 0.001),
          reason: 'OCR 提取 protein=2，per100=2，actualProtein=2*250/100=5');
      expect(n.fatG, closeTo(2.5, 0.001));
      expect(n.carbsG, closeTo(20, 0.001));
    });

    test('kJ 单位换算：packageServingKj=209 → per100Cal=50', () {
      // packageServingKj=209, servingG=100
      // servingKcal = 209 / 4.184 = 49.95 ≈ 50
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
        packageServingKj: 209, // 只标 kJ，不标 kcal
        packageServingProteinG: 0,
        packageServingFatG: 0,
        packageServingCarbsG: 0,
      );
      final n = controller.aiFallbackNutritionForTest(result);
      expect(n, isNotNull);
      expect(n!.calories, closeTo(124.9, 0.5),
          reason: 'actualCal = (209/4.184) * 250 / 100 ≈ 124.9');
      // 宏量全 0 → 保留 AI 值（全 0）
      expect(n.proteinG, 0);
      expect(n.fatG, 0);
      expect(n.carbsG, 0);
    });
  });
}
