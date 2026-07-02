# Material 3 全量改造设计文档

## 概述

将 EatWise 全部 13 个页面从当前"基础 M3 启用 + 大量硬编码颜色"升级为纯正 Material 3 设计规范，包含主题系统、组件升级、暗色模式，零硬编码颜色。

## 当前状态

- `app.dart` 已启用 `useMaterial3: true`，但仅有 `ColorScheme.fromSeed(seedColor: Colors.green)`
- 51 处硬编码 `Colors.xxx`（green/red/grey/blue/orange/purple/amber/white）
- 3 处 `withValues(alpha:)` 透明度硬编码
- 6 处 `DropdownButton`（M2 组件，M3 应替换）
- 90 处 `InputDecoration`/`AlertDialog`（M2 样式，M3 应走主题）
- 无暗色模式
- 无组件级 `ThemeData` 定制

## 改造范围

### 1. 主题系统（app.dart）

```dart
MaterialApp.router(
  title: 'EatWise',
  theme: _lightTheme,
  darkTheme: _darkTheme,
  themeMode: ThemeMode.system,
)

static final _lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.green,
    brightness: Brightness.light,
  ),
  cardTheme: CardThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    elevation: 0,
    surfaceTintColor: Colors.transparent,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
  ),
  appBarTheme: const AppBarTheme(
    centerTitle: false, // M3 Large TopAppBar 风格，左对齐
  ),
  sliderTheme: const SliderThemeData(
    year2023: false, // M3 最新滑块样式
  ),
  dialogTheme: DialogThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28), // M3 对话框规范
    ),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
  ),
  navigationDrawerTheme: NavigationDrawerThemeData(
    indicatorShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
    ),
  ),
)

static final _darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.green,
    brightness: Brightness.dark,
  ),
  // 同 _lightTheme 的组件级定制
)
```

### 2. 硬编码颜色映射表

| 当前硬编码 | M3 ColorScheme 角色 | 用途 |
|-----------|-------------------|------|
| `Colors.green` | `primary` | 主色（进度、按钮、图标） |
| `Colors.green.shade50` | `secondaryContainer` | 推荐标签背景 |
| `Colors.green.shade700` | `onSecondaryContainer` | 推荐标签文字 |
| `Colors.green[700]` | `primary` | 校准页历史提示文字 |
| `Colors.red` | `error` | 超量/错误/删除 |
| `Colors.grey` | `onSurfaceVariant` | 次要文字 |
| `Colors.grey.shade200` | `surfaceContainerHighest` | 进度条背景 |
| `Colors.grey.shade300` | `outlineVariant` | 图表边框 |
| `Colors.grey.shade600` | `onSurfaceVariant` | 余额文字 |
| `Colors.blue` | `primary` | 蛋白质图表线 |
| `Colors.orange` | `tertiary` | 脂肪图表线/警告 |
| `Colors.orange.shade100` | `tertiaryContainer` | 多菜未命中背景 |
| `Colors.purple` | `secondary` | 碳水图表线/体重线 |
| `Colors.amber` | `primary` | 推荐灯泡图标 |
| `Colors.white` | `onPrimary` | Drawer/删除图标 |

### 3. 页面级改造

#### 3.1 首页看板（dashboard_page.dart）

**环形进度**：
- 已摄入弧：`colorScheme.primary`
- 剩余弧：`colorScheme.surfaceContainerHighest`
- 超量：`colorScheme.error`
- 余额文字：`colorScheme.onSurfaceVariant`

**宏量进度条**：
- 蛋白质：`colorScheme.primary`
- 脂肪：`colorScheme.tertiary`
- 碳水：`colorScheme.secondary`
- 进度条背景：`colorScheme.surfaceContainerHighest`

**推荐卡片**：
- 灯泡图标：`colorScheme.primary`
- 标签背景：`colorScheme.secondaryContainer`
- 标签文字：`colorScheme.onSecondaryContainer`
- 提示文字：`colorScheme.onSurfaceVariant`

**Drawer**：
- Header 背景：`colorScheme.primaryContainer`
- Header 文字：`colorScheme.onPrimaryContainer`

#### 3.2 拍照识别页（recognize_page.dart）

- 餐次 `DropdownButton` → `SegmentedButton<String>`（M3 标准选择器）
- `SegmentedButton` 颜色走 `colorScheme`

#### 3.3 校准页（calibration_page.dart）

- 低置信度警告：`colorScheme.error`
- 历史中位数提示：`colorScheme.primary`
- 未命中组分警告：`colorScheme.tertiary`（原 `Colors.orange`）
- 次要文字：`colorScheme.onSurfaceVariant`
- Slider/按钮：M3 默认样式走主题

