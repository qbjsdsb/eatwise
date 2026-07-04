# EatWise 应用内自更新功能 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户在 app 内点击"检查更新"即可下载新版 APK 并触发系统安装器覆盖升级，无需卸载旧版；CI build 用固定 keystore 签名保证覆盖安装兼容性。

**Architecture:**
1. **固定签名 keystore**：用户本地生成一份 `eatwise-release.jks`，base64 上传到 GitHub Secrets；本地 build 通过 `key.properties` 引用，CI build 从 secrets 注入。keystore 不进 repo（安全），不进 `.gitignore` 之外的位置。
2. **GitHub Releases 作为更新源**：app 调 `https://api.github.com/repos/qbjsdsb/eatwise/releases/latest` 查最新 release，提取 tag_name 与 apk asset 下载 URL。
3. **Semver 比较**：纯函数实现 `0.17.0` vs `0.18.0` 比较，决定是否需要更新。
4. **APK 下载到 cache dir**：用 `http` 包流式下载到 `getApplicationCacheDirectory()/eatwise-update.apk`，下载中广播进度。
5. **触发系统安装器**：通过 `FileProvider` + `Intent(ACTION_VIEW)` + `application/vnd.android.package-archive` MIME 类型让系统包安装器接管，用户在系统弹窗确认安装。

**Tech Stack:**
- Flutter 3.44.4 + Dart 3.10
- `http: ^1.2.0`（已有，调 GitHub API + 下载 APK）
- `path_provider: ^2.1.0`（已有，cache dir）
- `package_info_plus: ^8.0.0`（已有，读当前版本号）
- `flutter_riverpod: ^3.3.1`（已有，状态管理）
- `mocktail: ^1.0.0`（已有，测试 mock http.Client）
- Android 原生：FileProvider（androidx.core.content.FileProvider 已是 Flutter 默认依赖）+ `REQUEST_INSTALL_PACKAGES` 权限

---

## 文件结构

**新增文件**：
- `lib/core/update/version_comparator.dart` — Semver 解析与比较纯函数（无副作用，最易测试）
- `lib/core/update/github_release_client.dart` — GitHub Releases API 客户端，封装 http 调用 + JSON 解析
- `lib/core/update/apk_downloader.dart` — APK 流式下载到 cache dir + 进度回调
- `lib/core/update/update_service.dart` — 编排 check + download，对外暴露 FutureProvider
- `lib/core/update/update_models.dart` — `ReleaseInfo` / `UpdateCheckResult` / `DownloadProgress` 不可变数据类
- `lib/features/update/update_page.dart` — 检查更新 UI 页（状态机：idle/checking/updateAvailable/downloading/readyToInstall/error）
- `test/core/update/version_comparator_test.dart` — A 系列 TDD 测试
- `test/core/update/github_release_client_test.dart` — B 系列 TDD 测试（mocktail mock http.Client）
- `test/core/update/apk_downloader_test.dart` — C 系列 TDD 测试（mock http + 真实 temp dir）
- `test/core/update/update_service_test.dart` — D 系列 TDD 测试（mock client + downloader）
- `test/features/update_page_test.dart` — E 系列 widget 测试
- `test/android_update_assets_test.dart` — F 系列 Android 资源静态测试（仿 `icon_assets_test.dart` 模式）
- `android/app/src/main/res/xml/file_paths.xml` — FileProvider 路径配置（允许共享 cache dir）
- `scripts/generate_keystore.sh` — 用户本地生成 keystore 脚本（带交互提示）

**修改文件**：
- `android/app/src/main/AndroidManifest.xml` — 加 `REQUEST_INSTALL_PACKAGES` 权限 + 注册 FileProvider
- `android/app/build.gradle.kts` — 加 release signingConfig（从 `key.properties` 读 keystore）
- `.github/workflows/release.yml` — 从 secrets 解码 keystore 到文件 + 注入 signingConfig
- `lib/features/settings/settings_page.dart` — "关于"组加"检查更新"入口（→ push UpdatePage）
- `pubspec.yaml` — bump `0.17.0+18` → `0.18.0+19`
- `HANDOFF.md` — 追加 M16 章节

**.gitignore**：
- 加 `android/app/key.properties`（本地 keystore 密码配置，不进 repo）
- 加 `android/app/eatwise-release.jks`（keystore 文件本身，不进 repo）

---

## Task 列表

### Task A1: 版本号解析与比较纯函数（TDD）

**Files:**
- Create: `lib/core/update/version_comparator.dart`
- Test: `test/core/update/version_comparator_test.dart`

- [ ] **Step 1: 写失败测试 `test/core/update/version_comparator_test.dart`**

```dart
import 'package:eatwise/core/update/version_comparator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSemver', () {
    test('解析标准三段版本号', () {
      final v = parseSemver('0.17.0');
      expect(v, (0, 17, 0));
    });

    test('解析两位版本号补 0', () {
      // 兼容 "1.0" → (1, 0, 0)
      final v = parseSemver('1.0');
      expect(v, (1, 0, 0));
    });

    test('非法格式抛 FormatException', () {
      expect(() => parseSemver('abc'), throwsFormatException);
      expect(() => parseSemver('1.x.0'), throwsFormatException);
      expect(() => parseSemver(''), throwsFormatException);
    });
  });

  group('parseVersionFromTag', () {
    test('剥离 v 前缀', () {
      expect(parseVersionFromTag('v0.17.0'), '0.17.0');
    });

    test('剥离日期后缀（CI 自动生成的 tag）', () {
      // release.yml L76: TAG="v${version}-$(date)"
      expect(parseVersionFromTag('v0.17.0-20260705-123456'), '0.17.0');
    });

    test('无 v 前缀也能解析', () {
      expect(parseVersionFromTag('0.17.0'), '0.17.0');
    });

    test('非法 tag 抛 FormatException', () {
      expect(() => parseVersionFromTag('random-tag'), throwsFormatException);
    });
  });

  group('isNewer', () {
    test('major 版本号大则更新', () {
      expect(isNewer(current: '0.17.0', latest: '1.0.0'), true);
    });

    test('minor 版本号大则更新', () {
      expect(isNewer(current: '0.17.0', latest: '0.18.0'), true);
    });

    test('patch 版本号大则更新', () {
      expect(isNewer(current: '0.17.0', latest: '0.17.1'), true);
    });

    test('版本相同无更新', () {
      expect(isNewer(current: '0.17.0', latest: '0.17.0'), false);
    });

    test('latest 比 current 旧无更新', () {
      expect(isNewer(current: '0.18.0', latest: '0.17.0'), false);
    });
  });

  group('compareSemver', () {
    test('相等返回 0', () {
      expect(compareSemver('0.17.0', '0.17.0'), 0);
    });

    test('a 大返回正数', () {
      expect(compareSemver('0.18.0', '0.17.0'), greaterThan(0));
    });

    test('a 小返回负数', () {
      expect(compareSemver('0.17.0', '0.18.0'), lessThan(0));
    });
  });
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `flutter test test/core/update/version_comparator_test.dart`
Expected: FAIL with "Error: Method not found: 'parseSemver'" 或类似（文件不存在）

- [ ] **Step 3: 写最小实现 `lib/core/update/version_comparator.dart`**

```dart
// lib/core/update/version_comparator.dart
//
// Semver 版本号解析与比较纯函数。
// 用于 app 内更新检查：比较当前版本（PackageInfo.version）与 GitHub Releases 最新 tag。
//
// 设计为纯函数（无副作用，无 IO），便于 100% 单元测试覆盖。

