import 'dart:convert';

import 'package:eatwise/core/update/github_release_client.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late MockHttpClient client;
  late GitHubReleaseClient releaseClient;

  setUp(() {
    client = MockHttpClient();
    releaseClient = GitHubReleaseClient(client: client);
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  group('GitHubReleaseClient.fetchLatestRelease', () {
    test('成功解析 release', () async {
      // 模拟 GitHub API 返回的 JSON
      final json = jsonEncode({
        'tag_name': 'v0.18.0',
        'name': 'EatWise v0.18.0',
        'body': '## 新功能\n- 应用内更新',
        'published_at': '2026-07-05T10:00:00Z',
        'assets': [
          {
            'name': 'app-release.apk',
            'browser_download_url':
                'https://github.com/qbjsdsb/eatwise/releases/download/v0.18.0/app-release.apk',
            'size': 25000000,
            'content_type': 'application/vnd.android.package-archive',
          },
          {
            'name': 'app-debug.apk',
            'browser_download_url':
                'https://github.com/qbjsdsb/eatwise/releases/download/v0.18.0/app-debug.apk',
            'size': 30000000,
            'content_type': 'application/vnd.android.package-archive',
          },
        ],
      });
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(json, 200,
              headers: {'content-type': 'application/json'}));

      final release = await releaseClient.fetchLatestRelease();

      expect(release.tagName, 'v0.18.0');
      expect(release.version, '0.18.0');
      expect(release.name, 'EatWise v0.18.0');
      expect(release.body, contains('应用内更新'));
      // 必须选 app-release.apk 而非 app-debug.apk
      expect(release.apkDownloadUrl,
          'https://github.com/qbjsdsb/eatwise/releases/download/v0.18.0/app-release.apk');
      expect(release.apkSize, 25000000);
    });

    test('无 app-release.apk asset 时抛 ReleaseAssetNotFoundException', () async {
      final json = jsonEncode({
        'tag_name': 'v0.18.0',
        'assets': [
          {
            'name': 'app-debug.apk',
            'browser_download_url': 'https://x/debug.apk',
            'size': 0
          }
        ],
      });
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(json, 200));

      expect(
        () => releaseClient.fetchLatestRelease(),
        throwsA(isA<ReleaseAssetNotFoundException>()),
      );
    });

    test('HTTP 403 抛 ReleaseFetchFailedException 含状态码', () async {
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('rate limit', 403));

      expect(
        () => releaseClient.fetchLatestRelease(),
        throwsA(isA<ReleaseFetchFailedException>()
            .having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('HTTP 404 抛 ReleaseFetchFailedException 含状态码', () async {
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('not found', 404));

      expect(
        () => releaseClient.fetchLatestRelease(),
        throwsA(isA<ReleaseFetchFailedException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('JSON 缺 tag_name 字段抛 FormatException', () async {
      final json = jsonEncode({'name': 'no tag'});
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(json, 200));

      expect(
        () => releaseClient.fetchLatestRelease(),
        throwsFormatException,
      );
    });

    test('网络异常抛 ReleaseFetchFailedException', () async {
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenThrow(Exception('network down'));

      expect(
        () => releaseClient.fetchLatestRelease(),
        throwsA(isA<ReleaseFetchFailedException>()),
      );
    });
  });
}
