// lib/core/update/apk_downloader.dart
//
// APK 流式下载到 cache dir。
//
// 设计：
// - 用 http.Client.get 拿 Response.bytes（小文件 OK，APK ~25MB 可全量加载内存）
// - 文件名固定 eatwise-update.apk，下载前删除同名旧文件（避免残留半截文件）
// - 进度回调：基于 content-length 计算 fraction
// - 错误处理：HTTP 非 200 / 网络异常 / 写盘失败各抛 ApkDownloadException
//
// 注：构造函数注入 http.Client 便于测试（MockClient）。

import 'dart:io';

import 'package:eatwise/core/update/update_models.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ApkDownloader {
  ApkDownloader({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _apkFileName = 'eatwise-update.apk';

  /// 下载 APK 到 application cache dir。
  ///
  /// [url] APK 下载 URL（来自 ReleaseInfo.apkDownloadUrl）。
  /// [onProgress] 进度回调（每收到一段数据调用一次）。
  ///
  /// 返回下载完成的本地文件绝对路径。
  /// 抛 [ApkDownloadException]（HTTP/网络/磁盘错误）。
  Future<String> download({
    required String url,
    required void Function(DownloadProgress) onProgress,
  }) async {
    final http.Response resp;
    try {
      resp = await _client.get(Uri.parse(url));
    } on SocketException catch (e) {
      throw ApkDownloadException('网络错误：${e.message}');
    } catch (e) {
      throw ApkDownloadException('请求失败：$e');
    }

    if (resp.statusCode != 200) {
      throw ApkDownloadException(
        'HTTP 错误：${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }

    final total = int.tryParse(resp.headers['content-length'] ?? '') ??
        resp.bodyBytes.length;
    onProgress(
        DownloadProgress(received: resp.bodyBytes.length, total: total));

    // 写入 cache dir
    final Directory cacheDir;
    try {
      cacheDir = await getApplicationCacheDirectory();
    } catch (e) {
      throw ApkDownloadException('获取 cache 目录失败：$e');
    }

    final file = File('${cacheDir.path}/$_apkFileName');
    // 下载前清空旧文件（避免半截残留）
    if (await file.exists()) {
      await file.delete();
    }
    try {
      await file.writeAsBytes(resp.bodyBytes);
    } catch (e) {
      throw ApkDownloadException('写文件失败：$e');
    }

    return file.path;
  }
}
