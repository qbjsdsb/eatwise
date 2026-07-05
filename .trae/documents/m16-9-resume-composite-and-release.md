# M16.9 续作——复合菜 _recordAll 收尾 + 发布（Task 3-7）

> **背景**：M16.9 已完成 Task 1-2（commit `addb10e`，calibrated_nutrition_calculator 查库命中分支重写为 AI 绝对优先 + 4 个新单元测试 + 1 个集成测试更新，40 测试全过）。Task 3-4 进行中：`_computeCompositeLookupHitCalibrated` 方法已添加（multi_dish_page.dart L379-413），`_calcNutrition` 两处 composite 分支已修改（L514-523 主菜 / L555-564 附加菜）。本 plan 处理剩余 Task 3-7。

**Goal**：完成 M16.9 剩余工作——(1) `_recordAll` composite 分支接入 AI 优先覆盖 cal/p/f/c；(2) 写复合菜 RED 测试 + commit Task 3-4；(3) calibration_page 残留 else 分支加注释；(4) 全量回归验证；(5) bump 0.18.8+27 + HANDOFF 回填 + 严肃 commit + push + tag v0.18.8。

**Tech Stack**：Flutter 3.x / Riverpod / Drift / TDD（RED→GREEN）

---

## 当前实际状态（Phase 1 探索确认）

### 已完成（commit `addb10e`）
- `lib/features/recognize/calibrated_nutrition_calculator.dart` L48-104：查库命中分支重写为 AI 绝对优先 + sanity check 兜底
- `test/features/calibrated_nutrition_calculator_test.dart`：4 个新测试（AI 偏差小也用 AI / 一致不写库 / per100g>900 兜底 / 负值兜底）
- `test/features/recognize_page_test.dart` L278-355：M16.9 集成测试（actualCalories=170, food_item.caloriesPer100g=85）

### Task 3-4 已完成部分（未 commit，工作区已修改）
- `lib/features/recognize/multi_dish_page.dart` L379-413：新增 `_computeCompositeLookupHitCalibrated` 方法
  - 包装营养表优先返回 null
  - composite + aiFallback 必须非空
  - sanity check：AI per100g ∈ [0, 900]，无效返回 null
  - AI 有效时返回 `CalibratedNutrition(caloriesPer100g:0, actualXxx: aiFallback.* × ratio, shouldUpdateFoodItem: false)`
- `lib/features/recognize/multi_dish_page.dart` L514-523（主菜）+ L555-564（附加菜）：`_calcNutrition` composite 分支前置 `_computeCompositeLookupHitCalibrated` 检查

### Task 3-4 剩余（本 plan 处理）
- `lib/features/recognize/multi_dish_page.dart` L715-752 `_recordAll` composite 分支：**尚未接入 AI 优先**
  - 当前逻辑（L715 `else if (composite != null)`）：直接 upsertAiRecognized，cal/p/f/c 仍是 `_calcNutrition` 返回值（已含 AI 优先，但需显式覆盖确保预览=记录）
  - 实际：因 `_calcNutrition` 已走 AI 优先，`var (cal, p, f, c) = _calcNutrition(i, dish)`（L650）已携带 AI 值，composite 分支不覆盖也正确。但为语义清晰 + 与单品查库命中分支（L688-714 显式覆盖）保持一致，应显式覆盖。
- RED 测试：`test/features/multi_dish_page_test.dart` 新增复合菜 AI 优先测试

### Task 5/6/7 待执行
- Task 5：`lib/features/recognize/calibration_page.dart` L465-474 残留 else 分支加注释
- Task 6：flutter analyze + flutter test 全量
- Task 7：pubspec.yaml bump 0.18.7+26 → 0.18.8+27 + HANDOFF M16.9 章节 + commit + push + tag v0.18.8

---

## Proposed Changes

### 决策

| 决策点 | 选择 | 理由 |
|--------|------|------|
| `_recordAll` composite 分支是否显式覆盖 cal/p/f/c | 是，显式调用 `_computeCompositeLookupHitCalibrated` 覆盖 | 与单品查库命中分支（L688-714）语义一致；保证预览=记录不变量；防未来 `_calcNutrition` 改动导致脱节 |
| RED 测试形式 | widget test（pump MultiDishPage + 点击记录按钮） | 验证端到端复合菜 AI 优先；参考现有 multi_dish_page_test.dart 复合菜测试结构 |
| 复合菜 RED 测试若 setup 过于复杂 | 降级为对 `_computeCompositeLookupHitCalibrated` 的单元测试（需提取为顶层函数或暴露测试入口） | 保证 TDD RED 阶段可执行 |
| sanity check 阈值 | AI per100g ∈ [0, 900]（与 Task 2 一致） | 上限 900 = 纯脂肪油 889 + solid clamp 上限 |
| shouldUpdateFoodItem（复合菜） | 始终 false | 复合菜 per100g=0 占位，不更新库 |

