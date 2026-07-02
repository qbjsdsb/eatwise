# EatWise 莫奈睡莲 M3 改造设计

> 日期：2026-07-02
> 状态：待实现
> 前置：2026-07-02-material3-redesign-design.md（已实施，本设计在其基础上重构信息架构与视觉风格）

## 1. 背景与目标

### 1.1 问题
当前 UI 虽已应用 M3 Expressive 色彩方案，但存在 4 个核心"丑"的来源：
1. **图标**：全项目用 `Icons.*_outlined`（线性），线条细碎、小尺寸单薄，"开发者默认"感
2. **首页**：环形图+三条横条 = "体检报告"既视感，缺层次和呼吸感
3. **导航**：Drawer 抽屉（7 入口）+ AppBar 图标按钮，入口分散、不符拇指操作
4. **配色**：单绿+纯白 = 医疗 App 感，缺 M3 的 surface 分层和 tonal 配色

### 1.2 目标
- 视觉风格：KSU Next / Magisk / APatch 式"教科书级 M3"，一眼有谷歌味道
- 配色：莫奈《睡莲》取色（青绿主色 + 睡莲粉强调），宁静治愈，契合健康饮食语义
- 信息架构：底部导航 4 tab + FAB 拍照，高频入口拇指可达，低频页归"我的"

### 1.3 非目标
- 不改业务逻辑、数据层、AI 调用链路
- 不新增/删除功能页面（9 个页面全部保留，仅重组导航归属）
- 不引入新依赖（fl_chart 保留，不换图表库）

## 2. 设计令牌（Design Tokens）

### 2.1 莫奈睡莲配色方案

采用 M3 `ColorScheme.fromSeed` + `DynamicSchemeVariant.expressive`，seedColor 为睡莲叶青绿。以下为目标感知色值（实际由 fromSeed 算法生成，用作验收基准）：

| 角色 | 用途 | 亮色模式 | 暗色模式 |
|------|------|----------|----------|
| `primary` | 关键 CTA、选中态强调 | #2D5A4A 深湖绿 | #B8E0CC 浅睡莲绿 |
| `onPrimary` | primary 上的文字 | #FFFFFF | #003821 |
| `primaryContainer` | 状态卡片底、选中容器 | #B8E0CC 浅睡莲绿 | #00513A |
| `onPrimaryContainer` | primaryContainer 上的文字 | #00210F | #B8E0CC |
| `secondary` | 次级操作、碳水宏量 | #4C6358 灰绿 | #B4CCBE |
| `tertiary` | 强调、警告、脂肪宏量 | #E8A5B8 睡莲粉 | #D8A5C0 |
| `surface` | 页面背景 | #F7FAF7 晨雾白 | #1A1F1B |
| `surfaceContainer` | 卡片底 | #EFF3EF | #2A302B |
| `surfaceContainerHigh` | 高层级卡片 | #E9EDE9 | #303732 |
| `onSurface` | 正文 | #1F2A24 墨绿黑 | #E1E3DE |
| `onSurfaceVariant` | 次要文字 | #424F48 | #C1C9BF |
| `error` | 错误、超热量 | #BA1A1A | #FFB4AB |

**实现要点：**
- `app.dart` 中 `seedColor: Color(0xFF5B8C7B)`（睡莲叶青绿），`dynamicSchemeVariant: DynamicSchemeVariant.expressive`
- 亮暗主题共用同一 seedColor，由 `brightness` 参数自动派生
- 所有页面颜色**禁止硬编码**，必须走 `Theme.of(context).colorScheme.*`

### 2.2 形状令牌（M3 规范）

| 元素 | 圆角 |
|------|------|
| 卡片（Card） | 28dp（M3 Large） |
| 对话框（Dialog） | 28dp |
| FAB | 20dp（M3 Large FAB） |
| FAB Extended | 20dp |
| 按钮（FilledButton） | 16dp（M3 Medium） |
| 输入框（TextField） | 8dp（M3 保留默认） |
| NavigationBar 指示器 | pill 形（StadiumBorder） |

### 2.3 图标体系（M3 规范）

