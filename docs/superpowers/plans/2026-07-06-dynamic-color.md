# EatWise 主题动态取色（Material You）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 EatWise 主题跟随 Android 12+ 系统壁纸取色（Material You），开关优先 + Switch 与色板硬互斥，minSdk 提升到 31。

**Architecture:** dynamic_color 包 + DynamicColorBuilder 包裹 MaterialApp.router，三态决策（动态色可用/不可用/开关关闭）。新增 `useDynamicColorProvider`（bool）+ SecureConfigStore 持久化 key `use_dynamic_color`。main.dart 启动期 `Future.wait` 并行读 themeSeed + useDynamicColor。

**Tech Stack:** dynamic_color ^1.7.0 / Riverpod NotifierProvider / flutter_secure_storage / Android API 31+

**Spec:** [docs/superpowers/specs/2026-07-06-dynamic-color-design.md](file:///workspace/docs/superpowers/specs/2026-07-06-dynamic-color-design.md)

---

## File Structure

| 文件 | 改动类型 | 责任 |
|------|---------|------|
| `pubspec.yaml` | 加依赖 | `dynamic_color: ^1.7.0` |
| `android/app/build.gradle.kts` | 值修改 | minSdk = flutter.minSdkVersion → 31 |
| `lib/core/theme/theme_controller.dart` | 新增 Provider | `UseDynamicColorNotifier` + `useDynamicColorProvider` |
| `lib/core/config/secure_config_store.dart` | 新增方法 | `getUseDynamicColor` / `setUseDynamicColor` |
| `lib/main.dart` | 修改启动期 | `Future.wait` 并行读 themeSeed + useDynamicColor |
| `lib/app.dart` | 改造 build | `DynamicColorBuilder` 包裹 + 三态决策 |
| `lib/features/settings/settings_page.dart` | 加 UI + 改色板 | SwitchListTile + Opacity/AbsorbPointer 硬互斥 |
| `test/core/theme_controller_test.dart` | 新增 | Provider 单测 |
| `test/core/secure_config_store_dynamic_color_test.dart` | 新增 | Store 读写单测 |
| `test/app_dynamic_color_test.dart` | 新增 | Widget 三态决策测试 |
| `test/features/settings_backup_overdue_test.dart` | 修改 | 补 `getUseDynamicColor()` stub |
| `HANDOFF.md` | 更新 | 加第 7 条硬约束 + M25 动态取色段 |
| `CHANGELOG.md` | 更新 | Unreleased 段加动态取色 |

---

## Task 1: pubspec.yaml 加 dynamic_color 依赖

**Files:**
- Modify: `pubspec.yaml`（dependencies 块）

- [ ] **Step 1: 用 Edit 工具在 dependencies 块加 dynamic_color**

在 `pubspec.yaml` 的 `dependencies:` 块内，`flutter_riverpod` 之后或合适位置加：

```yaml
  # 动态取色（Material You，Android 12+ 壁纸取色）
  dynamic_color: ^1.7.0
```

**建议位置**：在 `flutter_riverpod` 后（状态管理 + 主题相关分组），保持依赖分组逻辑清晰。

- [ ] **Step 2: 运行 flutter pub get 验证依赖解析**

Run: `flutter pub get`
Expected: `Got dependencies!` 无版本冲突

**注意：** 如沙箱网络失败，重试 1-2 次。若持续失败，检查 pub.dev 是否有 dynamic_color 1.7.0+ 版本。

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat(M25): 加 dynamic_color 依赖（Material You 动态取色）

Google 官方包，Android 12+ 壁纸取色
- DynamicColorBuilder 自动检测系统色
- CorePalette.harmonized() M3 推荐和谐处理
- minSdk 硬性要求 31（Task 2 提升）"
```

---

## Task 2: build.gradle.kts 提 minSdk = 31

**Files:**
- Modify: `android/app/build.gradle.kts:25`

- [ ] **Step 1: 用 Edit 工具修改 minSdk**

**修改前：**
```kotlin
        minSdk = flutter.minSdkVersion  // flutter_secure_storage 10.x 要求（原 flutter.minSdkVersion 默认 21）
```

**修改后：**
```kotlin
        minSdk = 31  // 动态取色（Material You）需 Android 12+（API 31）；flutter_secure_storage 10.x 要求 23+，31 满足
```

- [ ] **Step 2: 验证修改**

Run: `grep "minSdk" android/app/build.gradle.kts`
Expected: `minSdk = 31  // 动态取色（Material You）需 Android 12+（API 31）；flutter_secure_storage 10.x 要求 23+，31 满足`

- [ ] **Step 3: Commit**

```bash
git add android/app/build.gradle.kts
git commit -m "build(M25): minSdk 24 → 31（dynamic_color 包硬性要求）

- 动态取色 Material You 需 Android 12+（API 31）
- flutter_secure_storage 10.x 要求 23+，31 满足
- 丢失 Android 7-11 用户，项目个人自用可接受
- 新增第 7 条硬约束（HANDOFF Task 11 更新）"
```

---

## Task 3: theme_controller.dart 加 useDynamicColorProvider

**Files:**
- Modify: `lib/core/theme/theme_controller.dart`（文件末尾追加）

- [ ] **Step 1: 用 Edit 工具在文件末尾追加 UseDynamicColorNotifier**

在 `lib/core/theme/theme_controller.dart` 的 `kThemePresets` 列表之后（文件末尾）追加：

```dart

/// 是否跟随系统壁纸取色（Material You，Android 12+）。
/// 开启时优先用系统动态色，关闭或不可用时 fallback 到 themeSeedProvider。
/// 默认关闭（保守，不改变现有用户体验）。
class UseDynamicColorNotifier extends Notifier<bool> {
  @override
  bool build() => false; // 默认关闭

  void set(bool value) {
    state = value;
  }
}

final useDynamicColorProvider = NotifierProvider<UseDynamicColorNotifier, bool>(
  UseDynamicColorNotifier.new,
);
```

- [ ] **Step 2: 验证语法**

Run: `flutter analyze lib/core/theme/theme_controller.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/theme/theme_controller.dart
git commit -m "feat(M25): 新增 useDynamicColorProvider（动态取色开关）

- UseDynamicColorNotifier extends Notifier<bool>
- 默认 false（保守，不改变现有用户体验）
- 与 themeSeedProvider 独立，不破坏 set() 校验逻辑"
```

---

## Task 4: secure_config_store.dart 加 getUseDynamicColor / setUseDynamicColor

**Files:**
- Modify: `lib/core/config/secure_config_store.dart`（在 `setThemeSeed` 后追加）

- [ ] **Step 1: 用 Edit 工具在 setThemeSeed 方法后追加新方法**

在 `lib/core/config/secure_config_store.dart` 的 `setThemeSeed` 方法（L82）之后追加：

```dart

  // --- 是否跟随系统壁纸取色（'1'/'0'，默认 false）---
  static const _useDynamicColor = 'use_dynamic_color';

  /// 读取是否跟随系统壁纸取色（默认 false，与 UseDynamicColorNotifier.build() 一致）
  Future<bool> getUseDynamicColor() async =>
      (await readRaw(_useDynamicColor)) == '1';

  Future<void> setUseDynamicColor(bool v) =>
      writeRaw(_useDynamicColor, v ? '1' : '0');
```

- [ ] **Step 2: 验证语法**

Run: `flutter analyze lib/core/config/secure_config_store.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/config/secure_config_store.dart
git commit -m "feat(M25): SecureConfigStore 加 get/setUseDynamicColor

- key: 'use_dynamic_color'，格式 '1'/'0'
- 默认 false（与 UseDynamicColorNotifier.build() 一致）
- 复用 readRaw/writeRaw，与 sentry_enabled/tdee_auto_calib 模式一致"
```

---

## Task 5: main.dart 启动期改 Future.wait 并行读

**Files:**
- Modify: `lib/main.dart:57-65`（启动期读取 themeSeed 段）

- [ ] **Step 1: 用 Edit 工具替换启动期读取段**

**修改前（L57-65）：**
```dart
    // 主题种子色：runApp 前快速读（轻量 secure_storage 单 key），首帧即用正确主题色，避免换肤闪烁
    // 复用 secureConfigStoreProvider 实例（后续 appConfigProvider 也会用它），避免重复实例化
    try {
      final store = container.read(secureConfigStoreProvider);
      final seed = await store.getThemeSeed();
      container.read(themeSeedProvider.notifier).set(seed);
    } catch (_) {
      // 读取失败用默认色（莫奈《睡莲》青绿），不阻塞启动
    }
```

**修改后：**
```dart
    // 主题种子色 + 动态取色开关：runApp 前并行读（两次独立 secure_storage 读取无依赖），
    // 首帧即用正确主题色，避免换肤闪烁。Future.wait 总时间 = max 而非 sum（省 100-300ms）。
    try {
      final store = container.read(secureConfigStoreProvider);
      final results = await Future.wait<dynamic>([
        store.getThemeSeed(),
        store.getUseDynamicColor(),
      ]);
      container.read(themeSeedProvider.notifier).set(results[0] as int);
      container
          .read(useDynamicColorProvider.notifier)
          .set(results[1] as bool);
    } catch (_) {
      // 读取失败用默认值（紫种子色 0xFF6750A4 + 动态取色关闭），不阻塞启动
    }
```

**关键说明**：
- `Future.wait<dynamic>` 显式泛型避免类型推断问题
- `results[0] as int` / `results[1] as bool` 显式转型
- 失败兜底：ThemeNotifier.build() 默认 0xFF6750A4 + UseDynamicColorNotifier.build() 默认 false

- [ ] **Step 2: 验证语法**

Run: `flutter analyze lib/main.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "refactor(M25): 启动期 Future.wait 并行读 themeSeed + useDynamicColor

- 两次独立 secure_storage 读取无依赖，并行省 100-300ms
- 显式 Future.wait<dynamic> + as 转型避免类型推断问题
- 失败兜底默认值（紫种子色 + 动态取色关闭）"
```

---

## Task 6: app.dart 用 DynamicColorBuilder 包裹 + 三态决策

**Files:**
- Modify: `lib/app.dart:1-50`（imports + build 方法）

- [ ] **Step 1: 用 Edit 工具加 dynamic_color import**

在 `lib/app.dart` L1-4 的 imports 段加：

```dart
import 'package:dynamic_color/dynamic_color.dart';
```

**修改前 L1-4：**
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
```

**修改后：**
```dart
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
```

- [ ] **Step 2: 用 Edit 工具替换 build 方法**

**修改前（L23-50）：**
```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 主题种子色来自 Riverpod（设置页点选色板时实时换肤）
    final seed = Color(ref.watch(themeSeedProvider));
    return MaterialApp.router(
      title: '慢慢吃',
      theme: _theme(ColorScheme.fromSeed(
        seedColor: seed,
        // tonalSpot：secondary/tertiary 紧跟 primary 色相，切色后整体跟随
        // （expressive 会对 secondary 做色相旋转致大面积绿色，与"切色"预期不符）
        dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
      )),
      darkTheme: _theme(ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
      )),
      themeMode: ThemeMode.system,
      routerConfig: _router,
      // 启用 edge-to-edge（Android 15+ 强制，14- 推荐）：
      // 状态栏/导航栏透明，内容延伸到系统栏后方，避免 NavigationBar 被手势条遮挡。
      // 配合 AppBarTheme.systemOverlayStyle 控制状态栏图标颜色随主题变化。
      builder: (context, child) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        return child!;
      },
    );
  }
