// 排版规范测试：用户可见文案中的省略号应使用单字符 …（U+2026），
// 而非 ASCII 三点 "..."。本测试扫描 lib/features 下所有 .dart 源码，
// 检测字符串字面量中的 "..."，强制改为 "…"。
//
// 注意：本测试只针对字符串字面量中的 "..."，不影响：
// - 代码注释中的 ...
// - spread operator ...[ ] 或 ...widget.x
// - 多行字符串中的代码示例
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/features 下用户可见文案不含 ASCII 三点 ...（应为 … 单字符）', () {
    final featuresDir = Directory('lib/features');
    final offenders = <String>[];
    for (final file in featuresDir.listSync(recursive: true)) {
      if (file is! File) continue;
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // 跳过注释行
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
        // 匹配字符串字面量中的 ...（'...' 或 "..." 内）
        final stringLiteralRegex =
            RegExp(r"""['"]([^'"]*\.\.\.[^'"]*)['"]""");
        if (stringLiteralRegex.hasMatch(line)) {
          offenders.add('${file.path}:${i + 1} - ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: '用户可见文案应用 … 而非 ...，发现:\n${offenders.join('\n')}');
  });
}
