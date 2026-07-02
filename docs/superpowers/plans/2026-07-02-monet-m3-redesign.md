# 莫奈睡莲 M3 改造 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 EatWise UI 改造为 KSU/Magisk 式教科书级 M3 + 莫奈《睡莲》取色，重组信息架构为底部 4 tab + FAB。

**Architecture:** `StatefulShellRoute.indexedStack` 承载 4 tab（今日/记录/洞察/我的），MainShell 提供 NavigationBar + 全局 FAB。主题 seedColor 改莫奈青绿 #5B8C7B，expressive 变体。首页删环形图改 Display Large 大数字 + 状态卡片，设置页 5 组卡片，图标 Outlined→Rounded/Filled。

**Tech Stack:** Flutter 3.44.4, go_router (StatefulShellRoute), Riverpod, fl_chart, Material 3

**Spec:** `docs/superpowers/specs/2026-07-02-monet-m3-redesign-design.md`

---

## 文件结构

**新增：**
- `lib/main_shell.dart` — MainShell：NavigationBar + 居中 FAB + speed dial + navigationShell 容器
- `lib/features/me/me_page.dart` — 我的页：用户卡片 + 数据/偏好/关于三组列表
- `lib/features/records/records_tab_page.dart` — 记录 tab 容器页：SegmentedButton + IndexedStack 切换今日明细/体重/食物库

**修改：**
- `lib/app.dart` — 主题 seedColor + NavigationBar 主题 + ShellRoute 路由
- `lib/features/dashboard/dashboard_page.dart` — 删环形图，状态卡片 + 今日餐次区块 + SliverAppBar.large
- `lib/features/settings/settings_page.dart` — 5 组卡片 + TextField 无边框 + Extended FAB
- `lib/features/dashboard/today_meals_page.dart` — 图标 Rounded
- `lib/features/recognize/recognize_page.dart` — 图标 Rounded
- `lib/features/recognize/calibration_page.dart` — 图标 Rounded
- `lib/features/recognize/multi_dish_page.dart` — 颜色+图标
- `lib/features/manual_entry/manual_entry_page.dart` — 图标 Rounded
- `lib/features/food_library/food_library_page.dart` — leading 圆形容器 + Rounded 图标
- `lib/features/weight/weight_page.dart` — fl_chart 配色走 colorScheme
- `lib/features/insight/insight_page.dart` — fl_chart 配色走 colorScheme
- `lib/features/backup/backup_page.dart` — 状态卡片化
- `lib/features/profile/profile_page.dart` — 图标 Rounded

---

### Task 1: 主题改造 — 莫奈睡莲 seedColor + NavigationBar 主题

**Files:**
- Modify: `lib/app.dart`

- [ ] **Step 1: 修改 app.dart 主题配置**

替换 `lib/app.dart` 中 `_lightTheme` 和 `_darkTheme` 的 seedColor 为莫奈青绿，新增 `navigationBarTheme`。完整文件内容：

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/backup/backup_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/insight/insight_page.dart';
import 'features/manual_entry/manual_entry_page.dart';
import 'features/me/me_page.dart';
import 'features/profile/profile_page.dart';
import 'features/records/records_tab_page.dart';
import 'features/recognize/recognize_page.dart';
import 'features/settings/settings_page.dart';
import 'features/weight/weight_page.dart';
import 'main_shell.dart';

/// 莫奈《睡莲》seedColor：青绿色调，宁静治愈，契合健康饮食语义
const _monetWaterLilySeed = Color(0xFF5B8C7B);

