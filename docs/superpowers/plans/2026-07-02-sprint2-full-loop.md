# EatWise Sprint 2 实现计划：完整记录闭环 + 数据沉淀

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Sprint 1 拍照识别闭环基础上，补齐完整记录闭环（档案录入 + 今日记录 + 食物库 + 手动录入 + 体重趋势 + AI 汇总 + JSON 导入导出 + 离线队列），使 App 从"能拍苹果记录热量"升级为"可日常使用的个人营养记录工具"。

**Architecture:** 沿用 Sprint 1 架构（Flutter + drift 2.34 sqlite3mc 加密 + Riverpod 3.x + go_router + openai_dart）。Sprint 2 不改表结构（7 张表已齐全），schemaVersion 保持 1。新增 AI 汇总走 GLM-4-Flash（智谱免费文本模型，OpenAI 兼容，复用 openai_dart）。离线队列仅实现前台触发版（connectivity_plus 监听网络恢复），workmanager 后台兜底推迟 Sprint 3。

**Tech Stack:** 沿用 Sprint 1 全部依赖。新增使用：fl_chart 0.70.2（体重/热量趋势图）、connectivity_plus 6.1.5（离线队列前台触发）、openai_dart 调 GLM-4-Flash（汇总建议）。无新增 pubspec 依赖。

**参考设计文档:** [`docs/superpowers/specs/2026-07-01-eatwise-design.md`](../specs/2026-07-01-eatwise-design.md)（以下简称"设计文档"），重点章节：7.3（今日记录）、7.4（看板）、7.5（食物库）、7.6（手动录入）、7.7（体重）、7.8（AI 汇总）、9.1（JSON 导出导入）、10.1-10.2（离线队列）。

**Sprint 2 成功标准:**
1. 录入个人档案 → 看板显示热量环形进度 + 三宏量进度条 + 余额预警
2. 拍照记录可选餐次（早/午/晚/加餐）→ 今日记录按餐次分组 → 可编辑份量/删除 → 可反馈"识别准/不准"
3. 食物库可搜索/点击复用/编辑默认份量，标注数据来源
4. 手动录入兜底：搜库→选份量→记录；查不到→自定义→存库→记录
5. 体重记录 + fl_chart 折线趋势图
6. 周视图 → GLM-4-Flash 生成 ≤300 字中文建议 → 存 insight_summary（去重 + 可编辑）
7. JSON 导出/导入全表数据（含 schemaVersion）
8. 离线拍照进 pending_recognition 队列 → 联网后前台自动回补识别（重试上限 3 次）

**Sprint 2 范围决策（用户确认）:**
- 离线队列：只做前台触发版（connectivity_plus），workmanager 后台兜底推迟 Sprint 3
- AI 汇总：用 GLM-4-Flash（智谱免费模型，用户已有 key），沙箱真实冒烟验证
- 食物库数据：GitHub 拉取 Sanotsu 完整版《中国食物成分表》第6版，增强 importer 清洗脏数据

---

## API 实测确认（写计划前已核实，无盲区）

| 库 | 实测版本 | 关键 API | 确认状态 |
|---|---|---|---|
| connectivity_plus | 6.1.5 | `Stream<List<ConnectivityResult>> get onConnectivityChanged` / `Future<List<ConnectivityResult>> checkConnectivity()` | ✅ 6.0 breaking：返回 List（设备可多种连接并存） |
| ConnectivityResult 枚举 | 2.1.0 | bluetooth/wifi/ethernet/mobile/none/vpn/satellite/other | ✅ 8 值确认 |
| fl_chart | 0.70.2 | `LineChartBarData(color: Color?)` 单色，无 `colors` 列表（已移除） | ✅ 0.70 已彻底删除旧 colors |
| drift Migrator | 2.34.0 | `createTable(TableInfo)` / `addColumn(TableInfo, GeneratedColumn)` / `createAll()` | ✅ 签名确认 |
| GLM-4-Flash | - | baseUrl `https://open.bigmodel.cn/api/paas/v4`，OpenAI 兼容，免费 | ✅ 官方文档确认 |
| Sanotsu 完整数据 | - | `json_data/merged-{大类}-{子类}.json`，字段含脏数据 | ✅ 样本确认（见 T0.3） |

---

## 文件结构

Sprint 2 涉及的文件（新增 N / 修改 M）：

```
lib/
  data/
    repositories/
      profile_repository.dart      # N - profile 单行读写
      food_item_repository.dart    # M - 补 searchByName / getById / updateServing / listFrequent
      meal_log_repository.dart     # M - 补 updateMealLog / deleteMealLog / getMacrosByDate / getRange
    seed/
      food_seed_importer.dart      # M - 增强脏数据清洗（多值/空值/后缀）
    backup/
      json_exporter.dart           # N - 全表导出 JSON（含 schemaVersion）
      json_importer.dart           # N - 导入 JSON（清空后批量插入）
  features/
    profile/
      profile_page.dart            # N - 档案录入 UI
      nutrition_calculator.dart    # （不改，T0 调用）
    recognize/
      recognize_page.dart          # M - 加餐次选择器
      recognize_controller.dart    # M - pickAndRecognize 接收 mealType 参数
    dashboard/
      dashboard_page.dart          # M - 环形进度 + 宏量进度条 + 余额预警
      today_meals_page.dart        # N - 今日记录按餐次分组 + 编辑/删除/反馈
    food_library/
      food_library_page.dart       # N - 食物库列表 + 搜索 + 复用
      food_edit_page.dart          # N - 编辑默认份量
    manual_entry/
      manual_entry_page.dart       # N - 搜库→选份量 / 自定义输入
    weight/
      weight_page.dart             # N - 体重记录 + fl_chart 折线图
    insight/
      insight_page.dart            # N - 周视图 + GLM-4-Flash 汇总
      insight_provider.dart        # N - GLM-4-Flash 调用 + insight_summary 读写
    offline/
      offline_queue_controller.dart # N - pending_recognition 队列 + connectivity_plus 前台触发
  ai/
    glm_flash_provider.dart        # N - GLM-4-Flash 文本生成（openai_dart）
  app.dart                         # M - 路由补全（profile/food_library/weight/insight/today）
test/
  data/
    profile_repository_test.dart   # N
    food_item_repository_test.dart # M - 补搜索/频率测试
    meal_log_repository_test.dart  # M - 补更新/删除/区间查询测试
    backup/
      json_export_import_test.dart # N
  features/
    insight_provider_test.dart     # N - GLM-4-Flash Fake 测试
  integration/
    sprint2_e2e_test.dart          # N - Sprint 2 端到端集成测试
  smoke/
    glm_flash_smoke_test.dart      # N - GLM-4-Flash 真实 API 冒烟
  fixtures/
    sanotsu_dirty_sample.json      # N - 脏数据样本（测 importer 清洗）
```

---

## Task 0: 前置补丁（Sprint 1 遗留 + 数据基础）

**目标:** 补齐 Sprint 1 简化项（profile UI / 餐次选择 / Sanotsu 完整导入），为 T8-T14 扫清依赖。

**Files:**
- Create: `lib/data/repositories/profile_repository.dart`
- Create: `lib/features/profile/profile_page.dart`
- Modify: `lib/features/recognize/recognize_page.dart`（加餐次选择器）
- Modify: `lib/features/recognize/recognize_controller.dart`（pickAndRecognize 接收 mealType）
- Modify: `lib/data/seed/food_seed_importer.dart`（增强脏数据清洗）
- Create: `lib/data/seed/sanotsu_categories.dart`（常吃分类文件清单）
- Modify: `lib/features/recognize/providers.dart`（加 export database.dart，修复 T8-T14 各页面 `recognize.databaseProvider` 引用）
- Test: `test/data/profile_repository_test.dart`
- Test: `test/fixtures/sanotsu_dirty_sample.json`
- Test: `test/data/food_seed_importer_dirty_test.dart`

- [ ] **Step 0: 修改 providers.dart — 加 export database.dart**

**问题**：providers.dart 中 `databaseProvider` 是从 `database.dart` import 的，**未 export**。Dart 的 `import 'x.dart' as foo;` 只能访问 x.dart 自身声明或 export 的符号，import 进来的符号不会传递。Sprint 2 各页面（T8-T14）用 `recognize.databaseProvider`（共 15 处）会编译失败。

**修复**：在 providers.dart 顶部加一行 export：

```dart
// providers.dart 顶部新增（在现有 import 之后）：
export '../../data/database/database.dart';  // 让 recognize.databaseProvider 可被各页面访问
```

> **实测确认**：providers.dart 当前 `import '../../data/database/database.dart';` 但无 export，故 `recognize.databaseProvider` 不可达。`mealLogRepoProvider` / `foodItemRepoProvider` / `nutritionLookupProvider` 等 provider 在 providers.dart 内声明，无需 export 即可访问。

- [ ] **Step 1: 创建 profile_repository.dart**

profile 是单行表（id 固定 1），只需 get/update 两个方法。

```dart
import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

class ProfileRepository {
  final EatWiseDatabase _db;
  ProfileRepository(this._db);

  /// 读取唯一 profile 行（id=1）
  Future<Profile> get() {
    return (_db.profiles.select()..where((p) => p.id.equals(1))).getSingle();
  }

  /// 更新 profile（部分字段），同时重算 dailyCalorieTarget + 宏量目标缓存
  Future<void> update({
    double? heightCm,
    double? weightKg,
    double? bodyFatPct,
    int? age,
    String? gender,
    double? activityLevel,
    String? goal,
    double? goalRateKgPerWeek,
    String? formula,
    int? dailyCalorieTarget,
    double? proteinGPerKg,
    double? fatGPerKg,
    double? carbGPerKg,
    int? tdeeAdjustmentKcal,
  }) async {
    final companion = ProfilesCompanion(
      heightCm: heightCm != null ? Value(heightCm) : const Value.absent(),
      weightKg: weightKg != null ? Value(weightKg) : const Value.absent(),
      bodyFatPct: bodyFatPct != null ? Value(bodyFatPct) : const Value.absent(),
      age: age != null ? Value(age) : const Value.absent(),
      gender: gender != null ? Value(gender) : const Value.absent(),
      activityLevel: activityLevel != null ? Value(activityLevel) : const Value.absent(),
      goal: goal != null ? Value(goal) : const Value.absent(),
      goalRateKgPerWeek: goalRateKgPerWeek != null ? Value(goalRateKgPerWeek) : const Value.absent(),
      formula: formula != null ? Value(formula) : const Value.absent(),
      dailyCalorieTarget: dailyCalorieTarget != null ? Value(dailyCalorieTarget) : const Value.absent(),
      proteinGPerKg: proteinGPerKg != null ? Value(proteinGPerKg) : const Value.absent(),
      fatGPerKg: fatGPerKg != null ? Value(fatGPerKg) : const Value.absent(),
      carbGPerKg: carbGPerKg != null ? Value(carbGPerKg) : const Value.absent(),
      tdeeAdjustmentKcal: tdeeAdjustmentKcal != null ? Value(tdeeAdjustmentKcal) : const Value.absent(),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    );
    await (_db.profiles.update()..where((p) => p.id.equals(1))).write(companion);
  }
}
```

- [ ] **Step 2: 创建 profile_page.dart（档案录入 UI）**

