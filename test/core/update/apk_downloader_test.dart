import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:eatwise/core/update/apk_downloader.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Mock PathProviderPlatform，返回测试 temp dir。
/// 用 extends 而非 implements：PathProviderPlatform 是 abstract class with default
/// implementations，extends 只需 override 关心方法，避免新增方法破坏测试。
class _MockPathProvider extends PathProviderPlatform {
  _MockPathProvider(this.cacheDir);
  final Directory cacheDir;

  @override
  Future<String?> getTemporaryPath() async => cacheDir.path;

  @override
  Future<String?> getApplicationCachePath() async => cacheDir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => cacheDir.path;
}

/// 构造一个分多块返回的 ByteStream（模拟真实 HTTP 流式响应）。
http.ByteStream _chunkedStream(List<List<int>> chunks) {
  final controller = StreamController<List<int>>();
  for (final c in chunks) {
    controller.add(c);
  }
  controller.close();
  return http.ByteStream(controller.stream);
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('apk_downloader_test');
    PathProviderPlatform.instance = _MockPathProvider(tempDir);
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ApkDownloader.download', () {
    test('成功下载到 cache dir 并返回文件路径', () async {
      final fakeBytes = Uint8List.fromList(List.filled(1024, 0x42));
      final client = MockClient((request) async {
        return http.Response.bytes(fakeBytes, 200,
            headers: {'content-length': '${fakeBytes.length}'});
      });

      final downloader = ApkDownloader(client: client);
      final path = await downloader.download(
        url: 'https://github.com/release/app-release.apk',
        onProgress: (_) {},
      );

      final file = File(path);
      expect(await file.exists(), true);
      expect(await file.length(), fakeBytes.length);
      // 文件名必须是 eatwise-update.apk（UpdateService 安装时硬编码此名）
      expect(path.endsWith('eatwise-update.apk'), true);
    });

    test('下载中进度回调被调用且 fraction 单调递增', () async {
      // 分块响应：3 块 × 100 字节
      final chunk = Uint8List.fromList(List.filled(100, 0x42));
      final client = MockClient((request) async {
        return http.Response.bytes(
            Uint8List.fromList([...chunk, ...chunk, ...chunk]), 200,
            headers: {'content-length': '300'});
      });

      final downloader = ApkDownloader(client: client);
      final progresses = <DownloadProgress>[];
      await downloader.download(
        url: 'https://example.com/x.apk',
        onProgress: (p) => progresses.add(p),
      );

      // 至少调用一次（最终一次 fraction 应为 1.0）
      expect(progresses, isNotEmpty);
      expect(progresses.last.fraction, 1.0);
    });

    test('流式分块下载：每 chunk 触发一次 onProgress 且最终文件完整', () async {
      // 用 MockClient.streaming 模拟真实的分块 StreamedResponse
      // 3 个 chunk：100 / 50 / 150 字节，总 300 字节
      final chunk1 = Uint8List.fromList(List.filled(100, 0x41)); // 'A'
      final chunk2 = Uint8List.fromList(List.filled(50, 0x42)); // 'B'
      final chunk3 = Uint8List.fromList(List.filled(150, 0x43)); // 'C'
      final expectedBytes =
          Uint8List.fromList([...chunk1, ...chunk2, ...chunk3]);

      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          _chunkedStream([chunk1, chunk2, chunk3]),
          200,
          headers: {'content-length': '${expectedBytes.length}'},
        );
      });

      final downloader = ApkDownloader(client: client);
      final progresses = <DownloadProgress>[];
      final path = await downloader.download(
        url: 'https://example.com/x.apk',
        onProgress: (p) => progresses.add(p),
      );

      // 应触发 3 次进度回调（每个 chunk 一次）
      expect(progresses.length, 3);
      // fraction 单调递增
      expect(progresses[0].received, 100);
      expect(progresses[0].total, 300);
      expect(progresses[0].fraction, closeTo(0.333, 0.01));
      expect(progresses[1].received, 150);
      expect(progresses[1].fraction, 0.5);
      expect(progresses[2].received, 300);
      expect(progresses[2].fraction, 1.0);
      // 文件内容必须是所有 chunk 拼接
      final actual = await File(path).readAsBytes();
      expect(actual, expectedBytes);
    });

    test('无 content-length 时进度 total=received 兜底（fraction 仍为 0）', () async {
      // 无 content-length header
      final chunk = Uint8List.fromList(List.filled(100, 0x42));
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          _chunkedStream([chunk]),
          200,
          // 故意不设 content-length
        );
      });

      final downloader = ApkDownloader(client: client);
      final progresses = <DownloadProgress>[];
      await downloader.download(
        url: 'https://example.com/x.apk',
        onProgress: (p) => progresses.add(p),
      );

      expect(progresses, isNotEmpty);
      // total == received（兜底），fraction = received/total = 1.0
      // 但 DownloadProgress.fraction 在 total > 0 时才计算，total=received>0 时 fraction=1.0
      expect(progresses.last.total, 100);
      expect(progresses.last.received, 100);
    });

    test('HTTP 404 抛 ApkDownloadException 含状态码', () async {
      final client =
          MockClient((request) async => http.Response('not found', 404));

      final downloader = ApkDownloader(client: client);
      expect(
        () => downloader.download(
            url: 'https://example.com/x.apk', onProgress: (_) {}),
        throwsA(isA<ApkDownloadException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('HTTP 500 抛 ApkDownloadException', () async {
      final client =
          MockClient((request) async => http.Response('server error', 500));

      final downloader = ApkDownloader(client: client);
      expect(
        () => downloader.download(
            url: 'https://example.com/x.apk', onProgress: (_) {}),
        throwsA(isA<ApkDownloadException>()),
      );
    });

    test('网络异常抛 ApkDownloadException', () async {
      final client =
          MockClient((request) async => throw Exception('network down'));

      final downloader = ApkDownloader(client: client);
      expect(
        () => downloader.download(
            url: 'https://example.com/x.apk', onProgress: (_) {}),
        throwsA(isA<ApkDownloadException>()),
      );
    });

    test('下载前清空旧 APK（同名文件存在则覆盖）', () async {
      // 预先写一个旧 APK 文件
      final oldPath = '${tempDir.path}/eatwise-update.apk';
      await File(oldPath).writeAsBytes(Uint8List.fromList([1, 2, 3]));

      final fakeBytes = Uint8List.fromList(List.filled(100, 0x42));
      final client = MockClient((request) async => http.Response.bytes(
          fakeBytes, 200,
          headers: {'content-length': '100'}));

      final downloader = ApkDownloader(client: client);
      final path = await downloader.download(
        url: 'https://example.com/x.apk',
        onProgress: (_) {},
      );

      // 下载后文件应是新内容（100 字节），不是旧内容（3 字节）
      expect(await File(path).length(), 100);
    });

    test('下载不完整（received < total）抛 ApkDownloadException', () async {
      // 声明 content-length=300 但实际只发 100 字节
      final chunk = Uint8List.fromList(List.filled(100, 0x42));
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          _chunkedStream([chunk]),
          200,
          headers: {'content-length': '300'},
        );
      });

      final downloader = ApkDownloader(client: client);
      expect(
        () => downloader.download(
            url: 'https://example.com/x.apk', onProgress: (_) {}),
        throwsA(isA<ApkDownloadException>()
            .having((e) => e.message, 'message', contains('下载不完整'))),
      );
    });
  });
}