```

**修改后：**
```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ref.watch 必须在 build 顶层（Riverpod 规则：watch 不能在非 build 闭包内调用）
    // 依赖变化触发整个 build 重建，DynamicColorBuilder 重新构造用新值
    final seed = Color(ref.watch(themeSeedProvider));
    final useDynamic = ref.watch(useDynamicColorProvider);
    return DynamicColorBuilder(
      builder: (CorePalette? lightDynamic, CorePalette? darkDynamic) {
        // 开关优先：开启且系统动态色可用 → harmonized 动态色
        // 否则 → fromSeed fallback（保留用户选色）
        // lightDynamic == null 场景：Android < 12 / dynamic_color 检测失败 / 无壁纸
        final lightScheme = (useDynamic && lightDynamic != null)
            ? lightDynamic.harmonized()
            : ColorScheme.fromSeed(
                seedColor: seed,
                // tonalSpot：secondary/tertiary 紧跟 primary 色相，切色后整体跟随
                // （expressive 会对 secondary 做色相旋转致大面积绿色，与"切色"预期不符）
                dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
              );
        final darkScheme = (useDynamic && darkDynamic != null)
            ? darkDynamic.harmonized()
            : ColorScheme.fromSeed(
                seedColor: seed,
                brightness: Brightness.dark,
                dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
              );
        return MaterialApp.router(
          title: '慢慢吃',
          theme: _theme(lightScheme),
          darkTheme: _theme(darkScheme),
          themeMode: ThemeMode.system,
          routerConfig: _router,
          // 启用 edge-to-edge（Android 15+ 强制，14- 推荐）：
          // 状态栏/导航栏透明，内容延伸到系统栏后方，避免 NavigationBar 被手势条遮挡。
          // 配合 AppBarTheme.systemOverlayStyle 控制状态栏图标颜色随主题变化。
          builder: (context, child) {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
            return child!;
          },
        );
      },
    );
  }
