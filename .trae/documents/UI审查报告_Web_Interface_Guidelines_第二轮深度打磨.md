# EatWise UI 第二轮深度审查报告（Web Interface Guidelines）

**审查日期**：2026-07-07
**审查范围**：全部 26 个 UI 页面文件（11514 行）+ 公共组件 + 全局架构
**审查准则**：[Vercel Web Interface Guidelines](https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md)（Flutter 映射版）
**审查方法**：4 个并行 subagent 逐行验证第一轮发现 + 7 维度深度找漏（视觉一致性 / 信息架构 / 状态覆盖 / 响应式 / 键盘交互 / 首次启动 / 性能 + 交互流畅度 / 状态管理 / 错误恢复 / 数据一致性 / 可撤销性 / 进度反馈 / 边界场景 + 文案 / 表单 UX / 数据展示 / 主题/路由/全局错误/后台任务/设置/备份/更新）
**第一轮报告**：`/workspace/.trae/documents/UI审查报告_Web_Interface_Guidelines.md`

---

## 1. Summary（摘要）

第二轮深度审查做了两件事：
1. **验证第一轮**：逐行核查 132 条发现，确认 131 条准确 / 1 条部分误报 / 1 条严重度低估
2. **找漏**：7 维度深度审查，新发现 **0 P0 + 15 P1 + ~115 P2**

### 累计统计（两轮合并）

| 优先级 | 第一轮 | 第二轮新发现 | 累计 |
|--------|--------|------------|------|
| P0 | 0 | 0 | **0** |
| P1 | 30 | 15 | **45** |
| P2 | ~109 | ~115 | **~224** |

### 第一轮验证结论

- **0 误报（实质性）**：第一轮 132 条发现全部经逐行核查确认成立
- **1 条部分误报**：`m3_widgets.dart:456` 第一轮归为"装饰性 Icon 未 ExcludeSemantics"，实际是 `CircularProgressIndicator`；且建议 ExcludeSemantics 对 label=null 场景有害（会移除唯一加载语义），正确建议应加 `semanticsLabel`
- **1 条严重度低估**：`update_page.dart:282` 第一轮标 P2"标签过泛"，实际问题是 error 态"重试"按钮**行为错误**（固定调 `_check`，install 失败后重新 check+download 浪费带宽），升级为 P1
- **多条"判断准确但漏报同类"**：
  - `insight_page.dart` 硬编码 fontSize：第一轮列 6 处，实际有 19 处（漏报 13 处）
  - `insight_page.dart` 缺 tabularFigures：第一轮列 4 处，实际有 9 处（漏报 5 处）
  - Group C 错误文案含原始异常：第一轮列 2 处，实际有 11 处（漏报 9 处）
  - `calibration_page.dart` 硬编码 fontSize：第一轮列 3 处，实际有 5 处（漏报 2 处）
  - `dish_card.dart` 硬编码 fontSize：第一轮完全漏报（实际 5 处）

### 第二轮 P1 新发现（15 条，集中在 4 类系统性漏报 + 3 个严重 bug）

**4 类系统性漏报（11 条）**：
1. **错误文案含原始异常漏报 9 处**（Group C）
2. **insight_page fontSize 漏报 13 处** + **tabularFigures 漏报 5 处**（Group A）

**3 个严重 bug（4 条 P1）**：
1. **复合菜预览/记录路径优先级不一致**（calibration_page.dart）—— 包装+宏量全0+aiFallback 场景**显示值≠记录值**，违反 v2 重构核心契约
2. **复合菜 AI 优先路径未含用油量但滑块可见**（calibration_page.dart）—— 用户调整用油量滑块无效
3. **profile goalRate 游离 Form 外 + 全页数值无范围校验**（profile_page.dart）—— 垃圾输入直接写库污染下游
4. **weight 编辑 dialog 完全无校验静默 return**（weight_page.dart）—— 输入 "abc" 点保存 dialog 关闭什么都没发生

**3 个 UX 严重问题（3 条 P1）**：
1. **backup_page 导入成功后未 invalidate provider**（backup_page.dart）—— 其它页面数据过期
2. **update_page error 态"重试"行为错误**（update_page.dart）—— install 失败后浪费带宽重下
3. **confirmAction 长内容溢出 AlertDialog 不可滚动**（m3_widgets.dart）—— 小屏机型确认按钮不可达

---

## 2. Current State Analysis（项目 UI 架构现状）