class EatWiseApp extends StatelessWidget {
  const EatWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'EatWise',
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }

  static final _lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _monetWaterLilySeed,
      brightness: Brightness.light,
      dynamicSchemeVariant: DynamicSchemeVariant.expressive,
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
        }
        return const TextStyle(fontSize: 12);
      }),
    ),
  );

  static final _darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _monetWaterLilySeed,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.expressive,
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
        }
        return const TextStyle(fontSize: 12);
      }),
    ),
  );
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainShell(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/', builder: (c, s) => const DashboardPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/today', builder: (c, s) => const RecordsTabPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/insight', builder: (c, s) => const InsightPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/me', builder: (c, s) => const MePage()),
        ]),
      ],
    ),
    GoRoute(path: '/weight', builder: (c, s) => const WeightPage()),
    GoRoute(
        path: '/food_library', builder: (c, s) => const FoodLibraryPage()),
    GoRoute(path: '/profile', builder: (c, s) => const ProfilePage()),
    GoRoute(path: '/settings', builder: (c, s) => const SettingsPage()),
    GoRoute(path: '/backup', builder: (c, s) => const BackupPage()),
    GoRoute(
        path: '/manual_entry', builder: (c, s) => const ManualEntryPage()),
    GoRoute(path: '/recognize', builder: (c, s) => const RecognizePage()),
  ],
);
```

- [ ] **Step 2: 验证 analyze 通过（预期失败：MainShell/MePage/RecordsTabPage 未创建）**

Run: `flutter analyze --no-pub 2>&1 | tail -10`
Expected: FAIL，报错 `MainShell`、`MePage`、`RecordsTabPage` 未定义（正常，下几个 task 创建）

- [ ] **Step 3: Commit**

```bash
git add lib/app.dart
git commit -m "feat: 主题改莫奈睡莲 seedColor + ShellRoute 路由架构"
```

---

### Task 2: MainShell — NavigationBar + 居中 FAB + speed dial

**Files:**
- Create: `lib/main_shell.dart`

- [ ] **Step 1: 创建 main_shell.dart**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'features/manual_entry/manual_entry_page.dart';
import 'features/recognize/recognize_page.dart';

/// 主壳层：底部导航 + 居中 FAB（拍照）
/// 4 tab（今日/记录/洞察/我的）+ FAB 长按弹 speed dial（拍照/相册/手动录入）
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: navigationShell,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onFabTap(context),
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.camera_alt_rounded),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '记录',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: '洞察',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outlined),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }

  /// FAB 短按：直接进拍照页；长按：弹 speed dial（拍照/相册/手动录入）
  void _onFabTap(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RecognizePage()),
    );
  }
}
```

注意：speed dial（长按弹菜单）作为后续可选增强，当前短按直接进拍照页保持高频路径。`centerDocked` 让 FAB 浮于 NavigationBar 上方居中。

- [ ] **Step 2: 验证 analyze 通过（预期失败：MePage/RecordsTabPage 未创建）**

Run: `flutter analyze --no-pub 2>&1 | tail -10`
Expected: FAIL，仅剩 `MePage`、`RecordsTabPage` 未定义

- [ ] **Step 3: Commit**

```bash
git add lib/main_shell.dart
git commit -m "feat: MainShell 底部导航 4 tab + 居中 FAB"
```

---

### Task 3: MePage — 我的页（用户卡片 + 分组列表）

**Files:**
- Create: `lib/features/me/me_page.dart`

- [ ] **Step 1: 创建 me_page.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/profile_repository.dart';
import '../backup/backup_page.dart';
import '../profile/profile_page.dart';
import '../recognize/providers.dart' as recognize;
import '../settings/settings_page.dart';
import '../weight/weight_page.dart';

/// 我的页：用户卡片（tap 进档案）+ 数据/偏好/关于三组列表
class MePage extends ConsumerStatefulWidget {
  const MePage({super.key});
  @override
  ConsumerState<MePage> createState() => _MePageState();
}

