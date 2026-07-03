# 项目交接文档（Handoff）

> **用途**：沙箱会话不持久化，每天 AI 会"失忆"。
> 本文档是跨会话记忆载体，每个会话开始时 AI 必读，结束前 AI 必更新。
> **维护规则**：每次会话有实质进展就更新，保持"任何新 AI 读完此文档就能无缝接手"。

---

## 0. 新会话开启指令（给 AI 看的）

```
你是接手这个项目的新 AI。请按以下顺序操作：
1. 读本文件全文（HANDOFF.md）了解项目状态与约定
2. 读 .trae/rules/ 下的项目规则（若有）
3. 跑 `git log --oneline -20` 看最近提交
4. 跑 `git status` 看工作区状态
5. 问用户"今天要继续做什么"——不要主动改代码
```

---

## 1. 项目速览

- **项目名**：慢慢吃（EatWise）—— 拍照识别食物热量 + 营养记录 + AI 汇总建议
- **技术栈**：Flutter 3.44.4 / Dart / Riverpod / drift (SQLite) / Material 3 Expressive
- **当前版本**：0.12.0+13（pubspec.yaml）
- **当前分支**：v0.10.0-m3-merge（基于 v0.8.0，叠加 HEAD 的 AI 估热+主题色+Sentry）
- **关键约束**：
  - `meal_log.food_item_id` 是非空外键，PRAGMA foreign_keys=ON，foodItemId=0 哨兵写库前必须替换为真实 id
  - `android/app/build.gradle.kts` 必须保持 `isMinifyEnabled=false` + `isShrinkResources=false`（否则 R8 剥掉 sentry/workmanager 反射类致启动崩溃）
  - AI 兜底（foodItemId=0）需在前台 recognize_page、multi_dish_page、后台 offline_queue_controller 三条路径全部覆盖

---

## 2. 当前状态（每次会话结束更新）

**最后更新**：2026-07-03

**工作区状态**：clean（v0.13.0 已发布，workflow success；v0.12.0 已发布）
**最近 commit**：
- `1fdff0e` chore: bump 版本号到 0.13.0+14 准备发布 v0.13.0
- `11a0cba` docs: HANDOFF 补 Phase 3 C/D 批详情 + 陷阱 49（confirmAction/showAppToast 抽象偏好）
- `4252093` refactor: UI/UX 审查修复 D 批第三轮——confirmAction + showAppToast 公共抽象
- `390d19a` refactor: UI/UX 审查修复 D 批第二轮——foodSourceLabel/EmptyChartHint/WarningBanner/_sectionTitle
- `d46a1b9` fix: UI/UX 审查修复 C 批——数据安全 + 一致性 S 级
- `4ad029c` docs: HANDOFF 补 Phase 3 陷阱 45-48
- `（前次）` feat: UI/UX 审查修复 Phase 3——公共抽象层 B1-B6 + 数据安全 A1-A4
- `db80dfb` feat: 全 editable 第一批——体重记录可改值/改日期/删，餐次记录可改份量/营养/餐次/日期/换食物/高级覆盖
- `79a0ae6` feat: 食物识别增强四层自我进化架构（P0/P1/P2，已随 v0.13.0 发布）
- `7d1e8bd` docs: HANDOFF 补全 v0.12.0 release workflow run URL + APK 大小
- `cbdc664` docs: HANDOFF 补充图标精致化详情（v0.12.0 已含）
- `c37912b` feat: 启动器图标精致化 + bump v0.12.0（已发布 v0.12.0）
- `932c56c` docs: HANDOFF 补充深度审查修复 commit hash f5e611a
- `f5e611a` fix: 深度审查修复 15 项——TdeeCalibrator 符号/insertManual 别名冲突/酒精热量清零/JsonImporter FK+Sentry try-catch/NaN 校验/硬下限/markFailed 事务等（已随 v0.12.0 发布）
- `a8aa1f5` feat: 界面 MD3 全面优化（协调性+合规+字体层级，已随 v0.12.0 发布）
- `a680241` feat: 智能推荐算法 v3 五维评分 + addAlias 冲突检测（已随 v0.12.0 发布）
- `1064449` fix: 识别精准度修复+界面偏右修正（雪花啤酒→雪碧假阳性，已随 v0.12.0 发布）

**本次全 editable 第一批（已随 v0.13.0 发布）**：
解决用户反馈"所有功能都希望自己改，比如体重输错了点了确认后还能改"。
4 批渐进实施，本次第一批（P0：体重 + 餐次全 editable）。
- **体重记录全 editable**：`WeightLogRepository` 加 `getById`/`update`/`delete`（部分更新，null 跳过）；`weight_page` ListTile → Dismissible（左滑删除带二次确认 dialog）+ onTap 编辑 dialog（体重 TextField + 日期 DatePicker，StatefulBuilder 局部刷新）；编辑最新一条时同步 `ProfileRepository.update(weightKg:)`（与 _save 一致逻辑，保证 dashboard 宏量目标用最新体重）；删除/编辑后调 RefreshBus.notify 跨页刷新
- **餐次记录全 editable（8 字段）**：`MealLogRepository.updateMealLog` 从 5 必填营养字段扩展为 8 可选字段（加 date/mealType/foodItemId，全部 null 跳过保持原值），向后兼容现有 5 处调用；新增独立 `MealEditDialog`（ConsumerStatefulWidget，5 个 TextEditingController 管理份量+4 营养），支持换食物（push FoodLibraryPage pickForReuse 模式 + 自动重算营养）、改餐次（ChoiceChip 4 选 1）、改日期（DatePicker ListTile）、高级覆盖（ExpansionTile 4 个营养 TextField，监听手动修改标记 _nutritionOverridden 优先级最高）、营养重算优先级（advanced 覆盖 > 换食物重算 > 份量比例）
- **哨兵防御扩展**：`updateMealLog` 加 `foodItemId != null && foodItemId <= 0` ArgumentError 校验（与 insertMealLog 一致，防 UI 把 0 哨兵写入非空 FK 字段）
- **测试**：weight_log_repository 加 11 个测试（getById 2 + update 5 + delete 3 + 不存在 id 边界），meal_log_repository 加 9 个测试（date/mealType/foodItemId 部分更新 5 + 哨兵防御 4），全量 377 passed (3 skipped)
- **文件**：新建 1（meal_edit_dialog.dart），修改 4（weight_log_repository/weight_page/meal_log_repository/today_meals_page）+ 2 测试文件

**本次 UI/UX 审查修复 Phase 3（已随 v0.13.0 发布）**：
4 路并行 search agent 全面审查所有界面，识别 14 S 级 + 30+ M 级 + 10 L 级问题，分 6 批（A-F）渐进修复。本次完成公共抽象层（B1-B6）+ 数据安全（A1-A4）共 10 项。
- **B1 date_format 公共工具**：新建 `lib/core/util/date_format.dart`——`parseYmd`（严格校验：regex + 月/日范围 + round-trip 检查，非法日期返回 null 不抛异常）+ `formatYmd`（DateTime → yyyy-MM-dd）；新增 5 个单元测试。替代各页散落的 `DateTime.parse` + 手写格式化，统一日期边界处理
- **B2 food_name 公共工具**：新建 `lib/core/util/food_name.dart`——`placeholderFoodName(foodItemId)` 生成「未知食物#id」+ `isPlaceholderFoodName(name)` 判断；跨页统一食物名占位符（today_meals/dashboard/meal_edit_dialog 等），避免各页硬编码 `食物${id}` 字符串拼接不一致
- **B3 EmptyState 组件**：`m3_widgets.dart` 新增 `EmptyState`（icon + title + 可选 subtitle + 可选 action button），MD3 间距（icon→title 16 / title→subtitle 8 / subtitle→button 16 / 外 padding 32）；替换 today_meals_page 和 dashboard_page 2 处内联空态实现，删除 `_buildEmptyState()` 私有方法
- **B4 GroupCard 组件**：`m3_widgets.dart` 新增 `GroupCard`——`dividerIndent` 参数（null=不自动插分隔线，非 null=子项间自动插 Divider）+ 静态 `GroupCard.divider(context)` 手动插分隔线；替换 me_page（3 处）+ settings_page（7 处）共 10 处 `_groupCard` 调用，删除 4 个私有方法（`_groupCard`×2 / `_withDividers` / `_divider`）
- **B5 MealTypeSelector 组件**：`m3_widgets.dart` 新增 `MealTypeSelector`——封装 SegmentedButton 固定 4 段（早餐/午餐/晚餐/加餐），value/onChanged 接口；替换 recognize_page + manual_entry_page 2 处内联 SegmentedButton（各 ~10 行），recognize_page 补 m3_widgets import
- **B6 清理冗余 border: OutlineInputBorder()**：app.dart 的 `inputDecorationTheme`（L68-71）是全局主题单一源，6 文件 11 处冗余 `border: OutlineInputBorder()` 清除（meal_edit_dialog 6 / weight_page 2 / insight_page 1 / backup_page 1 / today_meals_page 2）；仅 app.dart 保留作全局定义
- **A1 Undo SnackBar 乐观删除**：today_meals_page 餐次卡片 Dismissible 改乐观删除——先从 UI 移除 + 显示 4s 撤销 SnackBar，未撤销才实际从 DB 删除（`repo.deleteMealLog`）；删除失败回滚 `_load()` + 错误提示。比原"立即删 + SnackBar 提示"更宽容误操作
- **A2 food_library 加载态**：food_library_page 加 `_initialLoading` 标志，`_loadFrequent` finally 块置 false；空态 UI 在 `_initialLoading` 时显示 CircularProgressIndicator（替代误导性的"暂无常用食物"文案），避免首屏加载期间显示假空态
- **A3 PopScope 未保存确认**：`m3_widgets.dart` 新增 `confirmDiscardChanges(context)` 共享 dialog（继续编辑/放弃）；4 个编辑页（food_edit_page / profile_page / settings_page / calibration_page）加 `bool _dirty` + `_markDirty()` + controller listeners + `PopScope(canPop: !_dirty, onPopInvokedWithResult: ...)`；profile_page/settings_page 的 `_markDirty` 加 `_loading` 守卫防初始赋值误标 dirty；保存成功后 `_dirty = false` 再 Navigator.pop
- **A4 RecognizePage 错误态重试入口**：recognize_page 加 `ImageSource? _lastSource` 记录最近选图来源；错误态 SnackBar 加"重试"按钮（6s 时长），点击重新调 `_pickAndRecognize(source)`；按错误类型智能判断可重试性——「操作太快」（限流 30s，重试只再触发限流）/「已转手动录入」（L3 已跳转）/「安全过滤」（同图结果不变）三类不显示重试，其余错误（压缩失败/模糊图/API 异常/入队失败）可重试
- **验证**：flutter analyze No issues + flutter test 392 passed (3 skipped)
- **文件**：新建 2（date_format.dart / food_name.dart）+ 2 测试文件，修改 12（m3_widgets / recognize_page / recognize_controller / multi_dish_page / calibration_page / today_meals_page / dashboard_page / meal_edit_dialog / food_library_page / food_edit_page / profile_page / settings_page / me_page / weight_page / insight_page / backup_page / manual_entry_page）

**未完成/待办**（按优先级）：
1. ⬜ 用户真机验收 v0.13.0（装 APK 验证：食物识别四层闭环 + 体重/餐次全 editable + UI/UX 审查修复 Phase 3 五批）
2. 🔧 UI/UX 审查修复 F 批：输入校验——TextField → Form+TextFormField validator（用户已确认范围=全部 7 页 + 实时校验+错误提示 MD3 模式；风险较高会改 form 行为，开工前需逐一确认每页校验规则）
3. 🔧 全 editable 第二批：FoodItems 删除/归档 + name/aliases 编辑（用户已批准 4 批计划，第一批已完成）
4. 🔧 全 editable 第三批：PendingRecognitions UI 页 + 重试/删除 + Feedbacks 历史/删除
5. 🔧 全 editable 第四批：历史 InsightSummaries 查看页 + 份量校准回滚
6. 🔧 第三波（待用户确认后启动）：建议 6（接入 USDA FoodData Central API 替代部分 OFF 云查，免费但需 API key）—— 但需先评估 OFF 中文命中率，USDA 是英文 API 中文菜名需翻译层
7. ⏸️ 建议 4 餐前/餐后双拍对比（DietDelta 思路）：用户明确暂不做
8. 🔧 重构性优化（风险较高，不阻塞当前版本）：
   - 路由方式统一（GoRouter vs Navigator.push 混用）
   - 版本号从 PackageInfo 读取（替代硬编码，me_page/settings_page/sentry_init 三处）
   - dashboard/today_meals N+1 查询优化（getByIds）
   - 测试覆盖增强：AI 兜底（test S3 哨兵防御已补）、getThemeSeed 单元测试
   - Sentry appRunner 标准化 + FlutterError.onError 链式调用
   - 后台回补补 fallback provider + circuitBreaker + incrementMonthlyCount
   - NutritionLookup 3x OFF 云查重构（深度审查 M4，暂不修复）
   - RecognitionPostProcessor correctAdditionalDishes needsRetry 丢弃（深度审查 M3，暂不修复）
   - image_quality_checker 改 isolate（深度审查 core M1，暂不修复）

