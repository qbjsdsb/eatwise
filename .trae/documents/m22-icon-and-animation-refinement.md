# M22 图标精修 + 识别等待动画重构 实施计划

> **TDD 约定**：每个 Round 严格 Red→Green→Refactor。先写失败测试，跑测试确认失败原因正确，再写最小实现，跑测试确认通过。

## Goal

解决用户反馈的两类问题：(1) App 图标「还是丑、颜色丑、粗糙、太大、不像谷歌」；(2) 识别等待界面动画「不够好看精致 + 逻辑有问题（done 态瞬间消失、阶段切换无过渡、查库阶段闪太快、进度条跳跃）」。

## Architecture

- **图标**：白底 + 紫前景反转配色（Google Camera/Lens 风），前景从「四角粗 L + 苹果圆 + 扫描线」精修为「四角细 L（2.5dp round cap）+ 中心碗剪影」，前景范围从 50dp 收敛到 36dp（更精致更小）。
- **动画**：进度卡片用 AnimatedContainer（状态圆圈颜色过渡）+ AnimatedSwitcher（图标 morph）+ TweenAnimationBuilder（进度条平滑插值）实现丝滑过渡；controller 给查库阶段加 300ms 最小展示；page 在 done 后加 400ms 成功停留再跳转。

## Tech Stack

- Android Vector Drawable XML（图标）
- Flutter AnimatedContainer / AnimatedSwitcher / TweenAnimationBuilder（动画）
- Flutter widget test（TDD）

## Decisions（用户已确认）

1. **图标配色**：白底 #FFFFFF + 紫前景 #6750A4（反转，Google Camera 风）
2. **图标造型**：精修取景框 + 食物剪影（保留概念全面精修：描边 4→2.5dp、square→round 线帽、范围 50→36dp、中心圆改碗剪影、移除扫描线）
3. **动画逻辑**：4 个问题全修（done 停留 + 阶段过渡 + 查库最小展示 + 进度条平滑）

## Current State Analysis

### 图标现状（M20）
- `colors.xml`：bg=#6750A4（紫）、bg_end=#FF6E40（橙）、fg=#FFFFFF（白）—— 紫橙对角渐变
- `ic_launcher_background.xml`：108×108 全画布紫→橙 135° 对角线线性渐变
- `ic_launcher_foreground.xml`：四角 L（strokeWidth=4, square cap, 范围 29-79=50dp）+ 中心苹果圆（直径 20dp fill）+ 扫描线（strokeWidth=2）

### 动画现状（M20）
- `recognize_progress_card.dart`：StatelessWidget，4 阶段竖向列表 + 顶部 LinearProgressIndicator
  - `_StatusCircle`：switch-case 直接返回不同 Container（无动画）
  - 进度条 `value: completedCount/4`（整数跳跃，无插值）
  - done 态：4 勾全显，但无成功反馈动画
- `recognize_controller.dart`：lookupNutrition 阶段设 state 后立即查库（~200ms 即跳 done，用户看不到）
- `recognize_page.dart`：pickAndRecognize 返回 done 后立即跳转 CalibrationPage（done 态只闪一帧）

### 约束
- Seedream API 不可用（沙箱无 ARK_API_KEY，scripts/seedream_image_generate.py 不存在），参考图生成跳过，基于 Material 3 / Google 设计规范手工实现
- 6 条硬约束不变（build.gradle minify=false / meal_log FK / AI 三路径 / per100g 基于 mid / SecureConfigStore 无 instance / initSentryAndRunApp 命名参数）
- `recognize_progress_card.dart` 现有 10 个测试需适配动画（pumpAndSettle）

---

## Part A：图标精修

### 几何设计（108×108 画布，安全区 66×66，中心 54,54）

**背景**：纯白 #FFFFFF（移除渐变，移除 bg_end 颜色）

**前景**（#6750A4 紫，所有元素在半径 18 内，前景范围 36dp = 33% 画布）：

