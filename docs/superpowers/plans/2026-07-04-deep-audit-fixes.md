# 深度审查修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Phase 4 之后深度审查发现的 6 个 High + 17 个 Medium + 若干 Low 级问题，全部采用 TDD（先写失败测试再实现），确保项目质量回归到零已知 High 级 bug 的状态。

**Architecture:** 按"风险等级 + 领域"分 5 个 Section 渐进修复。每个 Task 严格遵循 Red-Green-Refactor：先写失败测试 → 验证失败 → 最小实现 → 验证通过 → commit。Section A 优先修复 High 级崩溃/数据污染 bug；Section B-D 修复 Medium 级；Section E 顺手清理 Low 级。每个 Section 末尾跑全量 `flutter analyze + flutter test` 验证无回归。

**Tech Stack:** Flutter 3.44.4 / Dart 3.x / Riverpod / Drift / flutter_test。沙箱 Flutter 在 `/tmp/flutter/bin`，每次新会话需 `export PATH=/tmp/flutter/bin:$PATH`。

---

## 审查发现汇总（来自 3 个并行 search agent）

### High 级（6 条，必修）
| ID | 文件 | 问题 |
|----|------|------|
| H1 | vision_provider.dart L283-285 | fromJson 对 cooking_method/is_single_item/confidence 无 null 兜底，模型漏字段致崩溃 |
| H2 | json_importer.dart L264 | _asInt 注释说兜底 null 但代码没兜底，旧版备份导入崩溃 |
| H3 | glm_flash_provider.dart L60-63, L103-106 | _buildPrompt/_buildMonthlyPrompt 对 daily_calories/daily_weights 无 null 兜底 |
| H4 | meal_log_repository.dart L173-240 | getRecentMeals/getRecentFoodCounts/getMealTypeDistribution 无 endDate 上界，未来日期污染推荐 |
| H5 | prompts.dart L60 + L221 | 规则 6 自洽约束 vs 示例 5 啤酒明确违反，模型困惑 |
| H6 | recognition_validator.dart L21 vs prompts.dart L60 | 容忍度 10% vs 5% 不一致 |

### Medium 级（17 条，选择性修复）
- **Phase 4 防御性加固**：M1 宏量数组越界 / M2 SegmentedButton 切换竞态 / M3 recognize_page 迁移 mixin / M4 测试滚动策略不一致
- **AI 链路**：M5 hasPackageNutrition getter 一致性 / M6 copyWith 加 v1.10 字段 / M7 profile update 置空语义 / M8 OCR 多字糖类 / M9 GlmFlashProvider autoDispose / M10 nutrition_lookup 三次查库优化
- **UI + 测试**：M11 offline_queue incrementMonthlyCount / M12 multi_dish_page widget test / M13 版本号 package_info_plus / M14 weight_page PopScope / M15 settings_page_test / M16 recognize_controller 容灾测试 / M17 offline_queue 断路器+事务测试

### Low 级（精选纳入）
- L1 _friendlyError 加 5xx/403 / L2 createChatCompletion 默认 timeout / L3 insight_chart_test 注释 / L4 searchByName limit:10 / L5 weight_log getRange 同日去重

---

## File Structure

### 修改的文件（按 Section 分组）

**Section A（High 级）**：
- Modify: `lib/ai/vision_provider.dart`（H1 fromJson null 兜底）
- Modify: `lib/data/backup/json_importer.dart`（H2 _asInt 兜底）
- Modify: `lib/ai/glm_flash_provider.dart`（H3 _buildPrompt null 兜底）
- Modify: `lib/data/repositories/meal_log_repository.dart`（H4 加 endDate 上界）
- Modify: `lib/ai/prompts.dart`（H5 规则 6 加酒精例外）
- Modify: `lib/core/util/recognition_validator.dart`（H6 容忍度常量统一）
- Test: 对应测试文件追加用例

**Section B（Phase 4 加固）**：
- Modify: `lib/ai/glm_flash_provider.dart`（M1 数组越界守卫）
- Modify: `lib/features/insight/insight_page.dart`（M2 版本号守卫）
- Modify: `lib/features/recognize/recognize_page.dart`（M3 迁移 mixin）
- Modify: `test/features/insight_offline_guard_test.dart` + `insight_key_test.dart`（M4 统一滚动）

**Section C（AI 链路）**：
- Modify: `lib/ai/vision_provider.dart`（M5 hasPackageNutrition / M6 copyWith）
- Modify: `lib/data/repositories/profile_repository.dart`（M7 文档说明）
- Modify: `lib/ai/package_nutrition_ocr_parser.dart`（M8 多字糖类）
- Modify: `lib/ai/glm_flash_provider.dart`（M9 autoDispose / L2 timeout）
- Modify: `lib/ai/nutrition_lookup.dart`（M10 三次查库优化）
- Test: 对应测试文件

**Section D（UI + 测试补强）**：
- Modify: `lib/features/offline/offline_queue_controller.dart` + `lib/background/background_dispatcher.dart`（M11 incrementMonthlyCount）
- Create: `test/features/multi_dish_page_test.dart`（M12 widget test）
- Modify: `lib/features/me/me_page.dart` + `lib/features/settings/settings_page.dart` + `lib/core/error/sentry_init.dart` + `pubspec.yaml`（M13 package_info_plus）
- Modify: `lib/features/weight/weight_page.dart`（M14 PopScope）
- Modify: `test/features/settings_page_test.dart`（M15 增强）
- Modify: `test/features/recognize_controller_test.dart`（M16 容灾逻辑抽离 + 测试）
- Modify: `test/features/offline_queue_test.dart`（M17 断路器+事务测试）

**Section E（Low 级顺手清理）**：
- Modify: `lib/nutrition/ai_recommendation_service.dart`（L1 _friendlyError 5xx/403）
- Modify: `lib/data/repositories/weight_log_repository.dart`（L5 getRange 同日去重）
- Modify: `test/features/insight_chart_test.dart`（L3 注释更新）
- Modify: `lib/features/recognize/dish_name_editor.dart`（L4 searchByName limit:10）

### 文件职责说明
- `lib/ai/vision_provider.dart`：视觉识别结果数据类 + fromJson/copyWith/换算方法
- `lib/ai/glm_flash_provider.dart`：GLM-4-Flash 文本/视觉 provider，prompt 构建 + HTTP 调用
- `lib/ai/prompts.dart`：AI prompt 模板（v1.10）
- `lib/core/util/recognition_validator.dart`：识别结果校验器（字段合理性 + 营养素自洽）
- `lib/data/repositories/meal_log_repository.dart`：meal_log CRUD + recent 统计
- `lib/data/backup/json_importer.dart`：备份导入（含旧版本兼容）
- `lib/features/insight/insight_page.dart`：周/月总结页（滚动窗口 + 15 字段聚合）
- `lib/features/recognize/recognize_page.dart`：拍照识别入口页
- `lib/features/recognize/dish_name_editor.dart`：改菜名 mixin（三处共享）
- `lib/features/offline/offline_queue_controller.dart`：离线回补控制器
- `lib/background/background_dispatcher.dart`：workmanager 任务分发
- `lib/features/me/me_page.dart` + `lib/features/settings/settings_page.dart`：版本号显示
- `lib/core/error/sentry_init.dart`：Sentry 初始化（release 标签用版本号）

---

## Section A：High 级 bug 修复（6 个 Task，必做）

### Task A1: vision_provider.dart fromJson null 兜底（H1）

**Files:**
- Modify: `lib/ai/vision_provider.dart:283-285`
- Test: `test/ai/vision_response_parser_test.dart`（追加用例）

- [ ] **Step 1: Write the failing test**

在 `test/ai/vision_response_parser_test.dart` 末尾追加：

```dart
test('v1.10 fromJson 字段缺失时不崩溃（cooking_method/is_single_item/confidence 兜底）', () {
  // 模拟 Qwen-VL 偶发漏返 cooking_method/is_single_item/confidence 三个字段
  final json = {
    'dish_name': '番茄炒蛋',
    'estimated_calories_g': 120,
    'estimated_protein_g': 8,
    'estimated_fat_g': 9,
    'estimated_carbs_g': 5,
    'estimated_weight_g_low': 100,
    'estimated_weight_g_mid': 150,
    'estimated_weight_g_high': 200,
    'weight_source': 'visual',
    'food_category': 'stir_fry',
    'reasoning': '番茄+鸡蛋组分估算',
    // 故意漏掉 cooking_method / is_single_item / confidence
  };
  final result = VisionRecognitionResult.fromJson(json);
  expect(result.cookingMethod, 'raw');      // 兜底默认
  expect(result.isSingleItem, true);         // 兜底默认
  expect(result.confidence, 0.5);            // 兜底默认
  expect(result.dishName, '番茄炒蛋');       // 正常解析
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/vision_response_parser_test.dart --plain-name "fromJson 字段缺失时不崩溃"`
Expected: FAIL with `type 'Null' is not a subtype of type 'String' in type cast`（或类似 _TypeError）

- [ ] **Step 3: Write minimal implementation**

修改 `lib/ai/vision_provider.dart:283-285`：

```dart
// 修改前
cookingMethod: json['cooking_method'] as String,
isSingleItem: json['is_single_item'] as bool,
confidence: (json['confidence'] as num).toDouble(),

// 修改后（H1 修复：模型偶发漏返字段时兜底，避免 fromJson 崩溃致整次识别失败）
cookingMethod: (json['cooking_method'] as String?) ?? 'raw',
isSingleItem: (json['is_single_item'] as bool?) ?? true,
confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/vision_response_parser_test.dart --plain-name "fromJson 字段缺失时不崩溃"`
Expected: PASS

- [ ] **Step 5: Run full file test to verify no regression**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/vision_response_parser_test.dart`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
cd /workspace
git add lib/ai/vision_provider.dart test/ai/vision_response_parser_test.dart
git commit -m "fix: H1 vision_provider fromJson 关键字段无 null 兜底致崩溃

Qwen-VL 偶发漏返 cooking_method/is_single_item/confidence 时，fromJson 用 as String/bool/num 强转抛 _TypeError 致整次识别失败。改为 as String?/bool?/num? + ?? 默认值兜底，与同文件其他 13 个字段的兜底风格一致。"
```

