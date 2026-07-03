// date_format 工具单元测试
import 'package:eatwise/core/util/date_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatYmd', () {
    test('单位数月/日补 0', () {
      expect(formatYmd(DateTime(2026, 1, 3)), '2026-01-03');
    });

    test('两位数月/日不补 0', () {
      expect(formatYmd(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('忽略时分秒，只取年月日', () {
      expect(formatYmd(DateTime(2026, 7, 3, 23, 59, 59)), '2026-07-03');
    });
  });

  group('todayYmd', () {
    test('返回今天本地日期，格式 YYYY-MM-DD', () {
      final now = DateTime.now();
      final expected =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      expect(todayYmd(), expected);
    });

    test('长度严格为 10（4+1+2+1+2）', () {
      expect(todayYmd().length, 10);
    });
  });

  group('parseYmd', () {
    test('合法 YYYY-MM-DD 解析为午夜本地 DateTime', () {
      final dt = parseYmd('2026-07-03');
      expect(dt.year, 2026);
      expect(dt.month, 7);
      expect(dt.day, 3);
      expect(dt.hour, 0);
      expect(dt.minute, 0);
      expect(dt.second, 0);
    });

    test('单月/日也接受（DateTime.parse 容错，但格式必须匹配正则）', () {
      // 注意：formatYmd 总会补 0，但 parseYmd 只校验 \d{2} 位置，'07' '3' 不合法
      expect(() => parseYmd('2026-7-3'), throwsA(isA<FormatException>()));
    });

    test('非 YYYY-MM-DD 格式抛 FormatException', () {
      expect(() => parseYmd('2026/07/03'), throwsA(isA<FormatException>()));
      expect(() => parseYmd('07-03-2026'), throwsA(isA<FormatException>()));
      expect(() => parseYmd('20260703'), throwsA(isA<FormatException>()));
      expect(() => parseYmd(''), throwsA(isA<FormatException>()));
      expect(() => parseYmd('2026-07-03T00:00:00'),
          throwsA(isA<FormatException>()));
    });

    test('非法日期（月 13、日 32）抛 FormatException（DateTime.parse 校验）', () {
      expect(() => parseYmd('2026-13-01'), throwsA(isA<FormatException>()));
      expect(() => parseYmd('2026-02-31'), throwsA(isA<FormatException>()));
    });
  });

  group('往返一致性', () {
    test('formatYmd → parseYmd → 同一日期', () {
      final original = DateTime(2026, 7, 3);
      final formatted = formatYmd(original);
      final parsed = parseYmd(formatted);
      expect(parsed.year, original.year);
      expect(parsed.month, original.month);
      expect(parsed.day, original.day);
    });
  });
}
