# EatWise UI 审查报告（Web Interface Guidelines）

**审查日期**：2026-07-06
**审查范围**：全部 26 个 UI 页面文件（11514 行）
**审查准则**：[Vercel Web Interface Guidelines](https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md)（Flutter 映射版）
**审查方法**：4 个并行 subagent 按 4 个分组审查 + 跨组汇总

---

## 1. Summary（摘要）

EatWise UI 整体质量较高：防重入全覆盖、`_dirty` + `confirmDiscardChanges` 在多页一致落地、`「」` 中文引号统一、`…` 省略号正确、`colorScheme` 无硬编码 0xFF 颜色、`tabularFigures` 在数字列普遍应用、`ListView.builder` 用于大列表、`Form + validator` 在 profile_page 用法正确。

**共发现 0 P0 + 30 P1 + ~109 P2**。

无 P0 严重问题（无崩溃/数据丢失/无障碍完全不可用风险）。

P1 集中在 5 类系统性问题：
1. `showAppToast` 的 SnackBar 缺 `Semantics(liveRegion: true)`（影响全 App）
2. 数值 TextField 普遍缺 `inputFormatters`（7 个文件）
3. 校验错误走 SnackBar 而非 `errorText` 内联（5 个文件）
4. 错误信息含原始异常无修复步骤（9 处）
5. 部分动画未检查 `MediaQuery.accessibleNavigation`（reduced-motion）

P2 集中在 6 类细节问题：
1. 装饰图标未 `ExcludeSemantics`（读屏重复朗读）
2. 长文本缺 `maxLines + TextOverflow.ellipsis`（用户生成内容）
3. 硬编码 `fontSize`（应用 `textTheme.labelSmall/labelMedium`）
4. `ListView` 普遍缺 `SafeArea` 底部保护
5. 数字列缺 `FontFeature.tabularFigures()`（拖动时宽度跳动）
6. 日期硬编码 `padLeft` 拼接（应用 `intl DateFormat`）

---

## 2. Current State Analysis（项目 UI 架构现状）

```
lib/
├── app.dart                        # GoRouter 路由 + ColorScheme.fromSeed + dynamic_color
├── main.dart                       # 单一 ProviderContainer + Sentry + Workmanager
├── core/
│   ├── theme/theme_controller.dart # 种子色 Riverpod Notifier
│   ├── util/date_format.dart       # 手写 padLeft（非 intl，P2 系统性）
│   └── widgets/m3_widgets.dart     # SectionTitle / LeadingIconContainer / EmptyState / showAppToast / confirmDiscardChanges / HeroCard / WarningBanner / ErrorState / LoadingState
└── features/
    ├── dashboard/                  # 5 个 Tab 之一（首页）
    │   ├── dashboard_page.dart     # 310 行，CustomScrollView 主框架
    │   ├── today_meals_page.dart   # 739 行，今日餐次 + 删除 Undo
    │   ├── meal_edit_dialog.dart   # 396 行，餐次编辑
    │   └── dashboard/              # 6 个子组件（M24 B5 拆分）
    ├── records/records_tab_page.dart  # 90 行，记录 Tab
    ├── recognize/                  # 5 个 Tab 之一（拍照）
    │   ├── recognize_page.dart     # 794 行，识别入口
    │   ├── calibration_page.dart   # 1243 行，校准页（最大）
    │   ├── multi_dish_page.dart    # 542 行，多菜页
    │   ├── multi_dish/             # 4 个子组件（M24 B4 拆分）
    │   ├── recognize_progress_card.dart  # 287 行
    │   ├── dish_name_editor.dart   # 157 行，改菜名 mixin
    │   └── calibrated_nutrition_calculator.dart  # 218 行，纯计算
    ├── insight/insight_page.dart   # 1775 行，总结 Tab（最大）
    ├── me/me_page.dart             # 234 行，我的 Tab
    ├── food_library/               # 食物库 + 编辑
    ├── manual_entry/               # 手动录入
    ├── weight/weight_page.dart     # 611 行，体重记录
    ├── profile/                    # 个人资料 + 营养计算器
    ├── settings/                   # 设置
    ├── backup/                     # 备份恢复
    └── update/                     # 更新
```

**已遵循的良好实践**：
- `colorScheme` 配色全覆盖（无 0xFF 硬编码颜色，仅 `recognize_progress_card.dart:204` 一处 `Colors.white`）
- `IconButton` 普遍有 `tooltip`
- 写库按钮 `_isRecording`/`_busy` 防重入 + try-catch-finally + `mounted` 检查
- 破坏性操作 `confirmAction` / `confirmDismiss` / `PopScope` + `confirmDiscardChanges` 二次确认
- `ListView.builder` 用于大列表
- `tabularFigures` 在数字列普遍应用
- `「」` 中文引号 + `…` 省略号统一
- M24 B5 已拆分 dashboard / multi_dish 大文件，符合"文件 < 600 行"

---

## 3. 审查准则映射（Web → Flutter）

Web Interface Guidelines 原为 React/HTML 设计，本项目是 Flutter 移动 App。映射如下：