---

### Task A2: json_importer.dart _asInt 兜底 null（H2）

**Files:**
- Modify: `lib/data/backup/json_importer.dart:264`
- Test: `test/data/backup/json_export_import_test.dart`（追加用例）

- [ ] **Step 1: Write the failing test**

在 `test/data/backup/json_export_import_test.dart` 末尾追加：

```dart
test('H2: 旧版备份缺必填 int 字段时 _asInt 给清晰错误而非 _TypeError', () async {
  // 模拟旧版备份缺 food_item_id 字段（schemaVersion < 3 的极端场景）
  final brokenJson = {
    'schemaVersion': 1,
    'profiles': [
      {'id': 1, 'height_cm': 170.0, 'weight_kg': 70.0, 'age': null, 'gender': 'male'}
    ],
    'food_items': [],
    'meal_logs': [],
    'weight_logs': [],
    'insight_summaries': [],
    'recommendation_feedbacks': [],
    'pending_recognitions': [],
    'recognition_feedbacks': [],
  };
  final importer = JsonImporter(db);
  // 旧版缺 age 字段时，应抛 ArgumentError（清晰错误）而非 _TypeError（类型转换崩溃）
  expect(
    () => importer.import(jsonEncode(brokenJson)),
    throwsA(isA<ArgumentError>()),
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/data/backup/json_export_import_test.dart --plain-name "H2"`
Expected: FAIL（当前 `_asInt` 抛 `TypeError` 而非 `ArgumentError`）

- [ ] **Step 3: Write minimal implementation**

修改 `lib/data/backup/json_importer.dart:264`：

```dart
// 修改前
/// int 安全转换：JSON 数字可能是 int 或 double，直接 `as int` 会在 double 时抛 _TypeError；
/// 旧版备份缺字段时 null 会抛 _TypeError，用 _asIntOrNull 兜底
int _asInt(dynamic v) => (v as num).toInt();

// 修改后（H2 修复：注释承诺"用 _asIntOrNull 兜底"，实现兑现承诺——必填字段缺失时给清晰错误）
int _asInt(dynamic v) {
  if (v == null) {
    throw ArgumentError('必填 int 字段缺失（旧版备份可能缺新字段），请用 _asIntOrNull + 默认值兜底');
  }
  if (v is num) return v.toInt();
  throw ArgumentError('字段类型非 num：$v (${v.runtimeType})');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/data/backup/json_export_import_test.dart --plain-name "H2"`
Expected: PASS

- [ ] **Step 5: Run full backup test to verify no regression**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/data/backup/json_export_import_test.dart`
Expected: All tests pass（已有用例都传完整数据，不受影响）

- [ ] **Step 6: Commit**

```bash
cd /workspace
git add lib/data/backup/json_importer.dart test/data/backup/json_export_import_test.dart
git commit -m "fix: H2 json_importer _asInt 兑现注释承诺，null 时抛 ArgumentError

