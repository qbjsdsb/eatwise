// lib/core/update/update_service.dart
//
// 更新编排服务：组合 GitHubReleaseClient + ApkDownloader + 版本比较。
//
// 设计：
// - checkForUpdate：调 GitHubReleaseClient 拿最新 release，与 currentVersion 比较返回 UpdateCheckResult
// - downloadApk：调 ApkDownloader 下载 APK，进度透传
// - 构造函数注入 releaseClient / downloader / currentVersion，便于测试 mock
// - 错误处理：任何异常都转为 CheckFailed（不向 UI 抛，UI 只看 result 类型）

import 'package:eatwise/core/update/apk_downloader.dart';
import 'package:eatwise/core/update/github_release_client.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:eatwise/core/update/version_comparator.dart';

class UpdateService {
  UpdateService({
    required this.releaseClient,
    required this.downloader,
    required this.currentVersion,
  });

  final GitHubReleaseClient releaseClient;
  final ApkDownloader downloader;
  final String currentVersion;

  /// 检查更新。返回 [UpdateCheckResult] 之一（永不抛）。
  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      final release = await releaseClient.fetchLatestRelease();
      if (isNewer(current: currentVersion, latest: release.version)) {
        return UpdateAvailable(
          currentVersion: currentVersion,
          release: release,
        );
      }
      return UpToDate(currentVersion: currentVersion);
    } on ReleaseFetchFailedException catch (e) {
      return CheckFailed(e.toString());
    } on ReleaseAssetNotFoundException catch (e) {
      return CheckFailed(e.toString());
    } on FormatException catch (e) {
      return CheckFailed('版本号解析失败：$e');
    } catch (e) {
      return CheckFailed('未知错误：$e');
    }
  }

  /// 下载 APK。抛 [ApkDownloadException] 由 UI 层捕获提示。
  Future<String> downloadApk({
    required String url,
    required void Function(DownloadProgress) onProgress,
  }) {
    return downloader.download(url: url, onProgress: onProgress);
  }
}
