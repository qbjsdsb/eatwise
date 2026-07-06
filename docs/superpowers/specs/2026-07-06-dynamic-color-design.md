# EatWise 主题动态取色（Material You）设计

**日期**：2026-07-06
**版本**：v0.23.0+35 → 未发版（push 不打 tag，沿用 M25 图标策略）
**前置里程碑**：M22（M3 fromSeed 主题系统）+ M25（图标精修）
**后续里程碑**：M26+ 待定

## 1. 背景与动机

### 1.1 当前主题架构

EatWise 当前主题系统是 **"M3 fromSeed + Riverpod 单种子色 + SecureConfigStore 持久化 + 设置页 12 色板点选"**：

| 组件 | 文件 | 现状 |
|------|------|------|
| 种子色 Provider | `lib/core/theme/theme_controller.dart` | `themeSeedProvider`（NotifierProvider<int>，ARGB int），默认 0xFF6750A4 |
| 持久化 | `lib/core/config/secure_config_store.dart` | key `theme_seed`，ARGB int 十进制字符串 |
| App 应用 | `lib/app.dart` | `ColorScheme.fromSeed(seedColor: seed, dynamicSchemeVariant: tonalSpot)` |
| 启动期读取 | `lib/main.dart` L59-65 | `getThemeSeed()` → `set(seed)` |
| 设置页 UI | `lib/features/settings/settings_page.dart` | 12 色板 Wrap + `_colorDot` 圆形色块 |
| ThemeMode | `lib/app.dart` L40 | 硬编码 `ThemeMode.system`，无切换 UI |
| 预设色板 | `lib/core/theme/theme_controller.dart` L26-39 | 12 项（莫奈 + Material 经典）|

### 1.2 用户需求

用户指令："把软件内的主题做成可以根据壁纸取色的"。

### 1.3 当前架构扩展点评估

**已预留扩展点**：
1. 种子色已 Riverpod 化，`app.dart` 单点 `ref.watch → ColorScheme.fromSeed`，切换数据源单点完成
2. 持久化已抽象，`SecureConfigStore` 统一封装，新增 key 模式清晰
3. 种子色与 AppConfig 解耦，独立单 key 管理
4. `DynamicSchemeVariant` 已显式声明（tonalSpot）
5. 设置页色板组件已模块化（`_themePalette()` + `_colorDot()`）

**未预留 / 需补的点**：
1. 无 `dynamic_color` 依赖（pubspec.yaml）
2. 无 `DynamicColorBuilder` 包裹
3. 无"动态取色开关"provider 与持久化 key
4. `minSdk = flutter.minSdkVersion`（24）不满足动态取色要求（需 31）
5. 设置页无 Switch 入口

## 2. 设计目标

### 2.1 核心目标

1. **支持 Material You 动态取色**：Android 12+ 跟随系统壁纸自动生成 ColorScheme
2. **开关优先策略**：开启动态取色时完全用系统色，忽略用户选的种子色；关闭时回到种子色
3. **Switch + 色板硬互斥**：设置页 Switch 开启时色板灰显不可点，关闭时色板恢复可点
4. **低版本兜底**：Android < 12 或动态色不可用时自动 fallback 到 `ColorScheme.fromSeed`
5. **保留现有选色能力**：用户关闭动态取色后仍可用 12 色板选色，种子色记忆不丢失
6. **回滚零风险**：6 文件改动，git revert 可恢复

### 2.2 非目标

- 不引入 ThemeMode 切换（light/dark/system 三选一 UI），仍硬编码 `ThemeMode.system`
- 不引入 harmonization 系数调参（用 dynamic_color 包默认 `harmonized()`）
- 不自定义 ColorScheme（不混合动态色与用户选色）
- 不支持 iOS（项目 Android 单平台，且 iOS 不支持动态取色）
- 不打 tag 发版（沿用 M25 策略，仅 commit + push）

### 2.3 用户决策（3 个关键点已对齐）

1. **minSdk**：提升到 31（丢失 Android 7-11 用户，项目个人自用可接受）
2. **优先级**：开关优先（开启时完全用系统色，忽略种子色）
3. **UI**：Switch + 色板硬互斥（开启时色板灰显不可点）

## 3. 设计方案

### 3.1 方案选型

