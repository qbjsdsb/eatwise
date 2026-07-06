import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 验证 Android 图标资源完整性
///
/// 历史：M15 餐叉+餐刀+暖橙纯色 → M17 同心圆环+紫橙渐变 → M20 Google Lens 风
/// （四角 L+苹果圆+扫描线+紫橙渐变）→ M22 白底紫前景反转+精修取景框+碗剪影
/// → M25 白底自然绿前景+圆环描边盘+实心碗（对标 MyFitnessPal，紫色抑制食欲改绿）
/// 测试断言随设计演进更新，确保资源文件与设计意图保持一致。
void main() {
  group('图标资源完整性 (M25)', () {
    const androidResDir = 'android/app/src/main/res';

    test('colors.xml 含 ic_launcher_background 白色 + ic_launcher_foreground 自然绿（M25 对标 MFP）', () {
      final file = File('$androidResDir/values/colors.xml');
      final content = file.readAsStringSync();
      expect(
        content,
        contains('<color name="ic_launcher_background">#FFFFFF</color>'),
        reason: 'M25 背景白 #FFFFFF（M22 决策保留，M25 不变）',
      );
      expect(
        content,
        contains('<color name="ic_launcher_foreground">#2E7D32</color>'),
        reason: 'M25 前景自然绿 #2E7D32（Material Green 800，紫色抑制食欲改绿）',
      );
      // M22/M25 都不用渐变结束色
      expect(
        content,
        isNot(contains('ic_launcher_background_end')),
        reason: 'M22/M25 移除渐变结束色（白底纯色，无渐变）',
      );
    });

    test('ic_launcher_background.xml 纯白填充（M22/M25 无渐变）', () {
      final file = File('$androidResDir/drawable/ic_launcher_background.xml');
      final content = file.readAsStringSync();
      // M22/M25：纯白背景，引用 @color/ic_launcher_background
      expect(
        content,
        contains('android:fillColor="@color/ic_launcher_background"'),
        reason: '背景应纯白填充引用 @color/ic_launcher_background',
      );
      // M22/M25 不应有渐变
      expect(
        content,
        isNot(contains('<gradient')),
        reason: 'M22/M25 移除渐变（白底纯色）',
      );
      expect(
        content,
        isNot(contains('ic_launcher_background_end')),
        reason: 'M22/M25 不再引用渐变结束色',
      );
    });

    test('ic_launcher_foreground.xml 含圆环描边盘+实心碗剪影（M25 重设计）', () {
      final file = File('$androidResDir/drawable/ic_launcher_foreground.xml');
      final content = file.readAsStringSync();
      // M25 几何：圆环描边盘从 (26,54) 开始（M22 是 M36,36 四角 L 起点）
      expect(
        content,
        contains('android:pathData="M26,54'),
        reason: '圆环盘 path 应从 (26,54) 开始（M25 外径 56dp，中心 54,54）',
      );
      // M25 几何：中心实心碗从 (43,48.5) 开始（M22 是 M42,48）
      expect(
        content,
        contains('android:pathData="M43,48.5'),
        reason: '碗剪影 path 应从 (43,48.5) 开始（M25 碗 22×11dp，0.5dp 网格对齐）',
      );
      // M25 描边 2.5dp（M22 也是 2.5dp，M20 是 4dp）
      expect(
        content,
        contains('android:strokeWidth="2.5"'),
        reason: 'M25 圆环盘描边 2.5dp（精致克制）',
      );
      // M25 round 线帽（M22 也是 round，M20 是 square）
      expect(
        content,
        contains('android:strokeLineCap="round"'),
        reason: 'M25 round 线帽（精致圆润）',
      );
      expect(
        content,
        contains('android:fillColor="@color/ic_launcher_foreground"'),
        reason: '前景应引用 @color/ic_launcher_foreground（M25 自然绿）',
      );
      // M22 旧几何不应存在（M25 移除四角 L 角标）
      expect(
        content,
        isNot(contains('M36,36')),
        reason: 'M22 四角 L 起点 M36,36 应被 M25 圆环盘替换',
      );
      // M22 旧碗起点不应存在（M25 改为 0.5dp 对齐的 48.5）
      expect(
        content,
        isNot(contains('M42,48')),
        reason: 'M22 碗起点 M42,48 应被 M25 M43,48.5 替换（0.5dp 网格对齐）',
      );
      // M20 旧几何不应存在（M22/M25 都不应用）
      expect(
        content,
        isNot(contains('M33,54')),
        reason: 'M20 扫描线 M33,54 应不存在',
      );
      expect(
        content,
        isNot(contains('M44,54')),
        reason: 'M20 苹果圆 M44,54 应不存在',
      );
      expect(
        content,
        isNot(contains('M29,29')),
        reason: 'M20 取景框 M29,29 应不存在',
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