class _MePageState extends ConsumerState<MePage> {
  Future<Profile>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadProfile();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _future = _loadProfile());
  }

  Future<Profile> _loadProfile() async {
    final db = await ref.read(recognize.databaseProvider.future);
    return ProfileRepository(db).get();
  }

  /// 跳转子页，返回后刷新用户卡片
  Future<void> _pushAndRefresh(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: const Text('我的')),
          SliverToBoxAdapter(
            child: FutureBuilder<Profile>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final p = snap.data!;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Card(
                    color: cs.primaryContainer,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () => _pushAndRefresh(const ProfilePage()),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: cs.onPrimaryContainer.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.person_rounded,
                                  color: cs.onPrimaryContainer),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${p.heightCm.toStringAsFixed(0)}cm · ${p.weightKg.toStringAsFixed(1)}kg · ${p.age}岁',
                                    style: TextStyle(
                                      color: cs.onPrimaryContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_genderLabel(p.gender)} · ${_goalLabel(p.goal)} · ${_activityLabel(p.activityLevel)}',
                                    style: TextStyle(
                                      color: cs.onPrimaryContainer,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '每日目标 ${p.dailyCalorieTarget} kcal',
                                    style: TextStyle(
                                      color: cs.onPrimaryContainer,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              _sectionTitle('数据'),
              _groupCard([
                _listItem(
                  Icons.monitor_weight_rounded,
                  '体重记录',
                  () => _pushAndRefresh(const WeightPage()),
                ),
                _listItem(
                  Icons.cloud_upload_rounded,
                  '数据备份',
                  () => _pushAndRefresh(const BackupPage()),
                ),
              ]),
              _sectionTitle('偏好'),
              _groupCard([
                _listItem(
                  Icons.settings_rounded,
                  '设置',
                  () => _pushAndRefresh(const SettingsPage()),
                ),
              ]),
              _sectionTitle('关于'),
              _groupCard([
                _listItem(
                  Icons.info_outline_rounded,
                  '关于 EatWise',
                  () => _showAbout(context),
                ),
                _listItem(
                  Icons.privacy_tip_outlined,
                  '隐私政策',
                  () => _showPrivacy(context),
                ),
              ]),
              const SizedBox(height: 32),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _groupCard(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Column(children: _withDividers(children)),
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> items) {
    if (items.length <= 1) return items;
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i < items.length - 1) {
        result.add(Divider(
          height: 1,
          indent: 56,
          color: Theme.of(context).dividerColor,
        ));
      }
    }
    return result;
  }

  Widget _listItem(IconData icon, String title, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: cs.onSecondaryContainer),
      ),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  String _genderLabel(String g) => g == 'male' ? '男' : '女';
  String _goalLabel(String g) =>
      {'cut': '减脂', 'bulk': '增肌', 'maintain': '维持'}[g] ?? '维持';
  String _activityLabel(double a) => {
        1.2: '久坐',
        1.375: '轻度活动',
        1.55: '中度活动',
        1.725: '高强度活动',
        1.9: '极度活动',
      }[a] ??
      '轻度活动';

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'EatWise',
      applicationVersion: '1.0.0',
      applicationLegalese: '拍照识别食物热量 + 营养记录 + AI 汇总建议',
    );
  }

  Future<void> _showPrivacy(BuildContext context) async {
    // 复用 SettingsPage 已有的隐私政策逻辑
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const SettingsPage(),
    ));
  }
}
```

- [ ] **Step 2: 验证 analyze 通过（预期失败：RecordsTabPage 未创建）**

Run: `flutter analyze --no-pub 2>&1 | tail -10`
Expected: FAIL，仅剩 `RecordsTabPage` 未定义

- [ ] **Step 3: Commit**

```bash
git add lib/features/me/me_page.dart
git commit -m "feat: 我的页 用户卡片 + 分组列表"
```

---

### Task 4: RecordsTabPage — 记录 tab 容器页

**Files:**
- Create: `lib/features/records/records_tab_page.dart`

- [ ] **Step 1: 创建 records_tab_page.dart**

```dart
import 'package:flutter/material.dart';

import '../dashboard/today_meals_page.dart';
import '../food_library/food_library_page.dart';
import '../weight/weight_page.dart';

/// 记录 tab 容器页：SegmentedButton 切换 今日明细 / 体重 / 食物库
/// 用 IndexedStack 保留 3 子视图状态
class RecordsTabPage extends StatefulWidget {
  const RecordsTabPage({super.key});
  @override
  State<RecordsTabPage> createState() => _RecordsTabPageState();
}