候选 3 个：

| 方案 | 架构 | 改动量 | 优点 | 缺点 |
|------|------|--------|------|------|
| **A（推荐）** | dynamic_color + DynamicColorBuilder | 6 文件 60-100 行 | Google 官方包，API 稳定，测试简单 | 依赖第三方包 |
| B | 自建 PlatformChannel | 8-10 文件 150-200 行 | 不依赖第三方 | 重新造轮子，PlatformChannel 维护成本高 |
| C | dynamic_color + harmonization 混合 | A + 20-30 行 | 色彩和谐 | 与"开关优先"决策冲突 |

**选 A 理由**：最小改动量 / Google 官方包 / 与 3 个用户决策完全契合 / 测试友好 / 回滚零风险。

### 3.2 架构与数据流

```
main.dart 启动
  ├─ Future.wait 并行读 SecureConfigStore：themeSeed + useDynamicColor
  ├─ set themeSeedProvider + useDynamicColorProvider
  └─ runApp(UncontrolledProviderScope → EatWiseApp)

EatWiseApp.build
  ├─ ref.watch(themeSeedProvider) → 用户选色 seed
  ├─ ref.watch(useDynamicColorProvider) → 开关 bool
  └─ return DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          // 开关优先：开启且系统动态色可用 → harmonized 动态色
          // 否则 → fromSeed fallback
          final lightScheme = (useDynamic && lightDynamic != null)
              ? lightDynamic.harmonized()
              : ColorScheme.fromSeed(seedColor: seed, dynamicSchemeVariant: tonalSpot);
          final darkScheme = (useDynamic && darkDynamic != null)
              ? darkDynamic.harmonized()
              : ColorScheme.fromSeed(seedColor: seed, brightness: dark, dynamicSchemeVariant: tonalSpot);
          return MaterialApp.router(theme: _theme(lightScheme), darkTheme: _theme(darkScheme), ...);
        },
      );
```

**数据源优先级（开关优先）**：

```
useDynamicColorProvider == true
  ├─ lightDynamic != null（Android 12+ 系统返回动态色）
  │     → 用 lightDynamic.harmonized()
  └─ lightDynamic == null（Android < 12 或检测失败）
        → fallback to ColorScheme.fromSeed(seedColor: themeSeedProvider)

useDynamicColorProvider == false
  → 始终用 ColorScheme.fromSeed(seedColor: themeSeedProvider)
```

**为什么用 `harmonized()`**：dynamic_color 包提供 `ColorScheme.harmonized()` 方法，将系统取色的 primary 与 M3 baseline 做轻微和谐处理，避免某些壁纸色过于刺眼。这是 M3 推荐做法。

**关键设计决策**：
1. `useDynamicColorProvider` 独立于 `themeSeedProvider`，不破坏现有 `set()` 校验逻辑，不引入 sentinel 值
2. `themeSeedProvider` 保留：用户关闭动态取色时仍用其选色，开关切换不影响种子色记忆
3. `DynamicColorBuilder` 在 build 方法内：每次 `useDynamicColorProvider` 变化触发 rebuild，DynamicColorBuilder 重新获取系统色

### 3.3 Provider 与持久化设计

#### 3.3.1 新增 Provider：useDynamicColorProvider

```dart
// lib/core/theme/theme_controller.dart 新增

/// 是否跟随系统壁纸取色（Material You，Android 12+）。
/// 开启时优先用系统动态色，关闭或不可用时 fallback 到 themeSeedProvider。
class UseDynamicColorNotifier extends Notifier<bool> {
  @override
  bool build() => false; // 默认关闭（保守，不改变现有用户体验）

  void set(bool value) {
    state = value;
  }
}

final useDynamicColorProvider = NotifierProvider<UseDynamicColorNotifier, bool>(
  UseDynamicColorNotifier.new,
);
```

#### 3.3.2 SecureConfigStore 新增 key

```dart
// lib/core/config/secure_config_store.dart 新增

static const _useDynamicColor = 'use_dynamic_color';

/// 读取是否跟随系统壁纸取色（默认关闭，与 UseDynamicColorNotifier.build() 一致）
Future<bool> getUseDynamicColor() async =>
    (await readRaw(_useDynamicColor)) == '1'; // 默认 false

Future<void> setUseDynamicColor(bool v) =>
    writeRaw(_useDynamicColor, v ? '1' : '0');
```