| Web 准则 | Flutter 等价 |
|---------|------------|
| `aria-label` | `IconButton.tooltip` / `Semantics(label:)` |
| `aria-live="polite"` | `Semantics(liveRegion: true)` |
| `aria-hidden="true"` | `ExcludeSemantics` |
| `focus-visible:ring-*` | `InkWell focusColor` / Material 组件默认 focus |
| `<button>` vs `<div onClick>` | `IconButton/TextButton/ElevatedButton` vs `GestureDetector+onTap` |
| `transition: all` | 隐式 `AnimatedContainer`（应显式 `AnimatedXxx`） |
| `prefers-reduced-motion` | `MediaQuery.accessibleNavigation` / `disableAnimations` |
| `text-wrap: balance` | `Text(maxLines + overflow)` |
| `truncate` / `line-clamp-*` | `TextOverflow.ellipsis + maxLines` |
| `font-variant-numeric: tabular-nums` | `FontFeature.tabularFigures()` |
| `<img width height>` | `Image(width/height)` 或 `AspectRatio` |
| 大列表虚拟化 | `ListView.builder`（默认） |
| `Intl.DateTimeFormat` | `intl DateFormat` |
| `Intl.NumberFormat` | `intl NumberFormat` |
| `touch-action: manipulation` | Flutter 默认 |
| 触控目标 ≥48dp | `IconButton constraints` / `ListTile minVerticalPadding` |
| `env(safe-area-inset-*)` | `SafeArea(top/bottom)` |
| `color-scheme: dark` | `Theme.of(context).colorScheme` |

---

## 4. 全量问题清单（按文件分组）

### Group A：5 个 Tab 主框架 + dashboard 子组件

#### lib/features/dashboard/dashboard_page.dart
- `dashboard_page.dart:282` - CustomScrollView 无底部 SafeArea，刘海机底部手势条可能遮挡末段 (P2)
- `dashboard_page.dart:175,179,202,207` - showAppToast 反馈缺 `Semantics(liveRegion:true)`（根因在 m3_widgets.dart，见系统性问题 #1）(P1)

#### lib/features/records/records_tab_page.dart
- ✓ pass

#### lib/features/recognize/recognize_page.dart
- `recognize_page.dart:567` - 错误态 SnackBar 内联创建缺 `Semantics(liveRegion:true)`（含重试 action，关键反馈通道）(P1)
- `recognize_page.dart:584,625,781` - showAppToast 缺 liveRegion（系统性问题 #1）(P1)
- `recognize_page.dart:361-369` - 识别遮罩 + 进度卡片动画未检查 `MediaQuery.accessibleNavigation`（系统性问题 #5）(P2)

#### lib/features/insight/insight_page.dart（1775 行，最大）
- `insight_page.dart:592` - ListView padding EdgeInsets.all(16) 未叠加 MediaQuery 底部 padding，末尾 FilledButton 在手势条机型可能贴边/被遮挡 (P2)
- `insight_page.dart:467` - 错误文案 '生成失败：$e' 直接拼异常，缺修复步骤（系统性问题 #4）(P2)
- `insight_page.dart:827,836,903` - 图表轴日期 `'${date.month}/${date.day}'` 硬编码 M/D，非 intl DateFormat (P2)
- `insight_page.dart:828,837,853,997,1432,1704` - 图表 TextStyle 硬编码 `fontSize:10/11/12`，非 textTheme (P2)
- `insight_page.dart:853,996,1446,1718` - 数值轴标签 `'${value.round()}'` 缺 `FontFeature.tabularFigures()`，数字宽度跳动 (P2)
- `insight_page.dart:1096,1232,1378,1524,1659` - 卡片标题装饰图标（insights_rounded / pie_chart / bar_chart / restaurant_menu / calendar_view_week）未用 `ExcludeSemantics` (P2)
- `insight_page.dart:597,614` - AnimatedSwitcher(300ms) 未检查 reduced-motion (P2)
- `insight_page.dart:537` - ✓ 正面：唯一 IconButton（编辑汇总）已带 tooltip

#### lib/features/me/me_page.dart
- `me_page.dart:71` - HeroCard(onTap) 内部 InkWell 未加显式 `Semantics(button:true, label:)`，读屏仅读内部文本无"按钮"角色提示 (P2)
- `me_page.dart:168` - SliverList 末尾 SizedBox(32) 无底部 SafeArea (P2)

#### lib/features/recognize/recognize_progress_card.dart
- `recognize_progress_card.dart:204,212` - `Colors.white` 硬编码（应改 `cs.onPrimary`）(P2)
- `recognize_progress_card.dart:75,175,185` - TweenAnimationBuilder / AnimatedContainer / AnimatedSwitcher 三处动画未检查 reduced-motion (P2)
- `recognize_progress_card.dart:149,240` - 装饰图标未 `ExcludeSemantics`（阶段已有文本）(P2)
- `recognize_progress_card.dart:147,242` - TextStyle 手写 fontWeight，未用 textTheme (P2)
- `recognize_progress_card.dart:261-267` - ✓ 正面：阶段文案统一用「…」

#### lib/features/dashboard/dashboard/ai_rec_item.dart
- `ai_rec_item.dart:189` - _ratedChip Text 硬编码 `fontSize:10`，应改 `textTheme.labelSmall` (P2)
- ✓ 正面：L89/L98 maxLines+ellipsis、L145 动态 tooltip、L47/L150 防重入、L76/L93 ExcludeSemantics

#### lib/features/dashboard/dashboard/dashboard_data.dart
- ✓ pass（纯数据模型）

#### lib/features/dashboard/dashboard/recommendation_section.dart
- `recommendation_section.dart:250` - v4 推荐 ListTile 的 title Text(rec.food.name) 无 maxLines+ellipsis，长菜名会换行撑高、与 AiRecItem(maxLines:1) 不一致 (P2)