最简表单：身高/体重/年龄/性别/活动量/目标/体脂率（可选）。保存时调 NutritionCalculator 重算目标，写 profile 表。

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/profile_repository.dart';
import '../../data/database/database.dart';
import 'nutrition_calculator.dart';
import '../recognize/providers.dart' as recognize;

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});
  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _bodyFatCtrl = TextEditingController();
  String _gender = 'male';
  double _activity = 1.375;
  String _goal = 'maintain';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = ProfileRepository(db);
    final p = await repo.get();
    _heightCtrl.text = p.heightCm.toString();
    _weightCtrl.text = p.weightKg.toString();
    _ageCtrl.text = p.age.toString();
    _bodyFatCtrl.text = p.bodyFatPct?.toString() ?? '';
    _gender = p.gender;
    _activity = p.activityLevel;
    _goal = p.goal;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _ageCtrl.dispose();
    _bodyFatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('个人档案')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _heightCtrl,
              decoration: const InputDecoration(labelText: '身高 (cm)'),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || v.isEmpty ? '必填' : null,
            ),
            TextFormField(
              controller: _weightCtrl,
              decoration: const InputDecoration(labelText: '体重 (kg)'),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || v.isEmpty ? '必填' : null,
            ),
            TextFormField(
              controller: _ageCtrl,
              decoration: const InputDecoration(labelText: '年龄'),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || v.isEmpty ? '必填' : null,
            ),
            DropdownButtonFormField<String>(
              value: _gender,
              decoration: const InputDecoration(labelText: '性别'),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('男')),
                DropdownMenuItem(value: 'female', child: Text('女')),
              ],
              onChanged: (v) => setState(() => _gender = v!),
            ),
            TextFormField(
              controller: _bodyFatCtrl,
              decoration: const InputDecoration(labelText: '体脂率 % (可选，填了可用 Katch 公式)'),
              keyboardType: TextInputType.number,
            ),
            DropdownButtonFormField<double>(
              value: _activity,
              decoration: const InputDecoration(labelText: '活动量'),
              items: const [
                DropdownMenuItem(value: 1.2, child: Text('久坐')),
                DropdownMenuItem(value: 1.375, child: Text('轻度活动')),
                DropdownMenuItem(value: 1.55, child: Text('中度活动')),
                DropdownMenuItem(value: 1.725, child: Text('高强度活动')),
                DropdownMenuItem(value: 1.9, child: Text('极度活动')),
              ],
              onChanged: (v) => setState(() => _activity = v!),
            ),
            DropdownButtonFormField<String>(
              value: _goal,
              decoration: const InputDecoration(labelText: '目标'),
              items: const [
                DropdownMenuItem(value: 'cut', child: Text('减脂')),
                DropdownMenuItem(value: 'bulk', child: Text('增肌')),
                DropdownMenuItem(value: 'maintain', child: Text('维持')),
              ],
              onChanged: (v) => setState(() => _goal = v!),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Text('保存并重算目标'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = ProfileRepository(db);

    final height = double.parse(_heightCtrl.text);
    final weight = double.parse(_weightCtrl.text);
    final age = int.parse(_ageCtrl.text);
    final bodyFat = _bodyFatCtrl.text.isEmpty ? null : double.parse(_bodyFatCtrl.text);
    final gender = _gender == 'male' ? Gender.male : Gender.female;
    final goal = _goal == 'cut' ? Goal.cut : _goal == 'bulk' ? Goal.bulk : Goal.maintain;

    // 重算目标（MVP：始终用 mifflin，有体脂率时也用 mifflin 除非用户显式选 katch——Sprint 2 简化）
    final bmr = NutritionCalculator.bmrMifflin(
      weightKg: weight, heightCm: height, age: age, gender: gender,
    );
    final tdee = NutritionCalculator.tdee(bmr: bmr, activityLevel: _activity);
    final target = NutritionCalculator.dailyCalorieTarget(
      tdee: tdee, goal: goal, tdeeAdjustmentKcal: 0, gender: gender,
    );
    final macros = NutritionCalculator.macros(
      dailyCalorieTarget: target, weightKg: weight, goal: goal,
    );

    await repo.update(
      heightCm: height,
      weightKg: weight,
      bodyFatPct: bodyFat,
      age: age,
      gender: _gender,
      activityLevel: _activity,
      goal: _goal,
      formula: 'mifflin',
      dailyCalorieTarget: target,
      proteinGPerKg: goal == Goal.cut ? 2.4 : goal == Goal.bulk ? 1.8 : 1.4,
      fatGPerKg: goal == Goal.cut ? 0.9 : goal == Goal.bulk ? 1.0 : 0.9,
      carbGPerKg: goal == Goal.bulk ? 5.0 : null,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存，每日目标 $target kcal')),
      );
      Navigator.of(context).pop();
    }
  }
}
```

- [ ] **Step 3: 修改 recognize_controller.dart — pickAndRecognize 接收 mealType**

将 `pickAndRecognize(ImageSource source)` 改为 `pickAndRecognize(ImageSource source, {required String mealType})`，把 mealType 透传到 RecognizeUiState 供 recognize_page 写 meal_log 时使用。

```dart
// recognize_controller.dart 修改点：
class RecognizeUiState {
  // ... 原有字段 ...
  final String mealType;  // 新增

  RecognizeUiState({
    this.state = RecognizeState.idle,
    this.errorMessage,
    this.recognitionResult,
    this.singleNutrition,
    this.compositeNutrition,
    this.imagePath,
    this.mealType = 'snack',  // 默认值
  });

  RecognizeUiState copyWith({
    // ... 原有参数 ...
    String? mealType,
  }) {
    return RecognizeUiState(
      // ... 原有字段 ...
      mealType: mealType ?? this.mealType,
    );
  }
}

class RecognizeController extends StateNotifier<RecognizeUiState> {
  // ...
  Future<void> pickAndRecognize(ImageSource source, {required String mealType}) async {
    state = state.copyWith(state: RecognizeState.pickingImage, mealType: mealType);
    // ... 其余逻辑不变 ...
  }
}
```

- [ ] **Step 4: 修改 recognize_page.dart — 加餐次选择器**

在拍照按钮前加餐次选择（默认加餐），传入 controller。

```dart
// recognize_page.dart _RecognizePageState 新增字段：
String _mealType = 'snack';

// build 方法中拍照按钮上方加：
DropdownButton<String>(
  value: _mealType,
  items: const [
    DropdownMenuItem(value: 'breakfast', child: Text('早餐')),
    DropdownMenuItem(value: 'lunch', child: Text('午餐')),
    DropdownMenuItem(value: 'dinner', child: Text('晚餐')),
    DropdownMenuItem(value: 'snack', child: Text('加餐')),
  ],
  onChanged: (v) => setState(() => _mealType = v!),
),

// _pickAndRecognize 调用改为：
await controller.pickAndRecognize(source, mealType: _mealType);

// onConfirm 回调里 mealType 改用 state.mealType（而非硬编码 'snack'）：
await mealRepo.insertMealLog(
  date: _todayLocalDate(),
  mealType: state.mealType,  // 改这里
  // ...
);
```

- [ ] **Step 5: 增强 food_seed_importer.dart — 脏数据清洗**

Sanotsu 完整数据脏数据模式（实测样本确认）：
- `fat: "0.2 13.7"` → 两个值挤一字段（脂肪 + 饱和脂肪），取第一个空格前的值
- `CHO: ""` → 空字符串，跳过（返回 null）
- `protein: "—"` → 破折号表示未检测，Sprint 1 已处理
- `foodName: "苹果 (代表值)"` → 有后缀，清洗掉 `(代表值)` 等括号后缀

```dart
// food_seed_importer.dart 新增清洗方法：

/// 清洗食物名：去掉 (代表值)/(均值) 等括号后缀
String _cleanFoodName(String raw) {
  // 去掉尾部括号后缀，如 "苹果 (代表值)" → "苹果"
  return raw.replaceAll(RegExp(r'\s*[（(][^)）]*[)）]\s*$'), '').trim();
}

/// 解析可能含多值的数值字段（如 "0.2 13.7" → 0.2）
/// Sanotsu 完整版 fat 字段偶尔挤入"脂肪+饱和脂肪"两值，取第一个
double? _parseDoubleMultiValue(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final trimmed = raw.trim();
  if (trimmed == '—' || trimmed == '-' || trimmed == 'Tr' || trimmed == 'tr') return null;
  // 取第一个空格前的值
  final firstValue = trimmed.split(RegExp(r'\s+')).first;
  return double.tryParse(firstValue);
}
```

> **注意**：Sprint 1 的 `_parseDouble` 仍保留给原 4 字段用（energyKCal/protein/fat/CHO）。T0.3 把这 4 个字段的解析从 `_parseDouble` 切换到 `_parseDoubleMultiValue`（后者兼容前者行为，额外处理多值）。

- [ ] **Step 6: 创建 sanotsu_categories.dart — 常吃分类文件清单**

Sanotsu 仓库 `json_data/` 下按 `merged-{大类}-{子类}.json` 组织。常吃大类（跳过婴幼儿食品/特殊医学用途）。文件清单在实施时从 GitHub API 拉取（仓库超 50MB，jsdelivr 拒绝列目录，用 GitHub API `git/trees` 递归列表）。

```dart
// sanotsu_categories.dart
/// Sanotsu 完整数据常吃大类前缀（用于过滤 json_data/ 下的文件）
/// 跳过：婴幼儿食品、特殊医学用途婴儿配方食品
const sanotsuEdibleCategories = [
  '蔬菜类', '水果类', '谷类', '薯类', '干豆类', '大豆类',
  '坚果种子类', '畜肉类', '禽肉类', '蛋类', '鱼类', '软体动物类',
  '虾蟹类', '乳类', '调味品类', '菌藻类',
];

/// 油脂类（花生油/大豆油等，用于 nutrition_lookup 的 cookingOilCoefficients 补充）
const sanotsuOilCategories = ['动物油脂类', '植物油脂类'];

/// 判断 Sanotsu json 文件名是否属于常吃分类
bool isEdibleCategory(String fileName) {
  // fileName 格式：merged-蔬菜类及其制品-根菜类.json
  for (final cat in [...sanotsuEdibleCategories, ...sanotsuOilCategories]) {
    if (fileName.contains(cat)) return true;
  }
  return false;
}
```

- [ ] **Step 7: 创建脏数据测试 fixture + 测试**

创建 `test/fixtures/sanotsu_dirty_sample.json`：

```json
[
  {"foodCode":"061101x","foodName":"苹果 (代表值)","edible":"85","energyKCal":"53","protein":"0.4","fat":"0.2 13.7","CHO":"","water":"86.1"},
  {"foodCode":"043101","foodName":"马铃薯(土豆,洋芋)","edible":"94","energyKCal":"76","protein":"2.0","fat":"0.1","CHO":"16.5","water":"79.8"},
  {"foodCode":"—","foodName":"某未检测项","edible":"","energyKCal":"—","protein":"—","fat":"—","CHO":"—","water":""}
]
```

创建 `test/data/food_seed_importer_dirty_test.dart`：

```dart
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/seed/food_seed_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late FoodSeedImporter importer;

  setUp(() {
    db = EatWiseDatabase(NativeDatabase.memory());
    importer = FoodSeedImporter(db);
  });
  tearDown(() => db.close());

  test('脏数据清洗：多值 fat 取首值 + (代表值) 后缀清除 + 空值跳过', () async {
    const dirty = '''
[
  {"foodCode":"061101x","foodName":"苹果 (代表值)","edible":"85","energyKCal":"53","protein":"0.4","fat":"0.2 13.7","CHO":"","water":"86.1"},
  {"foodCode":"043101","foodName":"马铃薯(土豆,洋芋)","edible":"94","energyKCal":"76","protein":"2.0","fat":"0.1","CHO":"16.5","water":"79.8"},
  {"foodCode":"—","foodName":"某未检测项","edible":"","energyKCal":"—","protein":"—","fat":"—","CHO":"—","water":""}
]
''';
    final count = await importer.importFromJsonList(
        (jsonDecode(dirty) as List).cast<Map<String, dynamic>>());

    // 第三条全空应跳过，前两条导入
    expect(count, 2);

    final apple = await importer.findByName('苹果');
    expect(apple, isNotNull);
    expect(apple!.name, '苹果');  // (代表值) 已清除
    expect(apple.fatPer100g, 0.2);  // "0.2 13.7" 取首值 0.2

    final potato = await importer.findByName('马铃薯(土豆,洋芋)');
    expect(potato, isNotNull);
    expect(potato!.carbsPer100g, 16.5);
  });
}
```

> **注意**：测试调用了 `importer.findByName()`，需在 FoodSeedImporter 补一个简单的 `findByName` 查询方法（或直接用 FoodItemRepository.findByNameOrAlias）。实施时按 FoodSeedImporter 现有结构决定。

- [ ] **Step 8: 实现 Sanotsu 完整数据导入入口**

创建一个一次性导入脚本/入口（App 首次启动时若 food_items 表为空则触发）。由于 Sanotsu 仓库超 50MB 不便打包进 App，采用方案：**在 test/fixtures 或 assets 放一份精简的常吃分类 JSON 合集**（实施时从 GitHub 拉取常吃分类文件合并为一个 `sanotsu_common.json`，约 2000 条，打包进 assets）。

```dart
// food_seed_importer.dart 新增批量导入方法：
/// 从 assets/sanotsu_common.json 导入全部常吃分类数据
Future<int> importFromAssets() async {
  // 实施时：把 GitHub 拉取的常吃分类 JSON 合并后放 assets/sanotsu_common.json
  // 这里读 assets 并调用 importFromJsonList
  // 注意：assets 文件需在 pubspec.yaml 声明 assets: - assets/sanotsu_common.json
  throw UnimplementedError('实施时从 GitHub 拉取常吃分类合并为 assets/sanotsu_common.json');
}
```

> **实施时操作**：用 GitHub API 拉 `json_data/` 文件列表 → 过滤常吃分类 → 下载各文件 → 合并为 `assets/sanotsu_common.json` → pubspec 声明 assets → importer 读 assets 导入。这一步在实施时用 curl 脚本完成数据拉取合并。

- [ ] **Step 9: flutter analyze + test 验证**

```bash
flutter analyze   # 预期 0 issues
flutter test test/data/profile_repository_test.dart test/data/food_seed_importer_dirty_test.dart
```

- [ ] **Step 10: Commit**

```bash
git add lib/data/repositories/profile_repository.dart lib/features/profile/profile_page.dart \
  lib/features/recognize/recognize_page.dart lib/features/recognize/recognize_controller.dart \
  lib/data/seed/food_seed_importer.dart lib/data/seed/sanotsu_categories.dart \
  test/data/profile_repository_test.dart test/fixtures/sanotsu_dirty_sample.json \
  test/data/food_seed_importer_dirty_test.dart assets/sanotsu_common.json pubspec.yaml
