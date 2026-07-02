// lib/main.dart
// 降级启动版：所有初始化包 try-catch，任一插件失败不阻塞 UI 启动。
// 修复 workmanager 0.9.x 在部分 Android 设备 release 模式初始化抛异常导致闪退。
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'background/background_dispatcher.dart';
import 'background/background_tasks.dart';
import 'core/config/app_config.dart';
import 'core/error/sentry_init.dart';
import 'data/backup/image_cleanup.dart';
import 'data/database/database.dart';
import 'features/offline/offline_queue_controller.dart';

/// 把启动期异常写入本地文件（首启 Sentry 未配置时，便于用户反馈排查）
Future<void> _writeBootLog(String msg) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/boot_log.txt');
    await f.writeAsString('${DateTime.now().toIso8601String()} $msg\n',
        mode: FileMode.append);
  } catch (_) {
    // 连本地日志都写不了就放弃（不阻塞启动）
  }
}

void main() async {
  // 兜底 1：Flutter 框架未捕获的异步错误（红屏前最后一道防线）
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
    _writeBootLog('FlutterError: ${details.exception}\n${details.stack}');
  };
  // 兜底 2：Flutter 框架之外的未捕获异步错误
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformError: $error');
    _writeBootLog('PlatformError: $error\n$stack');
    return true; // 吞掉，不崩
  };

  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();

  // 1. appConfig（secure_storage 读 API key/Sentry DSN）
  // 包 try-catch：secure_storage 在个别设备首启可能异常，失败则用空配置继续
  try {
    await container.read(appConfigProvider.future);
  } catch (e, st) {
    debugPrint('appConfig 加载失败（降级继续）：$e');
    await _writeBootLog('appConfig fail: $e\n$st');
  }

  // 2. workmanager 初始化（T19）
  // 包 try-catch：workmanager 0.9.x 在部分 Android 设备 release 模式抛 PlatformException
  try {
    await Workmanager().initialize(
      callbackDispatcher,
      // ignore: deprecated_member_use
      isInDebugMode: kDebugMode,
    );
    await BackgroundTasks.registerAll();
  } catch (e, st) {
    debugPrint('Workmanager 初始化失败（降级继续，后台任务不可用）：$e');
    await _writeBootLog('workmanager fail: $e\n$st');
  }

  // 3. 离线队列监听（已有 try-catch，保留）
  try {
    final offlineQueue =
        await container.read(offlineQueueControllerProvider.future);
    await offlineQueue.start();
  } catch (e, st) {
    debugPrint('OfflineQueueController.start 失败：$e');
    await _writeBootLog('offlineQueue fail: $e\n$st');
  }

  // 4. 图片积压清理（已有 try-catch，保留）
  try {
    final db = await container.read(databaseProvider.future);
    ImageCleanup.runIfBacklogLarge(db).catchError((e) {
      debugPrint('ImageCleanup 启动清理失败：$e');
    });
  } catch (e, st) {
    debugPrint('ImageCleanup 初始化失败：$e');
    await _writeBootLog('imageCleanup init fail: $e\n$st');
  }

  // 5. Sentry 初始化（包 try-catch，失败不阻塞 runApp）
  Widget app = UncontrolledProviderScope(
    container: container,
    child: const EatWiseApp(),
  );
  try {
    app = await initSentryAndRunApp(container: container, app: app);
  } catch (e, st) {
    debugPrint('Sentry 初始化失败（降级继续）：$e');
    await _writeBootLog('sentry fail: $e\n$st');
  }

  runApp(app);
}