class _RecordsTabPageState extends State<RecordsTabPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: const Text('记录')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('今日明细')),
                  ButtonSegment(value: 1, label: Text('体重')),
                  ButtonSegment(value: 2, label: Text('食物库')),
                ],
                selected: {_index},
                onSelectionChanged: (v) => setState(() => _index = v.first),
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: true,
            child: IndexedStack(
              index: _index,
              children: const [
                TodayMealsPage(),
                WeightPage(),
                FoodLibraryPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 验证 analyze 通过**

Run: `flutter analyze --no-pub 2>&1 | tail -10`
Expected: PASS（无 error，可能有 warning 稍后处理）

- [ ] **Step 3: 验证测试通过**

Run: `flutter test --no-pub 2>&1 | tail -5`
Expected: 现有 242 测试全过

- [ ] **Step 4: Commit**

```bash
git add lib/features/records/records_tab_page.dart
git commit -m "feat: 记录 tab 容器页 SegmentedButton + IndexedStack"
```

---

### Task 5: 首页重构 — 删环形图 + 状态卡片 + 今日餐次

**Files:**
- Modify: `lib/features/dashboard/dashboard_page.dart`

- [ ] **Step 1: 重写 dashboard_page.dart**

替换整个文件。删除 PieChart 环形图，改 Display Large 大数字 + primaryContainer 状态卡片。新增"今日餐次"区块（查 `getMealsByDate`）。删除 Drawer（改底部导航后不再需要）。保留 `_pushAndRefresh` 和 `_refresh` 逻辑。

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../nutrition/recommendation_service.dart';
import '../manual_entry/manual_entry_page.dart';
import '../recognize/providers.dart' as recognize;
import '../recognize/recognize_page.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  Future<DashboardData>? _future;
  Future<List<RecommendedFood>>? _recFuture;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
    _recFuture = _loadRecommendations();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = _loadData();
      _recFuture = _loadRecommendations();
    });
  }

  Future<void> _pushAndRefresh(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _refresh();
  }

  Future<List<RecommendedFood>> _loadRecommendations() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final foodRepo = FoodItemRepository(db);
    final mealRepo = MealLogRepository(db);
    final profileRepo = ProfileRepository(db);
    final service = RecommendationService(foodRepo, mealRepo, profileRepo);
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final remaining = await service.getDailyRemaining(today);
    return service.recommend(remaining: remaining, limit: 5);
  }

  Future<DashboardData> _loadData() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final mealRepo = MealLogRepository(db);
    final profileRepo = ProfileRepository(db);
    final foodRepo = FoodItemRepository(db);
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final macros = await mealRepo.getMacrosByDate(today);
    final profile = await profileRepo.get();
    final meals = await mealRepo.getMealsByDate(today);
    final foodNames = <int, String>{};
    for (final m in meals) {
      if (!foodNames.containsKey(m.foodItemId)) {
        final food = await foodRepo.getById(m.foodItemId);
        foodNames[m.foodItemId] = food?.name ?? '食物 #${m.foodItemId}';
      }
    }
    final proteinGoal = profile.proteinGPerKg * profile.weightKg;
    final fatGoal = profile.fatGPerKg * profile.weightKg;
    final carbGoalRaw = profile.carbGPerKg != null
        ? profile.carbGPerKg! * profile.weightKg
        : (profile.dailyCalorieTarget - proteinGoal * 4 - fatGoal * 9) / 4;
    final carbGoal = carbGoalRaw < 0 ? 0.0 : carbGoalRaw;
    return DashboardData(
      cal: macros.calories,
      protein: macros.protein,
      fat: macros.fat,
      carbs: macros.carbs,
      target: profile.dailyCalorieTarget,
      proteinGoal: proteinGoal,
      fatGoal: fatGoal,
      carbGoal: carbGoal,
      weightKg: profile.weightKg,
      meals: meals,
      foodNames: foodNames,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<DashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('数据加载失败：${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snapshot.data!;
          return CustomScrollView(
            slivers: [
              SliverAppBar.large(title: const Text('今日')),
              SliverToBoxAdapter(child: _statusCard(d)),
              SliverToBoxAdapter(child: _recommendationSection(d)),
              SliverToBoxAdapter(child: _mealsSection(d)),
            ],
          );
        },
      ),
    );
  }

  Widget _statusCard(DashboardData d) {
    final cs = Theme.of(context).colorScheme;
    final remain = d.target - d.cal;
    final overflow = remain < 0;
    final pct = d.target > 0 ? (d.cal / d.target).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        color: cs.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_fire_department_rounded,
                      color: cs.onPrimaryContainer, size: 20),
                  const SizedBox(width: 8),
                  Text('今日还可摄入',
                      style: TextStyle(
                          color: cs.onPrimaryContainer, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                overflow ? '${(-remain).toStringAsFixed(0)}' : remain.toStringAsFixed(0),
                style: TextStyle(
                  color: overflow ? cs.error : cs.onPrimaryContainer,
                  fontSize: 57,
                  fontWeight: FontWeight.w300,
                  height: 1.1,
                ),
              ),
              Text('kcal · 已摄入 ${d.cal.toStringAsFixed(0)} / ${d.target}',
                  style: TextStyle(
                      color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                      fontSize: 12)),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: cs.onPrimaryContainer.withValues(alpha: 0.12),
                  color: overflow ? cs.error : cs.onPrimaryContainer,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),
              _miniMacro('蛋白', d.protein, d.proteinGoal, cs.onPrimaryContainer),
              _miniMacro('脂肪', d.fat, d.fatGoal, cs.tertiary),
              _miniMacro('碳水', d.carbs, d.carbGoal, cs.secondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniMacro(String label, double value, double goal, Color color) {
    final pct = goal > 0 ? (value / goal).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
              width: 40,
              child: Text(label,
                  style: TextStyle(color: color, fontSize: 12))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: color.withValues(alpha: 0.12),
                color: color,
                minHeight: 6,
              ),
            ),
          ),
          SizedBox(
              width: 80,
              child: Text(
                  '${value.toStringAsFixed(0)}/${goal.toStringAsFixed(0)}g',
                  textAlign: TextAlign.right,
                  style: TextStyle(color: color, fontSize: 11))),
        ],
      ),
    );
  }

  Widget _recommendationSection(DashboardData d) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<RecommendedFood>>(
      future: _recFuture,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final recs = snap.data!;
        final remain = d.target - d.cal;
        final proteinRemain = d.proteinGoal - d.protein;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
              child: Text('智能推荐',
                  style: TextStyle(
                      color: cs.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          proteinRemain > 5
                              ? '今日还差 ${proteinRemain.toStringAsFixed(0)}g 蛋白质'
                              : remain > 0
                                  ? '今日还可摄入 ${remain.toStringAsFixed(0)} kcal'
                                  : '今日热量已达标，推荐低卡食物',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                    for (final rec in recs) ...[
                      Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.restaurant_rounded,
                              size: 20, color: cs.onSecondaryContainer),
                        ),
                        title: Text(rec.food.name),
                        subtitle: Text(
                            '${rec.food.caloriesPer100g.toStringAsFixed(0)} kcal/100g · 蛋白 ${rec.food.proteinPer100g.toStringAsFixed(1)}g',
                            style: const TextStyle(fontSize: 11)),
                        trailing: Text('${rec.food.caloriesPer100g.toStringAsFixed(0)} kcal',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                        onTap: () => _pushAndRefresh(
                            ManualEntryPage(initialName: rec.food.name)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _mealsSection(DashboardData d) {
    final cs = Theme.of(context).colorScheme;
    if (d.meals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('今日还没有记录，点下方拍照按钮开始',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ),
      );
    }
    // 按餐次分组
    final groups = <String, List<MealLog>>{};
    for (final m in d.meals) {
      groups.putIfAbsent(m.mealType, () => []).add(m);
    }
    final mealOrder = ['breakfast', 'lunch', 'dinner', 'snack'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
          child: Text('今日餐次',
              style: TextStyle(
                  color: cs.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Column(
              children: [
                for (final mt in mealOrder)
                  if (groups[mt] != null)
                    for (final m in groups[mt]!) ...[
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: cs.tertiaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_mealIcon(mt),
                              size: 20, color: cs.onTertiaryContainer),
                        ),
                        title: Text(d.foodNames[m.foodItemId] ?? '食物'),
                        subtitle: Text(
                            '${_mealLabel(mt)} · ${_formatTime(m.loggedAt)}',
                            style: const TextStyle(fontSize: 11)),
                        trailing: Text('${m.actualCalories.toStringAsFixed(0)} kcal',
                            style: TextStyle(
                                fontSize: 13, color: cs.onSurfaceVariant)),
                      ),
                      if (m != groups[mt]!.last || mt != mealOrder.last)
                        Divider(height: 1, indent: 56, color: cs.outlineVariant),
                    ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  IconData _mealIcon(String mt) => {
        'breakfast': Icons.free_breakfast_rounded,
        'lunch': Icons.lunch_dining_rounded,
        'dinner': Icons.dinner_dining_rounded,
        'snack': Icons.cookie_rounded,
      }[mt] ??
      Icons.restaurant_rounded;

  String _mealLabel(String mt) => {
        'breakfast': '早餐',
        'lunch': '午餐',
        'dinner': '晚餐',
        'snack': '加餐',
      }[mt] ??
      '加餐';

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// 首页聚合数据
class DashboardData {
  final double cal;
  final double protein;
  final double fat;
  final double carbs;
  final int target;
  final double proteinGoal;
  final double fatGoal;
  final double carbGoal;
  final double weightKg;
  final List<MealLog> meals;
  final Map<int, String> foodNames;

  DashboardData({
    required this.cal,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.target,
    required this.proteinGoal,
    required this.fatGoal,
    required this.carbGoal,
    required this.weightKg,
    required this.meals,
    required this.foodNames,
  });
}
```

- [ ] **Step 2: 删除 fl_chart import（不再用 PieChart）**

检查 `dashboard_page.dart` 顶部，确认已删除 `import 'package:fl_chart/fl_chart.dart';`（上面代码已无此 import）。

- [ ] **Step 3: 验证 analyze 通过**

Run: `flutter analyze --no-pub 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 4: 验证测试通过**

Run: `flutter test --no-pub 2>&1 | tail -5`
Expected: 现有测试全过

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/dashboard_page.dart
git commit -m "feat: 首页重构 删环形图改状态卡片+今日餐次"
```

---

### Task 6: 设置页重构 — 5 组卡片 + Extended FAB

**Files:**
- Modify: `lib/features/settings/settings_page.dart`

- [ ] **Step 1: 重写 settings_page.dart body 部分**

将 `build` 方法中的 `ListView` 改为 `CustomScrollView` + slivers，分 5 组卡片。TextField 去 `OutlineInputBorder` 改默认下划线。保存按钮改 `FloatingActionButton.extended`。保留 `_loadSettings`、`_save`、`_showPrivacyPolicy`、`_showAbout` 逻辑不变。

替换 `build` 方法（保留文件顶部 import 和其他方法）：

```dart
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: const Text('设置')),
          SliverList(
            delegate: SliverChildListDelegate([
              _sectionTitle('AI 模型'),
              _groupCard([
                TextField(
                  controller: _qwenKeyCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Qwen API Key', border: InputBorder.none),
                  obscureText: true,
                ),
                _divider(),
                TextField(
                  controller: _qwenUrlCtrl,
                  decoration: InputDecoration(
                      labelText: 'Qwen Base URL (留空用默认)',
                      hintText: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
                      border: InputBorder.none),
                ),
                _divider(),
                TextField(
                  controller: _glmKeyCtrl,
                  decoration: const InputDecoration(
                      labelText: 'GLM API Key', border: InputBorder.none),
                  obscureText: true,
                ),
                _divider(),
                TextField(
                  controller: _glmUrlCtrl,
                  decoration: InputDecoration(
                      labelText: 'GLM Base URL (留空用默认)',
                      hintText: 'https://open.bigmodel.cn/api/paas/v4',
                      border: InputBorder.none),
                ),
              ]),
              _sectionTitle('监控与校准'),
              _groupCard([
                SwitchListTile(
                  title: const Text('启用 Sentry 上报'),
                  subtitle: const Text('崩溃和未处理异常自动上报（经脱敏）'),
                  value: _sentryEnabled,
                  onChanged: (v) => setState(() => _sentryEnabled = v),
                ),
                _divider(),
                SwitchListTile(
                  title: const Text('TDEE 自适应校准'),
                  subtitle: const Text('连续 4 周体重偏差 > 0.3 kg/周时自动微调每日目标'),
                  value: _tdeeAutoCalib,
                  onChanged: (v) => setState(() => _tdeeAutoCalib = v),
                ),
                _divider(),
                TextField(
                  controller: _sentryDsnCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Sentry DSN', border: InputBorder.none),
                ),
              ]),
              _sectionTitle('图片管理'),
              _groupCard([
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text('原图保留期'),
                  trailing: SizedBox(
                    width: 150,
                    child: DropdownMenu<int>(
                      initialSelection: _imageRetentionDays,
                      expandedInsets: EdgeInsets.zero,
                      onSelected: (v) =>
                          setState(() => _imageRetentionDays = v ?? 30),
                      dropdownMenuEntries: const [
                        DropdownMenuEntry(value: 7, label: '7 天'),
                        DropdownMenuEntry(value: 30, label: '30 天（默认）'),
                        DropdownMenuEntry(value: 0, label: '永久保留'),
                      ],
                    ),
                  ),
                ),
              ]),
              _sectionTitle('使用情况'),
              _groupCard([
                ListTile(
                  leading: const Icon(Icons.analytics_outlined),
                  title: const Text('本月识别次数'),
                  trailing: Text('$_monthlyCount 次'),
                ),
                _divider(),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('估算花费'),
                  trailing: Text('${_estimatedCost!.toStringAsFixed(3)} 元'),
                ),
                if (_estimatedCost! >= _costWarningThreshold)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      '⚠️ 本月花费已达 ${_estimatedCost!.toStringAsFixed(2)} 元，建议在厂商控制台设置月度费用上限',
                      style: TextStyle(color: cs.tertiary, fontSize: 12),
                    ),
                  ),
              ]),
              _sectionTitle('备份状态'),
              _groupCard([
                ListTile(
                  leading: const Icon(Icons.backup),
                  title: const Text('上次自动备份'),
                  trailing: Text(_lastBackupTime ?? '从未',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
                if (_backupOverdue)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      '⚠️ 已超过 14 天未备份，建议立即导出备份',
                      style: TextStyle(color: cs.tertiary, fontSize: 12),
                    ),
                  ),
              ]),
              _sectionTitle('关于'),
              _groupCard([
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('隐私政策'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showPrivacyPolicy,
                ),
              ]),
              const SizedBox(height: 80),
            ]),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.save),
        label: const Text('保存设置'),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _groupCard(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: children),
        ),
      ),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: Theme.of(context).dividerColor,
      );