git commit -m "feat: Sprint 2 T0 - profile UI + 餐次选择 + Sanotsu 完整导入增强"
```

---

## Task 8: 今日记录完善 + 看板宏量 + 识别反馈

**目标:** 看板从"只显示热量"升级为"环形进度 + 三宏量进度条 + 余额预警"；新增今日记录页（按餐次分组 + 编辑/删除/反馈）。

**参考设计文档:** 7.3（今日记录）、7.4（今日额度看板）、4.2.7（recognition_feedback 表）

**Files:**
- Modify: `lib/data/repositories/meal_log_repository.dart`（补 updateMealLog / deleteMealLog / getMacrosByDate / getRange）
- Create: `lib/features/dashboard/today_meals_page.dart`（今日记录按餐次分组 + 编辑/删除/反馈）
- Modify: `lib/features/dashboard/dashboard_page.dart`（环形进度 + 宏量进度条 + 余额预警）
- Create: `lib/data/repositories/recognition_feedback_repository.dart`（反馈写入）
- Modify: `lib/app.dart`（路由补 today/profile）
- Test: `test/data/meal_log_repository_test.dart`（补更新/删除/区间/宏量测试）

- [ ] **Step 1: meal_log_repository.dart 补 4 个方法**

```dart
// meal_log_repository.dart 新增方法：

/// 更新某条 meal_log 的份量（校准后修正）
Future<void> updateMealLog({
  required int id,
  required double actualServingG,
  required double actualCalories,
  required double actualProteinG,
  required double actualFatG,
  required double actualCarbsG,
}) async {
  await (_db.mealLogs.update()..where((m) => m.id.equals(id))).write(
    MealLogsCompanion(
      actualServingG: Value(actualServingG),
      actualCalories: Value(actualCalories),
      actualProteinG: Value(actualProteinG),
      actualFatG: Value(actualFatG),
      actualCarbsG: Value(actualCarbsG),
    ),
  );
}

/// 删除某条 meal_log（recognition_feedback 因 ON DELETE CASCADE 自动级联删除）
Future<void> deleteMealLog(int id) async {
  await (_db.mealLogs.delete()..where((m) => m.id.equals(id))).go();
}

/// 查询某日三大宏量总和（看板用）
Future<({double calories, double protein, double fat, double carbs})> getMacrosByDate(String date) async {
  final meals = await getMealsByDate(date);
  return (
    calories: meals.fold<double>(0.0, (s, m) => s + m.actualCalories),
    protein: meals.fold<double>(0.0, (s, m) => s + m.actualProteinG),
    fat: meals.fold<double>(0.0, (s, m) => s + m.actualFatG),
    carbs: meals.fold<double>(0.0, (s, m) => s + m.actualCarbsG),
  );
}

/// 查询某日期区间全部记录（周/月视图 + AI 汇总用）
Future<List<MealLog>> getRange(String startDate, String endDate) {
  return (_db.mealLogs.select()
        ..where((m) => m.date.isBetweenValues(startDate, endDate))
        ..orderBy([(m) => OrderingTerm.asc(m.date), (m) => OrderingTerm.asc(m.loggedAt)]))
      .get();
}
```

> **注意 drift 语法**：`isBetweenValues` 用于 TEXT 列的字符串区间查询（'YYYY-MM-DD' 字典序与时间序一致）。`OrderingTerm` 来自 drift。

- [ ] **Step 2: 创建 recognition_feedback_repository.dart**

```dart
import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

class RecognitionFeedbackRepository {
  final EatWiseDatabase _db;
  RecognitionFeedbackRepository(this._db);

