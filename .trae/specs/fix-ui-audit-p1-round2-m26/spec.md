# UI 第二轮审查 P1 修复 Spec（M26）

## Why

第二轮 Web Interface Guidelines 深度审查发现累计 0 P0 + **45 P1** + ~224 P2，其中 5 个 P1 是 v2 重构后新发现的严重 bug（违反"显示值=记录值"契约 / 用户调整滑块无效 / 垃圾输入直接写库 / 导入后数据不刷新 / 确认按钮不可达）。本 spec 收口全部 45 条 P1，恢复 v2 重构核心契约并补齐系统性短板。

## What Changes

### A 类：数据一致性 / 正确性（5 条，最高优先级）
- 修复复合菜预览/记录路径优先级不一致（`calibration_page.dart` `_buildNutritionPreview` vs `_confirmWithServing`）：两条路径统一为"包装优先（宏量非全0）→ AI 优先 → 组分累加"
- 修复复合菜 AI 优先路径未含用油量但滑块可见：AI 优先路径累加 `oilCaloriesPer100g * _oilG / 100` + `oilFatPer100g * _oilG / 100`
- 修复 `profile_page` goalRate `TextField` 游离 Form 外 + 4 个数值 TextFormField 无范围校验：goalRate 改 TextFormField + 全页加范围 validator（身高 50-250cm、体重 20-300kg、年龄 10-120、体脂率 0-60%）
- 修复 `weight_page` 编辑 dialog 完全无校验静默 return：dialog 内加 errorText 内联反馈，无效输入禁用"保存"
- 修复 `backup_page` 导入成功后未 invalidate provider：导入成功后 `ref.invalidate(appConfigProvider)` + `ref.invalidate(mealLogRepoProvider)` + `ref.invalidate(weightLogRepoProvider)` + `ref.invalidate(profileRepoProvider)` + 发 `RefreshBus.instance.notify()`

### B 类：用户能完成核心流程（3 条）
- 修复 `confirmAction` 长内容溢出 AlertDialog 不可达：content Text 加 `maxLines: 8` + `overflow: ellipsis`，外层包 `SingleChildScrollView`
- 修复 `update_page` error 态"重试"行为错误：新增 `_lastFailedStage` 状态记忆（check/download/install），error 态按钮分别调对应阶段
- 修复 `dish_name_editor.dart:155` 文案错误："食物库未命中「改菜名」" → "食物库未命中此菜名"

### C 类：系统性问题根因（4 条，1 处修复多文件受益）
- `showAppToast` 加 `Semantics(liveRegion: true)`：全 App toast 一次性收口
- `EmptyState` 硬编码 `Icons.camera_alt_rounded` 改为参数（保留默认值兼容现有调用）
- 18 处错误文案含原始异常改写为 `<操作>失败：<原因推测>。<修复步骤>`，原始异常仅 debugPrint：
  - insight_page:467 / today_meals_page:379/557/728 / calibration_page:849/992 / multi_dish_page:524 / settings_page:338 / backup_page:112/191 / update_page:73/107/127 / profile_page:78/515 / weight_page:430/573/599 / manual_entry_page:255/326 / food_edit_page:175/213
- 7 个文件数值 TextField 加 `inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))]`：calibration_page / meal_edit_dialog / food_edit_page / manual_entry_page / weight_page / profile_page / today_meals_page（反馈 dialog）

### D 类：编辑流程一致性（4 条）
- `meal_edit_dialog.dart:261` 加 `_dirty` + `PopScope` + `confirmDiscardChanges`，与 food_edit/manual_entry/weight/profile/calibration 五页一致
- `backup_page.dart:119` `_import()` 入口加 `_busy` 检查
- `settings_page.dart:139-205` 5 处 TextField 加 `focusedBorder: OutlineInputBorder()` 提供可见 focus ring
- `update_page.dart:315` AnimatedSize 检查 `MediaQuery.accessibleNavigation`，true 时 duration 改 0ms

### E 类：错误反馈与状态覆盖（5 条）
- `recognize_page.dart:567` 内联 SnackBar 加 `Semantics(liveRegion: true)`
- `today_meals_page.dart:346-364` Undo SnackBar 加 `Semantics(liveRegion: true)`
- `today_meals_page.dart:402-419` `Image.file` 加 `semanticLabel: '食物图片'`
- `today_meals_page.dart:529` showDialog 加 `barrierDismissible: false`
- 4 个文件校验错误走 toast 改 `errorText` 内联：meal_edit_dialog / food_edit_page / manual_entry_page / weight_page（参照 profile_page Form + validator 模式）

## Impact

