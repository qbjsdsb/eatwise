# EatWise M25 图标精修重设计 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Android 启动器图标从 M22（白底紫前景 + 四角 L 角标 + 中心碗）重设计为 M25（白底自然绿前景 + 圆环描边盘 + 中心实心碗），对标 MyFitnessPal 圆盘容器语言，解决紫色抑制食欲问题。

**Architecture:** 改动范围极小——3 个 Android 资源文件（`ic_launcher_foreground.xml` 重写 path / `ic_launcher_background.xml` 更新注释 / `values/colors.xml` 改前景色值）+ 1 个测试文件更新断言（`test/icon_assets_test.dart` 硬编码了 M22 几何与颜色）。无 Dart 代码逻辑改动，无数据迁移，回滚零风险。

**Tech Stack:** Android Vector Drawable XML / Material Design Green 800 (#2E7D32) / Flutter 测试（验证资源完整性）

**Spec:** [docs/superpowers/specs/2026-07-06-icon-redesign-design.md](file:///workspace/docs/superpowers/specs/2026-07-06-icon-redesign-design.md)

---

## File Structure

| 文件 | 改动类型 | 责任 |
|------|---------|------|
| `android/app/src/main/res/drawable/ic_launcher_foreground.xml` | 重写 | 圆环描边盘 + 中心实心碗剪影 path |
| `android/app/src/main/res/drawable/ic_launcher_background.xml` | 注释更新 | 加 M25 段说明背景不变 |
| `android/app/src/main/res/values/colors.xml` | 值修改 + 注释更新 | `ic_launcher_foreground` #6750A4 → #2E7D32 |
| `test/icon_assets_test.dart` | 断言更新 | M22 几何/颜色断言 → M25 几何/颜色断言 |
| `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` | 不变 | 已含 `<monochrome>` |
| `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml` | 不变 | 同上 |

---

## Task 1: 更新 colors.xml 主色值（紫 #6750A4 → 自然绿 #2E7D32）

**Files:**
- Modify: `android/app/src/main/res/values/colors.xml:7-11`

**为什么先做 colors.xml：** 颜色是 foundation，drawable 引用 `@color/ic_launcher_foreground`，先改颜色让后续 drawable 改动语义清晰。

- [ ] **Step 1: 修改 colors.xml 的 ic_launcher_foreground 值与注释**

将 `android/app/src/main/res/values/colors.xml` 第 7-11 行的 M22 注释段替换为 M25 注释段，颜色值 #6750A4 → #2E7D32。

**修改前（M22 注释 + 紫色值）：**
```xml
    <!-- M22：图标反转配色——白底 #FFFFFF + 紫前景 #6750A4（Google Camera 风）
         M15 暖橙纯色 → M17 紫橙渐变 → M20 紫橙渐变+Lens 风 → M22 白底紫前景（用户反馈「颜色丑、不像谷歌」重设计）
         白底最 Google 风，紫前景呼应 App 主题种子色，用户切主题色不影响图标识别 -->
    <color name="ic_launcher_background">#FFFFFF</color>
    <color name="ic_launcher_foreground">#6750A4</color>
```

**修改后（M25 注释 + 自然绿值，背景不变）：**
```xml
    <!-- M25：图标自然绿配色——白底 #FFFFFF + 自然绿前景 #2E7D32（对标 MyFitnessPal，紫色抑制食欲改绿）
         M15 暖橙纯色 → M17 紫橙渐变 → M20 紫橙渐变+Lens 风 → M22 白底紫前景 → M25 白底自然绿前景
         白底最衬托食物 App 语义，自然绿健康/平衡不抑制食欲，用户切主题色不影响图标识别 -->
    <color name="ic_launcher_background">#FFFFFF</color>
    <color name="ic_launcher_foreground">#2E7D32</color>
```

**注意：** `splash_background` 行不动（与图标独立）。`ic_launcher_background` 值 #FFFFFF 不变。

- [ ] **Step 2: 验证 colors.xml 语法**

Run: `head -20 android/app/src/main/res/values/colors.xml`
Expected: 看到 `<color name="ic_launcher_foreground">#2E7D32</color>` 且无 XML 语法错误

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/res/values/colors.xml
git commit -m "refactor(M25): 图标主色紫 #6750A4 → 自然绿 #2E7D32

对标 MyFitnessPal，紫色抑制食欲改自然绿
- Material Design Green 800，对比度 7.2:1（WCAG AAA）
- 健康语义（自然/平衡），不抑制食欲，契合「慢慢吃」理念
- 背景白 #FFFFFF 不变（M22 决策保留）"
```

---

## Task 2: 重写 ic_launcher_foreground.xml（四角 L + 碗 → 圆环盘 + 碗）

**Files:**
- Modify: `android/app/src/main/res/drawable/ic_launcher_foreground.xml`（整文件重写）

**几何参数（spec 3.3 节）：**
- 圆环描边盘：外径 56dp（半径 28），中心 (54,54)，描边 2.5dp round cap
  - path: `M26,54 A28,28 0 1 1 82,54 A28,28 0 1 1 26,54`
- 中心实心碗剪影：22×11dp，flat top y=48.5，curve bottom y=59.5
  - path: `M43,48.5 A11,11 0 0 1 65,48.5 Z`
- 比例：碗宽/盘径 = 22/56 = 0.393 ≈ 黄金分割 0.382

- [ ] **Step 1: 用 Write 工具整文件重写 ic_launcher_foreground.xml**

写入以下完整内容（注释 + 2 个 path）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  自适应图标前景：圆环描边盘 + 中心实心碗剪影（M25 重设计）。

  设计理念（M25 用户决策：对标 MyFitnessPal，自然绿 #2E7D32，盘+碗混合）：
  - 圆环描边盘 = 容器（MFP 核心结构语言，2.5dp round 描边精致克制）
  - 中心实心碗剪影 = 食物（保留 EatWise 碗语义，flat top + curve bottom）
  - 移除四角 L 形角标（M22 反馈"粗糙"，9 元素减为 2 元素更克制）
  - 自然绿 #2E7D32 替代紫色 #6750A4（紫色抑制食欲，绿色健康/平衡）

  设计哲学 "MyFitnessPal × Mindful Eating"：
  - 借鉴 MFP 圆盘容器语言（食物追踪 App 主流结构）
  - 描边盘而非实心盘——克制留白，契合"慢慢吃"
  - 实心碗作为焦点——视觉重量 1.5 vs 盘 1.0，焦点在食物

  画布 108×108dp，安全区 66×66（中心 54,54，半径 33）。
  M25 几何范围（前景 56dp span = 52% 画布，M22 是 36dp = 33%）：
  - 圆环描边盘：外径 56dp，描边 2.5dp round cap，中心 (54,54)
  - 中心实心碗：22dp wide × 11dp tall，flat top y=48.5，curve bottom y=59.5

  path 几何说明：
  - 圆环 path：M26,54 A28,28 0 1 1 82,54 A28,28 0 1 1 26,54
    起点 (26,54) 大弧到 (82,54) 上半圆，再大弧回 (26,54) 下半圆，闭合
  - 碗 path：M43,48.5 A11,11 0 0 1 65,48.5 Z
    左点 (43,48.5) 短弧顺时针到右点 (65,48.5)（sweep=1 = 下方半圆，碗底）
    Z 闭合（flat top = 碗口）

  比例依据（黄金分割）：
  - 碗宽/盘外径 = 22/56 = 0.393 ≈ 0.382
  - 碗高/碗宽 = 11/22 = 0.5（稳定比例）
  - 外留白/内留白 = 26/17 = 1.53 ≈ 1.618

  monochrome 兼容（Android 13+ 主题图标）：
  - 前景纯绿 alpha 通道，系统染色时白底被忽略
  - 圆环 + 实心碗剪影在染色后仍可识别（实心碗重量高于描边盘）

  M15 餐叉+餐刀 → M17 同心圆环 → M20 苹果圆+扫描线 → M22 碗剪影+四角L → M25 圆环描边盘+实心碗（用户反馈"紫色影响食欲、要对标 MFP"重设计）
-->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">

    <!-- 圆环描边盘（容器，外径 56dp，描边 2.5dp round cap，自然绿）：
         M26,54 起点（盘左点）
         A28,28 0 1 1 82,54 顺时针大弧到右点（上半圆）
         A28,28 0 1 1 26,54 顺时针大弧回左点（下半圆） -->
    <path
        android:strokeColor="@color/ic_launcher_foreground"
        android:strokeWidth="2.5"
        android:strokeLineCap="round"
        android:pathData="M26,54 A28,28 0 1 1 82,54 A28,28 0 1 1 26,54" />

    <!-- 中心实心碗剪影（22×11dp，flat top y=48.5，curve bottom y=59.5，自然绿填充）：
         M43,48.5 左点（碗口左端）
         A11,11 0 0 1 65,48.5 顺时针短弧到右点（sweep=1 = 下方半圆，碗底）
         Z 闭合（flat top = 碗口） -->
    <path
        android:fillColor="@color/ic_launcher_foreground"
        android:pathData="M43,48.5 A11,11 0 0 1 65,48.5 Z" />
</vector>
```

- [ ] **Step 2: 验证 XML 语法**

Run: `head -50 android/app/src/main/res/drawable/ic_launcher_foreground.xml`
Expected: 看到完整 XML 结构，2 个 `<path>` 元素，path data 含 `M26,54` 和 `M43,48.5`

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/res/drawable/ic_launcher_foreground.xml
git commit -m "refactor(M25): 图标前景四角L+碗 → 圆环描边盘+实心碗

对标 MyFitnessPal 圆盘容器语言
- 9 元素（8 L 角标 + 1 碗）减为 2 元素（1 圆环 + 1 碗）
- 圆环描边盘外径 56dp + 描边 2.5dp round cap
- 中心实心碗 22×11dp（黄金分割 22/56=0.393≈0.382）
- 0.5dp 网格对齐，48dp 缩放描边 1.11dp ≥1dp 阈值"
```

---

## Task 3: 更新 ic_launcher_background.xml 注释（加 M25 段）

**Files:**
- Modify: `android/app/src/main/res/drawable/ic_launcher_background.xml:2-11`

**说明：** 背景纯白 #FFFFFF 不变（M22 决策保留），仅更新注释加入 M25 段说明演进历史。

- [ ] **Step 1: 用 Edit 工具更新注释段**

将 `android/app/src/main/res/drawable/ic_launcher_background.xml` 第 2-11 行的注释替换。

**修改前（M22 注释）：**
```xml
<!--
  自适应图标背景：纯白 #FFFFFF（M22 反转配色重设计）。

  选色理由（M22 用户决策：白底+紫前景，Google Camera 风）：
  - 纯白背景最 Google 风（Google Camera/Lens 都是白底深前景）
  - 白底高对比衬托紫色前景，缩放到 48dp 仍清晰
  - 用户切 App 主题色不影响图标（图标独立配色，不跟主题变）

  M15 暖橙纯色 → M17 紫橙渐变 → M20 紫橙渐变+Lens 风 → M22 白底纯色（用户反馈「颜色丑、不像谷歌」重设计）
-->
```

**修改后（M25 注释，背景不变）：**
```xml
<!--
  自适应图标背景：纯白 #FFFFFF（M22 决策，M25 保留不变）。

  选色理由：
  - 纯白背景最衬托自然绿前景（MFP 同策略：白底深前景）
  - 白底高对比，缩放到 48dp 仍清晰
  - 用户切 App 主题色不影响图标（图标独立配色，不跟主题变）

  M15 暖橙纯色 → M17 紫橙渐变 → M20 紫橙渐变+Lens 风 → M22 白底纯色 → M25 白底纯色（不变，前景改自然绿）
-->
```

**注意：** `<vector>` 和 `<path>` 标签不动，仅改注释。

- [ ] **Step 2: 验证 XML 语法**

Run: `cat android/app/src/main/res/drawable/ic_launcher_background.xml`
Expected: 看到更新后注释 + 不变的 vector/path 结构

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/res/drawable/ic_launcher_background.xml
git commit -m "docs(M25): 图标背景注释更新加 M25 演进段

背景纯白 #FFFFFF 不变（M22 决策保留），仅注释加 M25 段
说明 M25 前景改自然绿但背景策略不变"
```

---

## Task 4: 更新 test/icon_assets_test.dart 断言（M22 → M25）

**Files:**
- Modify: `test/icon_assets_test.dart`（整文件重写断言）

**关键改动点（来自 spec 4.1 验证清单 + 现有测试分析）：**

现有测试（`test/icon_assets_test.dart`）硬编码了 M22 的几何与颜色，M25 改动后以下断言会失败：
1. **L24**: `contains('<color name="ic_launcher_foreground">#6750A4</color>')` → 改 #2E7D32
2. **L63**: `contains('android:pathData="M36,36')` → 改 M26,54（圆环盘起点）
3. **L69**: `contains('android:pathData="M42,48')` → 改 M43,48.5（碗起点）
4. **L20, L25**: reason 文本「M22 紫色」→ 「M25 自然绿」
5. **L60, L66, L75, L79, L86**: reason 文本「M22」→ 「M25」
6. **L11, L57**: group/test 名称「M22」→ 「M25」
7. **L7-8**: 文件头注释演进历史加 M25 段

M22 旧几何不应存在的断言（L92 `M33,54` / L98 `M44,54` / L104 `M29,29`）M25 仍满足（不会引入这些），保留即可。新增 M22 旧几何不应存在的断言：`M36,36`（M22 四角 L 起点）和 `M42,48`（M22 碗起点）。

- [ ] **Step 1: 用 Write 工具整文件重写 test/icon_assets_test.dart**

写入以下完整内容：

```dart
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
```

- [ ] **Step 2: 运行测试验证通过**

Run: `flutter test test/icon_assets_test.dart`
Expected: All tests passed（6 个测试全过）

**注意：** 沙箱可能因 sqlite3 native 库下载失败，重试通常能过。如持续失败，手动检查测试输出确认是网络问题而非断言失败。

- [ ] **Step 3: Commit**

```bash
git add test/icon_assets_test.dart
git commit -m "test(M25): 图标资源完整性断言更新 M22 → M25

- 颜色断言：#6750A4 紫 → #2E7D32 自然绿
- path 断言：M36,36 四角L → M26,54 圆环盘；M42,48 → M43,48.5（0.5dp 对齐）
- 新增 isNot 断言：M22 旧几何 M36,36/M42,48 不应存在
- group/test 名称 M22 → M25，reason 文本更新"
```

---

## Task 5: 全量验证（flutter analyze + flutter test + 6 硬约束）

**Files:**
- 无文件改动，仅运行验证命令

- [ ] **Step 1: flutter analyze 验证 No issues**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: flutter test 验证 1038 passed（0 回归）**

Run: `flutter test`
Expected: `All tests passed` + 总数 1038（基线 1038，本任务无新增测试，icon_assets_test 仍是 6 个测试）

**注意：** 沙箱 sqlite3 下载可能失败，重试 1-2 次通常能过。

- [ ] **Step 3: grep 验证颜色资源引用全部命中**

Run: `grep -r "@color/ic_launcher_foreground" android/app/src/main/res/`
Expected: 所有引用都能在 `values/colors.xml` 找到定义（ic_launcher_foreground.xml + ic_launcher_background.xml 不引用 foreground，仅 foreground.xml 引用）

Run: `grep -r "@color/ic_launcher_background" android/app/src/main/res/`
Expected: ic_launcher_background.xml 引用 + values/colors.xml 定义

- [ ] **Step 4: grep 验证 6 硬约束（图标改动不应影响）**

Run: `grep "isMinifyEnabled\|isShrinkResources" android/app/build.gradle.kts`
Expected: `isMinifyEnabled = false` + `isShrinkResources = false`

Run: `grep -r "SecureConfigStore.instance" lib/`
Expected: 无匹配（无 instance 静态属性）

Run: `grep -rn "initSentryAndRunApp" lib/main.dart`
Expected: 命名参数 `container:` + `app:`（不是位置参数）

**注意：** 图标改动不涉及 Dart 代码，6 硬约束应全部满足。如失败说明改动越界，需回查。

- [ ] **Step 5: 验证 mipmap-anydpi-v26 配置未变**

Run: `git diff HEAD~3 -- android/app/src/main/res/mipmap-anydpi-v26/`
Expected: 无 diff（M22 配置保留，M25 不改 adaptive-icon 文件）

- [ ] **Step 6: 如全量验证通过，无需 commit（本任务无文件改动）**

如全量验证失败，根据失败原因修复后回到对应 Task 重做。

---

## Task 6: 更新 CHANGELOG.md Unreleased 段（M25 图标精修完成）

**Files:**
- Modify: `CHANGELOG.md:5-7`

**说明：** CHANGELOG.md 当前 Unreleased 段是 `- M25 图标设计精修（进行中）`，完成后改为已完成描述。

- [ ] **Step 1: 用 Edit 工具更新 CHANGELOG.md Unreleased 段**

**修改前：**
```markdown
## [Unreleased]

- M25 图标设计精修（进行中）
```

**修改后：**
```markdown
## [Unreleased]

- M25 图标精修重设计：对标 MyFitnessPal，紫色 #6750A4 → 自然绿 #2E7D32，四角 L 角标 → 圆环描边盘（黄金分割比例 + 0.5dp 网格对齐）
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(M25): CHANGELOG Unreleased 段更新图标精修完成

进行中 → 已完成描述（对标 MFP + 自然绿 + 圆环盘）"
```

---

## Task 7: 更新 HANDOFF.md 第 2 节当前状态（M25 图标精修完成）

**Files:**
- Modify: `HANDOFF.md`（第 2 节"当前状态"段，加 M25 图标精修完成段）

**说明：** 按项目规则"会话结束必做 1. 更新 HANDOFF.md 第 2 节当前状态"。

- [ ] **Step 1: 用 Grep 定位 HANDOFF.md 第 2 节"当前状态"段**

Run: `grep -n "当前状态\|## 2" HANDOFF.md | head -10`
Expected: 找到第 2 节"当前状态"标题行号

- [ ] **Step 2: 用 Edit 工具在当前状态段加 M25 图标精修完成段**

在 v0.23.0+35 已发布段后或合适位置，加入 M25 图标精修完成段。具体内容由 Step 1 定位结果决定。

示例内容：
```markdown
### M25 图标精修重设计（已完成，未发版）
- 对标 MyFitnessPal 圆盘容器语言
- 配色：紫 #6750A4 → 自然绿 #2E7D32（紫色抑制食欲改绿）
- 结构：四角 L 角标 + 碗 → 圆环描边盘 + 实心碗（9 元素减为 2 元素）
- 几何：黄金分割比例（碗宽/盘径=0.393≈0.382）+ 0.5dp 网格对齐
- 改动：3 资源文件 + 1 测试文件，无 Dart 代码改动
- 验证：flutter analyze No issues / flutter test 1038 passed / 6 硬约束满足
- 状态：commit + push（不打 tag，不发版）
- 后续：本地真机验证图标显示（用户手动）
```

- [ ] **Step 3: Commit**

```bash
git add HANDOFF.md
git commit -m "docs(M25): HANDOFF 第 2 节加图标精修完成段

记录 M25 图标重设计完成状态（对标 MFP + 自然绿 + 圆环盘）"
```

---

## Task 8: Push 到远程（不打 tag，不发版）

**Files:**
- 无文件改动，仅 git push

**用户指令明确：** 「反复打磨，完了提交push不要打tag发布」

- [ ] **Step 1: 验证工作树 clean**

Run: `git status`
Expected: `nothing to commit, working tree clean`

- [ ] **Step 2: 查看待 push 的 commits**

Run: `git log origin/trae/agent-wX1X6Q..HEAD --oneline`
Expected: 看到 Task 1-7 的 6 个 commits（colors + foreground + background + test + changelog + handoff）

- [ ] **Step 3: Push 到远程**

Run: `git push origin trae/agent-wX1X6Q`
Expected: 推送成功，无 hook 错误

- [ ] **Step 4: 验证不打 tag**

Run: `git tag -l "v0.23*"`
Expected: 仅 v0.23.0（M25 不打新 tag）

**注意：** 如用户后续要求发版，再打 v0.24.0 tag + Release notes。本次严格执行「不打 tag」。

---

## Self-Review

**1. Spec coverage（spec 各节对应 task）：**

| Spec 节 | Task | 覆盖 |
|---------|------|------|
| 3.4.1 ic_launcher_foreground.xml | Task 2 | ✅ |
| 3.4.2 ic_launcher_background.xml | Task 3 | ✅ |
| 3.4.3 values/colors.xml | Task 1 | ✅ |
| 3.4.4 mipmap-anydpi-v26（不变） | Task 5 Step 5 验证 | ✅ |
| 3.5 monochrome 兼容 | Task 5 Step 5 验证不变 | ✅ |
| 4.1 验证清单 | Task 5 全量验证 | ✅ |
| 4.2 回归测试矩阵 | Task 4 + Task 5 Step 2 | ✅ |
| 4.4 6 硬约束自检 | Task 5 Step 4 | ✅ |
| 5 实施步骤 | Task 1-8 全覆盖 | ✅ |
| 7 交付物清单 | Task 1-3 + Task 5 Step 5 | ✅ |

**2. Placeholder 扫描：** ✅ 无 TBD/TODO，所有 step 含完整代码或命令

**3. Type consistency：** ✅
- 颜色值 #2E7D32 在 Task 1（colors.xml）、Task 4（测试断言）一致
- path `M26,54 A28,28 0 1 1 82,54 A28,28 0 1 1 26,54` 在 Task 2（foreground.xml）、Task 4（测试断言 `M26,54`）一致
- path `M43,48.5 A11,11 0 0 1 65,48.5 Z` 在 Task 2、Task 4 一致
- 描边 2.5dp 在 Task 2、Task 4 一致
- 颜色引用 `@color/ic_launcher_foreground` 在 Task 2、Task 4、Task 5 Step 3 一致

**4. 实施顺序合理性：**
- Task 1（colors.xml）先于 Task 2（foreground.xml）：drawable 引用颜色，先定义颜色让后续 drawable 改动语义清晰
- Task 2（foreground.xml）先于 Task 3（background.xml）：foreground 是核心改动，background 仅注释更新
- Task 4（测试）在 3 个资源文件改完后：测试断言基于最终文件状态
- Task 5（全量验证）在所有改动后：跑全量测试确认 0 回归
- Task 6/7（文档）在验证通过后：避免记录失败状态
- Task 8（push）最后：确保所有 commits 都验证过

无 issue，plan 可执行。