```
取景框四角 L（stroke 2.5dp, round cap, 每臂 8dp）：
  左上: M36,36 L44,36 M36,36 L36,44
  右上: M64,36 L72,36 M72,36 L72,44
  右下: M72,72 L64,72 M72,72 L72,64
  左下: M36,72 L44,72 M36,72 L36,64

中心碗剪影（fill, 半圆盘 flat top y=48 curve bottom y=60）：
  M42,48 A12,12 0 0 1 66,48 Z
```

**设计理由**：
- 描边 4→2.5dp + square→round：精致不粗糙（Google Material Symbols 标准描边）
- 范围 50→36dp：33% 画布填充（vs M20 的 46%），留白充足不显大
- 苹果圆→碗剪影：碗（半圆盘 flat top）比纯圆更可读为「食物/餐具」，且与取景框形成「扫描食物」隐喻
- 移除扫描线：静态线不传达动态，且增加视觉杂乱
- 白底紫前景：最 Google 风（Google Camera/Lens 都是白底深前景），用户切主题色不影响图标

---

### Task A1：更新 colors.xml（反转配色）

**Files:**
- Modify: `android/app/src/main/res/values/colors.xml`
- Modify: `android/app/src/main/res/values-night/colors.xml`
- Test: `test/icon_assets_test.dart`

- [ ] **Step 1：写失败测试（更新 icon_assets_test.dart 颜色断言）**

替换 `test/icon_assets_test.dart` 中的颜色断言（M20 紫橙渐变 → M22 白底紫前景）：

```dart
// 把 group 名改为 M22
group('图标资源完整性 (M22)', () {
  const androidResDir = 'android/app/src/main/res';

  test('colors.xml 含 ic_launcher_background 白色（M22 白底反转）', () {
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

  // ... 其余 test 见 Task A2/A3
```

- [ ] **Step 2：跑测试确认失败**

Run: `export PATH=/tmp/flutter/bin:$PATH && flutter test test/icon_assets_test.dart`
Expected: FAIL —— colors.xml 仍是 #6750A4（紫）/ #FFFFFF（白前景），断言期望 #FFFFFF（白底）/ #6750A4（紫前景）不匹配

- [ ] **Step 3：更新 colors.xml（亮色）**

`android/app/src/main/res/values/colors.xml`：
```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="splash_background">#FCF9F9</color>
    <!-- M22：图标反转配色——白底 #FFFFFF + 紫前景 #6750A4（Google Camera 风）
         M15 暖橙纯色 → M17 紫橙渐变 → M20 紫橙渐变+Lens 风 → M22 白底紫前景（用户反馈「颜色丑、不像谷歌」重设计）
         白底最 Google 风，紫前景呼应 App 主题种子色，用户切主题色不影响图标识别 -->
    <color name="ic_launcher_background">#FFFFFF</color>
    <color name="ic_launcher_foreground">#6750A4</color>
</resources>
```

- [ ] **Step 4：更新 colors.xml（暗色）**

`android/app/src/main/res/values-night/colors.xml`：
```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="splash_background">#1C1B1F</color>
    <!-- M22：暗色模式图标与亮色一致（自适应图标不随主题变，白底紫前景） -->
    <color name="ic_launcher_background">#FFFFFF</color>
    <color name="ic_launcher_foreground">#6750A4</color>
</resources>
```

- [ ] **Step 5：跑测试确认通过**

Run: `flutter test test/icon_assets_test.dart`
Expected: PASS（颜色断言部分）

---

### Task A2：更新 ic_launcher_background.xml（移除渐变改纯色）

**Files:**
- Modify: `android/app/src/main/res/drawable/ic_launcher_background.xml`
- Test: `test/icon_assets_test.dart`

- [ ] **Step 1：写失败测试（更新背景断言）**

在 `test/icon_assets_test.dart` 的 M22 group 内加：

```dart
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
```

- [ ] **Step 2：跑测试确认失败**

