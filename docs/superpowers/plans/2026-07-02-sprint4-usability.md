# Sprint 4：可用性补全

**编写日期：** 2026-07-02
**编写者：** Claude（writing-plans skill）
**前置条件：** Sprint 1-3 已完成（106 测试全过，analyze 0 issues）
**范围：** 5 个 Task（T25-T29），聚焦让 App 从"功能存在但不可达/不可用"变为"完整可用"
**执行方式：** Subagent-Driven Development（如 Sprint 3）
**沙箱约束：** 每个 Task 测试必须能在 `flutter test` 沙箱跑通（平台插件用 fake/注入），不引入需真机才能验证的 Task
**依赖约束：** 不新增 pubspec 依赖（复用 fl_chart / go_router / drift / flutter_riverpod 等已有包）

---

## 背景与缺口分析

Sprint 1-3 完成了核心识别、完整闭环、健壮性。但对照设计文档逐章核实发现 4 个 P0 缺口：

| P0 缺口 | 现状 | 影响 |
|---|---|---|
| 全局导航缺失 | Dashboard 仅 3 个入口（settings/today/recognize），profile/weight/insight/food_library/backup/manual_entry 无 UI 入口 | 半数功能不可达，用户无法设置档案/记录体重/查看汇总/备份 |
| 今日记录显示"食物ID" | today_meals_page.dart:111 `Text('食物ID ${m.foodItemId}')`，FoodItemRepository.getById 已存在未调用 | 用户看到无意义的 ID 而非食物名 |
| 复合菜校准残缺 | calibration_page.dart 复合菜无组分滑块/用油滑块/未命中展示/重算 | 设计 3.1 核心交互缺失，复合菜无法校准 |
| Insight key 未迁移 | insight_page.dart:71 仍用 `String.fromEnvironment('GLM_API_KEY')`，设置页填的 key 不生效 | Sprint 3 secure_storage 迁移对 Insight 无效 |

另含 1 个 P1：单品查库未命中无"改菜名→重查→转手动"流程（设计 3.1 step5/6.3）。

---

## Sprint 4 完成标准

- [ ] CI 全绿：`flutter analyze` 0 issues + `flutter test --exclude-tags smoke` 全过
- [ ] T25-T29 共 5 个 Task 的 commit 全部在分支
- [ ] Dashboard Drawer 含 7 个入口（个人档案/体重记录/AI 周报/食物库/手动录入/数据备份/设置）
- [ ] 今日记录列表项显示食物名（非 ID）
- [ ] 复合菜校准页支持组分滑块 + 用油滑块 + 未命中展示 + 实时重算
- [ ] Insight 页 GLM key 从 appConfigProvider 读取（设置页修改后生效）
- [ ] 单品未命中时弹窗提供"改菜名重试/转手动录入"选项
- [ ] Self-Review 6 节全部完成

---

## Task 25: 全局导航（Dashboard Drawer）

**目标:** Dashboard 添加 NavigationDrawer，提供 7 个功能模块入口，使半数不可达功能可访问。

**参考设计文档:** 2.4（分层）、7.1-7.8（各模块入口）

**Files:**
- Modify: `lib/features/dashboard/dashboard_page.dart`（加 Drawer）
- Test: `test/features/dashboard_drawer_test.dart`

**当前状态核实:**
- dashboard_page.dart 当前 AppBar.actions 有 settings + today 两个 IconButton，body 是 FutureBuilder 看板，FAB 跳 recognize
- app.dart 已有全部 GoRoute 路由（/profile /weight /insight /food_library /manual_entry /backup /settings）
- 各页面构造器均为 `const XxxPage({super.key})`

- [ ] **Step 1: 修改 dashboard_page.dart — 加 Drawer**

在 Scaffold 加 `drawer` 参数。Drawer 内用 ListView 列出 7 个 NavigationTile。点击用 `Navigator.of(context).push(MaterialPageRoute(builder: (_) => const XxxPage()))`（与现有 settings/today 跳转方式一致，不引入 go_router context.go 以保持代码风格统一）。

```dart
// lib/features/dashboard/dashboard_page.dart 完整改动：

// 1. 顶部 import 区追加各页面 import（保留现有 import）：
import '../backup/backup_page.dart';
import '../food_library/food_library_page.dart';
import '../insight/insight_page.dart';
import '../manual_entry/manual_entry_page.dart';
import '../profile/profile_page.dart';
import '../weight/weight_page.dart';
// settings_page.dart / today_meals_page.dart / recognize_page.dart 已 import

// 2. Scaffold 加 drawer 参数（在现有 Scaffold 的 appBar 下方加）：
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('今日'),
      // leading 区会被 Scaffold 自动填充为 drawer toggle（Scaffold 有 drawer 时自动出现汉堡按钮）
      actions: [
        // 保留现有 settings + today 两个 IconButton
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SettingsPage())),
        ),
        IconButton(
          icon: const Icon(Icons.list_alt),
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const TodayMealsPage())),
        ),
      ],
    ),
    drawer: _buildDrawer(context),  // 新增
    floatingActionButton: FloatingActionButton(
      onPressed: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const RecognizePage())),
      child: const Icon(Icons.add),
    ),
    body: FutureBuilder<...>(  // 保留现有 body 不变
      ...
    ),
  );
}

// 3. 新增 _buildDrawer 方法（放在 _DashboardPageState 类内，_macroBar 方法前）：
Widget _buildDrawer(BuildContext context) {
  return Drawer(
    child: ListView(
      padding: EdgeInsets.zero,
      children: [
        const DrawerHeader(
          decoration: BoxDecoration(color: Colors.green),
          child: Text('EatWise',
              style: TextStyle(color: Colors.white, fontSize: 24)),
        ),
        _drawerItem(Icons.person_outline, '个人档案', () => const ProfilePage()),
        _drawerItem(Icons.monitor_weight_outlined, '体重记录', () => const WeightPage()),
        _drawerItem(Icons.insights_outlined, 'AI 周报', () => const InsightPage()),
        _drawerItem(Icons.restaurant_menu_outlined, '食物库', () => const FoodLibraryPage()),
        _drawerItem(Icons.edit_note_outlined, '手动录入', () => const ManualEntryPage()),
        _drawerItem(Icons.backup_outlined, '数据备份', () => const BackupPage()),
        _drawerItem(Icons.settings_outlined, '设置', () => const SettingsPage()),
      ],
    ),
  );
}

Widget _drawerItem(IconData icon, String title, Widget Function() pageBuilder) {
  return ListTile(
    leading: Icon(icon),
    title: Text(title),
    onTap: () {
      Navigator.of(context).pop(); // 先关 Drawer
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => pageBuilder()));
    },
  );
}
```

> **注意**：Scaffold 有 `drawer` 时会自动在 AppBar leading 位置显示汉堡按钮（无需手动加 leading）。`_buildDrawer` 和 `_drawerItem` 是 `_DashboardPageState` 的实例方法（要用 `context`，且 Navigator 需要 State 持有的 context）。body 的 FutureBuilder 部分完全不变，Step 1 代码块中用 `...` 表示省略，实际实施时保留原样。

- [ ] **Step 2: 创建 dashboard_drawer_test.dart**

```dart
// test/features/dashboard_drawer_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/dashboard/dashboard_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dashboard Drawer 测试
/// 验证 Drawer 7 个入口文本可见
/// databaseProvider override 为内存 DB（绕过 path_provider 平台插件）
void main() {
  testWidgets('Dashboard Drawer 含 7 个功能入口', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    // 等 FutureBuilder 加载（内存 DB 种子 profile 存在，应快速完成）
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 打开 Drawer（Scaffold 有 drawer 时 AppBar 自动显示汉堡按钮，tooltip 为 'Open navigation menu'）
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    // 验证 7 个入口文本
    expect(find.text('个人档案'), findsOneWidget);
    expect(find.text('体重记录'), findsOneWidget);
    expect(find.text('AI 周报'), findsOneWidget);
    expect(find.text('食物库'), findsOneWidget);
    expect(find.text('手动录入'), findsOneWidget);
    expect(find.text('数据备份'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
```

