// lib/main.dart 完整覆写：
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/error/sentry_init.dart';
import 'features/offline/offline_queue_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();
  // 先加载 appConfig（Sentry DSN / API key 都从这里读）
  await container.read(appConfigProvider.future);

  // 启动离线队列监听（Sprint 2 T14 修复：原先 main 未启动）
  try {
    final offlineQueue =
        await container.read(offlineQueueControllerProvider.future);
    await offlineQueue.start();
  } catch (e) {
    debugPrint('OfflineQueueController.start 失败：$e');
  }

  // 初始化 Sentry 并获取包裹后的 app
  final app = await initSentryAndRunApp(
    container: container,
    app: UncontrolledProviderScope(
      container: container,
      child: const EatWiseApp(),
    ),
  );

  runApp(app);
}