Run: `flutter test test/icon_assets_test.dart`
Expected: FAIL —— 背景仍是 `<gradient>` 渐变，断言期望 `fillColor` 纯色

- [ ] **Step 3：更新 ic_launcher_background.xml**

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  自适应图标背景：纯白 #FFFFFF（M22 反转配色重设计）。

  选色理由（M22 用户决策：白底+紫前景，Google Camera 风）：
  - 纯白背景最 Google 风（Google Camera/Lens 都是白底深前景）
  - 白底高对比衬托紫色前景，缩放到 48dp 仍清晰
  - 用户切 App 主题色不影响图标（图标独立配色，不跟主题变）

  M15 暖橙纯色 → M17 紫橙渐变 → M20 紫橙渐变+Lens 风 → M22 白底纯色（用户反馈「颜色丑、不像谷歌」重设计）
-->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">

    <path
        android:pathData="M0,0 h108 v108 h-108 z"
        android:fillColor="@color/ic_launcher_background" />
</vector>
```

- [ ] **Step 4：跑测试确认通过**

Run: `flutter test test/icon_assets_test.dart`
Expected: PASS（背景断言部分）

---

### Task A3：更新 ic_launcher_foreground.xml（精修取景框 + 碗剪影）

**Files:**
- Modify: `android/app/src/main/res/drawable/ic_launcher_foreground.xml`
- Test: `test/icon_assets_test.dart`

- [ ] **Step 1：写失败测试（更新前景几何断言）**

在 `test/icon_assets_test.dart` 的 M22 group 内加：

```dart
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
  // ... 保留 M20 既有断言（不变）
  final file = File('$androidResDir/mipmap-anydpi-v26/ic_launcher_round.xml');
  expect(file.existsSync(), true);
  final content = file.readAsStringSync();
  expect(content, contains('<background android:drawable="@drawable/ic_launcher_background" />'));
  expect(content, contains('<foreground android:drawable="@drawable/ic_launcher_foreground" />'));
  expect(content, contains('<monochrome android:drawable="@drawable/ic_launcher_foreground" />'));
});

test('AndroidManifest.xml 含 android:roundIcon 声明', () {
  // ... 保留 M20 既有断言（不变）
});