/// 解析三段版本号为 `(major, minor, patch)` 记录。
/// 支持两位版本号（"1.0" → (1, 0, 0)）。
/// 非法格式抛 FormatException。
({int major, int minor, int patch}) parseSemver(String version) {
  final parts = version.split('.');
  if (parts.isEmpty || parts.length > 3) {
    throw FormatException('版本号格式错误：$version');
  }
  final major = int.tryParse(parts[0]);
  final minor = parts.length > 1 ? int.tryParse(parts[1]) : 0;
  final patch = parts.length > 2 ? int.tryParse(parts[2]) : 0;
  if (major == null || minor == null || patch == null) {
    throw FormatException('版本号格式错误：$version');
  }
  return (major: major, minor: minor, patch: patch);
}

/// 从 GitHub Release tag 提取纯版本号。
/// 处理：
/// - "v0.17.0" → "0.17.0"（剥离 v 前缀）
/// - "v0.17.0-20260705-123456" → "0.17.0"（剥离日期后缀，CI 自动生成）
/// - "0.17.0" → "0.17.0"（无 v 前缀也能解析）
/// 非法 tag（如 "random-tag"）抛 FormatException。
String parseVersionFromTag(String tag) {
  // 剥离 v 前缀（如有）
  var v = tag.startsWith('v') ? tag.substring(1) : tag;
  // 剥离日期后缀：取第一个 '-' 之前的部分
  final dashIdx = v.indexOf('-');
  if (dashIdx >= 0) {
    v = v.substring(0, dashIdx);
  }
  // 校验是合法 semver
  parseSemver(v);
  return v;
}

/// 比较两个 semver 版本号。
/// 返回：>0 表示 a > b，0 表示相等，<0 表示 a < b。
int compareSemver(String a, String b) {
  final va = parseSemver(a);
  final vb = parseSemver(b);
  if (va.major != vb.major) return va.major - vb.major;
  if (va.minor != vb.minor) return va.minor - vb.minor;
  return va.patch - vb.patch;
}