**本次 P0/P1/P2 食物识别增强（已随 v0.13.0 发布）**：
解决"雪花啤酒识别成雪碧 + 奶茶/网红零食能否准确分辨 + 热量能否严谨计算"三问。
核心思路：不追求库覆盖所有食物，建立"AI 估算(品类校准) + 品牌库(头部覆盖) + OFF(包装食品) + 用户纠错(长尾自进化)"四层闭环。
- **P0 品类校准 + brand 持久化**：新建 `food_category_defaults.dart`（beer=43/wine=83/carbonated=43/milk=61 等 13 品类默认值），AI 兜底 per100g 偏离默认值 2 倍用默认值替代；`upsertAiRecognized` 加 brand 参数，"品牌+菜名"存为 alias（如"雪花啤酒"），下次精确命中
- **P1 品牌官方热量库**：新建 `assets/chain_drink_menu.json`（10 品牌 41 招牌：喜茶/霸王茶姬/奈雪/瑞幸/星巴克/蜜雪/古茗/茶百道/一点点/Manner，数据来自各品牌小程序官方公示），`FoodSeedImporter.importChainDrinksFirstTime` 首次启动导入；`findByNameOrAlias` 加 brand 参数，优先级 0 按 brand+name 精确查品牌条目
- **P2 OFF brand 组合查询 + 反馈回流创建新条目**：`OffProvider.lookup` 加 brand 参数，先查"brand+name"再回退 name；`today_meals_page` 反馈回流精确 miss 时 `insertManual` 创建新条目（source='manual'，aliases=AI 错误名），实现长尾自进化
- **prompt v1.8**：补啤酒/茶饮剥离示例（雪花啤酒→dish_name=啤酒/brand=雪花，喜茶多肉葡萄→dish_name=多肉葡萄/brand=喜茶），强调连锁品牌 brand 必填
- **测试**：新增 18 个测试（品类校准 11 + brand 匹配 3 + brand 持久化 4），全量 358 passed (3 skipped)
- **文件**：新建 2（food_category_defaults.dart / chain_drink_menu.json），修改 8（prompts/food_item_repository/nutrition_lookup/off_provider/recognize_page/recognize_controller/multi_dish_page/offline_queue_controller/today_meals_page/database/food_seed_importer/pubspec）
- `52dc876` docs: 更新 HANDOFF——v0.11.1 已发布
- `84cc29a` feat: 个人档案特殊人群适配（孕期/哺乳/老年/青少年/糖尿病/肾病/素食，schema v1→v2，已随 v0.11.1 发布）
- `c6a76be` feat: 折线图美化与智能推荐算法升级（Y 轴 interval 防重叠+渐变填充+触摸 tooltip+推荐四维评分，已随 v0.11.1 发布）
- `685fc9e` docs: 更新 HANDOFF——记录启动与首屏性能优化
- `d1e5970` perf: 启动与首屏加载性能优化（secure_storage 并行+首屏查询并行+N+1→批量+splash 配色，已随 v0.11.1 发布）
- `fbcbf1e` fix: 修复 tab 页 dialog 按钮点击黑屏（嵌套 Navigator 误 pop 页面，已随 v0.11.1 发布）
- `b97eb89` style: 今日明细页卡片式重构（缩略图+营养素圆点+餐次小计，已随 v0.11.1 发布）
- `1f1fad0` fix: 校准页加多份识别警告横幅（避免一罐被识别成两罐时记录双倍克数，已随 v0.11.1 发布）
- `ec5d452` docs: 更新 HANDOFF——v0.11.0 已发布
- `58db4e3` chore: 版本号 bump 到 0.11.0+11 准备发布 v0.11.0
- `add3c42` docs: 更新 HANDOFF——主页刷新修复（profile/weight→RefreshBus→dashboard）
- `b167574` fix: 个人档案/体重页保存后通知主页刷新（profile/weight→RefreshBus→dashboard）
- `62dd475` refactor: 提取 RecognitionPostProcessor 修复三路径行为分叉（第二波 2.0+2.1）
- `47fd22c` feat: 食物热量计算优化第一波——可食部分系数+组分份量交叉验证+液体密度换算（建议1+3+7）

**已发布**：
- v0.13.0 已发布（2026-07-03，包含 v0.12.0 之后 3 大块：食物识别增强四层自我进化架构 P0/P1/P2 + 全 editable 第一批 体重+餐次 + UI/UX 审查修复 Phase 3 A+B+C+D+E 五批共 26 项）
  - Release: https://github.com/qbjsdsb/eatwise/releases/tag/v0.13.0
  - app-release.apk 74.1 MB / app-debug.apk 167.6 MB（debug 签名，自用版）
  - workflow run: https://github.com/qbjsdsb/eatwise/actions/runs/28680625942（success，13 分钟，由 `git push tag v0.13.0` 触发）
  - 新增能力：①食物识别四层闭环（品类校准兜底+品牌官方热量库 10 品牌 41 招牌+OFF brand 组合查询+反馈回流创建新条目）②体重记录全 editable（改值/改日期/删）③餐次记录 8 字段全 editable（份量/4 营养/餐次/日期/换食物/高级覆盖）④UI 公共抽象层（confirmAction/showAppToast/EmptyChartHint/WarningBanner 等 10+ 共享组件）⑤数据安全（乐观删除+Undo/PopScope 未保存确认/错误态可重试/加载失败显 ErrorState）
- v0.12.0 已发布（2026-07-03，包含 v0.11.1 之后 5 个修复/优化：识别精准度+智能推荐 v3+MD3 全面优化+深度审查修复 15 项+启动器图标精致化）
  - Release: https://github.com/qbjsdsb/eatwise/releases/tag/v0.12.0
  - app-release.apk 73.4 MB / app-debug.apk 167.6 MB（debug 签名，自用版）
  - workflow run: https://github.com/qbjsdsb/eatwise/actions/runs/28669494536（success，由 `git push tag v0.12.0` 触发）
- v0.11.1 已发布（2026-07-03，包含 v0.11.0 之后 6 个修复/优化：校准页警告+明细页卡片重构+dialog 黑屏修复+启动性能优化+折线图美化与推荐算法升级+个人档案特殊人群适配）
  - Release: https://github.com/qbjsdsb/eatwise/releases/tag/v0.11.1
  - app-release.apk 73.3 MB / app-debug.apk 167.5 MB
  - workflow run: https://github.com/qbjsdsb/eatwise/actions/runs/28662699235（success，19 步全过）
- v0.11.0 已发布（2026-07-03，包含识别智能化+食物热量优化第一波+第二波+主页刷新修复，APK 已上传）
  - Release: https://github.com/qbjsdsb/eatwise/releases/tag/v0.11.0
  - app-release.apk 73.1 MB / app-debug.apk 167.5 MB
  - workflow run: https://github.com/qbjsdsb/eatwise/actions/runs/28658030594（success）
- v0.10.0 已发布（2026-07-03）

**v0.11.1 已发布包含的六个修复（v0.11.0 之后）**：
1. **校准页多份识别警告**（`1f1fad0`）：用户反馈"一罐芬达显示两罐克数"。根因是 AI 偶发误判 quantity=2，校准页默认用 `estimatedWeightGMid`（已含 quantity 乘积）作初值，数量步进器在底部不显眼，用户未调整直接确认会写入双倍克数。修复方式：quantity>1 时在标题下方加 tertiaryContainer 警告横幅，提示用户检查数量。
2. **今日明细页卡片式重构**（`b97eb89`）：用户反馈"明细界面不够美观"。ListTile → Card 卡片布局：56x56 圆角缩略图、份量/热量 chip、三大宏量营养素彩色圆点、餐次分组带竖条+小计热量。纯 UI 层重构，不动写入逻辑。
3. **tab 页 dialog 按钮点击黑屏**（`fbcbf1e`）：用户反馈"识别准不准"的准/不准按钮、"关于"里的隐私政策按钮点击后黑屏，退出重进才恢复。根因：GoRouter 的 `StatefulShellRoute.indexedStack` 给每个 tab 配嵌套 Navigator，`showDialog` 默认 `useRootNavigator:true` 把 dialog push 到 root Navigator，但按钮 `Navigator.pop(context)` 用页面 context，`Navigator.of(context)` 找到 tab 嵌套 Navigator，把栈顶页面本身（MePage / RecordsTabPage）pop 掉了。修复 3 处（me_page._showPrivacy、today_meals_page._showEditDialog、today_meals_page._showFeedbackDialog 准/不准），统一改 `builder:(ctx)=>` + `Navigator.pop(ctx)`。**坑提醒：今后在 tab 页（dashboard/records/insight/me 分支下）写 dialog，关闭按钮必须用 dialog 的 ctx，不能用页面 context。**
4. **启动与首屏加载性能优化**（`d1e5970`）：用户反馈"点开软件要黑屏一两秒"。三个瓶颈：① main.dart 的 getThemeSeed 和 appConfig 两次独立 secure_storage 读取原串行，改提前触发 appConfigProvider 并行；② AppConfig.load() 原 10+ 次串行 platform channel read 改"同时启动 7 future + 分别 await"并行，并复用结果省 3 次重复 read；③ DashboardPage/TodayMealsPage 食物名反查 N+1 → FoodItemRepository.getByIds 批量 IN 查询，首屏三查询并行；④ Android launch_background 纯白底改 @color/splash_background 匹配 app 默认 surface 色（亮 #FCF9F9/暗 #1C1B1F）。**坑提醒：Future.wait 因多类型 future 会退化为 List<Object?>，并行不同类型 future 应用"同时启动 + 分别 await"模式保留类型。**
5. **折线图美化与智能推荐算法升级**（`c6a76be`）：用户反馈"折线图不够美观有数字重叠"+"智能推荐不够智能"。折线图：Y 轴固定 interval（热量 maxCal/4 取整 50 倍数 / 体重范围/4 至少 0.2）彻底消除重叠，参考线标签左对齐+padding(left:44) 避开 Y 轴 + 上下错开，边框只留左下，网格只水平虚线半透明，数据点变小+surface 描边，belowBarData 改 LinearGradient 渐变，加 lineTouchData 触摸 tooltip。推荐算法 v2：四维评分（相对缺口匹配 remaining/goal 比例取最缺宏量加权 / 历史频次 log2 压缩封顶 4 分 / 排除今日已吃 / 具体理由"补蛋白 32%"），新增 `MealLogRepository.getRecentFoodCounts`（最近 30 天引用次数）。**坑提醒：推荐算法蛋白缺口触发阈值用 hasProteinGap（remainingProtein>5）而非 ratio<0.3，无记录时 ratio=1.0 但仍应触发，否则高蛋白食物不被推荐（测试已覆盖）。**
6. **个人档案特殊人群适配**（`84cc29a`）：用户反馈"个人信息太简单，不能应用在不同人群"。profile 表 schema v1→v2 加 3 个 nullable 列（specialCondition/dietPreference/healthCondition，null 视为 'none' 向后兼容）。NutritionCalculator 按权威来源调整：孕期 +340 / 哺乳期 +500 kcal（IOM 2006）、老年蛋白 1.2g/kg 防肌少症（ISSN）、肾病蛋白 cap 0.8g/kg（KDOQI）、糖尿病碳水 cap 45%（ADA）。ProfilePage 加"特殊状况"段（3 个 DropdownMenu + 风险提示卡片）+ 活动量描述优化（步数/锻炼频率）+ 保存时孕期/哺乳/肾病减脂风险警告。JsonExporter/Importer 同步 3 字段导出导入；版本检查从严格相等放宽为只拒绝高于当前版本（支持旧备份恢复到新版本）。**坑提醒：JsonExporter 加新字段必须同步 JsonImporter 读取，否则备份恢复丢数据；DropdownMenu 测试用 find.byKey 定位，不要用 .last/.first（新增菜单会让索引漂移）。**

