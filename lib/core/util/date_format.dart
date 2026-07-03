// 日期格式化工具：YMD 字符串 <-> DateTime 互转
// 所有 'YYYY-MM-DD' 格式统一走这里，避免各处重复 padLeft 模板与
// month/day 顺序、padLeft 长度等小坑。本地时区，不取 UTC（避免跨日偏移）。

/// 今日 'YYYY-MM-DD'（本地时区）
String todayYmd() => formatYmd(DateTime.now());

/// DateTime → 'YYYY-MM-DD'（本地时区）
String formatYmd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 'YYYY-MM-DD' → DateTime（午夜本地时区）
/// 严格校验：① 格式必须匹配 ^\d{4}-\d{2}-\d{2}$ ② 月 ∈ [1,12]、日 ∈ [1,31]
/// ③ 日历合法（如 2026-02-30 会抛 FormatException，避免 Dart DateTime 构造器
/// 静默溢出 2026-03-02 致数据错误）。比裸 DateTime.parse 更早暴露脏数据。
DateTime parseYmd(String s) {
  final m = _ymdRegex.firstMatch(s);
  if (m == null) {
    throw FormatException('Invalid YMD format: "$s" (expected YYYY-MM-DD)');
  }
  final year = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  if (month < 1 || month > 12) {
    throw FormatException('Invalid month in "$s": $month');
  }
  if (day < 1 || day > 31) {
    throw FormatException('Invalid day in "$s": $day');
  }
  // DateTime 构造器会归一化溢出（如 2026-02-30 → 2026-03-02），用往返校验拦截
  final dt = DateTime(year, month, day);
  if (dt.year != year || dt.month != month || dt.day != day) {
    throw FormatException('Invalid calendar date: "$s"');
  }
  return dt;
}

final _ymdRegex = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
