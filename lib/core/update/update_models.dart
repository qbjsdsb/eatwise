// lib/core/update/update_models.dart
//
// 更新功能的数据模型。全部不可变。

/// GitHub Release 信息（已提取 APK 下载 URL）。
class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.apkDownloadUrl,
    required this.apkSize,
  });

  /// GitHub Release 的完整 tag（如 "v0.18.0" 或 "v0.18.0-20260705-123456"）
  final String tagName;

  /// 从 tag 提取的纯版本号（如 "0.18.0"）
  final String version;

  /// Release 标题
  final String name;

  /// Release notes（Markdown）
  final String body;

  /// 发布时间（ISO 8601）
  final String publishedAt;

  /// app-release.apk 下载 URL
  final String apkDownloadUrl;

  /// APK 文件大小（字节）
  final int apkSize;
}

/// 更新检查结果。
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// 当前已是最新版本。
class UpToDate extends UpdateCheckResult {
  const UpToDate({required this.currentVersion});
  final String currentVersion;
}

/// 有新版本可用。
class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable({
    required this.currentVersion,
    required this.release,
  });
  final String currentVersion;
  final ReleaseInfo release;
}

/// 检查失败（网络/解析/HTTP 错误）。
class CheckFailed extends UpdateCheckResult {
  const CheckFailed(this.reason);
  final String reason;
}

/// APK 下载进度（0.0 ~ 1.0）。
class DownloadProgress {
  const DownloadProgress({required this.received, required this.total});
  final int received;
  final int total;

  /// 0.0 ~ 1.0，total 未知时为 0
  double get fraction => total > 0 ? received / total : 0;
}

/// 自定义异常类型。
class ReleaseFetchFailedException implements Exception {
  const ReleaseFetchFailedException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() =>
      'ReleaseFetchFailedException: $message${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}

class ReleaseAssetNotFoundException implements Exception {
  const ReleaseAssetNotFoundException(this.message);
  final String message;
  @override
  String toString() => 'ReleaseAssetNotFoundException: $message';
}

class ApkDownloadException implements Exception {
  const ApkDownloadException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() =>
      'ApkDownloadException: $message${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}