test('5 个 mipmap 密度都有 ic_launcher.png 和 ic_launcher_round.png', () {
  // ... 保留 M20 既有断言（不变，PNG fallback 不变）
});
```

- [ ] **Step 2：跑测试确认失败**

Run: `flutter test test/icon_assets_test.dart`
Expected: FAIL —— 前景仍是 M20 几何（M29,29 / M44,54 / M33,54 / strokeWidth=4 / square）

- [ ] **Step 3：更新 ic_launcher_foreground.xml**

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  自适应图标前景：精修取景框 + 中心碗剪影（M22 重设计）。

  设计理念（M22 用户决策：白底+紫前景反转，精修取景框+食物）：
  - 四角 L 形角标 = 取景框（拍照识别核心功能），2.5dp round 描边精致不粗糙
  - 中心碗剪影 = 食物（半圆盘 flat top + curve bottom，比 M20 苹果圆更可读为「食物/餐具」）
  - 移除扫描线（静态线不传达动态，增加视觉杂乱）
  - 紫前景 #6750A4 在白底上高对比，呼应 App 主题种子色

  设计哲学 "Google Camera × Mindful Eating"：
  - 借鉴 Google Camera/Lens 的白底+深前景配色（最 Google 风）
  - 取景框语言传达「AI 扫描识别」
  - 碗剪影传达「食物/慢慢吃」

  画布 108×108dp，安全区 66×66（中心 54,54，半径 33）。
  M22 几何范围（前景 36dp span = 33% 画布，M20 是 50dp = 46%，M22 更小更精致留白足）：
  - 四角 L 形角标：每角 8×8dp，描边 2.5dp round cap，位于 (36,36)-(72,72) 取景框四角
  - 中心碗剪影：半圆盘 24dp wide × 12dp tall，flat top y=48，curve bottom y=60，中心 (54,54)

  path 几何说明：
  - 四角 L path：8 条线段（每角 2 条），strokeColor 紫 2.5dp round cap
    左上：M36,36→L44,36 + M36,36→L36,44
    右上：M64,36→L72,36 + M72,36→L72,44
    右下：M72,72→L64,72 + M72,72→L72,64
    左下：M36,72→L44,72 + M36,72→L36,64
  - 碗剪影 path：从 (42,48) 画半圆顺时针到 (66,48)（A12,12 sweep=1 = 下方半圆），Z 闭合
    flat top = 碗口，curve bottom = 碗底，reads as 碗/食物容器

  monochrome 兼容（Android 13+ 主题图标）：
  - 前景纯紫 alpha 通道，系统染色时白底被忽略，前景独立可识别（四角 L + 碗的剪影）

  M15 餐叉+餐刀 → M17 同心圆环 → M20 苹果圆+扫描线 → M22 碗剪影（用户反馈「还是丑、粗糙、太大、不像谷歌」重设计）
-->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">

    <!-- 四角 L 形角标（取景框，每角 8×8dp，紫色描边 2.5dp，round 线帽）：
         M36,36 起点（左上角虚拟直角点）
         8 条线段分别画 4 个角的 L 形 -->
    <path
        android:strokeColor="@color/ic_launcher_foreground"
        android:strokeWidth="2.5"
        android:strokeLineCap="round"
        android:pathData="M36,36 L44,36 M36,36 L36,44 M64,36 L72,36 M72,36 L72,44 M72,72 L64,72 M72,72 L72,64 M36,72 L44,72 M36,72 L36,64" />

    <!-- 中心碗剪影（半圆盘 24×12dp，flat top y=48，curve bottom y=60，紫色填充）：
         M42,48 左点（碗口左端）
         A12,12 0 0 1 66,48 顺时针画下半圆到右点（sweep=1 = 下方弧，碗底）
         Z 闭合（flat top = 碗口） -->
    <path
        android:fillColor="@color/ic_launcher_foreground"
        android:pathData="M42,48 A12,12 0 0 1 66,48 Z" />
</vector>
```

- [ ] **Step 4：跑测试确认通过**

Run: `flutter test test/icon_assets_test.dart`
Expected: PASS（全部图标断言）

- [ ] **Step 5：跑 flutter analyze 确认无 lint 错误**

Run: `flutter analyze`
Expected: No issues

---

## Part B：识别等待动画重构

### Task B1：进度卡片进度条平滑插值（TweenAnimationBuilder）

**Files:**
- Modify: `lib/features/recognize/recognize_progress_card.dart`
- Modify: `test/features/recognize_progress_card_test.dart`

- [ ] **Step 1：写失败测试（验证进度条用 TweenAnimationBuilder 包裹）**

在 `test/features/recognize_progress_card_test.dart` 既有 group 内加新 group：

```dart
group('RecognizeProgressCard 动画（M22）', () {
  testWidgets('进度条用 TweenAnimationBuilder 平滑插值', (tester) async {
    await tester.pumpWidget(wrap(const RecognizeProgressCard(
      currentState: RecognizeState.preprocessing,
    )));
    // 应存在 TweenAnimationBuilder 包裹 LinearProgressIndicator
    expect(find.byType(TweenAnimationBuilder), findsWidgets);
    // pumpAndSettle 让动画到达终值
    await tester.pumpAndSettle();
    final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(progress.value, 0.25);
  });

  testWidgets('done 态显示成功反馈图标（M22 新增）', (tester) async {
    await tester.pumpWidget(wrap(const RecognizeProgressCard(
      currentState: RecognizeState.done,
    )));
    await tester.pumpAndSettle();
    // done 态除了 4 个阶段勾，还应有一个成功反馈图标（Icons.check_circle）
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('状态圆圈用 AnimatedContainer 颜色过渡', (tester) async {
    await tester.pumpWidget(wrap(const RecognizeProgressCard(
      currentState: RecognizeState.preprocessing,
    )));
    // 应存在 AnimatedContainer（状态圆圈颜色过渡）
    expect(find.byType(AnimatedContainer), findsWidgets);
  });
});
```