| 场景 | 图标类型 | 示例 |
|------|----------|------|
| 底部导航选中态 | **Filled** | `Icons.home` `Icons.receipt_long` `Icons.insights` `Icons.person` |
| 底部导航未选中 | **Outlined** | `Icons.home_outlined` `Icons.receipt_long_outlined` `Icons.insights_outlined` `Icons.person_outlined` |
| 页面内主操作 | **Rounded** | `Icons.camera_alt_rounded` `Icons.photo_library_rounded` |
| 页面内次级操作 | **Outlined** | `Icons.chevron_right` `Icons.more_vert` |
| 列表项 leading | **Rounded**（圆形容器包裹） | `Icons.restaurant_rounded` `Icons.monitor_weight_rounded` |

**迁移规则：** 全项目 `Icons.*_outlined` → 按场景替换为 Rounded/Filled，仅保留次级操作用 Outlined。

### 2.4 字号令牌（M3 Type Scale）

| 角色 | TextStyle | 用途 |
|------|-----------|------|
| Display Large | 57/64 | 首页"760"大数字焦点 |
| Headline Medium | 28/36 | 页面大标题（LargeTopAppBar 展开） |
| Title Medium | 16/24 | 分区标题、卡片标题 |
| Body Large | 16/24 | 正文 |
| Body Small | 12/16 | 次要说明、宏量数值 |
| Label Large | 14/20 | 按钮文字 |

## 3. 信息架构

### 3.1 底部导航分组（方案 1：高频优先）

```
🏠 今日     📋 记录        📊 洞察      👤 我的
```

| Tab | 包含页面 | 路由 |
|-----|----------|------|
| 今日 | DashboardPage | `/` |
| 记录 | TodayMealsPage（默认）、WeightPage、FoodLibraryPage | `/today`、`/weight`、`/food_library` |
| 洞察 | InsightPage | `/insight` |
| 我的 | ProfilePage、SettingsPage、BackupPage | `/profile`、`/settings`、`/backup` |

**记录 tab 内部结构：** 顶部 `SegmentedButton<int>` 切换"今日明细 / 体重 / 食物库"3 个子视图，用 `IndexedStack` 保留各子视图状态。

**拍照入口：** FAB 居中浮于 NavigationBar 上方，全程可见（4 tab 任意页面都能点拍照）。长按 FAB 弹 speed dial：拍照 / 相册 / 手动录入。

**手动录入：** 不单独占 tab，通过 FAB speed dial + 记录 tab 内入口可达。

### 3.2 路由改造

- `app.dart` 用 `StatefulShellRoute.indexedStack` 包裹 4 个 tab 页面，共享 NavigationBar + FAB
- 每个 tab 是一个 `StatefulShellBranch`，内部用嵌套 Navigator 管理子页面栈
- FAB 在 shell 层，全局可见
- 非 tab 页面（RecognizePage、ManualEntryPage、CalibrationPage、MultiDishPage、ProfilePage、SettingsPage、BackupPage、WeightPage、FoodLibraryPage）用 `context.push` 走 root navigator 全屏覆盖
- 记录 tab 内部用 `IndexedStack` + `SegmentedButton<int>` 切换 3 子视图（非 TabBar，避免与 shell NavigationBar 语义混淆）

## 4. 页面设计

### 4.1 首页（今日 tab）

