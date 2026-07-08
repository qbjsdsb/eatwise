# D9 UX 无障碍检查报告

**检查日期**：2026-07-08
**检查范围**：EatWise v0.33.0+46
**HEAD commit**：`b140745`（`feat: 了解项目进展`）
**git status**：lib/ 无改动；仅 `docs/audit/` 下存在其它维度未跟踪报告
**检查方法**：Grep（semanticsLabel/tooltip/fontSize/Color/Colors./FocusNode/errorText/textScaler/Semantics/GestureDetector）+ 关键文件通读（`app.dart`、`main.dart`、`core/widgets/m3_widgets.dart`、`theme_controller.dart`、`main_shell.dart`、`recognize_page.dart`、`profile_page.dart`、`today_meals_page.dart`、`me_page.dart`、`update_page.dart`、`food_edit_page.dart`、`recommendation_section.dart`、`ai_rec_item.dart`、`settings_page.dart`、`recognize_progress_card.dart` 等）+ 既有无障碍测试通读（`test/features/icon_button_accessibility_test.dart` 等）

> 方法论备注：本审计的"统计结论"以 Grep `content` 模式（带行号、可回溯原文）和直接 Read 文件的结果为准。Grep `count` 模式在并行调用时观察到跨模式缓存串扰（同一文件列表被不同 pattern 返回），故计数类结论已用 content 模式复核。

## 总体评价

EatWise 的无障碍基础**整体良好**，明显优于同类个人项目平均水平。项目已建立统一的 M3 公共组件层（`LoadingState`/`ErrorState`/`EmptyState`/`EmptyChartHint`/`WarningBanner`/`HeroCard`/`GroupCard`），并在多处主动用 `ExcludeSemantics` 排除装饰性图标、用 `Semantics(liveRegion: true)` 让读屏用户即时感知 toast/删除反馈；触摸目标在主题层全局提升到 48dp；颜色几乎全部走 `ColorScheme` 角色，无硬编码 ARGB。存在的主要不足集中在**固定字号不随系统缩放**和**表单缺焦点流管理**，均为 P1/P2 级，无 P0 级"无法使用"问题。

## 检查项与结果

| # | 检查项 | 结论 | 关键证据 |
|---|--------|------|---------|
| 1 | Semantics 标注（IconButton tooltip / 装饰图 ExcludeSemantics / 表单 labelText） | ✅ 良好 | 全部 9 个 `IconButton` 均带 `tooltip`；`ExcludeSemantics` 在 16 文件广泛用于 chevron/装饰图标；表单 `TextField` 均有 `labelText` |
| 2 | 字号缩放（textScaler / TextTheme / 硬编码 fontSize） | ⚠️ 部分 | 0 处 `textScaler`/`textScaleFactor`；多数文本走 `TextTheme`（随系统缩放）；但 44 处硬编码 `fontSize`（多为 10/11/12）不随系统缩放 |
| 3 | 触摸目标 ≥48dp | ✅ 良好（个别 P2） | `app.dart` 主题层全局 `FilledButton/TextButton/OutlinedButton/SegmentedButton` minimumSize 48；色块 48×48（有测试）；个别 `InkWell` 文本触控区偏小 |
| 4 | 对比度 | ✅ 良好（个别 P2） | `ColorScheme.fromSeed` 生成 WCAG 友好配色；chip 用 `onContainer`/`container`；色块勾选用 `computeLuminance` 选黑/白；个别 `Colors.white` 应改 `onPrimary` |
| 5 | 键盘导航/焦点（FocusNode / 提交后焦点 / 物理键盘） | ⚠️ 弱 | 0 处 `FocusNode`；表单靠 `labelText`+`errorText` 可用但无焦点流转；无物理键盘快捷键 |
| 6 | 错误反馈（内联 errorText / 非 toast-only） | ✅ 良好 | 14 处 `errorText:` 内联校验（food_edit/manual_entry/meal_edit/weight）；`ErrorState` 组件用于 FutureBuilder 错误；删除走 SnackBar+`liveRegion`+撤销 |
| 7 | 加载/空状态（Loading/Error/Empty 一致性） | ✅ 优秀 | `m3_widgets.dart` 统一抽象 4 类状态组件，跨页一致复用；`profile_page` 用 `_loadError` 区分"加载失败"与"空表单" |
| 8 | 国际化（ARB / 硬编码中文） | ⚠️ 硬编码（个人自用可接受） | 0 个 `.arb`、0 处 `intl`、无 `localizationsDelegates`/`supportedLocales`；全部中文硬编码 |
| 9 | 暗色模式完整性 | ✅ 良好（个别 P2） | `app.dart` 定义 `darkTheme`+`themeMode: system`；0 处 `Color(0xFF...)` 硬编码；个别 `Colors.white`/`Colors.green` 不随主题 |

