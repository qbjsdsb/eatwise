// 冒烟预演：真实调用 Qwen-VL 验证多模态识别 + json_object 返回
//
// 用法：
//   export EATWISE_TEST_API_KEY='sk-xxx'
//   flutter test test/smoke/qwen_vl_api_smoke_test.dart
//
// 此文件仅用于冒烟预演，正式实施 Task 5 时不会用到。
// 验证点：
//   1. 百炼 OpenAI 兼容 endpoint + ApiKeyProvider 鉴权可用
//   2. qwen3-vl-flash 多模态调用（图片 base64 + 文本）能识别苹果
//   3. response_format=json_object 返回合法 JSON
//   4. JSON 含 dish_name / confidence 等期望字段
//   5. response.text 取文本响应可用
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
        Platform.environment['EATWISE_TEST_MODEL'] ?? 'qwen3-vl-flash';

    // 读测试图转 base64
    final imageFile = File('test/smoke/fixtures/apple.jpg');
    final imageBytes = imageFile.readAsBytesSync();
    final imageBase64 = base64Encode(imageBytes);

    group('Qwen-VL API 冒烟', () {
        if (apiKey == null || apiKey.isEmpty) {
            test('skip: 未设置 EATWISE_TEST_API_KEY', () {
                print('请设置 EATWISE_TEST_API_KEY 环境变量后再运行此测试');
            }, skip: true);
            return;
        }

        test('识别苹果 + json_object 返回', () async {
            final client = OpenAIClient(
                config: OpenAIConfig(
                    authProvider: ApiKeyProvider(apiKey),
                    baseUrl: baseUrl,
                ),
            );

            final systemPrompt = '你是食物识别助手。请识别图中的食物，'
                '返回严格 JSON：'
                '{"dish_name":"食物中文名","is_single_item":true/false,'
                '"confidence":0.0-1.0,"estimated_weight_g_mid":整数克数}'
                '。只返回 JSON，不要其他内容。';

            final response = await client.chat.completions
                .create(
                    ChatCompletionCreateRequest(
                        model: model,
                        responseFormat: ResponseFormat.jsonObject(),
                        messages: [
                            ChatMessage.system(systemPrompt),
                            ChatMessage.user(
                                UserMessageContent.parts([
                                    const TextContentPart(text: '请识别图中的食物'),
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

            final raw = response.text;
            print('=== Qwen-VL raw response ===');
            print(raw);
            print('=== model used: $model ===');
            print('=== finish_reason: ${response.choices.first.finishReason} ===');

            expect(raw, isNotNull, reason: '响应文本为空');
            expect(raw!.isNotEmpty, true, reason: '响应文本为空字符串');

            final json = jsonDecode(raw) as Map<String, dynamic>;
            print('=== parsed JSON ===');
            print(const JsonEncoder.withIndent('  ').convert(json));

            expect(json.containsKey('dish_name'), true,
                reason: 'JSON 缺少 dish_name 字段');
            final dishName = json['dish_name'].toString();
            print('=== dish_name: $dishName ===');
            expect(dishName.isNotEmpty, true, reason: 'dish_name 为空');

            if (json.containsKey('confidence')) {
                final conf = json['confidence'];
                print('=== confidence: $conf ===');
            }
            if (json.containsKey('estimated_weight_g_mid')) {
                final weight = json['estimated_weight_g_mid'];
                print('=== estimated_weight_g_mid: $weight ===');
            }
        });
    });
}
