// M21 Round 2：QwenVlProvider.isRefusalForTest 单元测试
//
// 验证 refusal 检测逻辑各分支（T39）：
// 1. OpenAI 标准 refusal 字段非空 → true
// 2. response.choices 为空 → 走文本兜底
// 3. response 字段访问失败（response 为 null）→ 走文本兜底
// 4. 文本含 refusal 关键词 + 非 JSON → true
// 5. 文本含 refusal 关键词 + 合法 JSON → false（菜名含关键词但合法）
// 6. 空文本 → false（走"空响应"分支）
// 7. 正常 JSON 响应（无关键词） → false
// 8. 文本不含关键词 → false
//
// recognizeWithClient 依赖 OpenAIClient 真实 HTTP，由 sprint1_e2e_test 间接覆盖。
// isRefusalForTest 是纯函数（@visibleForTesting），直测各分支。
import 'package:eatwise/ai/qwen_vl_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟 openai_dart response 结构（只含 isRefusalForTest 访问的字段）
///
/// isRefusalForTest 访问路径：response.choices[0].message.refusal
/// 用 Map 构造模拟对象，dynamic 参数允许任意结构。
class _FakeResponse {
  final List<_FakeChoice>? choices;

  _FakeResponse({this.choices});
}

class _FakeChoice {
  final _FakeMessage message;

  _FakeChoice({required this.message});
}

class _FakeMessage {
  final String? refusal;

  _FakeMessage({this.refusal});
}

void main() {
  group('QwenVlProvider.isRefusalForTest', () {
    group('标准 refusal 字段分支', () {
      test('response.choices[0].message.refusal 非空 → true', () {
        final response = _FakeResponse(
          choices: [
            _FakeChoice(message: _FakeMessage(refusal: '内容被安全过滤')),
          ],
        );
        expect(QwenVlProvider.isRefusalForTest('任何文本', response), true);
      });

      test('response.choices 为空列表 → 走文本兜底', () {
        final response = _FakeResponse(choices: []);
        // 空文本 → false（走"空响应"分支）
        expect(QwenVlProvider.isRefusalForTest('', response), false);
        // 文本含关键词 + 非 JSON → true
        expect(QwenVlProvider.isRefusalForTest('我无法识别', response), true);
      });

      test('response.choices 为 null → 走文本兜底', () {
        final response = _FakeResponse(choices: null);
        expect(QwenVlProvider.isRefusalForTest('我无法识别', response), true);
        expect(QwenVlProvider.isRefusalForTest('正常文本', response), false);
      });

      test('response 为 null → 走文本兜底', () {
        // dynamic 参数允许传 null
        expect(QwenVlProvider.isRefusalForTest('我无法识别', null), true);
        expect(QwenVlProvider.isRefusalForTest('正常文本', null), false);
      });
    });

    group('文本兜底：refusal 关键词分支', () {
      test('文本含"我无法" + 非 JSON → true', () {
        final response = _FakeResponse(choices: null);
        expect(QwenVlProvider.isRefusalForTest('我无法识别这道菜', response), true);
      });

      test('文本含"i cannot" + 非 JSON → true', () {
        final response = _FakeResponse(choices: null);
        expect(QwenVlProvider.isRefusalForTest('I cannot identify this food', response), true);
      });

      test('文本含"内容违反" + 非 JSON → true', () {
        final response = _FakeResponse(choices: null);
        expect(QwenVlProvider.isRefusalForTest('内容违反政策，无法识别', response), true);
      });

      test('文本含"我无法" + 合法 JSON → false（菜名含关键词但合法）', () {
        final response = _FakeResponse(choices: null);
        // 合法 JSON 对象（正常响应格式），即使含"我无法"也判 false
        const jsonText = '{"name":"我无法想象这道菜","reason":"..."}';
        expect(QwenVlProvider.isRefusalForTest(jsonText, response), false);
      });
    });

    group('文本兜底：非 refusal 分支', () {
      test('空文本 → false（走"空响应"分支）', () {
        final response = _FakeResponse(choices: null);
        expect(QwenVlProvider.isRefusalForTest('', response), false);
      });

      test('正常 JSON 响应（无关键词） → false', () {
        final response = _FakeResponse(choices: null);
        const jsonText = '{"name":"鸡胸肉沙拉","reason":"高蛋白低脂"}';
        expect(QwenVlProvider.isRefusalForTest(jsonText, response), false);
      });

      test('文本不含关键词 → false', () {
        final response = _FakeResponse(choices: null);
        expect(QwenVlProvider.isRefusalForTest('这是一道鸡胸肉沙拉', response), false);
      });
    });
  });
}