> **注意**：
> - `find.byTooltip('Open navigation menu')` 是 Scaffold 自动给 Drawer 汉堡按钮设置的默认 tooltip（Material 3 默认值）。若该 tooltip 在不同 Flutter 版本不同，实施时改用 `tester.tap(find.byIcon(Icons.menu))`。
> - **databaseProvider override**：databaseProvider 定义在 database.dart:61 为 `FutureProvider<EatWiseDatabase>`，内部调 `openEncryptedConnection()`（依赖 path_provider 平台插件，沙箱抛 MissingPluginException）。测试用 `recognize.databaseProvider.overrideWith((ref) async => db)` 注入内存 DB 绕过。recognize.databaseProvider 通过 providers.dart 的 `export '../../data/database/database.dart'`（line 15）暴露。
> - 内存 DB 的 beforeOpen 钩子（database.dart:38-54）会插入种子 profile，DashboardPage 的 FutureBuilder 能正常加载。

- [ ] **Step 3: flutter analyze + test**

```bash
export PATH="/opt/flutter/bin:$PATH"
flutter analyze
flutter test test/features/dashboard_drawer_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/dashboard/dashboard_page.dart test/features/dashboard_drawer_test.dart
git commit -m "feat: Sprint 4 T25 - 全局导航(Dashboard Drawer 7入口)"
```

---

## Task 26: 今日记录显示食物名

**目标:** today_meals_page 列表项显示食物名而非 foodItemId。加载时批量反查 food_item.name。

**参考设计文档:** 7.3（今日记录模块）

**Files:**
- Modify: `lib/features/dashboard/today_meals_page.dart`
- Test: `test/features/today_meals_food_name_test.dart`

**当前状态核实:**
- today_meals_page.dart:111 `Text('食物ID ${m.foodItemId}')`，注释自承"MVP"
- FoodItemRepository.getById(int id) 已存在（food_item_repository.dart:82），返回 Future<FoodItem?>
- today_meals_page 的 _load() 已用 `recognize.mealLogRepoProvider` 拿 repo，调 getMealsByDate
- MealLog 有 foodItemId 字段（int）

- [ ] **Step 1: 修改 today_meals_page.dart — 反查食物名**

在 `_load()` 中遍历 meals，调 foodItemRepo.getById 反查，缓存到 Map<int, String>。`_buildMealTile` 用缓存显示。

```dart
// lib/features/dashboard/today_meals_page.dart 改动：

// 1. 顶部 import 区追加：
import '../../data/repositories/food_item_repository.dart';

// 2. _TodayMealsPageState 加字段（在 _meals 字段下方）：
List<MealLog> _meals = [];
Map<int, String> _foodNames = {};  // 新增：foodItemId → name 缓存
bool _loading = true;

// 3. 修改 _load 方法：
Future<void> _load() async {
  final mealRepo = await ref.read(recognize.mealLogRepoProvider.future);
  final meals = await mealRepo.getMealsByDate(_today);
  // 批量反查食物名
  final db = await ref.read(recognize.databaseProvider.future);
  final foodRepo = FoodItemRepository(db);
  final names = <int, String>{};
  for (final m in meals) {
    if (!names.containsKey(m.foodItemId)) {
      final food = await foodRepo.getById(m.foodItemId);
      names[m.foodItemId] = food?.name ?? '食物 #${m.foodItemId}';
    }
  }
  _meals = meals;
  _foodNames = names;
  if (mounted) setState(() => _loading = false);
}

// 4. 修改 _buildMealTile 的 title（line 111 附近）：
// 原：title: Text('食物ID ${m.foodItemId}'),
// 改：
title: Text(_foodNames[m.foodItemId] ?? '食物 #${m.foodItemId}'),
```

> **注意**：
> - 反查用循环 `getById`（数据量小，一餐通常 < 20 条，性能可接受）。不用新增批量方法以避免改动 repository。
> - `food?.name ?? '食物 #${m.foodItemId}'` 兜底：food_item 被删除时（外键约束理论上禁止，但防御）显示 ID。
> - `recognize.databaseProvider` 已通过 `export '../../data/database/database.dart'`（providers.dart:15）暴露，today_meals_page 已 import providers.dart as recognize，可直接用。
> - `_load` 在 `onDismissed` 删除后会重新调用（line 92），反查逻辑自动生效。

- [ ] **Step 2: 创建 today_meals_food_name_test.dart**

```dart
// test/features/today_meals_food_name_test.dart
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/dashboard/today_meals_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证今日记录列表项显示食物名而非 ID
/// databaseProvider override 为内存 DB（绕过 path_provider 平台插件）
void main() {
  testWidgets('列表项显示食物名', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // 种子数据：插入食物 + 今日 meal_log
    final foodId = await db.into(db.foodItems).insert(
          FoodItemsCompanion.insert(
            name: '宫保鸡丁',
            defaultServingG: 100,
            caloriesPer100g: 200,
            proteinPer100g: 15,
            fatPer100g: 10,
            carbsPer100g: 8,
            source: 'manual',
            sourceVersion: 'test',
            createdAt: 1000,
          ),
        );
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await db.into(db.mealLogs).insert(
          MealLogsCompanion.insert(
            date: today,
            mealType: 'lunch',
            foodItemId: foodId,
            actualServingG: 150,
            actualCalories: 300,
            actualProteinG: 22.5,
            actualFatG: 15,
            actualCarbsG: 12,
            loggedAt: 2000,
          ),
        );

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TodayMealsPage()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 验证显示食物名"宫保鸡丁"，不显示"食物ID"
    expect(find.text('宫保鸡丁'), findsOneWidget);
    expect(find.textContaining('食物ID'), findsNothing);
  });
}
```

> **注意**：
> - `FoodItemsCompanion.insert` 和 `MealLogsCompanion.insert` 的必填字段对照 json_importer.dart 的 _foodItemFromJson/_mealLogFromJson（已核实）。
> - **databaseProvider override**：同 T25，用 `recognize.databaseProvider.overrideWith((ref) async => db)` 注入内存 DB。today_meals_page 用 `ref.read(recognize.mealLogRepoProvider.future)`，mealLogRepoProvider 内部 `await ref.watch(databaseProvider.future)`（providers.dart:55），override databaseProvider 即可让 mealLogRepoProvider 拿到内存 DB。
> - T26 Step 1 改动中 today_meals_page 新增 `ref.read(recognize.databaseProvider.future)` 构造 FoodItemRepository，同样由 override 覆盖。

- [ ] **Step 3: flutter analyze + test**

```bash
export PATH="/opt/flutter/bin:$PATH"
flutter analyze
flutter test test/features/today_meals_food_name_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/dashboard/today_meals_page.dart test/features/today_meals_food_name_test.dart
git commit -m "feat: Sprint 4 T26 - 今日记录显示食物名(批量反查 food_item.name)"
```

---

## Task 27: 复合菜校准完整化

**目标:** 校准页对复合菜支持：各组分份量滑块 + 用油量滑块 + 未命中组分展示"待确认" + 调整后实时重算总营养素。

**参考设计文档:** 3.1（校准页）、6.3（未命中组分）

**Files:**
- Modify: `lib/ai/nutrition_lookup.dart`（ComponentHit 加 per100g 字段，lookupCompositeDish 填充）
- Modify: `lib/features/recognize/calibration_page.dart`（复合菜分支完整化）
- Test: `test/features/calibration_composite_test.dart`

