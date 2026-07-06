# 重构拍照识别：AI 绝对优先 + 严谨验证（检测不修改）+ 用户手动兜底

## 摘要

用户报告"AI 推理和最后显示的内容不一样"，要求重构让 AI 优先级最高，库作为最后保底。Phase 1 探索发现：当前架构 M18+M25 后**已是 AI 优先**（库值优先仅剩 1 处：AI per100g>900 兜底），真正的不一致根因是 **6 处静默改写 AI 值的代码点**（Atwater 修正、宏量反推、AI 离谱兜底等）。

用户最新指令澄清方向：**"兜底也用 AI，进行严谨的验证，但是最后用户可以手动修改"**。即：
1. AI 估算值绝对不被静默修改（删除所有 correctedXxx 覆盖逻辑）
2. 保留严谨验证，但改为**检测+提示**而非**修改值**（输出 warnings 列表）
3. 用户作为最终兜底：UI 显示警告 + 增加手动编辑营养值入口
4. 库仅作 sanity check 标记，不覆盖 AI 值

重构范围：**最小改动**（保留三路径架构 + CalibratedNutritionCalculator 收敛层），只删除覆盖 AI 的代码 + 新增 warnings + UI 手动编辑。

## 当前状态分析

### 已是 AI 优先的部分（保留）
- 查库命中 + AI 有效：始终用 AI 反算 per100g 写库（`calibrated_nutrition_calculator.dart:89-107`）
- shouldUpdateFoodItem 阈值 >0（M18，让 AI 持续纠正库）
- 品类校准已废弃（M25 方案 D，`food_category_defaults.dart:104-120` 只剩物理 clamp）
- 三路径收敛（CalibratedNutritionCalculator + RecognitionPostProcessor 公共方法）

### "AI 推理与显示不一致"的 6 处根因（本次要改）

| # | 文件:行号 | 改写内容 | 触发条件 | 用户感知 |
|---|---|---|---|---|
| 1 | `recognition_validator.dart:119-138` | cal 改为 4p+9f+4c | 偏差>10% 且非酒精 | reasoning 显示 400，记录 481 |
| 2 | `recognition_validator.dart:81-101` | 宏量按品类默认比例填充 | cal>0 但宏量缺失 | reasoning 显示缺失，记录是品类猜测值 |
| 3 | `recognition_validator.dart:116-118` | cal 改为 4p+9f+4c | cal≤0 但 expected>0 | reasoning 显示 0，记录是宏量反推值 |
| 4 | `calibrated_nutrition_calculator.dart:71-87` | 用库值替代 AI | AI per100g>900 | reasoning 显示 5000，记录是库值 |
| 5 | `calibrated_nutrition_calculator.dart:189-190` | 返回 null 走 ratio 兜底 | 复合菜 AI per100g>900 | 同上 |
| 6 | `calibration_page.dart:491-505` 复合菜预览 | 组分累加 vs AI 优先 | 复合菜场景 | 校准页与多菜页数值不同 |

### 历史根因（已修复，本次不涉及）
- 米粉汤 526→171 bug：M25 方案 D 已废弃品类校准覆盖（`food_category_defaults.dart:104-120`）

## 提议改动

### 改动 A：删除 Atwater 修正 + 宏量反推（validator 静默改写）

**文件**：`lib/core/util/recognition_validator.dart`

**改什么**：
- 删除 `correctedCalories` 计算逻辑（L116-118 cal≤0 修正、L119-138 Atwater 偏差>10% 修正）
- 删除 `correctedProteinG/FatG/CarbsG` 宏量反推逻辑（L81-101）
- 删除 `RecognitionValidationResult` 的 correctedCalories/correctedProteinG/FatG/CarbsG 字段
- **保留**：字段合理性校验（dishName/confidence/weight/区间，L32-60，触发 needsRetry 重试）
- **保留**：组分份量交叉验证（L151-167，这是信任 mid 不是覆盖 AI 估算）
- **新增**：物理约束检测，输出 `warnings` 列表（List<String>，不修改值）
  - Atwater 偏差>10% → warning `"⚠ 宏量与热量不自洽：AI 估算 ${cal}kcal，宏量加和 ${expected}kcal（偏差 ${ratio}%），请核对"`
  - 宏量缺失（cal>0 但部分宏量=0）→ warning `"⚠ AI 未提供完整宏量数据，请核对"`
  - per100g>900 → warning `"⚠ 密度异常高（${per100g}kcal/100g），请核对"`
  - 宏量加和>100g/100g → warning `"⚠ 宏量超出物理上限（蛋白+脂肪+碳水=${sum}g/100g），请核对"`

