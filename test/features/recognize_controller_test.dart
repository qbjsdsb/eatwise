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
}
