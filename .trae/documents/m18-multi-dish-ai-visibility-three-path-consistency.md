# M18 多菜场景 AI 推理可见性 + 三路径一致性 + 提高 AI 优先值（v0.19.0）

> **触发**：用户反馈"比较复杂的场景比如有好几个食物的情况下，没有 AI 推理的过程，精准度我也有一定程度的怀疑，是不是正确安装 AI 的计算提交并且显示的，希望还能继续改进，严谨仔细，一定不能出问题" + "这个方案很好，但我还想提高AI的优先值，严谨一点进行改进"
> **Skill 组合**：brainstorming（方案发散）+ test-driven-development（Red-Green-Refactor 严格 TDD）
> **用户决策**：范围 = AI 可见性 + 三路径一致性 + 提高 AI 优先值；形态 = 完整 AI 估算卡片

---

## Phase 1 探索结果

### 核心问题（已验证）

1. **multi_dish_page 完全没有 AI 推理显示**（`lib/features/recognize/multi_dish_page.dart` L212-323 `_buildDishCard`）
   - 仅显示：菜名 + 未命中徽章 + 份量滑块 + 营养素行（kcal · 蛋白 · 脂肪 · 碳水）
   - **不显示**：reasoning（AI 推理过程）、confidence（置信度）、source badge（来源徽章）、AI 估算 vs 库值对比
   - 与 calibration_page（L213 置信度 + L241-277 reasoning 折叠面板 + L859-876 source badge）形成强烈对比

2. **复合菜三路径不一致**（硬约束 #3 要求全部覆盖）
   - `multi_dish_page._computeCompositeLookupHitCalibrated`（L384-413）：独立实现 AI 优先，per100g=0 占位
   - `offline_queue_controller` 复合菜命中分支（L330-392）：**不走 AI 差异检测**，直接用组分累加库值
   - `recognize_page` 复合菜路径（writeCalibratedMealLog L143-163）：仅创建 ai_recognized food_item，不走差异检测
   - 用户感知：同一道复合菜，前台记录 vs 后台回补可能给出不同热量

3. **用户无法验证 AI 精度**
   - M16.9 AI 绝对优先策略：AI per100g ∈ [0, 900] 即采用 AI 值
   - 但用户看不到"AI 估算 per100g vs 库 per100g"对比，无法判断 AI 是否靠谱
   - source badge 在查库命中 + AI 优先时显示"库匹配"，实际数值来自 AI，误导用户

### 关键文件清单（已读）

| 文件 | 行数 | 角色 |
|------|------|------|
| `lib/features/recognize/multi_dish_page.dart` | 825 | 多菜列表页 + _recordAll 写库 + _buildDishCard 渲染 |
| `lib/features/recognize/calibrated_nutrition_calculator.dart` | 187 | AI 绝对优先统一计算（单品路径） |
| `lib/features/offline/offline_queue_controller.dart` | ~450 | 后台回补（复合菜命中分支 L330-392 不走 AI 差异检测） |
| `lib/features/recognize/calibration_page.dart` | ~900 | 单品校准页（已有 reasoning + confidence + source badge，参考样板） |
| `lib/features/recognize/recognize_page.dart` | 719 | 识别入口 + writeCalibratedMealLog |
| `lib/ai/vision_provider.dart` | ~341 | VisionRecognitionResult 字段定义（含 reasoning / confidence / hasPackageNutrition） |
| `lib/ai/nutrition_lookup.dart` | ~300 | NutritionResult + NutritionSource 枚举（database / aiEstimate） |
| `test/features/multi_dish_page_test.dart` | 645 | 8 个测试（4 个 AI 精度相关） |
| `test/features/calibrated_nutrition_calculator_test.dart` | ~400 | M16.9 单品 AI 绝对优先测试 |
| `test/features/offline_queue_composite_test.dart` | ~350 | 离线队列复合菜测试 |

### 6 条硬约束（M18 不可违背）

