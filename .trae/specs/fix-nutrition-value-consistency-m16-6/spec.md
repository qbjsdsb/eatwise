# 营养数值一致性修复 Spec（M16.6）

## Why

用户反馈"AI 推理出来，显示完整推理过程计算出来的数值，和最后显示的，被记录的都不一样"。经深度排查，根因是三条识别路径（前台单品 / 一桌多菜 / 后台回补）在 AI 兜底哨兵路径下，`meal_log.actualCalories` 计算方式不一致：

- `offline_queue_controller.dart` L300-307：用**品类校准后**的 per100g 重新计算 actualCalories（`caloriesPer100g * mid / 100`），与食物库 per100g 一致
- `recognize_page.dart` L412-425：直接用 onConfirm 传入的 calories（**未校准**，来自 `_aiFallbackNutrition` 的 `r.estimatedCalories`）
- `multi_dish_page.dart` L583/662：同 recognize_page，用未校准值

后果（以啤酒为例，AI 离谱估算 200 kcal/100g，mid=300g）：
1. 推理过程显示：AI estimatedCalories = 600 kcal
2. CalibrationPage 显示：600 * ratio（基于 _aiFallbackNutrition 的 600，未校准）
3. 写入食物库 per100g：FoodCategoryDefaults.calibrate 校准为 43（beer 品类默认值）
4. meal_log.actualCalories：600（未校准，与食物库 per100g=43 脱节）
5. 下次再吃同款啤酒查库命中：43 * 300/100 = 129 kcal（与首次 600 差异巨大，用户感知"数值乱跳"）

## What Changes

- **统一三条路径的 actualCalories 计算逻辑**：AI 兜底哨兵路径（foodItemId=0）下，actualCalories 用**品类校准后**的 per100g 重新计算（`caloriesPer100g * servingG / 100`），与食物库 per100g 保持一致
- **同步 actualProteinG / actualFatG / actualCarbsG**：宏量也用校准后的 per100g 重新计算（与 actualCalories 一致，避免宏量与热量脱节）
- **CalibrationPage 单品哨兵路径预览同步**：`_confirmWithServing` 在单品 AI 兜底（foodItemId=0）路径下，传给 onConfirm 的 calories/protein/fat/carbs 也用校准后的 per100g 计算，让"显示预览"与"记录值"完全一致
- **包装 OCR 路径保持不变**：包装数据是精确值，不走品类校准，actualCalories 用 `packagePer100 * servingG / 100`（已是当前实现，无需改）

### 不在本次修复范围
- 查库命中路径（foodItemId > 0）：actualCalories 已基于数据库 per100g 计算，无脱节问题
- 复合菜路径：actualCalories 基于组分累加，无品类校准（复合菜无 meaningful food category）
- 推理过程文本（reasoning）显示：文本是 AI 自由描述，不与数值绑定，本次不动

## Impact

- **Affected specs**: 无（本次是 bug 修复，不涉及能力变更）
- **Affected code**:
  - `lib/features/recognize/recognize_page.dart`：onConfirm 回调 L299-432，AI 兜底哨兵分支（n.foodItemId == 0）
  - `lib/features/recognize/multi_dish_page.dart`：`_recordAll` L493-672，`resolveSingleFoodItemId` + insertMealLog
  - `lib/features/recognize/calibration_page.dart`：`_confirmWithServing` L662-731，单品 AI 兜底预览与 onConfirm 传值
  - `lib/features/offline/offline_queue_controller.dart`：L158-392（参考实现，行为已正确，本次不改动）
  - `lib/data/seed/food_category_defaults.dart`：`calibrate` 方法（不改动，仅复用）
- **影响范围**：仅 AI 兜底哨兵路径（foodItemId=0，库未命中 + AI 估算兜底）。查库命中 / 复合菜 / 包装 OCR 路径不受影响
- **向后兼容**：已记录的历史 meal_log 数据不迁移（脱节的历史数据保留，避免影响用户已有记录）。修复后新记录的 actualCalories 与食物库 per100g 一致