#### 3.4 多菜页（multi_dish_page.dart）

- 分隔线：`colorScheme.outlineVariant`
- 次要文字：`colorScheme.onSurfaceVariant`
- 未命中标签背景：`colorScheme.tertiaryContainer`
- 未命中标签文字：`colorScheme.onTertiaryContainer`
- 加载指示器：`colorScheme.onPrimary`

#### 3.5 今日记录页（today_meals_page.dart）

- 删除背景：`colorScheme.errorContainer`
- 删除图标：`colorScheme.onErrorContainer`
- 默认食物图标：`colorScheme.onSurfaceVariant`
- broken_image 图标：`colorScheme.onSurfaceVariant`

#### 3.6 食物库页（food_library_page.dart）

- 搜索 `TextField` + `OutlineInputBorder` → M3 `SearchBar` 组件
- 空状态文字：`colorScheme.onSurfaceVariant`

#### 3.7 个人档案页（profile_page.dart）

- `DropdownButtonFormField` → M3 样式（走 `dropdownMenuTheme`）
- 所有 `InputDecoration` 走 M3 默认 outlined 样式

#### 3.8 体重记录页（weight_page.dart）

- 图表边框：`colorScheme.outlineVariant`
- 热量线：`colorScheme.tertiary`（原 orange）
- 体重线：`colorScheme.primary`（原 green）
- 体重线区域：`colorScheme.primary.withValues(alpha: 0.1)`

#### 3.9 AI 周报页（insight_page.dart）

- 热量图表边框：`colorScheme.outlineVariant`
- 目标参考线：`colorScheme.primary`
- 均值参考线：`colorScheme.tertiary`
- 热量线：`colorScheme.primary`（原 blue）
- 热量线区域：`colorScheme.primary.withValues(alpha: 0.1)`
- 体重线：`colorScheme.secondary`（原 purple）

#### 3.10 手动录入页（manual_entry_page.dart）

- 餐次 `DropdownButton` → `SegmentedButton<String>`
- 所有 `InputDecoration` 走 M3 默认样式

#### 3.11 食物编辑页（food_edit_page.dart）

- 来源图标 + 文字：`colorScheme.onSurfaceVariant`
- 所有 `InputDecoration` 走 M3 默认样式

#### 3.12 设置页（settings_page.dart）

- 警告文字：`colorScheme.tertiary`（原 orange）
- 次要文字：`colorScheme.onSurfaceVariant`
- 图片保留期 `DropdownButton` → M3 `DropdownMenu`

#### 3.13 备份页（backup_page.dart）

- 说明文字：`colorScheme.onSurfaceVariant`
- `InputDecoration` 走 M3 默认样式

### 4. 对话框统一改造

所有 `AlertDialog` 走 `dialogTheme`（M3 圆角 28），无需逐个改。`InputDecoration(border: OutlineInputBorder())` 统一删除，走 M3 默认 outlined 样式。

### 5. 不改动的部分

- 业务逻辑：零改动
- 状态管理（Riverpod）：零改动
- 数据库（Drift）：零改动
- 路由（GoRouter）：零改动
- 导航刷新逻辑（本轮已修复）：零改动
- fl_chart 图表结构：仅改颜色引用，不改数据逻辑

## 实施顺序

1. **主题系统**：`app.dart` 添加 `_lightTheme` + `_darkTheme` + 组件级定制
2. **首页看板**：dashboard_page.dart 硬编码颜色替换（最核心页面）
3. **识别链路**：recognize_page + calibration_page + multi_dish_page
4. **记录页**：today_meals_page + manual_entry_page
5. **库页**：food_library_page + food_edit_page
6. **配置页**：profile_page + weight_page + settings_page
7. **其他页**：insight_page + backup_page
8. **验证**：`flutter analyze` + `flutter test` 全量通过

## 测试策略

- 每个 step 完成后运行 `flutter analyze` 确认零问题
- 全部完成后运行 `flutter test` 确认 242 个测试通过
- widget 测试中的 `MaterialApp` 需确保提供 M3 ThemeData（现有测试已用 `MaterialApp` 默认主题，M3 已启用，无需改测试代码）

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| `SegmentedButton` 替换 `DropdownButton` 改动较大 | 保留相同 state 逻辑，仅换 UI 组件 |
| fl_chart 颜色在暗色模式下对比度不足 | 用 ColorScheme 角色自动适配，`fromSeed` 保证对比度 |
| `SearchBar` API 与 `TextField` 不同 | 仅 food_library_page 一处，适配简单 |
| 测试中硬编码颜色断言 | 现有测试不涉及颜色断言（已确认） |
