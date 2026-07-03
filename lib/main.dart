// lib/main.dart
// 正式版：单一 ProviderContainer + 全局错误兜底 + 本地日志
// 修复双容器导致离线队列监听被销毁的问题
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'background/background_dispatcher.dart';
import 'background/background_tasks.dart';
import 'core/config/app_config.dart';
import 'core/error/sentry_init.dart';
import 'core/theme/theme_controller.dart';
import 'data/backup/image_cleanup.dart';
import 'data/database/database.dart';
import 'features/offline/offline_queue_controller.dart';

/// 把启动期异常写入本地文件（便于用户反馈排查）
Future<void> _writeBootLog(String msg) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/boot_log.txt');
    await f.writeAsString('${DateTime.now().toIso8601String()} $msg\n',
        mode: FileMode.append);
  } catch (_) {}
}

void main() {
  // 用 zone 包住整个 main，捕获所有同步+异步错误
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Flutter 框架错误兜底（build/layout/async）
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _writeBootLog('FlutterError: ${details.exception}\n${details.stack}');
    };

    // 单一 ProviderContainer：UI 与初始化共用，避免双容器导致监听被销毁
    final container = ProviderContainer();

    // 主题种子色：runApp 前快速读（轻量 secure_storage 单 key），首帧即用正确主题色，避免换肤闪烁
    // 复用 secureConfigStoreProvider 实例（后续 appConfigProvider 也会用它），避免重复实例化
    try {
      final store = container.read(secureConfigStoreProvider);
      final seed = await store.getThemeSeed();
      container.read(themeSeedProvider.notifier).set(seed);
    } catch (_) {
      // 读取失败用默认色（莫奈《睡莲》青绿），不阻塞启动
    }

    // 用 Sentry 包裹 app（DSN 为空时 initSentryAndRunApp 直接返回原 app，跳过 Sentry）
    final app = await initSentryAndRunApp(
      container: container,
      app: UncontrolledProviderScope(
        container: container,
        child: const EatWiseApp(),
      ),
    );
    runApp(app);

    // UI 起来后再异步初始化（失败降级继续，不阻塞已起来的 UI）
    // 关键：用同一个 container，不要 dispose（随 app 生命周期存活）
    try {
      await container.read(appConfigProvider.future);
    } catch (e, st) {
      debugPrint('appConfig 加载失败：$e');
      _writeBootLog('appConfig fail: $e\n$st');
    }

    try {
      await Workmanager().initialize(
        callbackDispatcher,
        // ignore: deprecated_member_use
        isInDebugMode: kDebugMode,
      );
      await BackgroundTasks.registerAll();
    } catch (e, st) {
      debugPrint('Workmanager 失败：$e');
      _writeBootLog('workmanager fail: $e\n$st');
    }

    try {
      final offlineQueue =
          await container.read(offlineQueueControllerProvider.future);
      await offlineQueue.start();
    } catch (e, st) {
      debugPrint('OfflineQueue 失败：$e');
      _writeBootLog('offlineQueue fail: $e\n$st');
    }

    try {
      final db = await container.read(databaseProvider.future);
      // 读取用户配置的图片保留期（0=永久保留），与后台任务对齐
      final store = container.read(secureConfigStoreProvider);
      final retentionDays = await store.getImageRetentionDays();
      ImageCleanup.runIfBacklogLarge(db, retentionDays: retentionDays)
          .catchError((e) {
        debugPrint('ImageCleanup 失败：$e');
      });
    } catch (e, st) {
      debugPrint('ImageCleanup 初始化失败：$e');
      _writeBootLog('imageCleanup fail: $e\n$st');
    }
    // 注意：不 dispose container，它随 app 生命周期存活
  }, (error, stack) {
    // zone 兜底：未捕获错误记日志 + 上报 Sentry（未初始化时 no-op，安全）
    // 不 runApp 错误页，避免覆盖已起来的 UI
    debugPrint('Zone 未捕获错误: $error');
    _writeBootLog('ZoneError: $error\n$stack');
    Sentry.captureException(error, stackTrace: stack);
  });
}