  /// 写入识别反馈
  /// isCorrect=1 表示识别正确；isCorrect=0 时填 correctedDishName/correctedServingG
  Future<int> insert({
    required int mealLogId,
    required bool isCorrect,
    String? correctedDishName,
    double? correctedServingG,
    required String promptVersion,
  }) async {
    return _db.into(_db.recognitionFeedbacks).insert(
          RecognitionFeedbacksCompanion.insert(
            mealLogId: mealLogId,
            isCorrect: isCorrect ? 1 : 0,
            correctedDishName: Value(correctedDishName),
            correctedServingG: Value(correctedServingG),
            promptVersion: promptVersion,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  /// 查询某条 meal_log 是否已有反馈（避免重复反馈）
  Future<bool> hasFeedback(int mealLogId) async {
    final count = await (_db.recognitionFeedbacks.select()
          ..where((f) => f.mealLogId.equals(mealLogId)))
        .get();
    return count.isNotEmpty;
  }
}
```

- [ ] **Step 3: 创建 today_meals_page.dart（今日记录按餐次分组 + 编辑/删除/反馈）**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/recognition_feedback_repository.dart';
import '../recognize/providers.dart' as recognize;

class TodayMealsPage extends ConsumerStatefulWidget {
  const TodayMealsPage({super.key});
  @override
  ConsumerState<TodayMealsPage> createState() => _TodayMealsPageState();
}

class _TodayMealsPageState extends ConsumerState<TodayMealsPage> {
  late final String _today;
  List<MealLog> _meals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _load();
  }

  Future<void> _load() async {
    final repo = await ref.read(recognize.mealLogRepoProvider.future);
    _meals = await repo.getMealsByDate(_today);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    // 按餐次分组
    final groups = <String, List<MealLog>>{};
    for (final m in _meals) {
      groups.putIfAbsent(m.mealType, () => []).add(m);
    }
    const order = ['breakfast', 'lunch', 'dinner', 'snack'];
    const labels = {'breakfast': '早餐', 'lunch': '午餐', 'dinner': '晚餐', 'snack': '加餐'};

    return Scaffold(
      appBar: AppBar(title: const Text('今日记录')),
      body: ListView(
        children: [
          for (final type in order)
            if (groups.containsKey(type)) ...[
              _buildSectionHeader(labels[type]!),
              for (final m in groups[type]!) _buildMealTile(m),
            ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(label, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _buildMealTile(MealLog m) {
    return Dismissible(
      key: ValueKey(m.id),
      direction: DismissDirection.endToStart,
      background: Container(color: Colors.red, alignment: Alignment.centerRight, child: const Icon(Icons.delete, color: Colors.white)),
      onDismissed: (_) async {
        final repo = await ref.read(recognize.mealLogRepoProvider.future);
        await repo.deleteMealLog(m.id);
        setState(() => _meals.remove(m));
      },
      child: ListTile(
        title: Text('食物ID ${m.foodItemId}'),  // MVP：显示 ID（T9 食物库可反查名称）
        subtitle: Text('${m.actualServingG.toStringAsFixed(0)}g · ${m.actualCalories.toStringAsFixed(0)} kcal'),
        trailing: m.recognitionConfidence != null
            ? IconButton(
                icon: const Icon(Icons.feedback_outlined),
                onPressed: () => _showFeedbackDialog(m),
              )
            : null,
        onTap: () => _showEditDialog(m),
      ),
    );
  }

  Future<void> _showEditDialog(MealLog m) async {
    final servingCtrl = TextEditingController(text: m.actualServingG.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('编辑份量'),
        content: TextField(controller: servingCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '份量 (g)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, double.tryParse(servingCtrl.text)), child: const Text('保存')),
        ],
      ),
    );
    if (result == null) return;
    // 按比例重算营养素
    final ratio = result / m.actualServingG;
    final repo = await ref.read(recognize.mealLogRepoProvider.future);
    await repo.updateMealLog(
      id: m.id,
      actualServingG: result,
      actualCalories: m.actualCalories * ratio,
      actualProteinG: m.actualProteinG * ratio,
      actualFatG: m.actualFatG * ratio,
      actualCarbsG: m.actualCarbsG * ratio,
    );
    _load();
  }

  Future<void> _showFeedbackDialog(MealLog m) async {
    final db = await ref.read(recognize.databaseProvider.future);
    final feedbackRepo = RecognitionFeedbackRepository(db);
    if (await feedbackRepo.hasFeedback(m.id)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已反馈过')));
      return;
    }
    final isCorrect = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('识别准不准？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('准')),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('不准')),
        ],
      ),
    );
    if (isCorrect == null) return;
    await feedbackRepo.insert(
      mealLogId: m.id,
      isCorrect: isCorrect,
      promptVersion: 'v1.0',  // Sprint 1 prompts.dart 版本
    );
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已记录反馈')));
  }
}
```

- [ ] **Step 4: 升级 dashboard_page.dart（环形进度 + 宏量进度条 + 余额预警）**

环形进度用 fl_chart 的 PieChart（单段进度模拟环形）；宏量用 LinearProgressIndicator。

```dart
// dashboard_page.dart 完整覆写：
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../recognize/providers.dart' as recognize;
import '../recognize/recognize_page.dart';
import 'today_meals_page.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TodayMealsPage())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecognizePage())),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<({double cal, double protein, double fat, double carbs, int target, double proteinGoal, double fatGoal, double carbGoal})>(
        future: _loadData(ref),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final d = snapshot.data!;
          final remain = d.target - d.cal;
          final overflow = remain < 0;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 环形进度（热量）
              SizedBox(
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(PieChartData(
                      sectionsSpace: 0,
                      centerSpaceRadius: 60,
                      sections: [
                        PieChartSectionData(
                          value: d.cal > d.target ? d.target.toDouble() : d.cal,
                          color: overflow ? Colors.red : Colors.green,
                          radius: 16,
                          showTitle: false,
                        ),
                        if (d.cal < d.target)
                          PieChartSectionData(
                            value: (d.target - d.cal).toDouble(),
                            color: Colors.grey.shade200,
                            radius: 16,
                            showTitle: false,
                          ),
                      ],
                    )),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${d.cal.toStringAsFixed(0)}', style: Theme.of(context).textTheme.headlineMedium),
                        Text('/ ${d.target} kcal', style: Theme.of(context).textTheme.bodySmall),
                        if (overflow)
                          Text('超 ${(-remain).toStringAsFixed(0)} kcal', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        if (!overflow)
                          Text('余 ${remain.toStringAsFixed(0)} kcal', style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // 三宏量进度条
              _macroBar('蛋白质', d.protein, d.proteinGoal, Colors.blue),
              _macroBar('脂肪', d.fat, d.fatGoal, Colors.orange),
              _macroBar('碳水', d.carbs, d.carbGoal, Colors.purple),
            ],
          );
        },
      ),
    );
  }

  Widget _macroBar(String label, double value, double goal, Color color) {
    final pct = goal > 0 ? (value / goal).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text('${value.toStringAsFixed(1)} / ${goal.toStringAsFixed(0)} g'),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: pct, backgroundColor: color.withOpacity(0.1), color: color, minHeight: 8),
        ],
      ),
    );
  }

  Future<({double cal, double protein, double fat, double carbs, int target, double proteinGoal, double fatGoal, double carbGoal})> _loadData(WidgetRef ref) async {
    final db = await ref.read(recognize.databaseProvider.future);
    final mealRepo = MealLogRepository(db);
    final profileRepo = ProfileRepository(db);
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final macros = await mealRepo.getMacrosByDate(today);
    final profile = await profileRepo.get();
    final proteinGoal = profile.proteinGPerKg * profile.weightKg;
    final fatGoal = profile.fatGPerKg * profile.weightKg;
    final carbGoal = profile.carbGPerKg != null ? profile.carbGPerKg! * profile.weightKg : (profile.dailyCalorieTarget - proteinGoal * 4 - fatGoal * 9) / 4;
    return (
      cal: macros.calories,
      protein: macros.protein,
      fat: macros.fat,
      carbs: macros.carbs,
      target: profile.dailyCalorieTarget,
      proteinGoal: proteinGoal,
      fatGoal: fatGoal,
      carbGoal: carbGoal,
    );
  }
}
```

> **注意**：dashboard 直接 `import '../../data/repositories/meal_log_repository.dart'` 后用 `MealLogRepository(db)` 构造（不通过 `recognize.` 前缀，因为 MealLogRepository 类不在 providers.dart 命名空间，providers.dart 只 import 未 export 它）。也可改用 `await ref.read(recognize.mealLogRepoProvider.future)` 拿现成实例，更符合 Riverpod 风格，实施时任选其一。

- [ ] **Step 5: 修改 app.dart 补路由**

```dart
// app.dart routes 补充：
GoRoute(path: '/today', builder: (context, state) => const TodayMealsPage()),
GoRoute(path: '/profile', builder: (context, state) => const ProfilePage()),
```

- [ ] **Step 6: 测试 + 验证**

```dart
// test/data/meal_log_repository_test.dart 新增测试：
test('updateMealLog 更新份量后按比例重算', () async { ... });
test('deleteMealLog 后 recognition_feedback 级联删除', () async { ... });
test('getMacrosByDate 返回四宏量总和', () async { ... });
test('getRange 按日期区间+时间排序', () async { ... });
```

```bash
flutter analyze
flutter test test/data/meal_log_repository_test.dart
```

- [ ] **Step 7: Commit**

```bash
git add lib/data/repositories/meal_log_repository.dart lib/data/repositories/recognition_feedback_repository.dart \
  lib/features/dashboard/today_meals_page.dart lib/features/dashboard/dashboard_page.dart lib/app.dart \
  test/data/meal_log_repository_test.dart
git commit -m "feat: Sprint 2 T8 - 看板环形进度+宏量+今日记录分组+识别反馈"
```

---

## Task 9: 食物库模块（搜索 / 复用 / 编辑）

**目标:** 食物库可搜索、可点击复用（免调 API 直接记录）、可编辑默认份量，标注数据来源。

**参考设计文档:** 7.5（食物库）

**Files:**
- Modify: `lib/data/repositories/food_item_repository.dart`（补 searchByName / getById / listFrequent）
- Create: `lib/features/food_library/food_library_page.dart`（列表 + 搜索 + 复用）
- Create: `lib/features/food_library/food_edit_page.dart`（编辑默认份量 + 来源标注）
- Modify: `lib/app.dart`（路由补 food_library）
- Test: `test/data/food_item_repository_test.dart`（补搜索/频率测试）

- [ ] **Step 1: food_item_repository.dart 补 3 个方法**

```dart
// food_item_repository.dart 新增方法：

/// 模糊搜索食物（名称 LIKE，MVP 够用，数据量 ≤3000 条）
Future<List<FoodItem>> searchByName(String keyword, {int limit = 50}) {
  return (_db.foodItems.select()
        ..where((f) => f.name.like('%$keyword%'))
        ..orderBy([(f) => OrderingTerm.asc(f.name)])
        ..limit(limit))
      .get();
}

/// 按 id 查询（今日记录页反查食物名用）
Future<FoodItem?> getById(int id) {
  return (_db.foodItems.select()..where((f) => f.id.equals(id))).getSingleOrNull();
}

/// 查询常用食物（按 meal_log 引用次数降序，取 top N）
/// 用于食物库首页"常吃"列表
Future<List<FoodItem>> listFrequent({int limit = 20}) async {
  // 子查询：统计每个 food_item_id 在 meal_log 中的引用次数
  final rows = await _db.customSelect(
    'SELECT f.*, COUNT(m.id) AS ref_count '
    'FROM food_items f '
    'LEFT JOIN meal_logs m ON m.food_item_id = f.id '
    'GROUP BY f.id '
    'ORDER BY ref_count DESC, f.name ASC '
    'LIMIT ?',
    variables: [Variable.withInt(limit)],
    readsFrom: {_db.foodItems, _db.mealLogs},
  ).map((row) => row.readTable(_db.foodItems)).get();
  return rows;
}

/// 更新默认份量
Future<void> updateDefaultServing(int id, double servingG) async {
  await (_db.foodItems.update()..where((f) => f.id.equals(id)))
      .write(FoodItemsCompanion(defaultServingG: Value(servingG)));
}
```

> **注意 drift customSelect**：`readsFrom` 告诉 drift 查询涉及哪些表（用于流式更新订阅）。`Variable.withInt` 是 drift 的参数化查询。`row.readTable(_db.foodItems)` 把结果行映射回 FoodItem 实体。

- [ ] **Step 2: 创建 food_library_page.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../recognize/providers.dart' as recognize;

class FoodLibraryPage extends ConsumerStatefulWidget {
  const FoodLibraryPage({super.key, this.pickForReuse = false});
  final bool pickForReuse;  // true: 从手动录入页跳来选食物复用

  @override
  ConsumerState<FoodLibraryPage> createState() => _FoodLibraryPageState();
}

class _FoodLibraryPageState extends ConsumerState<FoodLibraryPage> {
  final _searchCtrl = TextEditingController();
  List<FoodItem> _frequent = [];
  List<FoodItem> _searchResults = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadFrequent();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFrequent() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = FoodItemRepository(db);
    _frequent = await repo.listFrequent();
    setState(() {});
  }

  Future<void> _search(String keyword) async {
    if (keyword.isEmpty) {
      setState(() => _searching = false);
      return;
    }
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = FoodItemRepository(db);
    _searchResults = await repo.searchByName(keyword);
    setState(() => _searching = true);
  }

  @override
  Widget build(BuildContext context) {
    final list = _searching ? _searchResults : _frequent;
    return Scaffold(
      appBar: AppBar(title: const Text('食物库')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: '搜索食物',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
          ),
          if (!_searching)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(alignment: Alignment.centerLeft, child: Text('常吃', style: TextStyle(fontWeight: FontWeight.bold))),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final f = list[i];
                return ListTile(
                  title: Text(f.name),
                  subtitle: Text('${f.caloriesPer100g.toStringAsFixed(0)} kcal/100g · ${_sourceLabel(f.source)}'),
                  onTap: () {
                    if (widget.pickForReuse) {
                      Navigator.of(context).pop(f);  // 返回选中的 FoodItem 给手动录入页
                    } else {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => FoodEditPage(foodItem: f)));
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'china_fct': return '中国成分表';
      case 'usda': return 'USDA';
      case 'manual': return '手动';
      case 'ai_recognized': return 'AI 入库';
      default: return source;
    }
  }
}
```

- [ ] **Step 3: 创建 food_edit_page.dart（编辑默认份量 + 来源标注）**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../recognize/providers.dart' as recognize;

class FoodEditPage extends ConsumerStatefulWidget {
  const FoodEditPage({super.key, required this.foodItem});
  final FoodItem foodItem;

  @override
  ConsumerState<FoodEditPage> createState() => _FoodEditPageState();
}

class _FoodEditPageState extends ConsumerState<FoodEditPage> {
  late final TextEditingController _servingCtrl;
  late final TextEditingController _calCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _fatCtrl;
  late final TextEditingController _carbsCtrl;

  @override
  void initState() {
    super.initState();
    final f = widget.foodItem;
    _servingCtrl = TextEditingController(text: f.defaultServingG.toStringAsFixed(0));
    _calCtrl = TextEditingController(text: f.caloriesPer100g.toStringAsFixed(0));
    _proteinCtrl = TextEditingController(text: f.proteinPer100g.toStringAsFixed(1));
    _fatCtrl = TextEditingController(text: f.fatPer100g.toStringAsFixed(1));
    _carbsCtrl = TextEditingController(text: f.carbsPer100g.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _servingCtrl.dispose();
    _calCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    _carbsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.foodItem;
    return Scaffold(
      appBar: AppBar(title: Text(f.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.source_outlined'),
                  const SizedBox(width: 8),
                  Text('数据来源：${_sourceLabel(f.source)} ${f.sourceVersion}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(controller: _servingCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '默认份量 (g)')),
          TextField(controller: _calCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '热量 /100g (kcal)')),
          TextField(controller: _proteinCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '蛋白质 /100g (g)')),
          TextField(controller: _fatCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '脂肪 /100g (g)')),
          TextField(controller: _carbsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '碳水 /100g (g)')),
          const SizedBox(height: 24),
          // 仅 ai_recognized 和 manual 来源允许编辑营养素；china_fct/usda 只允许改默认份量
          if (f.source == 'ai_recognized' || f.source == 'manual')
            FilledButton(onPressed: _saveAll, child: const Text('保存全部修改')),
          if (f.source == 'china_fct' || f.source == 'usda')
            FilledButton(onPressed: _saveServingOnly, child: const Text('保存默认份量')),
        ],
      ),
    );
  }

  Future<void> _saveServingOnly() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = FoodItemRepository(db);
    await repo.updateDefaultServing(widget.foodItem.id, double.parse(_servingCtrl.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存默认份量')));
      Navigator.of(context).pop();
    }
  }

  Future<void> _saveAll() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = FoodItemRepository(db);
    await repo.updateDefaultServing(widget.foodItem.id, double.parse(_servingCtrl.text));
    // 补充一个 updateNutrients 方法（实施时在 repo 加）
    await (_dbUpdateNutrients(repo, widget.foodItem.id));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
      Navigator.of(context).pop();
    }
  }

  Future<void> _dbUpdateNutrients(FoodItemRepository repo, int id) async {
    // 实施时在 FoodItemRepository 补 updateNutrients 方法
    // await repo.updateNutrients(id, cal, protein, fat, carbs);
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'china_fct': return '中国成分表';
      case 'usda': return 'USDA';
      case 'manual': return '手动';
      case 'ai_recognized': return 'AI 入库';
      default: return source;
    }
  }
}
```

> **实施注意**：`_dbUpdateNutrients` 是占位，实施时需在 FoodItemRepository 补一个 `updateNutrients(id, cal, protein, fat, carbs)` 方法，逻辑类似 `updateDefaultServing`。

- [ ] **Step 4: 修改 app.dart 补路由**

```dart
GoRoute(path: '/food_library', builder: (context, state) => const FoodLibraryPage()),
```

- [ ] **Step 5: 测试 + 验证**

```dart
// test/data/food_item_repository_test.dart 新增：
test('searchByName 模糊匹配', () async { ... });
test('listFrequent 按引用次数降序', () async { ... });
test('getById 返回对应食物', () async { ... });
```

```bash
flutter analyze
flutter test test/data/food_item_repository_test.dart
```

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/food_item_repository.dart \
  lib/features/food_library/food_library_page.dart lib/features/food_library/food_edit_page.dart \
  lib/app.dart test/data/food_item_repository_test.dart
git commit -m "feat: Sprint 2 T9 - 食物库搜索/复用/编辑+来源标注"
```

---

## Task 10: 手动录入（兜底）

**目标:** 不拍照也能记录：搜库→选份量→记录；查不到→自定义输入→存库→记录。

**参考设计文档:** 7.6（手动录入）

**Files:**
- Create: `lib/features/manual_entry/manual_entry_page.dart`
- Modify: `lib/app.dart`（路由补 manual_entry）
- 复用: `lib/features/food_library/food_library_page.dart`（pickForReuse 模式）

- [ ] **Step 1: 创建 manual_entry_page.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../recognize/providers.dart' as recognize;
import '../food_library/food_library_page.dart';

class ManualEntryPage extends ConsumerStatefulWidget {
  const ManualEntryPage({super.key});
  @override
  ConsumerState<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends ConsumerState<ManualEntryPage> {
  String _mealType = 'snack';
  FoodItem? _selected;
  final _servingCtrl = TextEditingController(text: '100');

  // 自定义输入字段
  final _nameCtrl = TextEditingController();
  final _calCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  bool _customMode = false;

  @override
  void dispose() {
    _servingCtrl.dispose();
    _nameCtrl.dispose();
    _calCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    _carbsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('手动录入')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButton<String>(
            value: _mealType,
            items: const [
              DropdownMenuItem(value: 'breakfast', child: Text('早餐')),
              DropdownMenuItem(value: 'lunch', child: Text('午餐')),
              DropdownMenuItem(value: 'dinner', child: Text('晚餐')),
              DropdownMenuItem(value: 'snack', child: Text('加餐')),
            ],
            onChanged: (v) => setState(() => _mealType = v!),
          ),
          const SizedBox(height: 16),
          if (!_customMode) ...[
            // 搜库模式
            ListTile(
              title: Text(_selected?.name ?? '点击选择食物'),
              subtitle: _selected != null
                  ? Text('${_selected!.caloriesPer100g.toStringAsFixed(0)} kcal/100g')
                  : null,
              trailing: const Icon(Icons.search),
              onTap: () async {
                final result = await Navigator.of(context).push<FoodItem>(
                  MaterialPageRoute(builder: (_) => const FoodLibraryPage(pickForReuse: true)),
                );
                if (result != null) setState(() => _selected = result);
              },
            ),
            if (_selected != null) ...[
              TextField(controller: _servingCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '份量 (g)')),
              const SizedBox(height: 24),
              FilledButton(onPressed: _logFromLibrary, child: const Text('记录')),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _customMode = true),
              child: const Text('找不到？自定义输入'),
            ),
          ] else ...[
            // 自定义模式
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: '食物名称')),
            TextField(controller: _calCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '热量 /100g (kcal)')),
            TextField(controller: _proteinCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '蛋白质 /100g (g)')),
            TextField(controller: _fatCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '脂肪 /100g (g)')),
            TextField(controller: _carbsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '碳水 /100g (g)')),
            TextField(controller: _servingCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '份量 (g)')),
            const SizedBox(height: 24),
            FilledButton(onPressed: _logCustom, child: const Text('存库并记录')),
          ],
        ],
      ),
    );
  }

  Future<void> _logFromLibrary() async {
    if (_selected == null) return;
    final serving = double.parse(_servingCtrl.text);
    final ratio = serving / 100;
    final db = await ref.read(recognize.databaseProvider.future);
    final mealRepo = MealLogRepository(db);
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await mealRepo.insertMealLog(
      date: today,
      mealType: _mealType,
      foodItemId: _selected!.id,
      actualServingG: serving,
      actualCalories: _selected!.caloriesPer100g * ratio,
      actualProteinG: _selected!.proteinPer100g * ratio,
      actualFatG: _selected!.fatPer100g * ratio,
      actualCarbsG: _selected!.carbsPer100g * ratio,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已记录 ${_selected!.name} ${serving.toStringAsFixed(0)}g')));
      Navigator.of(context).pop();
    }
  }

  Future<void> _logCustom() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final foodRepo = FoodItemRepository(db);
    final mealRepo = MealLogRepository(db);

    // 先存库（source=manual）
    final foodId = await foodRepo.upsertAiRecognized(
      name: _nameCtrl.text,
      caloriesPer100g: double.parse(_calCtrl.text),
      proteinPer100g: double.parse(_proteinCtrl.text),
      fatPer100g: double.parse(_fatCtrl.text),
      carbsPer100g: double.parse(_carbsCtrl.text),
    );
    // 注意：upsertAiRecognized 会写 source='ai_recognized'，手动录入应写 source='manual'
    // 实施时在 FoodItemRepository 补一个 insertManual 方法，或修改 upsertAiRecognized 支持 source 参数

    final serving = double.parse(_servingCtrl.text);
    final ratio = serving / 100;
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await mealRepo.insertMealLog(
      date: today,
      mealType: _mealType,
      foodItemId: foodId,
      actualServingG: serving,
      actualCalories: double.parse(_calCtrl.text) * ratio,
      actualProteinG: double.parse(_proteinCtrl.text) * ratio,
      actualFatG: double.parse(_fatCtrl.text) * ratio,
      actualCarbsG: double.parse(_carbsCtrl.text) * ratio,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已存库并记录 ${_nameCtrl.text}')));
      Navigator.of(context).pop();
    }
  }
}
```

> **实施注意**：`upsertAiRecognized` 硬编码 `source: 'ai_recognized'`，手动录入需 `source: 'manual'`。实施时在 FoodItemRepository 补一个 `insertManual(name, cal, protein, fat, carbs)` 方法（类似 upsertAiRecognized 但 source='manual'，不做 confidence/componentsJson）。已在 T0 文件结构里预留此修改。

- [ ] **Step 2: 修改 app.dart 补路由**

```dart
GoRoute(path: '/manual_entry', builder: (context, state) => const ManualEntryPage()),
```

- [ ] **Step 3: 测试 + 验证**

```bash
flutter analyze
# 手动录入页 UI 为主，逻辑测试覆盖在 T9 repo 测试 + Sprint 2 E2E
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/manual_entry/manual_entry_page.dart lib/data/repositories/food_item_repository.dart lib/app.dart
git commit -m "feat: Sprint 2 T10 - 手动录入(搜库复用+自定义存库)"
```

---

## Task 11: 体重记录 + fl_chart 趋势图

**目标:** 记录体重 + fl_chart 折线趋势图。

**参考设计文档:** 7.7（体重记录）

**Files:**
- Create: `lib/data/repositories/weight_log_repository.dart`
- Create: `lib/features/weight/weight_page.dart`（记录 + 折线图）
- Modify: `lib/app.dart`（路由补 weight）
- Test: `test/data/weight_log_repository_test.dart`

- [ ] **Step 1: 创建 weight_log_repository.dart**

```dart
import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

class WeightLogRepository {
  final EatWiseDatabase _db;
  WeightLogRepository(this._db);

  /// 插入体重记录（同一天多次记录各存一条，UI 取最新）
  Future<int> insert({required String date, required double weightKg}) {
    return _db.into(_db.weightLogs).insert(WeightLogsCompanion.insert(
          date: date,
          weightKg: weightKg,
        ));
  }

  /// 查询某区间体重记录（折线图用，按日期升序）
  Future<List<WeightLog>> getRange(String startDate, String endDate) {
    return (_db.weightLogs.select()
          ..where((w) => w.date.isBetweenValues(startDate, endDate))
          ..orderBy([(w) => OrderingTerm.asc(w.date)]))
        .get();
  }

  /// 查询最近 N 天体重（首页快速预览）
  Future<List<WeightLog>> getRecent({int days = 30}) async {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: days));
    final startDate = '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final endDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return getRange(startDate, endDate);
  }
}
```

- [ ] **Step 2: 创建 weight_page.dart（记录 + fl_chart 折线图）**

fl_chart 0.70.2 API（实测确认）：`LineChartBarData(color: Color?)` 单色，无 `colors` 列表。

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';
import '../../data/repositories/weight_log_repository.dart';
import '../recognize/providers.dart' as recognize;

class WeightPage extends ConsumerStatefulWidget {
  const WeightPage({super.key});
  @override
  ConsumerState<WeightPage> createState() => _WeightPageState();
}

class _WeightPageState extends ConsumerState<WeightPage> {
  final _weightCtrl = TextEditingController();
  List<WeightLog> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = WeightLogRepository(db);
    _logs = await repo.getRecent(days: 30);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('体重记录')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weightCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '今日体重 (kg)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton(onPressed: _save, child: const Text('记录')),
            ],
          ),
          const SizedBox(height: 24),
          if (_logs.length >= 2)
            SizedBox(
              height: 250,
              child: _buildChart(),
            )
          else
            const Center(child: Text('至少记录 2 次才能显示趋势图')),
          const SizedBox(height: 16),
          // 记录列表
          for (final log in _logs.reversed)
            ListTile(
              leading: const Icon(Icons.monitor_weight_outlined),
              title: Text('${log.weightKg.toStringAsFixed(1)} kg'),
              subtitle: Text(log.date),
            ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    // fl_chart 0.70.2: LineChartBarData(color: Color?) 单色
    final spots = <FlSpot>[];
    for (var i = 0; i < _logs.length; i++) {
      spots.add(FlSpot(i.toDouble(), _logs[i].weightKg));
    }
    final weights = _logs.map((l) => l.weightKg).toList();
    final minW = weights.reduce((a, b) => a < b ? a : b);
    final maxW = weights.reduce((a, b) => a > b ? a : b);
    final padding = (maxW - minW) * 0.1 + 0.5;

    return LineChart(LineChartData(
      gridData: const FlGridData(show: true),
      borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
      minX: 0,
      maxX: (_logs.length - 1).toDouble(),
      minY: (minW - padding),
      maxY: (maxW + padding),
      titlesData: FlTitlesData(
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(1)),
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: Colors.green,  // 0.70.2: color 单色，非 colors 列表
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: Colors.green.withOpacity(0.1)),
        ),
      ],
    ));
  }

  Future<void> _save() async {
    if (_weightCtrl.text.isEmpty) return;
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = WeightLogRepository(db);
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await repo.insert(date: today, weightKg: double.parse(_weightCtrl.text));
    _weightCtrl.clear();
    _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已记录体重')));
  }
}
```

> **fl_chart 0.70.2 实测确认**：`LineChartBarData(color: Color?)` 单色参数，`colors` 列表已移除。`FlDotData` / `BarAreaData` / `AxisTitles` / `SideTitles` 类名不变。`getTitlesWidget: (value, meta) => Widget`。

- [ ] **Step 3: 修改 app.dart 补路由**

```dart
GoRoute(path: '/weight', builder: (context, state) => const WeightPage()),
```

- [ ] **Step 4: 测试 + 验证**

```dart
// test/data/weight_log_repository_test.dart
test('insert + getRange 按日期升序', () async { ... });
test('getRecent 默认30天', () async { ... });
```

```bash
flutter analyze
flutter test test/data/weight_log_repository_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/weight_log_repository.dart lib/features/weight/weight_page.dart lib/app.dart \
  test/data/weight_log_repository_test.dart