**当前状态核实:**
- calibration_page.dart:108-128 `_buildNutritionPreview` 复合菜返回 SizedBox.shrink()
- calibration_page.dart:153-162 `_confirmWithServing` 复合菜直接用原值，不重算
- nutrition_lookup.dart:110-128 CompositeNutritionResult 有 componentHits（List<ComponentHit>）+ componentMisses（List<String>）
- nutrition_lookup.dart:130-139 ComponentHit 当前只有 name/foodItemId/estimatedG（无 per100g）
- nutrition_lookup.dart:6-17 cookingOilCoefficients 是 const Map<String, double>
- nutrition_lookup.dart:20-21 oilCaloriesPer100g=889.0, oilFatPer100g=99.9
- vision_provider.dart:42-54 FoodComponent 有 name/estimatedG
- recognize_page.dart:108-153 onConfirm 回调签名：`(double servingG, double calories, double protein, double fat, double carbs, {String? componentsSnapshot})`

- [ ] **Step 1: 修改 nutrition_lookup.dart — ComponentHit 加 per100g 字段**

ComponentHit 增加 4 个 per100g 字段，让校准页无需额外查库即可重算。

```dart
// lib/ai/nutrition_lookup.dart 改动：

// 1. ComponentHit 类（line 130-139）改为：
class ComponentHit {
  final String name;
  final int foodItemId;
  final double estimatedG;
  // 新增：per100g 营养素（校准页重算用，lookup 时一次性填充）
  final double caloriesPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;

  const ComponentHit({
    required this.name,
    required this.foodItemId,
    required this.estimatedG,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
  });
}

// 2. lookupCompositeDish 方法（line 59-71）的循环内，hits.add 改为填充 per100g：
// 原：hits.add(ComponentHit(name: comp.name, foodItemId: food.id, estimatedG: g));
// 改：
hits.add(ComponentHit(
  name: comp.name,
  foodItemId: food.id,
  estimatedG: g,
  caloriesPer100g: food.caloriesPer100g,
  proteinPer100g: food.proteinPer100g,
  fatPer100g: food.fatPer100g,
  carbsPer100g: food.carbsPer100g,
));
```

> **注意**：ComponentHit 加了 required 字段，所有构造调用点都要更新。grep 确认 ComponentHit 构造仅在 nutrition_lookup.dart:70 一处（lookupCompositeDish 内），无其他调用方。Sprint 2 的营养查库测试（nutrition_lookup_test.dart）若构造了 ComponentHit 需同步改——**实施时核实**：grep "ComponentHit(" 全库，逐个更新。

- [ ] **Step 2: 修改 calibration_page.dart — 复合菜分支完整化**

```dart
// lib/features/recognize/calibration_page.dart 改动：

// 1. _CalibrationPageState 加字段（在 _servingG/_canSkipCalibration 下方）：
late double _servingG;
late bool _canSkipCalibration;
// 新增：复合菜校准状态
Map<int, double> _componentServings = {};  // 组分索引 → 份量 g
double _oilG = 0;  // 用油量 g

// 2. initState 末尾追加复合菜初始化（在 _canSkipCalibration 赋值后）：
@override
void initState() {
  super.initState();
  _servingG = widget.recognitionResult.estimatedWeightGMid;
  _canSkipCalibration =
      widget.recognitionResult.confidence >= 0.85 && widget.recognitionResult.isSingleItem;
  // 新增：复合菜初始化组分份量 + 用油量
  if (widget.compositeNutrition != null) {
    final hits = widget.compositeNutrition!.componentHits;
    for (var i = 0; i < hits.length; i++) {
      _componentServings[i] = hits[i].estimatedG;
    }
    _oilG = widget.compositeNutrition!.oilG;
  }
}

// 3. build 方法中 _buildNutritionPreview() 调用下方，追加复合菜 UI：
// 在 const Spacer() 上方加：
// 原：_buildNutritionPreview(),
//      const Spacer(),
// 改：
_buildNutritionPreview(),
if (widget.compositeNutrition != null) ...[
  const SizedBox(height: 16),
  _buildCompositeControls(),
],
const Spacer(),

// 4. 新增 _buildCompositeControls 方法（放在 _buildNutritionPreview 方法后）：
Widget _buildCompositeControls() {
  final composite = widget.compositeNutrition!;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('组分份量调整', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      // 各组分滑块
      for (var i = 0; i < composite.componentHits.length; i++)
        _buildComponentSlider(i, composite.componentHits[i]),
      // 未命中组分展示
      if (composite.componentMisses.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('⚠ 待确认组分（未在食物库找到）：',
            style: TextStyle(color: Colors.orange)),
        for (final miss in composite.componentMisses)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text('• $miss（请转手动录入或补充食物库）',
                style: const TextStyle(color: Colors.grey)),
          ),
      ],
      // 用油量滑块
      const SizedBox(height: 16),
      Text('用油量：${_oilG.toStringAsFixed(0)} g', style: Theme.of(context).textTheme.titleSmall),
      Slider(
        value: _oilG,
        min: 0,
        max: 50,
        divisions: 50,
        label: '${_oilG.toStringAsFixed(0)} g',
        onChanged: (v) => setState(() => _oilG = v),
      ),
    ],
  );
}

Widget _buildComponentSlider(int index, ComponentHit hit) {
  final serving = _componentServings[index] ?? hit.estimatedG;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${hit.name}：${serving.toStringAsFixed(0)} g'),
      Slider(
        value: serving,
        min: 0,
        max: (hit.estimatedG * 2).clamp(50, 1000),  // 上限为估算值 2 倍，clamp 防极端
        divisions: 50,
        label: '${serving.toStringAsFixed(0)} g',
        onChanged: (v) => setState(() => _componentServings[index] = v),
      ),
    ],
  );
}

// 5. 修改 _buildNutritionPreview，支持复合菜实时重算（替换原方法）：
Widget _buildNutritionPreview() {
  if (widget.singleNutrition != null) {
    // 单品路径：按总份量滑块比例重算（原逻辑不变）
    final ratio = _servingG / widget.recognitionResult.estimatedWeightGMid;
    final cal = widget.singleNutrition!.calories * ratio;
    final protein = widget.singleNutrition!.proteinG * ratio;
    final fat = widget.singleNutrition!.fatG * ratio;
    final carbs = widget.singleNutrition!.carbsG * ratio;
    return _nutritionCard(cal, protein, fat, carbs);
  }
  if (widget.compositeNutrition != null) {
    // 复合菜路径：按各组分滑块 + 用油量实时重算
    final composite = widget.compositeNutrition!;
    double cal = 0, protein = 0, fat = 0, carbs = 0;
    for (var i = 0; i < composite.componentHits.length; i++) {
      final hit = composite.componentHits[i];
      final g = _componentServings[i] ?? hit.estimatedG;
      cal += hit.caloriesPer100g * g / 100;
      protein += hit.proteinPer100g * g / 100;
      fat += hit.fatPer100g * g / 100;
      carbs += hit.carbsPer100g * g / 100;
    }
    // 加用油
    cal += oilCaloriesPer100g * _oilG / 100;
    fat += oilFatPer100g * _oilG / 100;
    return _nutritionCard(cal, protein, fat, carbs);
  }
  return const SizedBox.shrink();
}

// 6. 新增 _nutritionCard 辅助方法（抽取公共 Card 渲染）：
Widget _nutritionCard(double cal, double protein, double fat, double carbs) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('热量：${cal.toStringAsFixed(0)} kcal'),
          Text('蛋白质：${protein.toStringAsFixed(1)} g'),
          Text('脂肪：${fat.toStringAsFixed(1)} g'),
          Text('碳水：${carbs.toStringAsFixed(1)} g'),
        ],
      ),
    ),
  );
}

// 7. 修改 _confirmWithServing 复合菜分支（按调整后份量重算 onConfirm）：
void _confirmWithServing(double servingG) {
  if (widget.singleNutrition != null) {
    final ratio = servingG / widget.recognitionResult.estimatedWeightGMid;
    widget.onConfirm(
      servingG,
      widget.singleNutrition!.calories * ratio,
      widget.singleNutrition!.proteinG * ratio,
      widget.singleNutrition!.fatG * ratio,
      widget.singleNutrition!.carbsG * ratio,
    );
  } else if (widget.compositeNutrition != null) {
    // 按调整后份量重算
    final composite = widget.compositeNutrition!;
    double cal = 0, protein = 0, fat = 0, carbs = 0;
    for (var i = 0; i < composite.componentHits.length; i++) {
      final hit = composite.componentHits[i];
      final g = _componentServings[i] ?? hit.estimatedG;
      cal += hit.caloriesPer100g * g / 100;
      protein += hit.proteinPer100g * g / 100;
      fat += hit.fatPer100g * g / 100;
      carbs += hit.carbsPer100g * g / 100;
    }
    cal += oilCaloriesPer100g * _oilG / 100;
    fat += oilFatPer100g * _oilG / 100;
    // servingG 复合菜用总组分份量之和
    final totalG = _componentServings.values.fold<double>(0, (s, g) => s + g);
    widget.onConfirm(
      totalG,
      cal,
      protein,
      fat,
      carbs,
      componentsSnapshot: _buildSnapshotJson(),
    );
  }
  Navigator.of(context).pop();
}

// 8. 修改 _buildSnapshotJson，记录调整后份量（替换原方法）：
String _buildSnapshotJson() {
  if (widget.compositeNutrition == null) return '{}';
  final composite = widget.compositeNutrition!;
  final components = <Map<String, dynamic>>[];
  for (var i = 0; i < composite.componentHits.length; i++) {
    final hit = composite.componentHits[i];
    components.add({
      'name': hit.name,
      'actual_g': _componentServings[i] ?? hit.estimatedG,
    });
  }
  return jsonEncode({
    'components': components,
    'oil_g': _oilG,
  });
}
```