## 发现的问题

### P0（严重）

无。本次检查未发现导致功能无法使用的无障碍问题。

### P1（高优先级）

**P1-1：44 处硬编码 `fontSize` 不随系统字号缩放，影响大字号/视障用户可读性**

- **位置（按密度）**：
  - `lib/features/insight/insight_page.dart`：约 20 处 `fontSize: 10/11/12`（图表轴标签、图例、tooltip、月度明细等）
  - `lib/features/recognize/calibration_page.dart`：414/612/683/847/1001 行 `fontSize: 12/11`
  - `lib/features/recognize/multi_dish/dish_card.dart`：100/145/169/212/252 行 `fontSize: 11/12`
  - `lib/features/recognize/multi_dish/ai_estimate_card.dart`：102/133/162 行 `fontSize: 10/11`
  - `lib/core/widgets/m3_widgets.dart`：374（`EmptyChartHint`）、404（`WarningBanner`）`fontSize: 13/12`
  - `lib/app.dart`：199/201 `NavigationBar` labelTextStyle `fontSize: 12`
  - `lib/features/dashboard/dashboard/ai_rec_item.dart`：189 `_ratedChip` `fontSize: 10`
  - `lib/features/weight/weight_page.dart`：626 `fontSize: 12`
  - `lib/features/backup/backup_page.dart`：64 `fontSize: 13`
  - `lib/features/settings/settings_page.dart`：392 `fontSize: 12`
- **影响**：用户在系统设置开启大字号后，这些文本不放大。其中 `fontSize: 10`（insight 图表轴/图例、ai_rec_item chip）在默认字号下已偏小，大字号用户更难辨识。
- **现状 mitigations**：`profile_page.dart:267` 注释明确"labelSmall 替代硬编码 fontSize: 11，跟随系统字号缩放"，说明团队已有意识，但未全量推行；`app.dart` 主体文本走 `TextTheme`。
- **建议**：优先把 `fontSize: 10/11` 这类极小字号替换为 `textTheme.labelSmall/bodySmall`（14sp 基线，随系统缩放）；图表轴标签等空间受限场景可用 `MediaQuery.textScalerOf(context).scale(...)` 显式受控缩放，而非完全写死。

### P2（中低优先级）

**P2-1：`recognize_progress_card.dart` 用 `Colors.white` 而非 `cs.onPrimary`，存在暗色/浅种子对比度风险**

- **位置**：`lib/features/recognize/recognize_progress_card.dart:204`（`CircularProgressIndicator` 的 `valueColor: AlwaysStoppedAnimation(Colors.white)`）、`:212`（`Icon(Icons.check, color: Colors.white)`）
- **上下文**：这些元素绘制在 `colorScheme.primary` 实心填充圆上（`_StatusCircle`，`:170` `fillColor = colorScheme.primary`）。
- **问题**：`ColorScheme.fromSeed` 在某些种子色（浅色调）下 `primary` 偏亮，`onPrimary` 才是保证对比度的对应前景色。写死 `Colors.white` 在浅色 primary 上对比度可能不足 WCAG AA。
- **对比**：同项目 `settings_page.dart:481` 色块勾选图标已用 `computeLuminance() > 0.5 ? Colors.black : Colors.white` 动态选色（规范做法），此处未对齐。
- **建议**：改为 `cs.onPrimary`（最简）或复用 `computeLuminance` 动态选色。