#### lib/features/dashboard/dashboard/regenerate_button.dart
- ✓ pass（防重入、'生成中…' 用 …、≥48dp 触控目标均有守护）

#### lib/features/dashboard/dashboard/status_card_section.dart
- `status_card_section.dart:167-176` - 宏量值 Text 置于固定 SizedBox(80/110) 内无 maxLines，超大数字可能换行多行撑高 Row (P2)

#### lib/features/dashboard/dashboard/today_meals_section.dart
- `today_meals_section.dart:66` - ListTile title Text(d.foodNames[...] ?? '食物') 无 maxLines+ellipsis (P2)
- `today_meals_section.dart:110-113` - _formatTime 手写 padLeft 拼 'HH:mm'，应改 `intl DateFormat.Hm()` (P2)

**Group A 总结**：0 P0 + 2 P1 + 20 P2

---

### Group B：拍照识别详情流程

#### lib/features/recognize/calibration_page.dart（1243 行，最大）
- `calibration_page.dart:226` - 菜名 Text（headlineSmall）无 maxLines/overflow，AI/用户菜名可能很长会无限换行撑高布局 (P2)
- `calibration_page.dart:345` - TextStyle 硬编码 `fontSize: 12`，应用 `textTheme.labelSmall` (P2)
- `calibration_page.dart:373` - TextStyle 硬编码 `fontSize: 12`（历史中位数提示）(P2)
- `calibration_page.dart:570` - `_buildNutritionPreview` 无营养数据时 `SizedBox.shrink()` 静默空态，用户无任何反馈 (P2)
- `calibration_page.dart:583` - 热量行 Row（InkWell+Text+SizedBox+Text+SizedBox+Icon）无 Expanded，超大热量值可能 overflow (P2)
- `calibration_page.dart:588` - InkWell 包 Text 触控目标仅文字高度，<48dp (P2)
- `calibration_page.dart:588` - InkWell 无语义标签，读屏只读到数字不告知"可点击编辑" (P2)
- `calibration_page.dart:650` - 宏量值 InkWell 触控目标 <48dp 且无编辑语义标签 (P2)
- `calibration_page.dart:679` - "待确认组分" Row 中 Text 未包 Expanded，长文案可能 overflow (P2)
- `calibration_page.dart:751` - 数量步进器 Row 无 Expanded/Wrap，unit 较长时 overflow (P2)
- `calibration_page.dart:773` - TextStyle 硬编码 `fontSize: 12`（每份克数提示）(P2)
- `calibration_page.dart:849` - 错误信息"改菜名失败：$e"无修复步骤（系统性问题 #4）(P2)
- `calibration_page.dart:992` - 错误信息"记录失败：$e"无修复步骤 (P2)
- `calibration_page.dart:1099` - 4 个数值 TextField 无 inputFormatters（系统性问题 #2）(P2)
- `calibration_page.dart:1146` - 编辑对话框"确认"提交后无效输入被静默忽略，无 errorText 反馈（系统性问题 #3）(P2)
- `calibration_page.dart:1239` - _sourceBadge TextStyle 硬编码 `fontSize: 11` (P2)
- `calibration_page.dart:423` - body 底部 FilledButton 无 SafeArea(bottom) (P2)
- `calibration_page.dart:588` - `_showEditNutritionDialog` 触发点无防重入，快速连点数值会叠开两个对话框 (P2)

#### lib/features/recognize/multi_dish_page.dart
- `multi_dish_page.dart:524` - 错误信息"记录失败：$e"无修复步骤 (P2)
- `multi_dish_page.dart:155` - Scaffold body 底部 TotalSummaryBar 无 SafeArea(bottom) (P2)

#### lib/features/recognize/multi_dish/ai_estimate_card.dart
- `ai_estimate_card.dart:49` - `Icon(Icons.insights_outlined)` 装饰图标未包 `ExcludeSemantics` (P2)
- `ai_estimate_card.dart:61` - "置信度 X%" 数字无 `FontFeature.tabularFigures()` (P2)
- `ai_estimate_card.dart:102` - _buildSourceBadge TextStyle 硬编码 `fontSize: 10` (P2)
- `ai_estimate_card.dart:130` - AI vs 库值对比长 Text 无 maxLines (P2)
- `ai_estimate_card.dart:131` - 对比行多个数字无 `FontFeature.tabularFigures()` (P2)
- `ai_estimate_card.dart:148` - ExpansionTile title 中装饰图标未包 `ExcludeSemantics` (P2)
- `ai_estimate_card.dart:161` - reasoning Text 的 TextStyle 硬编码 `fontSize: 11` (P2)

#### lib/features/recognize/multi_dish/dish_card.dart
- `dish_card.dart:84` - 菜名 Text 在 Expanded 内但无 maxLines/overflow，超长菜名无限换行 (P2)
- `dish_card.dart:128` - "份量：Xg" 数字无 `FontFeature.tabularFigures()`，拖滑块时数字跳动 (P2)
- `dish_card.dart:167` - "库中未找到「$currentName」..." Text 无 maxLines (P2)
- `dish_card.dart:185` - 数量步进器 Row 无 Expanded/Wrap，长 unit overflow (P2)
- `dish_card.dart:250` - warnings 文本 Text 无 maxLines (P2)

#### lib/features/recognize/multi_dish/nutrition_preview.dart
- ✓ pass（纯计算类）

