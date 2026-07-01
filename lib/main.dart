import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/error/sentry_init.dart';
import 'features/offline/offline_queue_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 用 ProviderContainer 复用：启动离线队列监听后传给 runApp
  // Sprint 2 T14 修复：原先 main 未启动 offlineQueueControllerProvider，
  // 导致离线拍照联网后不会自动回补（P0 缺口）
  final container = ProviderContainer();
  // 先加载 appConfig（Sentry DSN / API key 都从这里读，T17 会改为用 appConfig.sentryDsn）
  await container.read(appConfigProvider.future);
  await initSentry();
  try {
    final offlineQueue =
        await container.read(offlineQueueControllerProvider.future);
    await offlineQueue.start();
  } catch (e) {
    // 启动失败不阻塞 App（如 connectivity_plus 在沙箱无平台通道）
    // 生产环境由 Sentry 上报
    debugPrint('OfflineQueueController.start 失败：$e');
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const EatWiseApp(),
    ),
  );
}
