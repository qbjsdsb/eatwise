import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 验证 Android 图标资源完整性
///
/// 历史：M15 餐叉+餐刀+暖橙纯色 → M17 同心圆环+紫橙渐变 → M20 Google Lens 风
/// （四角 L+苹果圆+扫描线+紫橙渐变）→ M22 白底紫前景反转+精修取景框+碗剪影
/// → M25 白底自然绿前景+圆环描边盘+实心碗（对标 MyFitnessPal）
/// → M26 径向渐变背景+描边碗+米粒+右上飘出叶子（精致美丽，自然×食物语义）
/// 测试断言随设计演进更新，确保资源文件与设计意图保持一致。
void main() {
  group('图标资源完整性 (M26)', () {
    const androidResDir = 'android/app/src/main/res';

    test('colors.xml 含 M26 六色配色定义', () {
      final file = File('$androidResDir/values/colors.xml');
      final content = file.readAsStringSync();
      // M26 新增 6 色
      expect(
        content,
        contains('<color name="ic_launcher_background_center">#FFFFFF</color>'),
        reason: 'M26 背景中心白（径向渐变中心）',
      );
      expect(
        content,
        contains('<color name="ic_launcher_background_edge">#F1F8E9</color>'),
        reason: 'M26 背景边缘 Light Green 50（径向渐变边缘）',
      );
      expect(
        content,
        contains('<color name="ic_launcher_bowl_stroke">#1B5E20</color>'),
        reason: 'M26 碗描边 Green 900（深绿比主色深一阶）',
      );
      expect(
        content,
        contains('<color name="ic_launcher_bowl_fill">#E8F5E9</color>'),
        reason: 'M26 碗填充 Green 50（淡绿）',
      );
      expect(
        content,
        contains('<color name="ic_launcher_leaf">#2E7D32</color>'),
        reason: 'M26 叶子 Green 800（主绿，保留 M25 主色）',
      );
      expect(
        content,
        contains('<color name="ic_launcher_rice">#FFF59D</color>'),
        reason: 'M26 米粒 Amber 200（淡黄食物语义）',
      );
    });

    test('ic_launcher_background.xml 含径向渐变（M26）', () {
      final file = File('$androidResDir/drawable/ic_launcher_background.xml');
      final content = file.readAsStringSync();
      // M26：径向渐变
      expect(
        content,
        contains('<gradient'),
        reason: 'M26 背景应含 <gradient> 标签',
      );
      expect(
        content,
        contains('android:type="radial"'),
        reason: 'M26 渐变类型 radial（径向）',
      );
      expect(
        content,
        contains('android:centerX="54"'),
        reason: 'M26 渐变中心 X=54（画布中心）',
      );
      expect(
        content,
        contains('android:centerY="54"'),
        reason: 'M26 渐变中心 Y=54（画布中心）',
      );
      expect(
        content,
        contains('android:gradientRadius="54"'),
        reason: 'M26 渐变半径 54dp',
      );
      expect(
        content,
        contains('@color/ic_launcher_background_center'),
        reason: 'M26 引用背景中心色',
      );
      expect(
        content,
        contains('@color/ic_launcher_background_edge'),
        reason: 'M26 引用背景边缘色',
      );
    });

    test('ic_launcher_foreground.xml 含碗+米粒+叶子（M26 重设计）', () {
      final file = File('$androidResDir/drawable/ic_launcher_foreground.xml');
      final content = file.readAsStringSync();
      // M26 碗几何：M39,51 A15,15（碗左点 + 弧半径 15）
      expect(
        content,
        contains('M39,51 A15,15'),
        reason: 'M26 碗 path 应从 (39,51) 开始，弧半径 15（碗 30×15dp）',
      );
      // M26 米粒几何：M47,60 m-1.2,0（左下米粒圆心 47,60）
      expect(
        content,
        contains('M47,60 m-1.2,0'),
        reason: 'M26 左下米粒圆心 (47,60)，r=1.2dp',
      );
      // M26 叶子几何：M69,51 C66,48 66,42 80,40（叶柄+第一条贝塞尔）
      expect(
        content,
        contains('M69,51 C66,48 66,42 80,40'),
        reason: 'M26 叶子 path：叶柄 (69,51) → 叶尖 (80,40)',
      );
      // M26 四色引用
      expect(
        content,
        contains('@color/ic_launcher_bowl_fill'),
        reason: 'M26 碗填充引用淡绿',
      );
      expect(
        content,
        contains('@color/ic_launcher_bowl_stroke'),
        reason: 'M26 碗描边引用深绿',
      );
      expect(
        content,
        contains('@color/ic_launcher_rice'),
        reason: 'M26 米粒引用淡黄',
      );
      expect(
        content,
        contains('@color/ic_launcher_leaf'),
        reason: 'M26 叶子引用主绿',
      );
      // M25 旧几何不应存在（M26 删除圆环盘 + 改碗几何）
      expect(
        content,
        isNot(contains('M26,54')),
        reason: 'M25 圆环盘 M26,54 应被 M26 删除',
      );
      expect(
        content,
        isNot(contains('M43,48.5')),
        reason: 'M25 实心碗 M43,48.5 应被 M26 碗几何替换',
      );
      // M22 旧几何不应存在
      expect(
        content,
        isNot(contains('M36,36')),
        reason: 'M22 四角 L 起点 M36,36 应不存在',
      );
      // M20 旧几何不应存在
      expect(
        content,
        isNot(contains('M33,54')),
        reason: 'M20 扫描线 M33,54 应不存在',
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
