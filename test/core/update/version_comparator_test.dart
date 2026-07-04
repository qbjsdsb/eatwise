import 'package:eatwise/core/update/version_comparator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSemver', () {
    test('解析标准三段版本号', () {
      final v = parseSemver('0.17.0');
      expect(v, (major: 0, minor: 17, patch: 0));
    });

    test('解析两位版本号补 0', () {
      // 兼容 "1.0" → (1, 0, 0)
      final v = parseSemver('1.0');
      expect(v, (major: 1, minor: 0, patch: 0));
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