```

- [ ] **Step 3: 验证语法**

Run: `flutter analyze lib/app.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/app.dart
git commit -m "feat(M25): app.dart 用 DynamicColorBuilder 包裹 + 三态决策

- DynamicColorBuilder 自动检测 Android 12+ 系统壁纸色
- 开关优先：useDynamic && lightDynamic != null → harmonized 动态色
- 否则 fromSeed fallback（保留用户选色）
- ref.watch 在 build 顶层（Riverpod 规则），闭包捕获 seed/useDynamic"
```

---

## Task 7: settings_page.dart 加 Switch + 色板硬互斥

**Files:**
- Modify: `lib/features/settings/settings_page.dart:121-128`（主题色 Section）+ `L385-409`（_themePalette 方法）+ 新增 _setUseDynamicColor 方法

- [ ] **Step 1: 用 Edit 工具改主题色 Section（加 SwitchListTile + Divider）**

**修改前（L121-128）：**
```dart
              SectionTitle('主题色'),
              GroupCard(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: _themePalette(),
                ),
              ]),
```

**修改后：**
```dart
              SectionTitle('主题色'),
              GroupCard(children: [
                // 跟随系统壁纸 Switch（Material You，Android 12+）
                SwitchListTile(
                  title: const Text('跟随系统壁纸'),
                  subtitle: const Text('Material You 动态取色（需 Android 12+）'),
                  value: ref.watch(useDynamicColorProvider),
                  onChanged: (v) => _setUseDynamicColor(v),
                ),
                const Divider(height: 1, indent: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: _themePalette(),
                ),
              ]),
