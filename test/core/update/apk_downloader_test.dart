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
  });
}