#### lib/features/recognize/multi_dish/total_summary_bar.dart
- `total_summary_bar.dart:27` - 底部 Container 无 SafeArea(bottom)，手势导航机型系统导航条会遮挡"全部记录"按钮 (P2)

#### lib/features/recognize/dish_name_editor.dart
- `dish_name_editor.dart:33` - 改菜名 TextField 未显式 `autocorrect:false/enableSuggestions:false`（菜名为专有名词 autocorrect=true 易误改）(P2)
- `dish_name_editor.dart:33` - 改菜名 TextField 无 inputFormatters/maxLength，无长度上限 (P2)
- `dish_name_editor.dart:87` - showFoodSelectionDialog 的 ListTile title/subtitle Text 无 maxLines (P2)
- `dish_name_editor.dart:155` - **文案错误**："食物库未命中「改菜名」"——「改菜名」是按钮标签被误植进未命中提示，语义混乱，应为"食物库未命中此菜名"或去掉「改菜名」**(P1)**

#### lib/features/recognize/calibrated_nutrition_calculator.dart
- ✓ pass（纯计算类）

**Group B 总结**：0 P0 + 1 P1 + 33 P2

---

### Group C：数据展示 + 录入

#### lib/features/dashboard/today_meals_page.dart（739 行）
- `today_meals_page.dart:346-364` P1 - 删除 Undo SnackBar 未包 `Semantics(liveRegion: true)`，读屏不播报"已删除/撤销"
- `today_meals_page.dart:402-419` P1 - `Image.file` 食物缩略图无 `semanticLabel`（内容图，非装饰）
- `today_meals_page.dart:616-622` P1 - 反馈 dialog 份量 TextField 无 `inputFormatters`（系统性问题 #2）
- `today_meals_page.dart:227-237` P2 - `groups` Map 在 build 内每次重算，可缓存
- `today_meals_page.dart:280` P2 - ListView 无 SafeArea 底部缺口保护
- `today_meals_page.dart:379,557` P2 - 错误文案"删除失败：$e"/"保存失败：$e"含原始异常，缺修复步骤
- `today_meals_page.dart:610-614` P2 - 菜名 TextField 未显式 `autocorrect:false`
- `today_meals_page.dart:529` P1 - `showDialog` 调 MealEditDialog 未设 `barrierDismissible:false`，dirty 态误触屏障丢编辑

#### lib/features/dashboard/meal_edit_dialog.dart（396 行）
- `meal_edit_dialog.dart:291-296,352-378` P1 - 5 个数值 TextField 均无 `inputFormatters`（系统性问题 #2）
- `meal_edit_dialog.dart:239-244` P1 - `_save` 校验失败用 `showAppToast` 弹错，应改 `errorText` 内联（系统性问题 #3）
- `meal_edit_dialog.dart:261` P1 - AlertDialog 全程无 `_dirty`/`PopScope`/`confirmDiscardChanges`，屏障可误触关闭丢编辑（与 food_edit/manual_entry/profile 不一致）
- `meal_edit_dialog.dart:324-350` P2 - advanced 折叠 InkWell 高度≈40dp，<48 触控目标
- `meal_edit_dialog.dart:391` P2 - "保存"标签过泛，应"保存餐次"
- `meal_edit_dialog.dart:291-378` P2 - 数值 TextField 未显式 `autocorrect:false/enableSuggestions:false`

#### lib/features/food_library/food_library_page.dart
- `food_library_page.dart:170-172` P1 - 食物名 title Text 无 `maxLines/ellipsis`，长名（用户生成内容）会撑高/换行
- `food_library_page.dart:163` P2 - ListView.builder 无 SafeArea
- `food_library_page.dart:168-169` P2 - LeadingIconContainer 装饰图标未 `ExcludeSemantics`
- `food_library_page.dart:173-178` P2 - subtitle 营养行无 `maxLines`

#### lib/features/food_library/food_edit_page.dart
- `food_edit_page.dart:93-126` P1 - 5 个数值 TextField 无 `inputFormatters`（系统性问题 #2）
- `food_edit_page.dart:158-217` P1 - `_saveServingOnly/_saveAll` 校验走 `_showError`(toast)，应 `errorText`（系统性问题 #3）
- `food_edit_page.dart:76` P2 - AppBar `Text(f.name)` 无 `maxLines/ellipsis`
- `food_edit_page.dart:87` P2 - 来源说明 Text 无 `maxLines`
- `food_edit_page.dart:77` P2 - ListView 无 SafeArea
- ✓ `_dirty` + PopScope + confirmDiscardChanges 做得对

#### lib/features/manual_entry/manual_entry_page.dart
- `manual_entry_page.dart:118-123,154-159,170-196` P1 - 全部数值 TextField 无 `inputFormatters`（系统性问题 #2）
- `manual_entry_page.dart:224-281` P1 - `_logFromLibrary/_logCustom` 校验走 toast，应 `errorText`（系统性问题 #3）
- `manual_entry_page.dart:150-152` P2 - 食物名称 TextField 未显式 `autocorrect:false/enableSuggestions:false`
- `manual_entry_page.dart:95-99` P2 - 选择食物 ListTile title/subtitle 无 `maxLines`
- `manual_entry_page.dart:78` P2 - ListView 无 SafeArea
- `manual_entry_page.dart:135` P2 - "记录"标签过泛，应"记录餐次"