```
┌──────────────────────────────────────┐
│ 今日                          （LargeTopAppBar，滚动折叠）
│ ┌──────────────────────────────────┐ │
│ │  ● 今日还可摄入                  │ │ ← 状态大卡片
│ │     760                          │ │   primaryContainer 底
│ │     kcal                         │ │   圆角 28，padding 24
│ │  ━━━━━━━━━━━━━━━━━━━━ 62%       │ │   LinearProgressIndicator
│ │  已摄入 1240 / 2000 kcal         │ │
│ │                                  │ │
│ │  蛋白  60g ▓▓▓░░ 50%             │ │ ← 宏量迷你进度（横排）
│ │  脂肪  25g ▓▓░░░ 42%             │ │   紧凑，不用卡片
│ │  碳水 150g ▓▓▓▓░ 60%             │ │
│ └──────────────────────────────────┘ │
│                                      │
│ 智能推荐                          ▸  │ ← 分区标题
│ ┌──────────────────────────────────┐ │
│ │ ○ 鸡胸肉沙拉      蛋白缺口 ★     │ │ ← 推荐卡片
│ │   120 kcal/100g · 蛋白 24g       │ │   leading 圆形容器
│ │                          350 kcal│ │   trailing 推荐热量
│ └──────────────────────────────────┘ │
│ ┌──────────────────────────────────┐ │
│ │ ○ 希腊酸奶        蛋白缺口       │ │
│ │   60 kcal/100g · 蛋白 10g        │ │
│ └──────────────────────────────────┘ │
│                                      │
│ 今日餐次                              │ ← 分区标题
│ ┌──────────────────────────────────┐ │
│ │ ○ 早餐 · 鸡蛋三明治    08:30     │ │ ← 餐次卡片
│ │                    320 kcal       │ │   tap → 今日明细页
│ │ ○ 午餐 · 牛肉饭        12:15     │ │
│ │                    580 kcal       │ │
│ │ ○ 加餐 · 苹果          15:00     │ │
│ │                     80 kcal       │ │
│ └──────────────────────────────────┘ │
│              ┌────────┐              │
│              │   📷   │              │ ← FAB 居中
├──────────────────────────────────────┤
│  🏠■     📋       📊       👤       │ ← NavigationBar（今日选中）
└──────────────────────────────────────┘
```

**关键变更：**
- 删除环形图（PieChart），用 Display Large "760" 作视觉焦点
- 宏量从 3 条独立横条 → 状态卡片内 3 条迷你横排
- 新增"今日餐次"区块（当前 Dashboard 没有，需查 meal_log 当日记录）
- FAB 从右下角 → 居中浮于 NavigationBar 上方

**数据来源：**
- 状态卡片：`MealLogRepository.getMacrosByDate(today)` + `ProfileRepository.get()`
- 推荐卡片：`RecommendationService.recommend()`（已有）
- 今日餐次：`MealLogRepository.getByDate(today)`（新增查询，返回当日所有 meal_log）

### 4.2 记录 tab

顶部 SegmentedButton 切换 3 个子视图：

```
┌──────────────────────────────────────┐
│ 记录                          （LargeTopAppBar）
│ ┌──────────────────────────────────┐ │
│ │ [今日明细] [体重] [食物库]        │ │ ← SegmentedButton（3 段）
│ └──────────────────────────────────┘ │
│                                      │
│ （选中"今日明细"时显示 TodayMealsPage）│
│ （选中"体重"时显示 WeightPage 内容）  │
│ （选中"食物库"时显示 FoodLibraryPage）│
│                                      │
│              ┌────────┐              │
│              │   📷   │              │
├──────────────────────────────────────┤
│  🏠       📋■     📊       👤       │
└──────────────────────────────────────┘
```

**实现：** 用 `IndexedStack` + `SegmentedButton<int>` 切换 3 个子页面，保留各子页面状态。

### 4.3 我的页

```
┌──────────────────────────────────────┐
│ 我的                          （LargeTopAppBar）
│ ┌──────────────────────────────────┐ │
│ │  👤   178cm · 70kg · 25岁         │ │ ← 用户卡片
│ │       男 · 维持 · 中度活动        │ │   primaryContainer 底
│ │       每日目标 2000 kcal          │ │   tap → ProfilePage
│ │                          ▸        │ │
│ └──────────────────────────────────┘ │
│                                      │
│ 数据                                 │ ← 分组标题
│ ┌──────────────────────────────────┐ │
│ │ ○ 体重记录                    ▸  │ │ ← 卡片化列表
│ │ ○ 数据备份                    ▸  │ │
│ └──────────────────────────────────┘ │
│                                      │
│ 偏好                                 │
│ ┌──────────────────────────────────┐ │
│ │ ○ 设置                        ▸  │ │
│ └──────────────────────────────────┘ │
│                                      │
│ 关于                                 │
│ ┌──────────────────────────────────┐ │
│ │ ○ 关于 EatWise                ▸  │ │
│ │ ○ 隐私政策                    ▸  │ │
│ └──────────────────────────────────┘ │
├──────────────────────────────────────┤
│  🏠       📋       📊       👤■     │
└──────────────────────────────────────┘
```