## ADDED Requirements

### Requirement: 三路径 actualCalories 计算一致性

AI 兜底哨兵路径（foodItemId=0）下，三条识别路径（前台单品 / 一桌多菜 / 后台回补）的 `meal_log.actualCalories` 计算方式必须一致：用品类校准后的 per100g 重新计算。

#### Scenario: 前台单品识别（recognize_page）AI 兜底哨兵路径
- **WHEN** 用户拍照识别"啤酒"，AI 估算 estimatedCalories=600（per100g=200，mid=300），foodCategory='beer'，库未命中
- **AND** 用户在 CalibrationPage 不调整滑块直接确认（servingG=mid=300）
- **THEN** FoodCategoryDefaults.calibrate 校准 per100g 从 200 → 43（beer 默认值，200 > 43*2 触发校准）
- **AND** 写入食物库 per100g = 43
- **AND** meal_log.actualCalories = 43 * 300 / 100 = 129（与食物库 per100g 一致，非 600）

#### Scenario: 一桌多菜识别（multi_dish_page）AI 兜底哨兵路径
- **WHEN** 一桌多菜场景，附加菜"啤酒"走 AI 兜底哨兵路径
- **AND** 用户点"全部记录"
- **THEN** beer 品类校准 per100g 从 200 → 43
- **AND** 写入食物库 per100g = 43
- **AND** meal_log.actualCalories = 43 * servingG / 100（与前台单品路径一致）

#### Scenario: 后台回补（offline_queue_controller）AI 兜底哨兵路径
- **WHEN** 离线队列回补识别"啤酒"走 AI 兜底哨兵路径
- **THEN** 行为与前台单品路径完全一致（已正确实现，本次修复后前台与后台对齐）

### Requirement: CalibrationPage 预览与记录值一致

AI 兜底哨兵路径下，CalibrationPage 的 `_buildNutritionPreview` 显示值与 onConfirm 传入的记录值必须完全一致。

#### Scenario: 用户调整滑块后预览与记录一致
- **WHEN** 用户在 CalibrationPage 调整滑块到 servingG=200（mid=300）
- **THEN** 预览显示：校准后 per100g * 200 / 100
- **AND** 点确认后 onConfirm 传入：校准后 per100g * 200 / 100（与预览一致）

### Requirement: 宏量与热量同步校准

AI 兜底哨兵路径下，actualProteinG / actualFatG / actualCarbsG 也用校准后的 per100g 重新计算，避免宏量与热量脱节。

#### Scenario: 啤酒校准后宏量同步
- **WHEN** beer 品类校准 per100g 从 200 → 43（calories 校准）
- **THEN** protein/fat/carbs per100g 保留 AI 值（FoodCategoryDefaults.calibrate 当前行为，仅校准 calories）
- **AND** actualProteinG = AI proteinPer100g * servingG / 100（未校准，但与 per100g 写库值一致）

注：FoodCategoryDefaults.calibrate 当前仅校准 calories（品类默认值表只有 calories），宏量保留 AI 值。本次修复不改变 calibrate 行为，只确保 actualMacros 用同一个 per100g 计算。

## MODIFIED Requirements

### Requirement: AI 兜底哨兵路径 actualCalories 计算

**修改前**：
- recognize_page / multi_dish_page：actualCalories = onConfirm 传入的 calories（来自 _aiFallbackNutrition 的 r.estimatedCalories，未校准）
- offline_queue_controller：actualCalories = 校准后 per100g * mid / 100

**修改后**（三路径统一）：
- 三路径：actualCalories = 校准后 per100g * servingG / 100
- servingG 在前台 = 用户调整后的滑块值；在后台 = AI mid（无用户交互）

## REMOVED Requirements

无（本次是 bug 修复，不删除现有能力）