#### lib/features/weight/weight_page.dart（611 行）
- `weight_page.dart:111-117,494-499` P1 - 体重 TextField（录入+编辑 dialog）均无 `inputFormatters`（系统性问题 #2）
- `weight_page.dart:379-387` P1 - `_save` 校验走 toast，应 `errorText`（系统性问题 #3）
- `weight_page.dart:465` P1 - `subtitle: Text(log.date)` 直接显示 `YYYY-MM-DD` 原始串，应用 `intl DateFormat` 本地化
- `weight_page.dart:140` P2 - `_logs.reversed` 用 for 循环构建 ListView，宜 `ListView.builder`
- `weight_page.dart:105` P2 - ListView 无 SafeArea
- `weight_page.dart:130` P2 - "记录"标签过泛，应"记录体重"
- `weight_page.dart:291` P2 - 图表 tooltip `log.date` 原始串
- `weight_page.dart:295` P2 - tooltip TextStyle 硬编码 `fontSize: 12`
- `weight_page.dart:494-499` P2 - 编辑 dialog TextField 未 `autocorrect:false/enableSuggestions:false`
- `weight_page.dart:539` P2 - 编辑 dialog "保存"标签过泛
- `weight_page.dart:486` P2 - 编辑体重 dialog 内无 dirty 拦截
- ✓ `confirmDismiss` / `_busy` / `_dirty` / PopScope / tabularFigures 都对

#### lib/features/profile/profile_page.dart（600 行）
- `profile_page.dart:144-207,279-287` P1 - 身高/体重/年龄/体脂/目标速率数值 TextField 无 `inputFormatters`（系统性问题 #2）
- `profile_page.dart:170-179` P2 - 年龄 TextFormField 未 `autocorrect:false/enableSuggestions:false`
- `profile_page.dart:279-287` P2 - 目标速率 TextField 未 `autocorrect:false/enableSuggestions:false`
- `profile_page.dart:393` P2 - `validate()` 失败未滚动/聚焦首个错误字段
- `profile_page.dart:589-593` P2 - 风险提示 hints Text 无 `maxLines`
- `profile_page.dart:135` P2 - ListView 无 SafeArea
- ✓ Form + validator 内联 errorText 做得对（本组唯一）；`_dirty`/PopScope/`_busy` ✓；特殊人群风险 `confirmAction` ✓

#### lib/features/profile/nutrition_calculator.dart
- ✓ pass（纯函数计算模块）

**Group C 总结**：0 P0 + 16 P1 + 32 P2

---

### Group D：设置 + 系统

#### lib/features/settings/settings_page.dart（482 行）
- `settings_page.dart:139-147,148-157,158-166,167-176,198-205` P1 - 内联 TextField 均用 `border: InputBorder.none`，未设 focusedBorder，聚焦时无可见 focus ring，键盘用户无法辨别当前焦点
- `settings_page.dart:338` P1 - 错误信息 `'保存失败：$e'` 直接抛原始异常，无修复步骤（系统性问题 #4）
- `settings_page.dart:198-205` P2 - Sentry DSN TextField 缺 `keyboardType: TextInputType.url`；DSN 含密钥未设 `obscureText: true`
- `settings_page.dart:155,174` P2 - hintText 为 URL 示例未以 "…" 结尾，与项目惯例不一致
- `settings_page.dart:214-226` P2 - DropdownMenu 无 `label`，仅靠 ListTile title 提供语义，TalkBack 朗读时上下文断裂
- `settings_page.dart:235-237,243-245` P2 - trailing Text 用裸 `TextStyle(fontFeatures:…)`，未基于 textTheme
- `settings_page.dart:256-257` P2 - trailing Text `TextStyle(color: cs.onSurfaceVariant)` 未基于 textTheme
- `settings_page.dart:235,243` P2 - 次数/金额未用 `NumberFormat`
- `settings_page.dart:383` P2 - `TextStyle(fontSize: 12, color: …)` 硬编码字号
- `settings_page.dart:407-424` P2 - `kThemePresets.map(...).toList()` 在 build 内执行（12 项，量小可接受）

#### lib/features/backup/backup_page.dart（197 行）
- `backup_page.dart:119,154-178` **P1** - `_import()` 入口未检查 `_busy`；输入 dialog 关闭 → pendingCount 查询 → `setState(_busy=true)` 之间存在重入窗口，用户可再点"导出"导致导出与导入并发操作同一 DB
- `backup_page.dart:112` P1 - `'导出失败：$e'` 含原始异常，无修复步骤（系统性问题 #4）
- `backup_page.dart:191` P1 - `'导入失败：$e'` 含原始异常，无修复步骤（系统性问题 #4）
- `backup_page.dart:59-62` P2 - 说明文本无 `maxLines`/`overflow`，小屏可能溢出 Card
- `backup_page.dart:61-63` P2 - `TextStyle(fontSize: 13, color: cs.onSurfaceVariant)` 硬编码字号
- `backup_page.dart:104-105` P2 - 文件名日期手工拼接 `now.year}${now.month.toString().padLeft(2,'0')}…`，应使用 `DateFormat('yyyyMMdd_HHmm')`
- `backup_page.dart:108` P2 - `'已导出到 ${file.path}'` 路径可能很长，SnackBar 浮动模式下单行可能截断
- ✓ 备份恢复破坏性操作已用 `confirmAction` 二次确认 + pending>0 时额外提示离线队列清空