1. `android/app/build.gradle.kts`：`isMinifyEnabled = false` + `isShrinkResources = false`（M18 不动 Android 层）
2. `meal_log.food_item_id` 非空外键 + `foodItemId=0` 哨兵 upsertAiRecognized（M18 不动写库逻辑，仅扩展显示）
3. **AI 兜底三路径必须全部覆盖**（M18 重点：复合菜命中分支三路径统一）
4. `per100g` 反算基于 `estimatedWeightGMid`（M18 不变）
5. `SecureConfigStore` 无 `instance` 静态属性（M18 不动）
6. `initSentryAndRunApp` 命名参数（M18 不动）

---

## Phase 2 用户决策（已完成）

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 改进范围 | **AI 可见性 + 三路径一致性 + 提高 AI 优先值** | 用户要求"严谨仔细，一定不能出问题" + "提高 AI 的优先值，严谨一点进行改进" |
| 可见性形态 | **完整 AI 估算卡片** | 与 calibration_page 风格一致，包含 reasoning + confidence + source badge + AI vs 库值对比 |

### "提高 AI 优先值"的具体策略（严谨版）

当前 M16.9 已是 "AI 绝对优先"，但仍有两个保守点限制了 AI 估算的利用率：

1. **复合菜 per100g=0 占位**：复合菜 AI 估算有效时，per100g 仍存 0（不进入食物库），导致未来查库命中时无法复用 AI 值
2. **shouldUpdateFoodItem diffRatio > 5% 才写库**：单品查库命中 + AI 偏差 < 5% 时不写库，库值仍是旧值，AI 估算未"沉淀"到库

**M18 改进**（严谨，不破坏 sanity check 安全网）：
- **改进 1**：复合菜 AI 有效时，per100g 从 0 占位改为 AI 反算值（`aiFallback.calories * 100 / mid`），让 AI 估算进入食物库。复合菜查库时 `lookupSingleItem` 已过滤 `componentsJson != null` 记录，不会污染单品查库。
- **改进 2**：单品查库命中 + AI 有效时，`shouldUpdateFoodItem` 始终为 true（diffRatio > 0 即写库），让 AI 估算持续纠正库。原 5% 阈值是为避免无意义写库，但用户要求"提高 AI 优先值"，持续写库让库值始终跟随 AI。
- **安全网不变**：AI per100g > 900 或 < 0 仍用库值兜底（sanity check 不放宽，硬约束 #4 不变）
- **mid=0 不变**：mid <= 0 时仍返回 null/兜底，防除零

---

## Phase 3 实施计划（4 个 Task，严格 TDD）

### 设计原则

1. **TDD 优先**：每个 Task 先写失败测试（RED）→ 验证失败 → 最小实现（GREEN）→ 验证通过 → 重构（REFACTOR）
2. **不破坏现有行为**：8 个 multi_dish_page_test + 4 个 calibrated_nutrition_calculator_test + offline_queue_composite_test 必须全部保持 green
3. **抽取公共逻辑**：复合菜 AI 优先逻辑从 multi_dish_page 抽取到 CalibratedNutritionCalculator，让三路径复用
4. **UI 改动最小化**：仅在 _buildDishCard 现有结构后追加 AI 估算卡片，不动份量滑块/营养素行/未命中逻辑

---

### Task 1: 抽取复合菜 AI 优先逻辑为 CalibratedNutritionCalculator.computeCompositeLookupHit

**目标**：让 multi_dish_page 和 offline_queue 共用同一套复合菜 AI 差异检测逻辑，消除三路径不一致。

**文件**：
- 修改：`lib/features/recognize/calibrated_nutrition_calculator.dart`（新增 `computeCompositeLookupHit` 静态方法）
- 修改：`lib/features/recognize/multi_dish_page.dart`（`_computeCompositeLookupHitCalibrated` 改为调用新方法）
- 修改：`lib/features/offline/offline_queue_controller.dart`（复合菜命中分支 L330-392 改为调用新方法）

#### TDD Step 1: RED - 写失败测试

**文件**：`test/features/calibrated_nutrition_calculator_test.dart`（追加）

新增 4 个测试：
1. `computeCompositeLookupHit: AI 有效时返回 AI 估算值 + per100g=0 占位`
   - 输入：aiFallback.calories=500, mid=200, composite.calories=314
   - 期望：返回 CalibratedNutrition（actualCalories=500, caloriesPer100g=0, shouldUpdateFoodItem=false）