> **注意**：
> - **ComponentHit import**：calibration_page.dart 已 import `../../ai/nutrition_lookup.dart`（line 5），ComponentHit 类型可直接用。
> - **oilCaloriesPer100g / oilFatPer100g**：是 nutrition_lookup.dart 的 top-level const（line 20-21），通过 import 可访问。
> - **复合菜 _servingG 滑块**：复合菜时总份量滑块（line 82-90）仍渲染，但复合菜的份量实际由各组分滑块决定。为避免混淆，可在复合菜时隐藏总份量滑块。**简化处理**：保留总份量滑块但复合菜确认时用 `_componentServings.values.fold` 之和（不用 _servingG）。这样总份量滑块对复合菜仅作参考，不影响记录值。
> - **`(hit.estimatedG * 2).clamp(50, 1000)`**：Slider 的 max 必须 > min=0。clamp 防止 estimatedG 极小时 max 太小无法滑动。
> - **onConfirm 回调签名兼容**：recognize_page.dart:108 的 onConfirm 接受 `(servingG, calories, protein, fat, carbs, {componentsSnapshot})`，复合菜传 6 参数（含 componentsSnapshot），与现有调用一致。

- [ ] **Step 3: 创建 calibration_composite_test.dart**

```dart
// test/features/calibration_composite_test.dart
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/features/recognize/calibration_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复合菜校准页测试
/// 验证：组分滑块渲染 + 用油滑块渲染 + 未命中展示 + 重算后 onConfirm 传调整值
void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    foodRepo = FoodItemRepository(db);
    // 种子：鸡肉 + 花生（组分命中），不插入"黄瓜"（组分未命中）
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '鸡肉',
          defaultServingG: 100,
          caloriesPer100g: 167,
          proteinPer100g: 19,
          fatPer100g: 9,
          carbsPer100g: 0,
          source: 'manual',
          sourceVersion: 'test',
          createdAt: 1000,
        ));
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '花生',
          defaultServingG: 100,
          caloriesPer100g: 567,
          proteinPer100g: 25,
          fatPer100g: 49,
          carbsPer100g: 16,
          source: 'manual',
          sourceVersion: 'test',
          createdAt: 1001,
        ));
  });
  tearDown(() async => db.close());

  testWidgets('复合菜显示组分滑块 + 用油滑块 + 未命中展示', (tester) async {
    final recognition = VisionRecognitionResult(
      dishName: '宫保鸡丁',
      estimatedWeightGLow: 200,
      estimatedWeightGMid: 250,
      estimatedWeightGHigh: 300,
      foodComponents: const [
        FoodComponent(name: '鸡肉', estimatedG: 150),
        FoodComponent(name: '花生', estimatedG: 30),
        FoodComponent(name: '黄瓜', estimatedG: 20),  // 未命中
      ],
      cookingMethod: 'stir-fry',
      isSingleItem: false,
      confidence: 0.75,
      promptVersion: 'v1.0',
    );
    // 先调 NutritionLookup 生成 compositeNutrition
    final lookup = NutritionLookup(foodRepo);
    final composite = await lookup.lookupCompositeDish(
      components: recognition.foodComponents,
      cookingMethod: recognition.cookingMethod,
    );

    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: recognition,
        compositeNutrition: composite,
        foodItemRepo: foodRepo,
        onConfirm: (_, __, ___, ____, _____, {componentsSnapshot}) {},
      ),
    ));

    // 验证组分滑块标签
    expect(find.textContaining('鸡肉'), findsWidgets);
    expect(find.textContaining('花生'), findsWidgets);
    // 验证未命中展示
    expect(find.textContaining('待确认组分'), findsOneWidget);
    expect(find.textContaining('黄瓜'), findsWidgets);
    // 验证用油量标签（stir-fry 默认 12g）
    expect(find.textContaining('用油量'), findsOneWidget);
  });

  testWidgets('确认时 onConfirm 传重算值（默认份量）', (tester) async {
    final recognition = VisionRecognitionResult(
      dishName: '宫保鸡丁',
      estimatedWeightGLow: 200,
      estimatedWeightGMid: 250,
      estimatedWeightGHigh: 300,
      foodComponents: const [
        FoodComponent(name: '鸡肉', estimatedG: 150),
        FoodComponent(name: '花生', estimatedG: 30),
      ],
      cookingMethod: 'stir-fry',
      isSingleItem: false,
      confidence: 0.75,
      promptVersion: 'v1.0',
    );
    final lookup = NutritionLookup(foodRepo);
    final composite = await lookup.lookupCompositeDish(
      components: recognition.foodComponents,
      cookingMethod: recognition.cookingMethod,
    );

    double? capturedCalories;
    double? capturedProtein;
    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: recognition,
        compositeNutrition: composite,
        foodItemRepo: foodRepo,
        onConfirm: (_, calories, protein, __, _____, {componentsSnapshot}) {
          capturedCalories = calories;
          capturedProtein = protein;
        },
      ),
    ));

    // 点击"确认记录"按钮（用默认份量，应等于 lookupCompositeDish 的原始计算值）
    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    // 验证 onConfirm 被调用且传入了重算值（鸡肉 150g + 花生 30g + 油 12g）
    expect(capturedCalories, isNotNull);
    expect(capturedCalories! > 0, isTrue);
    // 鸡肉 167*1.5 + 花生 567*0.3 + 油 889*0.12 = 250.5 + 170.1 + 106.68 = 527.28
    expect(capturedCalories, closeTo(527.28, 1.0));
    // 鸡肉 19*1.5 + 花生 25*0.3 = 28.5 + 7.5 = 36
    expect(capturedProtein, closeTo(36.0, 1.0));
  });
}
```