**为什么**：用户决策"删除（AI 绝对优先）"+ 新指令"严谨验证"。Atwater 修正静默改 cal 是最主要的不一致来源，删除后 reasoning 显示值=记录值。物理约束改为 warnings 提示让用户判断。

**怎么改**：
```dart
// RecognitionValidationResult 新结构
class RecognitionValidationResult {
  final bool isValid;        // 字段合理性（dishName/confidence/weight/区间）
  final bool needsRetry;     // 字段严重不合理触发重试
  final List<FoodComponent>? correctedComponents;  // 组份缩放保留（信任 mid）
  final List<String> warnings;  // 新增：物理约束警告（不修改值）
  final List<String> reasons;   // 字段不合理原因（用于 Sentry）
}
```

### 改动 B：删除 AI 离谱兜底（库值不再覆盖 AI）

**文件**：`lib/features/recognize/calibrated_nutrition_calculator.dart`

**改什么**：
- 删除 `compute` 的 AI 离谱兜底分支（L71-87，AI per100g>900 用库值）
- 删除 `aiValid` 检查（L71），始终走 AI 绝对优先分支（L89-107）
- 删除 `computeCompositeLookupHit` 的 aiValid 检查（L189-190），始终返回 AI 反算值
- **保留**：物理 clamp（在 FoodCategoryDefaults.calibrate 内，防除零/负值）
- shouldUpdateFoodItem 逻辑不变（diffRatio>0 时纠正库）

**为什么**：用户决策"删除（AI 给多少都照记）"+ "兜底也用 AI"。库值不再覆盖 AI，AI 离谱时通过 warnings 提示用户手动纠正。

**怎么改**：
```dart
// compute 方法简化：删除 aiValid 分支，始终走 AI 优先
if (lookupHitNutrition != null && lookupHitNutrition.foodItemId > 0) {
  // 始终用 AI 反算 per100g（不再检查 aiValid）
  final aiPer100Calories = aiFallback.calories * per100Ratio;
  // ... shouldUpdateFoodItem 逻辑不变
  return CalibratedNutrition(...);
}
// 哨兵分支不变（包装 OCR 优先 + FoodCategoryDefaults.calibrate 物理 clamp）
```

### 改动 C：PostProcessor 透传 warnings

**文件**：`lib/core/util/recognition_post_processor.dart` + `lib/ai/vision_provider.dart`

**改什么**：
- `VisionRecognitionResult` 新增 `List<String> warnings` 字段（默认空，不参与 JSON 序列化，transient）
- `RecognitionPostProcessor.process` 调 validator 后，把 `validation.warnings` 设置到 result.warnings
- 删除 PostProcessor 中所有 `correctedCalories/correctedProteinG/FatG/CarbsG` 回写逻辑（L35-50）
- **保留**：correctedComponents 回写（组份缩放，信任 mid）
- correctAdditionalDishes 同步：删除 correctedXxx 回写，透传 warnings

**为什么**：warnings 需要从 PostProcessor 传到 UI，最简单的方式是挂在 VisionRecognitionResult 上（transient 字段）。删除 correctedXxx 回写是改动 A 的配套。

### 改动 D：修复复合菜预览不一致

**文件**：`lib/features/recognize/calibration_page.dart`

**改什么**：
- `_buildNutritionPreview` 复合菜分支（L491-505）：当前用组分累加 + 用油量
- 改为：与 `multi_dish_page._calcNutrition` 一致，走 `CalibratedNutritionCalculator.computeCompositeLookupHit` AI 优先
- 如果 compositeNutrition 有 AI 估算（aiFallback），优先用 AI 值；组分累加仅作为滑块调整时的实时预览 fallback

