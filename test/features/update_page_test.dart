// UpdatePage widget 测试（M16-E1）
//
// 验证状态机：
// - idle：显示"检查更新"按钮
// - checking → upToDate：显示"已是最新版本"
// - updateAvailable：显示新版本号 + release notes + 下载按钮
// - error：显示错误信息 + 重试按钮
// - downloading：进度条 + 已下载/总大小 → readyToInstall
//
// 用 mocktail mock UpdateService，通过 override updateServiceProvider 注入。
import 'package:eatwise/core/update/update_models.dart';
import 'package:eatwise/core/update/update_service.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:eatwise/features/update/update_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockUpdateService extends Mock implements UpdateService {}

void main() {
  late MockUpdateService service;

  setUp(() {
    service = MockUpdateService();
    registerFallbackValue(DownloadProgress(received: 0, total: 0));
  });

  testWidgets('初始状态显示"检查更新"按钮', (tester) async {
    final container = ProviderContainer(overrides: [
      recognize.updateServiceProvider.overrideWith((ref) async => service),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: UpdatePage()),
    ));
    await tester.pump();

    expect(find.text('检查更新'), findsOneWidget);
  });

  testWidgets('点击检查更新 → checking → upToDate 显示"已是最新版本"', (tester) async {
    when(() => service.checkForUpdate())
        .thenAnswer((_) async => UpToDate(currentVersion: '0.17.0'));

    final container = ProviderContainer(overrides: [
      recognize.updateServiceProvider.overrideWith((ref) async => service),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: UpdatePage()),
    ));
    await tester.pump();

    await tester.tap(find.text('检查更新'));
    await tester.pump(); // 触发 checking
    await tester.pumpAndSettle(); // 等 checkForUpdate 完成

    expect(find.textContaining('已是最新版本'), findsOneWidget);
  });

  testWidgets('有新版本时显示新版本号 + release notes + 下载按钮', (tester) async {
    final release = ReleaseInfo(
      tagName: 'v0.18.0',
      version: '0.18.0',
      name: 'EatWise v0.18.0',
      body: '## 新功能\n- 应用内更新',
      publishedAt: '2026-07-05',
      apkDownloadUrl: 'https://x.apk',
      apkSize: 25000000,
    );
    when(() => service.checkForUpdate()).thenAnswer(
        (_) async => UpdateAvailable(currentVersion: '0.17.0', release: release));

    final container = ProviderContainer(overrides: [
      recognize.updateServiceProvider.overrideWith((ref) async => service),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: UpdatePage()),
    ));
    await tester.pump();

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    expect(find.textContaining('0.18.0'), findsWidgets);
    expect(find.textContaining('应用内更新'), findsOneWidget);
    expect(find.textContaining('下载并安装'), findsOneWidget);
  });

  testWidgets('默认折叠显示前 10 行 + 展开按钮', (tester) async {
    // 构造超过 10 行的 release notes，触发折叠 + 展开按钮显示
    final release = ReleaseInfo(
      tagName: 'v0.18.0',
      version: '0.18.0',
      name: 'EatWise v0.18.0',
      body: List.generate(15, (i) => '- 更新条目 ${i + 1}').join('\n'),
      publishedAt: '2026-07-05',
      apkDownloadUrl: 'https://x.apk',
      apkSize: 25000000,
    );
    when(() => service.checkForUpdate()).thenAnswer(
        (_) async => UpdateAvailable(currentVersion: '0.17.0', release: release));

    // 调大测试 surface，避免 release notes Card 撑爆 Scaffold body
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(overrides: [
      recognize.updateServiceProvider.overrideWith((ref) async => service),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: UpdatePage()),
    ));
    await tester.pump();

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    // 默认折叠时显示"展开全文"按钮
    expect(find.text('展开全文'), findsOneWidget);
    // 不应显示"收起"按钮
    expect(find.text('收起'), findsNothing);
  });

  testWidgets('点击展开显示完整内容', (tester) async {
    final release = ReleaseInfo(
      tagName: 'v0.18.0',
      version: '0.18.0',
      name: 'EatWise v0.18.0',
      body: List.generate(15, (i) => '- 更新条目 ${i + 1}').join('\n'),
      publishedAt: '2026-07-05',
      apkDownloadUrl: 'https://x.apk',
      apkSize: 25000000,
    );
    when(() => service.checkForUpdate()).thenAnswer(
        (_) async => UpdateAvailable(currentVersion: '0.17.0', release: release));

    // 调大测试 surface，避免展开后完整内容撑爆 Scaffold body
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(overrides: [
      recognize.updateServiceProvider.overrideWith((ref) async => service),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: UpdatePage()),
    ));
    await tester.pump();

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    // 折叠状态下不应有 SingleChildScrollView 包裹 release notes
    expect(find.byType(SingleChildScrollView), findsNothing);

    // 点击展开
    await tester.tap(find.text('展开全文'));
    await tester.pumpAndSettle();

    // 展开后按钮变为"收起"
    expect(find.text('收起'), findsOneWidget);
    expect(find.text('展开全文'), findsNothing);

    // 展开后用 SingleChildScrollView 包裹完整内容（无 maxLines 限制）
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('检查失败显示错误信息 + 重试按钮', (tester) async {
    when(() => service.checkForUpdate())
        .thenAnswer((_) async => const CheckFailed('网络错误'));

    final container = ProviderContainer(overrides: [
      recognize.updateServiceProvider.overrideWith((ref) async => service),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: UpdatePage()),
    ));
    await tester.pump();

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    expect(find.textContaining('网络错误'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('下载中显示进度条 + 已下载/总大小', (tester) async {
    final release = ReleaseInfo(
      tagName: 'v0.18.0',
      version: '0.18.0',
      name: '',
      body: '',
      publishedAt: '',
      apkDownloadUrl: 'https://x.apk',
      apkSize: 1024000,
    );
    when(() => service.checkForUpdate()).thenAnswer(
        (_) async => UpdateAvailable(currentVersion: '0.17.0', release: release));

    // 模拟下载：先回调进度，再 await 100ms 让 UI 进入 downloading 状态
    when(() => service.downloadApk(
            url: any(named: 'url'),
            onProgress: any(named: 'onProgress')))
        .thenAnswer((inv) async {
      final onProgress =
          inv.namedArguments[#onProgress] as void Function(DownloadProgress);
      onProgress(const DownloadProgress(received: 512000, total: 1024000));
      await Future.delayed(const Duration(milliseconds: 100));
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

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('下载并安装'));
    await tester.pump(); // 进入 downloading

    // 进度条显示
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // 512000 字节 = 500 KB，应显示在 "50%  (500 KB / 1000 KB)" 文案中
    expect(find.textContaining('500'), findsOneWidget);

    await tester.pumpAndSettle(); // 等下载完成 → readyToInstall

    // 按钮文案精确匹配（副标题含"打开系统安装器"会模糊匹配 2 个）
    expect(find.text('打开系统安装器'), findsOneWidget);
  });
}