git commit -m "feat: Sprint 2 T11 - 体重记录+fl_chart折线趋势"
```

---

## Task 12: AI 汇总（GLM-4-Flash）

**目标:** 周视图 → GLM-4-Flash 生成 ≤300 字中文建议 → 存 insight_summary（去重 + 可编辑）。

**参考设计文档:** 7.8（AI 汇总）

**关键 API（实测确认）：** GLM-4-Flash，baseUrl `https://open.bigmodel.cn/api/paas/v4`，OpenAI 兼容，免费。复用 openai_dart 7.0（同 Sprint 1 Qwen-VL 模式）。

**Files:**
- Create: `lib/ai/glm_flash_provider.dart`（GLM-4-Flash 文本生成）
- Create: `lib/data/repositories/insight_repository.dart`（insight_summary 读写 + 去重）
- Create: `lib/features/insight/insight_provider.dart`（Riverpod provider）
- Create: `lib/features/insight/insight_page.dart`（周视图 + 生成 + 可编辑）
- Modify: `lib/app.dart`（路由补 insight）
- Test: `test/features/insight_provider_test.dart`（Fake GLM 测试）
- Test: `test/smoke/glm_flash_smoke_test.dart`（真实 GLM-4-Flash 冒烟）

- [ ] **Step 1: 创建 glm_flash_provider.dart**

GLM-4-Flash 是纯文本模型（非视觉），用 openai_dart 的 chat completions（无图片消息）。

```dart
import 'package:openai_dart/openai_dart.dart';

/// GLM-4-Flash 汇总建议生成器（智谱免费文本模型，OpenAI 兼容）
class GlmFlashProvider {
  final OpenAIClient _client;

  /// apiKey: 智谱 API key
  /// baseUrl: 默认 https://open.bigmodel.cn/api/paas/v4
  GlmFlashProvider({
    required String apiKey,
    String baseUrl = 'https://open.bigmodel.cn/api/paas/v4',
  }) : _client = OpenAIClient(
          config: OpenAIConfig(
            authProvider: ApiKeyProvider(apiKey),
            baseUrl: baseUrl,
          ),
        );

  /// 根据一周饮食 + 体重数据生成 ≤300 字中文建议
  ///
  /// weeklyData 格式：
  /// {
  ///   'daily_calories': [1800, 2100, 1500, 2200, 1900, 2500, 1700],
  ///   'daily_weights': [70.2, 70.1, 70.3, 70.0, 69.8, 69.9, 69.7],
  ///   'target_calories': 2000,
  ///   'goal': 'cut',
  /// }
  Future<String> generateWeeklySummary(Map<String, dynamic> weeklyData) async {
    final prompt = _buildPrompt(weeklyData);
    final res = await _client.chat.completions.create(ChatCompletionCreateRequest(
      model: 'glm-4-flash',
      messages: [
        ChatMessage.system(
          '你是营养师助手。根据用户一周的饮食热量和体重数据，给出不超过300字的具体中文建议，'
          '包含：1）热量摄入评估 2）体重趋势分析 3）下周可执行建议。直接给建议，不要寒暄。',
        ),
        // 实测确认：openai_dart 7.0 是 UserMessageContent.text(...)（非 .string）
        // ChatMessage.user 也直接接受 String，等价简写为 ChatMessage.user(prompt)
        ChatMessage.user(UserMessageContent.text(prompt)),
      ],
      maxCompletionTokens: 500,  // 实测确认：maxTokens 已弃用，用 maxCompletionTokens
      temperature: 0.7,
    ));
    // 实测确认：res.choices.first.message.content 是 UserMessageContent（非空，非 String?）
    // 用 SDK 便捷访问器 res.text（String?），同 Sprint 1 qwen_vl_provider.dart 模式
    return res.text ?? '（无内容返回）';
  }

  String _buildPrompt(Map<String, dynamic> data) {
    final calories = data['daily_calories'] as List;
    final weights = data['daily_weights'] as List;
    final target = data['target_calories'];
    final goal = data['goal'];
    final goalLabel = goal == 'cut' ? '减脂' : goal == 'bulk' ? '增肌' : '维持';
    return '本周目标：$goalLabel，每日热量目标 $target kcal。'
        '每日摄入热量：$calories kcal。'
        '每日体重：$weights kg。'
        '请给出本周总结和下周建议。';
  }
}
```

> **openai_dart 7.0 API 已实测确认**（读 pub cache 源码 `openai_dart-7.0.0/lib/src/models/chat/user_message_content.dart`）：
> - `UserMessageContent.text(String)` ✅ 存在（非 `.string`，计划前版本写错已修正）
> - `UserMessageContent.parts([...])` ✅ 存在（Sprint 1 视觉用此）
> - `ChatMessage.user(String)` 直接接受字符串也合法（chat_message.dart 工厂构造器支持 String/List/UserMessageContent 三态）
> - 响应取文本：`res.text`（String? 便捷访问器），**非** `res.choices.first.message.content`（后者是 UserMessageContent 非空类型，不是 String?）
> - `maxTokens` 已弃用，用 `maxCompletionTokens`（两者都存在，前者会被 OpenAI 新模型忽略）

- [ ] **Step 2: 创建 insight_repository.dart（去重逻辑）**

去重：同 periodType + periodStart + periodEnd 已存在则返回旧记录，不重复生成（除非用户强制刷新）。

