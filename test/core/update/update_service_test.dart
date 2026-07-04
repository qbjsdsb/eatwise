// UpdateService TDD 测试（M16-D1）
//
// 验证 UpdateService 编排逻辑：
// - checkForUpdate：组合 GitHubReleaseClient + 版本比较，返回 UpdateCheckResult
// - downloadApk：透传 ApkDownloader
//
// 用 mocktail mock GitHubReleaseClient + ApkDownloader，不依赖真实网络/文件系统。
import 'package:eatwise/core/update/apk_downloader.dart';
import 'package:eatwise/core/update/github_release_client.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:eatwise/core/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGitHubReleaseClient extends Mock implements GitHubReleaseClient {}
class MockApkDownloader extends Mock implements ApkDownloader {}

void main() {
  late MockGitHubReleaseClient releaseClient;
  late MockApkDownloader downloader;

  setUp(() {
    releaseClient = MockGitHubReleaseClient();
    downloader = MockApkDownloader();
    registerFallbackValue(DownloadProgress(received: 0, total: 0));
  });

  group('UpdateService.checkForUpdate', () {
    test('当前版本 = 最新版本 → UpToDate', () async {
      final sampleRelease = ReleaseInfo(
        tagName: 'v0.17.0',
        version: '0.17.0',
        name: '',
        body: '',
        publishedAt: '',
        apkDownloadUrl: '',
        apkSize: 0,
      );
      when(() => releaseClient.fetchLatestRelease())
          .thenAnswer((_) async => sampleRelease);

      final service = UpdateService(
        releaseClient: releaseClient,
        downloader: downloader,
        currentVersion: '0.17.0',
      );
      final result = await service.checkForUpdate();

      expect(result, isA<UpToDate>());
      expect((result as UpToDate).currentVersion, '0.17.0');
    });

    test('最新版本 > 当前版本 → UpdateAvailable', () async {
      final sampleRelease = ReleaseInfo(
        tagName: 'v0.18.0',
        version: '0.18.0',
        name: 'EatWise v0.18.0',
        body: '## 新功能',
        publishedAt: '',
        apkDownloadUrl: 'https://x.apk',
        apkSize: 25000000,
      );
      when(() => releaseClient.fetchLatestRelease())
          .thenAnswer((_) async => sampleRelease);

      final service = UpdateService(
        releaseClient: releaseClient,
        downloader: downloader,
        currentVersion: '0.17.0',
      );
      final result = await service.checkForUpdate();

      expect(result, isA<UpdateAvailable>());
      expect((result as UpdateAvailable).release.version, '0.18.0');
    });

    test('当前版本 > 最新版本 → UpToDate（不降级）', () async {
      final sampleRelease = ReleaseInfo(
        tagName: 'v0.17.0',
        version: '0.17.0',
        name: '',
        body: '',
        publishedAt: '',
        apkDownloadUrl: '',
        apkSize: 0,
      );
      when(() => releaseClient.fetchLatestRelease())
          .thenAnswer((_) async => sampleRelease);

      final service = UpdateService(
        releaseClient: releaseClient,
        downloader: downloader,
        currentVersion: '0.18.0',
      );
      final result = await service.checkForUpdate();

      expect(result, isA<UpToDate>());
    });

    test('releaseClient 抛 ReleaseFetchFailedException → CheckFailed', () async {
      when(() => releaseClient.fetchLatestRelease())
          .thenThrow(const ReleaseFetchFailedException('network down'));

      final service = UpdateService(
        releaseClient: releaseClient,
        downloader: downloader,
        currentVersion: '0.17.0',
      );
      final result = await service.checkForUpdate();

      expect(result, isA<CheckFailed>());
      expect((result as CheckFailed).reason, contains('network down'));
    });

    test('releaseClient 抛 ReleaseAssetNotFoundException → CheckFailed', () async {
      when(() => releaseClient.fetchLatestRelease())
          .thenThrow(const ReleaseAssetNotFoundException('no apk'));

      final service = UpdateService(
        releaseClient: releaseClient,
        downloader: downloader,
        currentVersion: '0.17.0',
      );
      final result = await service.checkForUpdate();

      expect(result, isA<CheckFailed>());
      expect((result as CheckFailed).reason, contains('no apk'));
    });
  });

  group('UpdateService.downloadApk', () {
    test('成功下载返回文件路径', () async {
      when(() => downloader.download(
              url: any(named: 'url'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => '/tmp/cache/eatwise-update.apk');

      final service = UpdateService(
        releaseClient: releaseClient,
        downloader: downloader,
        currentVersion: '0.17.0',
      );
      final path = await service.downloadApk(
        url: 'https://x.apk',
        onProgress: (_) {},
      );

      expect(path, '/tmp/cache/eatwise-update.apk');
    });

    test('downloader 抛 ApkDownloadException → 透传', () async {
      when(() => downloader.download(
              url: any(named: 'url'),
              onProgress: any(named: 'onProgress')))
          .thenThrow(const ApkDownloadException('disk full'));

      final service = UpdateService(
        releaseClient: releaseClient,
        downloader: downloader,
        currentVersion: '0.17.0',
      );
      expect(
        () => service.downloadApk(url: 'https://x.apk', onProgress: (_) {}),
        throwsA(isA<ApkDownloadException>()),
      );
    });
  });
}
