# Tasks

修复顺序：A 类（数据一致性）→ B 类（核心流程）→ C 类（系统性根因）→ D 类（编辑流程）→ E 类（错误反馈）。每类一个 commit。

## Commit 1: A 类数据一致性（5 条）

- [ ] Task 1: 修复 calibration_page 复合菜预览/记录路径优先级不一致
  - [ ] SubTask 1.1: 调整 `_buildNutritionPreview`（L523-568）复合菜路径，将"包装优先（宏量非全0）→ AI 优先 → 组分累加"作为统一优先级链路
  - [ ] SubTask 1.2: 调整 `_confirmWithServing`（L869-984）复合菜路径，与 _buildNutritionPreview 条件完全对齐
  - [ ] SubTask 1.3: 验证两条路径在"包装+宏量全0+aiFallback"场景下都走 AI 优先
- [ ] Task 2: 修复 calibration_page 复合菜 AI 优先路径未含用油量
  - [ ] SubTask 2.1: 在 `_buildNutritionPreview` AI 优先分支（L542-550）累加 `oilCaloriesPer100g * _oilG / 100` 到 calories + `oilFatPer100g * _oilG / 100` 到 fat
  - [ ] SubTask 2.2: 在 `_confirmWithServing` AI 优先分支（L908-932）同样累加油量
  - [ ] SubTask 2.3: 在 `_confirmWithServing` mid<=0 兜底分支（L933-958）已含油量，无需改
- [ ] Task 3: 修复 profile_page goalRate 游离 Form + 全页数值无范围校验
  - [ ] SubTask 3.1: goalRate `TextField`（L279-287）改 `TextFormField` + validator（0.1-2.0 kg/周）
  - [ ] SubTask 3.2: 身高 validator（L150-154）加范围校验 50-250
  - [ ] SubTask 3.3: 体重 validator（L163-167）加范围校验 20-300
  - [ ] SubTask 3.4: 年龄 validator（L174-178）加范围校验 10-120
  - [ ] SubTask 3.5: 体脂率 validator（L202-206）加范围校验 0-60
  - [ ] SubTask 3.6: _save（L393）的 `double.tryParse(_goalRateCtrl.text) ?? 0` 改为读 Form 校验通过值
- [ ] Task 4: 修复 weight_page 编辑 dialog 完全无校验静默 return
  - [ ] SubTask 4.1: 编辑 dialog 改用 `Form` + `TextFormField` + validator（>0 且 ≤500）
  - [ ] SubTask 4.2: "保存"按钮点击时调 `Form.validate()`，失败时不关闭 dialog 显示 errorText
  - [ ] SubTask 4.3: 删除调用方 `if (result.weightKg == null || result.weightKg! <= 0) return;` 静默 return（dialog 内已校验）
- [ ] Task 5: 修复 backup_page 导入后未 invalidate provider
  - [ ] SubTask 5.1: 导入成功后（L184-188 之间）加 `ref.invalidate(appConfigProvider)` + `ref.invalidate(mealLogRepoProvider)` + `ref.invalidate(weightLogRepoProvider)` + `ref.invalidate(profileRepoProvider)`
  - [ ] SubTask 5.2: 加 `RefreshBus.instance.notify()` 通知非 Riverpod 页面刷新
- [ ] Task 6: 新增 A 类针对性测试
  - [ ] SubTask 6.1: 新增 `test/features/recognize/calibration_composite_consistency_test.dart` 覆盖"包装+宏量全0+aiFallback"场景的预览=记录
  - [ ] SubTask 6.2: 新增 `test/features/recognize/calibration_composite_oil_test.dart` 覆盖 AI 优先路径含用油量
  - [x] SubTask 6.3: 扩展 `test/features/profile_page_test.dart` 覆盖范围校验（身高 0/999、体重 0/9999、goalRate "abc"）
  - [x] SubTask 6.4: 新增 `test/features/weight_edit_dialog_validation_test.dart` 覆盖无效输入不关闭 dialog
  - [x] SubTask 6.5: 新增 `test/features/backup_import_invalidate_test.dart` 覆盖导入后 provider invalidate
- [ ] Task 7: 验证 A 类修复
  - [ ] SubTask 7.1: `flutter analyze` No issues
  - [ ] SubTask 7.2: `flutter test` 全量通过 0 回归
  - [ ] SubTask 7.3: 6+1 硬约束核查（未碰 build.gradle / meal_log 外键 / AI 三路径 / per100g 反算基于 mid / SecureConfigStore / initSentryAndRunApp / minSdk=31）
  - [ ] SubTask 7.4: v2 重构 4 断言（AI 估算值不被静默修改 / 预览值=onConfirm 写库值 / warnings 透传 / 用户手动编辑覆盖 AI 值）
- [ ] Task 8: Commit A 类修复（消息："M26 A: 修复 5 个 v2 重构后数据一致性 P1 bug"）

## Commit 2: B 类核心流程（3 条）

- [ ] Task 9: 修复 confirmAction 长内容溢出 AlertDialog 不可达
  - [ ] SubTask 9.1: `m3_widgets.dart:292` content Text 加 `maxLines: 8` + `overflow: TextOverflow.ellipsis`
  - [ ] SubTask 9.2: content 外层包 `SingleChildScrollView` 兜底超长内容