**v0.11.1 之后的修复（已随 v0.12.0/v0.13.0 发布）**：
7. **识别精准度修复 + 界面偏右修正**（`1064449`）：用户反馈"雪花啤酒被识别成雪碧"+"界面整体偏右"。识别错配根因有三：①findByNameOrAlias 优先级 5 编辑距离 ≤1 对 2 字短名假阳性（"雪花"vs"雪碧"编辑距离恰好 1 → 误命中）；②反馈回流 addAlias 用 5 级模糊查"正确菜"，模糊命中错对象后把 AI 错误名写成错对象别名 → 永久错配（无法自愈）；③_normalize 不处理全角半角（AI 返回全角字符精确匹配 miss → 降级模糊匹配增加误命中）。修复：①优先级 5 加严——query 长度 ≥3 且 target 与 query 等长才走编辑距离（2 字短名禁用，typo 容错仅保留 3+ 字等长如"蕃茄炒蛋"→"番茄炒蛋"）；②新增 findExactByNameOrAlias（只走 name/alias 精确匹配），today_meals_page 反馈回流改用它，避免模糊命中错对象导致反向错配；③_normalize 加全角→半角转换（数字/字母/空格/括号）。界面偏右根因：SectionTitle padding `fromLTRB(24,20,16,8)` 左 24 右 16 不对称，被 6 页面 14 处复用，标题相对下方卡片（padding 16）右移 8px → 改 `fromLTRB(16,20,16,8)` 对称；dashboard/me_page 的 Divider 缺 endIndent → 补 `endIndent: 16`。新增 4 个精准度专项测试（雪花不命中雪碧/typo 容错保留/findExact 只精确/全角括号归一化）。**坑提醒：2 字短名编辑距离 1 无法区分"假阳性（雪花/雪碧）"与"typo（可东/可乐）"，取舍上禁用 2 字短名编辑距离（牺牲罕见 2 字 typo 容错换取防常见相近名误判）；反馈回流别名必须用精确匹配查库，绝不能用模糊匹配（否则反向错配永久污染别名表）。**

8. **智能推荐算法 v3 五维评分 + addAlias 冲突检测**（`a680241`）：用户反馈"推荐冷门食物，不学习习惯，参考业界成熟方案优化"。WebSearch 调研业界（MyFitnessPal/Yazio/薄荷/Lifesum/Carbon Diet Coach），严谨筛选：弃用协同过滤（单机无用户群）、AI 生成食谱（离线 app）、替换建议（需建替代图谱留后续）；采用内容推荐+频次+约束过滤+时段感知+多样性（全离线，基于现有数据）。v3 五维：①冷门降权——常吃蛋白加权 *4，基础食材 *3，冷门 *1.5（直击"冷门霸榜"痛点，原 v2 全部 *4 致冷门高密度食物盖过常吃基础食材）；②基础食材白名单——硬编码 ~50 个中式家常食材关键词（鸡蛋/鸡胸/牛奶/燕麦/米饭/豆腐/苹果/西兰花…）命中 +3 底分，保证常见食物不沉底；③profile 约束过滤——素食/纯素/乳糖不耐/无麸质硬排除违规食物（按名称关键词），糖尿病高糖降权 *0.3，肾病极高蛋白降权 *0.5（软降权避免列表空）；④时段感知——MealLogRepository 新增 getMealTypeDistribution 学习每食物历史 mealType 分布（ratio>0.5 加 3 分），dashboard 按当前小时推断 mealType 传入；⑤多样性——排除今日已吃（已有）+ 昨日已吃降权 -2。addAlias 冲突检测（防反向错配第二道防线，findExact 是第一道）：写入前遍历全表，若别名已是其他食物的 name/alias 则拒绝写入，防止反馈回流把同一错误名绑多食物致永久错配。新增 9 个专项测试（冷门降权/白名单底分/素食过滤/乳糖过滤/时段感知/多样性 + addAlias 冲突检测 3 个）。**坑提醒：recommend() 新增 profile/mealType/yesterdayDate 全是可选参数，不传时退化到 v2 行为（向后兼容现有测试）；时段感知是数据驱动（学历史 mealType 分布）非硬编码"早餐食物"，样本<2 不返回避免单次误判；糖尿病/肾病用软降权而非硬排除，避免推荐列表空；addAlias 冲突检测遍历全表 O(n) 但在 addAlias 事务内，反馈回流低频调用可接受。**

9. **界面 MD3 全面优化**（`a8aa1f5`）：用户反馈"所有界面检查是否最新 MD3 感觉、协调、美观，借鉴开源"。search agent 全面审查 14 文件识别 37 个问题（H/M/L 三级），WebSearch 调研 MD3 v6.1 规范 + 开源饮食 app（FoodYou/NutriScan 的 Material You + Macro Rings）。实施全 4 批：**第一批协调性**——insight SegmentedButton pin 到 AppBar.bottom（与 records_tab 统一，不随滚动消失）；weight 折线图按 insight 范式重写（左下边框+虚线网格+渐变填充+tooltip+统一 barWidth2.5+图例）；宏量营养素跨页统一用 MacroColors（蛋白=tertiary/脂肪=secondary/碳水=primary，新增 m3_widgets.MacroColors 类，替代 dashboard 的 onPrimaryContainer alpha + today_meals 的硬编码 0xFF4CAF50）；today_meals 卡片改 Card.outlined+12dp+padding16（统一 dashboard）；today_meals section header 改用扩展后的 SectionTitle(trailing:)（替代手写色块+标题+sum）；me/settings 分隔线改 cs.outlineVariant（替代 MD2 的 Theme.dividerColor）。**第二批 MD3 合规**——today_meals 编辑对话框"保存"改 FilledButton（原 TextButton 违反 MD3 主操作规范）；profile 特殊状况提示改 Card(tertiaryContainer)（替代手写 Container）；profile/settings emoji 警告改 Icon(warning_amber_rounded, cs.error)（emoji 跨平台渲染不一致且不跟随主题）；settings 选中态 check 色按色块亮度动态选黑/白（WCAG AA）；recognize 遮罩改 cs.scrim（替代硬编码 Colors.black54）+ 次要按钮改 OutlinedButton 形成主次层级；food_library 列表项补 chevron + 空态套 Card；me 错误态 Icon 补 cs.error；today_meals 反馈 IconButton 恢复 48dp 触摸目标。**第三批字体层级**——SectionTitle 改 titleSmall（原 labelLarge 语义偏标签）；批量替换硬编码 fontSize 为 textTheme（dashboard displaySmall/bodySmall/labelSmall、today_meals labelSmall、me titleMedium/bodySmall、insight bodyMedium）。**坑提醒：MacroColors 是 m3_widgets 新增的共享类，跨页配色必须用它而非各自硬编码，否则 dashboard/today_meals 颜色再次分裂；SectionTitle 新增 trailing 参数是可选的，现有 14 处调用不传 trailing 不受影响（向后兼容）；records_tab/insight 的 AppBar 用普通 AppBar+bottom 而非 SliverAppBar，因 IndexedStack/ListView 子页有自己滚动，SliverAppBar 需 CustomScrollView 重构成本大，权衡用 bottom pinned 已满足"切换器常驻"需求。**

10. **深度审查修复 15 项**（commit `f5e611a`，已随 v0.12.0 发布）：用户要求"反复检查项目所有代码，最深度最深入找问题并严谨修复"。4 路并行 search agent 审查 features / ai+nutrition+data / core+main / test 四领域，识别 6 严重 + 10 中等 + 13 轻微 + 5 测试问题。修复 15 项（10 lib + 4 test + 1 HANDOFF）：**严重**——①`TdeeCalibrator.runAndApply` 符号约定冲突（`calibrate` 注释"减脂负/增肌正"但 profile.goalRateKgPerWeek 存正值，runAndApply 直传致减脂用户校准方向恒错，加 signedGoalRate 转换）；②`FoodItemRepository.insertManual` aliases 参数漏冲突检测（addAlias 有全表检测但 insertManual 漏，手动录入 AI 错误名可绑多食物致永久错配，复用 addAlias 全表遍历逻辑）；③`RecognitionValidator` 营养素自洽校验把酒精饮料热量清零（expected=4p+9f+4c 不含酒精 7kcal/g，啤酒 cal=150 但 expected=48 被强制清零，加 `expected>0` 守卫只在 expected 非零时校验）；④`JsonImporter` DELETE 序列漏 pending_recognitions（result_food_item_id 是 FK NO ACTION，DELETE food_items 前未清致真机导入 FK 阻塞）；⑤`JsonImporter` `as int` 强转崩溃（旧版备份缺字段时 `null as int` 抛 TypeError，新增 `_asInt`/`_asIntOrNull` 兜底，所有非空 int 字段全部替换）；⑥`SentryFlutter.init` 无 try-catch（初始化抛异常时 zone guard 只记日志不 runApp → 永久黑屏，加 try-catch 降级返回原 app）。**中等**——⑦`NutritionCalculator` gender=null 跳过硬下限（女性可能拿到 <1200 危险低目标，null 默认 1500 兜底）；⑧`PendingRecognitionRepository.markFailed` 非事务竞态（read-then-write 无事务，"立即重试"与 workmanager 并发时计数丢失，包 `_db.transaction`）；⑨`backup_page` 遮罩硬编码 Colors.black54（改 cs.scrim）；⑩`sentry_scrub` hex 正则只匹配小写（`[a-f0-9]` → `[a-fA-F0-9]`）；⑪版本号过时（me_page/settings_page 0.10.0 → 0.11.1）；⑫`RecognitionValidator` NaN 绕过校验（NaN<0=false NaN>1=false 通过 confidence/weight 校验，加 isNaN 显式判断）。**测试**——⑬`recommendation_service_test` 4 处假绿断言（`if (idx>=0)` 守卫让比较断言静默跳过，加 `expect(idx, greaterThanOrEqualTo(0))` 前置断言，薯片因 score=-17.35 被合理过滤是设计行为保留 if）；⑭`json_export_import_test` schema v2 三字段漏测（seedData 加 specialCondition/dietPreference/healthCondition，导入后断言）；⑮`meal_log_repository_test` 哨兵防御漏测（新增 foodItemId=0/-1 抛 ArgumentError + foodItemId=1 正常写入 3 个测试）。**坑提醒：TdeeCalibrator calibrate 算法期望"减脂负/增肌正"符号，但 profile.goalRateKgPerWeek 存正值（NutritionCalculator 用 >0 判断），runAndApply 必须按 goal 转换符号；JsonImporter DELETE 序列必须先子表后父表，pending_recognitions.result_food_item_id 是 FK 必须在 food_items 之前清；SentryFlutter.init 失败要降级返回原 app 保证 runApp 能执行（不能让初始化失败致永久黑屏）；RecognitionValidator 营养素自洽校验只在 expected>0 时执行，酒精/纤维/糖醇等非 Atwater 来源热量不能强制清零。**- 验证：`flutter analyze` No issues + `flutter test` 340 passed (3 skipped)。

11. **启动器图标精致化**（commit `c37912b`，已随 v0.12.0 发布）：用户反馈"软件图标太难看了，符合安卓设计规范的同时再精致一点点"。保持「碗+蒸汽」品牌语义（碗=食物，蒸汽=袅袅升起的温热感=慢慢吃），符合 Android Adaptive Icon 规范（108dp 画布 + 66dp 安全区 + 前景/背景/monochrome 三层），精致化五点：①背景平面青绿 → 对角线三色渐变 `#6BA08C→#5B8C7B→#4D7A6C`（立体感）；②前景色纯白 → 奶白 `#FDFBF7`（温暖，与 splash `#FCF9F9` 协调）；③碗口单椭圆 → 环形双线（外椭圆 `evenOdd` 挖内椭圆，厚度感，精致关键）；④碗底加小椭圆底座（稳重感）；⑤蒸汽 stroke 3→2.8，曲线更柔和，错落（中间高两侧低）。所有图形严格在 66dp 安全区 (21,21)-(87,87) 内，OEM 蒙版（圆/方圆角）不裁切。实现：vector drawable（`ic_launcher_background.xml` 渐变 shape + `ic_launcher_foreground.xml` 前景 vector，API 26+ 现代设备）+ Pillow 4x 超采样生成 5 密度 PNG fallback（48/72/96/144/192，API 21-25 旧设备）。monochrome 复用前景供 Android 13+ 主题图标（用户可让图标跟随壁纸取色）。**坑提醒：Android vector `fillType="evenOdd"` 在 API 24+ 支持，自适应图标 API 26+，兼容无问题；PNG fallback 不能漏，minSdk 21 的旧设备无 PNG 会显示默认图标；碗口环形用 evenOdd 挖空而非纯色填充（背景是渐变，纯色挖空会色差）；Pillow 画圆头线段需手动在端点画填充圆（ImageDraw.line 不支持圆头）；4x 超采样 + LANCZOS resize 是抗锯齿关键，直接画目标尺寸会有锯齿。**- 验证：`flutter analyze` No issues + `flutter test` 340 passed (3 skipped) + GitHub Actions release.yml 构建通过。

