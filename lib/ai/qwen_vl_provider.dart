import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:openai_dart/openai_dart.dart';

import 'prompts.dart';
import 'vision_provider.dart';

/// Qwen-VL 视觉模型 Provider（阿里云百炼，OpenAI-compatible）
/// 使用 response_format=json_object 强制合法 JSON（不用 function calling）
///
/// openai_dart 7.0 API 已核实，来源：
///   github.com/davidmigloz/ai_clients_dart/packages/openai_dart/example/
///   （vision_example.dart / error_handling_example.dart / 源码 content_part.dart /
///    response_format.dart / config.dart）
class QwenVlProvider implements VisionProvider {
  final OpenAIClient _client;
  final String _modelName;

  QwenVlProvider({
    required String apiKey,
    required String baseUrl,
    String modelName = 'qwen3-vl-flash',
  })  : _modelName = modelName,
        _client = OpenAIClient(
          config: OpenAIConfig(
            authProvider: ApiKeyProvider(apiKey), // OpenAIConfig 无 apiKey 参数，用 authProvider
            baseUrl: baseUrl,
          ),
        );

  @override
  String get name => 'Qwen-VL';

  @override
  String get promptVersion => Prompts.version;

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) =>
      recognizeWithClient(_client, _modelName, imageBase64, promptVersion);

  /// 公共识别逻辑（供 GLM-4V-Plus 容灾 Provider 复用）
  /// 两个 Provider 仅 client/baseUrl/modelName 不同，识别流程完全一致
  static Future<VisionRecognitionResult> recognizeWithClient(
    OpenAIClient client,
    String modelName,
    String imageBase64,
    String promptVersion,
  ) async {
    try {
      final response = await client.chat.completions.create(
        ChatCompletionCreateRequest(
          model: modelName, // openai_dart 7.0：model 为纯 String（非 ModelId 包装类）
          responseFormat: ResponseFormat.jsonObject(), // 静态工厂方法，不可加 const
          messages: [
            ChatMessage.system(Prompts.systemPrompt), // 位置参数 String
            ChatMessage.user(
              // 多模态消息：必须用 UserMessageContent.parts(...) 包装 ContentPart 列表
              UserMessageContent.parts([
                const TextContentPart(text: '请识别图中的食物'),
                ContentPart.imageBase64(
                  // 静态工厂：data=原始 base64 字符串（非 data:URL），SDK 内部拼接
                  data: imageBase64,
                  mediaType: 'image/jpeg',
                ),
              ]),
            ),
          ],
        ),
      );

      // response.text 为 String? 便捷访问器（openai_dart 7.0）
      final jsonStr = response.text;

      // T39：检测 refusal（内容安全过滤）
      // 1. 优先检查 OpenAI 标准 refusal 字段（openai_dart 7.0 response.choices[].message.refusal）
      //    但 Qwen-VL 兼容模式可能不填，需文本兜底
      // 2. 文本兜底：refusal 关键词检测（"我无法"/"不能识别"/"内容违反"/"I cannot"/"I can't"）
      if (isRefusalForTest(jsonStr, response)) {
        throw VisionRecognitionException(
          '内容被安全过滤（模型拒绝识别），请换一张照片或手动录入',
          retryable: false,
          isRefusal: true,
        );
      }

      if (jsonStr == null || jsonStr.isEmpty) {
        throw VisionRecognitionException('空响应', retryable: false);
      }

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return VisionRecognitionResult.fromJson(json, promptVersion);
    } on FormatException catch (e) {
      // JSON 语法错误：malformed，不可盲目重试（设计文档 3.2 节）
      throw VisionRecognitionException('JSON 解析失败: ${e.message}', retryable: false);
    } on RateLimitException catch (e) {
      // 429：尊重 Retry-After 头（e.retryAfter 为 Duration?）
      final waitSec = e.retryAfter?.inSeconds;
      throw VisionRecognitionException(
        '限流 429${waitSec != null ? "，Retry-After: ${waitSec}s" : ""}',
        retryable: true,
        retryAfter: e.retryAfter, // 透传 Duration 给上层 L1 等待重试
      );
    } on AuthenticationException catch (e) {
      // 401：key 失效，引导到设置页（设计文档 3.2 节，非 retryable）
      throw VisionRecognitionException('认证失败 401: ${e.message}', retryable: false);
    } on PermissionDeniedException catch (e) {
      // 403：key 无权限，引导到设置页（非 retryable）
      throw VisionRecognitionException('权限拒绝 403: ${e.message}', retryable: false);
    } on RequestTimeoutException catch (e) {
      // 超时：retryable（L1 重试 → L2 切 GLM）
      throw VisionRecognitionException('请求超时: ${e.message}', retryable: true);
    } on ConnectionException catch (e) {
      // 网络错误：retryable
      throw VisionRecognitionException('网络连接失败: ${e.message}', retryable: true);
    } on InternalServerException catch (e) {
      // 5xx：retryable（服务端临时错误）
      throw VisionRecognitionException('服务器错误 ${e.statusCode}: ${e.message}', retryable: true);
    } on ApiException catch (e) {
      // 其余 API 错误：5xx retryable，4xx（400/404 等）非 retryable
      final retryable = e.statusCode >= 500;
      throw VisionRecognitionException('API 错误 ${e.statusCode}: ${e.message}', retryable: retryable);
    } on OpenAIException catch (e) {
      // SDK 基类兜底：retryable（未知错误保守重试）
      throw VisionRecognitionException('OpenAI 错误: ${e.message}', retryable: true);
    } catch (e) {
      if (e is VisionRecognitionException) rethrow;
      throw VisionRecognitionException('未知错误: $e', retryable: true);
    }
  }

  /// 检测模型 refusal（内容安全过滤）— T39
  /// 1. OpenAI 标准 refusal 字段非空 → refusal
  /// 2. 文本兜底：含 refusal 关键词且非合法 JSON（避免误判正常菜名含"无法"等）
  @visibleForTesting
  static bool isRefusalForTest(String? text, dynamic response) {
    // 1. 标准 refusal 字段（openai_dart 7.0：response.choices[].message.refusal）
    try {
      final choices = response.choices;
      if (choices != null && choices.isNotEmpty) {
        final refusal = choices.first.message.refusal;
        if (refusal != null && refusal.isNotEmpty) return true;
      }
    } catch (_) {
      // 字段访问失败（SDK 版本差异 / response 为 null）→ 走文本兜底
    }
    // 2. 文本兜底：空文本或含 refusal 关键词
    if (text == null || text.isEmpty) return false; // 空文本走"空响应"分支
    final lower = text.toLowerCase();
    const refusalKeywords = [
      '我无法', '我不能', '无法识别', '不能识别', '内容违反', '违反政策',
      'i cannot', "i can't", 'i am unable', 'content policy', 'safety',
    ];
    // 仅当文本含关键词且【不是合法 JSON】时判定为 refusal
    // （正常菜名"我无法想象"等极罕见，且正常响应是 JSON 对象不会含这些短语）
    if (refusalKeywords.any((k) => lower.contains(k.toLowerCase()))) {
      try {
        jsonDecode(text); // 是合法 JSON → 不是 refusal（可能是菜名含关键词）
        return false;
      } catch (_) {
        return true; // 非 JSON + 含关键词 → refusal
      }
    }
    return false;
  }
}
