// lib/core/error/sentry_init.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/app_config.dart';
import 'sentry_scrub.dart';

/// 初始化 Sentry
/// 在 main() 中 runApp 前调用，用 SentryFlutter.init 包裹 runApp
///
/// 若 DSN 为空或 sentryEnabled=false，则跳过初始化（直接 runApp）
/// appConfig 加载失败时降级跳过 Sentry（不阻塞 runApp，避免白屏）
Future<Widget> initSentryAndRunApp({
  required ProviderContainer container,
  required Widget app,
}) async {
  AppConfig config;
  try {
    config = await container.read(appConfigProvider.future);
  } catch (e) {
    debugPrint('appConfig 加载失败，跳过 Sentry：$e');
    return app;
  }
  final dsn = config.sentryDsn;

  if (dsn.isEmpty || !config.sentryEnabled) {
    debugPrint('Sentry 未启用：dsn 空=${dsn.isEmpty}, enabled=${config.sentryEnabled}');
    return app;
  }

  // try-catch 包裹 SentryFlutter.init：若初始化抛异常（DSN 格式错/插件未就绪/
  // 版本不兼容），降级返回原 app 不阻塞 runApp，避免永久黑屏（zone guard 只记
  // 日志不会 runApp，用户将看到黑屏）
  try {
    await SentryFlutter.init(
      (options) {
        options.dsn = dsn;
        options.beforeSend = scrubBeforeSend;
        // 采样率：个人自用全采（1.0），无需抽样
        options.tracesSampleRate = 1.0;
        // Release 版本配合 --split-debug-info 解符号
        // TODO: 后续从 PackageInfo 读取版本号替代硬编码（HANDOFF 待办）
        options.release = const String.fromEnvironment('SENTRY_RELEASE',
            defaultValue: 'eatwise@0.15.0');
      },
      appRunner: () {},
    );
  } catch (e, st) {
    debugPrint('SentryFlutter.init 失败，跳过 Sentry：$e\n$st');
    return app; // 降级：返回原 app（不包 SentryWidget），保证 runApp 能执行
  }

  // SentryFlutter.init 仅初始化 SDK（appRunner 为空，不内部 runApp）。
  // 调用方 main.dart 负责 runApp，这里返回已包 SentryWidget 的 app。
  return SentryWidget(child: app);
}