---

## Task 3: RED 测试 — 复合菜分支接入 AI 绝对优先

**Files:**
- Test: `test/features/multi_dish_page_test.dart`

- [ ] **Step 1: 读取现有 multi_dish_page_test.dart 复合菜测试结构**

Run: 读 `test/features/multi_dish_page_test.dart` 找到现有复合菜测试（lookupCompositeDish mock + widget pump + 点击"全部记录"按钮的 setup），作为新测试的模板。

- [ ] **Step 2: 新增复合菜 AI 优先测试**

在 `test/features/multi_dish_page_test.dart` 末尾追加测试。两种形式按现有测试复杂度选择：

**形式 A（widget test，优先）**：
```dart
  testWidgets('M16.9: 复合菜查库命中 + AI 整菜估算有效时用 AI 值记录', (tester) async {
    // 复合菜 lookupCompositeDish 返回组分累加库值（如米饭+宫保鸡丁=400 kcal，mid=200g）
    // AI 整菜估算 estimatedCalories=500（per100g=250，有效区间内，偏差 25%）
    // 期望：meal_log.actualCalories=500（AI 整菜估算），food_item.caloriesPer100g=0（复合菜占位不更新）
    // ... 完整 setup（参考现有复合菜测试）
    // 关键断言：
    // expect(mealLog.actualCalories, closeTo(500, 0.5), reason: '复合菜 AI 绝对优先：用 AI 整菜估算');
    // expect(foodItem.caloriesPer100g, 0, reason: '复合菜 per100g 保持 0 占位');
  });
```

**形式 B（降级单元测试，若 widget setup 过于复杂）**：
- 提取 `_computeCompositeLookupHitCalibrated` 为顶层函数或 `@visibleForTesting` 静态方法
- 直接调用验证 AI 有效返回 AI 值、AI 无效返回 null

- [ ] **Step 3: 运行测试验证失败**

Run: `export PATH=/tmp/flutter/bin:$PATH && flutter test test/features/multi_dish_page_test.dart`
Expected: FAIL — 当前 `_recordAll` composite 分支未显式覆盖 cal/p/f/c（虽然 `_calcNutrition` 已走 AI 优先，但测试断言 meal_log.actualCalories 应能通过；若 FAIL 说明 `_recordAll` 未显式覆盖确实导致脱节，否则 RED 需调整为更严格的断言）

注：若 RED 测试已通过（因 `_calcNutrition` 已走 AI 优先），说明 `_recordAll` 显式覆盖是"防御性清晰化"而非"修复 bug"。此时 RED 阶段可标记为"已 GREEN"，直接进入 Task 4 显式覆盖 + 重新验证。

---

## Task 4: GREEN — _recordAll composite 分支显式覆盖 AI 优先

**Files:**
- Modify: `lib/features/recognize/multi_dish_page.dart` L715-752

- [ ] **Step 1: 在 `_recordAll` composite 分支插入 AI 优先覆盖**

读 `lib/features/recognize/multi_dish_page.dart` L715-752，在 `else if (composite != null)` 块内、`final packagePer100 = ...` 之前插入 AI 优先覆盖：

```dart
          } else if (composite != null) {
            // M16.9：复合菜查库命中 + AI 整菜估算 → AI 绝对优先
            // 显式覆盖 cal/p/f/c，与 _calcNutrition 保持一致（预览=记录）
            final compositeCalibrated = _computeCompositeLookupHitCalibrated(i, dish, serving);
            if (compositeCalibrated != null) {
              cal = compositeCalibrated.actualCalories;
              p = compositeCalibrated.actualProteinG;
              f = compositeCalibrated.actualFatG;
              c = compositeCalibrated.actualCarbsG;
            }
            final oilG = composite.oilG;
            componentsSnapshot = _encodeComponents(dish, oilG: oilG);
            // v1.9：复合菜有包装营养表数据时...（保留原 packagePer100 逻辑）
            final packagePer100 = dish.hasPackageNutrition
                ? dish.computePackageNutritionPer100g(...)
                : null;
            // ... 保留原 upsertAiRecognized 调用
          }
```

**注意**：`_computeCompositeLookupHitCalibrated` 内部已检查 `dish.hasPackageNutrition` 优先返回 null，所以包装路径不会冲突；composite 分支的 upsertAiRecognized 仍按原逻辑（packagePer100 或 0 占位）写库 per100g，AI 优先只覆盖 cal/p/f/c（meal_log 值），不冲突。

- [ ] **Step 2: 运行测试验证通过**

Run: `flutter test test/features/multi_dish_page_test.dart`
Expected: PASS

- [ ] **Step 3: 运行相关测试套件无回归**

