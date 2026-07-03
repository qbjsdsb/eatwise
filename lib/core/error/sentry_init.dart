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

  await SentryFlutter.init(
    (options) {
      options.dsn = dsn;
      options.beforeSend = scrubBeforeSend;
      // 采样率：个人自用全采（1.0），无需抽样
      options.tracesSampleRate = 1.0;
      // Release 版本配合 --split-debug-info 解符号
      options.release = const String.fromEnvironment('SENTRY_RELEASE',
          defaultValue: 'eatwise@0.10.0');
    },
    appRunner: () {},
  );

  // SentryFlutter.init 已在内部 runApp，但为统一返回 widget，这里返回 app
  // 注意：调用方需用 SentryWidget 包裹 app
  return SentryWidget(child: app);
}