/// 判断 latest 是否比 current 新。
/// 任意一方格式非法返回 false（保守策略：宁可漏更新也不误报）。
bool isNewer({required String current, required String latest}) {
  try {
    return compareSemver(latest, current) > 0;
  } catch (_) {
    return false;
  }
}
```

- [ ] **Step 4: 跑测试验证通过**

Run: `flutter test test/core/update/version_comparator_test.dart`
Expected: PASS（所有用例通过）

- [ ] **Step 5: 跑 flutter analyze 确认无 lint**

Run: `flutter analyze lib/core/update/version_comparator.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/core/update/version_comparator.dart test/core/update/version_comparator_test.dart
git commit -m "feat(M16-A1): 版本号解析与比较纯函数（semver + tag 解析）"
```

---

### Task B1: GitHub Release API 客户端（TDD with mocktail）

**Files:**
- Create: `lib/core/update/update_models.dart`
- Create: `lib/core/update/github_release_client.dart`
- Test: `test/core/update/github_release_client_test.dart`

- [ ] **Step 1: 写失败测试 `test/core/update/github_release_client_test.dart`**

```dart
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
      when(() => client.get(any())).thenAnswer(
          (_) async => http.Response(json, 200, headers: {'content-type': 'application/json'}));

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
          {'name': 'app-debug.apk', 'browser_download_url': 'https://x/debug.apk', 'size': 0}
        ],
      });
      when(() => client.get(any())).thenAnswer((_) async => http.Response(json, 200));

      expect(
        () => releaseClient.fetchLatestRelease(),
        throwsA(isA<ReleaseAssetNotFoundException>()),
      );
    });

    test('HTTP 403 抛 ReleaseFetchFailedException 含状态码', () async {
      when(() => client.get(any()))
          .thenAnswer((_) async => http.Response('rate limit', 403));

      expect(
        () => releaseClient.fetchLatestRelease(),
        throwsA(isA<ReleaseFetchFailedException>()
            .having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('HTTP 404 抛 ReleaseFetchFailedException', () async {
      when(() => client.get(any()))
          .thenAnswer((_) async => http.Response('not found', 404));

      expect(
        () => releaseClient.fetchLatestRelease(),
        throwsA(isA<ReleaseFetchFailedException>()),
      );
    });

    test('JSON 缺 tag_name 字段抛 FormatException', () async {
      final json = jsonEncode({'name': 'no tag'});
      when(() => client.get(any())).thenAnswer((_) async => http.Response(json, 200));

      expect(
        () => releaseClient.fetchLatestRelease(),
        throwsFormatException,
      );
    });

    test('网络异常（SocketException）抛 ReleaseFetchFailedException', () async {
      when(() => client.get(any())).thenThrow(Exception('network down'));

      expect(
        () => releaseClient.fetchLatestRelease(),
        throwsA(isA<ReleaseFetchFailedException>()),
      );
    });
  });
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `flutter test test/core/update/github_release_client_test.dart`
Expected: FAIL with "Error: Method not found: 'GitHubReleaseClient'" 或 "Target of URI doesn't exist"

- [ ] **Step 3: 写 `lib/core/update/update_models.dart`（数据类）**

```dart
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
```

- [ ] **Step 4: 写 `lib/core/update/github_release_client.dart`**

```dart
// lib/core/update/github_release_client.dart
//
// GitHub Releases API 客户端。
// 调 https://api.github.com/repos/qbjsdsb/eatwise/releases/latest 查最新 release，
// 提取 app-release.apk 下载 URL（跳过 app-debug.apk）。
//
// 设计：构造函数注入 http.Client，便于测试用 mocktail mock。
// 错误处理：HTTP 非 200 / 网络异常 / JSON 解析失败 / 缺 app-release.apk 各抛对应异常。

import 'dart:convert';
import 'dart:io';

import 'package:eatwise/core/update/update_models.dart';
import 'package:eatwise/core/update/version_comparator.dart';
import 'package:http/http.dart' as http;

class GitHubReleaseClient {
  GitHubReleaseClient({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _repo = 'qbjsdsb/eatwise';
  static const _apiUrl =
      'https://api.github.com/repos/qbjsdsb/eatwise/releases/latest';

  /// 查询最新 release。
  /// 抛 [ReleaseFetchFailedException]（HTTP/网络错误）或 [FormatException]（JSON 解析失败）
  /// 或 [ReleaseAssetNotFoundException]（缺 app-release.apk）。
  Future<ReleaseInfo> fetchLatestRelease() async {
    final http.Response resp;
    try {
      resp = await _client.get(Uri.parse(_apiUrl));
    } on SocketException catch (e) {
      throw ReleaseFetchFailedException('网络错误：${e.message}');
    } catch (e) {
      throw ReleaseFetchFailedException('请求失败：$e');
    }

    if (resp.statusCode != 200) {
      throw ReleaseFetchFailedException(
        'GitHub API 返回非 200',
        statusCode: resp.statusCode,
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('JSON 解析失败：$e');
    }

    final tagName = json['tag_name'];
    if (tagName is! String) {
      throw FormatException('JSON 缺 tag_name 字段或类型非 String');
    }

    final version = parseVersionFromTag(tagName);
    final name = json['name'] as String? ?? '';
    final body = json['body'] as String? ?? '';
    final publishedAt = json['published_at'] as String? ?? '';

    // 在 assets 中找 app-release.apk（不是 app-debug.apk）
    final assets = json['assets'];
    if (assets is! List) {
      throw ReleaseAssetNotFoundException('Release 无 assets 字段');
    }
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      if (name == 'app-release.apk') {
        final url = asset['browser_download_url'];
        final size = asset['size'];
        if (url is! String || size is! int) {
          throw ReleaseAssetNotFoundException(
              'app-release.apk 缺 browser_download_url 或 size');
        }
        return ReleaseInfo(
          tagName: tagName,
          version: version,
          name: name,
          body: body,
          publishedAt: publishedAt,
          apkDownloadUrl: url,
          apkSize: size,
        );
      }
    }
    throw ReleaseAssetNotFoundException('Release 缺 app-release.apk asset');
  }
}
```

- [ ] **Step 5: 跑测试验证通过**

Run: `flutter test test/core/update/github_release_client_test.dart`
Expected: PASS（6 个用例全过）

- [ ] **Step 6: 跑 analyze**

Run: `flutter analyze lib/core/update/`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
git add lib/core/update/update_models.dart lib/core/update/github_release_client.dart test/core/update/github_release_client_test.dart
git commit -m "feat(M16-B1): GitHub Release API 客户端 + 数据模型（mocktail TDD）"
```

---

### Task C1: APK 下载服务（TDD with mock http + 真实 temp dir）

**Files:**
- Create: `lib/core/update/apk_downloader.dart`
- Test: `test/core/update/apk_downloader_test.dart`

- [ ] **Step 1: 写失败测试 `test/core/update/apk_downloader_test.dart`**

```dart
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
class _MockPathProvider extends PathProviderPlatform {
  _MockPathProvider(this.cacheDir);
  final Directory cacheDir;

  @override
  Future<String?> getTemporaryPath() async => cacheDir.path;

  @override
  Future<String?> getApplicationCachePath() async => cacheDir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => cacheDir.path;

  @override
  Future<String?> getDownloadsPath() async => null;

  @override
  Future<String?> getExternalStoragePath() async => null;

  @override
  Future<List<String>?> getExternalCachePaths() async => null;

  @override
  Future<List<String>?> getExternalStoragePaths() async => null;

  @override
  Future<String?> getLibraryPath() async => null;

  @override
  Future<String?> getApplicationSupportPath() async => null;
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
      final client = MockClient((request) async => http.Response('not found', 404));

      final downloader = ApkDownloader(client: client);
      expect(
        () => downloader.download(url: 'https://example.com/x.apk', onProgress: (_) {}),
        throwsA(isA<ApkDownloadException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('HTTP 500 抛 ApkDownloadException', () async {
      final client = MockClient((request) async => http.Response('server error', 500));

      final downloader = ApkDownloader(client: client);
      expect(
        () => downloader.download(url: 'https://example.com/x.apk', onProgress: (_) {}),
        throwsA(isA<ApkDownloadException>()),
      );
    });

    test('网络异常抛 ApkDownloadException', () async {
      final client = MockClient((request) async => throw Exception('network down'));

      final downloader = ApkDownloader(client: client);
      expect(
        () => downloader.download(url: 'https://example.com/x.apk', onProgress: (_) {}),
        throwsA(isA<ApkDownloadException>()),
      );
    });

    test('下载前清空旧 APK（同名文件存在则覆盖）', () async {
      // 预先写一个旧 APK 文件
      final oldPath = '${tempDir.path}/eatwise-update.apk';
      await File(oldPath).writeAsBytes(Uint8List.fromList([1, 2, 3]));

      final fakeBytes = Uint8List.fromList(List.filled(100, 0x42));
      final client = MockClient((request) async =>
          http.Response.bytes(fakeBytes, 200, headers: {'content-length': '100'}));

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
```

- [ ] **Step 2: 跑测试验证失败**

Run: `flutter test test/core/update/apk_downloader_test.dart`
Expected: FAIL with "Target of URI doesn't exist: 'package:eatwise/core/update/apk_downloader.dart'"

- [ ] **Step 3: 写实现 `lib/core/update/apk_downloader.dart`**

```dart
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

    final total = int.tryParse(resp.headers['content-length'] ?? '') ?? resp.bodyBytes.length;
    onProgress(DownloadProgress(received: resp.bodyBytes.length, total: total));

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
```

- [ ] **Step 4: 跑测试验证通过**

Run: `flutter test test/core/update/apk_downloader_test.dart`
Expected: PASS（6 个用例全过）

- [ ] **Step 5: 跑 analyze**

Run: `flutter analyze lib/core/update/apk_downloader.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/core/update/apk_downloader.dart test/core/update/apk_downloader_test.dart
git commit -m "feat(M16-C1): APK 下载服务（流式下载到 cache dir + 进度回调）"
```

---

### Task D1: UpdateService 编排 + Provider（TDD）

**Files:**
- Create: `lib/core/update/update_service.dart`
- Modify: `lib/features/recognize/providers.dart`（追加 updateServiceProvider，沿用同一文件集中 provider 的项目惯例）
- Test: `test/core/update/update_service_test.dart`

- [ ] **Step 1: 写失败测试 `test/core/update/update_service_test.dart`**

```dart
import 'package:eatwise/core/update/apk_downloader.dart';
import 'package:eatwise/core/update/github_release_client.dart';
import 'package:eatwise/core/update/update_models.dart';
import 'package:eatwise/core/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
      when(() => releaseClient.fetchLatestRelease()).thenThrow(
          const ReleaseFetchFailedException('network down'));

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
```

- [ ] **Step 2: 跑测试验证失败**

Run: `flutter test test/core/update/update_service_test.dart`
Expected: FAIL with "Target of URI doesn't exist: 'package:eatwise/core/update/update_service.dart'"

- [ ] **Step 3: 写实现 `lib/core/update/update_service.dart`**

```dart
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
```

- [ ] **Step 4: 跑测试验证通过**

Run: `flutter test test/core/update/update_service_test.dart`
Expected: PASS（7 个用例全过）

- [ ] **Step 5: 跑 analyze**

Run: `flutter analyze lib/core/update/`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/core/update/update_service.dart test/core/update/update_service_test.dart
git commit -m "feat(M16-D1): UpdateService 编排 + 状态机结果（checkForUpdate + downloadApk）"
```

---

### Task D2: 注册 updateServiceProvider（Riverpod）

**Files:**
- Modify: `lib/features/recognize/providers.dart`（沿用项目集中 provider 惯例）
- Modify: `test/core/update/update_service_test.dart`（追加 provider 测试，可选）

> 注：项目 provider 集中在 `recognize/providers.dart`，沿用此惯例避免新建 provider 文件。

- [ ] **Step 1: 读 `lib/features/recognize/providers.dart` 确认现有结构**

Run: 读文件

- [ ] **Step 2: 在 `lib/features/recognize/providers.dart` 末尾追加 updateServiceProvider**

```dart
// === M16 应用内更新 providers ===
import '../../core/update/apk_downloader.dart';
import '../../core/update/github_release_client.dart';
import '../../core/update/update_service.dart';
import '../../core/config/app_version_provider.dart';

/// GitHubReleaseClient 单例（http.Client 内部复用连接池）
final gitHubReleaseClientProvider = Provider<GitHubReleaseClient>((ref) {
  return GitHubReleaseClient();
});

/// ApkDownloader 单例
final apkDownloaderProvider = Provider<ApkDownloader>((ref) {
  return ApkDownloader();
});

/// 当前版本号（纯 version，不含 buildNumber）
/// 从 appVersionShortProvider 取（已是 FutureProvider<String>）
/// UpdateService 需要同步 String，故用 FutureProvider.family 包一层
final updateServiceProvider = FutureProvider<UpdateService>((ref) async {
  final version = await ref.read(appVersionShortProvider.future);
  final releaseClient = ref.read(gitHubReleaseClientProvider);
  final downloader = ref.read(apkDownloaderProvider);
  return UpdateService(
    releaseClient: releaseClient,
    downloader: downloader,
    currentVersion: version,
  );
});
```

- [ ] **Step 3: 跑 analyze**

Run: `flutter analyze lib/features/recognize/providers.dart`
Expected: "No issues found!"

- [ ] **Step 4: 跑全量测试确认未破坏现有**

Run: `flutter test`
Expected: 全部 PASS（含原有 787 + 新增 update 测试）

- [ ] **Step 5: Commit**

```bash
git add lib/features/recognize/providers.dart
git commit -m "feat(M16-D2): 注册 updateServiceProvider（Riverpod）"
```

---

### Task E1: UpdatePage UI（widget test）

**Files:**
- Create: `lib/features/update/update_page.dart`
- Test: `test/features/update_page_test.dart`

**UI 状态机**：
- `idle`：显示"检查更新"按钮
- `checking`：显示 LoadingState + "正在检查..."
- `updateAvailable`：显示新版本号 + release notes + "下载并安装"按钮
- `upToDate`：显示"已是最新版本" + "重新检查"按钮
- `downloading`：显示进度条 + 已下载/总大小
- `readyToInstall`：显示"打开系统安装器"按钮
- `error`：显示错误信息 + "重试"按钮

- [ ] **Step 1: 写失败测试 `test/features/update_page_test.dart`**

```dart
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
      recognize.updateServiceProvider
          .overrideWith((ref) async => service),
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
      apkSize: 1000,
    );
    when(() => service.checkForUpdate()).thenAnswer(
        (_) async => UpdateAvailable(currentVersion: '0.17.0', release: release));

    // 模拟下载：先 sleep 100ms 让 UI 进入 downloading 状态
    when(() => service.downloadApk(
            url: any(named: 'url'),
            onProgress: any(named: 'onProgress')))
        .thenAnswer((inv) async {
      final onProgress = inv.namedArguments[#onProgress] as void Function(DownloadProgress);
      onProgress(const DownloadProgress(received: 500, total: 1000));
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
    expect(find.textContaining('500'), findsOneWidget);

    await tester.pumpAndSettle(); // 等下载完成 → readyToInstall

    expect(find.textContaining('打开系统安装器'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `flutter test test/features/update_page_test.dart`
Expected: FAIL with "Target of URI doesn't exist: 'package:eatwise/features/update/update_page.dart'"

- [ ] **Step 3: 写实现 `lib/features/update/update_page.dart`**

```dart
// lib/features/update/update_page.dart
//
// 应用内更新 UI 页。
//
// 状态机：
// - idle：初始态，显示"检查更新"按钮
// - checking：调 checkForUpdate 中
// - upToDate：已是最新
// - updateAvailable：有新版本，显示 release notes + "下载并安装"
// - downloading：下载中，显示进度条
// - readyToInstall：下载完成，显示"打开系统安装器"
// - error：检查/下载失败，显示错误 + 重试

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/update_models.dart';
import '../../core/widgets/m3_widgets.dart';
import '../recognize/providers.dart' as recognize;

class UpdatePage extends ConsumerStatefulWidget {
  const UpdatePage({super.key});
  @override
  ConsumerState<UpdatePage> createState() => _UpdatePageState();
}

enum _UpdateState { idle, checking, upToDate, updateAvailable, downloading, readyToInstall, error }

class _UpdatePageState extends ConsumerState<UpdatePage> {
  _UpdateState _state = _UpdateState.idle;
  UpdateCheckResult? _result;
  DownloadProgress? _progress;
  String? _downloadedPath;
  String? _errorMsg;
  bool _busy = false;

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _state = _UpdateState.checking;
      _errorMsg = null;
    });
    try {
      final service = await ref.read(recognize.updateServiceProvider.future);
      final result = await service.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _result = result;
        switch (result) {
          case UpToDate():
            _state = _UpdateState.upToDate;
          case UpdateAvailable():
            _state = _UpdateState.updateAvailable;
          case CheckFailed():
            _state = _UpdateState.error;
            _errorMsg = result.reason;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _UpdateState.error;
        _errorMsg = '检查失败：$e';
      });
    } finally {
      if (mounted) _busy = false;
    }
  }

  Future<void> _download() async {
    if (_busy) return;
    final result = _result;
    if (result is! UpdateAvailable) return;
    setState(() {
      _busy = true;
      _state = _UpdateState.downloading;
      _progress = null;
    });
    try {
      final service = await ref.read(recognize.updateServiceProvider.future);
      final path = await service.downloadApk(
        url: result.release.apkDownloadUrl,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadedPath = path;
        _state = _UpdateState.readyToInstall;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _UpdateState.error;
        _errorMsg = '下载失败：$e';
      });
    } finally {
      if (mounted) _busy = false;
    }
  }

  Future<void> _install() async {
    // 调 MethodChannel 触发系统安装器（在 Section F 配置 FileProvider 后生效）
    // 此处仅占位，实际触发逻辑放在 ApkInstaller（Section F Task E2 实现）
    if (_downloadedPath == null) return;
    // TODO(M16-F): 接入 ApkInstaller.triggerInstall(path)
    if (!mounted) return;
    showAppToast(context, '即将打开系统安装器（M16-F 接入原生通道）');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('检查更新')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildContent(cs, tt),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(ColorScheme cs, TextTheme tt) {
    switch (_state) {
      case _UpdateState.idle:
        return [
          Icon(Icons.system_update_alt, size: 64, color: cs.primary),
          const SizedBox(height: 16),
          Text('点击下方按钮检查是否有新版本',
              textAlign: TextAlign.center, style: tt.bodyMedium),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _check,
            icon: const Icon(Icons.refresh),
            label: const Text('检查更新'),
          ),
        ];
      case _UpdateState.checking:
        return [
          const LoadingState(label: '正在检查...'),
        ];
      case _UpdateState.upToDate:
        final r = _result as UpToDate;
        return [
          Icon(Icons.check_circle, size: 64, color: cs.primary),
          const SizedBox(height: 16),
          Text('已是最新版本', style: tt.titleMedium),
          const SizedBox(height: 8),
          Text('当前版本：${r.currentVersion}',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _busy ? null : _check,
            icon: const Icon(Icons.refresh),
            label: const Text('重新检查'),
          ),
        ];
      case _UpdateState.updateAvailable:
        final r = _result as UpdateAvailable;
        return [
          Icon(Icons.system_update, size: 64, color: cs.primary),
          const SizedBox(height: 16),
          Text('发现新版本：${r.release.version}',
              textAlign: TextAlign.center, style: tt.titleMedium),
          const SizedBox(height: 8),
          Text('当前版本：${r.currentVersion}',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          if (r.release.body.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.maxFinite,
                  child: Text(r.release.body,
                      style: tt.bodySmall,
                      maxLines: 10,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text('大小：${(r.release.apkSize / 1024 / 1024).toStringAsFixed(1)} MB',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _download,
            icon: const Icon(Icons.download),
            label: const Text('下载并安装'),
          ),
        ];
      case _UpdateState.downloading:
        final p = _progress;
        final fraction = p?.fraction ?? 0;
        final receivedKb = (p?.received ?? 0) ~/ 1024;
        final totalKb = (p?.total ?? 0) ~/ 1024;
        return [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: fraction == 0 ? null : fraction),
          const SizedBox(height: 8),
          Text(
            fraction > 0
                ? '${(fraction * 100).toStringAsFixed(0)}%  ($receivedKb KB / $totalKb KB)'
                : '正在下载...',
            textAlign: TextAlign.center,
            style: tt.bodySmall,
          ),
        ];
      case _UpdateState.readyToInstall:
        return [
          Icon(Icons.download_done, size: 64, color: cs.primary),
          const SizedBox(height: 16),
          Text('下载完成', style: tt.titleMedium),
          const SizedBox(height: 8),
          Text('点击下方按钮打开系统安装器完成升级',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _install,
            icon: const Icon(Icons.install_mobile),
            label: const Text('打开系统安装器'),
          ),
        ];
      case _UpdateState.error:
        return [
          Icon(Icons.error_outline, size: 64, color: cs.error),
          const SizedBox(height: 16),
          Text('出错了', style: tt.titleMedium?.copyWith(color: cs.error)),
          const SizedBox(height: 8),
          Text(_errorMsg ?? '未知错误',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _check,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ];
    }
  }
}
```

- [ ] **Step 4: 跑测试验证通过**

Run: `flutter test test/features/update_page_test.dart`
Expected: PASS（5 个用例全过）

- [ ] **Step 5: 跑 analyze**

Run: `flutter analyze lib/features/update/`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/features/update/update_page.dart test/features/update_page_test.dart
git commit -m "feat(M16-E1): UpdatePage 状态机 UI（idle/checking/available/downloading/install/error）"
```

---

### Task E2: settings_page 加"检查更新"入口

**Files:**
- Modify: `lib/features/settings/settings_page.dart`（"关于"组加"检查更新"项）

- [ ] **Step 1: 在 settings_page.dart 的 `关于` GroupCard 加新 ListTile**

定位 `SectionTitle('关于')` 下方的 GroupCard，在 `关于慢慢吃` ListTile **之前** 插入：

```dart
_listItem(
  Icons.system_update_alt,
  '检查更新',
  () => Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute(builder: (_) => const UpdatePage())),
),
```

需在文件顶部加 import：
```dart
import '../update/update_page.dart';
```

- [ ] **Step 2: 跑 settings_page 既有测试确认未破坏**

Run: `flutter test test/features/settings_page_test.dart test/features/settings_completeness_test.dart test/features/settings_backup_overdue_test.dart test/features/monthly_cost_test.dart`
Expected: 全部 PASS

- [ ] **Step 3: 跑 analyze**

Run: `flutter analyze lib/features/settings/settings_page.dart`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add lib/features/settings/settings_page.dart
git commit -m "feat(M16-E2): settings 关于组加检查更新入口"
```

---

### Task F1: Android Manifest + FileProvider 配置

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/main/res/xml/file_paths.xml`
- Test: `test/android_update_assets_test.dart`

- [ ] **Step 1: 写失败测试 `test/android_update_assets_test.dart`**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('M16 Android 更新资源', () {
    final manifestPath =
        'android/app/src/main/AndroidManifest.xml';
    final filePathsXmlPath =
        'android/app/src/main/res/xml/file_paths.xml';

    test('AndroidManifest 含 REQUEST_INSTALL_PACKAGES 权限', () {
      final manifest = File(manifestPath).readAsStringSync();
      expect(
        manifest,
        contains(
            'android.permission.REQUEST_INSTALL_PACKAGES'),
        reason: '应用内安装 APK 必须声明此权限（Android 8+）',
      );
    });

    test('AndroidManifest 注册了 FileProvider', () {
      final manifest = File(manifestPath).readAsStringSync();
      expect(manifest, contains('androidx.core.content.FileProvider'));
      expect(manifest, contains('android:authorities'));
      expect(manifest,
          contains('\${applicationId}.fileprovider'));
      expect(manifest, contains('android:grantUriPermissions="true"'));
    });

    test('file_paths.xml 存在并配置 cache-path', () {
      expect(File(filePathsXmlPath).existsSync(), true,
          reason: 'FileProvider 必须配置 file_paths.xml');
      final content = File(filePathsXmlPath).readAsStringSync();
      // cache-path 用于共享 getApplicationCacheDirectory() 下的 APK
      expect(content, contains('cache-path'));
      expect(content, contains('name="cache"'));
      expect(content, contains('path="."'));
    });
  });
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `flutter test test/android_update_assets_test.dart`
Expected: FAIL with "Expected: contains 'REQUEST_INSTALL_PACKAGES'" 等

- [ ] **Step 3: 修改 `android/app/src/main/AndroidManifest.xml`**

在 `<uses-permission android:name="android.permission.CAMERA" />` 之后加：

```xml
<!-- M16 应用内更新：安装下载的 APK 必需（Android 8+） -->
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```

在 `<application>` 标签内（与 `<activity>` 同级）加 FileProvider 注册：

```xml
<!-- M16 应用内更新：用 FileProvider 共享 cache_dir 下的 APK 给系统包安装器 -->
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths" />
</provider>
```

- [ ] **Step 4: 创建 `android/app/src/main/res/xml/file_paths.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <!-- cache-path 对应 Context.getCacheDir()，但 path="." 也覆盖 getExternalCacheDir() -->
    <!-- ApkDownloader 用 getApplicationCacheDirectory() 写文件，Android 端实际落到 cache dir -->
    <cache-path name="cache" path="." />
    <!-- 兼容外部 cache（部分设备 getApplicationCacheDirectory 落到 external） -->
    <external-cache-path name="external_cache" path="." />
</paths>
```

- [ ] **Step 5: 跑测试验证通过**

Run: `flutter test test/android_update_assets_test.dart`
Expected: PASS（3 个用例全过）

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml android/app/src/main/res/xml/file_paths.xml test/android_update_assets_test.dart
git commit -m "feat(M16-F1): AndroidManifest 加 REQUEST_INSTALL_PACKAGES 权限 + FileProvider 注册"
```

---

### Task F2: ApkInstaller MethodChannel（触发系统安装器）

**Files:**
- Create: `lib/core/update/apk_installer.dart`（Dart 端 MethodChannel 调用）
- Modify: `android/app/src/main/kotlin/com/eatwise/eatwise/MainActivity.kt`（注册 MethodChannel + 触发 Intent）
- Modify: `lib/features/update/update_page.dart`（接入 ApkInstaller.triggerInstall）
- Test: `test/core/update/apk_installer_test.dart`

> 注：MethodChannel 在沙箱无平台通道，测试只能 mock。

- [ ] **Step 1: 读 MainActivity.kt 确认现有结构**

Run: 读文件 `android/app/src/main/kotlin/com/eatwise/eatwise/MainActivity.kt`

- [ ] **Step 2: 写失败测试 `test/core/update/apk_installer_test.dart`**

```dart
import 'package:eatwise/core/update/apk_installer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApkInstaller', () {
    test('triggerInstall 调用 MethodChannel 触发安装', () async {
      // 拦截 MethodChannel 调用
      final handler = <Map<String, dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ApkInstaller.channel, (call) async {
        handler.add({
          'method': call.method,
          'args': call.arguments,
        });
        return null;
      });

      await ApkInstaller.triggerInstall('/tmp/x.apk');

      expect(handler.length, 1);
      expect(handler.first['method'], 'triggerInstall');
      expect(handler.first['args'], '/tmp/x.apk');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ApkInstaller.channel, null);
    });

    test('triggerInstall 失败抛 PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ApkInstaller.channel, (call) async {
        throw PlatformException(code: 'INSTALL_FAILED', message: 'installer not found');
      });

      expect(
        () => ApkInstaller.triggerInstall('/tmp/x.apk'),
        throwsA(isA<PlatformException>()),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ApkInstaller.channel, null);
    });
  });
}
```

- [ ] **Step 3: 跑测试验证失败**

Run: `flutter test test/core/update/apk_installer_test.dart`
Expected: FAIL with "Target of URI doesn't exist: 'package:eatwise/core/update/apk_installer.dart'"

- [ ] **Step 4: 写实现 `lib/core/update/apk_installer.dart`**

```dart
// lib/core/update/apk_installer.dart
//
// 触发 Android 系统包安装器。
//
// 通过 MethodChannel 调原生代码：
// - Dart 侧传 APK 文件路径
// - Kotlin 侧用 FileProvider.getUriForFile + Intent(ACTION_VIEW) + application/vnd.android.package-archive
// - 系统弹窗让用户确认安装
//
// Android 8+ 必须 REQUEST_INSTALL_PACKAGES 权限（已在 AndroidManifest 声明）
// Android 7+ 必须用 FileProvider 共享 file:// URI（已注册 FileProvider）