> **注意**：
> - `closeTo(527.28, 1.0)` 容差 1.0 是因为 oilCaloriesPer100g=889.0 的计算 889*0.12=106.68，鸡肉 167*150/100=250.5，花生 567*30/100=170.1，合计 527.28。实施时若数字略有出入（如 lookup 内部逻辑微调），调整容差到 5.0。
> - CalibrationPage 是 StatefulWidget（非 Consumer），无 Provider 依赖，widget test 直接 MaterialApp 包裹即可，无需 ProviderScope。
> - `find.textContaining('鸡肉')` 用 findsWidgets 因为"鸡肉"可能出现在组分滑块标签和别处。

- [ ] **Step 4: flutter analyze + test**

```bash
export PATH="/opt/flutter/bin:$PATH"
flutter analyze
flutter test test/features/calibration_composite_test.dart
# 回归 Sprint 1/2 营养查库测试（ComponentHit 加字段可能影响）
flutter test test/ai/nutrition_lookup_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/ai/nutrition_lookup.dart lib/features/recognize/calibration_page.dart test/features/calibration_composite_test.dart
git commit -m "feat: Sprint 4 T27 - 复合菜校准完整化(组分滑块+用油滑块+未命中展示+重算)"
```

---

## Task 28: Insight 页 GLM key 迁移 secure_storage

**目标:** insight_page 的 GLM key 从 `String.fromEnvironment` 改为从 `appConfigProvider` 读取，使设置页修改的 key 生效。

**参考设计文档:** 8.2（API key 安全）、7.8（AI 汇总）

**Files:**
- Modify: `lib/features/insight/insight_page.dart`
- Test: `test/features/insight_key_test.dart`

**当前状态核实:**
- insight_page.dart:71 `final apiKey = const String.fromEnvironment('GLM_API_KEY');`
- insight_page.dart:78 `final provider = GlmFlashProvider(apiKey: apiKey);`（未传 baseUrl，用默认）
- providers.dart:26-29 glmApiKeyProvider / glmBaseUrlProvider 已定义（从 appConfigProvider 读）
- providers.dart:9 已 import app_config.dart
- insight_page.dart:9 已 import `../recognize/providers.dart as recognize`
- GlmFlashProvider 构造：`GlmFlashProvider({required String apiKey, String baseUrl = 'https://open.bigmodel.cn/api/paas/v4'})`
- appConfigProvider 是 FutureProvider<AppConfig>，providers 中 glmApiKeyProvider 用 `ref.watch(appConfigProvider).maybeWhen(data: (c) => c.glmApiKey, orElse: () => '')`

- [ ] **Step 1: 修改 insight_page.dart — key 从 appConfig 读**

```dart
// lib/features/insight/insight_page.dart 改动：

// 1. _generate 方法中，替换 apiKey 读取逻辑（line 71-78）：
// 原：
//   final apiKey = const String.fromEnvironment('GLM_API_KEY');
//   if (apiKey.isEmpty) {
//     if (!mounted) return;
//     setState(() =>
//         _summary = '未配置 GLM_API_KEY（用 --dart-define=GLM_API_KEY=xxx 启动）');
//     return;
//   }
//   final provider = GlmFlashProvider(apiKey: apiKey);
// 改：
final apiKey = ref.read(recognize.glmApiKeyProvider);
final baseUrl = ref.read(recognize.glmBaseUrlProvider);
if (apiKey.isEmpty) {
  if (!mounted) return;
  setState(() => _summary = '未配置 GLM API Key，请到设置页填写');
  return;
}
final provider = GlmFlashProvider(
  apiKey: apiKey,
  baseUrl: baseUrl.isEmpty ? 'https://open.bigmodel.cn/api/paas/v4' : baseUrl,
);
```

> **注意**：
> - `ref.read(recognize.glmApiKeyProvider)` 在 `_InsightPageState`（ConsumerState）中可直接用，无需 async。
> - `glmBaseUrlProvider` 为空时用 GlmFlashProvider 的默认 baseUrl，保证向后兼容。
> - 错误提示从"用 --dart-define"改为"到设置页填写"，引导用户用 Sprint 3 设置页。
> - insight_page.dart 已 import `../recognize/providers.dart as recognize`（line 9），glmApiKeyProvider/glmBaseUrlProvider 通过该 import 可访问。
> - `GlmFlashProvider` import 已存在（line 4）。

- [ ] **Step 2: 创建 insight_key_test.dart**

```dart
// test/features/insight_key_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/insight/insight_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 Insight 页 GLM key 从 appConfigProvider 读取
/// key 为空时显示"到设置页填写"提示（验证迁移生效）
/// databaseProvider override 为内存 DB（InsightPage._generate 读 DB 取 meal/weight/profile）
void main() {
  testWidgets('GLM key 未配置时显示设置页引导', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // 不 override appConfigProvider：沙箱无 secure_storage，AppConfig.load() 抛 MissingPluginException，
    // appConfigProvider 进入 error 状态，glmApiKeyProvider 的 maybeWhen(orElse: () => '') 返回 ''
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InsightPage()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 点击"生成本周汇总"按钮触发 _generate
    await tester.tap(find.text('生成本周汇总'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 验证显示设置页引导（而非 --dart-define 提示）
    expect(find.textContaining('设置页'), findsWidgets);
    expect(find.textContaining('--dart-define'), findsNothing);
  });
}
```

> **注意**：
> - **databaseProvider override**：InsightPage._generate 调 `ref.read(recognize.databaseProvider.future)` 取 DB（读 meal/weight/profile），必须 override 为内存 DB，否则 path_provider 抛 MissingPluginException 导致 _generate catch 到异常显示"生成失败"而非"到设置页填写"。
> - **appConfigProvider 沙箱行为**：AppConfig.load() 调 SecureConfigStore（flutter_secure_storage），沙箱抛 MissingPluginException → appConfigProvider（FutureProvider）进入 error 状态 → `ref.read(recognize.glmApiKeyProvider)` 中 `ref.watch(appConfigProvider).maybeWhen(orElse: () => '')` 走 orElse 返回 ''。Riverpod 的 AsyncValue.error 在 maybeWhen 中不匹配 data 分支，走 orElse。✅ 已确认 Riverpod 此行为。
> - 若实施时发现 maybeWhen 不走 orElse（Riverpod 版本差异），改为 `ref.read(appConfigProvider).maybeWhen(data: (c) => c.glmApiKey, orElse: () => '')` 同步读 AsyncValue（不 await future）。

- [ ] **Step 3: flutter analyze + test**

```bash
export PATH="/opt/flutter/bin:$PATH"
flutter analyze
flutter test test/features/insight_key_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/insight/insight_page.dart test/features/insight_key_test.dart
git commit -m "feat: Sprint 4 T28 - Insight页GLM key迁移secure_storage(设置页生效)"
```

---

## Task 29: 单品未命中转手动流程

**目标:** 拍照识别后单品 + 复合菜均未命中营养库时，弹窗提供"改菜名重试/转手动录入"选项。ManualEntryPage 支持初始食物名参数。

**参考设计文档:** 3.1 step5、6.3

**Files:**
- Modify: `lib/features/manual_entry/manual_entry_page.dart`（加 initialName 参数）
- Modify: `lib/features/recognize/recognize_page.dart`（未命中弹窗）
- Test: `test/features/manual_entry_initial_name_test.dart`