- [ ] Task 10: 修复 update_page error 态"重试"行为错误
  - [ ] SubTask 10.1: 新增 `_lastFailedStage` enum 字段（none/check/download/install）
  - [ ] SubTask 10.2: _check/_download/_install catch 块设 `_lastFailedStage` 对应值
  - [ ] SubTask 10.3: error 态按钮 onPressed（L280）改为根据 `_lastFailedStage` 调对应方法（check→_check / download→_download / install→_install）
  - [ ] SubTask 10.4: install 失败重试时复用 `_downloadedPath`，不重新 _check + _download
- [ ] Task 11: 修复 dish_name_editor 文案错误
  - [ ] SubTask 11.1: `dish_name_editor.dart:155` `'食物库未命中「改菜名」，可转手动录入或再试一次'` 改为 `'食物库未命中此菜名，可转手动录入或再试一次'`
- [ ] Task 12: 新增 B 类针对性测试
  - [ ] SubTask 12.1: 新增 `test/widgets/confirm_action_overflow_test.dart` 覆盖长内容可滚动
  - [ ] SubTask 12.2: 新增 `test/features/update_retry_context_test.dart` 覆盖三阶段重试
  - [ ] SubTask 12.3: 扩展 `test/features/dish_name_editor_test.dart` 覆盖新文案
- [ ] Task 13: 验证 B 类修复（同 Task 7 三步）
- [ ] Task 14: Commit B 类修复（消息："M26 B: 修复 3 个核心流程 P1（confirmAction 溢出 + update 重试 + 文案错误）"）

## Commit 3: C 类系统性根因（4 条，批量整改）

- [ ] Task 15: 修复 showAppToast 缺 liveRegion
  - [ ] SubTask 15.1: `m3_widgets.dart:321-330` SnackBar content 外包 `Semantics(liveRegion: true, child: Text(msg))`
- [ ] Task 16: 修复 EmptyState 硬编码 camera 图标
  - [ ] SubTask 16.1: `m3_widgets.dart:137-141` 新增 `actionIcon` 参数（默认 `Icons.camera_alt_rounded` 兼容现有调用）
- [ ] Task 17: 改写 18 处错误文案含原始异常
  - [ ] SubTask 17.1: insight_page:467 '生成失败：$e' → '生成失败：AI 服务暂不可用，请检查网络后重试。' + debugPrint(e)
  - [ ] SubTask 17.2: today_meals_page:379/557/728 三处
  - [ ] SubTask 17.3: calibration_page:849/992 两处
  - [ ] SubTask 17.4: multi_dish_page:524
  - [ ] SubTask 17.5: settings_page:338
  - [ ] SubTask 17.6: backup_page:112/191 两处
  - [ ] SubTask 17.7: update_page:73/107/127 三处
  - [ ] SubTask 17.8: profile_page:78/515 两处
  - [ ] SubTask 17.9: weight_page:430/573/599 三处
  - [ ] SubTask 17.10: manual_entry_page:255/326 两处
  - [ ] SubTask 17.11: food_edit_page:175/213 两处
- [ ] Task 18: 7 个文件数值 TextField 加 inputFormatters
  - [ ] SubTask 18.1: calibration_page.dart:1099 4 个数值 TextField
  - [ ] SubTask 18.2: meal_edit_dialog.dart:291-296,352-378 5 个数值 TextField
  - [ ] SubTask 18.3: food_edit_page.dart:93-126 5 个数值 TextField
  - [ ] SubTask 18.4: manual_entry_page.dart:118-123,154-159,170-196 数值 TextField
  - [ ] SubTask 18.5: weight_page.dart:111-117,494-499 2 处体重 TextField
  - [ ] SubTask 18.6: profile_page.dart:144-207,279-287 5 个数值 TextFormField（改 TextFormField 后加 inputFormatters）
  - [ ] SubTask 18.7: today_meals_page.dart:616-622 反馈 dialog 份量 TextField
- [ ] Task 19: 新增 C 类针对性测试
  - [ ] SubTask 19.1: 扩展 `test/widgets/snackbar_clear_test.dart` 覆盖 liveRegion
  - [ ] SubTask 19.2: 新增 `test/widgets/empty_state_icon_test.dart` 覆盖 actionIcon 参数
  - [ ] SubTask 19.3: 新增 `test/features/error_message_friendly_test.dart` 覆盖关键错误文案不含原始异常
- [ ] Task 20: 验证 C 类修复（同 Task 7 三步）
- [ ] Task 21: Commit C 类修复（消息："M26 C: 修复 4 类系统性根因 P1（liveRegion + EmptyState 图标 + 18 处错误文案 + 7 文件 inputFormatters）"）

## Commit 4: D 类编辑流程一致性（4 条）