2. `computeCompositeLookupHit: AI 离谱（per100g>900）时返回 null`
   - 输入：aiFallback.calories=2000, mid=200（per100g=1000>900）
   - 期望：返回 null（调用方走原 ratio 兜底）
3. `computeCompositeLookupHit: mid=0 时返回 null（防除零）`
   - 输入：aiFallback.calories=500, mid=0
   - 期望：返回 null
4. `computeCompositeLookupHit: actualXxx 按 serving/mid 比例缩放`
   - 输入：aiFallback.calories=500, mid=200, servingG=100
   - 期望：actualCalories=250（500 × 100/200）

#### TDD Step 2: Verify RED

```bash
cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/calibrated_nutrition_calculator_test.dart
```
**预期**：4 个新测试失败（方法不存在），原有测试保持 green。

#### TDD Step 3: GREEN - 最小实现

**`calibrated_nutrition_calculator.dart` 新增方法**：

```dart
/// 复合菜查库命中 + AI 整菜估算的差异检测（M18：三路径统一）
///
/// 抽取自 multi_dish_page._computeCompositeLookupHitCalibrated，
/// 让 offline_queue_controller 复用，消除三路径不一致。
///
/// 策略（与单品查库命中分支一致，M16.9 AI 绝对优先）：
/// - AI 有效（per100g ∈ [0, 900]）：用 AI 整菜估算记 meal_log，per100g=0 占位不更新库
/// - AI 无效（null / 负 / >900 / mid=0）：返回 null，调用方走原 ratio 兜底
///
/// [aiFallback] AI 整菜估算（foodItemId=0，calories 对应 mid 份量）
/// [servingG] 用户调整后的份量（前台）或 AI mid（后台）
/// [mid] AI 估算重量中位数（per100g 反算基准，硬约束 #4）
static CalibratedNutrition? computeCompositeLookupHit({
  required NutritionResult aiFallback,
  required double servingG,
  required double mid,
}) {
  if (mid <= 0) return null; // 防除零
  final aiPer100 = aiFallback.calories * 100 / mid;
  final aiValid = aiPer100 >= 0 && aiPer100 <= 900;
  if (!aiValid) return null; // AI 离谱，调用方走原 ratio 兜底

  // AI 优先：actualXxx 按 serving/mid 比例缩放
  final ratio = servingG / mid;
  return CalibratedNutrition(
    caloriesPer100g: 0, // 复合菜 per100g=0 占位，不更新库
    proteinPer100g: 0,
    fatPer100g: 0,
    carbsPer100g: 0,
    actualCalories: aiFallback.calories * ratio,
    actualProteinG: aiFallback.proteinG * ratio,
    actualFatG: aiFallback.fatG * ratio,
    actualCarbsG: aiFallback.carbsG * ratio,
    foodItemId: 0, // 调用方 upsertAiRecognized 替换
    shouldUpdateFoodItem: false, // 复合菜不更新库 per100g
  );
}
```

**`multi_dish_page.dart` 重构 `_computeCompositeLookupHitCalibrated`**（L384-413）：

```dart
CalibratedNutrition? _computeCompositeLookupHitCalibrated(
  NutritionResult aiFallback,
  double servingG,
  double mid,
) {
  // M18：抽取到 CalibratedNutritionCalculator.computeCompositeLookupHit，三路径统一
  return CalibratedNutritionCalculator.computeCompositeLookupHit(
    aiFallback: aiFallback,
    servingG: servingG,
    mid: mid,
  );
}
```
（保留方法签名避免调用方改动，内部改为委托）

**`offline_queue_controller.dart` 复合菜命中分支改造**（L330-392）：