**为什么**：同一道复合菜在校准页用组分累加，在多菜页用 AI 优先，数值不同。用户感知"数值乱跳"。

**怎么改**：
```dart
// _buildNutritionPreview 复合菜分支
if (widget.compositeNutrition != null) {
  final composite = widget.compositeNutrition!;
  // 优先用 AI 估算（与 multi_dish_page 一致）
  if (composite.aiFallback != null) {
    final calibrated = CalibratedNutritionCalculator.computeCompositeLookupHit(
      aiFallback: composite.aiFallback!,
      servingG: _servingG,
      mid: widget.recognitionResult.estimatedWeightGMid,
    );
    if (calibrated != null) {
      return _nutritionCard(calibrated.actualCalories, ...);
    }
  }
  // fallback：组分累加（AI 无估算时）
  // ... 原逻辑
}
```

### 改动 E：UI 显示 warnings + 手动编辑营养值

**文件**：`lib/features/recognize/calibration_page.dart`

**改什么**：
1. **warnings 显示**：在 reasoning 卡片下方显示警告横幅
   - `result.warnings` 非空时，显示黄色/橙色 Card，列出所有 warning 文案
   - 图标用 Icons.warning_amber_rounded + onSurfaceVariant 色
2. **手动编辑营养值**：_nutritionCard 的 4 个数值（cal/protein/fat/carbs）改为可点击
   - 点击后弹出编辑对话框（AlertDialog + 4 个 TextField）
   - 用户输入新值，确认后 actualXxx = 用户输入值
   - per100g 基于用户输入值反算（per100g = userInput × 100 / mid，硬约束 #4 基于 mid）
   - 状态字段新增 `_userOverrides`（Map<String, double>，键为 'cal'/'protein'/'fat'/'carbs'）
   - _computeSingleItemActual 优先用 _userOverrides，否则用原逻辑

**为什么**：用户指令"最后用户可以手动修改"。warnings 提示用户哪些值可能有问题，手动编辑让用户作为最终兜底。基于 mid 反算 per100g 保证硬约束 #4。

### 改动 F：删除品类默认值表（defaults 表无引用后）

**文件**：`lib/data/seed/food_category_defaults.dart`

**改什么**：
- 改动 A 删除宏量反推后，`FoodCategoryDefaults.defaults` 表无引用
- 删除 defaults 表（L42-60）
- calibrate 方法保留（只剩物理 clamp [0,900]/[0,100]，被 CalibratedNutritionCalculator 哨兵分支调用）
- 或内联 clamp 到 CalibratedNutritionCalculator，删除整个 FoodCategoryDefaults 类

**为什么**：defaults 表仅供宏量反推用，删除宏量反推后无引用，删表避免代码冗余。calibrate 的物理 clamp 保留防除零/负值。

## 假设与决策

### 假设
1. AI provider 返回的 `estimated_calories/protein_g/fat_g/carbs_g` 对应 mid 份量（现有设计，不变）
2. per100g 反算基于 `estimatedWeightGMid`（硬约束 #4，不变）
3. 三路径（recognize_page/multi_dish_page/offline_queue_controller）继续通过 CalibratedNutritionCalculator 收敛
4. 字段合理性校验（dishName/confidence/weight/区间）保留触发重试，不删

### 决策
1. **Atwater 修正删除**（用户决策"删除 AI 绝对优先"）
2. **AI 离谱兜底删除**（用户决策"删除 AI 给多少都照记"）
3. **物理约束改为 warnings 提示**（用户新指令"严谨验证"+"用户手动修改"）
4. **最小改动范围**（用户决策"最小改动推荐"）
5. **保留组分份量缩放**（信任 mid，不是覆盖 AI 估算）
6. **保留包装 OCR 优先**（包装是 AI 读到的精确值，符合 AI 优先）
7. **保留物理 clamp [0,900]/[0,100]**（防除零/负值，不是覆盖 AI 估算）
8. **保留字段合理性重试**（dishName 空/confidence 越界等触发重试，不覆盖值）

