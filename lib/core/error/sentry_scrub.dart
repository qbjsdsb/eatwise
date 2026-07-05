// lib/core/error/sentry_scrub.dart
// ignore_for_file: deprecated_member_use
import 'package:sentry_flutter/sentry_flutter.dart';

/// Sentry beforeSend 脱敏钩子
/// 剥离业务字段：食物名/份量/体重/热量/API key/图片路径
/// 保留：异常类型、堆栈、设备型号、App 版本
///
/// 脱敏策略：
/// 1. 清空 server_name（不发送设备名）
/// 2. 遍历 event.extra / event.tags，key 或 value 含敏感词的删除
/// 3. exception message 中的文件路径（/data/.../image_xxx.jpg）替换为 [path]
/// 4. request body / hint 中的 API key 模式替换为 [redacted]
SentryEvent? scrubBeforeSend(SentryEvent event, Hint hint) {
  // 1. 清空 server_name
  event.serverName = '';

  // 2. 脱敏 extra
  final extra = Map<String, dynamic>.from(event.extra ?? const {});
  final scrubbedExtra = <String, dynamic>{};
  for (final entry in extra.entries) {
    if (_isSensitiveKey(entry.key)) continue;
    scrubbedExtra[entry.key] = _scrubValue(entry.value);
  }
  event.extra = scrubbedExtra;

  // 2.1 脱敏 tags（与 extra 同模式：命中 _isSensitiveKey 的 entry 删除）
  final tags = Map<String, String>.from(event.tags ?? const {});
  final scrubbedTags = <String, String>{};
  for (final entry in tags.entries) {
    if (_isSensitiveKey(entry.key)) continue;
    scrubbedTags[entry.key] = entry.value;
  }
  event.tags = scrubbedTags;

  // 3. 脱敏 exception message 中的路径和 key
  final exceptions = event.exceptions;
  if (exceptions != null) {
    for (final ex in exceptions) {
      ex.value = _scrubString(ex.value);
    }
  }

  // 4. 脱敏 breadcrumbs 中的 message
  final breadcrumbs = event.breadcrumbs;
  if (breadcrumbs != null) {
    for (final bc in breadcrumbs) {
      if (bc.message != null) {
        bc.message = _scrubString(bc.message);
      }
      if (bc.data != null) {
        final scrubbedData = <String, dynamic>{};
        for (final entry in bc.data!.entries) {
          if (_isSensitiveKey(entry.key)) continue;
          scrubbedData[entry.key] = _scrubValue(entry.value);
        }
        bc.data = scrubbedData;
      }
    }
  }

  // 5. 脱敏顶层 message（Sentry.captureMessage 上报的原文）
  if (event.message != null) {
    final scrubbed = _scrubString(event.message!.formatted) ?? '';
    event.message = SentryMessage(scrubbed);
  }

  // 6. 丢弃 request（HTTP 请求的 url/headers/cookies/body 可能含 API key，
  // 食物 app 不需要 HTTP 请求信息调试，直接置空最安全）
  event.request = null;

  return event;
}

/// 敏感 key 关键词（食物/份量/体重/热量/key/路径/token/secret）
bool _isSensitiveKey(String key) {
  final lower = key.toLowerCase();
  const sensitive = [
    'food', 'dish', 'serving', 'weight', 'calorie', 'kcal', 'protein', 'fat', 'carb',
    'api_key', 'apikey', 'key', 'token', 'secret', 'password', 'dsn',
    'image_path', 'imagepath', 'thumbnail', 'original_image',
  ];
  return sensitive.any((s) => lower.contains(s));
}

/// 脱敏字符串值：路径 → [path]，疑似 key/token → [redacted]
String? _scrubString(String? input) {
  if (input == null) return null;
  // 文件路径（含 /data/ 或 .jpg/.png/.jpeg）
  // 注意：计划原文用 raw 字符串 r'...\'..' 无法转义单引号（Dart raw 串不支持 \），
  // 改用普通字符串 + 转义，正则语义完全一致：/[^\s"'<>]+\.(jpg|jpeg|png|webp)/
  var result = input.replaceAll(RegExp('/[^\\s"\'<>]+\\.(jpg|jpeg|png|webp)'), '[path]');
  // 32+ 位 hex/key 模式（大小写都匹配：SHA256/UUID 去横线/JWT 签名常含大写）
  result = result.replaceAll(RegExp(r'[a-fA-F0-9]{32,}'), '[redacted]');
  // sk- 开头的 API key
  result = result.replaceAll(RegExp(r'sk-[a-zA-Z0-9]+'), '[redacted]');
  return result;
}

dynamic _scrubValue(dynamic value) {
  if (value is String) return _scrubString(value);
  return value;
}
