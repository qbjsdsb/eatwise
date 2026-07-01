import 'package:openai_dart/openai_dart.dart';

import 'prompts.dart';
import 'qwen_vl_provider.dart';
import 'vision_provider.dart';

/// GLM-4V-Plus 视觉模型 Provider（智谱 AI，OpenAI-compatible）
/// Qwen-VL 失败时容灾降级，识别逻辑与 Qwen-VL 完全一致，仅 client/modelName 不同
class Glm4vProvider implements VisionProvider {
  final OpenAIClient _client;
  final String _modelName;

  Glm4vProvider({
    required String apiKey,
    required String baseUrl,
    String modelName = 'glm-4v-plus',
  })  : _modelName = modelName,
        _client = OpenAIClient(
          config: OpenAIConfig(
            authProvider: ApiKeyProvider(apiKey), // 与 QwenVlProvider 一致
            baseUrl: baseUrl,
          ),
        );

  @override
  String get name => 'GLM-4V-Plus';

  @override
  String get promptVersion => Prompts.version;

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) =>
      QwenVlProvider.recognizeWithClient(_client, _modelName, imageBase64, promptVersion);
}