#### lib/features/update/update_page.dart（342 行）
- `update_page.dart:315-328` P1 - `AnimatedSize(duration: 300ms)` 未检查 `MediaQuery.accessibleNavigation`（系统性问题 #5）
- `update_page.dart:73` P1 - `'检查失败：$e'` 含原始异常，无修复步骤（系统性问题 #4）
- `update_page.dart:107` P1 - `'下载失败：$e'` 含原始异常，无修复步骤（系统性问题 #4）
- `update_page.dart:127` P1 - `'触发安装器失败：$e'` 含原始异常，无修复步骤（系统性问题 #4）
- `update_page.dart:237` P2 - `CircularProgressIndicator()` 无 semantics label，下载态对读屏用户无进度信息
- `update_page.dart:220` P2 - APK 大小 `(r.release.apkSize/1024/1024).toStringAsFixed(1) MB` 未用 `NumberFormat`
- `update_page.dart:243` P2 - 百分比/KB 数值未用 `NumberFormat`（已用 tabularFigures ✓）
- `update_page.dart:335` P2 - `TextStyle(color: cs.secondary)` 未基于 textTheme
- `update_page.dart:282` P2 - error 态按钮标签 `'重试'` 过于通用，无法区分重试检查还是重试下载

#### lib/core/widgets/m3_widgets.dart
- `m3_widgets.dart:321-330` **P1** - `showAppToast` 的 SnackBar 未包 `Semantics(liveRegion: true)`，异步更新对读屏用户无即时播报（全 App toast 都走此函数，影响面大，**系统性问题 #1 根因**）
- `m3_widgets.dart:137-141` **P1** - `EmptyState` 的 FilledButton.icon 硬编码 `Icons.camera_alt_rounded`，非拍照场景（如"暂无体重记录，去记录"）图标语义错误，应作为参数暴露
- `m3_widgets.dart:127,353,383,420,456` P2 - 装饰性 Icon 与同级 Text 语义重复，未包 `ExcludeSemantics`，读屏重复朗读
- `m3_widgets.dart:357` P2 - `TextStyle(color: cs.onSurfaceVariant, fontSize: 13)` 硬编码字号
- `m3_widgets.dart:387` P2 - `TextStyle(color: cs.error, fontSize: 12)` 硬编码字号
- `m3_widgets.dart:386` P2 - WarningBanner `Text(text)` 无 `maxLines`/`overflow`，长警告文案可能溢出 Row

#### lib/app.dart
- `app.dart:198-201` P2 - NavigationBar `labelTextStyle` 硬编码 `TextStyle(fontSize: 12, fontWeight: w600)`，注释说"M3 推荐用 labelMedium"但未实际使用 `tt.labelMedium`
- `app.dart:208-241` P2 - GoRouter 路由表无 `/update` 路由，UpdatePage 在 settings_page L270-272 用 `MaterialPageRoute` 直推，与其它页面的 GoRouter 导航方式不一致
- ✓ 主题配置（ColorScheme.fromSeed + dynamic_color + tonalSpot + edge-to-edge）合规；按钮 minimumSize 48dp ✓

#### lib/core/theme/theme_controller.dart
- ✓ pass（纯 Riverpod Notifier，无 UI）

#### lib/features/offline/offline_queue_controller.dart
- ✓ pass（纯控制器，无 Widget/BuildContext/Scaffold）
- **设计备注（P2，非 guideline 违规）**：后台回补成功后无任何用户可见反馈（不弹 toast/不更新 UI），用户不知道离线队列已处理完。建议处理完成后通过 ref 或事件总线通知 UI 层提示"已回补 N 条记录"

**Group D 总结**：0 P0 + 11 P1 + ~24 P2

---

## 5. 系统性问题（跨文件，根因集中）

### #1 showAppToast 缺 `Semantics(liveRegion: true)`【P1，影响全 App】
- **根因**：`lib/core/widgets/m3_widgets.dart:321-330`
- **影响范围**：dashboard_page / recognize_page / today_meals_page / food_edit_page / manual_entry_page / weight_page / profile_page / settings_page / backup_page / update_page / calibration_page / multi_dish_page 全部 toast 反馈
- **修复方式**：在 `showAppToast` 的 SnackBar content 外包一层 `Semantics(liveRegion: true, child: ...)`，一次性覆盖全 App

### #2 数值 TextField 普遍缺 `inputFormatters`【P1，7 个文件】
- **影响文件**：calibration_page / meal_edit_dialog / food_edit_page / manual_entry_page / weight_page / profile_page / today_meals_page（反馈 dialog）
- **风险**：物理键盘可输入字母/多小数点，仅 `double.tryParse` 静默丢弃无效输入
- **修复方式**：数值 TextField 统一加 `inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))]` + `maxLength: 10`

### #3 校验错误走 SnackBar 而非 `errorText` 内联【P1，5 个文件】
- **影响文件**：meal_edit_dialog / food_edit_page / manual_entry_page / weight_page
- **现状**：profile_page 是本组唯一用 `Form + validator + errorText` 做对的页面
- **修复方式**：改用 `Form + TextFormField + validator` + `errorText` 内联显示，聚焦第一个错误字段

### #4 错误信息含原始异常无修复步骤【P1，9 处】
- **影响位置**：
  - `insight_page.dart:467` '生成失败：$e'
  - `today_meals_page.dart:379,557` '删除失败：$e' / '保存失败：$e'
  - `calibration_page.dart:849,992` '改菜名失败：$e' / '记录失败：$e'
  - `multi_dish_page.dart:524` '记录失败：$e'
  - `settings_page.dart:338` '保存失败：$e'
  - `backup_page.dart:112,191` '导出失败：$e' / '导入失败：$e'
  - `update_page.dart:73,107,127` '检查失败：$e' / '下载失败：$e' / '触发安装器失败：$e'