Run: `flutter test test/features/multi_dish_page_test.dart test/features/recognize_page_test.dart test/features/offline_queue_test.dart test/features/calibrated_nutrition_calculator_test.dart`
Expected: All passed

- [ ] **Step 4: Commit Task 3-4**

```bash
git add lib/features/recognize/multi_dish_page.dart test/features/multi_dish_page_test.dart
git commit -m "M16.9: 复合菜分支接入 AI 绝对优先

复合菜 lookupCompositeDish 返回组分累加库值，原 M16.8 无差异检测，
AI 整菜估算（r.estimatedCalories）完全被丢弃。

修复：
- 新增 _computeCompositeLookupHitCalibrated：复合菜查库命中 + AI 有效时
  用 AI 整菜估算记 meal_log（不更新库 per100g，复合菜 per100g=0 占位）
- _calcNutrition + _recordAll 复合菜分支调用新方法
- AI 无效时返回 null，调用方走原 ratio 兜底（组分累加库值）

sanity check：AI per100g > 900 或 < 0 视为离谱，用组分累加库值兜底。"
```

---

## Task 5: calibration_page 残留路径加注释

**Files:**
- Modify: `lib/features/recognize/calibration_page.dart` L465-474

- [ ] **Step 1: 加注释说明此路径不应触发**

读 `lib/features/recognize/calibration_page.dart` L465-474，更新注释（不改逻辑）：

```dart
    // M16.9：查库命中但无 aiFallback——此分支在 M16.8 后不应触发
    // （主路径 recognize_page L466-467 / L663-664 已传 aiFallbackNutrition）
    // 兜底：按 servingG/mid 比例换算库值（保留原 ratio 逻辑）
    // 防除零：AI 返回 estimatedWeightGMid <= 0 时 ratio=1（用原值，不按比例换算）
    // 若未来有调用方未传 aiFallbackNutrition，此处仍是安全兜底
    final mid = r.estimatedWeightGMid;
    final ratio = mid > 0 ? servingG / mid : 1.0;
    return (
      n.calories * ratio,
      n.proteinG * ratio,
      n.fatG * ratio,
      n.carbsG * ratio,
    );
```

- [ ] **Step 2: Commit Task 5**

```bash
git add lib/features/recognize/calibration_page.dart
git commit -m "M16.9: calibration_page 残留 else 分支加注释说明

M16.8 主路径已传 aiFallbackNutrition，此 else 分支不应触发。
保留原 ratio 兜底逻辑作为安全网，加注释说明。不改逻辑。"
```

---

## Task 6: 全量回归验证

**Files:**
- 无修改，仅验证

- [ ] **Step 1: flutter analyze**

Run: `export PATH=/tmp/flutter/bin:$PATH && flutter analyze`
Expected: No issues found

- [ ] **Step 2: flutter test 全量**

Run: `flutter test --exclude-tags smoke`
Expected: All tests passed（923 + M16.9 新增测试）

- [ ] **Step 3: 验证 6 条硬约束**

1. `android/app/build.gradle.kts` `isMinifyEnabled=false` + `isShrinkResources=false` 未变
2. meal_log.food_item_id 哨兵写库前调 upsertAiRecognized（M16.9 查库命中分支 foodItemId > 0 不需 upsert）
3. AI 兜底三路径全覆盖（recognize_page / multi_dish_page / offline_queue_controller 都用 CalibratedNutritionCalculator）
4. per100g 反算基于 estimatedWeightGMid（calculator 内部 `mid = r.estimatedWeightGMid`）
5. SecureConfigStore 无 instance 静态属性
6. initSentryAndRunApp 命名参数

- [ ] **Step 4: 验证 M16.2~M16.8 修复区域无回归**

确认相关测试全过：calibrated_nutrition_calculator_test / recognize_page_test / multi_dish_page_test / calibration_page_test / offline_queue_test / food_category_defaults_test / food_item_repository_update_per100g_test

---

## Task 7: 发布准备（严肃 commit + push + tag v0.18.8）

**Files:**
- Modify: `pubspec.yaml`
- Modify: `HANDOFF.md`

- [ ] **Step 1: bump 版本**

`pubspec.yaml` L4: `0.18.7+26` → `0.18.8+27`

- [ ] **Step 2: 更新 HANDOFF.md**

更新第 2 节"当前状态"（HEAD / 待 push commit / tag v0.18.8）+ 新增 M16.9 章节（参考 M16.8 章节结构）：
- 触发：用户要求"把库值在这个项目中的重要性占比减小很多"
- 策略：AI 绝对优先（查库命中分支重写）+ 复合菜残留路径同步修复
- 核心改动：calibrated_nutrition_calculator 查库命中分支 AI 绝对优先 + sanity check 兜底
- 复合菜：_computeCompositeLookupHitCalibrated 新方法
- 验证：flutter analyze No issues + flutter test 全过 + 6 条硬约束满足
- 待用户执行：装 v0.18.8 APK 验证