在 "无包装 / 包装换算宏量全 0 → 组分累加" 分支前插入 AI 差异检测：
```dart
} else {
  // M18：复合菜组分部分命中 + AI 整菜估算 → AI 绝对优先（与 multi_dish_page 一致）
  final mid = result.estimatedWeightGMid;
  final aiFallback = NutritionResult(
    foodItemId: 0,
    calories: result.estimatedCalories ?? 0,
    proteinG: result.estimatedProteinG ?? 0,
    fatG: result.estimatedFatG ?? 0,
    carbsG: result.estimatedCarbsG ?? 0,
    source: NutritionSource.aiEstimate,
  );
  final calibrated = CalibratedNutritionCalculator.computeCompositeLookupHit(
    aiFallback: aiFallback,
    servingG: actualServingG > 0 ? actualServingG : mid,
    mid: mid,
  );
  if (calibrated != null) {
    // AI 有效：用 AI 整菜估算记 meal_log，per100g=0 占位
    foodItemId = await foodItemRepo.upsertAiRecognized(
      name: result.dishName,
      brand: result.brand,
      caloriesPer100g: 0,
      proteinPer100g: 0,
      fatPer100g: 0,
      carbsPer100g: 0,
      confidence: result.confidence,
      componentsJson: componentsJson,
    );
    actualCalories = calibrated.actualCalories;
    actualProteinG = calibrated.actualProteinG;
    actualFatG = calibrated.actualFatG;
    actualCarbsG = calibrated.actualCarbsG;
  } else {
    // AI 无效：走原组分累加兜底（原逻辑）
    foodItemId = await foodItemRepo.upsertAiRecognized(...); // 原代码
    actualCalories = composite.calories;
    ...
  }
}
```

#### TDD Step 4: Verify GREEN

```bash
flutter test test/features/calibrated_nutrition_calculator_test.dart
flutter test test/features/multi_dish_page_test.dart
flutter test test/features/offline_queue_composite_test.dart
```
**预期**：4 个新测试通过 + 原有 8+4+N 个测试保持 green。

#### TDD Step 5: REFACTOR

- 检查 `_computeCompositeLookupHitCalibrated` 是否可内联（如果只是单行委托，可考虑直接调用方调静态方法）
- 检查 offline_queue_controller 改造后的注释清晰度

---

### Task 2: multi_dish_page 完整 AI 估算卡片（UI 显示）

**目标**：在 _buildDishCard 的营养素行后追加 AI 估算卡片，与 calibration_page 风格一致。

**文件**：
- 修改：`lib/features/recognize/multi_dish_page.dart`（`_buildDishCard` L212-323 追加 AI 卡片）

#### AI 估算卡片结构（每道命中菜品 Card 内追加）

```
┌─────────────────────────────────────────┐
│ [菜名] ×数量  [未命中]  [改菜名]        │
│ 份量：250 g                             │
│ [======== Slider ========]              │
│ 350 kcal · 蛋白 15g · 脂肪 12g · 碳水 30g│
│ ─────────────────────────────────────── │
│ 📊 AI 估算    置信度 92%   [AI 优先]    │  ← 新增行 1
│ AI: 140 kcal/100g · 库: 125 (偏差 +12%) │  ← 新增行 2（仅查库命中时显示）
│ ▾ AI 推理过程                           │  ← 新增行 3（折叠面板）
│   [展开后显示 reasoning 文本]           │
└─────────────────────────────────────────┘
```

**显示规则**：
- 行 1（AI 估算 + 置信度 + 来源徽章）：所有命中菜品显示
  - 置信度：`dish.confidence * 100`%，<60% 红色警告
  - 来源徽章：
    - 查库命中 + AI 优先 → "AI 优先"（紫色 primaryContainer）
    - 查库命中 + AI 无效兜底 → "库匹配"（蓝色 secondaryContainer）
    - AI 兜底哨兵（foodItemId=0）→ "AI 估算"（橙色 tertiaryContainer）
- 行 2（AI vs 库值对比）：仅查库命中时显示
  - `AI: ${aiPer100} kcal/100g · 库: ${dbPer100} (偏差 ${diff}%)`
  - 偏差 > 50% 时红色高亮
- 行 3（reasoning 折叠面板）：reasoning 非空时显示
  - 默认折叠，ExpansionTile + psychology_outlined 图标
  - 与 calibration_page L241-277 风格一致

