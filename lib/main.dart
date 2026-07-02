// lib/main.dart
// 诊断版 v3：try-catch 包住整个 main + 错误页兜底
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
import 'data/backup/image_cleanup.dart';
import 'data/database/database.dart';
import 'features/offline/offline_queue_controller.dart';

/// 把启动期异常写入本地文件
Future<void> _writeBootLog(String msg) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/boot_log.txt');
    await f.writeAsString('${DateTime.now().toIso8601String()} $msg\n',
        mode: FileMode.append);
  } catch (_) {}
}

/// 崩溃显示页：把错误画到屏幕上
Widget _crashScreen(Object error, StackTrace stack) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.red[50],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('启动崩溃',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text('错误:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.red[800])),
                SelectableText('$error', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                const Text('堆栈:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(
                    stack.toString().split('\n').take(40).join('\n'),
                    style:
                        const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                const SizedBox(height: 20),
                const Text('请截图发给开发者。',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // 用 zone 包住整个 main，捕获所有同步+异步错误
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Flutter 框架错误兜底
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _writeBootLog('FlutterError: ${details.exception}\n${details.stack}');
    };

    // 先把 UI 跑起来（用 ErrorCapture 包裹，捕获 build 错误）
    runApp(ErrorCapture(
      child: UncontrolledProviderScope(
        container: ProviderContainer(),
        child: const EatWiseApp(),
      ),
    ));

    // UI 起来后再异步初始化
    final initContainer = ProviderContainer();
    try {
      await initContainer.read(appConfigProvider.future);
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
          await initContainer.read(offlineQueueControllerProvider.future);
      await offlineQueue.start();
    } catch (e, st) {
      debugPrint('OfflineQueue 失败：$e');
      _writeBootLog('offlineQueue fail: $e\n$st');
    }

    try {
      final db = await initContainer.read(databaseProvider.future);
      ImageCleanup.runIfBacklogLarge(db).catchError((e) {
        debugPrint('ImageCleanup 失败：$e');
      });
    } catch (e, st) {
      debugPrint('ImageCleanup 初始化失败：$e');
      _writeBootLog('imageCleanup fail: $e\n$st');
    }

    initContainer.dispose();
  }, (error, stack) {
    // zone 兜底：任何未捕获的错误都显示崩溃页
    debugPrint('Zone 未捕获错误: $error');
    _writeBootLog('ZoneError: $error\n$stack');
    runApp(_crashScreen(error, stack));
  });
}

/// 全局错误显示 Widget：把 build 错误显示到屏幕
class ErrorCapture extends StatefulWidget {
  final Widget child;
  const ErrorCapture({super.key, required this.child});
  @override
  State<ErrorCapture> createState() => _ErrorCaptureState();
}

class _ErrorCaptureState extends State<ErrorCapture> {
  FlutterErrorDetails? _error;

  @override
  void initState() {
    super.initState();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _writeBootLog('FlutterError: ${details.exception}\n${details.stack}');
      if (mounted) setState(() => _error = details);
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _crashScreen(_error!.exception, _error!.stack ?? StackTrace.empty);
    }
    return widget.child;
  }
}
