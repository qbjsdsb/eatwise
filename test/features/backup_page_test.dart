import 'dart:io';

import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/backup/backup_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MemoryPathProvider extends PathProviderPlatform {
  final String basePath;
  _MemoryPathProvider(this.basePath);
  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

/// 验证 BackupPage：
/// - 渲染导出/导入按钮
/// - 点导出 → 生成 JSON 文件 + SnackBar 提示
void main() {
  late EatWiseDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('backup_page_test');
    PathProviderPlatform.instance = _MemoryPathProvider(tempDir.path);
  });
  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('渲染导出/导入按钮', (tester) async {
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: BackupPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('导出为 JSON'), findsOneWidget);
    expect(find.text('从 JSON 导入'), findsOneWidget);
  });

  testWidgets('点导出生成 JSON 文件并提示', (tester) async {
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: BackupPage()),
    ));
    await tester.pumpAndSettle();

    // 触发导出：tap 启动 _export。_export 含多段串行真实异步
    // （6 次 DB 查询 + getApplicationDocumentsDirectory + File.writeAsString +
    // showSnackBar），在 testWidgets 的 fake-async zone 下每段真实 I/O 都会挂起，
    // 故需交替 pump（flush microtask 推进到下一段真实 I/O）+ runAsync（在真实事件
    // 循环中完成该段 I/O）多轮，才能让 _export 走完并渲染 SnackBar。
    await tester.tap(find.text('导出为 JSON'));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 250));
      });
    }
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 验证 SnackBar 出现
    expect(find.textContaining('已导出到'), findsOneWidget);

    // 验证文件生成
    final files = tempDir.listSync().whereType<File>().toList();
    expect(files.any((f) => f.path.contains('eatwise_backup_')), isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