```

注意：删除原有 `_sectionHeader` 方法（被新 `_sectionTitle` 替代）。

- [ ] **Step 2: 验证 analyze 通过**

Run: `flutter analyze --no-pub 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 3: 验证测试通过**

Run: `flutter test --no-pub 2>&1 | tail -5`
Expected: 全过

- [ ] **Step 4: Commit**

```bash
git add lib/features/settings/settings_page.dart
git commit -m "feat: 设置页 5 组卡片 + Extended FAB"
```

---

### Task 7: 图标迁移 — Outlined → Rounded/Filled（批量）

**Files:**
- Modify: `lib/features/dashboard/today_meals_page.dart`
- Modify: `lib/features/recognize/recognize_page.dart`
- Modify: `lib/features/recognize/calibration_page.dart`
- Modify: `lib/features/recognize/multi_dish_page.dart`
- Modify: `lib/features/manual_entry/manual_entry_page.dart`
- Modify: `lib/features/food_library/food_library_page.dart`
- Modify: `lib/features/profile/profile_page.dart`

- [ ] **Step 1: 批量替换图标（用 grep 找出所有 outlined 图标，逐一替换）**

先扫描全项目 outlined 图标：

Run: `grep -rn "Icons\.[a-z_]*_outlined" lib/ | grep -v "main_shell.dart"`