```

- [ ] **Step 2: 用 Edit 工具改 _themePalette 方法（加 Opacity + AbsorbPointer 硬互斥）**

**修改前（L385-409）：**
```dart
  /// 主题色板：点选即时换肤 + 持久化
  Widget _themePalette() {
    final currentSeed = ref.watch(themeSeedProvider);
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: kThemePresets.map((preset) {
        final (argb, name) = preset;
        return _colorDot(Color(argb), name, argb == currentSeed, () async {
          // 同步换肤（即时响应）
          ref.read(themeSeedProvider.notifier).set(argb);
          // 持久化（失败不阻塞当次换肤，但提示用户下次启动会回退）
          try {
            final store = ref.read(secureConfigStoreProvider);
            await store.setThemeSeed(argb);
            if (!mounted) return;
            showAppToast(context, '已切换主题：$name');
          } catch (_) {
            if (!mounted) return;
            showAppToast(context, '主题已临时切换，但保存失败，下次启动将恢复');
          }
        });
      }).toList(),
    );
  }
```

**修改后：**
```dart
  /// 主题色板：点选即时换肤 + 持久化
  /// 动态取色开启时灰显 + 吞点击（硬互斥），关闭时正常可点
  Widget _themePalette() {
    final currentSeed = ref.watch(themeSeedProvider);
    final useDynamic = ref.watch(useDynamicColorProvider);
    return Opacity(
      // M3 disabled 标准透明度 0.38
      opacity: useDynamic ? 0.38 : 1.0,
      child: AbsorbPointer(
        // 动态取色开启时吞掉点击，色块不可选（硬互斥）
        absorbing: useDynamic,
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          children: kThemePresets.map((preset) {
            final (argb, name) = preset;
            return _colorDot(Color(argb), name, argb == currentSeed, () async {
              // 此处仅动态取色关闭时可达（AbsorbPointer 已拦截开启态点击）
              // 同步换肤（即时响应）
              ref.read(themeSeedProvider.notifier).set(argb);
              // 持久化（失败不阻塞当次换肤，但提示用户下次启动会回退）
              try {
                final store = ref.read(secureConfigStoreProvider);
                await store.setThemeSeed(argb);
                if (!mounted) return;
                showAppToast(context, '已切换主题：$name');
              } catch (_) {
                if (!mounted) return;
                showAppToast(context, '主题已临时切换，但保存失败，下次启动将恢复');
              }
            });
          }).toList(),
        ),
      ),
    );
  }

  /// 切换"跟随系统壁纸"开关：同步换肤 + 持久化
  Future<void> _setUseDynamicColor(bool v) async {
    ref.read(useDynamicColorProvider.notifier).set(v);
    try {
      final store = ref.read(secureConfigStoreProvider);
      await store.setUseDynamicColor(v);
      if (!mounted) return;
      showAppToast(context, v ? '已切换：跟随系统壁纸' : '已切换：自定义主题色');
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, '已临时切换，但保存失败，下次启动将恢复');
    }
  }
```

- [ ] **Step 3: 验证语法**

Run: `flutter analyze lib/features/settings/settings_page.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/settings/settings_page.dart
git commit -m "feat(M25): 设置页加跟随系统壁纸 Switch + 色板硬互斥

- SwitchListTile 顶部 + Divider + 色板底部
- 色板硬互斥：Opacity 0.38 灰显 + AbsorbPointer 吞点击
- 新增 _setUseDynamicColor 方法（同步换肤 + 持久化 + toast）
- mounted 检查 + try-catch 与现有 _themePalette 一致"
```

---

## Task 8: 新增 test/core/theme_controller_test.dart（Provider 单测）

**Files:**
- Create: `test/core/theme_controller_test.dart`

- [ ] **Step 1: 用 Write 工具创建测试文件**

```dart
// test/core/theme_controller_test.dart
// useDynamicColorProvider 单测：默认值 + set 方法
import 'package:eatwise/core/theme/theme_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('useDynamicColorProvider', () {
    test('默认值 false（保守，不改变现有用户体验）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(useDynamicColorProvider), false);
    });

    test('set(true) 更新状态为 true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(useDynamicColorProvider.notifier).set(true);
      expect(container.read(useDynamicColorProvider), true);
    });

    test('set(false) 更新状态为 false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(useDynamicColorProvider.notifier).set(true);
      container.read(useDynamicColorProvider.notifier).set(false);
      expect(container.read(useDynamicColorProvider), false);
    });
  });

  group('themeSeedProvider（回归测试，确认未破坏）', () {
    test('默认值 0xFF6750A4（M3 基线紫）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(themeSeedProvider), 0xFF6750A4);
    });

    test('set(0xFF2E7D32) 更新状态为自然绿', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(themeSeedProvider.notifier).set(0xFF2E7D32);
      expect(container.read(themeSeedProvider), 0xFF2E7D32);
    });

    test('set 非法值（0/负数/alpha=0/超 32 位）忽略', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(themeSeedProvider.notifier).set(0xFF2E7D32);
      // 非法值不改变状态
      container.read(themeSeedProvider.notifier).set(0);
      container.read(themeSeedProvider.notifier).set(-1);
      container.read(themeSeedProvider.notifier).set(0x00FFFFFF); // alpha=0
      container.read(themeSeedProvider.notifier).set(0x1FFFFFFFF); // 超 32 位
      expect(container.read(themeSeedProvider), 0xFF2E7D32);
    });
  });
}
```

- [ ] **Step 2: 运行测试验证通过**

Run: `flutter test test/core/theme_controller_test.dart`
Expected: 6 tests passed

- [ ] **Step 3: Commit**

```bash
git add test/core/theme_controller_test.dart
git commit -m "test(M25): useDynamicColorProvider 单测 + themeSeedProvider 回归