**识别智能化批次 1-3 修复清单**（本次 commit，用户选择"全部融入"）：
- 批次 1 图片预检 + 字段校验：
  - 新建 `lib/core/util/recognition_validator.dart`——字段合理性校验（dishName/confidence/weight/区间）+ 营养素自洽校验（4p+9f+4c≈cal，±10%）
  - recognize_controller 集成校验：字段不合理→重试 1 次；营养素不自洽→自动用宏量营养素反推修正 calories
  - 修复 image_quality_checker.dart 类型错误（laplacianValues num→double）
  - 20 个校验器单元测试全过
- 批次 2 prompt v1.6 + 包装容量优先：
  - prompt v1.6：包装食品必须读取包装标签净含量（weight_source=package_label），不靠视觉估算
  - 营养素自洽约束：要求 AI 用 4p+9f+4c 反算 calories，偏差<5%
  - VisionRecognitionResult 新增 weightSource 字段 + fromJson 解析（向后兼容旧 prompt）
  - 示例 1-3 加 weight_source 字段 + 自洽性标注
- 批次 3 反馈闭环回流 aliasesJson：
  - FoodItemRepository 新增 addAlias 方法（事务包裹 + 归一化去重）
  - today_meals_page._showFeedbackDialog 加别名回流：用户纠正菜名后，把 AI 错误名作为正确菜的别名
  - 下次 AI 识别返回错误名时，findByNameOrAlias 命中别名，直接返回正确菜营养数据
  - 6 个 addAlias 单元测试全过

**验证**：flutter analyze No issues + flutter test 324 passed/3 skipped/0 failed

**食物热量计算优化第一波修复清单**（commit 47fd22c，等用户验收后发布 release）：
- 建议 1 ediblePercent 可食部分系数：
  - `nutrition_lookup.lookupSingleItem` 库命中分支 + `recognize_page._nutritionFromFoodItem` 反算点都加 `edibleFactor = (food.ediblePercent ?? 100).clamp(1,100) / 100`
  - `effectiveG = servingG * edibleFactor`，反算用真实可食克数（如香蕉 65%、带骨排骨 50%）
  - 复合菜 `lookupCompositeDish` 不乘（组分已是可食克数）
  - 6 个专项测试（香蕉/排骨/null/100%/0% clamp/复合菜不乘）全过
- 建议 7 复合菜组分份量交叉验证：
  - `RecognitionValidationResult` 新增 `correctedComponents` 字段
  - `sum(components.estimatedG)` 与 `estimatedWeightGMid` 偏差>15% 时按 mid 比例缩放
  - `recognize_controller._validateAndMaybeRetry` 主菜 + 附加菜两条路径都覆盖（在校验后、查库前）
  - 防除零（sumG=0/mid=0 不触发）+ 缩放后保留组分名
  - 8 个专项测试全过
- 建议 3 食物密度表 ml→g 换算：
  - 新建 `lib/ai/food_density.dart`——14 个类别密度表（油 0.92/蜂蜜 1.42/烈酒 0.79 等）+ `densityOf`/`isLiquidCategory` 辅助函数
  - prompt v1.7 新增 `food_category` 字段（water/carbonated/juice/milk/cream/oil/honey/sauce/alcohol/beer/wine/yogurt/soup/solid）
  - `VisionRecognitionResult` 新增 `foodCategory` 字段 + `copyWith` 扩展 + fromJson 解析（向后兼容默认 solid）
  - `recognize_controller._applyDensityConversion + _convertDensityForDish` 在校验前换算：仅对 `weight_source=package_label` + 液体类别换算，密度=1.0（水基）跳过
  - 换算公式：`realPerUnitG = perUnitG * density`，`realMid = realPerUnitG * quantity`，区间 ±3%
  - 20 个专项测试全过

**第二波修复清单**（commit 62dd475，三路径一致性 + 重试 bug 修复）：
- 提取 `lib/core/util/recognition_post_processor.dart`：
  - `process()` 完整链路：密度换算 → 字段校验 → 营养素自洽修正 → 组分份量交叉验证 → additionalDishes 修正
  - `applyDensityConversion` / `correctAdditionalDishes` 可单独调用
  - 纯静态方法，不持有状态，不依赖 provider/imageBase64
- 修复问题1（第一波盲区）：offline_queue_controller 后台回补完全没走校验链路
  - 包装液体未做 ml→g 密度换算（500ml 油 mid=500 而非 460）
  - 营养素不自洽未修正、组分份量不自洽未缩放
  - 导致前后台行为分叉：同张图不同网络条件下热量不一致
  - 修复：recognize 成功后调 `RecognitionPostProcessor.process(result)`
- 修复问题2（重试跳过换算 bug）：recognize_controller._validateAndMaybeRetry
  - 原代码重试成功后用未换算的 retryResult（油 500ml 重试后 mid 仍是 500 而非 460）
  - 修复：首次 + 重试结果都走 `RecognitionPostProcessor.process`
- controller 净减 98 行（4 个方法移到 PostProcessor，import + 简化调用）
- 17 个 PostProcessor 单元测试 + 1 个离线回补密度换算专项测试，全过
- 更新 1 个原有离线测试期望值（组分份量缩放后 actualServingG 180→250，新行为正确）

**主页刷新修复清单**（commit b167574，profile/weight 保存后通知 dashboard）：
- 问题：用户在 profile_page 录入体重身高年龄（重算 BMR/TDEE/目标）或在 weight_page 记录体重后，主页每日目标/宏量目标不更新
- 根因1：profile_page._save() pop 后没调 RefreshBus.notify()（dashboard 唯一刷新入口是 RefreshBus 监听）
- 根因2：weight_page._save() 只调本页 _load()，没调 RefreshBus.notify()
- 根因3：weight_page 只写 weight_logs 表，不同步 profile.weightKg（即使刷新，宏量目标 proteinGPerKg*weightKg 仍用旧体重）
- 修复：profile_page pop 后 + weight_page _save 末尾都加 RefreshBus.instance.notify()；weight_page insert 后同步 ProfileRepository.update(weightKg: weight)
- 设计决策：weight_page 不同步重算 dailyCalorieTarget（BMR 重算只在用户主动编辑档案时做，日常体重波动通过 TDEE 校准 adjustmentKcal 微调）
- 4 个 widget 测试全过（ProfilePage/WeightPage notify + weightKg 同步 + weight_logs 不影响）

---

## 3. 关键架构决策（不要轻易改）

### 3.1 AI 估热 + 本地库校验两层架构
- 库命中 → 用库值（NutritionSource.database）
- 库未命中 + AI 有 estimatedCalories → AI 兜底（foodItemId=0 哨兵，source=aiEstimate）
- 库未命中 + AI 无估算 → 走未命中弹窗转手动录入
- 复合菜组分全 miss → 转 AI 兜底走单品路径（v0.10.0 新增）

### 3.2 foodItemId=0 哨兵机制
- AI 兜底 NutritionResult.foodItemId=0（recognize_controller._aiFallbackNutrition）
- 写 meal_log 前必须调 upsertAiRecognized 创建真实 food_item 替换哨兵
- 三条路径已全部覆盖：recognize_page 单品、multi_dish_page 主菜+附加菜、offline_queue_controller

### 3.3 复合菜存储
- per100g=0 占位（实际热量在 meal_log.componentsSnapshotJson）
- nutrition_lookup.lookupSingleItem 过滤 componentsJson!=null 的记录（防 0 卡污染）
- listAllForRecommendation 排除 source='ai_recognized'

### 3.4 prompt 版本 v1.7
- v1.4：合并 v1.3（多菜多份 quantity/unit/perUnitG）+ v1.1（营养字段 estimated_calories 等）
- v1.6：包装容量优先（weight_source=package_label）+ 营养素自洽约束（4p+9f+4c≈cal，±5%）
- v1.7：新增 food_category 字段（water/carbonated/juice/milk/cream/oil/honey/sauce/alcohol/beer/wine/yogurt/soup/solid），用于包装液体 ml→g 密度换算
- 旧 prompt 响应无 food_category/weight_source 时默认 solid/ai_estimate（不换算、走视觉估算），向后兼容

### 3.5 per100g 反算 + 可食部分 + 密度换算三件套
- per100g 反算公式：`caloriesPer100g * effectiveG / 100`
- `effectiveG = servingG * edibleFactor`（建议 1）：edibleFactor 来自 FCT 数据 `ediblePercent` 字段（如香蕉 65%、带骨排骨 50%）
- 复合菜组分克数已是可食克数，不乘 edibleFactor
- 包装液体密度换算（建议 3）：`effectiveG = perUnitG * density * quantity`，仅 weight_source=package_label + 液体类别触发
- 三件套叠加顺序：识别 → **RecognitionPostProcessor.process**（密度换算→字段校验→营养素自洽→组分交叉验证→additionalDishes 修正）→ 查库反算（×edibleFactor）
- 第二波关键：三条路径（前台识别/重试/离线回补）都走 PostProcessor.process，行为一致

### 3.6 主题色
- themeSeedProvider（NotifierProvider<int>）+ secure_config_store 持久化
- 默认莫奈《睡莲》青绿 0xFF5B8C7B，12 色预设 kThemePresets
- main.dart runApp 前快速读，首帧即用正确主题色避免闪烁

### 3.7 启动流程（main.dart）
- runZonedGuarded 包整个 main
- 单一 ProviderContainer（UI 与初始化共用，不 dispose）
- themeSeed 快速读 → initSentryAndRunApp（appConfig 失败降级跳过 Sentry）→ runApp
- UI 起来后异步：appConfig / Workmanager / OfflineQueue（fire-and-forget）/ ImageCleanup（读用户保留期）

### 3.8 特殊人群营养适配（schema v2）
- profile 表加 3 个 nullable 列：specialCondition（生理状态）/dietPreference（饮食偏好）/healthCondition（健康状况）
- schema v1→v2 migration：`onUpgrade` 中 `m.addColumn` 加列，旧数据保持 null 视为 'none'（向后兼容）
- NutritionCalculator 调整权威来源：IOM 2006（孕期 +340 / 哺乳期 +500 kcal）、ISSN 老年蛋白 1.2g/kg、KDOQI 肾病蛋白 cap 0.8g/kg、ADA 糖尿病碳水 cap 45%
- 特殊人群调整在 goal 默认值之上覆盖：elderly 提蛋白（cut 不降）、kidney_issues 强制 cap、pregnancy/lactation 蛋白至少 1.1g/kg
- 能量加成在 deficit/surplus 之前加（避免减脂目标抵消孕期加成）
- JsonImporter 版本兼容：只拒绝高于当前的版本，允许旧备份导入（旧 JSON 缺新字段用 `as String?` 兜底 null）

### 3.9 食物查库匹配 5 级优先级 + 精确/模糊分离
- findByNameOrAlias（5 级模糊，识别主流程用）：①name 精确 → ②alias 精确 → ③name 双向 contains（长度约束）→ ④alias 双向 contains → ⑤name 编辑距离 ≤1（加严：query≥3 字且 target 等长，2 字短名禁用防雪花/雪碧假阳性）
- findExactByNameOrAlias（仅精确，反馈回流用）：只走 ①②，绝不模糊——避免模糊命中错对象导致 addAlias 反向错配永久污染别名表
- _normalize：全角→半角（数字/字母/空格/括号）+ 去空白 + 小写，避免全角字符精确 miss 降级模糊
- 反馈回流方向：AI 错误名 → 正确菜的别名（addAlias(correctFood.id, aiName)），查正确菜必须精确匹配
- addAlias 冲突检测：写入前遍历全表，若别名已是其他食物 name/alias 则拒绝（第二道防线）

### 3.11 推荐算法 v3 五维评分（参考业界 + 项目实际筛选）
- 调研：MyFitnessPal（大数据库+宏量分析）、Yazio（清洁 UX+断食）、薄荷（中式本土化+替代建议）、Lifesum（综合代谢画像）、Carbon Diet Coach（动态宏量调整）
- 弃用：协同过滤（单机无用户群）、AI 生成食谱（离线 app）、替换建议（需替代图谱留后续）
- 五维：①相对缺口匹配（Content-Based）②冷门降权+基础食材白名单（频次*4/基础*3/冷门*1.5）③profile 约束过滤（素食/乳糖/麸质硬排除，糖尿病/肾病软降权）④时段感知（数据驱动学 mealType 分布，非硬编码）⑤多样性（排除今日+昨日降权）
- 新增 MealLogRepository.getMealTypeDistribution(days:60) 学习食物历史 mealType 分布，样本<2 丢弃
- dashboard 按当前小时推断 mealType：5-10 breakfast / 11-13 lunch / 17-21 dinner / 其他 snack

