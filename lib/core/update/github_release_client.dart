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
      final assetName = asset['name'];
      if (assetName == 'app-release.apk') {
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