#### TDD Step 1: RED - 写失败测试

**文件**：`test/features/multi_dish_page_test.dart`（追加）

新增 5 个 UI 渲染测试：
1. `AI 估算卡片显示置信度百分比`
   - 渲染命中菜品（confidence=0.92）
   - 期望：找到 Text('置信度 92%')
2. `低置信度时显示红色警告`
   - 渲染命中菜品（confidence=0.45）
   - 期望：找到警告 Text（'待确认' 或红色样式）
3. `查库命中 + AI 优先时显示 AI 优先徽章`
   - 渲染查库命中 + AI 有效的菜品
   - 期望：找到 Text('AI 优先')
4. `查库命中时显示 AI vs 库值对比行`
   - 渲染查库命中菜品（aiPer100=140, dbPer100=125）
   - 期望：找到 Text 包含 'AI: 140' 和 '库: 125' 和 '偏差'
5. `reasoning 非空时显示 AI 推理过程折叠面板`
   - 渲染 reasoning='识别为宫保鸡丁...' 的菜品
   - 期望：找到 ExpansionTile 含 'AI 推理过程'

#### TDD Step 2: Verify RED

```bash
flutter test test/features/multi_dish_page_test.dart
```
**预期**：5 个新测试失败（UI 元素不存在），原有 8 个测试保持 green。

#### TDD Step 3: GREEN - 最小实现

**`multi_dish_page.dart` `_buildDishCard` 改造**（L276 `if (hit) ...[` 块内，营养素行后追加）：

```dart
if (hit) ...[
  const SizedBox(height: 8),
  Text('份量：${_servings[index].toStringAsFixed(0)} g'),
  Slider(...), // 原滑块
  _buildQuantityStepper(index, dish),
  Text('${cal.toStringAsFixed(0)} kcal · ...', ...), // 原营养素行
  
  // M18: AI 估算卡片
  const SizedBox(height: 8),
  _buildAiEstimateCard(index, dish, cal, p, f, c),
],
```

**新增 `_buildAiEstimateCard` 方法**：

```dart
/// M18: AI 估算卡片——显示置信度 + 来源徽章 + AI vs 库值对比 + reasoning
Widget _buildAiEstimateCard(
  int index,
  VisionRecognitionResult dish,
  double cal, double p, double f, double c,
) {
  final single = _getSingleNutrition(index);
  final composite = _getCompositeNutrition(index);
  final aiFallback = index == 0
      ? widget.mainAiFallback
      : widget.additionalItems[index - 1].aiFallback;
  
  // 判断来源
  final bool isAiSentinel = single != null && single.foodItemId == 0;
  final bool isLookupHit = single != null && single.foodItemId > 0 ||
      composite != null;
  final bool isAiPriority = isLookupHit && aiFallback != null && _isAiValid(dish, aiFallback);
  
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // 行 1: AI 估算 + 置信度 + 来源徽章
      Row(children: [
        Icon(Icons.insights_outlined, size: 14, color: cs.primary),
        SizedBox(width: 4),
        Text('AI 估算', style: bodySmall),
        SizedBox(width: 8),
        Text('置信度 ${(dish.confidence * 100).toStringAsFixed(0)}%',
            style: bodySmall.copyWith(
              color: dish.confidence < 0.6 ? cs.error : cs.onSurfaceVariant,
            )),
        SizedBox(width: 8),
        _buildSourceBadge(isAiSentinel, isAiPriority),
      ]),
      
      // 行 2: AI vs 库值对比（仅查库命中时显示）
      if (isLookupHit && aiFallback != null) ...[
        SizedBox(height: 4),
        _buildAiVsDbComparison(dish, aiFallback, single, composite),
      ],
      
      // 行 3: reasoning 折叠面板
      if (dish.reasoning != null && dish.reasoning!.isNotEmpty) ...[
        SizedBox(height: 4),
        _buildReasoningExpansionTile(dish.reasoning!),
      ],
    ],
  );
}

Widget _buildSourceBadge(bool isAiSentinel, bool isAiPriority) {
  final (label, color) = isAiSentinel
      ? ('AI 估算', cs.tertiaryContainer)
      : isAiPriority
          ? ('AI 优先', cs.primaryContainer)
          : ('库匹配', cs.secondaryContainer);
  return Container(
    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: TextStyle(fontSize: 10)),
  );
}

Widget _buildAiVsDbComparison(dish, aiFallback, single, composite) {
  final mid = dish.estimatedWeightGMid;
  if (mid <= 0) return SizedBox.shrink();
  final aiPer100 = aiFallback.calories * 100 / mid;
  final dbPer100 = single != null
      ? single.calories * 100 / mid
      : (composite != null ? composite.calories * 100 / mid : 0.0);
  final diff = dbPer100 > 0 ? ((aiPer100 - dbPer100) / dbPer100 * 100).abs() : 0.0;
  final diffStr = diff > 50 ? '⚠ 偏差 ${diff.toStringAsFixed(0)}%' : '偏差 ${diff.toStringAsFixed(0)}%';
  return Text(
    'AI: ${aiPer100.toStringAsFixed(0)} kcal/100g · 库: ${dbPer100.toStringAsFixed(0)} ($diffStr)',
    style: bodySmall.copyWith(
      fontSize: 11,
      color: diff > 50 ? cs.error : cs.onSurfaceVariant,
    ),
  );
}

Widget _buildReasoningExpansionTile(String reasoning) {
  return ExpansionTile(
    tilePadding: EdgeInsets.zero,
    dense: true,
    title: Row(children: [
      Icon(Icons.psychology_outlined, size: 16),
      SizedBox(width: 4),
      Text('AI 推理过程', style: bodySmall),
    ]),
    children: [
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text(reasoning, style: bodySmall.copyWith(fontSize: 11)),
      ),
    ],
  );
}

bool _isAiValid(VisionRecognitionResult dish, NutritionResult aiFallback) {
  final mid = dish.estimatedWeightGMid;
  if (mid <= 0) return false;
  final aiPer100 = aiFallback.calories * 100 / mid;
  return aiPer100 >= 0 && aiPer100 <= 900;
}
```