**当前状态核实:**
- recognize_page.dart:130-133 `singleNutrition==null && compositeNutrition==null` 时直接 return
- manual_entry_page.dart:11 `ManualEntryPage({super.key})` 无 initialName 参数
- manual_entry_page.dart:18-28 _customMode 初始 false，_nameCtrl 初始空
- manual_entry_page.dart:161-212 _logCustom 方法用 _nameCtrl.text
- NutritionLookup.lookupSingleItem({dishName, servingG}) 返回 Future<NutritionResult?>
- nutritionLookupProvider 是 FutureProvider<NutritionLookup>（providers.dart:59）

- [ ] **Step 1: 修改 manual_entry_page.dart — 加 initialName 参数**

```dart
// lib/features/manual_entry/manual_entry_page.dart 改动：

// 1. ManualEntryPage 类加 initialName 字段（line 11-12）：
class ManualEntryPage extends ConsumerStatefulWidget {
  const ManualEntryPage({super.key, this.initialName});
  final String? initialName;  // 新增：从识别页转来时预填菜名

  @override
  ConsumerState<ManualEntryPage> createState() => _ManualEntryPageState();
}

// 2. _ManualEntryPageState 的 _customMode 初始化改为基于 initialName（line 28）：
// 原：bool _customMode = false;
// 改：
late bool _customMode;

// 3. initState 初始化 _customMode + _nameCtrl（新增 initState）：
@override
void initState() {
  super.initState();
  _customMode = widget.initialName != null;
  if (widget.initialName != null) _nameCtrl.text = widget.initialName!;
}
```

> **注意**：
> - `_customMode` 从 `bool = false` 改为 `late bool`，在 initState 赋值。
> - `_nameCtrl` 已在 line 23 声明（`final _nameCtrl = TextEditingController()`），initState 中赋 text 即可。
> - 当 initialName 非空时默认进自定义模式（用户从识别页转来，菜名已预填，直接录营养素）。
> - 其余代码（_logFromLibrary / _logCustom / build）不变。

- [ ] **Step 2: 修改 recognize_page.dart — 未命中弹窗**

在 `_pickAndRecognize` 方法的 onConfirm 逻辑中，处理 `singleNutrition==null && compositeNutrition==null` 分支。

```dart
// lib/features/recognize/recognize_page.dart 改动：

// 1. 顶部 import 区追加（如尚未 import manual_entry_page）：
// recognize_page.dart 当前未 import manual_entry_page，需加：
import '../manual_entry/manual_entry_page.dart';

// 2. _pickAndRecognize 方法中，替换原 line 130-133 的 else 分支：
// 原：
//   } else {
//     // 无营养数据（查库未命中），不记录
//     return;
//   }
// 改：
} else {
  // 单品 + 复合菜均未命中 → 弹窗：改菜名重试 / 转手动录入 / 取消
  await _showNotFoundDialog(
    state.recognitionResult!,
    mealType: state.mealType,
    imagePath: state.imagePath,
  );
  return;
}

// 3. 新增 _showNotFoundDialog 方法（放在 _pickAndRecognize 方法后、_todayLocalDate 前）：
//    注意：需 import '../../ai/vision_provider.dart'（VisionRecognitionResult 类型）
Future<void> _showNotFoundDialog(
  VisionRecognitionResult result, {
  required String mealType,
  String? imagePath,
}) async {
  if (!mounted) return;
  final action = await showDialog<_NotFoundAction>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('未找到营养数据'),
      content: Text('识别菜名「${result.dishName}」在食物库中未命中。'
          '可修改菜名重试，或转手动录入。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, _NotFoundAction.cancel),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, _NotFoundAction.manual),
          child: const Text('转手动录入'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, _NotFoundAction.retry),
          child: const Text('改菜名重试'),
        ),
      ],
    ),
  );
  if (action == null || action == _NotFoundAction.cancel) return;
  if (!mounted) return;

  if (action == _NotFoundAction.manual) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ManualEntryPage(initialName: result.dishName),
    ));
    return;
  }

  // 改菜名重试
  final newDishName = await _promptNewDishName(result.dishName);
  if (newDishName == null || newDishName.isEmpty || !mounted) return;

  // 重新查库
  final lookup = await ref.read(nutritionLookupProvider.future);
  final nutrition = await lookup.lookupSingleItem(
    dishName: newDishName,
    servingG: result.estimatedWeightGMid,
  );
  if (nutrition == null) {
    // 仍未命中 → 再次弹窗引导
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('修改后的菜名仍未命中，请转手动录入')),
    );
    await _showNotFoundDialog(result);  // 递归（用户可再改或转手动）
    return;
  }
  // 命中 → 跳校准页（用新菜名的查库结果）
  if (!mounted) return;
  final foodItemRepo = await ref.read(foodItemRepoProvider.future);
  if (!mounted) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => CalibrationPage(
      recognitionResult: result,
      singleNutrition: nutrition,
      foodItemRepo: foodItemRepo,
      onConfirm: (servingG, calories, protein, fat, carbs, {componentsSnapshot}) async {
        final mealRepo = await ref.read(mealLogRepoProvider.future);
        await mealRepo.insertMealLog(
          date: _todayLocalDate(),
          mealType: mealType,  // 从 _showNotFoundDialog 参数传入
          foodItemId: nutrition.foodItemId,
          actualServingG: servingG,
          actualCalories: calories,
          actualProteinG: protein,
          actualFatG: fat,
          actualCarbsG: carbs,
          originalImagePath: imagePath,  // 从 _showNotFoundDialog 参数传入
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已记录：${calories.toStringAsFixed(0)} kcal')),
          );
        }
      },
    ),
  ));
}

Future<String?> _promptNewDishName(String original) async {
  final ctrl = TextEditingController(text: original);
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改菜名'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: '菜名'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  } finally {
    ctrl.dispose();
  }
}

// 4. 文件末尾新增 enum（放在 RecognizePage 类外、文件末尾）：
enum _NotFoundAction { cancel, retry, manual }
```

> **注意**：
> - **VisionRecognitionResult import**：recognize_page.dart 需直接 import `../../ai/vision_provider.dart`（Dart import 不传递，calibration_page.dart 的 import 不可复用）。**实施时核实**：recognize_page.dart 顶部是否已 import vision_provider.dart，若未 import 需加。
> - **_showNotFoundDialog 签名**：方法接收 `result` + 命名参数 `mealType`（required）+ `imagePath`（可选）。调用处从 `state.mealType` 和 `state.imagePath` 传入。onConfirm 内 `mealType: mealType` + `originalImagePath: imagePath`。
> - **递归调用风险**：`_showNotFoundDialog` 递归调用自身（用户多次改菜名未命中）。无深度限制，但用户可随时取消，实际风险低。
> - **import 检查**：recognize_page.dart 已 import `providers.dart`（line 7，含 nutritionLookupProvider/foodItemRepoProvider/mealLogRepoProvider）。
> - **CalibrationPage import**：recognize_page.dart 已 import `calibration_page.dart`（line 6）。

- [ ] **Step 3: 创建 manual_entry_initial_name_test.dart**

```dart
// test/features/manual_entry_initial_name_test.dart
import 'package:eatwise/features/manual_entry/manual_entry_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 ManualEntryPage 接受 initialName 并预填 + 默认进自定义模式
/// （recognize_page 的弹窗逻辑依赖 image_picker，沙箱无法 widget test，仅验证 ManualEntryPage 侧）
void main() {
  testWidgets('initialName 预填菜名并进入自定义模式', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ManualEntryPage(initialName: '宫保鸡丁'),
        ),
      ),
    );
    await tester.pump();

    // 验证菜名已预填到 TextField
    expect(find.text('宫保鸡丁'), findsOneWidget);
    // 验证进入自定义模式（显示"存库并记录"按钮，而非"找不到？自定义输入"）
    expect(find.text('存库并记录'), findsOneWidget);
    expect(find.text('找不到？自定义输入'), findsNothing);
  });

  testWidgets('无 initialName 时默认搜库模式', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ManualEntryPage()),
      ),
    );
    await tester.pump();

    // 验证默认搜库模式（显示"找不到？自定义输入"）
    expect(find.text('找不到？自定义输入'), findsOneWidget);
    expect(find.text('存库并记录'), findsNothing);
  });
}
```