#### 3.3.3 main.dart 启动期初始化（Future.wait 并行）

```dart
// lib/main.dart 修改启动期读取段（替换 L59-65）

// 主题种子色 + 动态取色开关：两次独立 secure_storage 读取，无依赖，并行
try {
  final store = container.read(secureConfigStoreProvider);
  final results = await Future.wait([
    store.getThemeSeed(),
    store.getUseDynamicColor(),
  ]);
  container.read(themeSeedProvider.notifier).set(results[0] as int);
  container.read(useDynamicColorProvider.notifier).set(results[1] as bool);
} catch (_) {
  // 读取失败用默认值（紫种子色 + 动态取色关闭），不阻塞启动
}
```

**为什么用 `Future.wait` 并行**：
- 两次读取无依赖关系，并行后总时间 = max（约 100-300ms）而非 sum（约 200-600ms）
- 与现有 L50-55 注释"启动期并行化"思路一致

#### 3.3.4 存储格式一致性

| key | 格式 | 默认值 | 与现有项对齐 |
|-----|------|--------|------------|
| `theme_seed` | ARGB int 十进制字符串 | `0xFF6750A4` | - |
| `use_dynamic_color` | `'1'`/`'0'` | `'0'`（false） | 与 `sentry_enabled` / `tdee_auto_calib` 一致 |

### 3.4 app.dart 改造

#### 3.4.1 改造前（L23-50）

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final seed = Color(ref.watch(themeSeedProvider));
  return MaterialApp.router(
    title: '慢慢吃',
    theme: _theme(ColorScheme.fromSeed(
      seedColor: seed,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    )),
    darkTheme: _theme(ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    )),
    themeMode: ThemeMode.system,
    routerConfig: _router,
    builder: (context, child) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      return child!;
    },
  );
}
```

#### 3.4.2 改造后

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  // ref.watch 在 EatWiseApp.build 顶层调用，依赖变化触发整个 build 重建
  // （DynamicColorBuilder 闭包捕获外层 ref，但 watch 必须在 build 顶层，
  // 不能在 DynamicColorBuilder 的 builder 闭包内 watch——否则 Riverpod 报错）
  final seed = Color(ref.watch(themeSeedProvider));
  final useDynamic = ref.watch(useDynamicColorProvider);
  return DynamicColorBuilder(
    builder: (CorePalette? lightDynamic, CorePalette? darkDynamic) {
      // 闭包捕获外层 seed / useDynamic（build 顶层 watch 的最新值）
      // 开关优先：开启且系统动态色可用 → harmonized 动态色
      // 否则 → fromSeed fallback（保留用户选色）
      // lightDynamic == null 场景：Android < 12 / dynamic_color 检测失败 / 无壁纸
      final lightScheme = (useDynamic && lightDynamic != null)
          ? lightDynamic.harmonized()
          : ColorScheme.fromSeed(
              seedColor: seed,
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
        builder: (context, child) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          return child!;
        },
      );
    },
  );
}
```

**关键说明**：`ref.watch` 必须在 `EatWiseApp.build` 顶层调用（Riverpod 规则：watch 不能在非 build 闭包内调用），`DynamicColorBuilder` 的 builder 闭包通过捕获获取 `seed` / `useDynamic`。当 `themeSeedProvider` 或 `useDynamicColorProvider` 变化时，Riverpod 触发 `EatWiseApp.build` 重建，`DynamicColorBuilder` 重新构造，builder 闭包用新捕获的值重建 `MaterialApp.router`。

#### 3.4.3 import 新增

```dart
import 'package:dynamic_color/dynamic_color.dart';
// theme_controller.dart 已 import，useDynamicColorProvider 自动可用
```

#### 3.4.4 关键改造点

1. `DynamicColorBuilder` 包裹 `MaterialApp.router`：dynamic_color 包提供的 widget，自动检测 Android 12+ 系统壁纸色，<12 或检测失败时 `lightDynamic`/`darkDynamic` 为 null
2. `CorePalette?` 类型：dynamic_color 包用 `CorePalette?`（非 `ColorScheme?`），需调 `.harmonized()` 转 `ColorScheme`
3. 三态决策：
   - `useDynamic == true && lightDynamic != null` → 动态色
   - `useDynamic == true && lightDynamic == null` → fromSeed fallback（Android < 12 兜底）
   - `useDynamic == false` → fromSeed（用户选色）