- [ ] **Step 2：跑测试确认失败**

Run: `flutter test test/features/recognize_progress_card_test.dart`
Expected: FAIL —— 当前卡片无 TweenAnimationBuilder / AnimatedContainer / done 态无 check_circle

- [ ] **Step 3：更新既有测试加 pumpAndSettle**

既有 10 个测试中，凡检查 `progress.value` 的，在 `pumpWidget` 后加 `await tester.pumpAndSettle();`（因 TweenAnimationBuilder 首帧从 begin=0 开始，需 settle 到 end）。具体：
- 'pickingImage' 测试：加 pumpAndSettle，progress.value 仍 0.0
- 'preprocessing' 测试：加 pumpAndSettle，progress.value 0.25
- 'recognizing' 测试：加 pumpAndSettle，progress.value 0.5
- 'lookupNutrition' 测试：加 pumpAndSettle，progress.value 0.75
- 'done' 测试：加 pumpAndSettle，progress.value 1.0
- 'idle' 测试：加 pumpAndSettle，progress.value 0.0

- [ ] **Step 4：重写 recognize_progress_card.dart（加动画）**

完整重写 `lib/features/recognize/recognize_progress_card.dart`：

```dart
import 'package:flutter/material.dart';

import 'recognize_controller.dart';

/// 识别进度卡片（M20 创建，M22 动画重构）
///
/// M22 改进：
/// - 进度条 TweenAnimationBuilder 平滑插值（不再 25% 整数跳跃）
/// - 状态圆圈 AnimatedContainer 颜色过渡 + AnimatedSwitcher 图标 morph
/// - done 态新增成功反馈图标（check_circle scale-in 弹性动画）
/// - 卡片 elevation 0 + surfaceContainerHigh（M3 tonal，更现代）
///
/// 监听 [RecognizeState]，展示 4 阶段进度：
/// 1. 选图（pickingImage）2. 压缩（preprocessing）
/// 3. AI 推理（recognizing）4. 查库回填（lookupNutrition）
class RecognizeProgressCard extends StatelessWidget {
  final RecognizeState currentState;

  const RecognizeProgressCard({super.key, required this.currentState});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 特殊状态：error / queued 不展示 4 阶段
    if (currentState == RecognizeState.error) {
      return _SpecialCard(
        color: cs.error,
        icon: Icons.error_outline,
        text: '识别失败',
      );
    }
    if (currentState == RecognizeState.queued) {
      return _SpecialCard(
        color: cs.primary,
        icon: Icons.cloud_off_outlined,
        text: '已加入离线队列，将在网络恢复后识别',
      );
    }

    final stages = _stageConfig(currentState);
    final completedCount =
        stages.where((s) => s.status == _StageStatus.done).length;
    final isDone = currentState == RecognizeState.done;

    return Card(
      elevation: 0, // M22：M3 tonal，无阴影更现代
      color: cs.surfaceContainerHigh, // M22：tonal surface 替代 elevation
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // M22：TweenAnimationBuilder 平滑插值进度条
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: completedCount / 4),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(cs.primary),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 4 阶段竖向列表（_StageRow 内部用 AnimatedContainer + AnimatedSwitcher）
            for (final stage in stages) _StageRow(stage: stage),
            // M22：done 态成功反馈（弹性 scale-in check_circle）
            if (isDone) ...[
              const SizedBox(height: 12),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1.0),
                duration: const Duration(milliseconds: 400),
                curve: Curves.elasticOut,
                builder: (context, scale, _) => Transform.scale(
                  scale: scale,
                  child: Icon(
                    Icons.check_circle,
                    color: cs.primary,
                    size: 32,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static List<_Stage> _stageConfig(RecognizeState current) {
    const order = [
      RecognizeState.pickingImage,
      RecognizeState.preprocessing,
      RecognizeState.recognizing,
      RecognizeState.lookupNutrition,
    ];
    if (current == RecognizeState.done) {
      return order
          .map((s) => _Stage(state: s, status: _StageStatus.done))
          .toList();
    }
    if (current == RecognizeState.idle) {
      return order
          .map((s) => _Stage(state: s, status: _StageStatus.pending))
          .toList();
    }
    final currentIdx = order.indexOf(current);
    return order.asMap().entries.map((e) {
      final idx = e.key;
      final state = e.value;
      final status = idx < currentIdx
          ? _StageStatus.done
          : idx == currentIdx
              ? _StageStatus.active
              : _StageStatus.pending;
      return _Stage(state: state, status: status);
    }).toList();
  }
}

/// 单行阶段（M22：状态圆圈用 AnimatedContainer + AnimatedSwitcher 平滑过渡）
class _StageRow extends StatelessWidget {
  final _Stage stage;

  const _StageRow({required this.stage});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = stage.status == _StageStatus.active;
    final isDone = stage.status == _StageStatus.done;
    final fontWeight =
        (isActive || isDone) ? FontWeight.bold : FontWeight.normal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // M22：AnimatedContainer 颜色过渡 + AnimatedSwitcher 图标 morph
          _StatusCircle(status: stage.status, colorScheme: cs),
          const SizedBox(width: 12),
          Text(stage.text, style: TextStyle(fontWeight: fontWeight)),
          const Spacer(),
          Icon(stage.icon, size: 18, color: cs.outline),
        ],
      ),
    );
  }
}

/// 状态圆圈（M22：AnimatedContainer 颜色/描边过渡 + AnimatedSwitcher 图标 morph）
class _StatusCircle extends StatelessWidget {
  final _StageStatus status;
  final ColorScheme colorScheme;

  const _StatusCircle({required this.status, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    const size = 28.0;
    final isActive = status == _StageStatus.active;
    final isDone = status == _StageStatus.done;
    // pending: 透明填充 + 灰描边；active/done: 紫填充 + 紫描边
    final fillColor = (isActive || isDone)
        ? colorScheme.primary
        : Colors.transparent;
    final borderColor =
        (isActive || isDone) ? colorScheme.primary : colorScheme.outline;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fillColor,
        border: Border.all(color: borderColor, width: 2),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: _buildChild(),
      ),
    );
  }

  Widget _buildChild() {
    switch (status) {
      case _StageStatus.pending:
        return const SizedBox.shrink(key: ValueKey('pending'));
      case _StageStatus.active:
        return const Padding(
          key: ValueKey('active'),
          padding: EdgeInsets.all(5),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(Colors.white),
          ),
        );
      case _StageStatus.done:
        return const Icon(
          key: ValueKey('done'),
          Icons.check,
          size: 18,
          color: Colors.white,
        );
    }
  }
}

/// 特殊状态卡片（error / queued）—— M20 既有，不变
class _SpecialCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _SpecialCard({
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

enum _StageStatus { pending, active, done }

class _Stage {
  final RecognizeState state;
  final _StageStatus status;

  const _Stage({required this.state, required this.status});

  String get text {
    switch (state) {
      case RecognizeState.pickingImage:
        return '选图中…';
      case RecognizeState.preprocessing:
        return '压缩图中…';
      case RecognizeState.recognizing:
        return 'AI 推理中…';
      case RecognizeState.lookupNutrition:
        return '查库回填中…';
      default:
        return '';
    }
  }

  IconData get icon {
    switch (state) {
      case RecognizeState.pickingImage:
        return Icons.camera_alt_outlined;
      case RecognizeState.preprocessing:
        return Icons.compress_outlined;
      case RecognizeState.recognizing:
        return Icons.center_focus_strong_outlined;
      case RecognizeState.lookupNutrition:
        return Icons.storage_outlined;
      default:
        return Icons.circle_outlined;
    }
  }
}
```