#### TDD Step 4: Verify GREEN

```bash
flutter test test/features/multi_dish_page_test.dart
```
**预期**：5 个新测试通过 + 原有 8 个测试保持 green。

#### TDD Step 5: REFACTOR

- 提取重复的 `mid > 0 ? aiFallback.calories * 100 / mid : 0.0` 为辅助方法
- 检查 `_isAiValid` 是否可复用 `CalibratedNutritionCalculator` 内部逻辑（避免重复 sanity check 阈值）

---

### Task 3: offline_queue_controller 复合菜命中分支集成测试

**目标**：验证 offline_queue_controller 改造后行为与 multi_dish_page 一致。

**文件**：
- 修改：`test/features/offline_queue_composite_test.dart`（追加）

#### TDD Step 1: RED - 写失败测试

新增 3 个测试：
1. `offline_queue 复合菜命中 + AI 有效 → 用 AI 整菜估算（与 multi_dish_page 一致）`
   - 输入：复合菜组分部分命中，AI estimatedCalories=500, mid=200（per100g=250 有效）
   - 期望：meal_log.actualCalories=500，food_item.caloriesPer100g=0
2. `offline_queue 复合菜命中 + AI 离谱 → 用组分累加库值兜底`
   - 输入：复合菜组分部分命中，AI estimatedCalories=2000, mid=200（per100g=1000 离谱）
   - 期望：meal_log.actualCalories=composite.calories（组分累加），food_item.caloriesPer100g=0
3. `offline_queue 复合菜命中 + AI 无估算 → 用组分累加（向后兼容旧 prompt）`
   - 输入：复合菜组分部分命中，AI estimatedCalories=null
   - 期望：meal_log.actualCalories=composite.calories（原行为不变）

#### TDD Step 2-5: Verify RED → GREEN → REFACTOR

```bash
flutter test test/features/offline_queue_composite_test.dart
```

---

### Task 4: 全量回归 + 发布

#### Step 1: 全量测试

