// test/core/sentry_scrub_test.dart
// ignore_for_file: deprecated_member_use
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:eatwise/core/error/sentry_scrub.dart';

void main() {
  group('scrubBeforeSend', () {
    test('清空 server_name', () {
      final event = SentryEvent(serverName: 'iPhone15-Pro');
      final result = scrubBeforeSend(event, Hint());
      expect(result!.serverName, '');
    });

    test('删除敏感 key 的 extra（food_name/calories/api_key）', () {
      final event = SentryEvent(extra: {
        'food_name': '宫保鸡丁',
        'calories': 500,
        'weight_kg': 70.5,
        'api_key': 'sk-xxx',
        'normal_field': 'ok',
      });
      final result = scrubBeforeSend(event, Hint())!;
      expect(result.extra!.containsKey('food_name'), isFalse);
      expect(result.extra!.containsKey('calories'), isFalse);
      expect(result.extra!.containsKey('weight_kg'), isFalse);
      expect(result.extra!.containsKey('api_key'), isFalse);
      expect(result.extra!['normal_field'], 'ok');
    });

    test('exception message 中的图片路径替换为 [path]', () {
      final ex = SentryException(
        type: 'FormatException',
        value: 'Failed to read /data/user/0/app/files/images/img123.jpg',
      );
      final event = SentryEvent(exceptions: [ex]);
      final result = scrubBeforeSend(event, Hint())!;
      expect(result.exceptions!.first.value, contains('[path]'));
      expect(result.exceptions!.first.value, isNot(contains('img123.jpg')));
    });

    test('API key 模式 sk-xxx 替换为 [redacted]', () {
      final ex = SentryException(
        type: 'ApiException',
        value: 'Auth failed with key sk-abcd1234567890efgh',
      );
      final event = SentryEvent(exceptions: [ex]);
      final result = scrubBeforeSend(event, Hint())!;
      expect(result.exceptions!.first.value, contains('[redacted]'));
      expect(result.exceptions!.first.value, isNot(contains('sk-abcd')));
    });

    test('breadcrumb message 中的路径也脱敏', () {
      final bc = Breadcrumb(message: 'saved image to /tmp/photo.png');
      final event = SentryEvent(breadcrumbs: [bc]);
      final result = scrubBeforeSend(event, Hint())!;
      expect(result.breadcrumbs!.first.message, contains('[path]'));
    });

    test('返回 null 丢弃事件（用户关闭上报时）', () {
      // scrubBeforeSend 本身不返回 null，丢弃逻辑在 initSentry 中根据 sentryEnabled 判断
      // 这里测试 scrub 函数始终返回 event（不丢弃）
      final event = SentryEvent();
      expect(scrubBeforeSend(event, Hint()), isNotNull);
    });
  });
}
