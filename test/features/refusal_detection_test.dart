import 'package:eatwise/ai/qwen_vl_provider.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 直接测 isRefusalForTest 静态方法（@visibleForTesting 暴露）
  // response 为 null 时走文本兜底分支

  test('refusal 文本（非 JSON + 含关键词）判定为 refusal', () {
    expect(QwenVlProvider.isRefusalForTest('我无法识别这张图片', null), isTrue);
    expect(QwenVlProvider.isRefusalForTest('I cannot help with this', null), isTrue);
  });

  test('合法 JSON 不判定为 refusal（即使含关键词）', () {
    // 正常响应是 JSON，即使菜名含"无法"也不是 refusal
    expect(QwenVlProvider.isRefusalForTest('{"dish_name":"无法命名的菜"}', null), isFalse);
  });

  test('正常 JSON 响应不判定为 refusal', () {
    expect(QwenVlProvider.isRefusalForTest('{"dish_name":"宫保鸡丁"}', null), isFalse);
  });

  test('空文本不判定为 refusal（走空响应分支）', () {
    expect(QwenVlProvider.isRefusalForTest('', null), isFalse);
    expect(QwenVlProvider.isRefusalForTest(null, null), isFalse);
  });

  test('VisionRecognitionException isRefusal 默认 false', () {
    // 构造器非 const（vision_provider.dart 现有构造器无 const 关键字），用 final
    final e = VisionRecognitionException('test');
    expect(e.isRefusal, isFalse);
  });

  test('VisionRecognitionException 可设置 isRefusal', () {
    final e = VisionRecognitionException('refusal', isRefusal: true);
    expect(e.isRefusal, isTrue);
    expect(e.retryable, isFalse);
  });
}