**用户卡片数据：** `ProfileRepository.get()`，展示身高/体重/年龄/性别/目标/活动量/每日目标 7 项摘要。

### 4.4 设置页

当前一长串 ListView → 按功能分 5 组卡片：

```
┌──────────────────────────────────────┐
│ 设置                          （LargeTopAppBar）
│ AI 模型                               │ ← 分组标题
│ ┌──────────────────────────────────┐ │
│ │  Qwen API Key      ●●●●●●        │ │ ← TextField 无边框
│ │  Qwen Base URL     (默认)        │ │   分割线分组
│ │  ────────────────────────────    │ │
│ │  GLM API Key       ●●●●●●        │ │
│ │  GLM Base URL      (默认)        │ │
│ └──────────────────────────────────┘ │
│                                      │
│ 监控与校准                            │
│ ┌──────────────────────────────────┐ │
│ │  Sentry 上报           [开/关]    │ │ ← SwitchListTile
│ │  ────────────────────────────    │ │
│ │  TDEE 自适应校准       [开/关]    │ │
│ └──────────────────────────────────┘ │
│                                      │
│ 图片管理                              │
│ ┌──────────────────────────────────┐ │
│ │  原图保留期           30 天 ▾    │ │ ← DropdownMenu
│ └──────────────────────────────────┘ │
│                                      │
│ 使用情况                              │
│ ┌──────────────────────────────────┐ │
│ │  本月识别次数         12 次       │ │
│ │  ────────────────────────────    │ │
│ │  估算花费            0.012 元     │ │
│ │  ⚠️ 已达 5 元，建议设上限         │ │ ← tertiary 睡莲粉
│ └──────────────────────────────────┘ │
│                                      │
│ 备份状态                              │
│ ┌──────────────────────────────────┐ │
│ │  上次自动备份        2026-06-28   │ │
│ │  ⚠️ 已超 14 天，建议立即导出      │ │
│ └──────────────────────────────────┘ │
│              ┌──────────────┐        │
│              │ 💾 保存设置   │        │ ← Extended FAB
├──────────────────────────────────────┤
│  🏠       📋       📊       👤■     │
└──────────────────────────────────────┘
```

**改造要点：**
- ListView → 5 组 Card，每组内用 Divider 分隔项
- TextField 去 OutlineInputBorder → UnderlineInputBorder 透明（融入卡片）
- 警告文案用 `colorScheme.tertiary`（睡莲粉）
- 保存按钮 `FilledButton` → `FloatingActionButton.extended`

### 4.5 其他页面（保持现有结构，仅换色+图标）

| 页面 | 改造内容 |
|------|----------|
| WeightPage | fl_chart 网格线用 `outlineVariant`，折线用 `primary`，标题图标换 Rounded |
| InsightPage | SegmentedButton 周月切换保留，图表配色走 colorScheme |
| FoodLibraryPage | 列表项 leading 圆形容器+Rounded 图标，删除背景色改 `surfaceContainer` |
| ManualEntryPage | SegmentedButton 保留，输入框走 M3 默认 |
| RecognizePage | SegmentedButton 餐次保留，两个 FilledButton 换 Rounded 图标 |
| CalibrationPage | 滑块走 M3 默认，确认按钮 FilledButton |
| BackupPage | 导入导出按钮 FilledButton，"上次备份时间"等状态信息卡片化（与我的页备份入口解耦，BackupPage 是完整备份操作页，我的页仅入口） |

## 5. 技术实现

### 5.1 主题配置（app.dart）