```dart
import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

class InsightRepository {
  final EatWiseDatabase _db;
  InsightRepository(this._db);

  /// 查询是否已有该周期汇总（去重用）
  Future<InsightSummary?> find(String periodType, String periodStart, String periodEnd) {
    return (_db.insightSummaries.select()
          ..where((i) =>
              i.periodType.equals(periodType) &
              i.periodStart.equals(periodStart) &
              i.periodEnd.equals(periodEnd)))
        .getSingleOrNull();
  }

  /// 插入新汇总
  Future<int> insert({
    required String periodType,
    required String periodStart,
    required String periodEnd,
    required String summaryText,
  }) {
    return _db.into(_db.insightSummaries).insert(InsightSummariesCompanion.insert(
          periodType: periodType,
          periodStart: periodStart,
          periodEnd: periodEnd,
          summaryText: summaryText,
          generatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
  }

  /// 编辑汇总文本（用户手动修改）
  Future<void> updateText(int id, String text) async {
    await (_db.insightSummaries.update()..where((i) => i.id.equals(id))).write(
      InsightSummariesCompanion(
        summaryText: Value(text),
        isEdited: const Value(1),
      ),
    );
  }

  /// 强制重新生成（删旧插新）
  Future<int> regenerate({
    required String periodType,
    required String periodStart,
    required String periodEnd,
    required String summaryText,
  }) async {
    final old = await find(periodType, periodStart, periodEnd);
    if (old != null) {
      await (_db.insightSummaries.delete()..where((i) => i.id.equals(old.id))).go();
    }
    return insert(
      periodType: periodType,
      periodStart: periodStart,
      periodEnd: periodEnd,
      summaryText: summaryText,
    );
  }
}
```

- [ ] **Step 3: 创建 insight_page.dart（周视图 + 生成 + 可编辑）**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/glm_flash_provider.dart';
import '../../data/repositories/insight_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/weight_log_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../recognize/providers.dart' as recognize;

class InsightPage extends ConsumerStatefulWidget {
  const InsightPage({super.key});
  @override
  ConsumerState<InsightPage> createState() => _InsightPageState();
}

class _InsightPageState extends ConsumerState<InsightPage> {
  String? _summary;
  bool _loading = false;
  late String _weekStart;
  late String _weekEnd;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    _weekStart = _fmt(monday);
    _weekEnd = _fmt(sunday);
    _loadExisting();
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadExisting() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = InsightRepository(db);
    final existing = await repo.find('weekly', _weekStart, _weekEnd);
    if (existing != null) setState(() => _summary = existing.summaryText);
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      final db = await ref.read(recognize.databaseProvider.future);
      final mealRepo = MealLogRepository(db);
      final weightRepo = WeightLogRepository(db);
      final profileRepo = ProfileRepository(db);

      final meals = await mealRepo.getRange(_weekStart, _weekEnd);
      final weights = await weightRepo.getRange(_weekStart, _weekEnd);
      final profile = await profileRepo.get();

      // 按日聚合热量
      final dailyCal = <double>[];
      for (var i = 0; i < 7; i++) {
        final date = _fmt(DateTime.parse(_weekStart).add(Duration(days: i)));
        final cal = meals.where((m) => m.date == date).fold<double>(0, (s, m) => s + m.actualCalories);
        dailyCal.add(cal);
      }
      final dailyWeight = weights.map((w) => w.weightKg).toList();

      final apiKey = const String.fromEnvironment('GLM_API_KEY');
      if (apiKey.isEmpty) {
        setState(() => _summary = '未配置 GLM_API_KEY（用 --dart-define=GLM_API_KEY=xxx 启动）');
        return;
      }
      final provider = GlmFlashProvider(apiKey: apiKey);
      final text = await provider.generateWeeklySummary({
        'daily_calories': dailyCal,
        'daily_weights': dailyWeight,
        'target_calories': profile.dailyCalorieTarget,
        'goal': profile.goal,
      });

      final insightRepo = InsightRepository(db);
      await insightRepo.regenerate(
        periodType: 'weekly',
        periodStart: _weekStart,
        periodEnd: _weekEnd,
        summaryText: text,
      );
      setState(() => _summary = text);
    } catch (e) {
      setState(() => _summary = '生成失败：$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$_weekStart ~ $_weekEnd')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_summary != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(_summary!, style: const TextStyle(fontSize: 15, height: 1.6)),
              ),
            )
          else
            const Card(
              child: Padding(padding: EdgeInsets.all(16), child: Text('本周尚未生成汇总，点击下方按钮生成')),
            ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            FilledButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_summary == null ? '生成本周汇总' : '重新生成'),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 创建真实 API 冒烟测试**

```dart
// test/smoke/glm_flash_smoke_test.dart
// 同 Sprint 1 real_api_smoke_test.dart 模式：HttpOverrides.global = null 走真实网络
import 'dart:io';
import 'package:eatwise/ai/glm_flash_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HttpOverrides.global = null;
  final apiKey = const String.fromEnvironment('GLM_API_KEY');
  final canRun = apiKey.isNotEmpty;

  test('GLM-4-Flash 生成周汇总', skip: canRun ? false : '需 GLM_API_KEY', () async {
    final provider = GlmFlashProvider(apiKey: apiKey);
    final text = await provider.generateWeeklySummary({
      'daily_calories': [1800, 2100, 1500, 2200, 1900, 2500, 1700],
      'daily_weights': [70.2, 70.1, 70.3, 70.0, 69.8, 69.9, 69.7],
      'target_calories': 2000,
      'goal': 'cut',
    });
    expect(text.length, lessThan(500), reason: '应≤300字');
    expect(text.isNotEmpty, isTrue);
    // ignore: avoid_print
    print('✅ GLM-4-Flash 返回 ${text.length} 字: $text');
  });
}
```

- [ ] **Step 5: 修改 app.dart 补路由**

```dart
GoRoute(path: '/insight', builder: (context, state) => const InsightPage()),
```

- [ ] **Step 6: 测试 + 验证**

```bash
flutter analyze
flutter test test/features/insight_provider_test.dart  # Fake 测试
# 真实冒烟（用户 key）：
flutter test test/smoke/glm_flash_smoke_test.dart --dart-define=GLM_API_KEY=YOUR_GLM_API_KEY
```

- [ ] **Step 7: Commit**

```bash
git add lib/ai/glm_flash_provider.dart lib/data/repositories/insight_repository.dart \
  lib/features/insight/insight_page.dart lib/app.dart \
  test/features/insight_provider_test.dart test/smoke/glm_flash_smoke_test.dart
git commit -m "feat: Sprint 2 T12 - GLM-4-Flash周汇总+insight去重+可编辑"
```

---

## Task 13: JSON 导出导入 + drift 迁移链

**目标:** 全表数据导出为 JSON 文件（含 schemaVersion）；导入 JSON 走迁移链恢复数据。

**参考设计文档:** 9.1（JSON 导出导入）

**关键决策：** Sprint 2 不改表结构（7 张表已齐全），schemaVersion 保持 1。T13 的"迁移链"指导入旧版本 JSON 时的兼容（当前只有 v1，预留 schemaVersion 字段为未来 v2 做准备）。

**Files:**
- Create: `lib/data/backup/json_exporter.dart`
- Create: `lib/data/backup/json_importer.dart`
- Create: `lib/features/backup/backup_page.dart`（导出/导入入口 UI）
- Modify: `lib/app.dart`（路由补 backup）
- Test: `test/data/backup/json_export_import_test.dart`

- [ ] **Step 1: 创建 json_exporter.dart**

导出 6 张表（除 pending_recognition，它是临时队列不导出）。每个 food_item 的 thumbnailPath 导出但标记为"可能失效"（导入时处理）。

```dart
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

class JsonExporter {
  final EatWiseDatabase _db;
  JsonExporter(this._db);

  /// 导出全表为 JSON Map
  /// 结构：{ schemaVersion: 1, exportedAt: ms, tables: { profiles: [...], food_items: [...], ... } }
  Future<Map<String, dynamic>> export() async {
    final profiles = await _db.profiles.select().get();
    final foodItems = await _db.foodItems.select().get();
    final mealLogs = await _db.mealLogs.select().get();
    final weightLogs = await _db.weightLogs.select().get();
    final insightSummaries = await _db.insightSummaries.select().get();
    final recognitionFeedbacks = await _db.recognitionFeedbacks.select().get();

    return {
      'schemaVersion': _db.schemaVersion,  // 1
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'tables': {
        'profiles': profiles.map(_profileToJson).toList(),
        'food_items': foodItems.map(_foodItemToJson).toList(),
        'meal_logs': mealLogs.map(_mealLogToJson).toList(),
        'weight_logs': weightLogs.map(_weightLogToJson).toList(),
        'insight_summaries': insightSummaries.map(_insightToJson).toList(),
        'recognition_feedbacks': recognitionFeedbacks.map(_feedbackToJson).toList(),
        // 注意：pending_recognitions 不导出（临时队列）
      },
    };
  }

  /// 导出为 JSON 字符串
  Future<String> exportAsString() async {
    final data = await export();
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Map<String, dynamic> _profileToJson(Profile p) => {
    'id': p.id, 'heightCm': p.heightCm, 'weightKg': p.weightKg,
    'bodyFatPct': p.bodyFatPct, 'age': p.age, 'gender': p.gender,
    'activityLevel': p.activityLevel, 'goal': p.goal, 'goalRateKgPerWeek': p.goalRateKgPerWeek,
    'formula': p.formula, 'dailyCalorieTarget': p.dailyCalorieTarget,
    'proteinGPerKg': p.proteinGPerKg, 'fatGPerKg': p.fatGPerKg, 'carbGPerKg': p.carbGPerKg,
    'tdeeAdjustmentKcal': p.tdeeAdjustmentKcal, 'updatedAt': p.updatedAt,
  };

  Map<String, dynamic> _foodItemToJson(FoodItem f) => {
    'id': f.id, 'name': f.name, 'defaultServingG': f.defaultServingG,
    'caloriesPer100g': f.caloriesPer100g, 'proteinPer100g': f.proteinPer100g,
    'fatPer100g': f.fatPer100g, 'carbsPer100g': f.carbsPer100g,
    'aliasesJson': f.aliasesJson, 'ediblePercent': f.ediblePercent,
    'source': f.source, 'sourceVersion': f.sourceVersion, 'confidence': f.confidence,
    'componentsJson': f.componentsJson,
    // thumbnailPath 导出但标记"可能失效"（不同设备路径不同）
    'thumbnailPath': f.thumbnailPath,
    'createdAt': f.createdAt,
  };

  Map<String, dynamic> _mealLogToJson(MealLog m) => {
    'id': m.id, 'date': m.date, 'mealType': m.mealType,
    'foodItemId': m.foodItemId, 'actualServingG': m.actualServingG,
    'actualCalories': m.actualCalories, 'actualProteinG': m.actualProteinG,
    'actualFatG': m.actualFatG, 'actualCarbsG': m.actualCarbsG,
    'originalImagePath': m.originalImagePath,  // 标记"可能失效"
    'recognitionConfidence': m.recognitionConfidence,
    'componentsSnapshotJson': m.componentsSnapshotJson,
    'loggedAt': m.loggedAt,
  };

  Map<String, dynamic> _weightLogToJson(WeightLog w) => {
    'id': w.id, 'date': w.date, 'weightKg': w.weightKg,
  };

  Map<String, dynamic> _insightToJson(InsightSummary i) => {
    'id': i.id, 'periodType': i.periodType, 'periodStart': i.periodStart,
    'periodEnd': i.periodEnd, 'summaryText': i.summaryText,
    'isEdited': i.isEdited, 'generatedAt': i.generatedAt,
  };

  Map<String, dynamic> _feedbackToJson(RecognitionFeedback f) => {
    'id': f.id, 'mealLogId': f.mealLogId, 'isCorrect': f.isCorrect,
    'correctedDishName': f.correctedDishName, 'correctedServingG': f.correctedServingG,
    'promptVersion': f.promptVersion, 'createdAt': f.createdAt,
  };
}
```

- [ ] **Step 2: 创建 json_importer.dart**

导入策略：清空 6 表后批量插入。ID 保留（便于 meal_log.food_item_id / feedback.mealLog_id 外键不变）。导入顺序：profile → food_items → meal_logs → weight_logs → insight_summaries → recognition_feedbacks（依赖顺序）。