**P2-2：`weight_page.dart` 蓝牙已连接图标硬编码 `Colors.green`**

- **位置**：`lib/features/weight/weight_page.dart:409` `Icon(Icons.bluetooth_connected, color: Colors.green)`
- **问题**：`Colors.green` 是 MD2 调色板固定值，不随主题种子/暗色模式变化；与项目"宏量营养素用 `MacroColors` 走 `ColorScheme` 角色"的规范不一致（`m3_widgets.dart:81-94` 注释明确反对硬编码 MD2 调色板）。
- **现状**：同文件 `:422` 蓝牙错误图标已正确用 `Theme.of(context).colorScheme.error`，说明此处是遗漏。
- **缓解**：绿色作为"已连接/成功"语义色尚可接受，不会导致不可用；但暗色模式下 `Colors.green` 偏亮可能与背景对比欠佳。
- **建议**：用 `cs.tertiary` 或新增一个成功语义角色；至少改用 `ColorScheme` 衍生色。

**P2-3：表单缺 `FocusNode` 管理，无字段间焦点流转**

- **位置**：全仓 0 处 `FocusNode`。涉及多字段表单：`profile_page`（身高/体重/年龄/体脂/目标速率）、`food_edit_page`（5 个营养字段）、`manual_entry_page`（热量/蛋白/脂肪/碳水）、`meal_edit_dialog`。
- **现状**：表单仍可用——`TextField` 自带点击聚焦、键盘出现；校验错误以 `errorText` 内联显示（14 处，做法正确）。
- **问题**：①无"下一个"键盘动作流转（`textInputAction: TextInputAction.next` + `focusNode.requestFocus`）；②提交失败后不会自动聚焦到出错字段；③接外接键盘时无法 Tab 遍历。
- **影响**：对纯触屏个人用户影响小；对使用外接键盘/蓝牙键盘的用户体验下降。
- **建议**：个人自用可暂不处理；若要改进，优先给 `food_edit_page`/`manual_entry_page` 加 `FocusNode` + `TextInputAction.next` 流转。

**P2-4：`today_meals_page` 日期选择 `InkWell` 触控区高度可能 <48dp**

- **位置**：`lib/features/dashboard/today_meals_page.dart:114-128`（"今天/dateText" 可点区域）
- **现状**：`InkWell` 包 `Padding(EdgeInsets.symmetric(horizontal: 12, vertical: 8))` + `Text`（`titleMedium`，约 16sp）。估算高度 ≈ 16(text) + 16(vertical padding) = 32dp，低于 48dp。
- **对比**：左右两侧 `IconButton`（前一天/后一天）默认 48dp 已达标。
- **影响**：日期切换点击偏小，手指粗或运动障碍用户可能误触相邻按钮。
- **建议**：把 `vertical: 8` 加大到 `16`，或套 `SizedBox(height: 48)` + `Center`，并补 `Tooltip`/`Semantics(button: true, label: '选择日期')`。

**P2-5：无国际化框架，全部中文硬编码**

- **位置**：0 个 `.arb` 文件；`pubspec.yaml` 无 `intl`/`flutter_localizations` 依赖；`app.dart` 的 `MaterialApp.router` 未设 `localizationsDelegates`/`supportedLocales`。
- **现状**：所有 UI 文案为中文常量（如 `'前一天'`/`'放弃修改？'`/`'已删除'`）。
- **结论**：**个人自用 app 可接受**（任务说明明确豁免）。仅作记录，非必须修复。
- **潜在影响**：若未来分享给非中文用户，需全量抽字符串；`confirmDiscardChanges`/`confirmAction`/`showAppToast` 等公共组件已集中文案，迁移成本可控。