- [ ] **Step 5：跑测试确认通过**

Run: `flutter test test/features/recognize_progress_card_test.dart`
Expected: PASS（全部 13 测试：10 既有 + 3 新增）

---

### Task B2：查库阶段最小展示时长（controller 300ms dwell）

**Files:**
- Modify: `lib/features/recognize/recognize_controller.dart`
- Test: `test/features/recognize_controller_test.dart`（既有文件，加测试）

- [ ] **Step 1：写失败测试**

在 `test/features/recognize_controller_test.dart` 既有文件内加测试（若文件不存在则创建）：

```dart
test('lookupMinDwell 常量存在且为 300ms（M22 查库最小展示）', () {
  // M22：查库阶段最小展示 300ms，避免 UI 闪烁
  expect(
    RecognizeController.lookupMinDwell,
    const Duration(milliseconds: 300),
    reason: '查库阶段应最小展示 300ms，避免 lookupNutrition 闪太快',
  );
});
```

- [ ] **Step 2：跑测试确认失败**

Run: `flutter test test/features/recognize_controller_test.dart`
Expected: FAIL —— `RecognizeController.lookupMinDwell` 不存在

- [ ] **Step 3：在 recognize_controller.dart 加常量 + dwell 延迟**

在 `RecognizeController` class 内（`_minInterval` 常量附近）加：

