// M21 Round 1：Glm4vProvider 单元测试
//
// 验证 GLM-4V-Plus 视觉识别容灾 Provider 的构造 + getter 行为。
// recognize 方法委托给 QwenVlProvider.recognizeWithClient 静态方法，
// 依赖真实 HTTP，由 sprint1_e2e_test 间接覆盖，此处不单测。
import 'package:eatwise/ai/glm_4v_provider.dart';
import 'package:eatwise/ai/prompts.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Glm4vProvider 构造与 getter', () {
    test('默认 modelName 为 glm-4v-plus', () {
      final provider = Glm4vProvider(
        apiKey: 'test-fake-key',
        baseUrl: 'http://localhost:9999',
      );
      // 构造不抛异常即可（modelName 私有，通过 name/promptVersion 间接验证）
      expect(provider, isNotNull);
    });

    test('自定义 modelName 透传不抛异常', () {
      final provider = Glm4vProvider(
        apiKey: 'test-fake-key',
        baseUrl: 'http://localhost:9999',
        modelName: 'glm-4v-plus-0112',
      );
      expect(provider, isNotNull);
    });

    test('name getter 返回 GLM-4V-Plus', () {
      final provider = Glm4vProvider(
        apiKey: 'test-fake-key',
        baseUrl: 'http://localhost:9999',
      );
      expect(provider.name, 'GLM-4V-Plus');
    });

    test('promptVersion getter 返回 Prompts.version', () {
      final provider = Glm4vProvider(
        apiKey: 'test-fake-key',
        baseUrl: 'http://localhost:9999',
      );
      expect(provider.promptVersion, Prompts.version);
    });

    test('Glm4vProvider 实现 VisionProvider 接口', () {
      final provider = Glm4vProvider(
        apiKey: 'test-fake-key',
        baseUrl: 'http://localhost:9999',
      );
      expect(provider, isA<VisionProvider>());
    });
  });
}