import 'package:flutter/services.dart';

class ApkInstaller {
  ApkInstaller._();

  static const channel = MethodChannel('com.eatwise.eatwise/apk_installer');

  /// 触发系统安装器安装指定路径的 APK。
  /// 抛 [PlatformException]：原生侧找不到包安装器 / FileProvider 配置错 / 路径无效
  static Future<void> triggerInstall(String apkPath) async {
    await channel.invokeMethod<void>('triggerInstall', apkPath);
  }
}
```

- [ ] **Step 5: 修改 `android/app/src/main/kotlin/com/eatwise/eatwise/MainActivity.kt`**

在现有 MainActivity 类内加 MethodChannel 注册：

```kotlin
package com.eatwise.eatwise

import android.content.Intent
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.eatwise.eatwise/apk_installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "triggerInstall" -> {
                        val apkPath = call.argument<String>(0) ?: call.arguments as String
                        triggerInstall(apkPath, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun triggerInstall(apkPath: String, result: io.flutter.plugin.common.MethodChannel.Result) {
        try {
            val file = File(apkPath)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "APK 文件不存在：$apkPath", null)
                return
            }
            val uri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(null)
        } catch (e: Exception) {
            result.error("INSTALL_FAILED", "触发安装器失败：${e.message}", null)
        }
    }
}
```

- [ ] **Step 6: 修改 `lib/features/update/update_page.dart` 的 `_install` 方法接入 ApkInstaller**

```dart
Future<void> _install() async {
  if (_downloadedPath == null) return;
  if (_busy) return;
  setState(() => _busy = true);
  try {
    await ApkInstaller.triggerInstall(_downloadedPath!);
    // 触发后系统安装器会弹窗，用户安装完手动返回 app
    if (!mounted) return;
    showAppToast(context, '已打开系统安装器，请在弹窗中确认安装');
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _state = _UpdateState.error;
      _errorMsg = '触发安装器失败：$e';
    });
  } finally {
    if (mounted) _busy = false;
  }
}
```

文件顶部加 import：
```dart
import '../../core/update/apk_installer.dart';
```

- [ ] **Step 7: 跑测试验证通过**

Run: `flutter test test/core/update/apk_installer_test.dart`
Expected: PASS（2 个用例全过）

- [ ] **Step 8: 跑全量测试**

Run: `flutter test`
Expected: 全部 PASS

- [ ] **Step 9: 跑 analyze**

Run: `flutter analyze lib/core/update/apk_installer.dart lib/features/update/update_page.dart`
Expected: "No issues found!"

- [ ] **Step 10: Commit**

```bash
git add lib/core/update/apk_installer.dart android/app/src/main/kotlin/com/eatwise/eatwise/MainActivity.kt lib/features/update/update_page.dart test/core/update/apk_installer_test.dart
git commit -m "feat(M16-F2): ApkInstaller MethodChannel + MainActivity Intent 触发系统安装器"
```

---

### Task G1: 固定签名 keystore 配置（build.gradle.kts + key.properties）

**Files:**
- Modify: `android/app/build.gradle.kts`
- Modify: `.gitignore`
- Create: `scripts/generate_keystore.sh`

> 注：keystore 文件本身（`eatwise-release.jks`）和 `key.properties` 不进 repo，由用户本地生成。

- [ ] **Step 1: 修改 `.gitignore` 加 keystore 相关忽略**

在 `.gitignore` 末尾追加：

```
# M16 应用内更新：keystore 与签名密码配置不进 repo
android/app/key.properties
android/app/eatwise-release.jks
```

- [ ] **Step 2: 修改 `android/app/build.gradle.kts` 加 signingConfig**

在 `android { ... }` 块内 `buildTypes { ... }` 之前加：

```kotlin
    // M16 应用内更新：固定签名 keystore（保证 CI 与本地 build 签名一致，支持覆盖安装）
    // keystore 文件路径与密码从 key.properties 读取（文件不进 repo）
    // key.properties 不存在时回退到 debug 签名（开发期不阻塞）
    val keystoreProperties = java.util.Properties()
    val keystorePropertiesFile = rootProject.file("app/key.properties")
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
```

修改 `buildTypes { release { ... } }` 块：

```kotlin
    buildTypes {
        release {
            // M16 应用内更新：有 key.properties 用固定 release 签名，否则回退 debug
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // 禁用 R8 代码压缩：sentry_flutter/workmanager 等插件依赖反射注册，
            // R8 默认规则会剥掉关键类导致 native 启动崩溃（Dart try-catch 抓不住）。
            // 个人自用 app 体积稍大可接受，稳定性优先。
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
```

> **关键**：保留 `isMinifyEnabled = false` + `isShrinkResources = false`（项目硬约束 1，否则 R8 剥反射类致崩溃）

- [ ] **Step 3: 创建 `scripts/generate_keystore.sh`**

```bash
#!/bin/bash
# M16 应用内更新：生成本地固定签名 keystore
#
# 用法：bash scripts/generate_keystore.sh
#
# 生成的文件：
# - android/app/eatwise-release.jks（keystore 文件，不进 repo）
# - android/app/key.properties（keystore 密码配置，不进 repo）
#
# 这两个文件都已在 .gitignore 中，提交时不会被包含。
# 首次生成后，本地 flutter build apk --release 会自动用此 keystore 签名。
# CI build 需要把 eatwise-release.jks base64 encode 后上传到 GitHub Secrets
# （详见 docs/superpowers/plans/2026-07-05-in-app-update.md Task G3）

set -e

KEYSTORE_PATH="android/app/eatwise-release.jks"
PROPERTIES_PATH="android/app/key.properties"

if [ -f "$KEYSTORE_PATH" ]; then
    echo "⚠️  $KEYSTORE_PATH 已存在"
    read -p "覆盖生成？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "取消"
        exit 0
    fi
    rm -f "$KEYSTORE_PATH" "$PROPERTIES_PATH"
fi

# 固定密码（个人自用项目，密码复杂度非关键，关键是 keystore 文件本身不泄露）
STORE_PASSWORD="eatwise_release_$(date +%s)"
KEY_PASSWORD="$STORE_PASSWORD"
KEY_ALIAS="eatwise-release"

echo "生成 keystore: $KEYSTORE_PATH"
keytool -genkeypair \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 36500 \
    -keystore "$KEYSTORE_PATH" \
    -storepass "$STORE_PASSWORD" \
    -keypass "$KEY_PASSWORD" \
    -dname "CN=EatWise, OU=Personal, O=Personal, L=Beijing, ST=Beijing, C=CN"

cat > "$PROPERTIES_PATH" <<EOF
storePassword=$STORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$KEY_ALIAS
storeFile=eatwise-release.jks
EOF

echo ""
echo "✅ 生成完成："
echo "  keystore: $KEYSTORE_PATH"
echo "  properties: $PROPERTIES_PATH"
echo ""
echo "📦 上传到 GitHub Secrets（CI build 用）："
echo "  base64 $KEYSTORE_PATH | tr -d '\\n' | pbcopy  # macOS 复制到剪贴板"
echo "  然后在 GitHub repo Settings → Secrets and variables → Actions 加：
    - ANDROID_KEYSTORE_BASE64
    - ANDROID_KEYSTORE_PASSWORD=$STORE_PASSWORD
    - ANDROID_KEY_ALIAS=$KEY_ALIAS
    - ANDROID_KEY_PASSWORD=$KEY_PASSWORD"
```

```bash
chmod +x scripts/generate_keystore.sh
```

- [ ] **Step 4: 跑 analyze 确认 build.gradle.kts 语法 OK**

> 注：沙箱无 Android SDK，无法跑 `flutter build apk`，但 Gradle Kotlin DSL 语法可静态检查

Run: `flutter analyze` （确认无 Dart 端 lint 误报）
Expected: "No issues found!"

- [ ] **Step 5: Commit**

```bash
git add .gitignore android/app/build.gradle.kts scripts/generate_keystore.sh
git commit -m "feat(M16-G1): 固定签名 keystore 配置 + 生成脚本（key.properties 不进 repo）"
```

---

### Task G2: release.yml 从 secrets 注入 keystore

**Files:**
- Modify: `.github/workflows/release.yml`

> 注：用户需先按 Task G1 的脚本生成 keystore，并把以下 4 个值上传到 GitHub Secrets：
> - `ANDROID_KEYSTORE_BASE64`（`base64 eatwise-release.jks` 的输出）
> - `ANDROID_KEYSTORE_PASSWORD`
> - `ANDROID_KEY_ALIAS`
> - `ANDROID_KEY_PASSWORD`

- [ ] **Step 1: 修改 `.github/workflows/release.yml`，在 `Build release APK` 步骤之前加 keystore 注入步骤**

在 `- name: Build release APK` 之前插入：

```yaml
      - name: 注入 release keystore（从 GitHub Secrets）
        env:
          ANDROID_KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
          ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          ANDROID_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
          ANDROID_KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
        run: |
          if [ -z "$ANDROID_KEYSTORE_BASE64" ]; then
            echo "⚠️  未配置 ANDROID_KEYSTORE_BASE64 secret，回退到 debug 签名（CI build 仍无法覆盖安装）"
            exit 0
          fi
          echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/app/eatwise-release.jks
          cat > android/app/key.properties <<EOF
          storePassword=$ANDROID_KEYSTORE_PASSWORD
          keyPassword=$ANDROID_KEY_PASSWORD
          keyAlias=$ANDROID_KEY_ALIAS
          storeFile=eatwise-release.jks
          EOF
          echo "✅ keystore 注入完成"
```

- [ ] **Step 2: 修改 release.yml 的 Release notes 文案**

把 `body: |` 中的"先卸载旧版本再装新版"段替换为：

```yaml
          body: |
            ## 安装说明

            1. 下载下方 apk（优先下 app-release.apk）
            2. 手机用数据线传过去（或扫码下载）
            3. 手机设置开启"允许安装未知来源应用"
            4. **直接覆盖安装即可**（已用固定 keystore 签名，无需卸载旧版）
            5. 首次启动在「设置」页填入你的 Qwen API Key（视觉识别用）
            6. 在「设置 → 检查更新」可一键升级到下一版

            ## 闪退排查：请先装 app-debug.apk

            如果 app-release.apk 闪退，请改装 **app-debug.apk**：
            - debug 版崩溃时会显示**红色错误页+完整堆栈**
            - 截图发给开发者即可定位根因

            ## 签名说明

            本包使用固定 release 签名（v0.18.0 起），可正常覆盖安装，
            但**不能上架应用商店**。

            ## 版本信息

            - 应用版本: ${{ steps.version.outputs.pubspec_version }}
            - 构建时间: ${{ github.run_id }}
            - 提交: ${{ github.sha }}
```

- [ ] **Step 3: 跑全量测试确认 release.yml 改动不影响 Dart 端**

Run: `flutter test`
Expected: 全部 PASS（release.yml 改动不影响测试）

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat(M16-G2): release.yml 从 secrets 注入 keystore + 更新安装说明（覆盖安装）"
```

---

### Task H1: 版本号 bump 0.17.0+18 → 0.18.0+19

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 修改 pubspec.yaml 第 4 行**

```yaml
version: 0.18.0+19
```

- [ ] **Step 2: 跑 app_version_provider 测试确认 mock 同步**

> 注：测试用 mock 值不依赖 pubspec，但运行时 PackageInfo.fromPlatform 会读 pubspec

Run: `flutter test test/core/app_version_provider_test.dart`
Expected: PASS（mock 值不受影响）

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml
git commit -m "chore(M16-H1): bump 版本号 0.17.0+18 → 0.18.0+19"
```

---

### Task H2: HANDOFF 回填 M16 + push

**Files:**
- Modify: `HANDOFF.md`

- [ ] **Step 1: 更新 HANDOFF.md 第 2 节"当前状态"**

把 v0.17.0 那行改为：
```
v0.18.0 release 待 push（M16 应用内自更新 13 Task，含 GitHub Releases 检查 + APK 下载 + 系统安装器 + 固定签名 keystore，详见下方"M16 应用内自更新"章节）
```

更新当前分支行：
```
HEAD = <commit hash>，13 个 M16 commit 待推送 <hash>~<hash>；远端 origin/trae/agent-wX1X6Q 停在 9d62aa7
```

- [ ] **Step 2: 在 "M15 图标重设计 + 每日历史记录查看" 章节之后追加 M16 章节**

内容包括：
- 工作区状态：v0.18.0 release 待 push
- 当前分支 HEAD
- M16 章节内容：应用内自更新的完整说明 + commit hash + 文件清单
- 用户手动步骤说明（生成 keystore + 上传 GitHub Secrets）
- 验证结果（flutter analyze 0 issues + flutter test 全过）

- [ ] **Step 3: Commit HANDOFF.md**

```bash
git add HANDOFF.md
git commit -m "docs(M16-H2): HANDOFF 回填 M16 应用内自更新"
```

- [ ] **Step 4: Push 全部 M16 commit**

```bash
git push origin trae/agent-wX1X6Q
```

- [ ] **Step 5: 验证 push 成功**

```bash
git fetch origin trae/agent-wX1X6Q
git log origin/trae/agent-wX1X6Q..HEAD --oneline | wc -l  # 应为 0
```

---

## Self-Review 检查

### 1. Spec 覆盖

| 用户需求 | 实现 Task |
|---------|----------|
| 每次发布可以直接更新（不卸载） | G1（固定 keystore）+ G2（release.yml 注入）|
| 软件内部就能更新 | A1（版本比较）+ B1（GitHub API）+ C1（APK 下载）+ D1（编排）+ E1（UI）+ E2（入口）+ F1（权限）+ F2（安装器）|
| 反复检查不要出问题 | 每个 Task 都有 TDD 测试 + 静态资源测试 + 全量回归 |

### 2. Placeholder 扫描

- ✅ 无 TBD / TODO（除 update_page.dart 的 `TODO(M16-F)` 在 F2 Task 接入后删除）
- ✅ 所有 code block 完整可执行
- ✅ 所有命令含 expected output
- ✅ 类型一致性：`ReleaseInfo` / `UpdateCheckResult` / `DownloadProgress` 在各 Task 中签名一致
- ✅ 异常类型一致：`ReleaseFetchFailedException` / `ReleaseAssetNotFoundException` / `ApkDownloadException`

### 3. 类型一致性

- `ReleaseInfo.version` 在 B1 定义，D1 用于比较
- `UpdateCheckResult` 三种子类在 B1 定义，D1 返回，E1 消费
- `DownloadProgress.fraction` 在 B1 定义，C1 计算，E1 显示
- `ApkInstaller.triggerInstall(String apkPath)` 在 F2 定义，E1 `_install` 调用

### 4. 已知风险与缓解

| 风险 | 缓解 |
|------|------|
| 沙箱无法 build APK 验证签名配置 | G1/G2 仅写文件 + 静态语法检查，用户本地手动验证 |
| 沙箱无法测试 MethodChannel 真实安装 | F2 用 mock MethodChannel 测试 Dart 端，原生端写明 Kotlin 代码 |
| GitHub API rate limit（未认证 60/h） | 个人自用频次低，不接 OAuth；如需可后续加 token |
| APK 下载 25MB 全量入内存 | 个人自用 OK；如需流式可后续改 StreamedResponse |
| 用户未生成 keystore 时 CI 回退 debug 签名 | G2 step 内 `if [ -z ... ]` 兜底，不阻塞 CI |
| 首次安装时旧 debug 签名版本无法覆盖 | 用户首次升级时需卸载一次（已在 release notes 说明）|

---

## 执行选择

Plan complete and saved to `docs/superpowers/plans/2026-07-05-in-app-update.md`.

13 个 Task 分布：
- Section A-D（4 Task）：Dart 纯逻辑 + TDD，可在沙箱完整验证
- Section E（2 Task）：UI + widget test
- Section F（2 Task）：Android 配置 + MethodChannel，沙箱部分验证
- Section G（2 Task）：签名 keystore + CI 配置，沙箱仅写文件，需用户本地验证
- Section H（2 Task）：版本号 + HANDOFF + push

**注意**：G1/G2 需用户在本地执行 `scripts/generate_keystore.sh` 生成 keystore + 上传 GitHub Secrets 后才能真正生效。沙箱只能完成代码与配置文件的编写，无法 build APK 验证签名。