- [ ] Task 22: 修复 meal_edit_dialog 无 dirty 拦截
  - [ ] SubTask 22.1: meal_edit_dialog.dart 加 `_dirty` 状态字段
  - [ ] SubTask 22.2: 所有编辑控件 onChanged 调 `setState(() => _dirty = true)`
  - [ ] SubTask 22.3: AlertDialog 外层包 `PopScope(canPop: false, onPopInvoked: ...)` + `_dirty` 时调 `confirmDiscardChanges`
  - [ ] SubTask 22.4: 调用方 today_meals_page.dart:529 showDialog 加 `barrierDismissible: false`
- [ ] Task 23: 修复 backup_page _import 重入窗口
  - [ ] SubTask 23.1: backup_page.dart:119 `_import()` 入口加 `if (_busy) return;` 检查
- [ ] Task 24: 修复 settings_page TextField focus ring
  - [ ] SubTask 24.1: settings_page.dart:139-205 5 处 TextField 的 `border: InputBorder.none` 加 `focusedBorder: OutlineInputBorder()` 或保留 border:none 但加 `focusedBorder: UnderlineInputBorder()`
- [ ] Task 25: 修复 update_page AnimatedSize reduced-motion
  - [ ] SubTask 25.1: update_page.dart:315 AnimatedSize duration 改读 `MediaQuery.accessibleNavigation ? Duration.zero : Duration(milliseconds: 300)`
- [ ] Task 26: 新增 D 类针对性测试
  - [ ] SubTask 26.1: 新增 `test/features/meal_edit_dialog_dirty_test.dart` 覆盖 dirty 拦截
  - [ ] SubTask 26.2: 扩展 backup_page_test 覆盖 _import 重入
- [ ] Task 27: 验证 D 类修复（同 Task 7 三步）
- [ ] Task 28: Commit D 类修复（消息："M26 D: 修复 4 条编辑流程一致性 P1（meal_edit dirty + backup 重入 + settings focus ring + update reduced-motion）"）

## Commit 5: E 类错误反馈与状态覆盖（5 条）

- [ ] Task 29: 修复 recognize_page SnackBar 缺 liveRegion
  - [ ] SubTask 29.1: recognize_page.dart:567 内联 SnackBar content 外包 `Semantics(liveRegion: true, child: Text(...))`
- [ ] Task 30: 修复 today_meals_page Undo SnackBar 缺 liveRegion
  - [ ] SubTask 30.1: today_meals_page.dart:346-364 Undo SnackBar content 外包 `Semantics(liveRegion: true, child: Text(...))`
- [ ] Task 31: 修复 today_meals_page Image.file 无 semanticLabel
  - [ ] SubTask 31.1: today_meals_page.dart:402-419 `Image.file(...)` 加 `semanticLabel: '食物图片'`
- [ ] Task 32: 修复 today_meals_page 反馈纠正 dialog barrierDismissible
  - [ ] SubTask 32.1: today_meals_page.dart:603-638 反馈纠正 dialog showDialog 加 `barrierDismissible: false`
- [ ] Task 33: 4 个文件校验错误走 toast 改 errorText 内联
  - [ ] SubTask 33.1: meal_edit_dialog.dart:239-244 _save 校验改 Form + TextFormField + validator + errorText
  - [ ] SubTask 33.2: food_edit_page.dart:158-217 _saveServingOnly/_saveAll 校验改 errorText
  - [ ] SubTask 33.3: manual_entry_page.dart:224-281 _logFromLibrary/_logCustom 校验改 errorText
  - [ ] SubTask 33.4: weight_page.dart:379-387 _save 校验改 errorText（与 Task 4 编辑 dialog 改造协同）
- [ ] Task 34: 新增 E 类针对性测试
  - [ ] SubTask 34.1: 扩展 today_meals_page_test 覆盖 Undo SnackBar liveRegion + Image semanticLabel + 反馈纠正 dialog barrierDismissible
  - [ ] SubTask 34.2: 新增 `test/features/inline_error_text_test.dart` 覆盖 4 个文件 errorText 内联
- [ ] Task 35: 验证 E 类修复（同 Task 7 三步）
- [ ] Task 36: Commit E 类修复（消息："M26 E: 修复 5 条错误反馈与状态覆盖 P1（liveRegion + Image semanticLabel + barrierDismissible + 4 文件 errorText）"）

## 最终验证

- [ ] Task 37: 全量回归测试
  - [ ] SubTask 37.1: `flutter analyze` No issues found
  - [ ] SubTask 37.2: `flutter test` 全量通过 0 回归
  - [ ] SubTask 37.3: 6+1 硬约束核查
  - [ ] SubTask 37.4: v2 重构 4 断言核查
  - [ ] SubTask 37.5: 更新 HANDOFF.md 第 2 节"当前状态"加 M26 修复记录
- [ ] Task 38: 全部 push 到 origin（不打 tag 不发版，等用户明确指令）

# Task Dependencies

- Task 4（weight 编辑 dialog）与 Task 33.4（weight _save errorText）协同改造 weight_page，可合并执行
- Task 18.6（profile inputFormatters）依赖 Task 3（profile 改 TextFormField）完成
- Task 33（4 文件 errorText）依赖 Task 18（inputFormatters）完成（避免冲突）
- Commit 1-5 串行（每个 commit 前验证通过再下一个）
- Task 37 最终验证依赖所有 commit 完成