```
lib/
├── app.dart                        # GoRouter 路由 + ColorScheme.fromSeed + dynamic_color
├── main.dart                       # 单一 ProviderContainer + Sentry + Workmanager + zone 兜底
├── core/
│   ├── theme/theme_controller.dart # 种子色 Riverpod Notifier
│   ├── util/date_format.dart       # 手写 padLeft（非 intl，P2 系统性）
│   └── widgets/m3_widgets.dart     # SectionTitle / LeadingIconContainer / EmptyState / EmptyChartHint / WarningBanner / ErrorState / LoadingState / GroupCard / MealTypeSelector / HeroCard / showAppToast / confirmAction / confirmDiscardChanges
└── features/
    ├── dashboard/                  # 5 个 Tab 之一（首页）
    │   ├── dashboard_page.dart     # 310 行，CustomScrollView 主框架
    │   ├── today_meals_page.dart   # 739 行，今日餐次 + 删除 Undo
    │   ├── meal_edit_dialog.dart   # 396 行，餐次编辑
    │   └── dashboard/              # 6 个子组件（M24 B5 拆分）
    ├── records/records_tab_page.dart  # 90 行，记录 Tab（IndexedStack 3 子页）
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

**已遵循的良好实践**（两轮共同确认）：
- `colorScheme` 配色全覆盖（无 0xFF 硬编码颜色，仅 `recognize_progress_card.dart:204` 一处 `Colors.white`）
- `IconButton` 普遍有 `tooltip`
- 写库按钮 `_isRecording`/`_busy` 防重入 + try-catch-finally + `mounted` 检查
- 破坏性操作 `confirmAction` / `confirmDismiss` / `PopScope` + `confirmDiscardChanges` 二次确认
- `ListView.builder` 用于大列表
- `tabularFigures` 在数字列普遍应用（但 insight_page 图表区严重漏用）
- `「」` 中文引号 + `…` 省略号统一
- M24 B5 已拆分 dashboard / multi_dish 大文件
- `Form + validator + errorText`：profile_page 是唯一做对的页面（其它应参照）

---

## 3. 第一轮问题验证详情

### 3.1 Group A 验证（23 条）

| 第一轮发现 | 验证结果 | 备注 |
|----------|---------|------|
| dashboard_page:282 无 SafeArea | ✅准确 | main_shell 不提供 SafeArea，edge-to-edge 启用 |
| dashboard_page showAppToast 4 处缺 liveRegion | ✅准确 | 根因 m3_widgets:321 |
| recognize_page:567 SnackBar 缺 liveRegion | ✅准确 | 内联 SnackBar，不走 showAppToast |
| recognize_page showAppToast 3 处缺 liveRegion | ✅准确 | |
| recognize_page:361-369 遮罩动画未检查 reduced-motion | ✅准确 | |
| insight_page:592 ListView 无底部 MediaQuery | ✅准确 | |
| insight_page:467 错误文案拼异常 | ✅准确 | |
| insight_page:827/836/903 日期硬编码 M/D | ✅准确 | |
| insight_page 硬编码 fontSize 6 处 | ✅准确**但漏报 13 处** | 实际 19 处 |
| insight_page 缺 tabularFigures 4 处 | ✅准确**但漏报 5 处** | 实际 9 处 |
| insight_page 装饰图标未 ExcludeSemantics 5 处 | ✅准确 | |
| insight_page AnimatedSwitcher 2 处 | ✅准确 | |
| me_page:71 HeroCard 无 Semantics | ✅准确 | 实例层 + 组件层双重根因 |
| me_page:168 SliverList 无 SafeArea | ✅准确 | |
| recognize_progress_card Colors.white 2 处 | ✅准确 | |
| recognize_progress_card 3 处动画 | ✅准确**但漏报 1 处** | L55 也未检查 |
| recognize_progress_card 装饰图标 2 处 | ✅准确 | |
| recognize_progress_card TextStyle 2 处 | ✅准确 | |
| ai_rec_item:189 fontSize:10 | ✅准确 | |
| recommendation_section:250 无 maxLines | ✅准确 | |
| status_card_section:167-176 无 maxLines | ✅准确 | |
| today_meals_section:66 无 maxLines | ✅准确 | |
| today_meals_section:110-113 padLeft | ✅准确 | |

**Group A 验证：23 条全部准确，0 误报**

### 3.2 Group B 验证（37 条）

37 条全部准确，0 误报 / 0 调整。详见第二轮 subagent 报告。漏报情况：
- `calibration_page.dart` 硬编码 fontSize：第一轮列 3 处（345/373/773），实际 5 处（漏报 1055、1239 第一轮已列）
- `dish_card.dart` 硬编码 fontSize：第一轮完全漏报（实际 5 处：100/145/169/212/252）

### 3.3 Group C 验证（43 条）

43 条全部准确，0 误报 / 0 调整。漏报情况：
- 错误文案含原始异常：第一轮列 2 处（today_meals_page:379/557），实际 11 处（漏报 9 处）

### 3.4 Group D 验证（31 条）

- 29 条准确
- 1 条部分误报：`m3_widgets.dart:456` 是 `CircularProgressIndicator` 非"装饰性 Icon"，建议 ExcludeSemantics 有害
- 1 条严重度低估：`update_page.dart:282` 升级 P2→P1（行为错误，非标签泛）

---

## 4. 第二轮新发现详情（按 Group + 维度）

### 4.1 Group A 新发现（0 P0 + 0 P1 + ~35 P2）

#### 维度 1：视觉一致性
- **insight_page.dart:875,889,906,1010,1216,1280,1394,1411,1497,1556,1574,1668,1758** — 图表区 TextStyle 硬编码 fontSize（第一轮漏报 13 处）。应统一改 `tt.labelSmall(11)/bodySmall(12)` (P2)
- **insight_page.dart:534** — AppBar title `Text('$_periodStart ~ $_periodEnd')` 直接显示原始 `YYYY-MM-DD ~ YYYY-MM-DD` 串，未本地化。应改 `DateFormat.yMd()` (P2)
- **insight_page.dart:905,1009,1408,1681** — 四处图表 tooltip 内数字缺 `FontFeature.tabularFigures()` (P2)
- **insight_page.dart:1214,1278,1554** — 环图 section title / _mealBadge / 排名徽章数字缺 tabularFigures (P2)
- **各页 AppBar 风格不统一** — dashboard/me 用 `SliverAppBar.large`，records/insight 用 `AppBar + bottom PreferredSize`，跨 tab 视觉跳跃明显 (P2 设计备注)

#### 维度 2：信息架构
- **records_tab_page.dart:80-87** — `IndexedStack` 一次性初始化 3 个子页（TodayMealsPage + WeightPage + FoodLibraryPage），首次进入即触发 3 个页面的数据库查询。应改懒加载 (P2)
- **me_page.dart:147-154** — "设置"入口放在"偏好"分组下不合理（含 Sentry DSN / API Key 等系统级配置）。建议独立为顶级分组 (P2)
- **me_page.dart:132-169** — "关于慢慢吃"+"隐私政策"两个入口点开都是 dialog，与"体重记录/数据备份/设置"跳页混合，交互模式不统一 (P2 minor)
- **dashboard_page.dart:282-304** — CustomScrollView 4 个 sliver 无快速跳转锚点 (P2 minor)

#### 维度 3：状态覆盖
- **recommendation_section.dart:236-238** — v4 FutureBuilder `hasError → debugPrint + SizedBox.shrink()`，静默吞错。用户看到 AI loading + 空白 (P2)
- **recommendation_section.dart:240-242** — v4 空数据 `SizedBox.shrink()`，无空态提示 (P2)
- **recognize_page.dart:327-351** — 拍照/相册按钮无网络前置守卫。离线时走完选图→压缩→AI 推理失败→入队/弹错整个链路才反馈 (P2)
- **insight_page.dart:475-513** — `_edit` 编辑汇总 dialog 无 `_dirty` 拦截 + 无 `barrierDismissible:false`，与五页一致性破坏 (P2)
- **insight_page.dart:483-491** — 编辑汇总 TextField 无 `maxLength` (P2 minor)

#### 维度 4：响应式
- **insight_page.dart:602,619,1240,1396,1670** — 5 处图表 `SizedBox(height: 200/150/180)` 固定高度，小屏占比过高，大屏留白多 (P2)
- **status_card_section.dart:148-178** — 三宏行 Row 结构超量时 value 列 110dp 宽可能换行/溢出 (P2)
- **recognize_page.dart:276-355** — Hero 引导区 + 操作区 flex:5:4，小屏可能挤压 Hero 区 (P2 minor)
- **dashboard_page.dart:284** — `SliverAppBar.large` 小屏占用 ~152dp 垂直空间 (P2 minor)

#### 维度 5：键盘交互
- **insight_page.dart:483-491** — 编辑汇总 TextField 无 `maxLength` 上限 (P2)
- **dashboard_page.dart:282 / insight_page.dart:591 / me_page.dart:51** — 三处滚动视图未设 `keyboardDismissBehavior: onDrag` (P2)
- **records_tab_page.dart:60-77 / insight_page.dart:547-587** — SegmentedButton 无方向键导航 (P2 minor)
- **recognize_page.dart:321-351** — 拍照按钮 Tab 焦点顺序在 MealTypeSelector 之后，与视觉权重不符 (P2 minor)

#### 维度 6：首次启动体验
- **recognize_page.dart:189** — `_mealType = 'snack'` 默认加餐。新用户首次打开看到默认选中"加餐"而非按时段推断。dashboard_page 已有 `_currentMealType` 逻辑可复用 (P2)
- **me_page.dart:55-130** — 新用户首次进入，Profile 有默认值但无"完善档案"引导提示 (P2)
- **dashboard_page.dart:282-304** — 新用户首次进入（无 meal_log），整体无"欢迎使用/开始记录"引导 (P2 minor)
- **insight_page.dart:607-610,624-627** — 新用户首次进入洞察页，信息层级可优化 (P2 minor)

#### 维度 7：性能
- **records_tab_page.dart:80-87** — IndexedStack 3 子页同时初始化（同维度 2），冷启动开销显著 (P2)
- **insight_page.dart:769-1774** — 7 个图表构建方法在 build 内每次 setState 都重建 LineChart/BarChart/PieChart。应用 `const` 缓存或 `RepaintBoundary` (P2)
- **today_meals_section.dart:40-43** — `groups` Map 在 build 内每次重算（第一轮对 today_meals_page 已列，此处 section 漏列）(P2 minor)
- **recommendation_section.dart:84-110** — `FutureBuilder` 嵌在 Row 内，可提取独立 widget (P2 minor)
- **insight_page.dart:347-369** — `_loadExisting` 每次调用都聚合 7/30 天 4 表查询。拍照记录一条就重新聚合 30 天 (P2)

#### 附加：无障碍细节
- **recommendation_section.dart:165-171** — `_aiLoadingHint` CircularProgressIndicator 无 semantics label (P2)
- **insight_page.dart:744-750** — loading 态 CircularProgressIndicator 无 semantics label (P2)
- **recognize_progress_card.dart:55-68,75-87,202-205** — 三处 CircularProgressIndicator/TweenAnimationBuilder 无 semantics label (P2)
- **recognize_page.dart:302-308** — Hero 副标题 Text 无 maxLines (P2 minor)
- **recognize_page.dart:298** — Hero 标题 Text 无 maxLines/overflow (P2 minor)

---

### 4.2 Group B 新发现（0 P0 + 2 P1 + 30 P2）

#### P1 严重问题（2 条，均为 v2 重构后数据一致性问题）

**P1-1：复合菜预览/记录路径优先级不一致**（calibration_page.dart:523-568 vs 869-984）

`_buildNutritionPreview`（L529）条件 `aiFallback != null && !hasPackageNutrition`：有包装时跳过 AI 优先走组分累加 fallback。

`_confirmWithServing`（L892）条件 `packagePer100 != null && !packageMacrosAllZero`：有包装+宏量非全0 走包装换算，否则（含宏量全0）走 AI 优先。

**当复合菜 + 包装 + 宏量全0 + aiFallback 时：预览显示组分累加值，记录却用 AI 优先值，显示值≠记录值**——违反 v2 重构核心契约"显示值 = 记录值"。

**P1-2：复合菜 AI 优先路径未含用油量但用油量滑块可见**（calibration_page.dart:529-552 vs 702-715）

`_buildNutritionPreview` AI 优先分支直接用 `calibrated.actualXxx`，不累加 `oilCaloriesPer100g * _oilG / 100`；但 `_buildCompositeControls`（L414-417）只要 compositeNutrition != null 就显示用油量滑块。

用户调整用油量滑块 → setState → 预览重建 → AI 优先路径仍返回原值 → 滑块可见但调整无效，用户极度困惑。

#### 维度 1：交互流畅度（5 条 P2）
- calibration_page:301-357 多份警告 Container 出现/消失无 AnimatedSwitcher 过渡，布局突然跳变
- calibration_page:426-435 `_isRecording` 期间仅按钮内显示 spinner，页面其他部分仍可交互无 disabled 视觉
- calibration_page:186-194 `_isRenaming` 期间仅 14x14 spinner，无阶段文案（OFF 云查可能数秒）
- multi_dish_page:60-71 `_recordAll` 期间仅按钮内 18x18 spinner，多菜事务无"第 N/M 道"进度
- multi_dish_page:107-115 改菜名期间 16x16 spinner，无阶段文案

#### 维度 2：状态管理 race condition（5 条 P2）
- calibration_page:170,175,197 `_isRenaming=true` 期间"一键记录"/"信任 AI"/"转手动"按钮未禁用，与改菜名 setState 替换 _currentNutrition 形成竞态
- calibration_page:380-400 `_isRecording=true` 期间 Slider 的 onChanged 未检查，用户仍可拖滑块改 _servingG
- calibration_page:705-715,728-738 `_isRecording=true` 期间用油量 Slider 和组分份量 Slider 也未禁用
- multi_dish_page:192-194 `_isRecording=true` 期间 DishCard Slider/IconButton 全程可交互
- multi_dish_page:335-336 vs 290 `_handleRename` 仅检查 `_isRenamingFlags[index]`，不检查 `_isRecording`
- calibration_page:834-839 改菜名命中后 `_userOverrides.clear()` 静默清空用户手动编辑值，toast 未提示

#### 维度 3：错误恢复（4 条 P2）
- calibration_page:1148-1157 编辑对话框无负数/超大值校验
- calibration_page:847-852,990-996 "改菜名失败"/"记录失败" toast 无重试按钮
- multi_dish_page:324-329 改菜名失败仅 toast 无重试引导
- multi_dish_page:521-525 "记录失败" toast 无重试按钮

#### 维度 4：数据一致性
- 见 P1-1 / P1-2
- calibration_page:464-477 vs 836 改菜名后用旧 aiFallback 与新 lookupHitNutrition 做差异检测，可能显示/记录值与库 per100g 脱节 (P2，需业务确认)

#### 维度 5：可撤销性（2 条 P2）
- multi_dish_page:516-519 `_recordAll` 成功后直接 pop，无 Undo SnackBar（多菜场景误录代价更大）
- calibration_page:986-989 `_confirmWithServing` 成功后直接 pop，无 Undo

#### 维度 6：进度反馈（3 条 P2）
- calibration_page:1071-1173 `_showEditNutritionDialog` 打开期间无"正在保存"反馈
- multi_dish_page:293-305 改菜名 await 三个 future 累计数秒，仅 spinner 无阶段文案
- calibration_page:820-826 `editDishNameAndLookup` 内部多阶段无进度反馈

#### 维度 7：边界场景（9 条 P2）
- calibration_page:382,706,729 滑块 min:0，用户可拖到份量=0 写入 meal_log
- multi_dish_page:131 DishCard Slider min:0，同上
- multi_dish_page:75,107,344 `additionalItems.take(5)` 截断为 5 道附加菜，超过 5 道静默丢弃无提示
- calibration_page:691-699 componentMisses 列表项 Text 无 maxLines
- calibration_page:1050-1058 `_buildWarningsBanner` warnings Text 无 maxLines
- calibration_page:696-699 "请转手动录入或补充食物库" Text 无 maxLines
- calibration_page:1055 TextStyle 硬编码 fontSize:12（第一轮漏报）
- dish_card.dart:100,145,169,212,252 5 处硬编码 fontSize（第一轮完全漏报）

---

### 4.3 Group C 新发现（0 P0 + 10 P1 + 30 P2）

#### P1 严重问题（10 条）

**P1 漏报 9 条：错误文案含原始异常**（第一轮 #4 系统性问题 Group C 漏报实例）
- **today_meals_page.dart:728** — `'反馈失败：$e'`
- **profile_page.dart:78** — `'档案加载失败：$e'`
- **profile_page.dart:515** — `'保存失败：$e'`
- **weight_page.dart:430** — `'记录失败：$e'`
- **weight_page.dart:573** — `'保存失败：$e'`
- **weight_page.dart:599** — `'删除失败：$e'`
- **manual_entry_page.dart:255** — `'记录失败：$e'`
- **manual_entry_page.dart:326** — `'记录失败：$e'`
- **food_edit_page.dart:175** — `_showError('保存失败：$e')`
- **food_edit_page.dart:213** — `_showError('保存失败：$e')`

**P1 新发现 3 条：表单校验缺陷**

- **profile_page.dart:279-287** — 目标速率用 `TextField` 而非 `TextFormField`，**游离于 Form 校验之外**。`double.tryParse(_goalRateCtrl.text) ?? 0` 静默兜底为 0，用户输入 "abc" 无 errorText 反馈，goalRate=0 触发默认 deficit（-500/+250）
- **profile_page.dart:150-178,202-206** — 4 个数值 TextFormField 的 validator 仅校验"能 parse"，**无范围校验**：身高 0/999cm、体重 0/9999kg、年龄 0/999、体脂率 200% 均通过校验。垃圾输入直接进入 BMR/TDEE 计算产生荒谬目标值
- **weight_page.dart:530-547** — 编辑 dialog "保存"按钮**无任何校验**：`double.tryParse` 失败返回 weightKg=null，`if (result.weightKg == null || result.weightKg! <= 0) return;` 静默 return。用户输入 "abc" 点保存 dialog 关闭什么都没发生

#### 维度 1：文案（15 条 P2）
- today_meals_page:728 `'反馈失败：$e'`（已列 P1）
- today_meals_page:349 Undo SnackBar 文案未告知撤销窗口时长（3 秒）
- today_meals_page:570 `'已反馈过'` 过简
- today_meals_page:584,587 反馈 dialog 按钮标签 `'准'` / `'不准'` 各仅 1 字
- today_meals_page:634 反馈纠正 dialog 按钮 `'提交'` 过泛
- weight_page:411 `'TDEE 已调整：${result.reason}'` 暴露技术字符串

#### 维度 2：表单 UX（14 条 P2）
- today_meals_page:467-472 反馈 IconButton 无 _busy 防重入（可叠开两个 dialog）
- today_meals_page:603-638 反馈纠正 dialog 有 TextField 编辑态但未设 barrierDismissible:false（第一轮漏报）
- today_meals_page:610-614 反馈纠正 dialog 菜名 TextField 无 maxLength（第一轮只提 autocorrect）
- meal_edit_dialog:272-288 食物字段 InkWell+InputDecorator 无显式 Semantics(button:true, label:)
- profile_page:285 hintText `'减脂建议 0.3-0.7，增肌建议 0.18-0.45'` 未以 `…` 结尾
- profile_page:74-83 _loadProfile 失败时既弹 toast 又设 _loadError 让 build 显示 ErrorState，反馈冗余
- manual_entry_page:139,214 `_customMode` 切换 TextButton.onPressed 未调 _markDirty
- weight_page:382-387 _save 仅校验 weight > 0，无上界校验
- meal_edit_dialog:240-244 _save 仅校验 serving > 0，无上界
- food_edit_page:160-194 _saveServingOnly/_saveAll 仅校验 > 0/能 parse，无范围
- manual_entry_page:227-281 _logFromLibrary/_logCustom 仅校验 > 0/能 parse，无范围

#### 维度 3：数据展示（4 条 P2）
- meal_edit_dialog:308 ListTile title `Text(formatYmd(_selectedDate))` 显示 `'YYYY-MM-DD'` 原始串
- weight_page:507 编辑 dialog 日期 ListTile title 同上
- weight_page:455 confirmAction content `'${log.weightKg.toStringAsFixed(1)} kg · ${log.date}'` 含 `'YYYY-MM-DD'` 原始串
- weight_page:149-151 _buildChart 内 `if (_logs.length < 2) return Center(...)` 是死代码（调用方 L135-138 已守卫）

#### 维度 4-7：撤销/搜索/首启/边界（6 条 P2 + 6 条设计备注）
- food_edit_page 编辑食物营养素后无 Undo，per100g 改动污染下游 meal_log
- food_library_page 无搜索历史/最近搜索
- food_library_page 无排序选项（固定按 freq）
- food_library_page 无按 source 筛选
- profile_page 首次进入（profile 未填）无引导文案
- weight_page:138 首次进入未解释"为什么要每天称体重"
- today_meals_page:113-127 日期切换栏 InkWell 无 tooltip/Semantics(label:)

---

### 4.4 Group D 新发现（0 P0 + 3 P1 + ~20 P2）

#### P1 严重问题（3 条）

**P1-1：confirmAction 长内容溢出 AlertDialog 不可滚动**（m3_widgets.dart:292）

`content: Text(content)` 无 maxLines。backup_page:172 传入超长 content（含多行 \n + pending 提示），小屏机型 AlertDialog content 区域不滚动会溢出屏幕底部，**确认按钮不可达**——破坏性操作确认流程完全失效。

**P1-2：backup_page 导入成功后未 invalidate provider**（backup_page.dart:183-188）

Grep 确认 backup_page 全文无 `ref.invalidate` / `ref.refresh`。dashboard 用 `ref.read(mealLogRepoProvider.future)` 在 async 方法中加载（非 reactive watch），导入后 dashboard/today_meals/insight/weight 等页面缓存数据过期，用户返回后看到的是导入前的旧数据，需手动下拉刷新或杀进程重启。

**P1-3：update_page error 态"重试"行为错误**（update_page.dart:280，从 P2 升级）

error 态按钮固定调 `_check`。但错误可能来自：①check 失败→_check 正确；②download 失败→应重试 _download；③install 失败→应重试 _install。install 失败后 `_downloadedPath` 仍有效但"重试"走 _check→updateAvailable→重新 _download→**浪费已下载 APK 带宽**。

#### 维度 1：m3_widgets 公共组件（7 条 P2）
- m3_widgets:61 SectionTitle Text 无 maxLines/Expanded，长标题+trailing 时 RenderFlex overflow
- m3_widgets:456 LoadingState 无 label 时无语义（**修正第一轮误报**：是 CircularProgressIndicator 非 Icon，应加 semanticsLabel 而非 ExcludeSemantics）
- m3_widgets:497 HeroCard onTap 无 Semantics(button:true)（me_page:71 实例层根因）
- m3_widgets:32 LeadingIconContainer Icon 未 ExcludeSemantics（全 App 复用影响面广）
- m3_widgets:132 EmptyState subtitle 无 maxLines
- m3_widgets:427 ErrorState "重试" 按钮标签过泛（建议支持 actionLabel 参数）

#### 维度 2：跨页面复用一致性（2 条 P2）
- backup_page:72-90 vs m3_widgets:442 加载态实现不一致（自定义 Stack overlay vs LoadingState 组件）
- update_page:280 vs m3_widgets:427 "重试"标签跨组件重复，但行为不同

#### 维度 3：主题/暗色模式（2 条 P2）
- settings_page:124-129 "跟随系统壁纸"在 Android<12 无反馈（开关打开后界面无变化无提示）
- settings_page:398-403 动态取色开启时色板 disabled 无 Semantics(disabled:true) 提示

#### 维度 4：路由/导航（2 条 P2）
- app.dart:208 GoRouter 无 errorBuilder，非法深链接显示红屏英文错误
- app.dart:208-241 路由表缺少多个子页面路由（/calibration、/multi_dish、/meal_edit 等），与 /update 同类问题

#### 维度 5：全局错误处理（2 条 P2）
- main.dart:29 boot_log.txt 仅 append 无轮转/大小上限
- main.dart:94-112 Workmanager/OfflineQueue 初始化失败对用户不可见

#### 维度 6：后台任务反馈（2 条 P2）
- offline_queue_controller:100-128 后台回补完成后无任何 UI 可见反馈
- settings_page:90 _monthlyCount 加载后不随后台回补刷新

#### 维度 7：设置页完整性（2 条 P2 + 1 条设计备注）
- settings_page:212 DropdownMenu SizedBox(width:150) 大字体可能截断
- settings_page:32 _costPerRecognition=0.001 硬编码不可配（设计备注）

#### 维度 8：备份/恢复 UX（4 条 P2 + 1 条设计备注）
- backup_page:31 ListView 无 SafeArea(bottom)
- backup_page:82 _busy 遮罩 CircularProgressIndicator 无 semanticsLabel
- backup_page:154-176 导入前无 JSON 格式校验
- backup_page:106-108 导出文件无法直接访问（设计备注）

#### 维度 9：更新检查 UX（3 条 P2 + 1 条设计备注）
- update_page:155-169 idle 态不显示当前版本号
- update_page:211 release notes 以纯文本显示（GitHub API 返回 markdown）
- update_page:80-112 下载中断无法恢复（设计备注）

---

## 5. 第二轮新发现的系统性问题（跨文件根因）

### #12 复合菜预览/记录路径优先级不一致【P1，v2 重构后新发现】
- **根因**：`lib/features/recognize/calibration_page.dart:529` vs `892`
- **场景**：复合菜 + 包装 + 宏量全0 + aiFallback
- **影响**：显示值≠记录值，违反 v2 核心契约
- **修复**：两条路径条件对齐，统一为"包装优先 → AI 优先 → 组分累加"

### #13 复合菜 AI 优先路径未含用油量但滑块可见【P1，v2 重构后新发现】
- **根因**：`lib/features/recognize/calibration_page.dart:529-552` vs `414-417`
- **影响**：用户调整用油量滑块无效，极度困惑
- **修复**：AI 优先路径也累加油量，或 AI 优先时隐藏用油量滑块

### #14 profile goalRate 游离 Form 外 + 全页数值无范围校验【P1，新发现】
- **根因**：`lib/features/profile/profile_page.dart:279-287,150-178,202-206`
- **影响**：垃圾输入（身高 0、体重 9999、goalRate "abc"）直接写库污染下游
- **修复**：goalRate 改 TextFormField + validator，全页数值加范围校验

### #15 weight 编辑 dialog 完全无校验静默 return【P1，新发现】
- **根因**：`lib/features/weight/weight_page.dart:530-547`
- **影响**：输入 "abc" 点保存 dialog 关闭什么都没发生
- **修复**：加 errorText 内联反馈

### #16 错误文案含原始异常漏报 9 处【P1，第一轮系统性问题 #4 Group C 实例】
- **影响位置**：见 4.3 P1 漏报 9 条
- **修复**：与第一轮 #4 一起统一改写

### #17 backup_page 导入后未 invalidate provider【P1，新发现】
- **根因**：`lib/features/backup/backup_page.dart:183-188`
- **影响**：导入后其它页面数据过期
- **修复**：导入成功后 `ref.invalidate(appConfigProvider)` + `ref.invalidate(mealLogRepoProvider)` 等

### #18 update_page error 态"重试"行为错误【P1，从 P2 升级】
- **根因**：`lib/features/update/update_page.dart:280`
- **影响**：install 失败后浪费带宽重下
- **修复**：根据 _state 记忆错误来源，上下文感知重试

### #19 confirmAction 长内容溢出 AlertDialog 不可滚动【P1，新发现】
- **根因**：`lib/core/widgets/m3_widgets.dart:292`
- **影响**：小屏机型破坏性操作确认按钮不可达
- **修复**：content Text 加 `maxLines: 8` + `overflow: ellipsis`，或 AlertDialog content 包 `SingleChildScrollView`

### #20 insight_page 图表区硬编码 fontSize 严重漏报【P2，第一轮漏报 13 处】
- **根因**：`lib/features/insight/insight_page.dart:875,889,906,1010,1216,1280,1394,1411,1497,1556,1574,1668,1758`
- **修复**：批量改 `tt.labelSmall(11)/bodySmall(12)`

### #21 insight_page 图表区缺 tabularFigures 严重漏报【P2，第一轮漏报 5 处】
- **根因**：`lib/features/insight/insight_page.dart:905,1009,1214,1278,1408,1554,1681`
- **修复**：批量加 `FontFeature.tabularFigures()`

### #22 race condition 集中区【P2，新发现 6 处】
- **根因**：`_isRenaming`/`_isRecording` 期间其它按钮/滑块未禁用
- **影响位置**：calibration_page 6 处 + multi_dish_page 2 处
- **修复**：所有 setState 期间相关交互组件禁用 + 视觉 disabled

### #23 滑块 min:0 可记录份量=0【P2，新发现 4 处】
- **根因**：`calibration_page.dart:382,706,729` + `multi_dish_page.dart:131`
- **修复**：min:1 或加校验

### #24 CircularProgressIndicator 批量缺 semanticsLabel【P2，新发现 6 处】
- **影响位置**：recommendation_section:165 / insight_page:744 / recognize_progress_card:55,75,202 / backup_page:82 / update_page:237 / m3_widgets:456
- **修复**：批量加 `semanticsLabel: '加载中'`

---

## 6. 修复优先级建议（两轮综合）

### 优先级 1：P1 严重问题（必须修，影响数据一致性 / 用户能完成核心流程）

#### A 类：数据一致性 / 正确性（5 条，最高优先级）
| # | 问题 | 文件 | 修复成本 |
|---|------|------|---------|
| 1 | 复合菜预览/记录路径优先级不一致 | calibration_page.dart:529 vs 892 | 中（条件对齐） |
| 2 | 复合菜 AI 优先路径未含用油量但滑块可见 | calibration_page.dart:529-552 vs 414-417 | 低（累加油量 or 隐藏滑块） |
| 3 | profile goalRate 游离 Form + 全页无范围校验 | profile_page.dart:279-287,150-178 | 中（goalRate 改 TextFormField + 全页加范围 validator） |
| 4 | weight 编辑 dialog 完全无校验静默 return | weight_page.dart:530-547 | 低（加 errorText） |
| 5 | backup_page 导入后未 invalidate provider | backup_page.dart:183-188 | 低（加 ref.invalidate） |

#### B 类：用户能完成核心流程（3 条）
| # | 问题 | 文件 | 修复成本 |
|---|------|------|---------|
| 6 | confirmAction 长内容溢出 AlertDialog 不可达 | m3_widgets.dart:292 | 低（加 maxLines 或 SingleChildScrollView） |
| 7 | update_page error 态"重试"行为错误 | update_page.dart:280 | 中（_state 记忆错误来源） |
| 8 | dish_name_editor 文案错误（第一轮） | dish_name_editor.dart:155 | 低（改文案） |

#### C 类：系统性问题根因（4 条，1 处修复多文件受益）
| # | 问题 | 根因文件 | 影响范围 | 修复成本 |
|---|------|---------|---------|---------|
| 9 | showAppToast 缺 liveRegion | m3_widgets.dart:321 | 全 App toast | 低（1 处） |
| 10 | EmptyState 硬编码 camera 图标 | m3_widgets.dart:137 | 非拍照场景空态 | 低（1 处） |
| 11 | 错误信息含原始异常（共 18 处：第一轮 9 + 第二轮 9） | 9 个文件 | 错误文案不友好 | 中（逐个改写） |
| 12 | 数值 TextField 缺 inputFormatters（7 个文件） | 7 个文件 | 输入离谱字符 | 中（批量） |

#### D 类：编辑流程一致性（4 条）
| # | 问题 | 文件 | 修复成本 |
|---|------|------|---------|
| 13 | meal_edit_dialog 无 dirty 拦截 | meal_edit_dialog.dart:261 | 低 |
| 14 | backup_page _import 重入窗口 | backup_page.dart:119 | 低 |
| 15 | settings_page TextField focus ring | settings_page.dart:139-205 | 中（5 处） |
| 16 | update_page AnimatedSize reduced-motion | update_page.dart:315 | 低 |

#### E 类：错误反馈与状态覆盖（4 条 P1）
| # | 问题 | 文件 | 修复成本 |
|---|------|------|---------|
| 17 | recognize_page SnackBar 缺 liveRegion | recognize_page.dart:567 | 低 |
| 18 | today_meals Undo SnackBar 缺 liveRegion | today_meals_page.dart:346-364 | 低 |
| 19 | today_meals Image.file 无 semanticLabel | today_meals_page.dart:402-419 | 低 |
| 20 | today_meals showDialog 未设 barrierDismissible:false | today_meals_page.dart:529 | 低 |
| 21 | 校验错误走 toast 而非 errorText（4 个文件） | meal_edit_dialog / food_edit / manual_entry / weight | 中（参照 profile_page） |

### 优先级 2：P2 高频模式（批量整改）

| # | 问题 | 影响范围 | 修复成本 |
|---|------|---------|---------|
| 22 | insight_page 图表区 fontSize 漏报 13 处 | insight_page | 中（批量改 textTheme） |
| 23 | insight_page 图表区 tabularFigures 漏报 5 处 | insight_page | 低（批量加） |
| 24 | race condition 6 处（_isRenaming/_isRecording 期间未禁用） | calibration_page / multi_dish_page | 中 |
| 25 | 滑块 min:0 可记录份量=0（4 处） | calibration_page / multi_dish_page | 低 |
| 26 | CircularProgressIndicator 缺 semanticsLabel（6 处） | 多文件 | 低 |
| 27 | 装饰图标未 ExcludeSemantics（15+ 处） | 多文件 | 中 |
| 28 | 长文本缺 maxLines+ellipsis（10+ 处） | 多文件 | 中 |
| 29 | 硬编码 fontSize（insight_page 19 处 + dish_card 5 处 + 其它） | 多文件 | 中 |
| 30 | ListView 缺 SafeArea（6 个文件 + backup_page） | 多文件 | 低 |
| 31 | 数字列缺 tabularFigures（dish_card / ai_estimate_card / insight_page） | 多文件 | 低 |
| 32 | 日期硬编码 padLeft / 原始 YYYY-MM-DD 串（5+ 处） | 多文件 | 中 |
| 33 | records_tab_page IndexedStack 改懒加载 | records_tab_page | 低 |
| 34 | recommendation_section v4 hasError/empty 补空态 | recommendation_section | 低 |
| 35 | insight_page _edit 补 dirty 拦截 | insight_page | 低 |
| 36 | recognize_page 拍照默认餐次按时段推断 | recognize_page | 低 |
| 37 | insight_page 7 图表 build 重建优化（RepaintBoundary） | insight_page | 中 |
| 38 | offline_queue_controller 后台回补 UI 反馈 + _monthlyCount 刷新 | offline_queue_controller / settings_page | 中 |
| 39 | backup_page 导入前 JSON 格式校验 | backup_page | 低 |
| 40 | GoRouter 加 errorBuilder + 补 /update 等路由 | app.dart | 低 |

### 优先级 3：P2 细节（可后续打磨）
- 按钮标签具体化（"保存"→"保存餐次"/"记录"→"记录体重"）
- hintText 末尾 `…` 一致性
- DropdownMenu 加 `label`
- 风险提示 Text 加 `maxLines`
- 反馈 dialog 按钮 `'准'`/`'不准'` 改"识别准确"/"识别不准"
- Undo SnackBar 文案告知撤销窗口时长
- TDEE reason 转用户友好文案
- 搜索历史 / 排序选项 / source 筛选（food_library）
- 首次进入引导文案（profile / weight）
- idle 态显示当前版本号（update_page）
- release notes markdown 渲染（update_page）
- 主题色板 disabled Semantics 提示（settings_page）
- Android<12 动态取色不可用提示（settings_page）

---

## 7. Assumptions & Decisions（假设与决策）

1. **审查范围**：全部 26 个 UI 页面文件（11514 行）+ m3_widgets 公共组件 + app.dart + main.dart 全局架构，共 26+4 = 30 个文件
2. **产出形式**：只出审查报告，不改代码（用户决策）
3. **优先级定义**：
   - P0 严重：崩溃 / 无障碍完全不可用 / 数据丢失风险
   - P1 重要：明显体验问题 / 无障碍部分缺失 / 文案错误 / 数据一致性 bug / 用户能完成核心流程
   - P2 改进：细节优化 / 一致性 / 视觉打磨 / 性能
4. **第二轮验证方法**：4 个并行 subagent 逐行 Read 文件验证第一轮 132 条发现 + 7 维度深度找漏
5. **"判断准确但漏报同类"算准确**：第一轮发现的点本身成立，只是同文件还有同类问题未列出。第二轮已补全
6. **Flutter Material 3 默认合规**：Material 3 组件（IconButton / TextField / Card 等）默认满足触控目标 ≥48dp / focus 反馈 / hover 反馈，审查时不再重复列出，只列偏离 Material 3 默认的问题
7. **v2 重构后契约**：显示值 = 记录值 + 用户手动兜底生效。第二轮发现 P1-1（calibration_page 复合菜预览/记录路径优先级不一致）违反此契约，需优先修

---

## 8. Verification（验证方式）

本报告为审查报告，无代码改动，无需运行验证。如用户后续选择修复，验证方式为：
- `flutter analyze` → No issues found
- `flutter test` → 全量通过，0 回归
- 6+1 硬约束全部满足（未碰 build.gradle / meal_log 外键 / AI 三路径 / per100g 反算基于 mid / SecureConfigStore / initSentryAndRunApp / minSdk=31）
- v2 重构核心契约验证：4 个断言（AI 估算值不被静默修改 / 校准页预览值 = onConfirm 写库值 / warnings 正确透传到 UI / 用户手动编辑覆盖 AI 值）

---

## 9. 下一步建议

报告已完成，第二轮深度审查在第一轮 0 P0 + 30 P1 + ~109 P2 基础上，验证 132 条全部准确（1 条部分误报修正 / 1 条升级），新发现 0 P0 + 15 P1 + ~115 P2，**累计 0 P0 + 45 P1 + ~224 P2**。

### 重点关注（强烈建议优先修复）

1. **P1-1 + P1-2 复合菜数据一致性问题**（calibration_page.dart）—— 违反 v2 重构核心契约"显示值 = 记录值"，且用户调整用油量滑块无效。这是新发现的 bug，需立即修
2. **P1 profile/weight 表单校验缺陷**（profile_page + weight_page）—— 垃圾输入直接写库污染下游
3. **P1 backup_page 导入后未 invalidate provider** —— 用户导入后看到旧数据
4. **P1 confirmAction 长内容溢出**（m3_widgets.dart）—— 破坏性操作确认按钮不可达
5. **P1 update_page error 重试行为错误** —— install 失败后浪费带宽

### 建议你审阅后决定

1. **是否要修复**？修复哪些优先级？
   - 选项 A：只修 P1（45 条）
   - 选项 B：P1 + P2 高频模式（系统性批量整改）
   - 选项 C：全部修
2. **修复策略**：
   - 选项 A：一次全修（单 commit）
   - 选项 B：分批修（按优先级 / 按 Group / 按问题类型分 commit）
   - 选项 C：先修 A 类数据一致性 + B 类核心流程（11 条），其余后续
3. **是否要补强某些审查维度**？
   - 视觉一致性 / 信息架构 / 用户流程 / 性能基准 / 实机测试
   - 本次第二轮已覆盖 7-9 个维度，但仍可深入（如视觉走查 / 实机无障碍测试 / 性能 profile）

等你的决策。