### 3.12 MD3 全面优化（4 批清单 + 开源参考，commit `a8aa1f5`）
- 调研：MD3 v6.1 规范（圆角 4/8/12/16/28；Type Scale 15 档；Chip outlineVariant；Card filled/elevated/outlined 三变体；ColorScheme tertiary/secondary/primary 角色跨页配色）+ 开源饮食 app（FoodYou/NutriScan 的 Material You + Macro Rings）
- 第一批协调性：insight SegmentedButton pin AppBar.bottom（与 records_tab 统一）；weight 折线图按 insight 范式重写（左下边框+虚线网格+渐变填充+tooltip+统一 barWidth2.5+图例）；宏量跨页用 MacroColors 统一（替代 dashboard onPrimaryContainer alpha + today_meals 硬编码 0xFF4CAF50）；today_meals Card.outlined+12dp+padding16；today_meals section header 用 SectionTitle(trailing:)；me/settings Divider 用 cs.outlineVariant
- 第二批 MD3 合规：today_meals 编辑对话框"保存" FilledButton（原 TextButton 违反 MD3 主操作规范）；profile 特殊状况提示 Card(tertiaryContainer)（替代手写 Container）；profile/settings emoji 警告改 Icon(warning_amber_rounded, cs.error)（emoji 跨平台渲染不一致且不跟随主题）；settings 选中态 check 色按色块亮度动态选黑/白（WCAG AA）；recognize 遮罩 cs.scrim + 次要按钮 OutlinedButton 主次层级；food_library 列表补 chevron + 空态套 Card；me 错误态 Icon 补 cs.error；today_meals 反馈 IconButton 恢复 48dp 触摸目标
- 第三批字体层级：SectionTitle 用 titleSmall（原 labelLarge 语义偏标签）；批量硬编码 fontSize 转 textTheme（dashboard displaySmall/bodySmall/labelSmall/titleMedium/bodyMedium、today_meals labelSmall、me titleMedium/bodySmall、insight bodyMedium height:1.6）
- 权衡：records_tab/insight 用普通 AppBar+bottom 而非 SliverAppBar（IndexedStack/ListView 子页有自己滚动，SliverAppBar 需 CustomScrollView 重构成本大，bottom pinned 已满足"切换器常驻"需求）
- 验证：flutter analyze lib/ No issues + flutter test 337 passed (3 skipped)

### 3.13 深度审查修复 15 项（已随 v0.12.0 发布）
- 审查方法：4 路并行 search agent 分领域逐文件核对（features / ai+nutrition+data / core+main / test）
- 严重问题修复（S1-S6）：
  - S1 `TdeeCalibrator.runAndApply` 符号转换——calibrate 算法期望"减脂负/增肌正"但 profile.goalRateKgPerWeek 存正值，runAndApply 加 `signedGoalRate = goal=='cut' ? -rate : goal=='bulk' ? rate : 0` 转换
  - S2 `FoodItemRepository.insertManual` aliases 冲突检测——复用 addAlias 全表遍历逻辑，剔除已是其他食物 name/alias 的别名（防手动录入 AI 错误名绑多食物永久错配）
  - S3+S5 `RecognitionValidator` 营养素自洽加 `expected>0` 守卫——酒精饮料（7kcal/g 不在 Atwater 4p+9f+4c）/纤维/糖醇等非 Atwater 来源热量不能强制清零
  - S4 `JsonImporter` DELETE 序列加 pending_recognitions——`pending_recognitions.result_food_item_id` 是 FK NO ACTION，必须在 DELETE food_items 之前清
  - S4+ `JsonImporter` `as int` 强转改 `_asInt`/`_asIntOrNull` 兜底——旧版备份缺字段 `null as int` 抛 TypeError
  - S6 `SentryFlutter.init` 包 try-catch 降级——失败时返回原 app（不包 SentryWidget）保证 runApp 能执行
- 中等问题修复（M1-M10 + core L2/L3）：
  - `NutritionCalculator` gender=null 默认 1500 硬下限（避免女性拿到 <1200 危险低目标）
  - `PendingRecognitionRepository.markFailed` 包 `_db.transaction`（防"立即重试"与 workmanager 并发计数丢失）
  - `backup_page` 遮罩 `Colors.black54` → `cs.scrim.withValues(alpha:0.54)`
  - `sentry_scrub` hex 正则 `[a-f0-9]` → `[a-fA-F0-9]`（大写 hex 也脱敏）
  - `RecognitionValidator` confidence/estimatedWeightGMid 加 isNaN 显式判断（NaN 绕过 <0/>1 校验）
  - me_page/settings_page 版本号 0.10.0 → 0.11.1
- 测试修复（test S1/S3/S4）：
  - `recommendation_service_test` 4 处 `if (idx>=0)` 守卫加 `expect(idx, greaterThanOrEqualTo(0))` 前置断言（防假绿）
  - `json_export_import_test` seedData 加 schema v2 三字段断言（防导出导入漏字段）
  - `meal_log_repository_test` 新增 foodItemId=0/-1 哨兵防御测试（防外键约束违规崩溃）
- 暂不修复（需设计调整）：
  - NutritionLookup 3x OFF 云查（需重构查库逻辑）
  - RecognitionPostProcessor correctAdditionalDishes needsRetry 丢弃（需改 process 返回结构）
  - RecognitionPostProcessor macros 不修正（需扩展 copyWith）
  - image_quality_checker 未用 isolate（需顶层函数重构）
  - main.dart zone guard 不 runApp（需确认兜底策略）
- 验证：flutter analyze lib/ test/ No issues + flutter test 340 passed (3 skipped)

### 3.14 启动器图标精致化（commit `c37912b`，已随 v0.12.0 发布）
- 规范：Android Adaptive Icon（API 26+）—— 108dp 画布 + 66dp 安全区居中 + 前景/背景/monochrome 三层；OEM 蒙版自动裁剪为圆/方/圆角方，前景必须避开边缘
- 品牌语义：碗=食物，蒸汽=袅袅升起的温热感=「慢慢吃」，与 App 名呼应
- 配色：背景莫奈青绿渐变（与主题 seedColor `#5B8C7B` 一致），前景奶白 `#FDFBF7`（与 splash `#FCF9F9` 协调，温暖感优于纯白）
- 精致化五点：①背景对角线三色渐变（立体感）②碗口 evenOdd 环形双线（厚度感）③碗底小椭圆底座（稳重感）④蒸汽 stroke 2.8 + 错落（柔和）⑤奶白前景
- 实现：vector drawable（API 26+ 现代设备）+ Pillow 4x 超采样生成 5 密度 PNG fallback（API 21-25 旧设备，48/72/96/144/192）
- monochrome 复用前景供 Android 13+ 主题图标（用户可让图标跟随壁纸取色）

### 3.15 食物识别增强四层自我进化架构（P0/P1/P2，已随 v0.13.0 发布）

解决"雪花啤酒识别成雪碧 + 奶茶/网红零食能否准确分辨 + 热量能否严谨计算"三问。

核心思路：不追求本地库覆盖所有食物（不可能也无需），建立四层闭环：
1. **AI 估算（品类校准兜底）**——离谱估算用 13 品类默认值拦截
2. **品牌库（头部覆盖）**——10 品牌 41 招牌产品官方热量精确
3. **OFF（包装食品）**——百万级云查补漏 + brand 组合查询
4. **用户纠错（长尾自进化）**——反馈回流精确 miss 时创建新条目

**P0 品类校准 + brand 持久化**：
- 新建 `lib/data/seed/food_category_defaults.dart`——13 品类 per100g 默认值（beer=43/wine=83/alcohol=298/carbonated=43/juice=46/milk=61/yogurt=72/cream=345/oil=889/honey=321/sauce=63/soup=30/water=0），solid 不提供（差异太大）；`calibrate` 方法按 2 倍阈值校准（AI 估算偏离默认值 2 倍以上用默认值替代，否则保留 AI 估算）
- `food_item_repository.upsertAiRecognized` 加 `brand` 参数——把"品牌+菜名"（如"雪花啤酒"）存为 alias，下次 AI 返回完整品牌名精确命中；冲突检测复用 addAlias 全表遍历逻辑（防 brand+name 已是其他食物 name/alias）；新增 `_mergeAliasSafely` 异步方法做更新路径的冲突检测（事务内 select 全表）
- recognize_page / multi_dish_page / offline_queue_controller **三路径同步品类校准 + brand 传递**（违反硬约束 3 会导致后台回补路径热量偏差）

**P1 品牌官方热量库**：
- 新建 `assets/chain_drink_menu.json`——10 品牌 41 招牌产品（喜茶/霸王茶姬/奈雪/瑞幸/星巴克/蜜雪冰城/古茗/茶百道/一点点/Manner），数据来自各品牌小程序官方公示
- `FoodSeedImporter.importChainDrinksFirstTime`——name 存"品牌+品名"（如"喜茶多肉葡萄"），aliases 含品名简写；per100g 反算 `calories/(size_ml/100)`，defaultServingG=size_ml（现制茶饮密度≈水）；database wasCreated 调用
- `findByNameOrAlias` 加 `brand` 参数——优先级 0 按 brand+name 精确查（高于 name 精确），避免通用"奶茶"条目抢先命中"喜茶奶茶"；brand 为空时行为不变（向后兼容）
- `nutrition_lookup.lookupSingleItem` 加 `brand` 参数透传查库和 OFF
- `recognize_controller` 主菜和附加菜查库传 brand（L302/L330）

**P2 OFF brand 组合查询 + 反馈回流创建新条目**：
- `OffProvider.lookup` 加 `brand` 参数——先查"brand+name"（如"雪花 啤酒"），未命中回退查 name；提升品牌包装食品命中率
- `today_meals_page` 反馈回流——`findExactByNameOrAlias` 精确 miss 时（库里无此菜）调 `insertManual` 创建新条目（source='manual'，aliases=AI 错误名），实现长尾自进化；营养用 meal_log 实际值反算 per100g，仅在 `servingG>0 && actualCalories>0` 时创建（防 0 卡污染库）

**prompt v1.8（v1.7 → v1.8）**：
- 补充啤酒/茶饮剥离示例——示例 5 雪花啤酒（dish_name=啤酒/brand=雪花，强调瓶身文字"雪花"不是"雪碧"）、示例 6 喜茶多肉葡萄（dish_name=多肉葡萄/brand=喜茶）
- 规则 1 补充啤酒/葡萄酒/白酒剥离说明 + 现制茶饮/咖啡剥离说明
- 强调连锁品牌 brand 必填（后端按 brand+name 查品牌库）

**测试**：新增 18 个测试（品类校准 11 + brand 匹配 3 + brand 持久化 4），全量 358 passed (3 skipped)。FakeOffProvider.lookup 和 _FakeNutritionLookup.lookupSingleItem 签名同步加 `{String brand = ''}` 防止 invalid_override

### 3.16 全 editable 架构（4 批渐进，第一批已随 v0.13.0 发布）

解决用户反馈"所有功能都希望自己改，比如体重输错了点了确认后还能改"。审计现状：weight_logs 无 update/delete（ListTile 无交互）、meal_logs updateMealLog 只接受 5 营养字段（无 date/mealType/foodItemId）、food_items 无 delete/无 name 编辑、pending_recognitions 无 UI 页、recognition_feedbacks 无 list/delete、insight_summaries 无历史访问。4 批渐进实施。

