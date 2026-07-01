// lib/main.dart 完整覆写（T17 版本 + T19 workmanager 初始化）：
import 'package:flutter/foundation.dart'; // kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'background/background_dispatcher.dart';
import 'background/background_tasks.dart';
import 'core/config/app_config.dart';
import 'core/error/sentry_init.dart';
import 'features/offline/offline_queue_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();
  // 先加载 appConfig（Sentry DSN / API key 都从这里读）
  await container.read(appConfigProvider.future);

  // T19: 初始化 workmanager（必须在 callbackDispatcher 定义之后）
  // workmanager 0.9.x: isInDebugMode 已废弃且无效，保留以兼容计划，用 ignore 抑制告警
  await Workmanager().initialize(
    callbackDispatcher,
    // ignore: deprecated_member_use
    isInDebugMode: kDebugMode,
  );
  // 注册周期任务（重复注册用 update 策略，不取消已有调度）
  await BackgroundTasks.registerAll();

  // 启动离线队列监听（Sprint 2 T14）
  try {
    final offlineQueue =
        await container.read(offlineQueueControllerProvider.future);
    await offlineQueue.start();
  } catch (e) {
    debugPrint('OfflineQueueController.start 失败：$e');
  }

  // 初始化 Sentry 并获取包裹后的 app（T17）
  final app = await initSentryAndRunApp(
    container: container,
    app: UncontrolledProviderScope(
      container: container,
      child: const EatWiseApp(),
    ),
  );

  runApp(app);
}