4. `harmonized()` 调用：M3 推荐，对系统取色做轻微和谐处理，避免某些壁纸色刺眼

#### 3.4.5 严谨性检查

| 检查项 | 状态 |
|--------|------|
| `ref.watch(themeSeedProvider)` 重建触发 | ✅ 保留 |
| `ref.watch(useDynamicColorProvider)` 重建触发 | ✅ 新增（Switch 变化触发 rebuild） |
| `DynamicColorBuilder` rebuild 行为 | ✅ 系统色变化包内部监听 |
| `lightDynamic == null` 兜底 | ✅ fromSeed fallback |
| `harmonized()` 不破坏动态色 | ✅ M3 推荐做法 |
| `_theme()` 静态方法不变 | ✅ 不动 |
| `routerConfig` 不变 | ✅ 不动 |
| `builder: edgeToEdge` 不变 | ✅ 保留 |
| `useMaterial3: true` 不变 | ✅ 保留在 `_theme()` 内 |
| ConsumerWidget ref 可用 | ✅ DynamicColorBuilder 内闭包捕获 ref |
| M24 跨层依赖约束 | ✅ 仅 root + core 层，不涉及 feature 层 |

### 3.5 设置页 UI 改造

#### 3.5.1 改造前（L121-128 + L385-409）

```dart
SectionTitle('主题色'),
GroupCard(children: [
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: _themePalette(),  // 仅色板，无 Switch
  ),
]),

Widget _themePalette() {
  final currentSeed = ref.watch(themeSeedProvider);
  return Wrap(spacing: 16, runSpacing: 12, children: [...]);
}
```

#### 3.5.2 改造后：Switch + 色板硬互斥

```dart
SectionTitle('主题色'),
GroupCard(children: [
  // 顶部：跟随系统壁纸 Switch（Material You，Android 12+）
  SwitchListTile(
    title: const Text('跟随系统壁纸'),
    subtitle: const Text('Material You 动态取色（需 Android 12+）'),
    value: ref.watch(useDynamicColorProvider),
    onChanged: (v) => _setUseDynamicColor(v),
  ),
  const Divider(height: 1, indent: 16),
  // 底部：色板（动态取色开启时灰显禁用，硬互斥语义）
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: _themePalette(),
  ),
]),
```

#### 3.5.3 `_setUseDynamicColor` 方法（新增）