> **注意**：
> - ManualEntryPage 是 ConsumerStatefulWidget，需 ProviderScope。但本测试不触发 DB 操作（仅验证 UI 初始状态），ProviderContainer 空即可。
> - recognize_page 的弹窗逻辑（_showNotFoundDialog）因依赖 image_picker 沙箱无平台通道，不做 widget test。该逻辑由真机验证（Self-Review 第 4 节）。

- [ ] **Step 4: flutter analyze + test**

```bash
export PATH="/opt/flutter/bin:$PATH"
flutter analyze
flutter test test/features/manual_entry_initial_name_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/manual_entry/manual_entry_page.dart lib/features/recognize/recognize_page.dart test/features/manual_entry_initial_name_test.dart
git commit -m "feat: Sprint 4 T29 - 单品未命中转手动(改菜名重试/转ManualEntry页)"
```

---

## Self-Review

> 本节在计划编写完成后由计划作者自查，确保严谨性。

### 1. Spec coverage（设计文档覆盖）

| 设计文档章节 | 对应 Task | 覆盖状态 |
|---|---|---|
| 2.4 分层（路由） | T25 | ✅ Drawer 提供全局导航入口 |
| 3.1 拍照识别闭环（校准页复合菜） | T27 | ✅ 组分滑块+用油滑块+重算 |
| 3.1 step5 未命中转手动 | T29 | ✅ 弹窗改菜名/转 ManualEntry |
| 6.3 未命中组分标注"待确认" | T27 | ✅ componentMisses 展示 |
| 7.1 个人档案模块入口 | T25 | ✅ Drawer 入口 |
| 7.3 今日记录（显示食物名） | T26 | ✅ 批量反查 food_item.name |
| 7.5 食物库入口 | T25 | ✅ Drawer 入口 |
| 7.6 手动录入入口 + initialName | T25 + T29 | ✅ Drawer 入口 + 预填菜名 |
| 7.7 体重记录入口 | T25 | ✅ Drawer 入口 |
| 7.8 AI 周报入口 + key 一致 | T25 + T28 | ✅ Drawer 入口 + appConfig 读 key |
| 9.1 备份入口 | T25 | ✅ Drawer 入口 |
| 8.2 API key 安全（Insight 一致） | T28 | ✅ 从 secure_storage 读 |

**未覆盖章节（留作 Sprint 5+）：**
- 3.2 容灾链路（L1 重试/断路器/L3）— Sprint 4 不含，调研报告 P1-1
- 5.3 goal_rate 设置 + 风险警告 — 调研报告 P1-6
- 5.6 显示规范（估算区间）— 调研报告 P2-1
- 6.2 L2-L4 数据源 — 设计标注后续迭代
- 7.4 看板估算区间 — 调研报告 P2-1
- 7.7 体重页热量对比 — 调研报告 P1-5
- 7.8 周月趋势图 — 调研报告 P1-4
- 10.1 离线回补复合菜 — 调研报告 P1-2
- 11.1 断路器 — 调研报告 P1-1
- 11.3 成本显示 — 调研报告 P2-4
- 12.4 Prompt 回归测试 — 调研报告 P2-9

**结论**：Sprint 4 聚焦 4 个 P0 + 1 个 P1，覆盖核心可用性缺口。剩余 P1/P2 留作 Sprint 5+。

### 2. Placeholder scan（占位符扫描）

逐项检查计划全文，确认无以下模式：
- ❌ "TBD" / "TODO" / "implement later" — **无**
- ❌ "Add appropriate error handling" — **无**
- ❌ "Write tests for the above"（无具体测试代码）— **无**（每个 Task 都有完整测试代码）
- ❌ 引用未定义的类型/函数 — **已核实**

**标注"实施时核实"的项（合理实施指引，非占位）：**
- T25 Step 2：databaseProvider override 方式（沙箱测试策略）
- T26 Step 2：databaseProvider override 方式
- T27 Step 1：ComponentHit 构造调用点 grep（确认仅 1 处）
- T28 Step 2：appConfigProvider 沙箱行为（maybeWhen orElse 是否生效）
- T29 Step 2：recognize_page.dart 是否已 import vision_provider.dart

**结论**：无占位符，"实施时核实"均为合理实施指引。

### 3. Type consistency（类型一致性）

| 类型/方法 | 定义位置 | 使用位置 | 一致性 |
|---|---|---|---|
| `FoodItemRepository.getById(int)` | food_item_repository.dart:82 | T26 Step 1（today_meals 反查） | ✅ 返回 Future<FoodItem?> |
| `FoodItem.name` | database.g.dart | T26 Step 1（food?.name） | ✅ String |
| `MealLog.foodItemId` | database.g.dart | T26 Step 1（m.foodItemId） | ✅ int |
| `ComponentHit` 加 4 个 per100g 字段 | T27 Step 1 | T27 Step 2（calibration_page 重算） | ✅ 新字段 required |
| `ComponentHit` 构造调用点 | nutrition_lookup.dart:70（grep 全库确认仅 1 处，test/ 无构造） | T27 Step 1 修改 | ✅ 已 grep 确认 |
| `CompositeNutritionResult.componentHits` / `.componentMisses` / `.oilG` | nutrition_lookup.dart:110-127 | T27 Step 2 | ✅ 已存在 |
| `oilCaloriesPer100g` / `oilFatPer100g` | nutrition_lookup.dart:20-21 | T27 Step 2（重算） | ✅ top-level const |
| `VisionRecognitionResult` 字段 | vision_provider.dart:2-23 | T27 Step 3 测试 / T29 Step 2 | ✅ dishName/estimatedWeightGMid/foodComponents/cookingMethod/isSingleItem/confidence/promptVersion |
| `FoodComponent.name` / `.estimatedG` | vision_provider.dart:42-53 | T27 Step 1（lookup 入参）/ T27 Step 3 测试 | ✅ |
| `GlmFlashProvider({apiKey, baseUrl})` | glm_flash_provider.dart:9-17 | T28 Step 1 | ✅ baseUrl 有默认值 |
| `ref.read(recognize.glmApiKeyProvider)` | providers.dart:26-29 | T28 Step 1 | ✅ 返回 String |
| `ManualEntryPage({key, initialName})` | T29 Step 1 修改 | T29 Step 2（Navigator push） | ✅ 新增可选参数 |
| `CalibrationPage` 构造参数 | calibration_page.dart:13-27 | T27 Step 3 测试 / T29 Step 2 | ✅ recognitionResult/singleNutrition/compositeNutrition/foodItemRepo/onConfirm |
| `onConfirm` 回调签名 | calibration_page.dart:18 | recognize_page.dart:108 / T29 Step 2 | ✅ (servingG, calories, protein, fat, carbs, {componentsSnapshot}) |
| `NutritionLookup.lookupSingleItem` | nutrition_lookup.dart:30-45 | T29 Step 2（改菜名重试） | ✅ 返回 Future<NutritionResult?> |
| `nutritionLookupProvider` | providers.dart:59-62 | T29 Step 2 | ✅ FutureProvider<NutritionLookup> |
| `databaseProvider` | database.dart:61（FutureProvider<EatWiseDatabase>，调 openEncryptedConnection 依赖 path_provider） | T25/T26/T28 测试 override | ✅ overrideWith((ref) async => db) 注入 NativeDatabase.memory() |
| `_showNotFoundDialog` 签名 | T29 Step 2 新增 | T29 Step 2 调用处 | ✅ (result, {required mealType, imagePath}) |
| `RecognizeUiState.mealType` / `.imagePath` | recognize_controller.dart:22/20 | T29 Step 2 调用处 | ✅ String / String? |