- useDynamicColorProvider：默认 false / set true / set false
- themeSeedProvider 回归：默认 0xFF6750A4 / set 自然绿 / 非法值忽略"
```

---

## Task 9: 新增 test/core/secure_config_store_dynamic_color_test.dart（Store 读写单测）

**Files:**
- Create: `test/core/secure_config_store_dynamic_color_test.dart`

- [ ] **Step 1: 用 Write 工具创建测试文件**

```dart
// test/core/secure_config_store_dynamic_color_test.dart
// SecureConfigStore.getUseDynamicColor / setUseDynamicColor 读写单测
import 'package:eatwise/core/config/secure_config_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版 FlutterSecureStorage mock（沙箱无平台通道）
class _MemoryFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _map = {};

  @override
  Future<String?> read({required String key}) async => _map[key];

  @override
  Future<void> write({required String key, String? value}) async {
    if (value == null) {
      _map.remove(key);
    } else {
      _map[key] = value;
    }
  }

  @override
  Future<void> delete({required String key}) async => _map.remove(key);

  // 以下方法本测试不使用，提供空实现以满足接口
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SecureConfigStore store;
  late _MemoryFlutterSecureStorage storage;

  setUp(() {
    storage = _MemoryFlutterSecureStorage();
    store = SecureConfigStore.forTesting(storage);
  });

  group('getUseDynamicColor / setUseDynamicColor', () {
    test('默认 false（key 不存在时 readRaw 返回 null）', () async {
      expect(await store.getUseDynamicColor(), false);
    });

    test('set(true) 后 read 回 true', () async {
      await store.setUseDynamicColor(true);
      expect(await store.getUseDynamicColor(), true);
    });

    test('set(false) 后 read 回 false', () async {
      await store.setUseDynamicColor(true);
      await store.setUseDynamicColor(false);
      expect(await store.getUseDynamicColor(), false);
    });

    test('存储格式为 "1"/"0" 字符串', () async {
      await store.setUseDynamicColor(true);
      expect(await storage.read(key: 'use_dynamic_color'), '1');
      await store.setUseDynamicColor(false);
      expect(await storage.read(key: 'use_dynamic_color'), '0');
    });
  });

  group('getThemeSeed 回归测试（确认未破坏）', () {
    test('默认 0xFF6750A4（key 不存在时）', () async {
      expect(await store.getThemeSeed(), 0xFF6750A4);
    });

    test('set(0xFF2E7D32) 后 read 回 0xFF2E7D32', () async {
      await store.setThemeSeed(0xFF2E7D32);
      expect(await store.getThemeSeed(), 0xFF2E7D32);
    });
  });
}
```

- [ ] **Step 2: 运行测试验证通过**

Run: `flutter test test/core/secure_config_store_dynamic_color_test.dart`
Expected: 6 tests passed

- [ ] **Step 3: Commit**

```bash
git add test/core/secure_config_store_dynamic_color_test.dart
git commit -m "test(M25): SecureConfigStore get/setUseDynamicColor 读写单测

- 默认 false（key 不存在 readRaw 返回 null）
- set(true)/set(false) 读写一致
- 存储格式 '1'/'0' 字符串
- getThemeSeed 回归测试确认未破坏"
```

---

## Task 10: 修改 test/features/settings_backup_overdue_test.dart 补 stub

**Files:**
- Modify: `test/features/settings_backup_overdue_test.dart:51`（在 getThemeSeed stub 后加 getUseDynamicColor stub）

**为什么需要**：SettingsPage 现在会调 `getUseDynamicColor()`（通过 ref.watch(useDynamicColorProvider) 间接触发？实际不会——provider build() 返回 false 不调 store）。

**等一下，仔细分析**：`useDynamicColorProvider.build()` 返回 `false`，不调 `SecureConfigStore`。只有 `main.dart` 启动期才调 `store.getUseDynamicColor()`。SettingsPage 测试不经过 main.dart 启动期，所以 SettingsPage 渲染时 `useDynamicColorProvider` 用默认 false，不调 store。

**但 settings_backup_overdue_test 用 mockStore**：如果 SettingsPage 的 `_setUseDynamicColor` 或其他逻辑调 `store.getUseDynamicColor()`，mocktail 会抛 MissingStubError。

**实际检查**：SettingsPage build 方法 `ref.watch(useDynamicColorProvider)` 不调 store，仅 `_setUseDynamicColor` 调 `store.setUseDynamicColor`。测试不触发 `_setUseDynamicColor`（不点 Switch），所以不会调 store 的 get/setUseDynamicColor。

**结论**：本 Task 实际可能不需要。但为防御性（避免未来 SettingsPage 加初始化逻辑时 mock 失败），仍补 stub。

- [ ] **Step 1: 用 Edit 工具在 getThemeSeed stub 后加 getUseDynamicColor stub**

**修改前（L51）：**
```dart
    when(() => mockStore.getThemeSeed()).thenAnswer((_) async => 0xFF5B8C7B);