- **Affected specs**: v2 重构核心契约（显示值 = 记录值 + 用户手动兜底生效）；M24 P1 清零里程碑；6+1 硬约束（不动 build.gradle / meal_log 外键 / AI 三路径 / per100g 反算基于 mid / SecureConfigStore / initSentryAndRunApp / minSdk=31）
- **Affected code**:
  - `lib/features/recognize/calibration_page.dart`（复合菜路径优先级 + 用油量）
  - `lib/features/recognize/dish_name_editor.dart`（文案）
  - `lib/features/recognize/multi_dish_page.dart`（错误文案）
  - `lib/features/recognize/recognize_page.dart`（SnackBar liveRegion）
  - `lib/features/profile/profile_page.dart`（goalRate Form + 范围校验）
  - `lib/features/weight/weight_page.dart`（编辑 dialog 校验 + errorText）
  - `lib/features/dashboard/today_meals_page.dart`（SnackBar liveRegion + Image semanticLabel + barrierDismissible + 反馈 dialog inputFormatters）
  - `lib/features/dashboard/meal_edit_dialog.dart`（dirty 拦截 + inputFormatters + errorText）
  - `lib/features/food_library/food_edit_page.dart`（inputFormatters + errorText）
  - `lib/features/manual_entry/manual_entry_page.dart`（inputFormatters + errorText）
  - `lib/features/insight/insight_page.dart`（错误文案）
  - `lib/features/settings/settings_page.dart`（focus ring + 错误文案）
  - `lib/features/backup/backup_page.dart`（_busy 检查 + provider invalidate + 错误文案）
  - `lib/features/update/update_page.dart`（重试行为 + AnimatedSize reduced-motion + 错误文案）
  - `lib/core/widgets/m3_widgets.dart`（showAppToast liveRegion + EmptyState 图标参数 + confirmAction 长内容滚动）

## ADDED Requirements

### Requirement: 复合菜预览值等于记录值

校准页 `_buildNutritionPreview` 与 `_confirmWithServing` 复合菜路径必须使用同一优先级链路：包装优先（宏量非全0）→ AI 优先（aiFallback 非空）→ 组分累加 fallback。

#### Scenario: 包装+宏量全0+aiFallback 场景显示值等于记录值
- **WHEN** 复合菜 + 有包装数据 + 宏量全 0 + 有 aiFallback
- **THEN** 预览与记录都走 AI 优先路径，显示值 = onConfirm 传入值 = meal_log.actualXxx

### Requirement: AI 优先路径含用油量

复合菜 AI 优先路径（`computeCompositeLookupHit`）返回的 actualXxx 必须累加 `oilCaloriesPer100g * _oilG / 100` + `oilFatPer100g * _oilG / 100`，与组分累加 fallback 路径一致。

#### Scenario: 用户调整用油量滑块时预览数值实时变化
- **WHEN** 复合菜 + AI 优先路径 + 用户拖动用油量滑块
- **THEN** 预览热量和脂肪随用油量变化，滑块不再"无效"

### Requirement: profile 数值范围校验

profile_page 4 个数值字段（身高/体重/年龄/体脂率）+ goalRate 必须在 Form 内并通过 validator 校验范围：
- 身高 50-250 cm
- 体重 20-300 kg
- 年龄 10-120
- 体脂率 0-60%（可选字段，空值放行）
- goalRate 0.1-2.0 kg/周（仅 cut/bulk 显示时校验）

#### Scenario: 用户输入垃圾值时被拒绝
- **WHEN** 用户在 profile 输入身高 0 / 体重 9999 / goalRate "abc"
- **THEN** validator 返回 errorText，_save 直接 return 不写库

### Requirement: weight 编辑 dialog 内联校验

weight_page 编辑 dialog 必须在 dialog 内显示 errorText 反馈无效输入，禁止静默关闭。

#### Scenario: 用户输入非数字点保存
- **WHEN** 用户在编辑 dialog 输入 "abc" 点"保存"
- **THEN** dialog 不关闭，TextField 显示 errorText "请输入有效数字"

### Requirement: backup 导入后 provider 刷新

backup_page 导入成功后必须 invalidate 关键 provider，确保用户返回其它页面看到新数据。

#### Scenario: 导入后 dashboard 显示新数据
- **WHEN** 用户在 backup_page 导入成功
- **THEN** appConfigProvider / mealLogRepoProvider / weightLogRepoProvider / profileRepoProvider 被 invalidate + RefreshBus 通知，dashboard / today_meals / insight / weight 自动刷新

## MODIFIED Requirements

### Requirement: 错误信息含修复步骤

所有 catch 块的 toast 错误文案必须为 `<操作>失败：<原因推测>。<修复步骤>` 格式，原始异常仅 debugPrint 不暴露给用户。共 18 处。

### Requirement: 数值 TextField 输入过滤

所有数值 TextField 必须加 `inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))]`，防止物理键盘输入字母/多小数点。共 7 个文件。

### Requirement: showAppToast 无障碍播报

`showAppToast` 的 SnackBar content 必须包 `Semantics(liveRegion: true)`，读屏用户即时感知 toast 反馈。

### Requirement: confirmAction 长内容可滚动

`confirmAction` content Text 必须支持长内容滚动，小屏机型确认按钮始终可达。

### Requirement: update 重试上下文感知

update_page error 态按钮必须根据 `_lastFailedStage` 调用对应阶段（check/download/install），install 失败时复用 `_downloadedPath` 不重新下载。

### Requirement: 编辑流程 dirty 拦截一致

所有编辑类 dialog / 页面（food_edit / manual_entry / weight / profile / calibration / meal_edit_dialog / today_meals 反馈纠正 dialog / insight _edit dialog）必须有 `_dirty` + `PopScope` + `confirmDiscardChanges` + `barrierDismissible: false`。

## REMOVED Requirements

### Requirement: 原始异常直接暴露给用户
**Reason**: 原始异常对象 toString 对用户无意义，可能含技术细节（堆栈/类名/SQL）造成困惑
**Migration**: 18 处 catch 块改为友好文案 + debugPrint 原始异常