```bash
cd /workspace && export PATH=/tmp/flutter/bin:$PATH
flutter analyze
flutter test --exclude-tags smoke
```
**预期**：
- flutter analyze: No issues found
- 所有测试通过（含 M18 新增 12 个测试 + 原有全部测试）

#### Step 2: 6 条硬约束复检

```bash
grep -E "isMinifyEnabled|isShrinkResources" android/app/build.gradle.kts
# 期望: isMinifyEnabled = false + isShrinkResources = false
grep -r "foodItemId.*=.*0" lib/features/recognize/ lib/features/offline/ | grep -v "upsertAiRecognized"
# 期望: 无输出（哨兵 0 都有 upsertAiRecognized 替换）
```

#### Step 3: bump 版本

`pubspec.yaml`: `0.18.9+28` → `0.19.0+29`（M18 是新功能，跳 minor 版本）

#### Step 4: HANDOFF.md 回填 M18 章节

在 M17 章节后、`## 3. 关键架构决策` 前插入 M18 章节，内容包含：
- 触发：用户反馈多菜场景无 AI 推理过程 + 精度存疑
- 核心决策：AI 可见性 + 三路径一致性 + 完整 AI 估算卡片
- 4 个 Task 实现（含 TDD Red-Green-Refactor）
- 核心不变量更新（复合菜三路径统一调用 CalibratedNutritionCalculator.computeCompositeLookupHit）
- 用户感知变化（multi_dish_page 新增 AI 估算卡片）

#### Step 5: 严肃 commit + push + tag v0.19.0

```bash
git add lib/features/recognize/multi_dish_page.dart \
  lib/features/recognize/calibrated_nutrition_calculator.dart \
  lib/features/offline/offline_queue_controller.dart \
  test/features/multi_dish_page_test.dart \
  test/features/calibrated_nutrition_calculator_test.dart \
  test/features/offline_queue_composite_test.dart \
  pubspec.yaml HANDOFF.md \
  .trae/documents/m18-multi-dish-ai-visibility-three-path-consistency.md

git commit -m "M18: 多菜场景 AI 推理可见性 + 三路径一致性（v0.19.0）

用户反馈多菜场景无 AI 推理过程，精度存疑。本次改进：
1. multi_dish_page 新增完整 AI 估算卡片（reasoning + confidence + source badge + AI vs 库值对比）
2. 抽取复合菜 AI 优先逻辑为 CalibratedNutritionCalculator.computeCompositeLookupHit
3. offline_queue_controller 复合菜命中分支接入 AI 差异检测，三路径统一

TDD: 12 个新测试（4 calculator + 5 UI + 3 offline_queue）Red-Green-Refactor
bump 0.18.9+28 → 0.19.0+29 + HANDOFF M18 章节。"

git push origin trae/agent-wX1X6Q
git tag v0.19.0
git push origin v0.19.0
```

#### Step 6: 验证发布

```bash
git log --oneline -5
git tag -l 'v0.19.*'
git ls-remote --tags origin v0.19.0
```

---

## Assumptions & Decisions

### 决策 1：抽取复合菜 AI 优先逻辑为静态方法（非扩展 CalibratedNutritionCalculator.compute）
- **理由**：复合菜与单品的 CalibratedNutrition 结构不同（复合菜 per100g=0 占位，不更新库），强行合并到 compute 会让签名复杂化
- **方案**：新增独立静态方法 `computeCompositeLookupHit`，返回 nullable（AI 无效时返回 null 让调用方走兜底）

### 决策 2：multi_dish_page 保留 `_computeCompositeLookupHitCalibrated` 包装方法
- **理由**：避免改动调用方（_calcNutrition 和 _recordAll 多处调用），内部委托给静态方法
- **REFACTOR 阶段**评估是否内联

### 决策 3：offline_queue_controller 复合菜命中分支保留原组分累加兜底
- **理由**：AI 无效时（per100g>900 或 mid=0）必须回退到原逻辑，避免破坏向后兼容
- **AI 估算为 null 时**（旧 prompt）也走原逻辑，保持向后兼容

