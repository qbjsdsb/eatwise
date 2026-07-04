import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 验证 Android 图标资源完整性（M15 图标重设计配套测试）
void main() {
  group('图标资源完整性 (M15)', () {
    const androidResDir = 'android/app/src/main/res';

    test('colors.xml 含 ic_launcher_background 颜色定义', () {
      final file = File('$androidResDir/values/colors.xml');
      final content = file.readAsStringSync();
      expect(
        content,
        contains('<color name="ic_launcher_background">#FF6E40</color>'),
        reason: '图标背景颜色应抽到 colors.xml 而非硬编码在 drawable',
      );
    });

    test('colors.xml 含 ic_launcher_foreground 颜色定义', () {
      final file = File('$androidResDir/values/colors.xml');
      final content = file.readAsStringSync();
      expect(
        content,
        contains('<color name="ic_launcher_foreground">#FFFFFF</color>'),
        reason: '图标前景颜色应抽到 colors.xml',
      );
    });

    test('ic_launcher_background.xml 引用 @color/ic_launcher_background 而非硬编码', () {
      final file = File('$androidResDir/drawable/ic_launcher_background.xml');
      final content = file.readAsStringSync();
      expect(
        content,
        contains('android:color="@color/ic_launcher_background"'),
        reason: '背景 drawable 应引用 colors.xml 资源',
      );
      expect(
        content,
        isNot(contains('#FF6E40')),
        reason: '不应再硬编码颜色值',
      );
    });
  });
}
