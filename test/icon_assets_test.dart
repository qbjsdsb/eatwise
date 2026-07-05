import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 验证 Android 图标资源完整性
///
/// 历史：M15 餐叉+餐刀+暖橙纯色 → M17 同心圆环+紫橙渐变 → M20 Google Lens 风
/// （四角 L+苹果圆+扫描线+紫橙渐变）→ M22 白底紫前景反转+精修取景框+碗剪影
/// （用户反馈「颜色丑、粗糙、太大、不像谷歌」重设计）。
/// 测试断言随设计演进更新，确保资源文件与设计意图保持一致。
void main() {
  group('图标资源完整性 (M22)', () {
    const androidResDir = 'android/app/src/main/res';

    test('colors.xml 含 ic_launcher_background 白色 + ic_launcher_foreground 紫色（M22 白底反转）', () {
      final file = File('$androidResDir/values/colors.xml');
      final content = file.readAsStringSync();
      expect(
        content,
        contains('<color name="ic_launcher_background">#FFFFFF</color>'),
        reason: 'M22 反转配色：背景白 #FFFFFF（Google Camera 风），移除紫橙渐变',
      );
      expect(
        content,
        contains('<color name="ic_launcher_foreground">#6750A4</color>'),
        reason: 'M22 前景紫 #6750A4（M3 基线紫，呼应 App 主题种子色）',
      );
      // M22 移除渐变结束色（不再用渐变背景）
      expect(
        content,
        isNot(contains('ic_launcher_background_end')),
        reason: 'M22 移除渐变结束色（白底纯色，无渐变）',
      );
    });

    test('ic_launcher_background.xml 纯白填充（M22 移除渐变）', () {
      final file = File('$androidResDir/drawable/ic_launcher_background.xml');
      final content = file.readAsStringSync();
      // M22：纯白背景，引用 @color/ic_launcher_background
      expect(
        content,
        contains('android:fillColor="@color/ic_launcher_background"'),
        reason: 'M22 背景应纯白填充引用 @color/ic_launcher_background',
      );
      // M22 不应有渐变（移除 <gradient> 和 aapt:attr）
      expect(
        content,
        isNot(contains('<gradient')),
        reason: 'M22 移除渐变（白底纯色）',
      );
      expect(
        content,
        isNot(contains('ic_launcher_background_end')),
        reason: 'M22 不再引用渐变结束色',
      );
    });

    test('ic_launcher_foreground.xml 含精修取景框+碗剪影（M22 重设计）', () {
      final file = File('$androidResDir/drawable/ic_launcher_foreground.xml');
      final content = file.readAsStringSync();
      // M22 几何：取景框四角 L 从 (36,36) 开始（M20 是 29,29，M22 收敛到 36,36 更小更精致）
      expect(
        content,
        contains('android:pathData="M36,36'),
        reason: '取景框 path 应从 (36,36) 开始（M22 收敛范围 50→36dp）',
      );
      // M22 几何：中心碗剪影（半圆盘）从 (42,48) 开始
      expect(
        content,
        contains('android:pathData="M42,48'),
        reason: '碗剪影 path 应从 (42,48) 开始（M22 中心碗半圆盘）',
      );
      // M22 描边 2.5dp（M20 是 4dp，M22 精修更细）
      expect(
        content,
        contains('android:strokeWidth="2.5"'),
        reason: 'M22 取景框描边 2.5dp（M20 4dp 太粗）',
      );
      // M22 round 线帽（M20 是 square，M22 精修更圆润）
      expect(
        content,
        contains('android:strokeLineCap="round"'),
        reason: 'M22 round 线帽（M20 square 太生硬）',
      );
      expect(
        content,
        contains('android:fillColor="@color/ic_launcher_foreground"'),
        reason: '前景应引用 @color/ic_launcher_foreground（M22 紫色）',
      );
      // M22 移除扫描线（M20 的 M33,54 应不存在）
      expect(
        content,
        isNot(contains('M33,54')),
        reason: 'M22 移除扫描线（静态线不传达动态，增加杂乱）',
      );
      // M20 的苹果圆 M44,54 应不存在
      expect(
        content,
        isNot(contains('M44,54')),
        reason: 'M20 苹果圆 path 应被 M22 碗剪影替换',
      );
      // M20 的取景框 M29,29 应不存在
      expect(
        content,
        isNot(contains('M29,29')),
        reason: 'M20 取景框 path 应被 M22 收敛范围替换',
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
