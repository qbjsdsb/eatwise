// test/features/update_retry_context_test.dart
// update_page 三阶段重试上下文测试（B 类 P1 修复 2）
//
// 验证修复：error 态"重试"按钮根据 _lastFailedStage 精准重试
// - check 失败 → 重试调 _check（不调 _download/_install）
// - download 失败 → 重试调 _download
// - install 失败 → 重试调 _install 且不重新下载（复用 _downloadedPath）
//
// 用 mocktail mock UpdateService + TestDefaultBinaryMessengerBinding mock
// ApkInstaller MethodChannel。用计数器跟踪方法调用次数，避免 mocktail
// verify 跨阶段语义歧义。
import 'package:eatwise/core/update/apk_installer.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:eatwise/core/update/update_service.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:eatwise/features/update/update_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockUpdateService extends Mock implements UpdateService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockUpdateService service;

  setUp(() {
    service = MockUpdateService();
    registerFallbackValue(DownloadProgress(received: 0, total: 0));
  });

  group('update_page 三阶段重试上下文', () {
    testWidgets('check 失败 → 重试调 _check（不调 _download/_install）',
        (tester) async {
      var checkCallCount = 0;
      var downloadCallCount = 0;
      // checkForUpdate 抛异常 → _lastFailedStage = check
      when(() => service.checkForUpdate()).thenAnswer((_) async {
        checkCallCount++;
        throw Exception('网络错误');
      });
      when(() => service.downloadApk(
            url: any(named: 'url'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async {
        downloadCallCount++;
        return '/tmp/eatwise-update.apk';
      });

      final container = ProviderContainer(overrides: [
        recognize.updateServiceProvider.overrideWith((ref) async => service),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: UpdatePage()),
      ));
      await tester.pump();

      // idle → tap 检查更新 → checking → error（checkForUpdate 抛异常）
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();

      expect(checkCallCount, 1);
      expect(find.textContaining('检查失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      // tap 重试 → _retry → _check（不是 _download/_install）
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      // checkForUpdate 被调用 2 次（初始 + 重试）
      expect(checkCallCount, 2);
      // downloadApk 从未被调用
      expect(downloadCallCount, 0);
      // 仍是 error 态（checkForUpdate 仍抛异常）
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('download 失败 → 重试调 _download', (tester) async {
      final release = ReleaseInfo(
        tagName: 'v0.18.0',
        version: '0.18.0',
        name: '',
        body: '',
        publishedAt: '',
        apkDownloadUrl: 'https://x.apk',
        apkSize: 1024000,
      );
      var checkCallCount = 0;
      var downloadCallCount = 0;
      when(() => service.checkForUpdate()).thenAnswer((_) async {
        checkCallCount++;
        return UpdateAvailable(
            currentVersion: '0.17.0', release: release);
      });
      // downloadApk 抛异常 → _lastFailedStage = download
      when(() => service.downloadApk(
            url: any(named: 'url'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async {
        downloadCallCount++;
        throw Exception('下载失败');
      });

      final container = ProviderContainer(overrides: [
        recognize.updateServiceProvider.overrideWith((ref) async => service),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: UpdatePage()),
      ));
      await tester.pump();

      // check → updateAvailable
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(checkCallCount, 1);

      // download → error（downloadApk 抛异常）
      await tester.tap(find.textContaining('下载并安装'));
      await tester.pumpAndSettle();

      expect(downloadCallCount, 1);
      expect(find.textContaining('下载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      // tap 重试 → _retry → _download（不是 _check）
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      // downloadApk 被调用 2 次（初始 + 重试）
      expect(downloadCallCount, 2);
      // checkForUpdate 仍只被调用 1 次（重试不重新 check）
      expect(checkCallCount, 1);
    });

    testWidgets('install 失败 → 重试调 _install 且不重新下载', (tester) async {
      final release = ReleaseInfo(
        tagName: 'v0.18.0',
        version: '0.18.0',
        name: '',
        body: '',
        publishedAt: '',
        apkDownloadUrl: 'https://x.apk',
        apkSize: 1024000,
      );
      var checkCallCount = 0;
      var downloadCallCount = 0;
      when(() => service.checkForUpdate()).thenAnswer((_) async {
        checkCallCount++;
        return UpdateAvailable(
            currentVersion: '0.17.0', release: release);
      });
      // downloadApk 成功返回路径
      when(() => service.downloadApk(
            url: any(named: 'url'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async {
        downloadCallCount++;
        return '/tmp/eatwise-update.apk';
      });

      // Mock ApkInstaller MethodChannel → 抛 PlatformException
      // _install 调 ApkInstaller.triggerInstall → 抛异常 → _lastFailedStage = install
      var installCallCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ApkInstaller.channel, (call) async {
        installCallCount++;
        throw PlatformException(
            code: 'INSTALL_FAILED', message: 'installer not found');
      });
      addTearDown(() =>
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(ApkInstaller.channel, null));

      final container = ProviderContainer(overrides: [
        recognize.updateServiceProvider.overrideWith((ref) async => service),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: UpdatePage()),
      ));
      await tester.pump();

      // check → updateAvailable
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(checkCallCount, 1);

      // download → readyToInstall
      await tester.tap(find.textContaining('下载并安装'));
      await tester.pumpAndSettle();

      expect(downloadCallCount, 1);
      expect(find.text('打开系统安装器'), findsOneWidget);

      // install → error（triggerInstall 抛 PlatformException）
      await tester.tap(find.text('打开系统安装器'));
      await tester.pumpAndSettle();

      expect(installCallCount, 1);
      expect(find.textContaining('触发安装器失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      // tap 重试 → _retry → _install（复用 _downloadedPath，不重新下载）
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      // triggerInstall 被调用 2 次（初始 + 重试）
      expect(installCallCount, 2);
      // downloadApk 仍只被调用 1 次（重试不重新下载，复用 _downloadedPath）
      expect(downloadCallCount, 1);
      // checkForUpdate 仍只被调用 1 次
      expect(checkCallCount, 1);
    });
  });
}