```dart
// 莫奈睡莲 seedColor
static const _monetWaterLilySeed = Color(0xFF5B8C7B);

static final _lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _monetWaterLilySeed,
    brightness: Brightness.light,
    dynamicSchemeVariant: DynamicSchemeVariant.expressive,
  ),
  cardTheme: CardThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    elevation: 0,
    color: ColorScheme.fromSeed(seedColor: _monetWaterLilySeed, brightness: Brightness.light).surfaceContainer,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  appBarTheme: const AppBarTheme(centerTitle: false),
  dialogTheme: DialogThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
  navigationBarTheme: NavigationBarThemeData(
    indicatorShape: StadiumBorder(),  // pill 形指示器
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
      }
      return TextStyle(fontSize: 12);
    }),
  ),
);
```

### 5.2 路由与 ShellRoute

用 `StatefulShellRoute.indexedStack` 实现 4 tab + 嵌套 Navigator：

```dart
final _router = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainShell(navigationShell: navigationShell);
      },
      branches: [
        // 今日 tab
        StatefulShellBranch(routes: [
          GoRoute(path: '/', builder: (c, s) => const DashboardPage()),
        ]),
        // 记录 tab（内部用 IndexedStack 切换，路由只承载容器页）
        StatefulShellBranch(routes: [
          GoRoute(path: '/today', builder: (c, s) => const RecordsTabPage()),
        ]),
        // 洞察 tab
        StatefulShellBranch(routes: [
          GoRoute(path: '/insight', builder: (c, s) => const InsightPage()),
        ]),
        // 我的 tab
        StatefulShellBranch(routes: [
          GoRoute(path: '/me', builder: (c, s) => const MePage()),
        ]),
      ],
    ),
    // 非 tab 页面（root navigator 全屏覆盖）
    GoRoute(path: '/weight', builder: (c, s) => const WeightPage()),
    GoRoute(path: '/food_library', builder: (c, s) => const FoodLibraryPage()),
    GoRoute(path: '/profile', builder: (c, s) => const ProfilePage()),
    GoRoute(path: '/settings', builder: (c, s) => const SettingsPage()),
    GoRoute(path: '/backup', builder: (c, s) => const BackupPage()),
    GoRoute(path: '/manual_entry', builder: (c, s) => const ManualEntryPage()),
    GoRoute(path: '/recognize', builder: (c, s) => const RecognizePage()),
  ],
);
```

**记录 tab 容器页 `RecordsTabPage`（新增）：** 持有 `IndexedStack` + `SegmentedButton<int>`，内部 3 子视图直接实例化（不走子路由，保留状态）。

`MainShell` 是 StatelessWidget，包含：
- `Scaffold` + `body` = `navigationShell`（当前 tab 内容）
- `floatingActionButton` = 居中 FAB（拍照），长按弹 speed dial
- `bottomNavigationBar` = `NavigationBar`（4 destinations）

### 5.3 LargeTopAppBar

首页用 `FlexibleSpaceBar` + `SliverAppBar` 实现滚动折叠大标题：

```dart
CustomScrollView(
  slivers: [
    SliverAppBar.large(
      title: Text('今日'),
    ),
    SliverToBoxAdapter(child: statusCard),
    SliverToBoxAdapter(child: recommendationSection),
    SliverToBoxAdapter(child: mealsSection),
  ],
)
```

### 5.4 图标迁移

全项目批量替换：
- `Icons.person_outline` → `Icons.person_rounded`（页面内）/ `Icons.person`（选中态）
- `Icons.monitor_weight_outlined` → `Icons.monitor_weight_rounded`
- `Icons.insights_outlined` → `Icons.insights_rounded`
- `Icons.restaurant_menu_outlined` → `Icons.restaurant_rounded`
- `Icons.edit_note_outlined` → `Icons.edit_rounded`
- `Icons.backup_outlined` → `Icons.cloud_upload_rounded`
- `Icons.settings_outlined` → `Icons.settings_rounded`
- `Icons.camera_alt` → `Icons.camera_alt_rounded`
- `Icons.photo_library` → `Icons.photo_library_rounded`

## 6. 验收标准