### 不改的部分
- 三路径架构（recognize_page/multi_dish_page/offline_queue_controller）
- CalibratedNutritionCalculator 收敛层（只删 aiValid 分支）
- 密度换算（物理换算，不覆盖 AI 估算）
- 包装 OCR 优先（AI 读到的精确值）
- 组份份量缩放（信任 mid）
- 字段合理性重试（触发重试不覆盖值）
- 物理 clamp（防除零/负值）
- 哨兵替换 upsertAiRecognized（硬约束 #2）
- per100g 反算基于 mid（硬约束 #4）

## 验证步骤（TDD）

### 测试文件（新增）
- `test/core/recognition_validator_v2_test.dart`：AI 值不被静默修改 + warnings 输出
- `test/features/calibrated_nutrition_calculator_v2_test.dart`：AI 离谱不用库值兜底
- `test/features/calibration_page_manual_edit_test.dart`：warnings 显示 + 手动编辑
- `test/features/composite_preview_consistency_test.dart`：复合菜预览一致性

### 测试用例（关键）
1. **AI 值不被静默修改**：
   - AI 给 cal=400, p=20, f=10, c=30（expected=4×20+9×10+4×30=290，偏差 27.5%>10%）
   - 旧逻辑：correctedCalories=290（覆盖 AI 的 400）
   - 新逻辑：calories 保持 400，warnings 含"宏量与热量不自洽"
2. **AI 离谱不用库值兜底**：
   - AI per100g=5000，库 per100g=100
   - 旧逻辑：用库值 100
   - 新逻辑：用 AI 值 5000，warnings 含"密度异常高"
3. **米粉汤回归**（v0.23.0 方案 D 已修，确保不回归）：
   - AI 估算 526 kcal/570g → per100g=92.3 → actualCalories=526（与 AI 一致）
4. **复合菜预览一致性**：
   - 同一道复合菜在校准页和多菜页数值相同
5. **warnings 显示**：
   - warnings 非空时 UI 显示警告横幅
6. **手动编辑**：
   - 用户点击 cal 数值 → 输入 600 → actualCalories=600，per100g=600×100/mid
7. **三路径一致性**：
   - recognize_page/multi_dish_page/offline_queue_controller 行为一致
8. **字段合理性重试保留**：
   - dishName 空 → needsRetry=true（不修改值，触发重试）

### 回归测试（现有测试调整）
- `test/core/recognition_validator_test.dart`：删除 Atwater 修正 + 宏量反推的测试，新增 warnings 测试
- `test/features/calibrated_nutrition_calculator_test.dart`：删除 AI 离谱兜底测试
- `test/features/plan_d_calibrate_removal_test.dart`：保留（米粉汤回归）
- `test/features/recognize_page_test.dart`：调整（AI 绝对优先场景不变，删除 Atwater 修正场景）
- `test/data/food_category_defaults_test.dart`：删除（defaults 表删除）

### 全量验证
- `flutter analyze` → No issues
- `flutter test` → 全过，0 回归
- 6+1 硬约束全部满足

## 实施顺序（TDD Red-Green-Refactor）

1. **改动 A**：validator 删除 Atwater 修正 + 宏量反推 + 新增 warnings
   - RED：写测试"AI cal=400 偏差>10% 不被修正"+"warnings 含不自洽提示"
   - GREEN：改 validator
   - REFACTOR：清理 correctedXxx 字段
2. **改动 B**：calculator 删除 AI 离谱兜底
   - RED：写测试"AI per100g=5000 不用库值"
   - GREEN：改 calculator
3. **改动 C**：PostProcessor 透传 warnings + 删除 correctedXxx 回写
   - RED：写测试"PostProcessor.process 输出 warnings"
   - GREEN：改 PostProcessor + VisionRecognitionResult
4. **改动 D**：修复复合菜预览不一致
   - RED：写测试"校准页复合菜预览 == 多菜页"
   - GREEN：改 calibration_page
5. **改动 E**：UI warnings 显示 + 手动编辑
   - RED：写测试"warnings 非空显示横幅"+"手动编辑改 cal"
   - GREEN：改 calibration_page
6. **改动 F**：删除品类默认值表
   - GREEN：删 defaults 表，跑测试确认无引用
7. **回归**：flutter analyze + flutter test 全量验证
