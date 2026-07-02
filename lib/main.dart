// lib/main.dart
// 诊断版 v2：绝对最简启动 + 全局错误可视 + 本地日志
// 修复目标：即使崩溃也显示错误信息而非闪退，便于定位
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

/// 全局错误显示 Widget：把错误画到屏幕上而非闪退
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
    // 兜底 1：Flutter 框架错误（build/layout/async）
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _writeBootLog('FlutterError: ${details.exception}\n${details.stack}');
      if (mounted) setState(() => _error = details);
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
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
                    const Text('启动错误',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text('Exception:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.red[800])),
                    SelectableText('${_error!.exception}',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 12),
                    const Text('Stack:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SelectableText(
                        _error!.stack.toString().split('\n').take(30).join('\n'),
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace')),
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
    return widget.child;
  }
}

void main() async {
  // 兜底 2：Flutter 框架之外的未捕获异步错误（不闪退，只记日志）
  WidgetsFlutterBinding.ensureInitialized();
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformError: $error');
    _writeBootLog('PlatformError: $error\n$stack');
    return true;
  };

  // 关键修改：先把 UI 跑起来（用 ErrorCapture 包裹），
  // 再异步做所有可能崩溃的初始化。这样即使初始化崩，UI 已在。
  runApp(ErrorCapture(
    child: UncontrolledProviderScope(
      container: ProviderContainer(),
      child: const EatWiseApp(),
    ),
  ));

  // UI 起来后再异步初始化（失败不阻塞已起来的 UI）
  // 用一个独立的 ProviderContainer 给初始化用
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

  // Sentry 跳过（首启无 DSN，跳过省事）
  initContainer.dispose();
}