### 6.1 视觉验收
- [ ] 所有颜色走 `colorScheme.*`，无硬编码（grep 检查 `Color(0x`、`Colors.green` 等）
- [ ] 卡片圆角 28，按钮圆角 16，NavigationBar pill 指示器
- [ ] 底部导航选中态 Filled 图标 + pill，未选中 Outlined
- [ ] 首页无环形图，用 Display Large 大数字作焦点
- [ ] 设置页 5 组卡片，TextField 无 OutlineInputBorder

### 6.2 功能验收
- [ ] 4 tab 切换保留各自状态（IndexedStack）
- [ ] FAB 拍照在 4 tab 全程可见，长按弹 speed dial（拍照/相册/手动录入）
- [ ] 首页"今日餐次"区块 tap 进今日明细页
- [ ] 记录 tab 的 SegmentedButton 切换今日明细/体重/食物库
- [ ] 我的页用户卡片 tap 进 ProfilePage
- [ ] 所有原有功能不受影响（识别/校准/备份/体重录入/洞察生成）

### 6.3 质量验收
- [ ] `flutter analyze` 零 issue
- [ ] `flutter test` 全部通过（现有 242 测试 + 新增导航/shell 测试）
- [ ] 暗色模式配色正确（莫奈睡莲暗色变体）
- [ ] 无 setState after dispose、无 null 崩溃（沿用前一轮审查的健壮性标准）

## 7. 影响范围

### 7.1 需修改的文件
| 文件 | 改动 |
|------|------|
| `lib/app.dart` | 主题 seedColor 改莫奈绿 + NavigationBar 主题 + ShellRoute 路由 |
| `lib/features/dashboard/dashboard_page.dart` | 重构：删环形图+横条，加状态卡片+今日餐次区块，SliverAppBar.large |
| `lib/features/dashboard/today_meals_page.dart` | 颜色+图标迁移 |
| `lib/features/recognize/recognize_page.dart` | 图标 Rounded |
| `lib/features/recognize/calibration_page.dart` | 图标 Rounded |
| `lib/features/recognize/multi_dish_page.dart` | 颜色+图标 |
| `lib/features/manual_entry/manual_entry_page.dart` | 图标 Rounded |
| `lib/features/food_library/food_library_page.dart` | leading 圆形容器+Rounded 图标 |
| `lib/features/weight/weight_page.dart` | fl_chart 配色走 colorScheme |
| `lib/features/insight/insight_page.dart` | fl_chart 配色走 colorScheme |
| `lib/features/backup/backup_page.dart` | 状态卡片化 |
| `lib/features/profile/profile_page.dart` | 图标 Rounded |
| `lib/features/settings/settings_page.dart` | 重构：5 组卡片 + TextField 无边框 + Extended FAB |
| `lib/main_shell.dart`（新增） | MainShell：NavigationBar + FAB + navigationShell |
| `lib/features/me/me_page.dart`（新增） | 我的页：用户卡片 + 分组列表 |
| `lib/features/records/records_tab_page.dart`（新增） | 记录 tab 容器页：SegmentedButton + IndexedStack 切换今日明细/体重/食物库 |

### 7.2 不修改的文件
- 数据层（`lib/data/**`）
- AI 层（`lib/ai/**`）
- 后台任务（`lib/background/**`）
- 营养计算（`lib/nutrition/**`）
- 核心配置（`lib/core/**`）

## 8. 风险与缓解

| 风险 | 缓解 |
|------|------|
| ShellRoute 嵌套 Navigator 与现有 push 路径冲突 | 子页面用 `context.push` 走 root navigator，非 tab 页用 `push` 全屏覆盖 |
| IndexedStack 4 tab 同时驻留内存 | 各 tab 页面轻量，且保留状态是用户期望（切换不丢失滚动位置） |
| LargeTopAppBar 滚动折叠需 CustomScrollView 改造 | 仅首页/我的/设置用 Sliver，其他页保持普通 Scaffold |
| FAB speed dial 长按交互新引入 | 长按可选，短按仍直接拍照（保持现有高频路径） |
| 图标批量替换漏改 | grep 全项目 `Icons.*_outlined` 逐一核对 |