- **修复方式**：错误文案改为 `<操作>失败：<原因推测>。<修复步骤>`（如"导出失败：存储空间不足或权限被拒。请检查存储权限后重试。"），原始异常仅 debugPrint 不暴露给用户

### #5 部分动画未检查 `MediaQuery.accessibleNavigation`【P1/P2】
- **影响位置**：
  - `recognize_progress_card.dart:75,175,185` TweenAnimationBuilder / AnimatedContainer / AnimatedSwitcher（P2）
  - `insight_page.dart:597,614` AnimatedSwitcher（P2）
  - `update_page.dart:315-328` AnimatedSize（P1）
  - `recognize_page.dart:361-369` 识别遮罩动画（P2）
- **修复方式**：读 `MediaQuery.accessibleNavigation` / `disableAnimations`，true 时降级为瞬时切换或 0ms duration

### #6 装饰图标未 `ExcludeSemantics`【P2，多处】
- **影响位置**：insight_page 5 处 / recognize_progress_card 2 处 / ai_estimate_card 2 处 / m3_widgets 5 处 / food_library 1 处 / today_meals_section
- **风险**：读屏会朗读图标名（如"心理学图标"）与同级 Text 语义重复
- **修复方式**：装饰性 Icon 统一包 `ExcludeSemantics(child: Icon(...))`

### #7 长文本缺 `maxLines + TextOverflow.ellipsis`【P2，多处】
- **影响位置**：calibration_page 菜名 / dish_card 菜名 / food_library 食物名 / manual_entry ListTile / weight tooltip / today_meals_section / recommendation_section / status_card_section 宏量值
- **风险**：用户生成内容（菜名/食物名/备注）可能很长，无限换行撑高布局
- **修复方式**：用户生成内容 Text 统一加 `maxLines: 1` + `TextOverflow.ellipsis`（多行场景 `maxLines: 2`）

### #8 硬编码 `fontSize`【P2，多处】
- **影响位置**：insight_page 图表区 6+ 处 / ai_estimate_card 3 处 / calibration_page 4 处 / recognize_progress_card 2 处 / weight tooltip / m3_widgets 2 处 / settings_page / ai_rec_item
- **修复方式**：硬编码 `fontSize: 10/11/12/13` 改用 `textTheme.labelSmall(11)/labelMedium(12)/bodySmall(12)/bodyMedium(14)`

### #9 `ListView` 普遍缺 `SafeArea` 底部保护【P2，6 个文件】
- **影响文件**：today_meals_page / food_library_page / food_edit_page / manual_entry_page / weight_page / profile_page
- **风险**：手势导航机型底部系统导航条可能遮挡末尾内容/按钮
- **修复方式**：`ListView(padding: EdgeInsets.only(bottom: MediaQuery.contextViewPaddingOf(context).bottom + 16))` 或外层包 `SafeArea(bottom: true)`

### #10 数字列缺 `FontFeature.tabularFigures()`【P2，多处】
- **影响位置**：dish_card 份量 / ai_estimate_card 置信度+对比行 / insight_page 数值轴标签
- **风险**：数字变化时宽度跳动，视觉不稳定
- **修复方式**：数字 Text 的 `style: TextStyle(fontFeatures: [FontFeature.tabularFigures()])`

### #11 日期硬编码 `padLeft` 拼接【P2】
- **影响位置**：`lib/core/util/date_format.dart:9` formatYmd 手写 + `today_meals_section.dart:110` _formatTime + `weight_page.dart:465,291` log.date 原始串 + `insight_page.dart:827,836,903` 图表轴日期 + `backup_page.dart:104-105` 文件名日期
- **修复方式**：统一用 `intl DateFormat`（`DateFormat.yMd()` / `DateFormat.Hm()` / `DateFormat('yyyyMMdd_HHmm')`）

---

## 6. 做得好的地方（值得肯定）

- **防重入全覆盖**：`_isRecording`/`_busy`/`_isRenaming`/`_aiRegenerating`/`_rating` 在所有写库按钮 + try-catch-finally + `mounted` 检查
- **`_dirty` + `confirmDiscardChanges` 一致落地**：food_edit / manual_entry / weight / profile / calibration 五页一致
- **破坏性操作二次确认**：`confirmAction` / `confirmDismiss` / `PopScope` 全覆盖；backup_page pending>0 时额外提示离线队列清空
- **`「」` 中文引号统一**：全 App 未发现 `""` 误用
- **`…` 省略号正确**：全 App 未发现 `...` 误用（Loading/生成中/选图中…）
- **`colorScheme` 配色全覆盖**：无 0xFF 硬编码颜色（仅 `recognize_progress_card.dart:204` 一处 `Colors.white`）
- **`tabularFigures` 在数字列普遍应用**：状态卡 / 数字卡片 / today_meals / weight 图表
- **`ListView.builder` 用于大列表**：food_library / multi_dish / dish_name_editor 候选列表
- **`Form + validator + errorText`**：profile_page 是本组唯一做对的页面（其它应参照）
- **删除餐次用 Undo SnackBar**：优于纯删除，给用户反悔窗口
- **M24 B5 已拆分大文件**：dashboard_page / multi_dish_page 都 < 600 行
- **`IconButton` 普遍有 `tooltip`**：全 App 唯一缺 tooltip 的位置在 deep audit 后未发现
- **`EmptyState` / `ErrorState` / `LoadingState` 空态守卫**：m3_widgets 封装统一
- **特殊人群风险 `confirmAction`**：profile_page 营养计算器风险提示有二次确认