**P2-6：`GestureDetector` 未用于可交互元素（已是正确实践，记录确认）**

- 全仓 `GestureDetector` 仅 1 处出现，且是 `settings_page.dart:456` 的**注释**（"GestureDetector 无 state layer，违反 M3 规范"），实际可点元素一律用 `Material`+`InkWell`+`Tooltip`（如 `settings_page._colorDot`）。这是优于多数项目的正确做法，读屏可识别 ripple 语义。无问题，记录以正视听。

## 改进建议

### 优先级排序

1. **（P1）统一字号策略**：把 `insight_page` / `calibration_page` / `multi_dish` / `ai_rec_item` 中 `fontSize: 10/11` 的文本替换为 `textTheme.labelSmall`（14sp）或 `bodySmall`（12sp），让大字号用户受益。图表轴标签等确实需要小字号的，用 `MediaQuery.textScalerOf(context).scale(10)` 显式受控缩放，而非 `fontSize: 10` 写死。可在 `analysis_options.yaml` 加 `avoid_hardcoded_font_sizes` lint 规则防回潮。

2. **（P2）对齐前景色规范**：`recognize_progress_card.dart` 的 `Colors.white` → `cs.onPrimary`；`weight_page.dart:409` 的 `Colors.green` → `ColorScheme` 角色。统一后暗色模式对比度更有保障。

3. **（P2）补关键 `InkWell` 触控目标与语义**：`today_meals_page` 日期 `InkWell` 加高到 48dp + `Semantics(button: true, label: '选择日期')`。

4. **（P2，可选）表单焦点流**：给 `food_edit_page`、`manual_entry_page` 多字段表单加 `FocusNode` + `TextInputAction.next`，提升外接键盘体验。

5. **（可选）读屏增强**：`recognize_page` 识别状态变化（idle→recognizing→done/error）可考虑 `SemanticsService.announce` 主动播报，让视障用户不依赖视觉进度卡片。当前仅 `today_meals` 删除 toast 和 `recognize_page:576` 用了 `liveRegion`，识别主流程的状态切换未被读屏感知。

### 值得保持的良好实践（不要回退）

- `m3_widgets.dart` 的公共状态组件抽象（`LoadingState/ErrorState/EmptyState/EmptyChartHint/WarningBanner`）——继续在所有新页面复用，不要各页手写。
- `showAppToast` 内置 `Semantics(liveRegion: true)` + `clearSnackBars`——所有新提示走此函数，不要散落 `showSnackBar`。
- 装饰性 chevron/图标统一 `ExcludeSemantics`——`me_page`/`food_library`/`manual_entry`/`recommendation_section`/`ai_rec_item` 已形成约定，保持。
- `IconButton` 一律带 `tooltip`——9/9 覆盖，保持；`test/features/icon_button_accessibility_test.dart` 已有用例守门，建议扩展为全量回归。
- 主题层全局 48dp 触摸目标——`app.dart` 已统一提升 `TextButton/OutlinedButton/FilledButton/SegmentedButton`，不要在新组件单独写小尺寸。
- `settings_page._colorDot` 的 `Tooltip + Material + InkWell + 48×48 + ExcludeSemantics(勾选) + computeLuminance 选色`——作为自定义可点色块的参考范式。

## 结论

EatWise v0.33.0+46 在 D9 UX 无障碍维度**无 P0 问题**，有 1 项 P1（硬编码字号不随系统缩放）与 5 项 P2。项目已具备扎实的无障碍基础（统一状态组件、广泛 `ExcludeSemantics`、`liveRegion` 反馈、48dp 触摸目标、全 `ColorScheme` 配色），主要改进空间在字号缩放一致性、个别硬编码前景色、表单焦点流。鉴于项目定位为个人自用，当前状态可接受；P1 建议在下一个迭代处理，P2 可视精力渐进修复。