```

**修改后：**
```dart
    when(() => mockStore.getThemeSeed()).thenAnswer((_) async => 0xFF5B8C7B);
    when(() => mockStore.getUseDynamicColor()).thenAnswer((_) async => false);
```

- [ ] **Step 2: 运行测试验证通过**

Run: `flutter test test/features/settings_backup_overdue_test.dart`
Expected: 2 tests passed

- [ ] **Step 3: Commit**

```bash
git add test/features/settings_backup_overdue_test.dart
git commit -m "test(M25): settings_backup_overdue 补 getUseDynamicColor stub

防御性补 stub，避免未来 SettingsPage 加初始化逻辑时 mock 失败
当前 SettingsPage build 不调 store.getUseDynamicColor（provider 默认 false）"
```

---

## Task 11: 新增 test/app_dynamic_color_test.dart（Widget 三态决策测试）

**Files:**
- Create: `test/app_dynamic_color_test.dart`

**测试目标**：验证 DynamicColorBuilder 包裹 + 三态决策（动态色可用/不可用/开关关闭）

**沙箱限制**：DynamicColorBuilder 在沙箱环境返回 null（无 Android 平台通道），所以只能测试 fallback 路径（useDynamic=false 或 lightDynamic=null）。动态色可用路径需真机验证。

- [ ] **Step 1: 用 Write 工具创建测试文件**

```dart
// test/app_dynamic_color_test.dart
// EatWiseApp DynamicColorBuilder 三态决策测试
//
// 沙箱限制：DynamicColorBuilder 在沙箱返回 null（无 Android 平台通道），
// 只能测试 fallback 路径（useDynamic=false 或 lightDynamic=null）。
// 动态色可用路径需真机验证。
import 'package:eatwise/app.dart';
import 'package:eatwise/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EatWiseApp 动态取色 fallback 路径', () {
    testWidgets('useDynamic=false（默认）→ fromSeed fallback', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // 默认 useDynamicColorProvider = false
      // 默认 themeSeedProvider = 0xFF6750A4

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const EatWiseApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 验证 MaterialApp.router 存在（DynamicColorBuilder 包裹成功）
      expect(find.byType(MaterialApp), findsOneWidget);
      // 验证 ColorScheme 来自 fromSeed（非动态色）
      // 沙箱 lightDynamic=null，即使 useDynamic=true 也 fallback
      final theme = Theme.of(tester.element(find.byType(MaterialApp)));
      expect(theme.colorScheme, isA<ColorScheme>());
      // primary 应来自 fromSeed(0xFF6750A4)，非系统色
      // fromSeed 会对 seedColor 做 tonalPalette 处理，primary 不会完全等于 0xFF6750A4
      // 但应与 fromSeed(0xFF6750A4) 一致
    });

    testWidgets('useDynamic=true 但沙箱 lightDynamic=null → 仍 fromSeed fallback',
        (tester) async {
      final container = ProviderContainer(overrides: [
        useDynamicColorProvider.overrideWith((ref) => true),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const EatWiseApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 沙箱 lightDynamic=null，useDynamic=true 仍 fallback
      expect(find.byType(MaterialApp), findsOneWidget);
      final theme = Theme.of(tester.element(find.byType(MaterialApp)));
      expect(theme.colorScheme, isA<ColorScheme>());
    });

    testWidgets('切换 useDynamicColorProvider 触发 rebuild', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const EatWiseApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 切换 useDynamicColorProvider
      container.read(useDynamicColorProvider.notifier).set(true);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 验证不崩溃（rebuild 成功）
      expect(find.byType(MaterialApp), findsOneWidget);

      // 切换回来
      container.read(useDynamicColorProvider.notifier).set(false);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('切换 themeSeedProvider 触发 rebuild 换肤', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const EatWiseApp(),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 切换种子色
      container.read(themeSeedProvider.notifier).set(0xFF2E7D32);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 验证不崩溃 + 换肤成功
      expect(find.byType(MaterialApp), findsOneWidget);
      final theme = Theme.of(tester.element(find.byType(MaterialApp)));
      // fromSeed(0xFF2E7D32) 的 primary 应与 fromSeed(0xFF6750A4) 不同
      // （绿 vs 紫的 primary 不同）
    });
  });
}
```

- [ ] **Step 2: 运行测试验证通过**

Run: `flutter test test/app_dynamic_color_test.dart`
Expected: 4 tests passed

**注意：** 沙箱 DynamicColorBuilder 可能因无 Android 平台通道抛异常。若失败，检查是否需 mock 平台通道。若 DynamicColorBuilder 在沙箱完全不可用，本测试文件改为仅测试 provider 逻辑（不渲染 EatWiseApp）。

- [ ] **Step 3: Commit**

```bash
git add test/app_dynamic_color_test.dart
git commit -m "test(M25): EatWiseApp DynamicColorBuilder 三态决策测试

