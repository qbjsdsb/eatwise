import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 验证 Android 图标资源完整性
///
/// 历史：M15 引入餐叉+餐刀 + 暖橙纯色背景；M17 重设计为 M3 抽象几何
/// （同心圆环+中心圆点）+ 紫橙双色渐变（用户反馈"图标实在太丑"重设计）。
/// 测试断言随设计演进更新，确保资源文件与设计意图保持一致。
void main() {
  group('图标资源完整性 (M17)', () {
    const androidResDir = 'android/app/src/main/res';

    test('colors.xml 含 ic_launcher_background 紫色起始色（M17 紫橙渐变）', () {
      final file = File('$androidResDir/values/colors.xml');
      final content = file.readAsStringSync();
      expect(
        content,
        contains('<color name="ic_launcher_background">#6750A4</color>'),
        reason: 'M17 起始色 #6750A4（M3 基线紫），呼应 App 主题种子色',
      );
      expect(
        content,
        contains('<color name="ic_launcher_background_end">#FF6E40</color>'),
        reason: 'M17 渐变结束色 #FF6E40（Deep Orange 400），食欲色/食物色',
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

    test('ic_launcher_background.xml 用渐变引用 @color/ic_launcher_background*（M17 紫橙渐变）', () {
      final file = File('$androidResDir/drawable/ic_launcher_background.xml');
      final content = file.readAsStringSync();
      // M17：渐变背景，引用两个 color 资源（起始紫 + 结束橙）
      expect(
        content,
        contains('android:startColor="@color/ic_launcher_background"'),
        reason: '渐变起始色应引用 @color/ic_launcher_background（紫）',
      );
      expect(
        content,
        contains('android:endColor="@color/ic_launcher_background_end"'),
        reason: '渐变结束色应引用 @color/ic_launcher_background_end（橙）',
      );
      // 属性值不应硬编码颜色（注释里的颜色说明允许，但 startColor/endColor
      // 属性值必须是 @color 引用，不能是 # 字面量）
      expect(
        content,
        isNot(contains('android:startColor="#')),
        reason: 'startColor 属性值不应硬编码 # 字面量（应通过 @color 资源引用）',
      );
      expect(
        content,
        isNot(contains('android:endColor="#')),
        reason: 'endColor 属性值不应硬编码 # 字面量（应通过 @color 资源引用）',
      );
    });

    test('ic_launcher_foreground.xml 含同心圆环+中心圆点 path（M17 重设计）', () {
      final file = File('$androidResDir/drawable/ic_launcher_foreground.xml');
      final content = file.readAsStringSync();
      // M17 几何：外环带顶部 8dp 缺口，从 (50,29) 起
      expect(
        content,
        contains('android:pathData="M50,29'),
        reason: '外环 path 应从 (50,29) 开始（M17 同心圆环几何布局）',
      );
      // M17 几何：中心圆点，从 (46,54) 起
      expect(
        content,
        contains('android:pathData="M46,54'),
        reason: '中心圆点 path 应从 (46,54) 开始（M17 几何布局）',
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
      // M15 餐叉+餐刀 path 应已移除
      expect(
        content,
        isNot(contains('M38,24')),
        reason: 'M15 餐叉 path 应被 M17 同心圆环替换',
      );
      expect(
        content,
        isNot(contains('M62,24')),
        reason: 'M15 餐刀 path 应被 M17 中心圆点替换',
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

    test('5 个 mipmap 密度都有 ic_launcher.png 和 ic_launcher_round.png', () {
      const densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
      for (final d in densities) {
        final png = File('$androidResDir/mipmap-$d/ic_launcher.png');
        expect(
          png.existsSync(),
          true,
          reason: 'mipmap-$d/ic_launcher.png 应存在（方形图标 PNG fallback）',
        );
        final pngRound = File('$androidResDir/mipmap-$d/ic_launcher_round.png');
        expect(
          pngRound.existsSync(),
          true,
          reason: 'mipmap-$d/ic_launcher_round.png 应存在（圆角图标 PNG fallback）',
        );
      }
    });
  });
}