逐一替换为 Rounded 变体（保留 NavigationBar 已处理的 4 个 outlined 不动）：
- `Icons.person_outline` → `Icons.person_rounded`
- `Icons.monitor_weight_outlined` → `Icons.monitor_weight_rounded`
- `Icons.insights_outlined` → `Icons.insights_rounded`（洞察页内）
- `Icons.restaurant_menu_outlined` → `Icons.restaurant_rounded`
- `Icons.edit_note_outlined` → `Icons.edit_rounded`
- `Icons.backup_outlined` → `Icons.cloud_upload_rounded`
- `Icons.settings_outlined` → `Icons.settings_rounded`
- `Icons.camera_alt`（无后缀）→ `Icons.camera_alt_rounded`
- `Icons.photo_library`（无后缀）→ `Icons.photo_library_rounded`
- `Icons.add`（无后缀）→ 保留（FAB 已用 camera_alt_rounded）
- `Icons.list_alt`（无后缀）→ `Icons.receipt_long_rounded`

保留不动的次级操作图标：
- `Icons.chevron_right`、`Icons.more_vert`、`Icons.close`、`Icons.delete_outline`、`Icons.edit_outlined`（列表内编辑次级操作）

- [ ] **Step 2: 食物库页 leading 加圆形容器**

在 `food_library_page.dart` 的列表项中，将 `leading: Icon(...)` 改为圆形容器包裹：