### 决策 4：AI 估算卡片默认折叠 reasoning
- **理由**：与 calibration_page 风格一致；reasoning 文本较长，默认展开会占满屏幕影响份量调整
- **置信度 + 来源徽章 + AI vs 库值对比**始终显示（关键信息不藏起来）

### 决策 5：版本号跳 v0.19.0（非 v0.18.10）
- **理由**：M18 是新功能（AI 可见性 + 三路径统一），非 bug fix，跳 minor 版本标志新里程碑

### 假设
1. `dish.reasoning` 字段在 v1.9+ prompt 下必有值；旧 prompt 数据可能为 null（已兜底）
2. `dish.confidence` 字段始终有值（VisionRecognitionResult.fromJson 兜底默认 0.0）
3. offline_queue_controller 改造后，原有 "无包装 / 包装换算宏量全 0 → 组分累加" 分支保留作为 AI 无效兜底
4. TDD 测试用 mock data，不依赖真实 AI 调用

---

## Verification Steps

### 1. Task 1 验证（复合菜逻辑抽取）
- [ ] `calibrated_nutrition_calculator_test.dart` 4 个新测试通过
- [ ] `multi_dish_page_test.dart` 原有 8 个测试保持 green（_computeCompositeLookupHitCalibrated 委托后行为不变）
- [ ] `offline_queue_composite_test.dart` 原有测试保持 green

### 2. Task 2 验证（AI 估算卡片 UI）
- [ ] `multi_dish_page_test.dart` 5 个新 UI 测试通过
- [ ] 原有 8 个测试保持 green（UI 追加不破坏现有断言）
- [ ] 手动验证（如有条件）：AI 估算卡片在命中/未命中/查库命中/AI 兜底四种场景下正确渲染

### 3. Task 3 验证（offline_queue 一致性）
- [ ] `offline_queue_composite_test.dart` 3 个新测试通过
- [ ] 验证 offline_queue 与 multi_dish_page 在相同输入下产出相同 meal_log.actualCalories

### 4. Task 4 验证（全量回归 + 发布）
- [ ] `flutter analyze` No issues found
- [ ] `flutter test --exclude-tags smoke` 全部通过
- [ ] 6 条硬约束复检通过
- [ ] commit + push + tag v0.19.0 成功
- [ ] HANDOFF.md M18 章节回填

---

## Self-Review

### 1. Spec coverage（用户诉求 → 计划覆盖）
- ✅ "没有 AI 推理的过程" → Task 2 reasoning 折叠面板
- ✅ "精准度我也有一定程度的怀疑" → Task 2 AI vs 库值对比行 + source badge 标明数据来源
- ✅ "是不是正确安装 AI 的计算提交并且显示的" → Task 1+3 三路径统一保证提交一致 + Task 2 显示让用户验证
- ✅ "希望还能继续改进，严谨仔细，一定不能出问题" → 严格 TDD（12 个新测试 Red-Green-Refactor）+ 全量回归 + 6 硬约束复检

### 2. 风险评估
- **风险 1**：offline_queue_controller 改造破坏现有后台回补行为
  - 缓解：Task 3 专门针对 offline_queue 写 3 个集成测试 + 保留原组分累加兜底
- **风险 2**：UI 改动破坏现有 multi_dish_page_test 断言
  - 缓解：Task 2 Step 4 验证原有 8 个测试保持 green；UI 追加在营养素行后，不改原有结构
- **风险 3**：AI vs 库值对比行计算 mid<=0 时崩溃
  - 缓解：`_buildAiVsDbComparison` 内 `if (mid <= 0) return SizedBox.shrink()`
- **风险 4**：reasoning 文本过长影响 UI 布局
  - 缓解：ExpansionTile 默认折叠 + 展开 inner Text 不限高（与 calibration_page 一致）

### 3. 不做的事
- 不改 meal_log schema（不持久化 reasoning，避免 drift 迁移）
- 不改 today_meals_page（事后回顾留待未来里程碑）
- 不改 recognize_page 复合菜路径（writeCalibratedMealLog L143-163 仅创建 food_item，无差异检测需求）
- 不动 Android 资源层（硬约束 #1）
- 不改 AI prompt（v1.10 已足够，本次是显示层 + 三路径统一）
