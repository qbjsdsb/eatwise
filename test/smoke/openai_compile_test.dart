// 冒烟预演：验证 openai_dart 7.0 API 编译通过
// 仅验证 API 签名（OpenAIClient / OpenAIConfig / ApiKeyProvider /
// ChatMessage.system / ChatMessage.user 多模态 / ContentPart.imageBase64 /
// ResponseFormat.jsonObject / ChatCompletionCreateRequest / response.text /
// 异常层级），不实际调用 API。
//
// 此文件仅用于冒烟预演，正式实施 Task 5 时不会用到。
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart';

void main() {
  test('openai_dart 7.0 API 签名编译验证', () {
    // 1. OpenAIClient + OpenAIConfig + ApiKeyProvider 构造
    final client = OpenAIClient(
      config: OpenAIConfig(
        authProvider: ApiKeyProvider('test-key'),
        baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      ),
    );
    expect(client, isNotNull);

    // 2. ChatMessage.system(String) —— 位置参数
    final systemMsg = ChatMessage.system('你是一个食物识别助手');
    expect(systemMsg, isNotNull);

    // 3. ChatMessage.user 多模态：UserMessageContent.parts([...])
    final userMsg = ChatMessage.user(
      UserMessageContent.parts([
        const TextContentPart(text: '请识别图中的食物'),
        ContentPart.imageBase64(
          data: 'base64dummydata',
          mediaType: 'image/jpeg',
        ),
      ]),
    );
    expect(userMsg, isNotNull);

    // 4. ChatCompletionCreateRequest + ResponseFormat.jsonObject()（无 const）
    final request = ChatCompletionCreateRequest(
      model: 'qwen3-vl-flash',
      responseFormat: ResponseFormat.jsonObject(),
      messages: [systemMsg, userMsg],
    );
    expect(request.model, 'qwen3-vl-flash');
  });

  test('openai_dart 7.0 异常层级可捕获', () {
    // 验证异常类存在且可被 catch（仅类型检查，不实例化）
    void checkTypes() {
      // ApiException 有 statusCode 字段
      ApiException? apiErr;
      RateLimitException? rateLimit;
      AuthenticationException? authErr;
      PermissionDeniedException? permErr;
      RequestTimeoutException? timeoutErr;
      ConnectionException? connErr;
      InternalServerException? serverErr;
      BadRequestException? badReqErr;
      NotFoundException? notFoundErr;
      OpenAIException? openaiErr;
      // 全部置 null 避免未使用警告
      apiErr = null;
      rateLimit = null;
      authErr = null;
      permErr = null;
      timeoutErr = null;
      connErr = null;
      serverErr = null;
      badReqErr = null;
      notFoundErr = null;
      openaiErr = null;
      expect(apiErr, isNull);
      expect(rateLimit, isNull);
      expect(authErr, isNull);
      expect(permErr, isNull);
      expect(timeoutErr, isNull);
      expect(connErr, isNull);
      expect(serverErr, isNull);
      expect(badReqErr, isNull);
      expect(notFoundErr, isNull);
      expect(openaiErr, isNull);
    }

    checkTypes();
  });
}