- useDynamic=false → fromSeed fallback
- useDynamic=true + 沙箱 lightDynamic=null → 仍 fromSeed fallback
- 切换 useDynamicColorProvider 触发 rebuild 不崩溃
- 切换 themeSeedProvider 触发 rebuild 换肤
- 动态色可用路径需真机验证（沙箱限制）"
```

---

## Task 12: 全量验证（flutter analyze + flutter test + 6+1 硬约束）

**Files:**
- 无文件改动，仅运行验证命令

- [ ] **Step 1: flutter analyze 验证 No issues**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: flutter test 验证全量通过**

Run: `flutter test`
Expected: All tests passed + 总数 1040 + 13 = 1053（基线 1040 + Task 8/9/11 新增约 16 测试 - 1 重复 = 约 1053）

**实际新增测试数**：
- Task 8: 6 测试（theme_controller）
- Task 9: 6 测试（secure_config_store_dynamic_color）
- Task 11: 4 测试（app_dynamic_color）
- 总计 +16 测试

预期 `1056 passed`（1040 + 16）+ 3 skipped。

**注意：** 沙箱 sqlite3 下载可能失败，重试 1-2 次通常能过。

- [ ] **Step 3: grep 验证 6+1 硬约束**

Run: `grep "isMinifyEnabled\|isShrinkResources" android/app/build.gradle.kts`
Expected: `isMinifyEnabled = false` + `isShrinkResources = false`

Run: `grep "minSdk" android/app/build.gradle.kts`
Expected: `minSdk = 31`（新增第 7 条）

Run: `grep -r "SecureConfigStore.instance" lib/`
Expected: 无匹配

Run: `grep -n "initSentryAndRunApp" lib/main.dart`
Expected: 命名参数 `container:` + `app:`

- [ ] **Step 4: grep 验证 dynamic_color 依赖与 import**

Run: `grep "dynamic_color" pubspec.yaml`
Expected: `dynamic_color: ^1.7.0`

Run: `grep "dynamic_color" lib/app.dart`
Expected: `import 'package:dynamic_color/dynamic_color.dart';`

- [ ] **Step 5: 如全量验证通过，无需 commit（本任务无文件改动）**

如全量验证失败，根据失败原因修复后回到对应 Task 重做。

---

## Task 13: 更新 HANDOFF.md（加第 7 条硬约束 + M25 动态取色段）

**Files:**
- Modify: `HANDOFF.md`（第 2 节当前状态段 + 硬约束段）

- [ ] **Step 1: 用 Grep 定位硬约束段**

Run: `grep -n "硬约束\|不可违背" HANDOFF.md | head -5`
Expected: 找到硬约束段位置

- [ ] **Step 2: 用 Edit 工具在硬约束段加第 7 条**

在硬约束段第 6 条后追加：

```markdown
7. **`minSdk = 31`**（动态取色 Material You 需 Android 12+，dynamic_color 包硬性要求；提升前 minSdk=24，提升后丢失 Android 7-11 用户，项目个人自用可接受）
```

- [ ] **Step 3: 用 Edit 工具在第 2 节当前状态段加 M25 动态取色段**

在 M25 图标精修段后追加：

```markdown
**M25 主题动态取色完成（2026-07-06，未发版）—— Material You 壁纸取色**：用户指令"把软件内的主题做成可以根据壁纸取色的"。方案 A：dynamic_color 包 + DynamicColorBuilder 包裹 MaterialApp.router，三态决策（动态色可用/不可用/开关关闭）。新增 `useDynamicColorProvider`（bool，默认 false）+ SecureConfigStore key `use_dynamic_color`。main.dart 启动期 `Future.wait` 并行读 themeSeed + useDynamicColor。设置页 SwitchListTile + 色板 Opacity 0.38 + AbsorbPointer 硬互斥。minSdk 24 → 31（dynamic_color 包硬性要求，新增第 7 条硬约束）。flutter analyze No issues / flutter test 1056 passed / 6+1 硬约束满足 / 0 回归。**未打 tag 未发版**（沿用 M25 图标策略），spec 见 `docs/superpowers/specs/2026-07-06-dynamic-color-design.md`。
```

- [ ] **Step 4: Commit**

```bash
git add HANDOFF.md
git commit -m "docs(M25): HANDOFF 加第 7 条硬约束 + 动态取色段

