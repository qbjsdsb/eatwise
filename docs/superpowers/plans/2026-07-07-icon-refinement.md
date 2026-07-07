# M26 图标精修实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 M25 圆环盘+实心碗图标升级为 M26 径向渐变背景+描边碗+米粒+右上飘出叶子，提升精致度与食物语义。

**Architecture:** 改 3 个 XML 资源文件（colors.xml / ic_launcher_background.xml / ic_launcher_foreground.xml），更新 icon_assets_test.dart 断言，用 Python+cairosvg+pillow 重新渲染 5 个密度的 PNG fallback，最后 bump 版本 v0.28.0+40 → v0.29.0+41。

**Tech Stack:** Android Vector Drawable（XML）/ Flutter widget test / Python cairosvg + pillow

**Spec:** [docs/superpowers/specs/2026-07-07-icon-refinement-design.md](file:///workspace/docs/superpowers/specs/2026-07-07-icon-refinement-design.md)

**硬约束（项目规则）：**
- `android/app/build.gradle.kts` 不动（保持 minify=false / shrink=false / minSdk=31）
- 不动 meal_log / AI 三路径 / food_components 逻辑
- 注释用中文
- 沙箱 Flutter 在 `/tmp/flutter/bin`，每次新会话需 `export PATH=/tmp/flutter/bin:$PATH`

---

## 文件结构

| 文件 | 操作 | 责任 |
|------|------|------|
| `android/app/src/main/res/values/colors.xml` | 修改 | 新增 6 个 M26 颜色定义（保留 M25 旧色兼容 splash 等其它引用） |
| `android/app/src/main/res/drawable/ic_launcher_background.xml` | 修改 | 改为径向渐变（中心白 → 边缘 Light Green 50） |
| `android/app/src/main/res/drawable/ic_launcher_foreground.xml` | 修改 | 重写为 4 path：碗填充+碗描边+米粒+叶子 |
| `test/icon_assets_test.dart` | 修改 | 断言更新为 M26 几何与配色 |
| `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` | 重新生成 | Python 渲染 5 个密度 |
| `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_round.png` | 重新生成 | Python 渲染 + 圆形裁剪 5 个密度 |
| `pubspec.yaml` | 修改 | version 0.28.0+40 → 0.29.0+41 |

`mipmap-anydpi-v26/ic_launcher.xml` 和 `ic_launcher_round.xml` 不动（已正确引用 `@drawable/ic_launcher_background` 和 `@drawable/ic_launcher_foreground`，monochrome 复用 foreground）。

---

## Task 1: 更新 colors.xml 新增 M26 配色

**Files:**
- Modify: `android/app/src/main/res/values/colors.xml`

- [ ] **Step 1: 读取当前 colors.xml 确认基线**

Run: `cat android/app/src/main/res/values/colors.xml`
Expected: 含 `splash_background` / `ic_launcher_background` (#FFFFFF) / `ic_launcher_foreground` (#2E7D32) 三个色

- [ ] **Step 2: 在 `ic_launcher_foreground` 后追加 6 个新颜色**

把文件末尾的：
```xml
    <color name="ic_launcher_background">#FFFFFF</color>
    <color name="ic_launcher_foreground">#2E7D32</color>
</resources>
```

改为：
```xml
    <color name="ic_launcher_background">#FFFFFF</color>
    <color name="ic_launcher_foreground">#2E7D32</color>

    <!-- M26：图标精修配色——径向渐变背景 + 描边碗+米粒+叶子
         M25 白底+自然绿前景 → M26 径向渐变+4 色层次
         - 背景中心 #FFFFFF（White）：径向渐变中心
         - 背景边缘 #F1F8E9（Light Green 50）：极淡绿衬托前景
         - 碗描边 #1B5E20（Green 900）：比主色深一阶
         - 碗填充 #E8F5E9（Green 50）：淡绿与背景同色系
         - 叶子 #2E7D32（Green 800）：主绿，保留 M25 主色
         - 米粒 #FFF59D（Amber 200）：淡黄食物语义 -->
    <color name="ic_launcher_background_center">#FFFFFF</color>
    <color name="ic_launcher_background_edge">#F1F8E9</color>
    <color name="ic_launcher_bowl_stroke">#1B5E20</color>
    <color name="ic_launcher_bowl_fill">#E8F5E9</color>
    <color name="ic_launcher_leaf">#2E7D32</color>
    <color name="ic_launcher_rice">#FFF59D</color>
</resources>
```

注意：`ic_launcher_background` 和 `ic_launcher_foreground` 保留不动（`launch_background.xml` 等其它资源可能引用；新旧定义共存不冲突）。

- [ ] **Step 3: 验证文件格式正确**

Run: `cat android/app/src/main/res/values/colors.xml`
Expected: 含 9 个 `<color>` 标签（3 旧 + 6 新），XML 闭合完整

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/res/values/colors.xml
git commit -m "feat(icon): M26 新增 6 色配色定义（渐变背景+碗描边填充+叶+米粒）"
```

---

## Task 2: 改写 ic_launcher_background.xml 为径向渐变

**Files:**
- Modify: `android/app/src/main/res/drawable/ic_launcher_background.xml`

- [ ] **Step 1: 用径向渐变版本覆盖整个文件**

把整个文件替换为：
```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  自适应图标背景：径向渐变（中心白 → 边缘 Light Green 50）。

  M26 决策：从 M22/M25 的纯白背景升级为径向渐变，增加层次感。
  - 中心 #FFFFFF 白色，前景焦点（碗+叶子）下方最亮
  - 边缘 #F1F8E9 极淡绿，与碗填充 #E8F5E9 同色系，衬托前景
  - 渐变半径 54dp（画布对角线一半稍短，覆盖到四角）

  Android vector 渐变用 <aapt:attr> 嵌套 <gradient> 实现内联：
  - android:type="radial" 径向
  - centerX/centerY 54,54 画布中心
  - gradientRadius 54 渐变半径
  - startColor 中心白 / endColor 边缘淡绿

  monochrome 兼容：Android 13+ 主题图标染色时渐变被忽略，系统用单色染色，可接受。

  M22/M25 纯白 → M26 径向渐变（精致层次）
-->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">

    <path android:pathData="M0,0 h108 v108 h-108 z">
        <aapt:attr name="android:fillColor">
            <gradient
                android:type="radial"
                android:centerX="54"
                android:centerY="54"
                android:gradientRadius="54"
                android:startColor="@color/ic_launcher_background_center"
                android:endColor="@color/ic_launcher_background_edge" />
        </aapt:attr>
    </path>
</vector>
```

- [ ] **Step 2: 验证文件**

Run: `cat android/app/src/main/res/drawable/ic_launcher_background.xml`
Expected: 含 `<aapt:attr>` 嵌套 `<gradient android:type="radial"`，引用 `@color/ic_launcher_background_center` 和 `@color/ic_launcher_background_edge`

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/res/drawable/ic_launcher_background.xml
git commit -m "feat(icon): M26 背景改径向渐变（中心白→边缘淡绿）"
```

---

## Task 3: 重写 ic_launcher_foreground.xml（碗+米粒+叶子）

**Files:**
- Modify: `android/app/src/main/res/drawable/ic_launcher_foreground.xml`

- [ ] **Step 1: 用 M26 四 path 版本覆盖整个文件**

把整个文件替换为：
```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  自适应图标前景：描边碗+内部填充 + 三粒米粒 + 右上飘出叶子（M26 重设计）。

  设计理念（M26 用户决策：碗+叶子=自然×食物，精致美丽）：
  - 描边碗+内部填充 = 容器（深绿描边 + 淡绿填充，2.5dp round 描边精致克制）
  - 三粒米粒 = 食物（淡黄 Amber 200，碗内三角排列，食物语义）
  - 右上飘出叶子 = 自然（主绿 Green 800，45° 上扬，自然×食物的双重语义）
  - 删除 M25 圆环盘（碗成为唯一主体，几何更聚焦）

  画布 108×108dp，安全区 66×66（中心 54,54，半径 33）。
  M26 几何：
  - 碗：30×15dp，碗口 y=51 flat top，碗底 y=66 curve bottom
    碗左点 (39,51) 碗右点 (69,51)，A15,15 半径 15 顺时针短弧 sweep=1
  - 米粒：r=1.2dp，3 粒三角排列
    左下 (47,60) 右下 (61,60) 中上 (54,55)
  - 叶子：水滴形，叶柄 (69,51) 叶尖 (80,40)，45° 上扬
    两条贝塞尔 C66,48 66,42 80,40 + C78,46 74,50 69,51

  配色层次（4 色 vs M25 的 2 色）：
  - 碗描边 #1B5E20（Green 900，深绿）→ 重量最高
  - 碗填充 #E8F5E9（Green 50，淡绿）→ 中等重量
  - 叶子 #2E7D32（Green 800，主绿）→ 重量高（焦点）
  - 米粒 #FFF59D（Amber 200，淡黄）→ 食物语义对比色

  monochrome 兼容（Android 13+ 主题图标）：
  - 系统染色时背景渐变被忽略，前景各 path 的 alpha 通道被染色
  - 碗描边+碗填充+叶子+米粒 在染色后层次仍可识别（实心>描边重量）

  M25 圆环盘+实心碗 → M26 描边碗+米粒+叶子（用户反馈"想更精致美丽"重设计）
-->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">

    <!-- 碗填充（淡绿 #E8F5E9，30×15dp）：
         M39,51 左点（碗口左端）
         A15,15 0 0 1 69,51 顺时针短弧到右点（sweep=1 = 下方半圆 = 碗底）
         Z 闭合（flat top = 碗口） -->
    <path
        android:fillColor="@color/ic_launcher_bowl_fill"
        android:pathData="M39,51 A15,15 0 0 1 69,51 Z" />

    <!-- 碗描边（深绿 #1B5E20，2.5dp round cap，无填充）：
         path 同碗填充，strokeColor 描边轮廓 -->
    <path
        android:strokeColor="@color/ic_launcher_bowl_stroke"
        android:strokeWidth="2.5"
        android:strokeLineCap="round"
        android:fillColor="#00000000"
        android:pathData="M39,51 A15,15 0 0 1 69,51 Z" />

    <!-- 三粒米粒（淡黄 #FFF59D，r=1.2dp，碗内三角排列）：
         M47,60 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0  左下米粒
         M61,60 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0  右下米粒
         M54,55 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0  中上米粒
         圆画法：先 M 到圆心，再 m -r,0 移到左侧，两个 a 半弧画圆 -->
    <path
        android:fillColor="@color/ic_launcher_rice"
        android:pathData="M47,60 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0 M61,60 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0 M54,55 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0" />

    <!-- 右上飘出叶子（主绿 #2E7D32，水滴形，45° 上扬）：
         M69,51 叶柄起点（碗口右端）
         C66,48 66,42 80,40 第一条贝塞尔：叶柄→叶尖左侧弧线（叶面凸出）
         C78,46 74,50 69,51 第二条贝塞尔：叶尖→叶柄右侧弧线（叶背稍直）
         Z 闭合 -->
    <path
        android:fillColor="@color/ic_launcher_leaf"
        android:pathData="M69,51 C66,48 66,42 80,40 C78,46 74,50 69,51 Z" />
</vector>
```

- [ ] **Step 2: 验证文件**

Run: `cat android/app/src/main/res/drawable/ic_launcher_foreground.xml`
Expected:
- 含 4 个 `<path>` 标签
- 含 `@color/ic_launcher_bowl_fill` / `@color/ic_launcher_bowl_stroke` / `@color/ic_launcher_rice` / `@color/ic_launcher_leaf`
- 含 `M39,51 A15,15` (碗) + `M47,60 m-1.2,0` (米粒) + `M69,51 C66,48` (叶子)
- 不含 M25 旧几何 `M26,54` 或 `M43,48.5`

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/res/drawable/ic_launcher_foreground.xml
git commit -m "feat(icon): M26 前景改描边碗+米粒+叶子（4 path 精致重设计）"
```

---

## Task 4: 更新 icon_assets_test.dart 断言

**Files:**
- Modify: `test/icon_assets_test.dart`

- [ ] **Step 1: 用 M26 断言版本覆盖整个文件**

把整个文件替换为：
```dart
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
```

- [ ] **Step 2: 确认 Flutter 已安装**

Run: `which flutter || export PATH=/tmp/flutter/bin:$PATH && which flutter`
Expected: 输出 flutter 路径（如 `/tmp/flutter/bin/flutter`）。若不存在的报错，执行沙箱 Flutter 安装（见 spec 错误 3 修复脚本）。

- [ ] **Step 3: 跑测试验证断言**

Run: `flutter test test/icon_assets_test.dart`
Expected: 6 个 test 全 PASS。若有失败，根据失败原因修对应的 XML 文件。

- [ ] **Step 4: Commit**

```bash
git add test/icon_assets_test.dart
git commit -m "test(icon): M26 断言更新（径向渐变+碗+米粒+叶子 4 path）"
```

---

## Task 5: 重新生成 5 个密度 PNG fallback

**Files:**
- Create: `/tmp/render_icon.py`（脚本，渲染完即删，不入库）
- Modify: `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`
- Modify: `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_round.png`

- [ ] **Step 1: 安装 Python 依赖**

Run: `pip install cairosvg pillow`
Expected: `Successfully installed cairosvg-*.whl pillow-*.whl`（或 "already satisfied"）

- [ ] **Step 2: 写渲染脚本 `/tmp/render_icon.py`**

```python
#!/usr/bin/env python3
"""M26 图标 PNG 渲染脚本：从 vector drawable 合成 SVG，渲染 5 个密度 PNG。

把 ic_launcher_background.xml 的径向渐变 + ic_launcher_foreground.xml 的 4 个 path
合成一个 108x108 SVG，然后渲染为 5 个密度的 PNG（方形 + 圆形裁剪）。
"""
import cairosvg
from PIL import Image, ImageDraw
import io
import os

# 5 个密度对应的物理像素尺寸
DENSITIES = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
}

RES_DIR = 'android/app/src/main/res'

# 合成 SVG：把背景渐变 + 前景 4 path 组合到 108x108 画布
# 注意：Android vector path 命令与 SVG path 命令基本一致（M/L/A/C/Z 都通用）
SVG_TEMPLATE = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="108" height="108" viewBox="0 0 108 108">
  <defs>
    <radialGradient id="bg" cx="54" cy="54" r="54" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#FFFFFF" />
      <stop offset="100%" stop-color="#F1F8E9" />
    </radialGradient>
  </defs>
  <!-- 背景：径向渐变 -->
  <rect x="0" y="0" width="108" height="108" fill="url(#bg)" />
  <!-- 碗填充（淡绿 #E8F5E9） -->
  <path d="M39,51 A15,15 0 0 1 69,51 Z" fill="#E8F5E9" />
  <!-- 碗描边（深绿 #1B5E20，2.5dp round cap） -->
  <path d="M39,51 A15,15 0 0 1 69,51 Z" fill="none" stroke="#1B5E20" stroke-width="2.5" stroke-linecap="round" />
  <!-- 三粒米粒（淡黄 #FFF59D） -->
  <path d="M47,60 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0 M61,60 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0 M54,55 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0" fill="#FFF59D" />
  <!-- 右上飘出叶子（主绿 #2E7D32） -->
  <path d="M69,51 C66,48 66,42 80,40 C78,46 74,50 69,51 Z" fill="#2E7D32" />
</svg>
'''

def render_round(png_bytes: bytes, size: int) -> bytes:
    """把方形 PNG 裁剪为圆形（ic_launcher_round.png 用）。"""
    img = Image.open(io.BytesIO(png_bytes)).convert('RGBA')
    img = img.resize((size, size), Image.LANCZOS)
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, size - 1, size - 1), fill=255)
    result = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    result.paste(img, (0, 0), mask)
    out = io.BytesIO()
    result.save(out, format='PNG')
    return out.getvalue()

def main():
    svg_bytes = SVG_TEMPLATE.encode('utf-8')
    for density, size in DENSITIES.items():
        # 方形 PNG
        square_png = cairosvg.svg2png(
            bytestring=svg_bytes,
            output_width=size,
            output_height=size,
        )
        square_path = f'{RES_DIR}/mipmap-{density}/ic_launcher.png'
        with open(square_path, 'wb') as f:
            f.write(square_png)
        print(f'wrote {square_path} ({size}x{size})')

        # 圆形 PNG
        round_png = render_round(square_png, size)
        round_path = f'{RES_DIR}/mipmap-{density}/ic_launcher_round.png'
        with open(round_path, 'wb') as f:
            f.write(round_png)
        print(f'wrote {round_path} ({size}x{size})')

if __name__ == '__main__':
    main()
```

Run: 用 Write 工具写入 `/tmp/render_icon.py`

- [ ] **Step 3: 执行渲染脚本**

Run: `cd /workspace && python3 /tmp/render_icon.py`
Expected:
```
wrote android/app/src/main/res/mipmap-mdpi/ic_launcher.png (48x48)
wrote android/app/src/main/res/mipmap-mdpi/ic_launcher_round.png (48x48)
wrote android/app/src/main/res/mipmap-hdpi/ic_launcher.png (72x72)
...
wrote android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png (192x192)
wrote android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png (192x192)
```

- [ ] **Step 4: 验证 PNG 文件存在且尺寸正确**

Run: `python3 -c "from PIL import Image; import os; [print(f'{d}: {Image.open(f\"android/app/src/main/res/mipmap-{d}/ic_launcher.png\").size}, {os.path.getsize(f\"android/app/src/main/res/mipmap-{d}/ic_launcher.png\")} bytes') for d in ['mdpi','hdpi','xhdpi','xxhdpi','xxxhdpi']]"`
Expected: 5 行输出，尺寸依次 48/72/96/144/192，字节数 > 0

- [ ] **Step 5: 清理渲染脚本**

Run: `rm /tmp/render_icon.py`
Expected: 无输出（脚本删除，不入库）

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/res/mipmap-mdpi/ic_launcher.png android/app/src/main/res/mipmap-mdpi/ic_launcher_round.png android/app/src/main/res/mipmap-hdpi/ic_launcher.png android/app/src/main/res/mipmap-hdpi/ic_launcher_round.png android/app/src/main/res/mipmap-xhdpi/ic_launcher.png android/app/src/main/res/mipmap-xhdpi/ic_launcher_round.png android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png android/app/src/main/res/mipmap-xxhdpi/ic_launcher_round.png android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png
git commit -m "feat(icon): M26 重新渲染 5 个密度 PNG fallback（cairosvg）"
```

---

## Task 6: 跑全量验证（analyze + test）

**Files:** 无修改

- [ ] **Step 1: flutter analyze**

Run: `flutter analyze`
Expected: `No issues found! (NNN ms)`（或与 v0.28.0 基线一致的 N 个 issues，0 个新增）

- [ ] **Step 2: flutter test 全量**

Run: `flutter test`
Expected:
- icon_assets_test.dart 6 个 test 全 PASS
- 全量 1134+ passed 0 failed（v0.28.0 基线 1134 passed / 3 skipped，新增/修改不应引入回归）
- 若 `github_release_smoke_test` 失败（沙箱网络限流），属已知问题，与本次改动无关

- [ ] **Step 3: 若有回归，定位修复**

若非 sandbox 网络问题的失败，定位到具体 test → 检查是否本次 XML 改动破坏了其它 test → 修复 → 重跑

---

## Task 7: bump 版本 v0.28.0+40 → v0.29.0+41

**Files:**
- Modify: `pubspec.yaml:4`

- [ ] **Step 1: 改 pubspec.yaml version 行**

把 `pubspec.yaml` 第 4 行：
```yaml
version: 0.28.0+40
```
改为：
```yaml
version: 0.29.0+41
```

- [ ] **Step 2: 检查是否有其它地方硬编码版本号**

Run: `grep -rn "0.28.0+40\|0.28.0" --include="*.dart" --include="*.yaml" --include="*.md" /workspace/lib /workspace/test /workspace/pubspec.yaml /workspace/CHANGELOG.md 2>/dev/null | head -20`
Expected: 若 CHANGELOG.md 或其它地方有版本引用，相应更新；若仅 pubspec.yaml 一处，跳过

- [ ] **Step 3: 追加 CHANGELOG 条目（若项目有 CHANGELOG.md）**

Run: `ls /workspace/CHANGELOG.md 2>/dev/null && head -20 /workspace/CHANGELOG.md`
Expected: 若存在，在最顶部追加：
```
## v0.29.0 (2026-07-07)

### 图标精修（M26）
- 背景：径向渐变（中心白 → 边缘淡绿），替代 M25 纯白
- 前景：描边碗+内部填充 + 三粒米粒 + 右上飘出叶子，替代 M25 圆环盘+实心碗
- 配色：4 色层次（深绿描边/淡绿填充/主绿叶/淡黄米粒），替代 M25 2 色纯绿
- 重新渲染 5 个密度 PNG fallback
```
若不存在 CHANGELOG.md，跳过此步（项目规则不主动创建文档）。

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml CHANGELOG.md  # 若 CHANGELOG 不存在或不改，去掉它
git commit -m "chore: bump v0.29.0+41（M26 图标精修）"
```

---

## Task 8: 更新 HANDOFF.md

**Files:**
- Modify: `/workspace/HANDOFF.md`

- [ ] **Step 1: 读 HANDOFF.md 当前状态段**

Run: `head -200 /workspace/HANDOFF.md`
Expected: 找到"当前状态"或类似章节

- [ ] **Step 2: 更新当前状态**

在 HANDOFF.md 第 2 节"当前状态"补充/更新：
- 当前版本：v0.29.0+41（M26 图标精修）
- 上一版本：v0.28.0+40（库解耦架构改造）
- M26 变更：图标重设计（径向渐变背景+描边碗+米粒+叶子），6 色配色，5 个密度 PNG 重新渲染
- 验证：flutter analyze No issues / flutter test 全量 PASS
- 待办：等用户明确指令 push + 打 tag v0.29.0 + GitHub Release

- [ ] **Step 3: Commit**

```bash
git add HANDOFF.md
git commit -m "docs: HANDOFF 更新 v0.29.0 M26 图标精修状态"
```

---

## Self-Review

**1. Spec coverage:**
- §2.1 用户决策链 6 项 → Task 1-3 全部实现（碗+叶子+米粒+渐变+描边+删圆环）✓
- §2.2 视觉结构 3 元素 → Task 3 foreground 4 path（碗填充+碗描边+米粒+叶子）✓
- §2.3 配色 6 色 → Task 1 colors.xml 6 个新色 + Task 2/3 引用 ✓
- §2.4.1 径向渐变 → Task 2 background.xml ✓
- §2.4.2 碗描边+填充 → Task 3 前 2 path ✓
- §2.4.3 三粒米粒 → Task 3 第 3 path ✓
- §2.4.4 右上叶子 → Task 3 第 4 path ✓
- §2.5 monochrome 兼容 → mipmap-anydpi-v26/ic_launcher.xml 已正确引用（Task 4 测试断言验证），无需改动 ✓
- §2.6 PNG fallback → Task 5 渲染 5 密度 ✓
- §3 实施步骤 → Task 1-8 全覆盖 ✓
- §4 验证 → Task 6 ✓
- §5 版本 → Task 7 ✓

**2. Placeholder scan:** 全部代码块完整，无 TBD/TODO/「类似 Task N」引用。Task 5 渲染脚本完整可执行。✓

**3. Type consistency:**
- 颜色名一致：`ic_launcher_background_center/edge` / `ic_launcher_bowl_stroke/fill` / `ic_launcher_leaf` / `ic_launcher_rice` 在 Task 1 定义、Task 2/3 引用、Task 4 断言 —— 全一致 ✓
- path 几何一致：`M39,51 A15,15`（碗）+ `M47,60 m-1.2,0`（米粒）+ `M69,51 C66,48 66,42 80,40`（叶子）在 Task 3 实现、Task 4 断言、Task 5 SVG 模板 —— 全一致 ✓
- 版本号 `0.29.0+41` 在 Task 7 pubspec 与 HANDOFF 一致 ✓

无遗漏。计划完整可执行。

---

## Execution Handoff

计划已保存到 [docs/superpowers/plans/2026-07-07-icon-refinement.md](file:///workspace/docs/superpowers/plans/2026-07-07-icon-refinement.md)。

两种执行方式：

1. **Subagent-Driven（推荐）** — 每个 Task 派一个独立 subagent 执行，Task 间审查，迭代快
2. **Inline Execution** — 在当前会话批量执行，分段 checkpoint 审查

选哪种？