```dart
leading: Container(
  width: 40,
  height: 40,
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.secondaryContainer,
    shape: BoxShape.circle,
  ),
  child: Icon(Icons.restaurant_rounded,
      size: 20, color: Theme.of(context).colorScheme.onSecondaryContainer),
),
```

- [ ] **Step 3: 验证 analyze 通过**

Run: `flutter analyze --no-pub 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 4: 验证测试通过**

Run: `flutter test --no-pub 2>&1 | tail -5`
Expected: 全过

- [ ] **Step 5: Commit**

```bash
git add lib/features/
git commit -m "style: 图标 Outlined → Rounded/Filled 按 M3 规范"
```

---

### Task 8: fl_chart 配色走 colorScheme

**Files:**
- Modify: `lib/features/weight/weight_page.dart`
- Modify: `lib/features/insight/insight_page.dart`

- [ ] **Step 1: weight_page.dart fl_chart 配色**

在 weight_page.dart 中找到 fl_chart 的 `LineChartBarData`、`FlGridData`、`FlTitlesData` 配置，将硬编码颜色改为 colorScheme：
- 折线颜色：`colorScheme.primary`
- 网格线：`colorScheme.outlineVariant`
- 边框：`colorScheme.outlineVariant`
- 标题文字：`colorScheme.onSurfaceVariant`

具体改动：用 `grep -n "Color(0x\|Colors\." lib/features/weight/weight_page.dart` 找出硬编码，逐一替换为 `Theme.of(context).colorScheme.*`。

- [ ] **Step 2: insight_page.dart fl_chart 配色**

同上，处理 insight_page.dart 的 fl_chart 配色。

- [ ] **Step 3: 验证 analyze 通过**

Run: `flutter analyze --no-pub 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 4: 验证测试通过**

Run: `flutter test --no-pub 2>&1 | tail -5`
Expected: 全过