```dart
  // M22：查库阶段最小展示时长，避免 lookupNutrition state 闪太快（DB lookup ~200ms）
  // 设 state 后延迟 300ms 再查库，让用户看到「查库回填中…」阶段
  @visibleForTesting
  static const lookupMinDwell = Duration(milliseconds: 300);
```

在 `pickAndRecognize` 方法内，设 `lookupNutrition` state 后（line 308-312 附近），查库前加延迟：

```dart
      // 查库回填营养素
      state = state.copyWith(
        state: RecognizeState.lookupNutrition,
        recognitionResult: result,
        imagePath: xFile.path,
      );
      // M22：查库阶段最小展示，避免 UI 闪烁（DB lookup ~200ms 会闪过）
      await Future.delayed(lookupMinDwell);

      // 主菜查库回填（既有代码不变）
      NutritionResult? mainSingle;
      // ...
```

- [ ] **Step 4：跑测试确认通过**

Run: `flutter test test/features/recognize_controller_test.dart`
Expected: PASS

- [ ] **Step 5：跑全部 controller 测试确认无回归**

Run: `flutter test test/features/recognize_controller_test.dart`
Expected: PASS（既有测试 + 新增测试）

---

### Task B3：done 态成功停留（page 400ms dwell）

**Files:**
- Modify: `lib/features/recognize/recognize_page.dart`
- Test: `test/features/recognize_page_test.dart`（既有文件，加测试）

- [ ] **Step 1：写失败测试**

在 `test/features/recognize_page_test.dart` 既有文件内加测试（若文件不存在则创建）：

```dart
test('doneSuccessDwell 常量存在且为 400ms（M22 done 成功停留）', () {
  // M22：done 态成功停留 400ms，让用户看到完成反馈再跳转
  expect(
    RecognizePage.doneSuccessDwell,
    const Duration(milliseconds: 400),
    reason: 'done 态应停留 400ms 让用户看到成功反馈，不再瞬间消失',
  );
});
```

- [ ] **Step 2：跑测试确认失败**

Run: `flutter test test/features/recognize_page_test.dart`
Expected: FAIL —— `RecognizePage.doneSuccessDwell` 不存在

- [ ] **Step 3：在 recognize_page.dart 加常量 + dwell 延迟**

在 `RecognizePage` class 内（`writeCalibratedMealLog` 静态方法附近）加常量：

```dart
  /// M22：done 态成功停留时长，让用户看到完成反馈动画再跳转校准页
  @visibleForTesting
  static const doneSuccessDwell = Duration(milliseconds: 400);
```

在 `_pickAndRecognize` 方法内，`if (state.state == RecognizeState.done && ...)` 分支内，导航前加延迟：