```dart
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

class JsonImporter {
  final EatWiseDatabase _db;
  JsonImporter(this._db);

  /// 从 JSON 字符串导入
  /// 返回导入条数统计
  Future<({int profiles, int foodItems, int mealLogs, int weightLogs, int insights, int feedbacks})> importFromString(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    return importFromMap(data);
  }

  Future<({int profiles, int foodItems, int mealLogs, int weightLogs, int insights, int feedbacks})> importFromMap(Map<String, dynamic> data) async {
    final schemaVersion = data['schemaVersion'] as int;
    if (schemaVersion != _db.schemaVersion) {
      throw ArgumentError('schemaVersion 不匹配：文件 $schemaVersion vs 当前 ${_db.schemaVersion}');
    }

    final tables = data['tables'] as Map<String, dynamic>;
    // 关闭外键约束（清空时需临时关闭，避免级联删除顺序问题）
    await _db.customStatement('PRAGMA foreign_keys = OFF;');
    try {
      // 清空 6 表（顺序无所谓，因外键已关闭）
      await _db.customStatement('DELETE FROM recognition_feedbacks;');
      await _db.customStatement('DELETE FROM insight_summaries;');
      await _db.customStatement('DELETE FROM weight_logs;');
      await _db.customStatement('DELETE FROM meal_logs;');
      await _db.customStatement('DELETE FROM food_items;');
      await _db.customStatement('DELETE FROM profiles;');

      // 按依赖顺序插入
      int profiles = 0, foodItems = 0, mealLogs = 0, weightLogs = 0, insights = 0, feedbacks = 0;

      // 1. profiles
      for (final p in (tables['profiles'] as List)) {
        await _db.into(_db.profiles).insert(_profileFromJson(p as Map<String, dynamic>));
        profiles++;
      }
      // 2. food_items
      for (final f in (tables['food_items'] as List)) {
        await _db.into(_db.foodItems).insert(_foodItemFromJson(f as Map<String, dynamic>));
        foodItems++;
      }
      // 3. meal_logs（依赖 food_items）
      for (final m in (tables['meal_logs'] as List)) {
        await _db.into(_db.mealLogs).insert(_mealLogFromJson(m as Map<String, dynamic>));
        mealLogs++;
      }
      // 4. weight_logs（独立）
      for (final w in (tables['weight_logs'] as List)) {
        await _db.into(_db.weightLogs).insert(_weightLogFromJson(w as Map<String, dynamic>));
        weightLogs++;
      }
      // 5. insight_summaries（独立）
      for (final i in (tables['insight_summaries'] as List)) {
        await _db.into(_db.insightSummaries).insert(_insightFromJson(i as Map<String, dynamic>));
        insights++;
      }
      // 6. recognition_feedbacks（依赖 meal_logs）
      for (final f in (tables['recognition_feedbacks'] as List)) {
        await _db.into(_db.recognitionFeedbacks).insert(_feedbackFromJson(f as Map<String, dynamic>));
        feedbacks++;
      }

      return (profiles: profiles, foodItems: foodItems, mealLogs: mealLogs, weightLogs: weightLogs, insights: insights, feedbacks: feedbacks);
    } finally {
      // 恢复外键约束
      await _db.customStatement('PRAGMA foreign_keys = ON;');
    }
  }

  ProfilesCompanion _profileFromJson(Map<String, dynamic> j) => ProfilesCompanion.insert(
    id: Value(j['id'] as int),
    heightCm: j['heightCm'] as double,
    weightKg: j['weightKg'] as double,
    bodyFatPct: Value(j['bodyFatPct'] as double?),
    age: j['age'] as int,
    gender: j['gender'] as String,
    activityLevel: j['activityLevel'] as double,
    goal: j['goal'] as String,
    goalRateKgPerWeek: j['goalRateKgPerWeek'] as double,
    formula: j['formula'] as String,
    dailyCalorieTarget: j['dailyCalorieTarget'] as int,
    proteinGPerKg: j['proteinGPerKg'] as double,
    fatGPerKg: j['fatGPerKg'] as double,
    carbGPerKg: Value(j['carbGPerKg'] as double?),
    tdeeAdjustmentKcal: Value(j['tdeeAdjustmentKcal'] as int),
    updatedAt: j['updatedAt'] as int,
  );

  FoodItemsCompanion _foodItemFromJson(Map<String, dynamic> j) => FoodItemsCompanion.insert(
    id: Value(j['id'] as int),  // 保留原 ID（外键依赖）
    name: j['name'] as String,
    defaultServingG: j['defaultServingG'] as double,
    caloriesPer100g: j['caloriesPer100g'] as double,
    proteinPer100g: j['proteinPer100g'] as double,
    fatPer100g: j['fatPer100g'] as double,
    carbsPer100g: j['carbsPer100g'] as double,
    aliasesJson: Value(j['aliasesJson'] as String?),
    ediblePercent: Value(j['ediblePercent'] as double?),
    source: j['source'] as String,
    sourceVersion: j['sourceVersion'] as String,
    confidence: Value(j['confidence'] as double?),
    componentsJson: Value(j['componentsJson'] as String?),
    thumbnailPath: Value(j['thumbnailPath'] as String?),  // 可能失效
    createdAt: j['createdAt'] as int,
  );

  MealLogsCompanion _mealLogFromJson(Map<String, dynamic> j) => MealLogsCompanion.insert(
    id: Value(j['id'] as int),
    date: j['date'] as String,
    mealType: j['mealType'] as String,
    foodItemId: j['foodItemId'] as int,
    actualServingG: j['actualServingG'] as double,
    actualCalories: j['actualCalories'] as double,
    actualProteinG: j['actualProteinG'] as double,
    actualFatG: j['actualFatG'] as double,
    actualCarbsG: j['actualCarbsG'] as double,
    originalImagePath: Value(j['originalImagePath'] as String?),  // 可能失效
    recognitionConfidence: Value(j['recognitionConfidence'] as double?),
    componentsSnapshotJson: Value(j['componentsSnapshotJson'] as String?),
    loggedAt: j['loggedAt'] as int,
  );

  WeightLogsCompanion _weightLogFromJson(Map<String, dynamic> j) => WeightLogsCompanion.insert(
    id: Value(j['id'] as int),
    date: j['date'] as String,
    weightKg: j['weightKg'] as double,
  );

  InsightSummariesCompanion _insightFromJson(Map<String, dynamic> j) => InsightSummariesCompanion.insert(
    id: Value(j['id'] as int),
    periodType: j['periodType'] as String,
    periodStart: j['periodStart'] as String,
    periodEnd: j['periodEnd'] as String,
    summaryText: j['summaryText'] as String,
    isEdited: Value(j['isEdited'] as int),
    generatedAt: j['generatedAt'] as int,
  );

  RecognitionFeedbacksCompanion _feedbackFromJson(Map<String, dynamic> j) => RecognitionFeedbacksCompanion.insert(
    id: Value(j['id'] as int),
    mealLogId: j['mealLogId'] as int,
    isCorrect: j['isCorrect'] as int,
    correctedDishName: Value(j['correctedDishName'] as String?),
    correctedServingG: Value(j['correctedServingG'] as double?),
    promptVersion: j['promptVersion'] as String,
    createdAt: j['createdAt'] as int,
  );
}
```

> **注意**：导入时临时 `PRAGMA foreign_keys = OFF` 以便清空表时不触发级联，最后恢复 `ON`。drift 的 `insert` 默认不覆盖 autoIncrement 的 id，需用 `Value(id)` 显式指定保留原 ID（保证 meal_logs.food_item_id 外键不变）。

- [ ] **Step 3: 创建 backup_page.dart（导出/导入入口 UI）**

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';  // 注意：需加 share_plus 依赖

import '../../data/backup/json_exporter.dart';
import '../../data/backup/json_importer.dart';
import '../recognize/providers.dart' as recognize;

class BackupPage extends ConsumerWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据备份')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: () => _export(context, ref),
            icon: const Icon(Icons.upload),
            label: const Text('导出为 JSON'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _import(context, ref),
            icon: const Icon(Icons.download),
            label: const Text('从 JSON 导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final db = await ref.read(recognize.databaseProvider.future);
    final exporter = JsonExporter(db);
    final jsonStr = await exporter.exportAsString();
    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final fileName = 'eatwise_backup_${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}.json';
    final file = await File('${dir.path}/$fileName').writeAsString(jsonStr);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出到 ${file.path}')));
      await Share.shareXFiles([XFile(file.path)], text: 'EatWise 数据备份');
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    // MVP：从文件选择器读 JSON（需 file_picker 依赖）
    // 实施时简化：用 file_picker 选文件 → 读内容 → JsonImporter.importFromString
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导入功能实施时接 file_picker')));
  }
}
```

> **实施注意**：`share_plus` 和 `file_picker` 需加到 pubspec。若不想加依赖，导出改为写入 App 文档目录后只显示路径 SnackBar，导入改为从固定路径读。实施时按需决定。

- [ ] **Step 4: 测试 + 验证**

```dart
// test/data/backup/json_export_import_test.dart
test('导出→导入后数据一致', () async {
  // 1. 内存 DB 插入测试数据
  // 2. JsonExporter.export() → jsonStr
  // 3. 新内存 DB → JsonImporter.importFromString(jsonStr)
  // 4. 查询比对各表条数 + 关键字段
});

test('schemaVersion 不匹配时抛异常', () async { ... });

test('导入后外键关系完整（meal_log.food_item_id 有效）', () async { ... });
```

```bash
flutter analyze
flutter test test/data/backup/json_export_import_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/data/backup/json_exporter.dart lib/data/backup/json_importer.dart \
  lib/features/backup/backup_page.dart lib/app.dart \
  test/data/backup/json_export_import_test.dart pubspec.yaml
git commit -m "feat: Sprint 2 T13 - JSON全表导出导入+schemaVersion校验"
```

---

## Task 14: 离线队列（前台触发版）

**目标:** 离线拍照进 pending_recognition 队列 → 联网后前台自动回补识别（重试上限 3 次）。

**参考设计文档:** 10.1-10.2（离线队列）

**关键决策（用户确认）：** 只做前台触发版（connectivity_plus 监听网络恢复），workmanager 后台兜底推迟 Sprint 3。

**关键 API（实测确认）：** connectivity_plus 6.1.5，`Stream<List<ConnectivityResult>>`（6.0 breaking：返回 List）。

**Files:**
- Create: `lib/data/repositories/pending_recognition_repository.dart`
- Create: `lib/features/offline/offline_queue_controller.dart`（connectivity_plus 监听 + 重试）
- Modify: `lib/features/recognize/recognize_controller.dart`（离线时入队而非直接报错）
- Test: `test/features/offline_queue_test.dart`

- [ ] **Step 1: 创建 pending_recognition_repository.dart**

```dart
import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

class PendingRecognitionRepository {
  final EatWiseDatabase _db;
  PendingRecognitionRepository(this._db);

  /// 入队（离线拍照时调用）
  Future<int> enqueue({
    required String imagePath,
    required String mealType,
    required String date,
    String promptVersion = 'v1.0',
  }) {
    return _db.into(_db.pendingRecognitions).insert(PendingRecognitionsCompanion.insert(
          imagePath: imagePath,
          mealType: mealType,
          date: date,
          status: 'pending',
          promptVersion: Value(promptVersion),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
  }

  /// 查询所有 pending 记录（按创建时间升序，FIFO）
  Future<List<PendingRecognition>> listPending() {
    return (_db.pendingRecognitions.select()
          ..where((p) => p.status.equals('pending'))
          ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]))
        .get();
  }