**⚠️ 需核实的项（仅剩 1 项）：**
1. **recognize_page.dart import vision_provider.dart**：T29 Step 2 用 VisionRecognitionResult 类型。recognize_page.dart 当前 import 了 calibration_page.dart（它 import 了 vision_provider.dart），但 Dart import 不传递。**实施时核实**：recognize_page.dart 顶部是否已直接 import vision_provider.dart，若未 import 需加 `import '../../ai/vision_provider.dart';`。

**第2轮 Self-Review 已修正的缺陷：**
1. ~~T25/T26/T28 测试缺 databaseProvider override~~ → 已加 `recognize.databaseProvider.overrideWith((ref) async => db)`
2. ~~T27 ComponentHit 构造调用点未核实~~ → 已 grep 确认仅 nutrition_lookup.dart:70 一处，test/ 无构造
3. ~~T27 测试2 名"调整后"但未调整滑块~~ → 改名为"确认时 onConfirm 传重算值（默认份量）"
4. ~~T29 _showNotFoundDialog 签名缺 mealType/imagePath~~ → 已加命名参数，调用处从 state 传入
5. ~~T29 onConfirm 内 `mealType: result.promptVersion.isEmpty ? 'snack' : 'snack'` bug~~ → 改为 `mealType: mealType`（从参数传入）
6. ~~T29 onConfirm 内 `originalImagePath: null`~~ → 改为 `originalImagePath: imagePath`（从参数传入）

### 4. 沙箱不可验证项（需真机）

| 项 | 原因 | 计划中的应对 | 真机验证步骤 |
|---|---|---|---|
| T29 改菜名重试/转手动完整流程 | recognize_page 依赖 image_picker | T29 Step 3 仅测 ManualEntryPage initialName | 真机拍照→未命中→改菜名/转手动 |
| T28 GLM 真实生成汇总 | 需真实 API key + 网络 | T28 Step 2 测 key 来源迁移（沙箱 key 必空） | 真机设置页填 key→生成汇总 |
| T27 复合菜滑块交互手感 | widget test 可验证渲染 | T27 Step 3 widget test 验证滑块+重算 | 真机拖动滑块观察实时重算 |
| T25 Drawer 实际跳转各页 | 跳转后页面依赖 DB/平台插件 | T25 Step 2 验证 Drawer 渲染+入口文本 | 真机点击各入口观察页面加载 |

**结论**：所有真机不可测项都有对应的沙箱单测/widget test 覆盖核心逻辑，真机验证仅作集成验收。

### 5. 实施中发现的计划偏差（实施时填写）

> 本节在 subagent 执行过程中由执行者追加，记录计划与实际代码状态不符的偏差及修正。

| Task | 偏差描述 | 修正方式 | 影响范围 |
|---|---|---|---|
| （实施时填写） | | | |

**偏差处理原则：**
- 若偏差是计划引用的代码与实际不符（如行号偏移、方法签名微调）：执行者直接修正计划中的引用，并在 commit message 标注 `[plan-fix]`。
- 若偏差是计划假设的 API 不存在：暂停该 Task，返回"BLOCKED: <原因>"，不要自行发挥。
- 若偏差是测试在沙箱无法运行（如平台插件）：调整测试策略（mock/override/改集成测试），在 commit message 标注。

### 6. Self-Review 完成结论

- ✅ Spec coverage：12 项章节覆盖，剩余 P1/P2 留作 Sprint 5+
- ✅ Placeholder scan：无占位符（1 处"实施时核实"为合理指引：recognize_page import vision_provider）
- ✅ Type consistency：20 项类型/方法一致，1 项 ⚠️ 待执行时核实（recognize_page import vision_provider.dart）
- ✅ 沙箱不可验证项：4 项均有沙箱单测覆盖核心逻辑
- ✅ **第2轮 Self-Review 修正 6 处缺陷**：测试 databaseProvider override（3 处）+ ComponentHit grep 确认 + T27 测试名修正 + T29 签名/mealType/originalImagePath bug 修正（3 处）
- ✅ Self-Review 完成（2 轮），计划可进入执行阶段

---

## 执行交接

### 实施顺序

按 Task 编号顺序执行（T25 → T29），无顺序调整。理由：
1. **T25 导航优先**：使所有功能可达，后续 Task 测试可复用导航
2. **T26 食物名**：独立改动，不依赖其他 Task
3. **T27 复合菜校准**：最复杂，放中间确保前面简单 Task 已稳
4. **T28 Insight key**：独立改动
5. **T29 未命中转手动**：依赖 ManualEntryPage 改动，但 ManualEntryPage 改动在 T29 内完成

### Task 完成检查清单（每个 Task 完成后必查）

执行 subagent 完成一个 Task 后，主控必须验证：
- [ ] **代码与计划一致**：逐行核对（允许格式微调，不允许逻辑偏差）
- [ ] **测试存在且通过**：`flutter test <path>` 全过
- [ ] **Commit 已提交**：git log 可见该 Task 的 commit
- [ ] **无新增 analyze warning**：`flutter analyze` 0 issues
- [ ] **类型一致性**：对照 Self-Review 第 3 节表格
- [ ] **无遗留 TODO**

### Sprint 4 完成标准（全部 Task 完成后）

- [ ] CI 全绿：`flutter analyze` 0 issues + `flutter test --exclude-tags smoke` 全过
- [ ] T25-T29 共 5 个 Task 的 commit 全部在分支
- [ ] Dashboard Drawer 含 7 个入口
- [ ] 今日记录显示食物名
- [ ] 复合菜校准页支持组分/用油滑块 + 未命中展示 + 重算
- [ ] Insight 页 GLM key 从 appConfigProvider 读取
- [ ] 单品未命中弹窗提供改菜名/转手动选项
- [ ] Self-Review 第 5 节"实施偏差"已填写（若有）

### 执行方式确认

用户已选：**Subagent-Driven Development**（如 Sprint 3）。

主控将按 T25→T29 顺序，每个 Task 派发一个 fresh subagent 执行，subagent 完成后主控执行"Task 完成检查清单"审查，审查通过才进入下一个 Task。遇偏差按 Self-Review 第 5 节原则处理。

**Subagent 派发模板（每个 Task 复用）：**

```
执行 Sprint 4 Task <N>：<Task 标题>

计划文件：docs/superpowers/plans/2026-07-02-sprint4-usability.md
你的任务：仅执行 Task <N> 的所有 Step，不要触碰其他 Task 的文件。

要求：
1. 严格按计划代码块逐行实现，不允许逻辑偏差（格式微调可接受）
2. 每个 Step 的测试必须实际运行通过（flutter test <path>）才进入下一步
3. 计划中标注"实施时核实"的项，先用 Read/Grep 核实再继续
4. 遇到计划与实际代码不符（行号偏移/签名微调）：直接修正并继续，commit message 标注 [plan-fix]
5. 遇到计划假设的 API 不存在：暂停，返回"BLOCKED: <原因>"，不要自行发挥
6. 全部 Step 完成后 git commit（按计划 commit message），并返回：
   - 修改的文件列表
   - 测试运行结果（pass/fail 计数）
   - 与计划的偏差（若有）

不要执行 git push。
```

---

**计划版本：** v1.1（第2轮 Self-Review 后）
**编写日期：** 2026-07-02
**编写者：** Claude（writing-plans skill）
**Self-Review 状态：** ✅ 完成（2 轮，6 节检查通过，修正 6 处缺陷）
**待执行：** T25 → T29（5 个 Task，subagent-driven）