**第一批（P0：体重 + 餐次全 editable，已随 v0.13.0 发布）**：
- `WeightLogRepository` 加 `getById(id)` / `update(id, weightKg?, date?)` / `delete(id)` —— 部分更新模式（null 跳过用 `Value.absent()`，非 null 用 `Value(x)`）
- `weight_page` ListTile → Dismissible（confirmDismiss 二次确认 dialog 比 Undo SnackBar 更适合低频数据）+ onTap 编辑 dialog（StatefulBuilder 局部刷新避免重建整个页面）
- **编辑最新一条体重必须同步 ProfileRepository.update(weightKg:)**（与 _save 一致逻辑，否则 dashboard 宏量目标 proteinGPerKg*weightKg 仍用旧体重）；判断"最新"用 `_logs.isEmpty || log.id == _logs.last.id`（_logs 已按日期升序）
- `MealLogRepository.updateMealLog` 从 5 必填扩展为 8 可选（加 date/mealType/foodItemId），向后兼容现有 5 处调用（required double → double? 不破坏调用方）
- **新增独立 MealEditDialog**（ConsumerStatefulWidget，不内嵌 AlertDialog）—— 复杂表单状态隔离；5 个 TextEditingController（份量 + 4 营养）+ 4 个独立状态（_mealType/_selectedDate/_newFoodItemId/_nutritionOverridden）
- **营养重算优先级**：advanced 手动覆盖 > 换食物重算 > 份量比例。`_nutritionOverridden` 标志由 4 个营养 TextField 的 listener `_markOverride` 设置；`_setCtrlSilently` 在程序化设值前移除 listener，避免触发 override 误判
- **换食物**：push `FoodLibraryPage(pickForReuse:true)` 接收 FoodItem，用新食物 per100g × 当前份量重算营养（与 NutritionLookup.lookupSingleItem 反算公式一致：caloriesPer100g * servingG / 100）
- **哨兵防御扩展**：`updateMealLog` 加 `foodItemId != null && foodItemId <= 0` ArgumentError（与 insertMealLog 一致，防 UI 把 0 哨兵写入非空 FK 字段致 PRAGMA foreign_keys=ON 崩溃）

**第二批（待实施）：FoodItems 删除/归档 + name/aliases 编辑**
- 现状：FoodItemRepository 无 delete 方法，food_edit_page 只能改营养不能改名
- 计划：加 delete（带 meal_log 引用检查，有引用则归档 source='archived' 而非物理删除）+ updateName + updateAliases

**第三批（待实施）：PendingRecognitions UI 页 + 重试/删除 + Feedbacks 历史/删除**
- 现状：pending_recognitions 无 UI 页（只能 workmanager 后台重试），recognition_feedbacks 无 list/delete
- 计划：me_page 加"离线队列"入口显示 pending 列表（手动重试/删除单条），加"反馈历史"列表（按时间倒序，可删除）

**第四批（待实施）：历史 InsightSummaries 查看页 + 份量校准回滚**
- 现状：insight_summaries 只显示当前周期，历史 insight 无访问入口；meal_log 份量校准后无法回滚到 AI 原始估算
- 计划：insight_page 加历史周期 SegmentedButton（weekly/monthly 切换 + 滚动历史），meal_log 加 estimatedServingGAiOriginal 字段记录 AI 原始值供回滚

### 3.17 UI/UX 审查修复 Phase 3（A+B+C+D 四批，已随 v0.13.0 发布）
4 路并行 search agent 全面审查所有界面，识别 14 S + 30+ M + 10 L 级问题，分 6 批（A-F）渐进修复。本次完成 A+B+C+D 四批共 26 项（E 评估后跳过、F 待用户确认）。

**公共抽象层模式**：把跨页重复的 UI 模式/工具函数提取到共享文件（m3_widgets.dart / core/util/），防止各页实现漂移。

**B 批（公共抽象层第一轮）**：新增 4 个共享组件（EmptyState / GroupCard / MealTypeSelector / confirmDiscardChanges）+ 2 个工具（date_format / food_name）
- **B6 主题单一源**：app.dart 的 `inputDecorationTheme` 是全局 OutlineInputBorder 定义，各页 TextField 不再重复声明 `border: OutlineInputBorder()`，改主题色只需改 app.dart 一处

**A 批（数据安全）**：
- **A1 乐观删除 + Undo**：Dismissible 先从 UI 移除 + 4s 撤销 SnackBar，未撤销才实际 DB delete。比"立即删 + SnackBar 提示"更宽容误操作。删除失败回滚 `_load()`
- **A3 PopScope + _dirty 追踪**：编辑页加 `_dirty` 标志 + `_markDirty()` + controller listeners；`PopScope(canPop: !_dirty)` 拦截返回 + `confirmDiscardChanges` 共享 dialog。`_markDirty` 必须加 `_loading` 守卫——初始 `_loadXxx()` 异步赋值 controller.text 会触发 listener，若不守卫会误标 dirty 致首屏就拦截返回
- **A4 错误态可重试性判断**：recognize_page 错误态 SnackBar 加"重试"按钮，按错误消息内容判断可重试性。「操作太快」/「已转手动录入」/「安全过滤」三类不显示重试（重试无意义或已跳转），其余错误可重试。用 `msg.contains(...)` 字符串匹配判断，因 controller 的错误文案是固定字符串
- **权衡**：A4 用字符串匹配判断错误类型而非枚举，因 controller 已有的错误文案是固定中文字符串，改枚举需动 controller 状态结构，本次最小改动只动 recognize_page。后续若错误类型增多可重构为枚举

**C 批（数据安全 + 一致性 S 级，commit `d46a1b9`）**：
- **C1 today_meals 乐观删除页面销毁后未删 DB 修复**：A1 引入的 bug——`onDismissed` 里 `setState` + `await SnackBar` 后才 DB delete，但 await 4s 期间页面可能已销毁（用户切 tab），`if (!mounted) return` 跳过 delete 致记录"复活"（UI 已删但 DB 还在，下次 _load 重新出现）。修复：在 await 前提前 `final mealRepo = await ref.read(...)` + `final id = m.id` 捕获引用，DB delete 不依赖 mounted，删除失败用捕获的 messenger 显示错误（不用 context）
- **C2 today_meals 加载失败显 ErrorState**：原 `_load()` catch 置空列表，build 中显示"今日暂无记录"误导用户以为今日真无数据。加 `_loadError` 标志区分"加载失败"与"空数据"，失败时显 `EmptyState(icon: error_outline, actionLabel: '重试')`
- **C3 insight 错误信息独立 `_error` 字段 + errorContainer Card**：原 controller 失败时把错误塞进 `_summary` 字段伪装 AI 输出（用户看到 "AI 汇总失败：xxx" 像 AI 响应）。改独立 `_error` 字段，build 中用 `Card(color: cs.errorContainer)` 醒目显示，与正常 AI 汇总分隔
- **C4 meal_edit_dialog ChoiceChip → MealTypeSelector**：B5 抽象出 MealTypeSelector 后，meal_edit_dialog 仍用内联 ChoiceChip 4 段（与 recognize/manual_entry 不一致）。改用 MealTypeSelector 统一三页餐次选择 UI
- **C5 multi_dish_page + manual_entry_page 补 PopScope 未保存确认**：A3 漏补两页——multi_dish 用户拖滑块改份量/数量后未确认直接返回会丢修改；manual_entry 5+ TextField 输入到一半返回同样丢。两页都加 `_dirty` 标志（滑块 onChanged / controller listener 触发）+ PopScope + confirmDiscardChanges
- **C6 emoji ⚠ → Icon(Icons.warning_amber_rounded)**：backup/calibration 的 emoji 警告跨平台渲染不一致（iOS/Android 字体不同）且不跟随主题色。改 Icon 用 cs.error 色，与 profile/settings 一致（已在 v0.12.0 a8aa1f5 完成 profile/settings 两页，C6 补完剩余 backup/calibration）
- **C7 FilledButton 内 CircularProgressIndicator 加 color**：8 处 FilledButton 内的 loading 圈用默认 primary 色，在 errorContainer/FilledButton 背景下对比度不足。加 `color: cs.onPrimary` 或 `cs.onPrimaryContainer` 保证可见
- **C8 app.dart 加 textButtonTheme + outlinedButtonTheme minimumSize 48dp**：MD3 默认 TextButton/OutlinedButton 高度 40dp 不满足 WCAG 2.5.5 触摸目标最小 44dp（推荐 48dp）。设 `minimumSize: Size(48,48)` 全局生效，避免各页再单独设

**D 批（公共抽象层第二轮 + 第三轮，commit `390d19a` + `4252093`）**：
- **D1 foodSourceLabel 集中**（commit `390d19a`）：food_edit_page + food_library_page 各有本地 `_sourceLabel(source)` switch 把 'manual'/'ai_recognized'/'brand_official' 等映射到中文标签。提到 `food_name.dart` 的 `foodSourceLabel(source)` 函数，新增 source 类型只改一处
- **D2 删 _sectionTitle 包装**（commit `390d19a`）：me_page（3 处）+ settings_page（7 处）有零价值间接层 `_sectionTitle(text) => SectionTitle(text)`，直接用 `SectionTitle(text)` 删除中间层。10 处调用替换 + 2 个私有方法删除
- **D3 EmptyChartHint 组件**（commit `390d19a`）：weight_page + insight_page 各有本地 `_emptyChartHint` 实现（Card + show_chart 图标 + 灰文提示"暂无数据"）。提到 `m3_widgets.dart` 的 `EmptyChartHint` 共享组件（120px 高 Card + show_chart 图标 + onSurfaceVariant 灰文），与全屏 `EmptyState` 区分（图表占位用 EmptyChartHint 120px，全屏空态用 EmptyState）
- **D4 WarningBanner 组件**（commit `390d19a`）：settings_page 2 处内联 `Padding+Row(Icon+Text)` 警告横幅实现重复。提到 `m3_widgets.dart` 的 `WarningBanner(text)` 共享组件（warning_amber_rounded 图标 + cs.error 色文 + 12px 字号），统一警示横幅样式
- **D5 confirmAction 共享确认对话框**（commit `4252093`）：m3_widgets.dart 新增 `confirmAction(context, title, content, {cancelLabel, confirmLabel, icon, destructive})`，统一 AlertDialog 取消/确认两按钮样板。支持 `destructive`（errorContainer 配色确认按钮，用于删除）+ `icon`（cs.error 色警示图标，用于风险警告/确认导入）。替换 4 处内联 `showDialog<bool>`：weight_page 删除体重确认（destructive）/ profile_page 风险警告确认（icon）/ insight_page 重新生成确认（简单）/ backup_page 确认导入（icon）。profile_page 原用 `Row(icon+title)` 非标准模式，改 MD3 `AlertDialog.icon` 参数更合规
- **D6 showAppToast 共享 toast 提示**（commit `4252093`）：m3_widgets.dart 新增 `showAppToast(context, msg, {duration})`，封装 `ScaffoldMessenger + SnackBar` 样板。替换 23 处简单 SnackBar（无 SnackBarAction 的成功/失败/提示消息），覆盖 8 文件：today_meals / meal_edit_dialog / weight / settings / profile / manual_entry / backup / multi_dish_page。backup_page 4 处带 5s duration（导入导出操作结果需更长阅读时间）。**recognize_page 4 处带 SnackBarAction 重试按钮的不替换**（重试按钮是功能性入口，showAppToast 不支持 SnackBarAction）

**E 批（评估后跳过）**：24 处硬编码 `fontSize:` 扫描。多数在图表上下文（insight/weight 的 fl_chart 坐标轴标签、tooltip）需精确字号控制，转 textTheme 无收益；4 处非图表（settings/profile/backup 脚注）转 textTheme 收益微小。整体评估为低价值，跳过

**验证**：
- C 批：flutter analyze No issues + flutter test 392 passed (3 skipped)
- D 批第二轮（D1-D4）：flutter analyze No issues + flutter test 392 passed (3 skipped)
- D 批第三轮（D5+D6）：flutter analyze No issues + flutter test 392 passed (3 skipped)

---

## 4. 已知陷阱（踩过的坑）

