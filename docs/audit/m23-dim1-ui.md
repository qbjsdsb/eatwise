# M23 维度 1：UI 界面规范审查

## 审查依据

- **Web Interface Guidelines**（拉取日期 2026-07-05，源 https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md）
  - 适用 Flutter 的规则摘要：加载态结尾用 `…`、错误信息含下一步、空态不渲染破损 UI、长内容用 truncate/line-clamp、列表 >50 项虚拟化、数值列用 tabular-nums、破坏性操作需二次确认、触控目标≥48dp、hover/active 增强对比、主动语态 + Title Case、数字用阿拉伯数字、跳过纯 web 规则（HTML 语义化/ARIA/URL state sync 等）。
- **Material 3 Expressive 规范**：基础间距 4/8/16/24 倍数；Card 圆角 12（medium）/28（hero）；触控目标≥48dp；最小可读字号 12；容器色配对色（onXxxContainer）保证 WCAG AA 4.5:1；加载/空/错三态显式区分；动效用 transform/opacity。

## 审查范围

14 个 feature 页面 + 1 个公共组件 + 1 个进度卡片（共 17 文件）：

- [dashboard_page.dart](file:///workspace/lib/features/dashboard/dashboard_page.dart)
- [today_meals_page.dart](file:///workspace/lib/features/dashboard/today_meals_page.dart)
- [meal_edit_dialog.dart](file:///workspace/lib/features/dashboard/meal_edit_dialog.dart)
- [food_library_page.dart](file:///workspace/lib/features/food_library/food_library_page.dart)
- [food_edit_page.dart](file:///workspace/lib/features/food_library/food_edit_page.dart)
- [insight_page.dart](file:///workspace/lib/features/insight/insight_page.dart)
- [manual_entry_page.dart](file:///workspace/lib/features/manual_entry/manual_entry_page.dart)
- [me_page.dart](file:///workspace/lib/features/me/me_page.dart)
- [profile_page.dart](file:///workspace/lib/features/profile/profile_page.dart)
- [recognize_page.dart](file:///workspace/lib/features/recognize/recognize_page.dart)
- [calibration_page.dart](file:///workspace/lib/features/recognize/calibration_page.dart)
- [multi_dish_page.dart](file:///workspace/lib/features/recognize/multi_dish_page.dart)
- [records_tab_page.dart](file:///workspace/lib/features/records/records_tab_page.dart)
- [settings_page.dart](file:///workspace/lib/features/settings/settings_page.dart)
- [update_page.dart](file:///workspace/lib/features/update/update_page.dart)
- [weight_page.dart](file:///workspace/lib/features/weight/weight_page.dart)
- [backup_page.dart](file:///workspace/lib/features/backup/backup_page.dart)
- 辅助：[m3_widgets.dart](file:///workspace/lib/core/widgets/m3_widgets.dart) + [recognize_progress_card.dart](file:///workspace/lib/features/recognize/recognize_progress_card.dart)

## 6 条硬约束检查

UI 审查中**未发现**违反 6 条硬约束的情况：
1. `build.gradle.kts` minify/shrink — 不在 UI 范围
2. `meal_log.food_item_id` 非空外键 — `recognize_page.dart:67-68` 注释明确"必须有有效 food_item_id"，写库前 `upsertAiRecognized` 替换哨兵，UI 路径无违反
3. AI 兜底三路径 — UI 不涉及（recognize/multi_dish/offline_queue 均有显式哨兵分支处理）
4. per100g 反算基于 `estimatedWeightGMid` — UI 不涉及（计算在 CalibratedNutritionCalculator）
5. `SecureConfigStore` 无 `instance` — UI 范围内调用均为 `container.read(secureConfigStoreProvider)` 或 `ref.read(secureConfigStoreProvider)`，未误用
6. `initSentryAndRunApp` 命名参数 — 不在 UI 范围

## 发现清单

### 1.1 间距与视觉层级

- [P2] [food_edit_page.dart:84](file:///workspace/lib/features/food_library/food_edit_page.dart#L84) 数据来源 Card 内 `padding: EdgeInsets.all(12)`，应为 16
  - 现状：`Padding(padding: EdgeInsets.all(12), child: Row(...))`
  - 影响：与同页其他 Card（无显式 padding，默认 16）+ manual_entry/profile/calibration 同类 Card 内 padding=16 不一致
  - 建议修复：改为 `EdgeInsets.all(16)`
  - 工作量：5 分钟

- [P2] [multi_dish_page.dart:224](file:///workspace/lib/features/recognize/multi_dish_page.dart#L224) `_buildDishCard` Card 内 `padding: EdgeInsets.all(12)`，应为 16
  - 现状：每个菜品卡片 padding=12，列表项视觉密度偏高
  - 影响：与 today_meals _buildMealCard padding=16、dashboard 推荐卡片 padding=16 不一致
  - 建议修复：改为 `EdgeInsets.all(16)`
  - 工作量：5 分钟

- [P2] [profile_page.dart:558](file:///workspace/lib/features/profile/profile_page.dart#L558) `_buildSpecialConditionHint` Card 内 `padding: EdgeInsets.all(12)`，应为 16
  - 现状：风险提示 Card padding=12
  - 影响：与同页基本信息/活动量/目标 Card 的 padding=16 不一致
  - 建议修复：改为 `EdgeInsets.all(16)`
  - 工作量：5 分钟

- [P2] [update_page.dart:208](file:///workspace/lib/features/update/update_page.dart#L208) release notes Card 内 `padding: EdgeInsets.all(12)`，应为 16
  - 现状：更新说明 Card padding=12
  - 影响：与同页其他元素 padding=24 不协调
  - 建议修复：改为 `EdgeInsets.all(16)`
  - 工作量：5 分钟

- [P2] [today_meals_page.dart:287](file:///workspace/lib/features/dashboard/today_meals_page.dart#L287) ListView `padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)`，水平应为 16
  - 现状：列表水平 padding=12
  - 影响：与 dashboard（horizontal:16）、weight_page（all:16）、manual_entry（all:16）等同类 ListView 不一致；同文件 L382 注释自述"内 padding 16 统一 dashboard"，但 ListView 外层 padding 实际是 12，注释与代码不符
  - 建议修复：改为 `EdgeInsets.symmetric(horizontal: 16, vertical: 8)`
  - 工作量：5 分钟

- [P2] [recognize_page.dart:302](file:///workspace/lib/features/recognize/recognize_page.dart#L302) Hero 区 `SizedBox(height: 20)`，不是 4/8/16/24 基础单位倍数
  - 现状：图标与标题间距 20dp
  - 影响：违反 MD3 8dp grid 规范，应为 16 或 24
  - 建议修复：改为 `SizedBox(height: 24)`（与下方 SizedBox(height: 8) 形成层级）
  - 工作量：2 分钟

- [P2] [calibration_page.dart:248](file:///workspace/lib/features/recognize/calibration_page.dart#L248) AI 推理过程 ExpansionTile `tilePadding: EdgeInsets.symmetric(horizontal: 12)`，应为 16
  - 现状：折叠标题左右 padding=12
  - 影响：与同页 Card(padding:16) 内边距不齐
  - 建议修复：改为 `EdgeInsets.symmetric(horizontal: 16)`
  - 工作量：2 分钟

### 1.2 加载态 / 空态 / 错误态

- [P1] [insight_page.dart:394-405](file:///workspace/lib/features/insight/insight_page.dart#L394) 周/月切换时无 loading 指示，图表直接消失再出现
  - 现状：`onSelectionChanged` 内 `setState(() { _dailyCal = []; _dailyWeight = []; ... _loadExisting(); })`，`_loadExisting` 是 async（聚合 + DB 查询），期间图表区直接显示 EmptyChartHint（"暂无足够数据"），误导用户以为该周期无数据
  - 影响：用户切换周/月时看到"暂无足够热量数据"闪现，体验突兀；与 dashboard FutureBuilder 显式 LoadingState 不一致
  - 建议修复：新增 `_chartLoading` 标志，切换时置 true 显示 LoadingState，`_loadExisting` 完成后置 false
  - 工作量：30 分钟

- [P1] [food_library_page.dart:55-59](file:///workspace/lib/features/food_library/food_library_page.dart#L55) `_loadFrequent` 异常被静默吞掉，无错误提示
  - 现状：`catch (_) { // 加载失败保持空列表，UI 显示空态 }`，仅 finally 关 `_initialLoading`
  - 影响：DB 异常时用户看到"暂无常用食物"空态，与"DB 加载失败"语义不同，误导用户以为没记录过食物；无重试入口
  - 建议修复：新增 `_loadError` 标志，catch 内置 true，UI 显示 ErrorState + 重试按钮（与 today_meals_page.dart:258-268 同构）
  - 工作量：30 分钟

- [P1] [food_library_page.dart:95-102](file:///workspace/lib/features/food_library/food_library_page.dart#L95) `_doSearch` 异常被静默吞掉，清空结果无提示
  - 现状：`catch (_) { setState(() { _searchResults = []; _searchLoading = false; }); }`
  - 影响：搜索 DB 异常时用户看到"未找到相关食物"，与"搜索失败"语义不同；无重试入口
  - 建议修复：catch 内 showAppToast('搜索失败，请重试') 或显示内联错误提示
  - 工作量：15 分钟

- [P1] [profile_page.dart:74-78](file:///workspace/lib/features/profile/profile_page.dart#L74) 档案加载失败仅 toast，UI 显示空白表单
  - 现状：`catch (e) { showAppToast(context, '档案加载失败：$e'); } finally { _loading = false; }`，build 中 `_loading=false` 后渲染空白表单（controllers 为空）
  - 影响：用户看到一堆空输入框 + 一个 toast，不知道发生了什么；无法重试加载
  - 建议修复：新增 `_loadError` 标志，build 中显示 ErrorState + 重试按钮（与 dashboard 同构）
  - 工作量：30 分钟

- [P1] [update_page.dart:213-214](file:///workspace/lib/features/update/update_page.dart#L213) release notes `maxLines: 10, overflow: TextOverflow.ellipsis`，长更新说明被截断
  - 现状：`Text(r.release.body, style: tt.bodySmall, maxLines: 10, overflow: TextOverflow.ellipsis)`
  - 影响：更新日志超 10 行被尾部省略号截断，用户看不到完整内容；无"展开全文"入口
  - 建议修复：改用 `SingleChildScrollView + Text`（无 maxLines）或加"展开/收起"按钮；与 me_page._showPrivacy 用 SingleChildScrollView 一致
  - 工作量：15 分钟

- [P2] [insight_page.dart:502-507](file:///workspace/lib/features/insight/insight_page.dart#L502) 周期未生成汇总时用普通 Card + 纯文本，未用 EmptyState 组件
  - 现状：`Card(child: Padding(padding:16, child: Text('$periodLabel尚未生成汇总，点击下方按钮生成')))`
  - 影响：与 dashboard/today_meals/food_library 的 EmptyState（图标+标题+副标题+按钮）风格不统一
  - 建议修复：复用 EmptyState（icon: Icons.auto_awesome, title: '$periodLabel尚未生成汇总', actionLabel: '生成'），或保留现状但补充图标引导
  - 工作量：15 分钟

### 1.3 无障碍

- [P1] [dashboard_page.dart:519-520](file:///workspace/lib/features/dashboard/dashboard_page.dart#L519) `_regenerateButton` 触控目标 32dp < 48dp，违反 MD3 可访问性
  - 现状：`TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4), minimumSize: Size(0, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap)`
  - 影响：触控高度 32dp 低于 MD3 推荐的 48dp 最小触控目标，手指粗或操作不便用户易误触；与 multi_dish_page.dart:271 显式 `BoxConstraints(minWidth:48, minHeight:48)` 不一致
  - 建议修复：移除 `minimumSize` + `tapTargetSize`，或改为 `minimumSize: Size(0, 48)`；若视觉上太大，保留 padding 但 minimumSize 用 48
  - 工作量：5 分钟

- [P2] [dashboard_page.dart:932](file:///workspace/lib/features/dashboard/dashboard_page.dart#L932) `_ratedChip` 文字 `fontSize: 10`，小于最小可读字号 12
  - 现状：`Text(label, style: TextStyle(fontSize: 10, color: color))`
  - 影响：弱视用户难辨识；违反 MD3 最小字号 12 建议
  - 建议修复：改用 `tt.labelSmall`（约 11sp）或显式 `fontSize: 11`，并加 `fontFeatures: [tabularFigures]` 若含数字
  - 工作量：2 分钟

- [P2] [multi_dish_page.dart:490](file:///workspace/lib/features/recognize/multi_dish_page.dart#L490) `_buildSourceBadge` 文字 `fontSize: 10`
  - 现状：`Text(label, style: TextStyle(fontSize: 10, color: fgColor, fontWeight: FontWeight.w500))`
  - 影响：同上
  - 建议修复：改 `fontSize: 11` 或 `tt.labelSmall`
  - 工作量：2 分钟

- [P2] [calibration_page.dart:873](file:///workspace/lib/features/recognize/calibration_page.dart#L873) `_sourceBadge` 文字 `fontSize: 11`
  - 现状：`Text(isDb ? '库匹配' : 'AI 估算（库未命中）', style: TextStyle(fontSize: 11, color: ...))`
  - 影响：边界值，但与 multi_dish_page 同类徽章 fontSize:10 不一致
  - 建议修复：统一两页徽章字号为 `tt.labelSmall` 或显式 11
  - 工作量：5 分钟（含跨页统一）

- [P2] [calibration_page.dart:352](file:///workspace/lib/features/recognize/calibration_page.dart#L352) 历史中位数提示硬编码 `fontSize: 12`
  - 现状：`Text('📊 已按你历史记录的中位数预填份量', style: TextStyle(fontSize: 12, color: cs.primary))`
  - 影响：硬编码字号不跟随系统字体缩放（accessibility text scale factor）
  - 建议修复：改用 `tt.labelSmall?.copyWith(color: cs.primary)`
  - 工作量：2 分钟

- [P2] [insight_page.dart:599](file:///workspace/lib/features/insight/insight_page.dart#L599) 图表 X 轴标签硬编码 `fontSize: 10`
  - 现状：`Text('${date.month}/${date.day}', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant))`
  - 影响：图表轴标签硬编码，不跟随系统字号；与 weight_page 同类标签一致（两页都硬编码 10），但违反"用 textTheme"规范
  - 建议修复：改用 `tt.labelSmall?.copyWith(fontSize: 10, color: ...)`（保留 10 但继承 labelSmall 字重）；或接受现状（图表轴标签固定小字号是行业惯例）
  - 工作量：10 分钟（4 处统一）

- [P2] [multi_dish_page.dart:299-308](file:///workspace/lib/features/recognize/multi_dish_page.dart#L299) 营养素行硬编码 `fontSize: 12`
  - 现状：`Text('... kcal · 蛋白 ... g · ...', style: TextStyle(fontFeatures: [...], fontSize: 12, color: cs.onSurfaceVariant))`
  - 影响：不跟随系统字号缩放
  - 建议修复：改用 `tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: [...])`
  - 工作量：2 分钟

- [P2] [backup_page.dart:62](file:///workspace/lib/features/backup/backup_page.dart#L62) 说明文字硬编码 `fontSize: 13`
  - 现状：`Text('说明：...', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))`
  - 影响：不跟随系统字号
  - 建议修复：改用 `tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)`
  - 工作量：2 分钟

- [P2] [settings_page.dart:375](file:///workspace/lib/features/settings/settings_page.dart#L375) 关于说明硬编码 `fontSize: 12`
  - 现状：`Text('营养目标依据 ACSM/ISSN/NIH/WHO 标准', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant))`
  - 影响：不跟随系统字号
  - 建议修复：改用 `tt.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)`
  - 工作量：2 分钟

### 1.4 动效一致性

- [P1] [insight_page.dart:394-405](file:///workspace/lib/features/insight/insight_page.dart#L394) 周/月 SegmentedButton 切换时图表突兀消失再出现
  - 现状：`setState` 直接清空 `_dailyCal/_dailyWeight`，fl_chart 立即重绘为空，加载完成后又突然出现新图表
  - 影响：与 M22 已修的 recognize_progress_card 平滑过渡理念不一致；切换瞬间视觉跳跃明显
  - 建议修复：配合 1.2 节 loading 标志，切换时图表区用 AnimatedSwitcher 包裹（LoadingState ↔ 图表），过渡 300ms
  - 工作量：30 分钟（与 1.2 第 1 项合并实施）

- [P2] [today_meals_page.dart:155-191](file:///workspace/lib/features/dashboard/today_meals_page.dart#L155) 日期切换 _goToPrevDay/_goToNextDay 时直接 `_loading=true` 显示全屏 LoadingState，无淡入淡出
  - 现状：切换日期立即全屏转圈，加载完成后突然显示列表
  - 影响：日期栏常驻但内容区突兀切换；与 records_tab IndexedStack 无动画切换一致，可接受
  - 建议修复：可选——加载快时（<200ms）不显示 LoadingState，避免闪烁；或用 AnimatedSwitcher
  - 工作量：30 分钟（可选优化）

- 无发现：recognize_progress_card.dart M22 重构后已用 TweenAnimationBuilder + AnimatedContainer + AnimatedSwitcher，符合规范

### 1.5 跨页面视觉一致性

- [P2] Card 风格三套并存，未统一
  - 现状：
    - [today_meals_page.dart:382](file:///workspace/lib/features/dashboard/today_meals_page.dart#L382) 用 `Card.outlined`（带边框无阴影）
    - [recognize_progress_card.dart:47](file:///workspace/lib/features/recognize/recognize_progress_card.dart#L47) 用 `Card(elevation: 0, color: cs.surfaceContainerHigh)`（M3 tonal 无阴影）
    - 其他页面（dashboard/insight/weight/me/settings/food_library/food_edit/manual_entry/profile/calibration/multi_dish/update/backup）用 `Card` 默认（elevation:1）
  - 影响：三套 Card 风格混用，跨页面视觉不统一；M22 引入的 tonal 风格未推广到其他页面
  - 建议修复：统一约定——列表卡片用 Card 默认，焦点卡片用 HeroCard（28dp 圆角 + primaryContainer），状态卡片用 Card.outlined；或将 today_meals 改回默认 Card 保持一致
  - 工作量：1 小时（跨页面统一）

- [P2] 主操作按钮风格不统一
  - 现状：
    - [settings_page.dart:286](file:///workspace/lib/features/settings/settings_page.dart#L286) 用 `FloatingActionButton.extended`（保存设置）
    - 其他页面（food_edit/manual_entry/profile/calibration/multi_dish/weight/insight）用 `FilledButton` 全宽底部按钮
    - [update_page.dart:164](file:///workspace/lib/features/update/update_page.dart#L164) 用 `FilledButton.icon` 居中（非全宽）
  - 影响：settings 用 FAB 与其他页面底部 FilledButton 风格不一致；update 居中按钮又与全宽按钮不一致
  - 建议修复：settings 改为底部 FilledButton（与 profile/food_edit 一致），或保留 FAB 但其他编辑页也改 FAB；update 居中可接受（更新流程是独立状态机）
  - 工作量：30 分钟

- [P2] AppBar 风格分层合理但需文档化
  - 现状：
    - 主 tab 页（dashboard/me/settings）用 `SliverAppBar.large`（大标题）
    - 子页（profile/food_edit/weight/calibration/multi_dish/backup/update/recognize）用普通 `AppBar`
    - records_tab/insight 用 `AppBar + bottom: SegmentedButton`
  - 影响：风格分层合理（主 tab vs 子页），但缺少显式约定文档，新页面可能选错
  - 建议修复：在 m3_widgets.dart 顶部注释补充 AppBar 选用约定；无需改代码
  - 工作量：10 分钟（仅文档）

- [P2] [insight_page.dart:375](file:///workspace/lib/features/insight/insight_page.dart#L375) AppBar.title 显示日期范围 `'$_periodStart ~ $_periodEnd'`（如 "2026-06-29 ~ 2026-07-05"），与其他页面简洁标题不一致
  - 现状：标题是日期范围字符串
  - 影响：标题冗长，小屏可能被截断；与 records_tab '今日明细'/weight '体重记录' 等简洁标题不统一
  - 建议修复：标题改为 'AI 周报'，日期范围作为副标题或顶部信息行
  - 工作量：15 分钟

- 无发现：LoadingState/ErrorState/EmptyState 通过 m3_widgets 统一组件，跨页一致；MacroColors 三宏配色跨页统一；LeadingIconContainer 跨页统一；SectionTitle 跨页统一

## 维度 1 汇总

- **P0: 0 项**（未发现崩溃/数据丢失/安全漏洞/6 条硬约束违反）
- **P1: 6 项**
  - insight 周/月切换无 loading 指示 + 图表突兀切换（1.2 + 1.4，可合并实施，按 1 项计）
  - food_library 加载失败静默吞掉，无错误提示
  - food_library 搜索失败静默吞掉，无错误提示
  - profile 加载失败仅 toast，UI 显示空白表单
  - update release notes maxLines:10 截断，无展开入口
  - dashboard _regenerateButton 触控目标 32dp < 48dp（无障碍违反）
- **P2: 17 项**
  - 间距类（7 项）：food_edit/multi_dish/profile/update Card padding=12，today_meals ListView padding=12，recognize_page SizedBox height=20，calibration ExpansionTile tilePadding=12
  - 字号类（7 项）：dashboard/multi_dish 徽章 fontSize:10，calibration 徽章 fontSize:11，calibration 历史提示 fontSize:12，insight 图表轴标签 fontSize:10，multi_dish 营养素行 fontSize:12，backup/settings 说明文字硬编码 fontSize
  - 跨页一致性类（3 项）：Card 三套风格并存，主操作按钮 FAB vs FilledButton 不统一，insight AppBar.title 冗长日期范围；外加 AppBar 风格需文档化

**整体评价**：

EatWise 14 个 feature 页面整体 UI 规范执行度高——M3 公共组件（LoadingState/ErrorState/EmptyState/HeroCard/SectionTitle/LeadingIconContainer/GroupCard/MacroColors）抽象到位，跨页配色与图标语义统一，数值列普遍使用 `FontFeature.tabularFigures()` 防数字跳动，编辑页 PopScope + confirmDiscardChanges 防误退 + 防重入 `_busy`/`_isRecording` 模式一致，M22 进度卡片动画重构后达到 M3 Expressive 标准。**未发现 P0 级问题**，6 条硬约束均无违反。

主要短板集中在三方面：(1) **错误态覆盖不完整**——food_library/profile 静默吞异常或仅 toast 不显示 ErrorState，与 dashboard/today_meals 的显式 ErrorState + 重试入口模式不一致，是 P1 重点；(2) **insight 页周/月切换体验**——无 loading 指示 + 图表突兀切换，是单一最严重的体验缺陷（P1+P1 可合并修）；(3) **间距/字号小瑕疵**——多页 Card padding=12（应为 16）、徽章 fontSize=10/11（应≥12）、部分文字硬编码 fontSize 不跟随系统缩放，属 P2 可读性与一致性优化。

Card 风格三套并存（默认/outlined/tonal）是设计演进的自然结果（M22 引入 tonal），建议制定显式约定（列表卡/焦点卡/状态卡）而非任由漂移。FAB vs FilledButton 不一致仅 settings 一处，统一成本低。

**建议优先级**：先修 6 项 P1（错误态 + 触控目标 + 切换体验，预估 2.5 小时），再批量修 P2 间距/字号（预估 1 小时），Card 风格统一可作为下一里程碑设计任务。
