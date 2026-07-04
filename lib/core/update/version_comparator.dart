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