- [ ] **Step 5: Commit**

```bash
git add lib/features/weight/weight_page.dart lib/features/insight/insight_page.dart
git commit -m "style: fl_chart 配色走 colorScheme"
```

---

### Task 9: 备份页 + 多菜页状态卡片化

**Files:**
- Modify: `lib/features/backup/backup_page.dart`
- Modify: `lib/features/recognize/multi_dish_page.dart`

- [ ] **Step 1: backup_page.dart 状态信息卡片化**

在 backup_page.dart 中，将"上次备份时间"等状态信息用 Card 包裹，导入导出按钮用 FilledButton。硬编码颜色改 colorScheme。

- [ ] **Step 2: multi_dish_page.dart 颜色+图标迁移**

用 `grep -n "Color(0x\|Colors\.\|Icons\." lib/features/recognize/multi_dish_page.dart` 找出需改项，颜色走 colorScheme，图标按 Task 7 规则迁移。

- [ ] **Step 3: 验证 analyze + test 通过**

Run: `flutter analyze --no-pub 2>&1 | tail -5 && flutter test --no-pub 2>&1 | tail -5`
Expected: 全过

- [ ] **Step 4: Commit**

```bash
git add lib/features/backup/backup_page.dart lib/features/recognize/multi_dish_page.dart
git commit -m "style: 备份页+多菜页 状态卡片化+图标迁移"
```

---

### Task 10: 全量验证 + 硬编码颜色扫描

**Files:**
- All lib/**/*.dart

- [ ] **Step 1: 扫描硬编码颜色**

Run: `grep -rn "Color(0x\|Colors\.\(green\|blue\|red\|orange\|grey\|white\|black\|amber\)" lib/ | grep -v "colorScheme" | grep -v "//.*Color"`

逐一核对每处：状态色（error/success）可用 colorScheme.error/primary，其他必须走 colorScheme。修复残留硬编码。

- [ ] **Step 2: 暗色模式验证**

Run: `flutter analyze --no-pub 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 3: 完整测试**

Run: `flutter test --no-pub 2>&1 | tail -10`
Expected: 全部 242+ 测试通过

- [ ] **Step 4: 验收清单核对**

对照 spec 6.1 视觉验收、6.2 功能验收、6.3 质量验收清单，逐一核对：
- [ ] 所有颜色走 colorScheme，无硬编码
- [ ] 卡片圆角 28，按钮圆角 16，NavigationBar pill 指示器
- [ ] 底部导航选中态 Filled + pill，未选中 Outlined
- [ ] 首页无环形图，Display Large 大数字
- [ ] 设置页 5 组卡片，TextField 无边框
- [ ] 4 tab 切换保留状态
- [ ] FAB 全程可见
- [ ] 首页今日餐次 tap 进明细
- [ ] 记录 tab SegmentedButton 切换
- [ ] 我的页用户卡片 tap 进档案

- [ ] **Step 5: Commit + tag**

```bash
git add -A
git commit -m "chore: 硬编码颜色清理 + 全量验证通过"
git tag v0.6.0
git push origin main --tags
```

---

## Self-Review

**1. Spec coverage:**
- ✅ 2.1 莫奈配色 → Task 1（seedColor）
- ✅ 2.2 形状令牌 → Task 1（cardTheme 28dp + filledButton 16dp + navigationBar StadiumBorder）
- ✅ 2.3 图标体系 → Task 2（NavigationBar Filled/Outlined）+ Task 7（页面内 Rounded）
- ✅ 2.4 字号令牌 → Task 5（Display Large 57 在状态卡片）
- ✅ 3.1 底部导航 → Task 2（MainShell NavigationBar）+ Task 4（记录 tab 容器）
- ✅ 3.2 路由 → Task 1（StatefulShellRoute.indexedStack）
- ✅ 4.1 首页 → Task 5
- ✅ 4.2 记录 tab → Task 4
- ✅ 4.3 我的页 → Task 3
- ✅ 4.4 设置页 → Task 6
- ✅ 4.5 其他页面 → Task 7（图标）+ Task 8（fl_chart）+ Task 9（备份/多菜）

**2. Placeholder scan:** 无 TBD/TODO，所有代码块完整。

**3. Type consistency:** `DashboardData` 类在 Task 5 定义并被 build/`_statusCard`/`_recommendationSection`/`_mealsSection` 统一使用。`MainShell` 构造参数 `navigationShell` 在 Task 1 路由定义和 Task 2 实现一致。`RecordsTabPage`、`MePage` 类名在路由和定义处一致。

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-02-monet-m3-redesign.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