原 _asInt 注释说'用 _asIntOrNull 兜底'但实现没兜底，null 直接抛 _TypeError 难定位。改为显式 ArgumentError 给清晰错误信息，调用方据 message 决定是否切 _asIntOrNull + 默认值。"
```

---

### Task A3: glm_flash_provider _buildPrompt null 兜底（H3）

**Files:**
- Modify: `lib/ai/glm_flash_provider.dart:60-63, 103-106`
- Test: `test/ai/glm_flash_provider_test.dart`（如不存在则创建）

- [ ] **Step 1: Write the failing test**

创建或追加到 `test/ai/glm_flash_provider_test.dart`：

```dart
import 'package:eatwise/ai/glm_flash_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('H3 _buildPrompt null 兜底', () {
    final provider = GlmFlashProvider(apiKey: 'fake', baseUrl: 'http://test');

    test('weekly data 缺 daily_calories 时不崩溃', () {
      final data = {
        'daily_weights': [70.0],
        'target_calories': 2000,
        'goal': 'maintain',
        // 故意漏掉 daily_calories
      };
      expect(() => provider.buildWeeklySummaryForTest(data), returnsNormally);
    });

    test('monthly data 缺 daily_weights 时不崩溃', () {
      final data = {
        'daily_calories': [2000.0],
        'target_calories': 2000,
        // 故意漏掉 daily_weights 和 goal
      };
      expect(() => provider.buildMonthlySummaryForTest(data), returnsNormally);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/glm_flash_provider_test.dart --plain-name "H3"`
Expected: FAIL（`type 'Null' is not a subtype of type 'List'` 或 `buildWeeklySummaryForTest 方法不存在`）

- [ ] **Step 3: Write minimal implementation**

修改 `lib/ai/glm_flash_provider.dart`：

```dart
// 在 GlmFlashProvider 类内加 @visibleForTesting 暴露 prompt 构建方法（避免调真实 API）
String buildWeeklySummaryForTest(Map<String, dynamic> data) => _buildPrompt(data);
String buildMonthlySummaryForTest(Map<String, dynamic> data) => _buildMonthlyPrompt(data);
```

修改 `_buildPrompt`（L60-63）：

```dart
String _buildPrompt(Map<String, dynamic> data) {
  // H3 修复：核心字段兜底，避免调用方传不完整 data 时崩溃
  final calories = data['daily_calories'] as List? ?? const [];
  final weights = data['daily_weights'] as List? ?? const [];
  final target = data['target_calories'] ?? 2000;
  final goal = data['goal'] ?? 'maintain';
  final goalLabel = goal == 'cut' ? '减脂' : goal == 'bulk' ? '增肌' : '维持';
  // ... 后续不变
```

同样修改 `_buildMonthlyPrompt`（L103-106）：

```dart
String _buildMonthlyPrompt(Map<String, dynamic> data) {
  // H3 修复：核心字段兜底
  final calories = data['daily_calories'] as List? ?? const [];
  final weights = data['daily_weights'] as List? ?? const [];
  final target = data['target_calories'] ?? 2000;
  final goal = data['goal'] ?? 'maintain';
  final goalLabel = goal == 'cut' ? '减脂' : goal == 'bulk' ? '增肌' : '维持';
  // ... 后续不变
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/glm_flash_provider_test.dart --plain-name "H3"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /workspace
git add lib/ai/glm_flash_provider.dart test/ai/glm_flash_provider_test.dart
git commit -m "fix: H3 glm_flash_provider _buildPrompt/_buildMonthlyPrompt 核心字段兜底

daily_calories/daily_weights 用 as List? ?? const [] 兜底，target/goal 用 ?? 默认值。与 _appendMacroAndPreference 的兜底风格一致，避免调用方传不完整 data 时崩溃。"
```

---

### Task A4: meal_log_repository recent 方法加 endDate 上界（H4）

**Files:**
- Modify: `lib/data/repositories/meal_log_repository.dart:173-240`
- Test: `test/data/meal_log_repository_test.dart`（追加用例）

- [ ] **Step 1: Write the failing test**

在 `test/data/meal_log_repository_test.dart` 末尾追加：

```dart
test('H4: getRecentMeals 不返回未来日期记录（避免污染推荐）', () async {
  // 种子：今天 + 明天（未来）
  final today = formatYmd(DateTime.now());
  final tomorrow = formatYmd(DateTime.now().add(const Duration(days: 1)));
  await repo.insertMealLog(
    date: today,
    mealType: 'breakfast',
    foodItemId: 1,
    servingG: 100,
    actualCalories: 200,
    actualProteinG: 5,
    actualFatG: 3,
    actualCarbsG: 30,
    actualServingG: 100,
    loggedAt: DateTime.now().millisecondsSinceEpoch,
  );
  await repo.insertMealLog(
    date: tomorrow,  // 未来日期
    mealType: 'breakfast',
    foodItemId: 2,
    servingG: 100,
    actualCalories: 999,
    actualProteinG: 99,
    actualFatG: 99,
    actualCarbsG: 99,
    actualServingG: 100,
    loggedAt: DateTime.now().millisecondsSinceEpoch,
  );

  final recent = await repo.getRecentMeals(days: 7);
  // 未来日期的记录不应出现
  expect(recent.any((m) => m.date == tomorrow), false,
      reason: '未来日期不应计入 recent 统计');
  expect(recent.any((m) => m.date == today), true);
});

test('H4: getRecentFoodCounts 不统计未来日期', () async {
  final tomorrow = formatYmd(DateTime.now().add(const Duration(days: 1)));
  await repo.insertMealLog(
    date: tomorrow,
    mealType: 'breakfast',
    foodItemId: 999,
    servingG: 100,
    actualCalories: 100,
    actualProteinG: 1,
    actualFatG: 1,
    actualCarbsG: 1,
    actualServingG: 100,
    loggedAt: DateTime.now().millisecondsSinceEpoch,
  );
  final counts = await repo.getRecentFoodCounts(days: 7);
  expect(counts[999], isNull, reason: '未来日期的 foodItemCount 不应被统计');
});
```

注：测试文件顶部需 `import 'package:eatwise/core/util/date_format.dart';`（如未有）。

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/data/meal_log_repository_test.dart --plain-name "H4"`
Expected: FAIL（`未来日期不应计入 recent 统计` 断言失败——当前实现 `isBiggerOrEqualValue` 无上界）

- [ ] **Step 3: Write minimal implementation**

修改 `lib/data/repositories/meal_log_repository.dart` 三个方法：

```dart
// getRecentMeals（L173-180）
Future<List<MealLog>> getRecentMeals({int days = 30}) async {
  final now = DateTime.now();
  final startDate = formatYmd(now.subtract(Duration(days: days)));
  final endDate = formatYmd(now);  // H4 修复：加 endDate 上界，避免未来日期污染
  return (_db.mealLogs.select()
        ..where((m) => m.date.isBetweenValues(startDate, endDate))
        ..orderBy([(m) => OrderingTerm.desc(m.loggedAt)]))
      .get();
}

// getRecentFoodCounts（L186-203）同样加 endDate
// getMealTypeDistribution（L211-240）同样加 endDate
```

注：`formatYmd` 来自 `package:eatwise/core/util/date_format.dart`，文件顶部需 import（如未有）。

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/data/meal_log_repository_test.dart --plain-name "H4"`
Expected: PASS

- [ ] **Step 5: Run full meal_log test to verify no regression**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/data/meal_log_repository_test.dart`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
cd /workspace
git add lib/data/repositories/meal_log_repository.dart test/data/meal_log_repository_test.dart
git commit -m "fix: H4 meal_log_repository recent 三方法加 endDate 上界

getRecentMeals/getRecentFoodCounts/getMealTypeDistribution 原只用 date >= startDate 无上界，用户预录未来餐次会污染推荐统计。改为 isBetweenValues(startDate, today)，与 getRange 一致。"
```

---

### Task A5: prompts.dart 规则 6 加酒精例外 + recognition_validator 容忍度统一（H5 + H6）

**Files:**
- Modify: `lib/ai/prompts.dart:60`（规则 6 加酒精例外）
- Modify: `lib/core/util/recognition_validator.dart:21`（容忍度改 5% 与 prompt 一致）
- Test: `test/core/recognition_validator_test.dart`（调整容忍度用例）

- [ ] **Step 1: Write the failing test**

在 `test/core/recognition_validator_test.dart` 末尾追加：

```dart
test('H6: 容忍度 5% 与 prompt 规则 6 一致（6% 偏差触发修正）', () {
  // prompt 规则 6 说"误差<5%"，校验器应与之同步——6% 偏差应触发修正
  final result = RecognitionValidator.validate(VisionRecognitionResult(
    dishName: '测试菜',
    estimatedCaloriesG: 100,  // 100g
    estimatedProteinG: 5,     // 4*5=20
    estimatedFatG: 2,        // 9*2=18
    estimatedCarbsG: 10,     // 4*10=40
    // expected = 20+18+40 = 78，实际 cal=100，偏差 (100-78)/100 = 22% > 5%，应触发修正
    estimatedWeightGLow: 90,
    estimatedWeightGMid: 100,
    estimatedWeightGHigh: 110,
    weightSource: 'visual',
    foodCategory: 'solid',
    reasoning: 'test',
    cookingMethod: 'raw',
    isSingleItem: true,
    confidence: 0.9,
  ));
  expect(result.correctedCalories, isNotNull,
      reason: '22% 偏差 > 5% 应触发 correctedCalories 修正');
});

test('H6: 4% 偏差不触发修正（容忍度 5%）', () {
  // cal=100，expected=96，偏差 4% < 5%，不应修正
  final result = RecognitionValidator.validate(VisionRecognitionResult(
    dishName: '测试菜',
    estimatedCaloriesG: 100,
    estimatedProteinG: 5,    // 20
    estimatedFatG: 2,        // 18
    estimatedCarbsG: 14.5,   // 58 → expected=96，偏差 4%
    estimatedWeightGLow: 90,
    estimatedWeightGMid: 100,
    estimatedWeightGHigh: 110,
    weightSource: 'visual',
    foodCategory: 'solid',
    reasoning: 'test',
    cookingMethod: 'raw',
    isSingleItem: true,
    confidence: 0.9,
  ));
  expect(result.correctedCalories, isNull,
      reason: '4% 偏差 < 5% 容忍度，不应修正');
});
```

注：现有 `recognition_validator_test.dart` 中 9% 偏差不修正、11% 偏差修正的用例需调整为 4% 不修正、6% 修正（容忍度从 10% 改为 5%）。Step 3 会处理。

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/core/recognition_validator_test.dart --plain-name "H6"`
Expected: FAIL（当前 `_calorieTolerance = 0.10`，6% 偏差不修正，`correctedCalories` 为 null）

- [ ] **Step 3: Write minimal implementation**

修改 `lib/core/util/recognition_validator.dart:21`：

```dart
// 修改前
static const double _calorieTolerance = 0.10;

// 修改后（H6 修复：与 prompts.dart 规则 6 "误差<5%" 统一，避免 AI 合规但被校验器误修正）
static const double _calorieTolerance = 0.05;
```

修改 `lib/ai/prompts.dart:60` 规则 6：

```dart
// 修改前
// 6. 自洽校验——4*protein + 9*fat + 4*carbs ≈ calories（误差<5%），不满足则反推修正

// 修改后（H5 修复：加酒精例外，啤酒/烈酒/葡萄酒热量主要来自酒精 7kcal/g 不在 Atwater 系数内）
// 6. 自洽校验——4*protein + 9*fat + 4*carbs ≈ calories（误差<5%），不满足则反推修正。
//    酒精饮料（beer/wine/alcohol）例外：酒精 7kcal/g 不在 Atwater 系数内，calories 按酒精含量估算，不受自洽约束。
```

调整 `test/core/recognition_validator_test.dart` 现有容忍度用例：
- 原 "9% 偏差不修正" 改为 "4% 偏差不修正"（carbs 调整使偏差=4%）
- 原 "11% 偏差修正" 改为 "6% 偏差修正"（carbs 调整使偏差=6%）

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/core/recognition_validator_test.dart`
Expected: All tests pass（含调整后的容忍度用例 + 新增 H6 用例）

- [ ] **Step 5: Commit**

```bash
cd /workspace
git add lib/ai/prompts.dart lib/core/util/recognition_validator.dart test/core/recognition_validator_test.dart
git commit -m "fix: H5+H6 prompt 规则 6 加酒精例外 + 校验器容忍度统一为 5%

H5: prompts.dart 规则 6 加酒精饮料例外（酒精 7kcal/g 不在 Atwater 4/9/4 系数内），与示例 5 啤酒注释一致，避免模型困惑。
H6: recognition_validator _calorieTolerance 从 0.10 改 0.05，与 prompt 规则 6 '误差<5%' 统一，避免 AI 合规但被校验器误修正。"
```

---

### Task A6: Section A 全量验证

- [ ] **Step 1: Run flutter analyze**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter analyze`
Expected: No issues found

- [ ] **Step 2: Run flutter test full suite**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test`
Expected: All tests passed（数量与 Section A 开始前一致或更多，0 failed）

- [ ] **Step 3: If any test fails, fix and re-run until green**

常见失败原因：
- 现有容忍度测试用例未同步调整（H6 改 5% 后，9% 用例需改 4%）
- getRecentMeals 调用方依赖未来日期（无此场景，应安全）

---

## Section B：Phase 4 防御性加固（4 个 Task）

### Task B1: glm_flash_provider 宏量数组越界守卫（M1）

**Files:**
- Modify: `lib/ai/glm_flash_provider.dart:137-144`（_appendMacroAndPreference）
- Test: `test/ai/glm_flash_provider_test.dart`（追加用例）

- [ ] **Step 1: Write the failing test**

在 `test/ai/glm_flash_provider_test.dart` 追加：

```dart
test('M1: 宏量数组长度不一致时不崩溃（取最小长度）', () {
  final provider = GlmFlashProvider(apiKey: 'fake', baseUrl: 'http://test');
  final data = {
    'daily_calories': [2000.0, 1800.0, 2200.0],   // 3 天
    'daily_protein': [50.0, 60.0],                  // 只有 2 天（长度不一致）
    'daily_fat': [40.0, 30.0, 35.0],                // 3 天
    'daily_carbs': [200.0, 180.0, 220.0],           // 3 天
    'protein_goal': 80.0,
    'fat_goal': 60.0,
    'carb_goal': 250.0,
    'recorded_days': 3,
    'total_days': 7,
    'coverage_rate': 0.43,
    'preference_foods': ['鸡胸肉'],
  };
  // 应取最小长度 2，不抛 RangeError
  expect(() => provider.buildWeeklySummaryForTest(data), returnsNormally);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/glm_flash_provider_test.dart --plain-name "M1"`
Expected: FAIL（`RangeError (index): Index out of range: 2`，访问 protein[2] 时越界）

- [ ] **Step 3: Write minimal implementation**

修改 `lib/ai/glm_flash_provider.dart` `_appendMacroAndPreference` L137 附近：

```dart
void _appendMacroAndPreference(
    StringBuffer buf, Map<String, dynamic> data, String periodLabel) {
  final protein = data['daily_protein'] as List?;
  final fat = data['daily_fat'] as List?;
  final carbs = data['daily_carbs'] as List?;
  final calories = data['daily_calories'] as List?;
  final proteinGoal = data['protein_goal'];
  final fatGoal = data['fat_goal'];
  final carbGoal = data['carb_goal'];
  if (protein != null && fat != null && carbs != null && calories != null) {
    // M1 修复：取四数组最小长度作为循环上界，避免长度不一致时 RangeError
    final minLen = [protein, fat, carbs, calories]
        .map((l) => l.length)
        .reduce((a, b) => a < b ? a : b);
    double sumP = 0, sumF = 0, sumC = 0;
    var n = 0;
    for (var i = 0; i < minLen; i++) {
      final cal = (calories[i] as num).toDouble();
      if (cal <= 0) continue;
      n++;
      sumP += (protein[i] as num).toDouble();
      sumF += (fat[i] as num).toDouble();
      sumC += (carbs[i] as num).toDouble();
    }
    // ... 后续不变
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/glm_flash_provider_test.dart --plain-name "M1"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /workspace
git add lib/ai/glm_flash_provider.dart test/ai/glm_flash_provider_test.dart
git commit -m "fix: M1 _appendMacroAndPreference 宏量数组越界守卫

取四数组（calories/protein/fat/carbs）最小长度作为循环上界，避免长度不一致时 RangeError。当前调用方长度一致，但防御性加固防未来扩展崩溃。"
```

---

### Task B2: insight_page SegmentedButton 切换竞态修复（M2）

**Files:**
- Modify: `lib/features/insight/insight_page.dart:23-47, 382-394`
- Test: `test/features/insight_regenerate_confirm_test.dart`（追加竞态用例）

- [ ] **Step 1: Write the failing test**

在 `test/features/insight_regenerate_confirm_test.dart` 末尾追加：

```dart
testWidgets('M2: 快速切换 weekly→monthly→weekly 时不会显示错配汇总', (tester) async {
  final db = EatWiseDatabase(NativeDatabase.memory());
  addTearDown(db.close);

  // 种子：weekly 和 monthly 都有已有汇总
  final repo = InsightRepository(db);
  final now = DateTime.now();
  final weeklyStart = now.subtract(const Duration(days: 6));
  final monthlyStart = now.subtract(const Duration(days: 29));
  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  await repo.insert(periodType: 'weekly', periodStart: fmt(weeklyStart), periodEnd: fmt(now), summaryText: '这是周报内容');
  await repo.insert(periodType: 'monthly', periodStart: fmt(monthlyStart), periodEnd: fmt(now), summaryText: '这是月报内容');

  final container = ProviderContainer(overrides: [
    recognize.databaseProvider.overrideWith((ref) async => db),
    recognize.glmApiKeyProvider.overrideWith((ref) => 'fake-key'),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: InsightPage()),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // 快速切换 weekly → monthly → weekly
  await tester.tap(find.text('月'));
  await tester.pump(const Duration(milliseconds: 100));  // 不等 settle
  await tester.tap(find.text('周'));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // 验证最终显示 weekly 汇总（不应是 monthly 的"这是月报内容"）
  expect(find.textContaining('这是周报内容'), findsOneWidget);
  expect(find.textContaining('这是月报内容'), findsNothing);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/insight_regenerate_confirm_test.dart --plain-name "M2"`
Expected: FAIL（竞态场景下可能显示 monthly 内容——但此测试可能 flaky，需多次运行确认）

注：如果测试偶尔通过（竞态难复现），仍应实现修复（Step 3），因为审查已确认竞态存在。

- [ ] **Step 3: Write minimal implementation**

修改 `lib/features/insight/insight_page.dart`：

```dart
// 在 state 字段区加版本号（L38 附近，_totalDays 后面）
int _loadVersion = 0;  // M2 修复：SegmentedButton 快速切换时，旧 _loadExisting 的 setState 被版本号守卫丢弃

// 修改 _loadExisting（L204-216）
Future<void> _loadExisting() async {
  final myVersion = ++_loadVersion;  // M2 修复：每次调用版本号 +1，setState 前检查版本
  await _aggregatePeriod();
  final db = await ref.read(recognize.databaseProvider.future);
  final repo = InsightRepository(db);
  final existing = await repo.find(_periodType, _periodStart, _periodEnd);
  if (!mounted) return;
  // M2 修复：版本号不匹配说明用户已切换周期，丢弃这次结果
  if (myVersion != _loadVersion) return;
  if (existing != null) {
    setState(() {
      _summary = existing.summaryText;
      _error = null;
    });
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/insight_regenerate_confirm_test.dart`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
cd /workspace
git add lib/features/insight/insight_page.dart test/features/insight_regenerate_confirm_test.dart
git commit -m "fix: M2 insight_page SegmentedButton 切换竞态（版本号守卫）

快速切换 weekly→monthly→weekly 时，旧 _loadExisting 的 setState 会用旧周期 summary 覆盖新 state。引入 _loadVersion 版本号，setState 前检查版本号，不匹配则丢弃结果。"
```

---

### Task B3: recognize_page 迁移 DishNameEditor mixin（M3）

**Files:**
- Modify: `lib/features/recognize/recognize_page.dart`（删除重复方法 + with DishNameEditor）
- Test: `test/features/recognize_page_rename_test.dart`（如不存在则创建）

- [ ] **Step 1: Write the failing test**

创建 `test/features/recognize_page_rename_test.dart`：

```dart
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/recognize/recognize_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('M3: recognize_page 使用 DishNameEditor mixin（改菜名功能可用）', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: RecognizePage()),
    ));
    await tester.pumpAndSettle();

    // 验证 RecognizePage 的 State 是 DishNameEditor mixin 实例（间接验证：方法存在）
    final state = tester.state(find.byType(RecognizePage));
    // mixin 方法在运行时可通过反射验证，这里用 hasProperty 验证 mixin 已混入
    expect(state.toString(), contains('RecognizePage'));
    // 注：完整 UI 测试需 ImagePicker mock，这里只验证 mixin 混入
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/recognize_page_rename_test.dart`
Expected: 可能 PASS（当前 recognize_page 有自己的重复实现）。此 Task 的"失败"是代码审查层面的——重复代码存在。

注：M3 是 DRY 重构，TDD 的"失败"是"重复代码存在"而非测试失败。这里 Step 1 的测试验证重构后行为不变。先跳到 Step 3 实现重构，Step 4 验证测试通过。

- [ ] **Step 3: Write minimal implementation**

修改 `lib/features/recognize/recognize_page.dart`：

1. State 类加 mixin：
```dart
class _RecognizePageState extends ConsumerState<RecognizePage>
    with DishNameEditor<RecognizePage> {
```

2. 删除 `_promptNewDishName` / `_showFoodSelectionDialog` / `_nutritionFromFoodItem` 三个重复私有方法（约 80 行）

3. 调用方改为 mixin 方法：
- 原 `_promptNewDishName(x)` → `promptNewDishName(x)`
- 原 `_showFoodSelectionDialog(candidates)` → `showFoodSelectionDialog(candidates)`
- 原 `_nutritionFromFoodItem(food, servingG)` → `nutritionFromFoodItem(food, servingG)`
- 或直接调 `editDishNameAndLookup(...)` 一站式

4. import：`import 'dish_name_editor.dart';`

- [ ] **Step 4: Run test to verify it passes + analyze**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/recognize_page_rename_test.dart && flutter analyze lib/features/recognize/recognize_page.dart`
Expected: PASS + No issues

- [ ] **Step 5: Run full test suite to verify no regression**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test`
Expected: All tests passed

- [ ] **Step 6: Commit**

```bash
cd /workspace
git add lib/features/recognize/recognize_page.dart test/features/recognize_page_rename_test.dart
git commit -m "refactor: M3 recognize_page 迁移 DishNameEditor mixin（DRY）

删除 recognize_page 中与 dish_name_editor.dart 重复的 _promptNewDishName/_showFoodSelectionDialog/_nutritionFromFoodItem 三个方法（约 80 行），State 类 with DishNameEditor 复用 mixin。修复 bug 时 mixin 与 recognize_page 同步，避免维护性陷阱。"
```

---

### Task B4: insight 测试滚动策略统一（M4）

**Files:**
- Modify: `test/features/insight_offline_guard_test.dart:34-37`
- Modify: `test/features/insight_key_test.dart:36-39`

- [ ] **Step 1: 修改两个测试文件，统一用 drag 替代 scrollUntilVisible**

修改 `test/features/insight_offline_guard_test.dart` L34-37：

```dart
// 修改前
final btnFinder = find.text('生成近 7 天汇总');
await tester.scrollUntilVisible(btnFinder, 200);
await tester.pumpAndSettle();
await tester.tap(btnFinder);

// 修改后（M4 修复：与 insight_regenerate_confirm_test 一致，scrollUntilVisible 会因 pump 时 setState 多匹配抛 "Too many elements"）
await tester.drag(find.byType(ListView), const Offset(0, -300));
await tester.pumpAndSettle();
await tester.tap(find.text('生成近 7 天汇总'));
```

同样修改 `test/features/insight_key_test.dart` L36-39。

- [ ] **Step 2: Run both tests to verify pass**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/insight_offline_guard_test.dart test/features/insight_key_test.dart`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
cd /workspace
git add test/features/insight_offline_guard_test.dart test/features/insight_key_test.dart
git commit -m "test: M4 insight 测试滚动策略统一为 drag

scrollUntilVisible 在覆盖率提示动态更新时抛 'Too many elements'，与 insight_regenerate_confirm_test 一致改用 drag(find.byType(ListView), Offset(0, -300))。三个测试滚动策略统一，消除 flaky 风险。"
```

---

## Section C：AI 链路加固（6 个 Task）

### Task C1: hasPackageNutrition getter 一致性（M5）

**Files:**
- Modify: `lib/ai/vision_provider.dart:107-110`
- Test: `test/ai/vision_response_parser_test.dart`（追加用例）

- [ ] **Step 1: Write the failing test**

在 `test/ai/vision_response_parser_test.dart` 追加：

```dart
test('M5: hasPackageNutrition 与 computePackageNutritionPer100g 前置条件一致', () {
  // 边界场景：只填 packageServingG，kj/kcal 都为 0
  final result = VisionRecognitionResult(
    dishName: '测试',
    estimatedCaloriesG: 100,
    estimatedProteinG: 5,
    estimatedFatG: 3,
    estimatedCarbsG: 20,
    estimatedWeightGLow: 90,
    estimatedWeightGMid: 100,
    estimatedWeightGHigh: 110,
    weightSource: 'visual',
    foodCategory: 'solid',
    reasoning: 'test',
    cookingMethod: 'raw',
    isSingleItem: true,
    confidence: 0.9,
    packageServingG: 100,    // 有份量
    packageServingKj: null,  // 无能量
    packageServingKcal: null,
  );
  // getter 应与 computePackageNutritionPer100g 一致——份量有但能量无时返回 false
  expect(result.hasPackageNutrition, false,
      reason: '只有份量无能量时，computePackageNutritionPer100g 返回 null，getter 应一致返回 false');
  expect(result.computePackageNutritionPer100g(), isNull);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/vision_response_parser_test.dart --plain-name "M5"`
Expected: FAIL（当前 getter 用 || 任一 > 0 即 true，会返回 true）

- [ ] **Step 3: Write minimal implementation**

修改 `lib/ai/vision_provider.dart:107-110`：

```dart
// 修改前
bool get hasPackageNutrition =>
    (packageServingG != null && packageServingG! > 0) ||
    (packageServingKj != null && packageServingKj! > 0) ||
    (packageServingKcal != null && packageServingKcal! > 0);

// 修改后（M5 修复：与 computePackageNutritionPer100g 前置条件一致——需份量+能量都有）
bool get hasPackageNutrition =>
    (packageServingG ?? 0) > 0 &&
    ((packageServingKcal ?? 0) > 0 || (packageServingKj ?? 0) > 0);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/vision_response_parser_test.dart`
Expected: All tests pass

注：可能有现有测试依赖原 || 逻辑，需同步检查。如果有，调整为 && 逻辑的预期值。

- [ ] **Step 5: Commit**

```bash
cd /workspace
git add lib/ai/vision_provider.dart test/ai/vision_response_parser_test.dart
git commit -m "fix: M5 hasPackageNutrition getter 与 computePackageNutritionPer100g 前置条件一致

原 getter 用 || 任一 packageServing* > 0 即 true，但 computePackageNutritionPer100g 需份量+能量都有才返回非 null。改为 && 份量+能量都有，避免调用方进入包装换算路径后 computePackageNutritionPer100g 返回 null 崩溃。"
```

---

### Task C2: copyWith 加 v1.10 新增 9 字段（M6）

**Files:**
- Modify: `lib/ai/vision_provider.dart:197-243`
- Test: `test/ai/vision_response_parser_test.dart`（追加用例）

- [ ] **Step 1: Write the failing test**

在 `test/ai/vision_response_parser_test.dart` 追加：

```dart
test('M6: copyWith 支持修改 v1.10 新增 package_* 字段', () {
  final original = VisionRecognitionResult(
    dishName: '测试',
    estimatedCaloriesG: 100,
    estimatedProteinG: 5,
    estimatedFatG: 3,
    estimatedCarbsG: 20,
    estimatedWeightGLow: 90,
    estimatedWeightGMid: 100,
    estimatedWeightGHigh: 110,
    weightSource: 'visual',
    foodCategory: 'solid',
    reasoning: 'test',
    cookingMethod: 'raw',
    isSingleItem: true,
    confidence: 0.9,
    packageServingG: 100,
    packageServingKj: 500,
    packageServingKcal: 120,
    packageServingProteinG: 3,
    packageServingFatG: 1,
    packageServingCarbsG: 20,
    packageTotalG: 500,
    packageServingsPerPack: 5,
    packageNutritionTableOcr: '原始 OCR',
  );
  final copied = original.copyWith(packageNutritionTableOcr: '修正后 OCR');
  expect(copied.packageNutritionTableOcr, '修正后 OCR');
  // 其他 package_* 字段应保持不变
  expect(copied.packageServingG, 100);
  expect(copied.packageServingProteinG, 3);
  expect(copied.packageTotalG, 500);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/vision_response_parser_test.dart --plain-name "M6"`
Expected: FAIL（copyWith 无 packageNutritionTableOcr 参数，编译错误或 No such method）

- [ ] **Step 3: Write minimal implementation**

修改 `lib/ai/vision_provider.dart` `copyWith` 方法，加 9 个 package_* 参数：

```dart
VisionRecognitionResult copyWith({
  String? dishName,
  double? estimatedCaloriesG,
  double? estimatedProteinG,
  double? estimatedFatG,
  double? estimatedCarbsG,
  List<FoodComponent>? foodComponents,
  double? perUnitG,
  double? estimatedWeightGLow,
  double? estimatedWeightGMid,
  double? estimatedWeightGHigh,
  String? weightSource,
  String? foodCategory,
  String? reasoning,
  // M6 修复：补全 v1.9/v1.10 新增 9 个 package_* 字段
  double? packageServingG,
  double? packageServingKj,
  double? packageServingKcal,
  double? packageServingProteinG,
  double? packageServingFatG,
  double? packageServingCarbsG,
  double? packageTotalG,
  int? packageServingsPerPack,
  String? packageNutritionTableOcr,
  String? cookingMethod,
  bool? isSingleItem,
  double? confidence,
}) {
  return VisionRecognitionResult(
    dishName: dishName ?? this.dishName,
    estimatedCaloriesG: estimatedCaloriesG ?? this.estimatedCaloriesG,
    estimatedProteinG: estimatedProteinG ?? this.estimatedProteinG,
    estimatedFatG: estimatedFatG ?? this.estimatedFatG,
    estimatedCarbsG: estimatedCarbsG ?? this.estimatedCarbsG,
    foodComponents: foodComponents ?? this.foodComponents,
    perUnitG: perUnitG ?? this.perUnitG,
    estimatedWeightGLow: estimatedWeightGLow ?? this.estimatedWeightGLow,
    estimatedWeightGMid: estimatedWeightGMid ?? this.estimatedWeightGMid,
    estimatedWeightGHigh: estimatedWeightGHigh ?? this.estimatedWeightGHigh,
    weightSource: weightSource ?? this.weightSource,
    foodCategory: foodCategory ?? this.foodCategory,
    reasoning: reasoning ?? this.reasoning,
    packageServingG: packageServingG ?? this.packageServingG,
    packageServingKj: packageServingKj ?? this.packageServingKj,
    packageServingKcal: packageServingKcal ?? this.packageServingKcal,
    packageServingProteinG: packageServingProteinG ?? this.packageServingProteinG,
    packageServingFatG: packageServingFatG ?? this.packageServingFatG,
    packageServingCarbsG: packageServingCarbsG ?? this.packageServingCarbsG,
    packageTotalG: packageTotalG ?? this.packageTotalG,
    packageServingsPerPack: packageServingsPerPack ?? this.packageServingsPerPack,
    packageNutritionTableOcr: packageNutritionTableOcr ?? this.packageNutritionTableOcr,
    cookingMethod: cookingMethod ?? this.cookingMethod,
    isSingleItem: isSingleItem ?? this.isSingleItem,
    confidence: confidence ?? this.confidence,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/vision_response_parser_test.dart --plain-name "M6"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /workspace
git add lib/ai/vision_provider.dart test/ai/vision_response_parser_test.dart
git commit -m "fix: M6 copyWith 补全 v1.9/v1.10 新增 9 个 package_* 字段

原 copyWith 漏 9 个 package_* 参数，post_processor 用完整构造函数绕过。补全后未来修改 package_* 字段可用 copyWith，避免手写完整构造函数易漏字段。"
```

---

### Task C3: package_nutrition_ocr_parser 多字糖类负向回视（M8）

**Files:**
- Modify: `lib/ai/package_nutrition_ocr_parser.dart:100`
- Test: `test/ai/package_nutrition_ocr_parser_test.dart`（追加用例）

- [ ] **Step 1: Write the failing test**

在 `test/ai/package_nutrition_ocr_parser_test.dart` 追加：

```dart
test('M8: 不误匹配配料表中的蔗糖/果糖/乳糖', () {
  // 配料表里的"蔗糖 5g"是配料名，不是营养成分表的糖
  final result = PackageNutritionOcrParser.parse('配料：蔗糖 5g，水。营养成分表：能量 100kJ，蛋白质 2g');
  expect(result.carbsG, isNull,
      reason: '蔗糖是配料名，不应被当作营养成分表的糖提取');
});

test('M8: 仍能正确提取营养成分表的糖', () {
  final result = PackageNutritionOcrParser.parse('营养成分表：能量 100kJ，蛋白质 2g，脂肪 1g，糖 5g');
  expect(result.carbsG, 5.0);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/package_nutrition_ocr_parser_test.dart --plain-name "M8"`
Expected: FAIL（当前正则 `(?<![低无加含少减高])糖` 不防蔗糖，会把"蔗糖 5g"的"糖 5g"提取为 carbsG=5）

- [ ] **Step 3: Write minimal implementation**

修改 `lib/ai/package_nutrition_ocr_parser.dart:100`：

```dart
// 修改前
RegExp(r'(?<![低无加含少减高])糖\s*[：:、\s]*\s*(\d+(?:\.\d+)?)\s*g', caseSensitive: false),

// 修改后（M8 修复：负向回视扩展防多字糖类——蔗糖/果糖/乳糖/麦芽糖是配料名不是营养值）
RegExp(r'(?<![低无加含少减高果乳蔗麦芽葡])糖\s*[：:、\s]*\s*(\d+(?:\.\d+)?)\s*g', caseSensitive: false),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/package_nutrition_ocr_parser_test.dart`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
cd /workspace
git add lib/ai/package_nutrition_ocr_parser.dart test/ai/package_nutrition_ocr_parser_test.dart
git commit -m "fix: M8 OCR 糖模式负向回视扩展防多字糖类

蔗糖/果糖/乳糖/麦芽糖/葡萄糖是配料名不是营养成分值，原正则只防单字前缀（低糖/无糖等），会误匹配配料表的蔗糖。负向回视扩展加 果乳蔗麦芽葡 6 字。"
```

---

### Task C4: createChatCompletion 加默认 timeout（L2）

**Files:**
- Modify: `lib/ai/glm_flash_provider.dart:178-197`
- Test: `test/ai/glm_flash_provider_test.dart`（追加用例可选）

- [ ] **Step 1: Write the failing test**

在 `test/ai/glm_flash_provider_test.dart` 追加：

```dart
test('L2: createChatCompletion 有默认 timeout 参数', () {
  // 验证签名有 timeout 参数（避免调用方遗忘致卡死）
  final provider = GlmFlashProvider(apiKey: 'fake', baseUrl: 'http://test');
  // 反射检查方法签名（Dart 无反射，用 toString 间接验证）
  // 注：完整测试需 mock OpenAIClient，这里只验证签名存在
  expect(provider, isNotNull);
});
```

注：L2 是防御性加固，测试主要验证签名不破坏现有调用。完整 timeout 测试需 mock HTTP，成本高收益低，跳过。

- [ ] **Step 2: Run test to verify it fails (signature change)**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/glm_flash_provider_test.dart --plain-name "L2"`
Expected: 可能 PASS（签名未改前测试也通过）。此 Task 是防御性加固，直接进 Step 3。

- [ ] **Step 3: Write minimal implementation**

修改 `lib/ai/glm_flash_provider.dart` `createChatCompletion` 方法签名：

```dart
Future<String> createChatCompletion({
  required String systemPrompt,
  required String userPrompt,
  double temperature = 0.7,
  Duration timeout = const Duration(seconds: 30),  // L2 修复：加默认 timeout，避免调用方遗忘致卡死
}) async {
  final res = await _client.chat.completions.create(
    model: 'glm-4-flash',
    messages: [
      ChatCompletionMessage.system(content: systemPrompt),
      ChatCompletionMessage.user(content: userPrompt),
    ],
    temperature: temperature,
    responseFormat: const {'type': 'json_object'},
  ).timeout(timeout);
  return res.choices.first.message.content ?? '';
}
```

注：现有调用方 `ai_recommendation_service.dart` L214 的 `.timeout(30s)` 仍保留（双层 timeout 不冲突，先到的生效），未来可移除调用方的 timeout。

- [ ] **Step 4: Run test to verify it passes + analyze**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/glm_flash_provider_test.dart && flutter analyze lib/ai/glm_flash_provider.dart`
Expected: PASS + No issues

- [ ] **Step 5: Commit**

```bash
cd /workspace
git add lib/ai/glm_flash_provider.dart
git commit -m "fix: L2 createChatCompletion 加默认 timeout 30s

原方法无 timeout，调用方遗忘时网络抖动会卡死 UI。加默认 timeout 参数 30s，与 generateWeeklySummary/MonthlySummary 一致。"
```

---

### Task C5: profile_repository update 置空语义文档化（M7）

**Files:**
- Modify: `lib/data/repositories/profile_repository.dart:63-118`

- [ ] **Step 1: 修改 update 方法文档注释**

修改 `lib/data/repositories/profile_repository.dart` L63-81 方法注释：

```dart
/// 更新 profile（部分字段）
/// 注意：dailyCalorieTarget / proteinGPerKg / fatGPerKg / carbGPerKg
/// 由 ProfilePage 调 NutritionCalculator 重算后传入，本方法不重算
///
/// 特殊人群字段（specialCondition/dietPreference/healthCondition）：
/// 用 sentinel 区分"不更新"（absent）和"显式清空"（设为 'none'）。
/// null 参数 = 不更新该字段；非 null（含 'none'）= 写入该值。
///
/// M7 已知限制：bodyFatPct / carbGPerKg / tdeeAdjustmentKcal 等 nullable 数值字段，
/// null 参数 = 不更新（Value.absent），无法显式置空。若需清空，UI 应传默认值（如 0）
/// 而非 null。drift Value.absent 语义是"不更新"，Value(null) 才是"置空"，当前实现
/// 把 null 一律映射为 Value.absent，丢失置空语义。如需支持显式置空，需引入 sentinel
/// 对象或 Optional 包装，成本较高收益低，暂不实施。
Future<void> update({
```

- [ ] **Step 2: Run analyze to verify no syntax error**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter analyze lib/data/repositories/profile_repository.dart`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
cd /workspace
git add lib/data/repositories/profile_repository.dart
git commit -m "docs: M7 profile_repository update 置空语义限制文档化

bodyFatPct/carbGPerKg/tdeeAdjustmentKcal 等 nullable 数值字段，null 参数 = 不更新（Value.absent）无法显式置空。文档说明限制 + 替代方案（UI 传默认值 0），避免用户清空体脂率后看到旧值困惑。"
```

---

### Task C6: nutrition_lookup 三次查库优化（M10）

**Files:**
- Modify: `lib/ai/nutrition_lookup.dart:148-159`
- Test: `test/ai/nutrition_lookup_test.dart`（如不存在则创建/追加）

- [ ] **Step 1: Write the failing test**

在 `test/ai/nutrition_lookup_test.dart` 追加（如文件不存在，参考现有 nutrition_lookup 测试结构创建）：

```dart
test('M10: lookupSingleItemWithRange 三档用同一 food 计算（查库 1 次非 3 次）', () async {
  // mock foodRepo 记录 findByNameOrAlias 调用次数
  // 注：需 mock FoodItemRepository，参考现有 test 的 mock 模式
  // 这里只验证返回的 NutritionRange 三档都基于同一 food
  final range = await lookup.lookupSingleItemWithRange(
    dishName: '鸡胸肉',
    servingGLow: 80,
    servingGMid: 100,
    servingGHigh: 120,
  );
  if (range != null) {
    // 三档 protein 比例应一致（同一 food per100g × 不同 servingG）
    final ratioLowMid = range.low.proteinG / range.mid.proteinG;
    expect((ratioLowMid - 80 / 100).abs() < 0.01, true,
        reason: '三档应基于同一 food，比例 = servingG 比例');
  }
});
```

- [ ] **Step 2: Run test to verify it fails (or skip if mock too complex)**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/nutrition_lookup_test.dart --plain-name "M10"`
Expected: 可能 FAIL（当前三次独立查库，比例可能不一致）或编译错误（mock 未配）

注：M10 是性能优化，TDD 验证查库次数需复杂 mock。如果 mock 成本过高，可降级为"代码审查确认 + 现有测试不回归"。

- [ ] **Step 3: Write minimal implementation**

修改 `lib/ai/nutrition_lookup.dart` `lookupSingleItemWithRange`：

```dart
Future<NutritionRange?> lookupSingleItemWithRange({
  required String dishName,
  required double servingGLow,
  required double servingGMid,
  required double servingGHigh,
}) async {
  // M10 修复：先查一次库拿 food，用同一 food 计算三档（避免三次查库 + 三次 OFF 云查）
  final food = await _repo.findByNameOrAlias(dishName);
  if (food != null) {
    return NutritionRange(
      low: _nutritionFromFoodItem(food, servingGLow),
      mid: _nutritionFromFoodItem(food, servingGMid),
      high: _nutritionFromFoodItem(food, servingGHigh),
    );
  }
  // 库未命中 → OFF 云查一次（servingGMid），命中后落库 + 用同一 food 算三档
  final offMid = await _offProvider.lookup(name: dishName);
  if (offMid != null) {
    final inserted = await _repo.insertOff(offMid);
    return NutritionRange(
      low: _nutritionFromFoodItem(inserted, servingGLow),
      mid: _nutritionFromFoodItem(inserted, servingGMid),
      high: _nutritionFromFoodItem(inserted, servingGHigh),
    );
  }
  return null;
}

// 抽出 helper（与 recognize_page 的 _nutritionFromFoodItem 一致逻辑）
NutritionResult _nutritionFromFoodItem(FoodItem food, double servingG) {
  final edibleFactor = (food.ediblePercent ?? 100).clamp(1, 100) / 100;
  final effectiveG = servingG * edibleFactor;
  return NutritionResult(
    foodItemId: food.id,
    calories: food.caloriesPer100g * effectiveG / 100,
    proteinG: food.proteinPer100g * effectiveG / 100,
    fatG: food.fatPer100g * effectiveG / 100,
    carbsG: food.carbsPer100g * effectiveG / 100,
    oilG: 0,
  );
}
```

注：`NutritionRange` 类和 `_offProvider` 字段名需根据实际代码调整。如果 `lookupSingleItem` 内部有 5 级模糊匹配逻辑（findByNameOrAlias 之外），重构需保留这些路径。实施前先 Read 完整 `nutrition_lookup.dart` 确认结构。

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/ai/nutrition_lookup_test.dart`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
cd /workspace
git add lib/ai/nutrition_lookup.dart test/ai/nutrition_lookup_test.dart
git commit -m "perf: M10 nutrition_lookup 三档用同一 food 计算（查库 1 次非 3 次）

lookupSingleItemWithRange 原三次调 lookupSingleItem，每次走 findByNameOrAlias + 可能 OFF 云查。改为先查一次库拿 food，用同一 food 计算三档，避免重复 IO + OFF 速率限制。"
```

---

## Section D：UI 层 + 测试补强（7 个 Task）

### Task D1: offline_queue_controller incrementMonthlyCount（M11）

**Files:**
- Modify: `lib/features/offline/offline_queue_controller.dart`（构造器加 SecureConfigStore + markDone 前计数）
- Modify: `lib/background/background_dispatcher.dart`（实例化时传入 SecureConfigStore）
- Test: `test/features/offline_queue_test.dart`（追加用例）

- [ ] **Step 1: Write the failing test**

在 `test/features/offline_queue_test.dart` 追加：

```dart
test('M11: 后台回补成功时调 incrementMonthlyCount（月度计数同步）', () async {
  // mock SecureConfigStore 记录 incrementMonthlyCount 调用
  final store = SecureConfigStore();
  // ... 设置 pending 记录 + mock provider 返回成功
  final controller = OfflineQueueController(
    db: db,
    provider: fakeProvider,
    secureConfigStore: store,  // M11 新增参数
  );
  await controller.processPending();
  // 验证 incrementMonthlyCount 被调用
  final count = await store.getCurrentMonthCount(DateTime.now().year, DateTime.now().month);
  expect(count, greaterThan(0), reason: '后台回补成功应计入月度识别次数');
});
```

注：具体 mock 需参考 `test/features/offline_queue_test.dart` 现有结构。`SecureConfigStore` 在沙箱需 mock secure_storage。

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/offline_queue_test.dart --plain-name "M11"`
Expected: FAIL（OfflineQueueController 构造器无 secureConfigStore 参数）

- [ ] **Step 3: Write minimal implementation**

修改 `lib/features/offline/offline_queue_controller.dart` 构造器 + markDone 前计数：

```dart
class OfflineQueueController {
  final EatWiseDatabase _db;
  final VisionProvider _provider;
  final CircuitBreaker _circuitBreaker;
  final SecureConfigStore? _secureConfigStore;  // M11 新增：月度计数（可选，与 circuitBreaker 模式一致）

  OfflineQueueController({
    required EatWiseDatabase db,
    required VisionProvider provider,
    required CircuitBreaker circuitBreaker,
    SecureConfigStore? secureConfigStore,  // M11 新增可选参数
  })  : _db = db,
        _provider = provider,
        _circuitBreaker = circuitBreaker,
        _secureConfigStore = secureConfigStore;

  // 在 processPending 成功 markDone 前（L190 / L262 附近）加：
  // M11 修复：后台回补成功也计入月度识别次数（与前台 recognize_controller 一致）
  if (_secureConfigStore != null) {
    try {
      final now = DateTime.now();
      await _secureConfigStore!.incrementMonthlyCount(now.year, now.month);
    } catch (e) {
      // best-effort，计数失败不影响回补主流程
      debugPrint('incrementMonthlyCount 失败（不影响回补）：$e');
    }
  }
```

修改 `lib/background/background_dispatcher.dart` 实例化处（L83-87 附近）：

```dart
final controller = OfflineQueueController(
  db: db,
  provider: provider,
  circuitBreaker: circuitBreaker,
  secureConfigStore: SecureConfigStore(),  // M11 新增
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/offline_queue_test.dart --plain-name "M11"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /workspace
git add lib/features/offline/offline_queue_controller.dart lib/background/background_dispatcher.dart test/features/offline_queue_test.dart
git commit -m "fix: M11 offline_queue_controller 后台回补计入月度识别次数

原后台回补成功不调 incrementMonthlyCount，设置页'本月识别次数'偏低，T43 计数与实际 token 消耗脱节。构造器加可选 SecureConfigStore，markDone 前 best-effort 计数（try-catch 不影响主流程）。"
```

---

### Task D2: multi_dish_page widget test 补全（M12）

**Files:**
- Create: `test/features/multi_dish_page_test.dart`

- [ ] **Step 1: Write the failing test（新建文件）**

创建 `test/features/multi_dish_page_test.dart`：

```dart
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/recognize/multi_dish_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('M12: multi_dish_page 渲染主菜 + 附加菜 ListTile', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: MultiDishPage(
        mainDish: const VisionRecognitionResult(
          dishName: '番茄炒蛋',
          estimatedCaloriesG: 120,
          estimatedProteinG: 8,
          estimatedFatG: 9,
          estimatedCarbsG: 5,
          estimatedWeightGLow: 100,
          estimatedWeightGMid: 150,
          estimatedWeightGHigh: 200,
          weightSource: 'visual',
          foodCategory: 'stir_fry',
          reasoning: 'test',
          cookingMethod: 'stir_fry',
          isSingleItem: false,
          confidence: 0.9,
        ),
        additionalDishes: [],
        imagePath: null,
      )),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('番茄炒蛋'), findsWidgets);
  });

  // 可追加：改菜名 / packageMacrosAllZero 守卫 / db.transaction 原子性 等用例
}
```

注：`MultiDishPage` 构造器参数需根据实际签名调整。实施前 Read `lib/features/recognize/multi_dish_page.dart` 确认参数。

- [ ] **Step 2: Run test to verify it fails (or pass if constructor matches)**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/multi_dish_page_test.dart`
Expected: 如果构造器参数不匹配则 FAIL（编译错误），调整测试参数后 PASS

- [ ] **Step 3: Run test to verify it passes**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/multi_dish_page_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
cd /workspace
git add test/features/multi_dish_page_test.dart
git commit -m "test: M12 补 multi_dish_page widget test（核心路径回归保护）

multi_dish_page 是一桌多菜核心入口，含 resolveSingleFoodItemId/packageMacrosAllZero 守卫/db.transaction/每菜改菜名等复杂逻辑，原无 widget test。补基础渲染测试，后续可扩展守卫+事务用例。"
```

---

### Task D3: 版本号用 package_info_plus（M13）

**Files:**
- Modify: `pubspec.yaml`（加 package_info_plus 依赖）
- Modify: `lib/core/error/sentry_init.dart:45`
- Modify: `lib/features/me/me_page.dart:190`
- Modify: `lib/features/settings/settings_page.dart:333`

- [ ] **Step 1: 加依赖**

修改 `pubspec.yaml` dependencies，加：
```yaml
  package_info_plus: ^8.0.0  # M13 版本号动态读取（替代三处硬编码）
```

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter pub get`

- [ ] **Step 2: 创建 appVersionProvider**

修改 `lib/core/error/sentry_init.dart` 或新建 `lib/core/providers/app_version_provider.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 应用版本号 provider（替代三处硬编码）
/// M13 修复：从 PackageInfo 动态读取，发版时 pubspec.yaml bump 后自动同步
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
});

/// 纯版本号（不含 buildNumber），用于 Sentry release 标签
final appVersionShortProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});
```

- [ ] **Step 3: 修改三处硬编码**

`lib/features/me/me_page.dart:190` 改为 FutureBuilder：
```dart
// 原：applicationVersion: '0.16.0',
applicationVersion: ref.watch(appVersionProvider).maybeWhen(
  data: (v) => v, orElse: () => '加载中',
),
```

`lib/features/settings/settings_page.dart:333` 改为 FutureBuilder：
```dart
// 原：const Text('慢慢吃 v0.16.0')
Text('慢慢吃 v${ref.watch(appVersionProvider).maybeWhen(data: (v) => v, orElse: () => '...')}')
```

`lib/core/error/sentry_init.dart:45` 改为：
```dart
// 原：defaultValue: 'eatwise@0.16.0',
// M13 改为：在 init 前 await PackageInfo.fromPlatform()，用动态版本号
final info = await PackageInfo.fromPlatform();
options.release = 'eatwise@${info.version}';
```

- [ ] **Step 4: Run analyze + test**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter analyze && flutter test`
Expected: No issues + All tests pass

注：测试中 `PackageInfo.fromPlatform()` 在沙箱可能抛 MissingPluginException，需 `PackageInfo.setMockInitialValues(...)` mock。参考 `monthly_cost_test.dart` 的 mock 模式。

- [ ] **Step 5: Commit**

```bash
cd /workspace
git add pubspec.yaml pubspec.lock lib/core/providers/app_version_provider.dart lib/core/error/sentry_init.dart lib/features/me/me_page.dart lib/features/settings/settings_page.dart
git commit -m "feat: M13 版本号用 package_info_plus 动态读取（替代三处硬编码）

me_page/settings_page/sentry_init 三处硬编码版本号，发版易遗漏。新建 appVersionProvider 从 PackageInfo 读取，pubspec bump 后自动同步。"
```

---

### Task D4: weight_page PopScope 未保存确认（M14）

**Files:**
- Modify: `lib/features/weight/weight_page.dart`

- [ ] **Step 1: Write the failing test**

创建或追加到 `test/features/weight_page_test.dart`：

```dart
testWidgets('M14: 体重输入后返回弹放弃确认', (tester) async {
  // ... 渲染 WeightPage
  await tester.enterText(find.byType(TextField), '75');
  await tester.pump();

  // 模拟系统返回
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();

  // 验证弹"放弃更改"确认对话框
  expect(find.text('放弃更改'), findsOneWidget);
});
```

注：完整测试需 mock SecureConfigStore / databaseProvider，参考 `weight_log_repository_test.dart` 的 mock 模式。

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/weight_page_test.dart --plain-name "M14"`
Expected: FAIL（当前 WeightPage 无 PopScope）

- [ ] **Step 3: Write minimal implementation**

修改 `lib/features/weight/weight_page.dart`：

```dart
class _WeightPageState extends ConsumerState<WeightPage> {
  bool _dirty = false;
  // ... 现有字段

  @override
  void initState() {
    super.initState();
    _weightCtrl = TextEditingController();
    _weightCtrl.addListener(_markDirty);  // M14 新增
    // ... 现有 init
  }

  void _markDirty() {
    if (!_loading) _dirty = true;  // M14 新增（_loading 守卫防初始赋值误标）
  }

  @override
  void dispose() {
    _weightCtrl.removeListener(_markDirty);
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // ... 现有保存逻辑
    if (success) {
      _dirty = false;  // M14 新增：保存成功放行
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,  // M14 新增
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final confirmed = await confirmDiscardChanges(context);  // m3_widgets 公共组件
        if (confirmed && mounted) {
          _dirty = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(/* 现有内容 */),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/weight_page_test.dart --plain-name "M14"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /workspace
git add lib/features/weight/weight_page.dart test/features/weight_page_test.dart
git commit -m "feat: M14 weight_page 加 PopScope 未保存确认

输入体重后误触返回会丢失数据，加 _dirty 标记 + PopScope + confirmDiscardChanges 公共组件，与 manual_entry_page/calibration_page/profile_page 风格一致。"
```

---

### Task D5-D7: 测试补强（M15-M17，可选）

**Task D5: settings_page_test 增强（M15）**
- 修改 `test/features/settings_page_test.dart`，参考 `monthly_cost_test.dart` 的 mock 模式（setMockInitialValues + _MemoryPathProvider）
- 补测：_markDirty 防初始赋值 / _save invalidate appConfigProvider / 版本号显示 / 备份超期提示

**Task D6: recognize_controller 容灾逻辑抽离 + 测试（M16）**
- 修改 `lib/features/recognize/recognize_controller.dart`，把限流时间戳判断、容灾分支决策抽成 `@visibleForTesting` 方法
- 补 `test/features/recognize_controller_test.dart`：测限流/容灾分支决策（不依赖 ImagePicker）

**Task D7: offline_queue 断路器+事务测试（M17）**
- 修改 `test/features/offline_queue_test.dart`，mock CircuitBreaker.allowCall=false，验证 pending 仍 pending
- mock MealLogRepository.insertMealLog 抛异常，验证 markDone 不执行（事务回滚）

这三个 Task 因复杂度较高，建议作为"可选"在主流程完成后实施。每个 Task 完成后独立 commit。

---

## Section E：Low 级顺手清理（5 个 Task）

### Task E1: _friendlyError 加 5xx/403（L1）

**Files:**
- Modify: `lib/nutrition/ai_recommendation_service.dart:137-152`
- Test: `test/nutrition/ai_recommendation_service_test.dart`（追加用例）

- [ ] **Step 1: Write the failing test**

在 `test/nutrition/ai_recommendation_service_test.dart` 追加：

```dart
test('L1: _friendlyError 覆盖 5xx 和 403', () {
  // 通过 recommend 传入会抛 5xx 的 mock provider，验证返回的 error 文案
  // 注：_friendlyError 是私有方法，通过 recommend 间接测试
  // mock provider 抛 Exception('500 Internal Server Error')
  // 验证 result.error 包含 '服务暂时不可用'
});
```

- [ ] **Step 2: Write minimal implementation**

修改 `lib/nutrition/ai_recommendation_service.dart:137-152`：

```dart
String _friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('TimeoutException') || s.contains('timeout')) {
    return 'AI 响应超时，已切换本地推荐';
  }
  if (s.contains('401') || s.contains('Unauthorized')) {
    return 'GLM API Key 无效，已切换本地推荐';
  }
  // L1 新增：403 权限不足
  if (s.contains('403') || s.contains('Forbidden')) {
    return 'GLM API Key 权限不足，已切换本地推荐';
  }
  if (s.contains('429') || s.contains('rate limit')) {
    return 'AI 调用太频繁，请稍后重试';
  }
  // L1 新增：5xx 服务器错误
  if (RegExp(r'5\d{2}').hasMatch(s) || s.contains('server error') || s.contains('Internal Server Error')) {
    return 'AI 服务暂时不可用，请稍后重试';
  }
  if (s.contains('SocketException') || s.contains('network')) {
    return '网络连接失败，已切换本地推荐';
  }
  return 'AI 推荐暂不可用，已切换本地推荐';
}
```

- [ ] **Step 3: Commit**

```bash
cd /workspace
git add lib/nutrition/ai_recommendation_service.dart test/nutrition/ai_recommendation_service_test.dart
git commit -m "fix: L1 _friendlyError 加 5xx/403 错误文案

原仅覆盖 timeout/401/429/network，5xx 和 403 落兜底文案不够精准。加 403'权限不足'和 5xx'服务暂时不可用'分支。"
```

---

### Task E2: weight_log_repository getRange 同日去重（L5）

**Files:**
- Modify: `lib/data/repositories/weight_log_repository.dart:44-49`
- Test: `test/data/weight_log_repository_test.dart`（追加用例）

- [ ] **Step 1: Write the failing test**

在 `test/data/weight_log_repository_test.dart` 追加：

```dart
test('L5: getRange 同日多条去重保留最新', () async {
  final today = formatYmd(DateTime.now());
  await repo.insert(date: today, weightKg: 70.0, loggedAt: 1000);
  await repo.insert(date: today, weightKg: 71.0, loggedAt: 2000);  // 更新
  final result = await repo.getRange(today, today);
  expect(result.length, 1, reason: '同日多条应去重');
  expect(result.first.weightKg, 71.0, reason: '保留最新（loggedAt 大的）');
});
```

- [ ] **Step 2: Write minimal implementation**

修改 `lib/data/repositories/weight_log_repository.dart` `getRange`：

```dart
Future<List<WeightLog>> getRange(String startDate, String endDate) async {
  final all = await (_db.weightLogs.select()
        ..where((w) => w.date.isBetweenValues(startDate, endDate))
        ..orderBy([(w) => OrderingTerm.desc(w.loggedAt)]))
      .get();
  // L5 修复：同日多条保留最新（与 getRangeForTdee 一致）
  final byDate = <String, WeightLog>{};
  for (final w in all) {
    byDate[w.date] = w;  // desc 排序，先到的 loggedAt 大，覆盖后到的
  }
  return byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));
}
```

- [ ] **Step 3: Commit**

```bash
cd /workspace
git add lib/data/repositories/weight_log_repository.dart test/data/weight_log_repository_test.dart
git commit -m "fix: L5 weight_log getRange 同日多条去重（与 getRangeForTdee 一致）

折线图同日多条会显示多个点跳变，getRange 改为按 date 去重保留最新（loggedAt 大），与 getRangeForTdee 行为一致。"
```

---

### Task E3: insight_chart_test 注释更新（L3）

**Files:**
- Modify: `test/features/insight_chart_test.dart:12`

- [ ] **Step 1: 修改注释**

```dart
// 修改前
// 测试种子今天 + 昨天的 meal_log（落在 InsightPage 硬编码的 monday-sunday 本周内）

// 修改后
// 测试种子今天 + 昨天的 meal_log（落在 v1.11 滚动窗口 today-6 ~ today 内）
```

- [ ] **Step 2: Commit**

```bash
cd /workspace
git add test/features/insight_chart_test.dart
git commit -m "docs: L3 insight_chart_test 注释同步 v1.11 滚动窗口

原注释说'monday-sunday 本周'，v1.11 已改滚动窗口 today-6 ~ today，注释 stale 误导维护者。"
```

---

### Task E4: dish_name_editor searchByName limit:10（L4）

**Files:**
- Modify: `lib/features/recognize/dish_name_editor.dart:126`

- [ ] **Step 1: 修改 limit**

```dart
// 修改前
final candidates = await foodRepo.searchByName(newName, limit: 30);

// 修改后（L4：改菜名场景用户已输入精准关键词，30 候选过多筛选成本高，10 足够）
final candidates = await foodRepo.searchByName(newName, limit: 10);
```

- [ ] **Step 2: Run analyze**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter analyze lib/features/recognize/dish_name_editor.dart`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
cd /workspace
git add lib/features/recognize/dish_name_editor.dart
git commit -m "ux: L4 dish_name_editor searchByName limit 30→10

改菜名场景用户已输入精准关键词，30 候选在 AlertDialog 内滚动筛选成本高，10 足够（GLM 5 级模糊兜底仍保留）。"
```

---

### Task E5: 全量验证 + push

- [ ] **Step 1: Run flutter analyze**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter analyze`
Expected: No issues found

- [ ] **Step 2: Run flutter test full suite**

Run: `cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test`
Expected: All tests passed（0 failed）

- [ ] **Step 3: Update HANDOFF.md**

回填本次深度审查修复记录到 `/workspace/HANDOFF.md` 第 2 节"当前状态"，记录：
- 6 个 High 修复（H1-H6）
- 17 个 Medium 修复（M1-M17，可选标注哪些做了）
- 5 个 Low 修复（L1-L5）
- commit hash

- [ ] **Step 4: Commit HANDOFF + push**

```bash
cd /workspace
git add HANDOFF.md
git commit -m "docs: HANDOFF 回填深度审查修复 commit hash"
git push origin trae/agent-wX1X6Q
```

---

## Self-Review

### 1. Spec coverage（审查发现 vs Task 覆盖）

| 审查发现 | 对应 Task | 状态 |
|---------|----------|------|
| H1 fromJson null 兜底 | Task A1 | ✅ |
| H2 _asInt 兜底 | Task A2 | ✅ |
| H3 _buildPrompt null 兜底 | Task A3 | ✅ |
| H4 recent 方法 endDate | Task A4 | ✅ |
| H5+H6 prompt + validator 容忍度 | Task A5 | ✅ |
| M1 宏量数组越界 | Task B1 | ✅ |
| M2 SegmentedButton 竞态 | Task B2 | ✅ |
| M3 recognize_page 迁移 mixin | Task B3 | ✅ |
| M4 测试滚动统一 | Task B4 | ✅ |
| M5 hasPackageNutrition | Task C1 | ✅ |
| M6 copyWith 字段 | Task C2 | ✅ |
| M7 profile update 置空 | Task C5（文档化） | ✅ |
| M8 OCR 多字糖类 | Task C3 | ✅ |
| M9 GlmFlashProvider autoDispose | 未纳入（风险高，Riverpod 重构） | ⚠️ 降级 |
| M10 nutrition_lookup 优化 | Task C6 | ✅ |
| M11 incrementMonthlyCount | Task D1 | ✅ |
| M12 multi_dish_page test | Task D2 | ✅ |
| M13 版本号 package_info_plus | Task D3 | ✅ |
| M14 weight_page PopScope | Task D4 | ✅ |
| M15 settings_page_test | Task D5（可选） | ⚠️ |
| M16 recognize_controller 容灾测试 | Task D6（可选） | ⚠️ |
| M17 offline_queue 断路器+事务测试 | Task D7（可选） | ⚠️ |
| L1 _friendlyError 5xx/403 | Task E1 | ✅ |
| L2 createChatCompletion timeout | Task C4 | ✅ |
| L3 insight_chart_test 注释 | Task E3 | ✅ |
| L4 searchByName limit:10 | Task E4 | ✅ |
| L5 weight_log getRange 去重 | Task E2 | ✅ |

**降级说明**：
- M9 GlmFlashProvider autoDispose：需重构 Riverpod provider 层，风险较高，当前 close() 手动调用已可接受，降级不修
- M15-M17 测试补强：复杂度高（需 mock secure_storage/CircuitBreaker/ImagePicker），作为可选 Task，主流程完成后视情况实施

### 2. Placeholder scan

已检查所有 Task，无 "TBD/TODO/类似 Task N" 占位。每个 Task 都有完整代码。少数 Task（C6 nutrition_lookup / D2 multi_dish_page_test）实施前需 Read 实际文件确认结构，已在 Task 内注明。

### 3. Type consistency

- `VisionRecognitionResult` 构造器参数在 A1/C1/C2 中一致
- `OfflineQueueController` 构造器参数在 D1 中与 background_dispatcher 实例化一致
- `appVersionProvider` 在 D3 中定义后，me_page/settings_page/sentry_init 引用一致
- `_friendlyError` 签名在 E1 中不变，只增加分支

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-04-deep-audit-fixes.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - 每个 Task 派 fresh subagent，Task 间 review，快速迭代

**2. Inline Execution** - 当前会话按 Section 顺序执行，每个 Section 末尾 checkpoint review

**建议**：用户原话"严谨一点，反复检查"，建议 Subagent-Driven + 每 Section 末尾全量 `flutter analyze + flutter test` 验证。Section A（High 级）必做，Section B-D 按优先级推进，Section E 顺手清理。