---

## 7. 修复优先级建议

### 优先级 1（P1，系统性问题，一次修复多文件受益）

| # | 问题 | 根因文件 | 影响范围 | 修复成本 |
|---|------|---------|---------|---------|
| 1 | showAppToast 缺 liveRegion | m3_widgets.dart:321 | 全 App toast | 低（1 处） |
| 2 | EmptyState 硬编码 camera 图标 | m3_widgets.dart:137 | 非拍照场景空态 | 低（1 处） |
| 3 | dish_name_editor 文案错误 | dish_name_editor.dart:155 | 改菜名未命中提示 | 低（1 处） |
| 4 | backup_page _import 重入窗口 | backup_page.dart:119 | 备份恢复并发风险 | 低（1 处） |
| 5 | settings_page TextField focus ring | settings_page.dart:139-205 | 键盘无障碍 | 中（5 处） |
| 6 | meal_edit_dialog 无 dirty 拦截 | meal_edit_dialog.dart:261 | 误触屏障丢编辑 | 低（1 处） |
| 7 | 数值 TextField 缺 inputFormatters | 7 个文件 | 输入离谱字符 | 中（批量） |
| 8 | 校验错误走 toast 而非 errorText | 4 个文件 | 错误反馈不内联 | 中（参照 profile_page） |
| 9 | 错误信息含原始异常无修复步骤 | 9 处 | 错误文案不友好 | 中（逐个改写） |
| 10 | update_page AnimatedSize reduced-motion | update_page.dart:315 | 无障碍 | 低（1 处） |

### 优先级 2（P2 高频模式，批量整改）

| # | 问题 | 影响范围 | 修复成本 |
|---|------|---------|---------|
| 11 | 装饰图标未 ExcludeSemantics | 15+ 处 | 中（批量包） |
| 12 | 长文本缺 maxLines+ellipsis | 10+ 处 | 中（逐个加） |
| 13 | 硬编码 fontSize | 15+ 处 | 中（批量改 textTheme） |
| 14 | ListView 缺 SafeArea | 6 个文件 | 低（批量加） |
| 15 | 数字列缺 tabularFigures | 5+ 处 | 低（批量加） |
| 16 | 日期硬编码 padLeft | 5+ 处 | 中（统一 intl） |
| 17 | Colors.white 硬编码 | 1 处 | 低 |
| 18 | NavigationBar labelTextStyle 硬编码 | 1 处 | 低 |
| 19 | GoRouter 路由不一致（/update） | 1 处 | 低 |

### 优先级 3（P2 细节，可后续打磨）

- 按钮标签具体化（"保存"→"保存餐次"/"记录"→"记录体重"）
- hintText 末尾 `…` 一致性
- DropdownMenu 加 `label`
- CircularProgressIndicator 加 semantics label
- 风险提示 Text 加 `maxLines`
- offline_queue_controller 后台回补成功后用户可见反馈

---

## 8. Assumptions & Decisions（假设与决策）

1. **审查准则映射**：Web Interface Guidelines 原为 React/HTML 设计，本项目是 Flutter 移动 App。已将 Web 准则精神映射到 Flutter 等价物（如 `aria-label` → `tooltip`、`aria-live` → `Semantics(liveRegion:)`、`aria-hidden` → `ExcludeSemantics`、`prefers-reduced-motion` → `MediaQuery.accessibleNavigation`、`Intl.DateTimeFormat` → `intl DateFormat` 等）。
2. **审查范围**：全部 26 个 UI 页面文件（11514 行），不含纯计算类（nutrition_calculator / calibrated_nutrition_calculator / nutrition_preview / theme_controller / offline_queue_controller / dashboard_data）。
3. **产出形式**：只出审查报告，不改代码（用户决策）。
4. **优先级定义**：
   - P0 严重：崩溃 / 无障碍完全不可用 / 数据丢失风险
   - P1 重要：明显体验问题 / 无障碍部分缺失 / 文案错误 / 性能问题
   - P2 改进：细节优化 / 一致性 / 视觉打磨
5. **Flutter Material 3 默认合规**：Material 3 组件（IconButton / TextField / Card 等）默认满足触控目标 ≥48dp / focus 反馈 / hover 反馈，审查时不再重复列出，只列偏离 Material 3 默认的问题。

---

## 9. Verification（验证方式）

本报告为审查报告，无代码改动，无需运行验证。如用户后续选择修复，验证方式为：
- `flutter analyze` → No issues found
- `flutter test` → 全量通过，0 回归
- 6+1 硬约束全部满足（未碰 build.gradle / meal_log 外键 / AI 三路径 / per100g 反算基于 mid / SecureConfigStore / initSentryAndRunApp / minSdk=31）

---

## 10. 下一步建议

报告已完成，共发现 0 P0 + 30 P1 + ~109 P2。

建议你审阅后决定：
1. 是否要修复？修复哪些优先级（P1 全部 / P1+P2 高频模式 / 全部）？
2. 修复策略：一次全修 vs 分批修（按优先级分批 commit）？
3. 是否要补强某些审查维度（如视觉一致性 / 信息架构 / 用户流程，本次只审 Web Interface Guidelines 维度）？

等你的决策。