```dart
      if (state.state == RecognizeState.done &&
          state.recognitionResult != null) {
        // M22：done 态成功停留，让用户看到 4 阶段全勾 + 成功反馈动画再跳转
        await Future.delayed(doneSuccessDwell);
        if (!mounted) return;
        // 持久化原图（既有代码）
        if (state.imagePath != null) {
          // ...
```

- [ ] **Step 4：跑测试确认通过**

Run: `flutter test test/features/recognize_page_test.dart`
Expected: PASS

---

### Task B4：跑全部测试 + analyze 验证无回归

- [ ] **Step 1：跑 flutter analyze**

Run: `export PATH=/tmp/flutter/bin:$PATH && flutter analyze`
Expected: No issues

- [ ] **Step 2：跑全部测试**

Run: `flutter test`
Expected: All pass（图标测试 + 卡片测试 + controller 测试 + page 测试 + 既有全部测试）

注：若 sqlite3 native 库下载失败（沙箱网络问题），重试通常能过。

---

## Assumptions & Decisions

1. **Seedream 参考图跳过**：沙箱无 ARK_API_KEY，无法生成参考图。基于 Material 3 / Google Camera 设计规范手工实现几何，用户批准后执行。
2. **图标几何**：碗剪影用半圆盘（flat top + curve bottom），fills 紫色。比 M20 苹果圆更可读为「食物容器」。
3. **PNG fallback 不重新生成**：mipmap-{density}/ic_launcher.png 是 M15 旧 PNG，自适应图标（anydpi-v26）优先级更高，PNG 仅极旧设备 fallback。M22 只改 vector drawable + colors.xml，PNG 不动（用户未反馈 PNG 问题，且沙箱无 ImageMagick/Android 工具链重新生成）。
4. **动画测试用 pumpAndSettle**：TweenAnimationBuilder/AnimatedContainer 首帧从 begin 开始，需 pumpAndSettle 到终值再断言。既有 10 个测试加 pumpAndSettle 适配。
5. **碗剪影不可读风险**：若用户反馈半圆盘仍不像碗，可加碗口横线（rim stroke）或改用 fork+knife。M22 先用半圆盘（最简洁），保留迭代空间。
6. **查库 dwell 不影响识别速度感知**：300ms 延迟在查库前，用户看到「查库回填中…」→ 等 300ms → 查库完成 → done。总延迟 +300ms 可接受（识别本身 2-5s）。
7. **done dwell 不阻塞跳转**：400ms 延迟在 done state 后、导航前。用户看到 4 勾 + check_circle 弹性动画 → 跳转校准页。400ms 可接受。

## Verification

1. `flutter test test/icon_assets_test.dart` —— 图标颜色/几何断言全过
2. `flutter test test/features/recognize_progress_card_test.dart` —— 卡片动画测试全过（10 既有 + 3 新增）
3. `flutter test test/features/recognize_controller_test.dart` —— lookupMinDwell 常量测试 + 既有
4. `flutter test test/features/recognize_page_test.dart` —— doneSuccessDwell 常量测试 + 既有
5. `flutter analyze` —— 无 lint 错误
6. `flutter test` —— 全部测试通过无回归
7. 手动验证（用户侧）：安装 APK 看启动器图标（白底紫前景取景框+碗），拍照识别看等待动画（进度条平滑插值 + 状态圆圈颜色过渡 + 查库阶段可见 + done 成功反馈）

## 硬约束检查

- [x] build.gradle minify/shrink 不动（M22 不碰 build.gradle）
- [x] meal_log.food_item_id 非空外键不碰（M22 不碰 DB 层）
- [x] AI 三路径不碰（M22 不碰 recognize_controller 的容灾逻辑，只加 lookupMinDwell 延迟）
- [x] per100g 基于 estimatedWeightGMid 不碰
- [x] SecureConfigStore 无 instance 不碰
- [x] initSentryAndRunApp 命名参数不碰
