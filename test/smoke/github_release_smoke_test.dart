@Tags(['smoke'])
library;

// 真实 GitHub Releases API smoke test
//
// 用真实 http.Client 调 https://api.github.com/repos/qbjsdsb/eatwise/releases/latest
// 验证：
// - 仓库可匿名访问（必须 public，否则返回 404）
// - v0.18.0 release 含 app-release.apk asset
// - release tag 解析后 version == '0.18.0'
//
// 运行：
//   flutter test test/smoke/github_release_smoke_test.dart
//
// 依赖：网络可用 + 仓库已改 public（私有仓库匿名访问会返回 404）
//
// 与 unit test 区别：
// - unit test 用 mocktail mock http.Client，永远返回 200，掩盖真实 API 行为
// - smoke test 走真实网络，能发现"私有仓库 404"、"GitHub 限流"、"API 字段变更"等问题
//
// 这是 M16 应用内自更新功能的"测试盲区"修复（P3）。
import 'dart:io';

import 'package:eatwise/core/update/github_release_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 禁用 flutter_test 的 HTTP 劫持，允许真实网络请求
  HttpOverrides.global = null;

  group('GitHub Releases API 真实访问', () {
    test('匿名访问 latest release → 解析 tag + app-release.apk URL', () async {
      final client = GitHubReleaseClient();
      final release = await client.fetchLatestRelease();

      // 基本字段非空
      expect(release.tagName, isNotEmpty,
          reason: 'tag_name 应非空（GitHub API 返回）');
      expect(release.version, isNotEmpty,
          reason: 'version 应非空（parseVersionFromTag 解析后）');
      expect(release.apkDownloadUrl, isNotEmpty,
          reason: 'APK 下载 URL 应非空');
      expect(release.apkSize, greaterThan(0),
          reason: 'APK 文件大小应 > 0');

      // app-release.apk URL 必须含 /releases/download/ 路径
      expect(release.apkDownloadUrl, contains('releases/download/'));
      expect(release.apkDownloadUrl, contains('app-release.apk'),
          reason: 'URL 必须指向 app-release.apk（不能是 app-debug.apk）');

      // tag 应是 v 开头格式（v0.18.0 或 v0.18.0-日期后缀）
      expect(release.tagName, startsWith('v'));

      // version 应是纯数字 + 点（剥离 v 前缀和日期后缀后）
      expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(release.version), true,
          reason: 'version 应是 X.Y.Z 格式，实际：${release.version}');
    });

    test('匿名下载 release asset HEAD 请求返回 200', () async {
      // 改 public 后，release 资产下载 URL 应可匿名访问
      // 这里只发 HEAD 请求验证可访问性，不实际下载 78MB APK
      final client = GitHubReleaseClient();
      final release = await client.fetchLatestRelease();

      final headResp = await HttpClient().headUrl(
        Uri.parse(release.apkDownloadUrl),
      ).then((req) => req.close());

      expect(headResp.statusCode, 200,
          reason:
              'release asset URL 应可匿名下载（HTTP 200）。'
              '若返回 404 说明仓库仍是私有，需到 GitHub Settings 改 public');
    });
  });
}