```dart
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

#### 3.5.4 `_themePalette` 改造（硬互斥）

```dart
Widget _themePalette() {
  final currentSeed = ref.watch(themeSeedProvider);
  final useDynamic = ref.watch(useDynamicColorProvider);
  return Opacity(
    // 动态取色开启时灰显色板（M3 disabled 标准透明度 0.38）
    opacity: useDynamic ? 0.38 : 1.0,
    child: AbsorbPointer(
      absorbing: useDynamic,  // 动态取色开启时吞掉点击，色块不可选
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: kThemePresets.map((preset) {
          final (argb, name) = preset;
          return _colorDot(Color(argb), name, argb == currentSeed, () async {
            // 此处仅动态取色关闭时可达（AbsorbPointer 已拦截开启态点击）
            ref.read(themeSeedProvider.notifier).set(argb);
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
```

#### 3.5.5 互斥状态机

| 场景 | Switch | 色板 | 用户操作路径 |
|------|--------|------|------------|
| 动态取色 ON | ON | 灰显 + 不可点 | 想换自定义色 → 先关 Switch → 色板恢复可点 → 点色块 |
| 动态取色 OFF | OFF | 正常 + 可点 | 点色块直接切色（无需操作 Switch） |
| Switch ON→OFF | OFF | 恢复可点 | Switch onChanged → _setUseDynamicColor(false) |
| Switch OFF→ON | ON | 灰显 | Switch onChanged → _setUseDynamicColor(true) |

#### 3.5.6 严谨性检查

| 检查项 | 状态 |
|--------|------|
| SwitchListTile 触控目标 ≥48dp | ✅ M3 默认满足 |
| 色板灰显透明度 0.38 | ✅ M3 disabled 标准 |
| AbsorbPointer 拦截点击 | ✅ 开启态点色块无响应 |
| 色块 onTap 逻辑仅关闭态可达 | ✅ AbsorbPointer 保证 |
| `mounted` 检查在 async gap 后 | ✅ 与现有 _themePalette 一致 |
| try-catch-finally | ✅ try-catch + mounted + toast |
| Toast 文案区分场景 | ✅ 三种（跟随壁纸/自定义色/保存失败） |
| Divider 视觉分隔 | ✅ 与 GroupCard 风格一致 |
| SectionTitle 不变 | ✅ 仍 '主题色'，涵盖 Switch + 色板 |

### 3.6 minSdk 提升

#### 3.6.1 改动

```kotlin
// android/app/build.gradle.kts L25
// 修改前
minSdk = flutter.minSdkVersion  // flutter_secure_storage 10.x 要求（原 flutter.minSdkVersion 默认 21）

// 修改后
minSdk = 31  // 动态取色（Material You）需 Android 12+（API 31）；flutter_secure_storage 10.x 要求 23+，31 满足
```

#### 3.6.2 为什么是 31

- Android 12（API 31）是 Material You 动态取色的最低版本
- `dynamic_color` 包文档明确要求 `minSdkVersion 31`
- 提到 32/33/34 会丢失更多用户，无额外收益

#### 3.6.3 用户影响评估（项目个人自用）

| 设备 Android 版本 | API | minSdk=24 可装 | minSdk=31 可装 | 影响 |
|------------------|-----|---------------|---------------|------|
| 7.0-11 | 24-30 | ✅ | ❌ | 丢失 |
| 12+ | 31+ | ✅ | ✅ | 保留 |

项目 HANDOFF 标注"个人自用"，且 dynamic_color 在 < 31 设备上 `lightDynamic` 返回 null 自动 fallback，但 `dynamic_color` 包本身要求 minSdk 31（否则编译期报错）。提升是硬性要求。

#### 3.6.4 新增硬约束（第 7 条）

```markdown
7. **`minSdk = 31`**（动态取色 Material You 需 Android 12+，dynamic_color 包硬性要求；
   提升前 minSdk=24，提升后丢失 Android 7-11 用户，项目个人自用可接受）
```

## 4. 验证策略

### 4.1 验证清单

| 验证项 | 方法 | 通过标准 |
|--------|------|---------|
| pubspec 依赖 | `flutter pub get` | dynamic_color ^1.7.0 解析成功 |
| flutter analyze | `flutter analyze` | No issues |
| Provider 单测 | 新增 `test/core/theme_controller_test.dart` | useDynamicColorProvider set/默认值测试通过 |
| SecureConfigStore 单测 | 新增 `test/core/secure_config_store_dynamic_color_test.dart` | get/setUseDynamicColor 读写 + 默认 false |
| app.dart widget 测试 | 新增 `test/app_dynamic_color_test.dart` | DynamicColorBuilder 包裹 + 三态决策 |
| 设置页 widget 测试 | 修改现有 settings 测试 | Switch 切换 + 色板互斥灰显 |
| 全量回归 | `flutter test` | 基线 1040 → 预期 1045+（新增约 5-8 测试） |
| 6 硬约束 + 新增第 7 条 | grep 验证 | 全部满足 |
| Android 编译 | `flutter build apk --debug` | APK 构建成功（沙箱可能失败，本地真机验证） |

### 4.2 回归测试矩阵

| 测试文件 | 预期 | 验证点 |
|---------|------|--------|
| `test/icon_assets_test.dart` | pass | 图标测试不受影响（M25 改动） |
| `test/features/settings_*` | 需 stub `getUseDynamicColor()` | mock SecureConfigStore 补 stub |
| 全量 `flutter test` | 1045+ passed | 0 回归 |

### 4.3 风险与缓解

| 风险 | 概率 | 缓解 |
|------|------|------|
| `dynamic_color` 包与 Flutter 3.44.4 不兼容 | 低 | 包文档支持 Flutter 3.x，pub.dev 验证最新版 |
| `DynamicColorBuilder` 在沙箱测试环境返回 null | 中 | 测试用例覆盖 null 场景（fallback 路径） |
| `CorePalette.harmonized()` API 变化 | 低 | dynamic_color 1.7.0 稳定 API |
| minSdk 提升致编译期警告 | 低 | build.gradle.kts 加注释说明原因 |
| 现有 mock SecureConfigStore 测试失败 | 中 | 补 `getUseDynamicColor()` stub 返回 false |
| `main.dart` Future.wait 类型推断 | 低 | 显式 `Future.wait<dynamic>` + as 转型 |

### 4.4 6 硬约束 + 新增第 7 条自检

| 硬约束 | 影响 | 状态 |
|--------|------|------|
| build.gradle minify=false | 不涉及 | ✅ |
| meal_log.food_item_id 非空外键 | 不涉及 | ✅ |
| AI 三路径 | 不涉及 | ✅ |
| per100g 基于 estimatedWeightGMid | 不涉及 | ✅ |
| SecureConfigStore 无 instance | 不涉及（仍用构造函数） | ✅ |
| initSentryAndRunApp 命名参数 | 不涉及 | ✅ |
| **minSdk = 31（新增）** | **本次提升** | ✅ |

## 5. 实施步骤

1. pubspec.yaml 加 `dynamic_color: ^1.7.0` + `flutter pub get`
2. build.gradle.kts 提 minSdk = 31
3. theme_controller.dart 加 `useDynamicColorProvider`
4. secure_config_store.dart 加 `getUseDynamicColor` / `setUseDynamicColor`
5. main.dart 启动期改 `Future.wait` 并行读 themeSeed + useDynamicColor
6. app.dart 用 `DynamicColorBuilder` 包裹 + 三态决策
7. settings_page.dart 加 SwitchListTile + 色板 Opacity/AbsorbPointer 硬互斥
8. 新增 3 测试文件（provider/store/widget）
9. 修改现有 settings 测试补 stub
10. `flutter analyze` + `flutter test` + grep 6 + 1 硬约束
11. commit + push（不打 tag，不发版——沿用 M25 图标策略）
12. 更新 HANDOFF.md 加第 7 条硬约束 + M25 动态取色段
13. 更新 CHANGELOG.md Unreleased 段

## 6. 回滚预案

- 改动 6 文件：pubspec.yaml / app.dart / theme_controller.dart / secure_config_store.dart / settings_page.dart / build.gradle.kts
- `git revert <commit>` 即可恢复
- 不涉及数据库迁移，无数据风险
- 回滚后 minSdk 回 24，dynamic_color 依赖移除，主题回到 fromSeed 单源
- 回滚零风险

## 7. 交付物清单

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `pubspec.yaml` | 加依赖 | `dynamic_color: ^1.7.0` |
| `android/app/build.gradle.kts` | 值修改 | minSdk = flutter.minSdkVersion → 31 |
| `lib/core/theme/theme_controller.dart` | 新增 Provider | `useDynamicColorProvider` |
| `lib/core/config/secure_config_store.dart` | 新增方法 | `getUseDynamicColor` / `setUseDynamicColor` |
| `lib/main.dart` | 修改启动期 | `Future.wait` 并行读 themeSeed + useDynamicColor |
| `lib/app.dart` | 改造 build | `DynamicColorBuilder` 包裹 + 三态决策 |
| `lib/features/settings/settings_page.dart` | 加 UI + 改色板 | SwitchListTile + Opacity/AbsorbPointer 硬互斥 |
| `test/core/theme_controller_test.dart` | 新增 | Provider 单测 |
| `test/core/secure_config_store_dynamic_color_test.dart` | 新增 | Store 读写单测 |
| `test/app_dynamic_color_test.dart` | 新增 | Widget 三态决策测试 |
| 现有 settings 测试 | 修改 | 补 `getUseDynamicColor()` stub |
| `HANDOFF.md` | 更新 | 加第 7 条硬约束 + M25 动态取色段 |
| `CHANGELOG.md` | 更新 | Unreleased 段加动态取色 |

## 8. 后续待办

- 本地真机验证动态取色（Android 12+ 设备，沙箱无法完成，用户手动）
- 截图采集放 `docs/screenshots/` 后补 README（用户手动）
- 如发版需打 tag + Release notes，本次不做
