// 诊断测试：让 Qwen-VL 描述图片内容（不要求 JSON），确认模型看到的是什么
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart';

void main() {
    final apiKey = Platform.environment['EATWISE_TEST_API_KEY'];
    final baseUrl =
        Platform.environment['EATWISE_TEST_BASE_URL'] ??
        'https://dashscope.aliyuncs.com/compatible-mode/v1';
    final model =
        Platform.environment['EATWISE_TEST_MODEL'] ?? 'qwen-vl-max';

    final imageFile = File('test/smoke/fixtures/apple.jpg');
    final imageBase64 = base64Encode(imageFile.readAsBytesSync());

    test('诊断：描述图片内容', () async {
        if (apiKey == null) return;
        final client = OpenAIClient(
            config: OpenAIConfig(
                authProvider: ApiKeyProvider(apiKey),
                baseUrl: baseUrl,
            ),
        );

        final response = await client.chat.completions
            .create(
                ChatCompletionCreateRequest(
                    model: model,
                    messages: [
                        ChatMessage.user(
                            UserMessageContent.parts([
                                const TextContentPart(
                                    text: '请详细描述这张图片里有什么。你看到了什么物体、颜色、背景？',
                                ),
                                ContentPart.imageBase64(
                                    data: imageBase64,
                                    mediaType: 'image/jpeg',
                                ),
                            ]),
                        ),
                    ],
                ),
            )
            .timeout(const Duration(minutes: 2));

        print('=== 模型对图片的描述 ===');
        print(response.text);
        print('=== model: $model ===');
    });
}