- [ ] **Step 3: 严肃 commit**

```bash
git add pubspec.yaml HANDOFF.md
git commit -m "M16.9: 减小库值重要性——AI 绝对优先（v0.18.8）—— 查库命中分支重写 + 复合菜残留路径修复

用户要求"把库值在这个项目中的重要性占比减小很多"。

核心改动：
- 查库命中分支（foodItemId>0）改为 AI 估算绝对优先
  - AI 有效（per100g ∈ [0, 900]）时始终用 AI 反算 per100g 写库 + 用 AI 值记 meal_log
  - AI 无效（null/负/>900）时用库值兜底（不更新库）
  - shouldUpdateFoodItem：diffRatio > 5% 时为 true（避免无意义写库）
- 复合菜分支（multi_dish_page composite）接入 AI 绝对优先
  - 新增 _computeCompositeLookupHitCalibrated
  - AI 整菜估算有效时用 AI 值记 meal_log（不更新库 per100g，复合菜 per100g=0 占位）
- calibration_page 残留 else 分支加注释说明（M16.8 后不应触发）

库值重要性大幅降低：从'偏差 ≤ 50% 用库值'降级为'仅 AI 离谱时兜底'。
三路径（recognize_page/multi_dish_page/offline_queue）共用 calculator 自动继承新逻辑。

验证：flutter analyze No issues + flutter test 全过；
6 条硬约束全部满足；M16.2~M16.8 修复区域无回归。

bump 0.18.7+26 → 0.18.8+27 + HANDOFF 回填 M16.9 章节。"
```

- [ ] **Step 4: 严肃 push**

```bash
git push origin trae/agent-wX1X6Q
```

- [ ] **Step 5: 严肃打 tag + push tag**

```bash
git tag v0.18.8
git push origin v0.18.8
```

- [ ] **Step 6: 验证 push 成功**

Run: `git log --oneline -5 && git tag -l v0.18.*`
Expected: 看到 v0.18.8 tag + 最新 commit 在 origin/trae/agent-wX1X6Q

---

## Assumptions & Decisions

### 决策 1：_recordAll composite 分支显式覆盖（非必需但推荐）
- **现状**：`_calcNutrition` 已走 AI 优先，`var (cal, p, f, c) = _calcNutrition(i, dish)`（L650）已携带 AI 值
- **决策**：仍显式调用 `_computeCompositeLookupHitCalibrated` 覆盖 cal/p/f/c
- **理由**：与单品查库命中分支（L688-714 显式覆盖）语义一致；防未来 `_calcNutrition` 改动导致预览≠记录；代码可读性

### 决策 2：复合菜 RED 测试形式按复杂度选择
- 优先 widget test（端到端验证）；若 setup 过于复杂降级为单元测试
- 不强求 widget test，避免过度工程

### 决策 3：offline_queue L212-219（无 AI 估算旧 prompt）保留不动
- 旧 prompt v1.4 之前兼容分支，新 prompt 不走
- 保留原 ratio 逻辑

### 假设
1. AI 估算（r.estimatedCalories）在 prompt v1.9+ 始终存在
2. 复合菜 AI 整菜估算与组分累加库值可比较（都对应 mid 份量整菜热量）
3. 三路径调用方已正确传入 aiFallbackNutrition（M16.8 已修复主路径）

---

## Verification Steps

1. **Task 3-4 单元/集成测试**：`flutter test test/features/multi_dish_page_test.dart`
   - 复合菜 AI 优先 ✅
   - 复合菜 AI 无效兜底 ✅

2. **Task 6 全量回归**：`flutter test --exclude-tags smoke`
   - 923+ 测试全过 ✅
   - M16.2~M16.8 修复区域无回归 ✅

3. **Task 6 静态分析**：`flutter analyze`
   - No issues found ✅

4. **Task 6 硬约束**：6 条全部满足 ✅

5. **Task 7 发布**：commit + push + tag v0.18.8 ✅

---

## Self-Review

### 1. Spec coverage
- ✅ 减小库值重要性：Task 2 已完成（commit addb10e）
- ✅ 复合菜残留路径同步修复：Task 4 _recordAll 显式覆盖
- ✅ 严肃 commit + push + tag：Task 7 完整发布流程
- ✅ 仔细：每步验证 + 全量回归 + 6 条硬约束

### 2. 风险评估
- **风险 1**：_recordAll 显式覆盖可能与 _calcNutrition 已走 AI 优先重复
  - 缓解：显式覆盖是防御性清晰化，不改变行为；测试验证一致性
- **风险 2**：复合菜 widget test setup 复杂
  - 缓解：降级为单元测试（形式 B）
- **风险 3**：push 失败（网络/权限）
  - 缓解：Task 7 Step 6 验证，失败重试