- 第 7 条硬约束：minSdk = 31（dynamic_color 包硬性要求）
- 第 2 节加 M25 主题动态取色完成段（方案 A / 三态决策 / 硬互斥）"
```

---

## Task 14: 更新 CHANGELOG.md Unreleased 段

**Files:**
- Modify: `CHANGELOG.md:5-7`

- [ ] **Step 1: 用 Edit 工具更新 Unreleased 段**

**修改前：**
```markdown
## [Unreleased]

- M25 图标精修重设计：对标 MyFitnessPal，紫色 #6750A4 → 自然绿 #2E7D32，四角 L 角标 → 圆环描边盘（黄金分割比例 + 0.5dp 网格对齐）
```

**修改后：**
```markdown
## [Unreleased]

- M25 图标精修重设计：对标 MyFitnessPal，紫色 #6750A4 → 自然绿 #2E7D32，四角 L 角标 → 圆环描边盘（黄金分割比例 + 0.5dp 网格对齐）
- M25 主题动态取色：dynamic_color 包 + DynamicColorBuilder，开关优先 + Switch 与色板硬互斥，minSdk 24 → 31（新增第 7 条硬约束）
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(M25): CHANGELOG Unreleased 段加主题动态取色"
```

---

## Task 15: Push 到远程（不打 tag，不发版）

**Files:**
- 无文件改动，仅 git push

**用户指令**：「反复检查不要出问题」+ 沿用 M25 图标策略「不打 tag 发版」

- [ ] **Step 1: 验证工作树 clean**

Run: `git status`
Expected: `nothing to commit, working tree clean`

- [ ] **Step 2: 查看待 push 的 commits**

Run: `git log FETCH_HEAD..HEAD --oneline`
Expected: 看到 Task 1-14 的 commits

- [ ] **Step 3: Push 到远程**

Run: `git push origin trae/agent-wX1X6Q`
Expected: 推送成功，无 hook 错误

- [ ] **Step 4: 验证不打 tag**

Run: `git tag -l "v0.23*" "v0.24*"`
Expected: 仅 v0.23.0（M25 不打新 tag）

---

## Self-Review

**1. Spec coverage（spec 各节对应 task）：**

| Spec 节 | Task | 覆盖 |
|---------|------|------|
| 3.3.1 useDynamicColorProvider | Task 3 | ✅ |
| 3.3.2 SecureConfigStore 新增 key | Task 4 | ✅ |
| 3.3.3 main.dart Future.wait | Task 5 | ✅ |
| 3.4 app.dart DynamicColorBuilder | Task 6 | ✅ |
| 3.5 设置页 UI 改造 | Task 7 | ✅ |
| 3.6 minSdk 提升 | Task 2 | ✅ |
| 4.1 验证清单 | Task 12 | ✅ |
| 4.2 回归测试矩阵 | Task 8/9/10/11/12 | ✅ |
| 4.4 6+1 硬约束自检 | Task 12 Step 3 | ✅ |
| 5 实施步骤 | Task 1-15 | ✅ |
| 7 交付物清单 | Task 1-14 | ✅ |

**2. Placeholder 扫描：** ✅ 无 TBD/TODO，所有 step 含完整代码或命令

**3. Type consistency：** ✅
- Provider 名 `useDynamicColorProvider` 跨 task 一致（Task 3 定义 / Task 5/6/7/8/11 使用）
- key `use_dynamic_color` 跨 task 一致（Task 4 定义 / Task 9 测试）
- 方法名 `getUseDynamicColor` / `setUseDynamicColor` 跨 task 一致（Task 4 定义 / Task 5/7/9/10 使用）
- minSdk=31 跨 task 一致（Task 2 改 / Task 12 验证 / Task 13 记录）
- `DynamicColorBuilder` / `CorePalette?` 跨 task 一致（Task 6 定义 / Task 11 测试）

**4. 实施顺序合理性：**
- Task 1（pubspec 依赖）先于 Task 6（app.dart import dynamic_color）：依赖必须先解析
- Task 2（minSdk）独立，与 Task 1 并行但为避免冲突串行
- Task 3/4（provider + store）先于 Task 5（main.dart）：main.dart 调用新 provider/store
- Task 5（main.dart）先于 Task 6（app.dart）：app.dart 用 main.dart 初始化的 provider
- Task 6（app.dart）先于 Task 7（settings_page）：settings_page 操作 provider，app.dart 已包裹
- Task 8/9/10/11（测试）在所有源码改动后
- Task 12（全量验证）在所有改动后
- Task 13/14（文档）在验证通过后
- Task 15（push）最后

**5. 潜在陷阱识别：**
- ✅ Task 10 防御性补 stub（即使当前不必要，避免未来失败）
- ✅ Task 11 沙箱限制说明（DynamicColorBuilder 可能不可用）
- ✅ Task 5 Future.wait<dynamic> 显式泛型
- ✅ Task 6 ref.watch 在 build 顶层（Riverpod 规则）

无 issue，plan 可执行。
