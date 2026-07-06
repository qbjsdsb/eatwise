# M26 P1 修复 Checklist

## A 类数据一致性

- [x] 复合菜预览/记录路径优先级一致：`_buildNutritionPreview` 与 `_confirmWithServing` 在"包装+宏量全0+aiFallback"场景都走 AI 优先
- [x] 复合菜 AI 优先路径含用油量：用户拖动用油量滑块时预览热量+脂肪实时变化
- [x] profile goalRate 改 TextFormField 并在 Form 内校验（0.1-2.0 kg/周）
- [x] profile 4 个数值字段加范围校验（身高 50-250 / 体重 20-300 / 年龄 10-120 / 体脂率 0-60）
- [x] profile _save 不再用 `?? 0` 兜底 goalRate
- [x] weight 编辑 dialog 用 Form + TextFormField + validator，无效输入显示 errorText 不关闭 dialog
- [x] weight 编辑 dialog 删除调用方静默 return 逻辑
- [x] backup_page 导入成功后 invalidate 4 个 provider + RefreshBus.notify
- [x] 新增 5 个测试文件覆盖 A 类 5 个 bug 修复
- [x] A 类 commit 完成，flutter analyze + flutter test 通过

## B 类核心流程

- [x] confirmAction content Text 加 maxLines:8 + overflow:ellipsis
- [x] confirmAction content 外层包 SingleChildScrollView
- [x] update_page 新增 _lastFailedStage 字段
- [x] update_page _check/_download/_install catch 块设 _lastFailedStage
- [x] update_page error 态按钮根据 _lastFailedStage 调对应方法
- [x] update_page install 失败重试复用 _downloadedPath 不重新下载
- [x] dish_name_editor.dart:155 文案改为"食物库未命中此菜名，可转手动录入或再试一次"
- [x] 新增 3 个测试文件覆盖 B 类 3 个 bug 修复
- [x] B 类 commit 完成，flutter analyze + flutter test 通过

## C 类系统性根因

- [x] showAppToast SnackBar content 包 Semantics(liveRegion: true)
- [x] EmptyState 新增 actionIcon 参数（默认 Icons.camera_alt_rounded 兼容现有调用）
- [x] 18 处错误文案改为"<操作>失败：<原因推测>。<修复步骤>"格式 + debugPrint 原始异常
  - [x] insight_page:467
  - [x] today_meals_page:379/557/728
  - [x] calibration_page:849/992
  - [x] multi_dish_page:524
  - [x] settings_page:338
  - [x] backup_page:112/191
  - [x] update_page:73/107/127
  - [x] profile_page:78/515
  - [x] weight_page:430/573/599
  - [x] manual_entry_page:255/326
  - [x] food_edit_page:175/213
- [x] 7 个文件数值 TextField 加 inputFormatters（FilteringTextInputFormatter.allow + RegExp）
  - [x] calibration_page 4 处
  - [x] meal_edit_dialog 5 处
  - [x] food_edit_page 5 处
  - [x] manual_entry_page 数值处
  - [x] weight_page 2 处
  - [x] profile_page 5 处（依赖 goalRate 改 TextFormField）
  - [x] today_meals_page 反馈 dialog 1 处
- [x] 新增 3 个测试文件覆盖 C 类修复
- [x] C 类 commit 完成，flutter analyze + flutter test 通过

## D 类编辑流程一致性

- [x] meal_edit_dialog 加 _dirty 状态 + 所有编辑控件 onChanged 调 _markDirty
- [x] meal_edit_dialog 外层 PopScope + confirmDiscardChanges
- [x] today_meals_page:529 showDialog 加 barrierDismissible: false
- [x] backup_page _import 入口加 _busy 检查
- [x] settings_page 5 处 TextField 加 focusedBorder
- [x] update_page AnimatedSize 检查 MediaQuery.accessibleNavigation
- [x] 新增 2 个测试文件覆盖 D 类修复
- [x] D 类 commit 完成，flutter analyze + flutter test 通过

## E 类错误反馈与状态覆盖

- [ ] recognize_page:567 内联 SnackBar content 包 Semantics(liveRegion: true)
- [ ] today_meals_page:346-364 Undo SnackBar content 包 Semantics(liveRegion: true)
- [ ] today_meals_page:402-419 Image.file 加 semanticLabel: '食物图片'
- [ ] today_meals_page:603-638 反馈纠正 dialog 加 barrierDismissible: false
- [ ] meal_edit_dialog _save 校验改 Form + errorText
- [ ] food_edit_page _saveServingOnly/_saveAll 校验改 errorText
- [ ] manual_entry_page _logFromLibrary/_logCustom 校验改 errorText
- [ ] weight_page _save 校验改 errorText
- [ ] 新增 2 个测试文件覆盖 E 类修复
- [ ] E 类 commit 完成，flutter analyze + flutter test 通过

## 最终验证

- [ ] 全量 `flutter analyze` No issues found
- [ ] 全量 `flutter test` 通过 0 回归（基线 1107 passed，预期新增约 15-20 测试，总数 ≥ 1122）
- [ ] 6+1 硬约束核查（build.gradle 未碰 / meal_log 外键未碰 / AI 三路径 / per100g 反算基于 mid / SecureConfigStore / initSentryAndRunApp / minSdk=31）
- [ ] v2 重构 4 断言核查（AI 估算值不被静默修改 / 预览值=onConfirm 写库值 / warnings 透传 / 用户手动编辑覆盖 AI 值）
- [ ] HANDOFF.md 第 2 节"当前状态"加 M26 修复记录（5 个 commit hash + 修复清单 + 验证结果）
- [ ] 全部 push 到 origin/trae/agent-wX1X6Q，不打 tag 不发版