1. **APK 打不开**：build.gradle.kts 丢失 R8 禁用配置 → native 启动崩溃。必须保持 `isMinifyEnabled=false` + `isShrinkResources=false`
2. **SecureConfigStore.instance 不存在**：v0.8.0 用 `SecureConfigStore()` 构造函数，没有静态 instance。main.dart 用 `container.read(secureConfigStoreProvider)`
3. **initSentryAndRunApp 参数名**：是 `container:` + `app:`（命名参数），不是位置参数
4. **multi_dish_page take(5) 截断**：附加菜超 5 道静默丢弃，当前未提示用户（待优化）
5. **滑块 max 与 perUnitG*20 边界**：perUnitG 极大/极小时滑块与步进器可能不同步（待优化）
6. **测试 mock 需补 getThemeSeed stub**：AppConfig.load() 新增了 getThemeSeed() 调用，mock SecureConfigStore 的测试必须 stub
7. **复合菜组分克数已是可食克数，不能再乘 ediblePercent**：`lookupCompositeDish` 反算时不要加 edibleFactor（与单品 `lookupSingleItem` 不同），否则双重缩放
8. **密度换算只对 weight_source=package_label + 液体类别触发**：散装菜（ai_estimate）即使 foodCategory=milk 也不换算（视觉估算已是克数）；水基（密度=1.0）跳过避免无谓重建
9. **三路径必须走 RecognitionPostProcessor.process**：前台识别（recognize_controller）、重试结果、离线回补（offline_queue_controller）三条路径的 recognize 结果都必须经过 PostProcessor.process，否则行为分叉（第二波修复的关键约束）。重试结果若跳过 process 会导致密度换算被跳过（油 500ml 重试后 mid 仍是 500 而非 460）
10. **profile/weight 页保存后必须调 RefreshBus.notify()**：dashboard 唯一刷新入口是 RefreshBus 监听（main_shell FAB 也用此机制）。profile_page._save 和 weight_page._save 末尾都必须 notify，否则主页每日目标/宏量目标不更新。weight_page 还需同步 profile.weightKg（否则宏量目标 proteinGPerKg*weightKg 仍用旧体重）
11. **dashboard 用裸 FutureBuilder+setState，无响应式 provider**：当前 dashboard 不 watch 任何 profile provider，完全靠 RefreshBus 触发 _refresh() 重查库。若未来新增其他修改 profile 的入口，也必须调 RefreshBus.notify()
12. **JsonExporter/Importer 新增字段必须同步**：profile 表加列后，JsonExporter._profileToJson 要导出新字段，JsonImporter._profileFromJson 要读取新字段（用 `as String?` 兼容旧 JSON 无此字段）。否则备份恢复丢数据。本次 schema v2 漏导出 3 个特殊人群字段，已补修复
13. **DropdownMenu 测试用 find.byKey 定位**：不要用 `find.byType(DropdownMenu<String>).last` 或 `.first`，因为新增菜单会让索引漂移。本次 profile_page 新增 3 个 DropdownMenu 导致 .last 从 goal 漂移到饮食偏好菜单，测试失效。修复：给 goal 菜单加 `key: const Key('goal_dropdown')`，测试用 `find.byKey`
14. **JsonImporter 版本检查只拒绝高于当前**：`if (schemaVersion > _db.schemaVersion)` 而非严格相等，允许旧版本备份导入新版本 DB（向后兼容，老用户升级后可恢复旧备份）。旧 JSON 缺新字段由 _profileFromJson 用 `as String?` 兜底为 null
15. **findByNameOrAlias 优先级 5 编辑距离对 2 字短名禁用**：2 字短名编辑距离 1 无法区分"假阳性（雪花/雪碧）"与"typo（可东/可乐）"，禁用 2 字短名编辑距离（query.length>=3 且 target 与 query 等长才走）。typo 容错仅保留 3+ 字等长场景（蕃茄炒蛋→番茄炒蛋）
16. **反馈回流别名必须用 findExactByNameOrAlias 精确匹配查库**：today_meals_page 用户纠正菜名后调 addAlias 回流别名，查"正确菜"必须用精确匹配（name/alias 归一化相等），绝不能用 findByNameOrAlias 5 级模糊匹配。否则模糊命中错对象后把 AI 错误名写成错对象别名 → 永久错配且无法自愈（雪花啤酒模糊命中雪碧 → "雪碧"成雪碧别名 → 永久错配）
17. **SectionTitle padding 必须左右对称且与下方 Card 对齐**：`fromLTRB(16,20,16,8)`，左缘与 Card 的 EdgeInsets.all(16)/symmetric(horizontal:16) 对齐。曾用 `fromLTRB(24,20,16,8)` 左 24 右 16 不对称，被 6 页面 14 处复用导致"界面整体偏右"。改公共组件 padding 必须考虑所有复用页面
18. **addAlias 写入前必须做全表冲突检测**：写入别名前遍历全表，若别名已是其他食物的 name/alias 则拒绝写入（防反向错配第二道防线）。findExactByNameOrAlias 是第一道（调用方用精确匹配查"正确菜"），addAlias 冲突检测是第二道。两道防线缺一不可——单靠 findExact 仍可能因调用方传错 foodItemId 而写入冲突别名
19. **推荐算法 v3 冷门降权用动态蛋白权重**：常吃 *4 / 基础食材 *3 / 冷门 *1.5，三者区分决定排序。原 v2 全部 *4 致冷门高密度食物（蛋白粉等）盖过常吃基础食材（鸡蛋）。改权重必须同步 _scoreFood 里"非最缺宏量"分支的 0.4 系数（用 proteinWeight*0.4 保持比例）
20. **recommend() 新增维度参数必须可选且向后兼容**：profile/mealType/yesterdayDate 全可选，不传时退化到 v2 行为。现有 6 个 v2 测试不传新参数仍全过。新增维度测试在独立 group 里显式传参验证

21. **宏量营养素跨页配色必须用 MacroColors 共享类**：蛋白/脂肪/碳水三色在 `m3_widgets.MacroColors` 统一（蛋白=tertiary/脂肪=secondary/碳水=primary，跟随 seed 变化且色弱友好）。曾出现 dashboard 用 `onPrimaryContainer.alpha(0.x)`、today_meals 硬编码 `0xFF4CAF50` 致跨页颜色分裂。新增页面渲染三宏色必须用 `MacroColors.protein(cs)/fat(cs)/carb(cs)`，禁止再硬编码颜色值

22. **SectionTitle.trailing 是可选参数，向后兼容现有调用**：扩展 SectionTitle 加 `trailing?:Widget` 用于显示分组小计（如 today_meals 餐次标题 trailing 显示 "xxx kcal"）。现有 14 处 `SectionTitle(text)` 调用不传 trailing 不受影响。需要 trailing 的页面复用同一组件而非另起炉灶（曾因 today_meals 手写"色块+标题+sum"破坏统一）

23. **records_tab/insight 的 SegmentedButton 用 AppBar.bottom pinned 而非 SliverAppBar**：切换器需常驻顶部不随滚动消失。权衡：用普通 `AppBar(bottom: PreferredSize(...))` 而非 SliverAppBar，因 IndexedStack/ListView 子页有自己的滚动结构，SliverAppBar 需 CustomScrollView 重构成本大；AppBar.bottom pinned 已满足"切换器常驻"需求

24. **TdeeCalibrator calibrate 算法期望"减脂负/增肌正"符号**：但 `profile.goalRateKgPerWeek` 存正值（NutritionCalculator.dailyCalorieTarget 用 `>0` 判断 deficit/surplus）。`runAndApply` 必须按 goal 转换符号：cut 取负、bulk 取正、maintain 取 0，否则减脂用户校准方向恒错。改 calibrate 算法或改 profile 存储都会破坏多处依赖，符号转换在 runAndApply 边界处做最稳

25. **JsonImporter DELETE 序列必须先子表后父表**：`pending_recognitions.result_food_item_id` 是 FK NO ACTION，DELETE food_items 之前必须先清 pending_recognitions，否则 FK 阻塞致真机导入失败。当前序列：recognition_feedbacks → insight_summaries → weight_logs → pending_recognitions → meal_logs → food_items → profiles。新增带 FK 的表必须同步更新 DELETE 序列

26. **SentryFlutter.init 失败必须降级返回原 app**：初始化抛异常时 zone guard 只记日志不 runApp → 永久黑屏。`initSentryAndRunApp` 必须 try-catch 包 SentryFlutter.init，失败时返回原 app（不包 SentryWidget）保证调用方 runApp 能执行。Sentry 是可观测性工具，初始化失败不应阻塞 app 启动

27. **RecognitionValidator 营养素自洽校验只在 expected>0 时执行**：`expected = 4*protein + 9*fat + 4*carbs` 不含酒精（7kcal/g）、纤维、糖醇等非 Atwater 来源热量。若 expected==0 但 cal>0（如啤酒 cal=150 expected=48 实际 expected 来自 p/f/c 微量），强制清零会丢数据。校验器只在 `expected > 0` 时校验自洽性，expected==0 保留 AI 的 calories

28. **RecognitionValidator confidence/weight 必须显式判 NaN**：Dart 中 `NaN < 0 = false`、`NaN > 1 = false`、`NaN <= 0 = false`，AI 返回非数值字符串被 `double.tryParse` 解析为 NaN 时会绕过 `[0,1]` / `>0` 区间校验。校验器必须显式 `if (value.isNaN || value < 0 || value > 1)` 判断

29. **测试断言不能用 `if (idx >= 0)` 守卫包裹比较断言**：`indexWhere` 返回 -1 时 `if (idx >= 0)` 守卫让内部比较断言静默跳过 → 测试通过不代表功能正确（假绿）。应在比较前显式 `expect(idx, greaterThanOrEqualTo(0), reason: '...')` 前置断言确保元素在列表中，再执行比较。例外：被设计行为过滤的元素（如推荐算法超标场景 score<=0 的食物）保留 if 守卫，但其他元素必须强制断言

30. **insertManual aliases 参数必须做冲突检测**：addAlias 有全表冲突检测（陷阱 18）但 insertManual 的 aliases 参数路径曾漏掉。手动录入时若用户输入 AI 错误名作别名，可绑多食物致永久错配（与反馈回流 addAlias 同风险）。insertManual 必须复用 addAlias 全表遍历逻辑，剔除已是其他食物 name/alias 的别名

31. **JsonImporter 不要用 `as int` 强转可空字段**：旧版备份 JSON 缺字段时 `null as int` 抛 TypeError 致整个导入失败。所有非空 int 字段必须用 `_asInt(v) => (v as num).toInt()` 兜底（num 兼容 int/double），可空字段用 `_asIntOrNull(v) => v == null ? null : (v as num).toInt()`。导出 JSON 是跨版本兼容的关键入口，类型强转是常见崩溃源

32. **启动器图标改动必须同步 vector drawable + 5 密度 PNG fallback**：vector drawable（`mipmap-anydpi-v26/ic_launcher.xml` 引用 `drawable/ic_launcher_foreground.xml` + `ic_launcher_background.xml`）只对 API 26+ 生效；API 21-25 旧设备需 `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`（48/72/96/144/192）。只改 vector 不更新 PNG → 旧设备显示旧图标；只更新 PNG 不改 vector → 现代设备显示旧图标。两层必须同步。沙箱无 Android SDK/ImageMagick 时用 Pillow 4x 超采样 + LANCZOS resize 生成 PNG（抗锯齿）

33. **Android Adaptive Icon 前景必须在 66dp 安全区内**：108dp 画布，安全区中心 (54,54) 半径 33（即 21-87 范围）。OEM 蒙版（圆/方圆角）会裁掉安全区外内容。前景图形越界 → 部分 OEM 设备图标被裁残缺。改图标坐标后必须核对所有图形在 (21,21)-(87,87) 内

34. **Android vector 碗口环形用 evenOdd 而非纯色挖空**：背景是渐变色，碗口内椭圆若用纯色 `#5B8C7B` 挖空会与渐变背景色差。用 `android:fillType="evenOdd"` + 两个嵌套椭圆子路径（外椭圆 + 内椭圆），系统自动渲染环形（内椭圆区域不填充，露出背景渐变）。`fillType="evenOdd"` API 24+ 支持，自适应图标 API 26+ 兼容无问题

35. **品类校准阈值用 2 倍比例而非绝对偏差**：`FoodCategoryDefaults.calibrate` 按 `aiCal/defCal > 2.0 || < 0.5` 判断离谱，不用绝对偏差（如 `|aiCal-defCal|>50`）。原因：各品类默认值跨度大（water=0 vs oil=889），绝对偏差对低卡品类过严、高卡品类过松。2 倍阈值对啤酒（默认 43）容忍 AI 估 22-86，对油（默认 889）容忍 445-1778，比例统一合理。water 特殊：defCal=0 时 AI 任何正值都算偏离（ratio=999）→ 用 0 卡替代，避免把水估成有热量。仅校准 calories 偏离，蛋白/脂肪/碳水跟随品类默认值一并替换（差异大，AI 单项离谱也需拦截）

36. **upsertAiRecognized brand 别名冲突检测必须事务内做**：`_mergeAliasSafely` 在 `_db.transaction` 内调 `_db.foodItems.select().get()` 遍历全表，事务保证读到的快照一致。若在事务外做冲突检测再写库，期间其他事务可能写入同名 alias → 冲突检测失效。drift 事务对 SQLite 是 SERIALIZABLE（实际是 journal 锁），事务内 select-then-update 原子。`_mergeAliasSafely` 返回 `Future<List<String>?>`，调用方必须 `await`（曾因漏 await 致类型不匹配编译错误）