  /// 标记成功
  Future<void> markDone(int id, int resultFoodItemId) async {
    await (_db.pendingRecognitions.update()..where((p) => p.id.equals(id))).write(
      PendingRecognitionsCompanion(
        status: const Value('done'),
        resultFoodItemId: Value(resultFoodItemId),
        processedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 标记失败 + 重试计数 +1
  Future<void> markFailed(int id, String errorMessage) async {
    final current = await (_db.pendingRecognitions.select()..where((p) => p.id.equals(id))).getSingle();
    await (_db.pendingRecognitions.update()..where((p) => p.id.equals(id))).write(
      PendingRecognitionsCompanion(
        status: current.retryCount >= 2 ? const Value('failed') : const Value('pending'),  // 重试 3 次后 failed
        retryCount: Value(current.retryCount + 1),
        errorMessage: Value(errorMessage),
      ),
    );
  }

  /// 统计 pending 数量（UI 角标用）
  Future<int> countPending() async {
    final result = await (_db.pendingRecognitions.select()..where((p) => p.status.equals('pending'))).get();
    return result.length;
  }
}
```

- [ ] **Step 2: 创建 offline_queue_controller.dart**

connectivity_plus 6.1.5 实测确认：`onConnectivityChanged` 返回 `Stream<List<ConnectivityResult>>`，判断有网用 `results.any((r) => r != ConnectivityResult.none)`。

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/qwen_vl_provider.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/pending_recognition_repository.dart';
import '../../data/database/database.dart';
import '../recognize/providers.dart' as recognize;

/// 离线队列前台触发控制器
/// 监听 connectivity_plus 网络恢复事件，自动回补 pending 识别
class OfflineQueueController {
  final EatWiseDatabase _db;
  final String _qwenApiKey;
  final String _qwenBaseUrl;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _wasOffline = true;
  bool _processing = false;

  OfflineQueueController({
    required EatWiseDatabase db,
    required String qwenApiKey,
    String qwenBaseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1',
  })  : _db = db,
        _qwenApiKey = qwenApiKey,
        _qwenBaseUrl = qwenBaseUrl;

  /// 启动监听（App 启动时调用）
  Future<void> start() async {
    // 取初始状态
    final initial = await Connectivity().checkConnectivity();
    _wasOffline = initial.every((r) => r == ConnectivityResult.none);

    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (_wasOffline && isOnline) {
        // 网络恢复 → 触发回补
        processPending();
      }
      _wasOffline = !isOnline;
    });

    // 启动时若已在线也尝试一次（处理上次崩溃残留）
    if (!_wasOffline) processPending();
  }

  /// 停止监听
  void stop() => _sub?.cancel();

  /// 处理所有 pending 记录
  Future<void> processPending() async {
    if (_processing) return;  // 防重入
    _processing = true;
    try {
      final pendingRepo = PendingRecognitionRepository(_db);
      final pending = await pendingRepo.listPending();
      if (pending.isEmpty) return;

      final provider = QwenVlProvider(apiKey: _qwenApiKey, baseUrl: _qwenBaseUrl);
      final mealRepo = MealLogRepository(_db);
      final foodItemRepo = FoodItemRepository(_db);  // 已在顶部直接 import food_item_repository.dart
      final lookup = NutritionLookup(foodItemRepo);

      for (final p in pending) {
        try {
          // 读图片 base64
          final imageFile = File(p.imagePath);
          if (!imageFile.existsSync()) {
            await pendingRepo.markFailed(p.id, '图片文件不存在');
            continue;
          }
          final imageBase64 = base64Encode(await imageFile.readAsBytes());

          // 调 Qwen-VL
          final result = await provider.recognize(imageBase64);

          // 查库回填
          final nutrition = await lookup.lookupSingleItem(
            dishName: result.dishName,
            servingG: result.estimatedWeightGMid,
          );

          if (nutrition == null) {
            // 查库未命中 → upsertAiRecognized 后再查
            final foodId = await foodItemRepo.upsertAiRecognized(
              name: result.dishName,
              caloriesPer100g: 0, proteinPer100g: 0, fatPer100g: 0, carbsPer100g: 0,
              confidence: result.confidence,
            );
            await pendingRepo.markDone(p.id, foodId);
            continue;
          }

          // 写 meal_log
          await mealRepo.insertMealLog(
            date: p.date,
            mealType: p.mealType,
            foodItemId: nutrition.foodItemId,
            actualServingG: result.estimatedWeightGMid,
            actualCalories: nutrition.calories,
            actualProteinG: nutrition.proteinG,
            actualFatG: nutrition.fatG,
            actualCarbsG: nutrition.carbsG,
            originalImagePath: p.imagePath,
            recognitionConfidence: result.confidence,
          );
          await pendingRepo.markDone(p.id, nutrition.foodItemId);
        } catch (e) {
          await pendingRepo.markFailed(p.id, e.toString());
        }
      }
    } finally {
      _processing = false;
    }
  }
}
```

> **注意 import**：`base64Encode` 来自 `dart:convert`，`File` 来自 `dart:io`，已在顶部补全。`FoodItemRepository` 直接 import `../../data/repositories/food_item_repository.dart`（不通过 `recognize.` 前缀，因 providers.dart 未 export 此类）。

- [ ] **Step 3: 修改 recognize_controller.dart — 离线时入队**

在 `pickAndRecognize` 的 recognizing 阶段捕获网络异常，若离线则入队 pending_recognition 而非报错。

```dart
// recognize_controller.dart 修改点（recognizing 阶段 catch 网络异常）：

Future<void> pickAndRecognize(ImageSource source, {required String mealType}) async {
  // ... pickingImage + preprocessing 不变 ...

  state = state.copyWith(state: RecognizeState.recognizing);
  try {
    // ... 调 QwenVlProvider ...
  } on VisionRecognitionException catch (e) {
    // 网络类异常 → 入队
    if (_isNetworkError(e)) {
      final pendingRepo = PendingRecognitionRepository(_db);
      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
      await pendingRepo.enqueue(
        imagePath: state.imagePath!,
        mealType: mealType,
        date: today,
      );
      state = state.copyWith(
        state: RecognizeState.idle,
        errorMessage: '当前离线，已加入队列，联网后自动识别',
      );
    } else {
      state = state.copyWith(state: RecognizeState.error, errorMessage: e.message);
    }
  }
}

bool _isNetworkError(VisionRecognitionException e) {
  // VisionRecognitionException 的子类：NetworkError / Timeout
  return e is VisionRecognitionNetworkException || e is VisionRecognitionTimeoutException;
}
```

> **实施注意**：`_isNetworkError` 的异常子类名需对照 Sprint 1 `vision_provider.dart` 的实际定义。实施时核实。

- [ ] **Step 4: 测试 + 验证**

```dart
// test/features/offline_queue_test.dart
// 用 Fake QwenVlProvider（模拟网络失败→恢复）+ 内存 DB
test('离线入队 → 模拟网络恢复 → 自动回补识别', () async { ... });
test('重试 3 次后标记 failed', () async { ... });
test('图片不存在时 markFailed', () async { ... });
test('countPending 角标数量', () async { ... });
```

```bash
flutter analyze
flutter test test/features/offline_queue_test.dart
```

> **沙箱验证说明**：connectivity_plus 是平台插件，沙箱无法模拟真实网络切换。测试用 Fake provider + 手动调 `processPending()` 验证逻辑。真实网络切换监听需真机验证，标注为"已知不可验证项"。

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/pending_recognition_repository.dart \
  lib/features/offline/offline_queue_controller.dart \
  lib/features/recognize/recognize_controller.dart \
  test/features/offline_queue_test.dart
git commit -m "feat: Sprint 2 T14 - 离线队列前台触发版(connectivity_plus+重试上限3)"
```

---

## Sprint 2 端到端集成测试 + 真实 API 冒烟

**目标:** 全部 Task 完成后，跑端到端集成测试 + GLM-4-Flash 真实冒烟，验证 Sprint 2 成功标准。

**Files:**
- Create: `test/integration/sprint2_e2e_test.dart`（集成测试）
- Test: `test/smoke/glm_flash_smoke_test.dart`（T12 已创建，此处运行）

- [ ] **Step 1: 创建 sprint2_e2e_test.dart**

```dart
// Sprint 2 端到端集成测试（内存 DB + Fake Provider）
// 覆盖：profile 录入→看板宏量 / 拍照记录餐次→今日分组 / 食物库搜索复用 /
//       手动录入 / 体重记录 / insight 去重 / JSON 导出导入 / 离线队列入队
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/weight_log_repository.dart';
import 'package:eatwise/data/repositories/insight_repository.dart';
import 'package:eatwise/data/repositories/pending_recognition_repository.dart';
import 'package:eatwise/data/repositories/recognition_feedback_repository.dart';
import 'package:eatwise/data/backup/json_exporter.dart';
import 'package:eatwise/data/backup/json_importer.dart';
import 'package:eatwise/data/seed/food_seed_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  // ... setUp/tearDown 同 Sprint 1 e2e ...

  test('T0+T8: profile 录入 → 看板读取宏量目标', () async { ... });
  test('T8: 拍照记录带餐次 → 今日记录按餐次分组', () async { ... });
  test('T8: 编辑份量 → 按比例重算营养素', () async { ... });
  test('T8: 删除 meal_log → recognition_feedback 级联删除', () async { ... });
  test('T9: 搜索食物 → listFrequent 按引用次数', () async { ... });
  test('T10: 手动录入自定义食物 → 存库(source=manual) → 记录', () async { ... });
  test('T11: 体重记录 → getRange 按日期升序', () async { ... });
  test('T12: insight 同周期去重 → regenerate 删旧插新', () async { ... });
  test('T13: 导出→新DB导入→数据一致+外键完整', () async { ... });
  test('T14: 离线入队 → 手动 processPending → 写 meal_log', () async { ... });
  test('T14: 重试3次后标记 failed', () async { ... });
}
```

- [ ] **Step 2: 运行全量测试 + 真实冒烟**

```bash
# 常规测试（单元 + 集成）
flutter analyze
flutter test test/ai/ test/data/ test/features/ test/integration/

# GLM-4-Flash 真实冒烟
flutter test test/smoke/glm_flash_smoke_test.dart \
  --dart-define=GLM_API_KEY=YOUR_GLM_API_KEY
```

- [ ] **Step 3: Commit**

```bash
git add test/integration/sprint2_e2e_test.dart
git commit -m "test: Sprint 2 端到端集成测试 + GLM-4-Flash 真实冒烟"
```

---

## Self-Review

> 本节在实施过程中持续更新，记录发现的计划偏差、API 差异、数据问题及修复方式。

### 1. 计划编写前的 API 实测（已完成，无盲区）

| 项 | 实测方式 | 结果 | 影响 Task |
|---|---|---|---|
| connectivity_plus 6.1.5 | 读 pub cache 源码 | `Stream<List<ConnectivityResult>>` + 枚举 8 值 | T14 |
| fl_chart 0.70.2 | grep pub cache | `LineChartBarData(color: Color?)` 单色，无 colors | T11 |
| drift Migrator 2.34.0 | grep pub cache | `createTable(TableInfo)` / `addColumn(TableInfo, GeneratedColumn)` | T13（Sprint 2 不改表，预留） |
| GLM-4-Flash | WebSearch 官方文档 | `open.bigmodel.cn/api/paas/v4` OpenAI 兼容免费 | T12 |
| Sanotsu 完整数据 | curl GitHub + jsdelivr | 仓库超 50MB，字段有脏数据（多值/空/后缀） | T0.3 |

### 2. 复核中已实测确认的 API 项（计划已修正，无需实施时再核实）

| 项 | 位置 | 实测结果 | 计划修正 |
|---|---|---|---|
| `UserMessageContent.string()` | T12 glm_flash_provider | ❌ 不存在；✅ 实际是 `UserMessageContent.text(String)` | 已改为 `.text(prompt)`；`ChatMessage.user(String)` 也合法 |
| 响应取文本 | T12 glm_flash_provider | `res.choices.first.message.content` 是 `UserMessageContent`（非空，非 String?） | 已改用 `res.text ?? '...'`（同 Sprint 1 qwen_vl_provider） |
| `maxTokens` | T12 glm_flash_provider | 存在但已弃用，OpenAI 新模型会忽略 | 已改为 `maxCompletionTokens` |
| `recognize.databaseProvider` 可达性 | T8-T14（15 处） | providers.dart 只 import 未 export database.dart，`recognize.databaseProvider` 不可达 | T0 Step 0 已加 `export '../../data/database/database.dart';` |
| `recognize.FoodItemRepository` | T14 | providers.dart 未 export 此类 | T14 改为直接 import + `FoodItemRepository(_db)` |

### 3. 实施中仍需核实的项（实施时第一个 Step 核实）

| 项 | 位置 | 风险 | 核实方式 |
|---|---|---|---|
| `FoodItemRepository.insertManual` | T10 | upsertAiRecognized 硬编码 source='ai_recognized' | T10 实施时在 repo 补 insertManual 方法 |
| `FoodItemRepository.updateNutrients` | T9 food_edit_page | 计划标注占位 | T9 实施时补此方法 |
| `_isNetworkError` 异常子类名 | T14 recognize_controller | 计划标注需核实 | grep vision_provider.dart 的异常类定义 |
| `share_plus` / `file_picker` 依赖 | T13 backup_page | 计划标注可选 | 实施时决定是否加依赖，或改为只写文件路径 |

### 4. Sprint 2 范围决策（用户确认）

- 离线队列：只做前台触发版（connectivity_plus），workmanager 后台兜底推迟 Sprint 3
- AI 汇总：用 GLM-4-Flash（智谱免费模型，用户 key `656d...`），沙箱真实冒烟
- 食物库数据：GitHub 拉取 Sanotsu 完整版，增强 importer 清洗脏数据

### 5. 沙箱不可验证项（需真机）

| 项 | 原因 | 真机验证方式 |
|---|---|---|
| connectivity_plus 真实网络切换监听 | 平台插件，沙箱无网络硬件 | 真机开关飞行模式，观察 pending 自动回补 |
| image_picker 相机/相册 | 平台插件 | 真机拍照选图 |
| fl_chart 实际渲染效果 | 需图形界面 | 真机查看折线图 |
| share_plus 分享面板 | 平台插件 | 真机点导出看分享面板 |

> 沙箱可验证：全部业务逻辑（DB 读写 / Provider 调用 / 队列重试 / 导出导入 / GLM 真实 API）。唯一不可验证：平台插件的真实触发。

### 6. 实施中发现的计划偏差（实施时回写）

> 实施过程中每发现一个偏差，在此记录：Issue 编号 + 根因 + 修复 + 核实来源。格式同 Sprint 1 Self-Review 第 8 节。

（实施时填写）

---

## 执行交接

**实施顺序：** T0 → T8 → T9 → T10 → T11 → T12 → T13 → T14 → 端到端测试

**每个 Task 完成后必须：**
1. `flutter analyze` → 0 issues
2. 该 Task 的测试全过
3. 发现计划偏差 → 当场修复 + 回写 Self-Review 第 5 节

**真实 API 冒烟（仅 T12）：**
```bash
flutter test test/smoke/glm_flash_smoke_test.dart \
  --dart-define=GLM_API_KEY=YOUR_GLM_API_KEY
```

**Sprint 2 完成标准（全部满足才算完成）：**
- [ ] T0-T14 全部实施，flutter analyze 0 issues
- [ ] 全量测试通过（Sprint 1 回归 + Sprint 2 新增）
- [ ] GLM-4-Flash 真实冒烟通过
- [ ] 端到端集成测试通过
- [ ] Self-Review 第 5 节回写完毕

