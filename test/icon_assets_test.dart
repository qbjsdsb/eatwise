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

    test('ic_launcher_foreground.xml 含餐叉+餐刀 path（M15 重设计）', () {
      final file = File('$androidResDir/drawable/ic_launcher_foreground.xml');
      final content = file.readAsStringSync();
      // 餐叉+餐刀几何图形的 path（M15 重设计后应有）
      expect(
        content,
        contains('android:pathData="M38,24'),
        reason: '餐叉 path 应从 x=38 开始（M15 几何布局）',
      );
      expect(
        content,
        contains('android:pathData="M62,24'),
        reason: '餐刀 path 应从 x=62 开始（M15 几何布局）',
      );
      expect(
        content,
        contains('android:fillColor="@color/ic_launcher_foreground"'),
        reason: '前景应引用 @color/ic_launcher_foreground',
      );
      // 旧的"碗+蒸汽"应被移除（注释里 'steam' 也不应有）
      expect(
        content,
        isNot(contains('steam')),
        reason: '旧的蒸汽注释应被移除',
      );
    });

    test('mipmap-anydpi-v26/ic_launcher_round.xml 存在且引用正确', () {
      final file = File('$androidResDir/mipmap-anydpi-v26/ic_launcher_round.xml');
      expect(file.existsSync(), true, reason: '圆角 adaptive-icon 应存在');
      final content = file.readAsStringSync();
      expect(content,
          contains('<background android:drawable="@drawable/ic_launcher_background" />'));
      expect(content,
          contains('<foreground android:drawable="@drawable/ic_launcher_foreground" />'));
      expect(content,
          contains('<monochrome android:drawable="@drawable/ic_launcher_foreground" />'));
    });

    test('AndroidManifest.xml 含 android:roundIcon 声明', () {
      final file = File('android/app/src/main/AndroidManifest.xml');
      final content = file.readAsStringSync();
      expect(
        content,
        contains('android:roundIcon="@mipmap/ic_launcher_round"'),
        reason: 'AndroidManifest 应声明 android:roundIcon（部分启动器需要）',
      );
    });
  });
}
