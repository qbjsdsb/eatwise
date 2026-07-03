import 'dart:io';

import 'package:drift/native.dart';
import 'package:eatwise/core/config/app_config.dart';
import 'package:eatwise/core/config/secure_config_store.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:eatwise/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MemoryPathProvider extends PathProviderPlatform {
  final String basePath;
  _MemoryPathProvider(this.basePath);
  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

class _MockSecureConfigStore extends Mock implements SecureConfigStore {}

/// 验证设置页 14 天未备份提示：
/// - 造 15 天前的备份文件 → pump SettingsPage → 提示出现
/// - 无备份文件 → 提示不出现（仅显示"从未"）
///
/// 注意：testWidgets 体内在 fake-async zone，真实事件循环被阻塞，
/// 故测试体内的文件准备必须用同步 I/O（createSync/writeAsStringSync/
/// setLastModifiedSync），否则 await 会挂起。setUp 在真实 zone，
/// Directory.systemTemp.createTemp 可用异步。
void main() {
  late EatWiseDatabase db;
  late Directory tempDir;
  late _MockSecureConfigStore mockStore;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('settings_backup_test');
    PathProviderPlatform.instance = _MemoryPathProvider(tempDir.path);

    mockStore = _MockSecureConfigStore();
    // AppConfig.load() 调用 7 个 getter + settings_page._loadSettings 调用 2 个
    when(() => mockStore.getQwenApiKey()).thenAnswer((_) async => null);
    when(() => mockStore.getQwenBaseUrl()).thenAnswer((_) async => null);
    when(() => mockStore.getGlmApiKey()).thenAnswer((_) async => null);
    when(() => mockStore.getGlmBaseUrl()).thenAnswer((_) async => null);
    when(() => mockStore.getSentryDsn()).thenAnswer((_) async => null);
    when(() => mockStore.getSentryEnabled()).thenAnswer((_) async => false);
    when(() => mockStore.getTdeeAutoCalib()).thenAnswer((_) async => true);
    when(() => mockStore.getThemeSeed()).thenAnswer((_) async => 0xFF5B8C7B);
    when(() => mockStore.getCurrentMonthCount()).thenAnswer((_) async => 0);
    when(() => mockStore.getImageRetentionDays()).thenAnswer((_) async => 30);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('超过 14 天未备份显示提示', (tester) async {
    // 造 15 天前的备份文件（同步 I/O：fake-async zone 下异步文件操作会挂起）
    final backupDir = Directory('${tempDir.path}/backups');
    backupDir.createSync(recursive: true);
    final backupFile = File('${backupDir.path}/eatwise_backup_20260617.json');
    backupFile.writeAsStringSync('{"test":1}');
    // 设置 mtime 为 15 天前
    final oldTime = DateTime.now().subtract(const Duration(days: 15));
    backupFile.setLastModifiedSync(oldTime);

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
      secureConfigStoreProvider.overrideWith((ref) => mockStore),
    ]);
    addTearDown(container.dispose);

    // 放大视口：备份区位于 ListView 后段，默认视口无法完整显示
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsPage()),
    ));
    // runAsync 让 _loadSettings 中的真实异步（mock getter、目录检查）
    // 在真实事件循环中完成；pumpAndSettle 会等所有 frame 稳定。
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('已超过 14 天未备份'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('从未备份不显示超期提示（仅显示"从未"）', (tester) async {
    // 不造任何备份文件
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
      secureConfigStoreProvider.overrideWith((ref) => mockStore),
    ]);
    addTearDown(container.dispose);

    // 放大视口：备份区位于 ListView 后段，默认视口无法完整显示
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsPage()),
    ));
    // runAsync 让 _loadSettings 中的真实异步（mock getter、目录检查）
    // 在真实事件循环中完成；pumpAndSettle 会等所有 frame 稳定。
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('从未'), findsOneWidget);
    expect(find.textContaining('已超过 14 天未备份'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
