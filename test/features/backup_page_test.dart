import 'dart:io';

import 'package:drift/native.dart';
import 'package:eatwise/data/repositories/pending_recognition_repository.dart';
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

  // M24 Task A5：备份导入会 DELETE FROM pending_recognitions 清空离线队列，
  // 破坏性操作需在确认弹窗中告知用户具体条数（知情同意）。
  // 以下两个测试覆盖 pending>0 与 pending=0 两种场景。
  testWidgets('pending>0 时确认弹窗含离线队列条数提示', (tester) async {
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    // 预置 5 条 pending 记录（导入会清空 pending_recognitions，需在弹窗告知用户）
    final pendingRepo = PendingRecognitionRepository(db);
    for (var i = 0; i < 5; i++) {
      await pendingRepo.enqueue(
        imagePath: '/tmp/fake_$i.jpg',
        mealType: 'breakfast',
        date: '2026-07-05',
      );
    }
    expect(await pendingRepo.countPending(), 5);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: BackupPage()),
    ));
    await tester.pumpAndSettle();

    // 1. 点"从 JSON 导入"，触发 _import，弹出 JSON 粘贴弹窗
    await tester.tap(find.text('从 JSON 导入'));
    await tester.pumpAndSettle();

    // 2. 输入任意非空文本（仅通过空串校验，不会真正执行导入）
    await tester.enterText(
        find.byType(TextField), '{"schemaVersion":1,"tables":{}}');
    // 3. 点"导入"关闭粘贴弹窗，_import 继续：查 countPending → 弹确认弹窗
    await tester.tap(find.text('导入'));

    // countPending 是真实异步 DB 查询，需交替 pump + runAsync 让其完成
    for (var i = 0; i < 8; i++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 150));
      });
    }
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 断言确认弹窗已弹出 + content 含离线队列条数提示
    expect(find.text('确认导入'), findsOneWidget);
    expect(find.textContaining('⚠️ 离线队列中 5 条待识别记录将被清空'),
        findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('pending=0 时确认弹窗不显示离线队列提示', (tester) async {
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    // 空 db，countPending() 返回 0，弹窗不应含离线队列行

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: BackupPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('从 JSON 导入'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField), '{"schemaVersion":1,"tables":{}}');
    await tester.tap(find.text('导入'));

    for (var i = 0; i < 8; i++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 150));
      });
    }
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 断言确认弹窗已弹出，但 content 不含离线队列提示
    expect(find.text('确认导入'), findsOneWidget);
    expect(find.textContaining('离线队列'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