37. **品牌库 per100g 反算基于 size_ml 不是 calories 总值**：`importChainDrinksFirstTime` 用 `per100 = 100.0 / size_ml`（每毫升对应多少 100g 单位）反算 per100g，因为现制茶饮密度≈水（1ml≈1g），ml=g。若用 `calories / 总热量` 反算会循环引用。defaultServingG=size_ml（每杯总毫升数），用户调整份量时按 ml 缩放正确。改密度换算必须同步改反算公式（如咖啡密度 1.05 需 `size_ml*1.05` 转克）

38. **OFF brand 组合查询必须先 brand+name 再 name 回退**：`OffProvider.lookup` brand 非空时先查 `"$brand $dishName"`（如"雪花 啤酒"），OFF 有品牌产品名字段命中率高。若先查 name 再查 brand+name 会浪费一次 API 调用，且 name 单查可能命中通用"啤酒"而非"雪花啤酒"品牌产品。组合查询 miss 才回退 name 查询，最多 2 次 API 调用。`_searchOff` 是从原 `lookup` 内部逻辑提取的独立方法，避免组合/回退两路径代码重复

39. **反馈回流精确 miss 必须用 insertManual 创建新条目而非 addAlias**：`today_meals_page` 用户纠正菜名时，`findExactByNameOrAlias(correctedDishName)` 返回 null（库里无此菜）→ 必须调 `insertManual` 创建新条目（source='manual'，aliases=AI 错误名），不能调 `addAlias`（addAlias 需要 foodItemId，无条目可绑）。这是长尾自进化入口——用户每纠正一次新菜，库就多一条。仅在 `servingG>0 && actualCalories>0` 时创建（防 0 卡污染库）。反算 per100g = `100.0 / servingG`（用 `m.actualServingG` 用户校准后的真实克数，不是 defaultServingG）

40. **prompt v1.8 啤酒剥离示例必须强调瓶身文字**：雪花啤酒瓶身绿色与雪碧瓶身绿色视觉相似，AI 视觉模型仅看颜色易混淆。prompt 必须明确"读瓶身标签文字是'雪花'不是'雪碧'"，dish_name=啤酒/brand=雪花。仅靠品类校准（beer 默认 43）不够——若 AI 识别成雪碧（carbonated 默认 43，巧合热量相近），品类校准无法拦截，必须靠 prompt 引导 AI 读文字。同时 brand 字段必填连锁品牌（喜茶/瑞幸等），后端按 brand+name 查品牌库精确命中。prompt 改版本必须同步 bump `Prompts.version`（v1.7→v1.8），离线入队存 promptVersion 字段以便后续兼容

41. **Drift 部分更新必须用 Value.absent() 跳过 null 字段**：repo update 方法把可选参数转 `MealLogsCompanion` 时，`param == null ? const Value.absent() : Value(param)`。`Value.absent()` 表示"该字段不参与 UPDATE"，`Value(null)` 表示"该字段置 NULL"，`Value(x)` 表示"该字段置 x"。三者语义完全不同。若把 null 字段写成 `Value(null)` 会把数据库已有值清空（破坏数据）；写成 `Value.absent()` 才是"保持原值"。WeightLogRepository.update 和 MealLogRepository.updateMealLog 都遵循此模式。新增可选字段更新方法必须照此实现

42. **编辑最新一条体重必须同步 profile.weightKg**：weight_page 编辑/删除体重记录时，若操作的是 `_logs.last`（最新一条，_logs 已按日期升序），必须同步调 `ProfileRepository.update(weightKg: newValue)`。原因：dashboard 宏量目标 `proteinGPerKg * weightKg` 用 profile.weightKg 而非 weight_logs 最新值。若只改 weight_logs 不改 profile，dashboard 显示的目标仍是旧体重算的。判断"最新"用 `log.id == _logs.last.id`（按 id 不可靠，必须用已排序的 _logs 末位）。删除最新一条时，profile.weightKg 应同步为新的最新一条（_logs 倒数第二条）或保留——当前实现仅编辑时同步，删除时不同步（避免删完所有记录后 profile 体重被清空）

43. **复杂表单 dialog 必须提取为独立 StatefulWidget 而非内嵌 AlertDialog**：餐次编辑涉及 5 TextEditingController + 4 独立状态（_mealType/_selectedDate/_newFoodItemId/_nutritionOverridden）+ 换食物导航 + 日期选择 + 高级覆盖监听。若用 AlertDialog + StatefulBuilder 内联实现，状态管理混乱且无法用 ConsumerStatefulWidget 的 ref。提取为 `MealEditDialog extends ConsumerStatefulWidget` 后：①状态隔离在 dialog 内不污染父页 ②可用 ref.read(recognize.databaseProvider) 获取 DB ③controller 在 dispose 统一释放防泄漏 ④返回值类型化（MealEditResult）比 Map<String,dynamic> 安全。今后涉及 3+ 字段编辑的 dialog 都应提取为独立 widget

44. **TextField 程序化设值前必须移除 listener 避免误触发 override 标记**：MealEditDialog 的 4 个营养 TextField 加了 `_markOverride` listener（用户手动改值时标记 `_nutritionOverridden=true`，让 advanced 覆盖优先级最高）。但程序化设值（如换食物后重算营养、展开 advanced 时回填当前值）也会触发 listener → 误标记 override → 份量/换食物重算被跳过。`_setCtrlSilently` 方法在 setText 前 `removeListener`，setText 后 `addListener`，保证只有用户真实输入才标记 override。controller 的 listener 必须区分"用户输入"与"程序设值"两种触发源

45. **PopScope 编辑页 `_markDirty` 必须加 `_loading` 守卫**：编辑页（profile/settings/food_edit 等）在 initState 注册 controller listener 后才异步 `_loadXxx()` 给 controller.text 赋值。赋值会触发 listener → 若 `_markDirty` 无守卫会误标 `_dirty=true` → 首屏就拦截返回键弹"放弃修改"对话框（用户没改任何东西）。守卫模式：`void _markDirty() { if (_loading || _dirty) return; setState(() => _dirty = true); }`，`_loadXxx` 的 finally 块置 `_loading=false`。calibration_page 用滑块 onChanged 触发 dirty 不需守卫（无异步赋值），但 controller-based 的页面必须守卫

46. **GroupCard 分隔线策略：dividerIndent 非null 自动插 / null 手动插**：`GroupCard(dividerIndent: 16, children: [...])` 在子项间自动插 Divider（适合纯 ListTile/TextField 均匀列表）；`GroupCard(children: [...])` 不自动插（适合混合 ListTile + 警告 Padding 等非均匀内容，调用方用 `GroupCard.divider(context)` 手动在指定位置插）。曾因 me_page 的"使用情况"段含 cost 警告 Padding，用自动插会在 Padding 上下出现多余分隔线，改手动插解决。新增 GroupCard 调用需根据子项类型选策略

47. **app.dart inputDecorationTheme 是 OutlineInputBorder 全局单一源**：app.dart L68-71 的 `inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder())` 全局生效，各页 TextField 不再需要重复声明 `border: OutlineInputBorder()`。本次清除 6 文件 11 处冗余声明。改主题色/圆角只需改 app.dart 一处。新增 TextField 默认就用 OutlineInputBorder，无需显式声明 border（除非要 InputBorder.none 做内嵌 ListTile 样式）

48. **Undo SnackBar 乐观删除必须捕获 messenger 引用 + 用 undone 标志**：Dismissible 的 `onDismissed` 回调里 `setState(() => _meals.removeAt(index))` 后立即 `showSnackBar`，但 await 4s 后 widget 可能已 unmounted。必须 `final messenger = ScaffoldMessenger.of(context)` 在 await 前捕获引用（context 可能失效但 messenger 仍可用），用 `var undone = false` 标志在 SnackBarAction.onPressed 置 true，await 后检查 `if (undone) return` 跳过 DB delete。删除失败要 `await _load()` 回滚 UI + 错误提示。比"立即删"多一个 4s 窗口给用户反悔

49. **confirmAction/showAppToast 抽象：SnackBarAction 重试按钮与图表 fontSize 必须保持内联**：D5/D6 抽象出共享 `confirmAction`（确认对话框）+ `showAppToast`（toast）后，有两类场景必须保留内联实现不能用共享抽象——①**SnackBarAction 重试按钮**：recognize_page 4 处错误态 SnackBar 带"重试"按钮（SnackBarAction），是功能性入口（点击重新触发识别），showAppToast 不支持 SnackBarAction 参数，强行替换会丢重试功能。带 action 的 SnackBar 必须保留 `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:..., action: SnackBarAction(label:'重试', onPressed:...)))` 内联写法；②**图表 fontSize 精确控制**：fl_chart 坐标轴标签、tooltip 的硬编码 `fontSize: 10/11/12` 需精确像素控制（图表内文字与数据点对齐，textTheme 的相对单位会破坏对齐），不能转 textTheme。E 批评估跳过即因此。新增 toast 时先检查是否带 SnackBarAction，是则保留内联；新增图表文字样式时不要转 textTheme

---

## 5. 常用命令

```bash
# 环境（沙箱每次需重设 PATH）
export PATH=/tmp/flutter/bin:$PATH

# 验证
flutter analyze
flutter test
flutter test test/features/settings_backup_overdue_test.dart  # 单个测试

# 构建（fat APK 全架构）
flutter build apk --release --no-tree-shake-icons

# Git
git log --oneline -10
git status
git tag --list 'v*'
```

---

## 6. 文件地图（关键文件）

```
lib/
├── main.dart                          # 启动：zone+Sentry+themeSeed+异步初始化
├── app.dart                           # M3 主题 + 4-tab StatefulShellRoute 路由
├── main_shell.dart                    # 底部导航壳 + FAB
├── ai/
│   ├── prompts.dart                   # v1.4 prompt
│   ├── vision_provider.dart           # VisionRecognitionResult（含 copyWith）
│   ├── vision_service.dart            # 视觉服务
│   ├── nutrition_lookup.dart          # NutritionLookup + NutritionSource 枚举
│   └── off_provider.dart              # Open Food Facts 云查
├── core/
│   ├── config/
│   │   ├── app_config.dart            # AppConfig.load() + appConfigProvider
│   │   └── secure_config_store.dart   # secure_storage 封装（含 themeSeed）
│   ├── theme/theme_controller.dart    # themeSeedProvider + kThemePresets
│   ├── util/
│   │   ├── image_quality_checker.dart # 模糊图预检（批次 1）
│   │   ├── recognition_validator.dart # 字段合理性 + 营养素自洽 + 组分交叉验证
│   │   └── recognition_post_processor.dart # 三路径共用后处理（密度换算+校验修正，第二波）
│   └── error/
│       ├── sentry_init.dart           # initSentryAndRunApp（appConfig 失败降级）
│       └── sentry_scrub.dart          # Sentry 脱敏
├── data/
│   ├── database/database.dart         # drift，PRAGMA foreign_keys=ON
│   └── repositories/
│       ├── food_item_repository.dart  # upsertAiRecognized（更新含 componentsJson）
│       ├── meal_log_repository.dart   # insertMealLog + updateMealLog（8 可选字段全 editable）
│       └── weight_log_repository.dart # insert + getRange + getById/update/delete（全 editable）
└── features/
    ├── recognize/
    │   ├── recognize_controller.dart  # AI 兜底 + 复合菜全 miss 转 AI
    │   ├── recognize_page.dart        # 哨兵处理 + 改菜名 copyWith
    │   ├── calibration_page.dart      # 校准 + 数量步进器 + 徽章
    │   └── multi_dish_page.dart       # 多菜 _hitFlags 含 componentHits 判定
    ├── offline/offline_queue_controller.dart  # 离线回补 AI 兜底 + fire-and-forget
    ├── settings/settings_page.dart    # 主题色板 + _isSaving
    ├── profile/profile_page.dart      # _busy + try-catch
    ├── weight/weight_page.dart        # _busy + _load try-catch
    ├── food_library/                  # food_edit_page + food_library_page
    ├── manual_entry/manual_entry_page.dart
    ├── backup/backup_page.dart        # 导入二次确认
    ├── me/me_page.dart
    ├── records/records_tab_page.dart
    ├── dashboard/dashboard_page.dart
    ├── dashboard/meal_edit_dialog.dart   # 全 editable 第一批：餐次编辑独立 dialog（换食物+改餐次+日期+高级覆盖）
    └── insight/insight_page.dart
```

---

## 7. 会话结束前 AI 必做

1. 更新本文件第 2 节"当前状态"（日期、commit、工作区、未完成项）
2. 如有新陷阱，补到第 4 节
3. 如有新架构决策，补到第 3 节
4. 确认 `git status` clean（或明确记录未提交的改动原因）
