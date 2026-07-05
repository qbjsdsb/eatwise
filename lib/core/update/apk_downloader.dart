// lib/core/update/apk_downloader.dart
//
// APK 流式下载到 cache dir。
//
// 设计：
// - 用 http.Client.send(StreamedRequest) 拿 ByteStream，边收 chunk 边写盘
//   避免 78MB APK 全量加载内存致低端机 OOM
// - 每个 chunk 触发 onProgress 回调，UI 进度条渐进刷新（非 0%→100% 跳变）
// - 文件名固定 eatwise-update.apk，下载前删除同名旧文件（避免半截残留）
// - 错误处理：HTTP 非 200 / 网络异常 / 写盘失败 / 超时各抛 ApkDownloadException
//
// 注：构造函数注入 http.Client 便于测试（MockClient）。
// 测试用 MockClient.send 返回固定 ByteStream 验证流式逻辑。

import 'dart:async';
import 'dart:io';

import 'package:eatwise/core/update/update_models.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ApkDownloader {
  ApkDownloader({http.Client? client, Duration? timeout})
      : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 120);

  final http.Client _client;
  final Duration _timeout;

  static const _apkFileName = 'eatwise-update.apk';

  /// 下载 APK 到 application cache dir。
  ///
  /// [url] APK 下载 URL（来自 ReleaseInfo.apkDownloadUrl）。
  /// [onProgress] 进度回调（每收到一段数据调用一次，含累计已下载/总大小）。
  ///
  /// 返回下载完成的本地文件绝对路径。
  /// 抛 [ApkDownloadException]（HTTP/网络/磁盘/超时错误）。
  Future<String> download({
    required String url,
    required void Function(DownloadProgress) onProgress,
  }) async {
    final http.StreamedResponse streamed;
    try {
      // 用 send 拿 streamed response，避免全量加载到内存
      final request = http.Request('GET', Uri.parse(url));
      streamed = await _client.send(request).timeout(_timeout);
    } on SocketException catch (e) {
      throw ApkDownloadException('网络错误：${e.message}');
    } on TimeoutException {
      throw ApkDownloadException(
          '连接超时（${_timeout.inSeconds}s）—— 请检查网络后重试');
    } catch (e) {
      throw ApkDownloadException('请求失败：$e');
    }

    if (streamed.statusCode != 200) {
      // 释放 stream 避免连接泄漏
      await streamed.stream.drain<void>();
      throw ApkDownloadException(
        'HTTP 错误：${streamed.statusCode}',
        statusCode: streamed.statusCode,
      );
    }

    final total = int.tryParse(streamed.headers['content-length'] ?? '') ?? 0;

    // 写入 cache dir
    final Directory cacheDir;
    try {
      cacheDir = await getApplicationCacheDirectory();
    } catch (e) {
      // 释放 stream
      await streamed.stream.drain<void>();
      throw ApkDownloadException('获取 cache 目录失败：$e');
    }

    final file = File('${cacheDir.path}/$_apkFileName');
    // 下载前清空旧文件（避免半截残留）
    if (await file.exists()) {
      await file.delete();
    }

    // 流式写盘：每收到一个 chunk 写入文件 + 触发进度回调
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        // total=0（无 content-length）时用 received 兜底，fraction 仍为 0 让 UI 显示 indeterminate
        onProgress(DownloadProgress(
          received: received,
          total: total > 0 ? total : received,
        ));
      }
      await sink.flush();
    } on SocketException catch (e) {
      throw ApkDownloadException('下载中断：${e.message}');
    } catch (e) {
      throw ApkDownloadException('写文件失败：$e');
    } finally {
      await sink.close();
    }

    // 校验下载完整性（仅 content-length 已知时）
    if (total > 0 && received != total) {
      throw ApkDownloadException(
          '下载不完整：$received / $total bytes（可能网络中断）');
    }

    return file.path;
  }
}
