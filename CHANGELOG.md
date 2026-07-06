# Changelog

本项目所有重要变更记录。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Bug 修复：SnackBar 横幅累积"存在非常久"+ 撤销时序不同步
- **根因**：(1) ScaffoldMessenger 默认队列式，连续操作时 N 个横幅依次显示 N×duration，用户连删多条时横幅"存在非常久"；(2) today_meals_page 撤销横幅用 `Future.delayed(3s)` 等待撤销窗口，与 SnackBar 实际显示时序不同步（排队/被挤掉/超时都会让撤销按钮变无效）
- **修复**：`showAppToast` 显示前 `clearSnackBars` 清空队列；today_meals_page 撤销横幅改用 `controller.closed` 替代 `Future.delayed`，正确感知关闭原因（action/timeout/swipe/被挤掉）；缩短 duration（撤销 4→3s / 识别失败 6→4s / 备份 5→4s 共 6 处）
- **测试**：新增 `test/widgets/snackbar_clear_test.dart` 5 个测试（clearSnackBars 不排队 / 单次显示 / 默认 4s / 自定义 duration / 撤销 reason==action）
- **验证**：flutter analyze No issues / flutter test 1062 passed / 0 回归

### Bug 修复：AI 推荐冷启动加载失败（connectivity 误报 + 缓存不刷新）
- **根因**：(1) `networkAvailableProvider` 是 `FutureProvider<bool>`（无 autoDispose），connectivity_plus 6.x 在 Android 冷启动时 ConnectivityManager 的 NetworkCallback 尚未首次回调，`checkConnectivity()` 误报 `[none]` 即使设备有网，首次 false 永久缓存导致 dashboard AI 推荐"刚打开软件就加载失败"；(2) `_loadAiRecommendations` 用 `ref.read` 不刷新 provider，重试按钮也无效（forceRefresh=true 时仍读缓存 false）
- **修复**：`networkAvailableProvider` 改 `FutureProvider.autoDispose<bool>`（页面重建/重新进入时重新查询，避免冷启动 false 永久缓存）+ 冷启动校正（首次返回 [none] 时 delay 500ms 重查一次）；`_loadAiRecommendations` forceRefresh=true 时用 `ref.refresh` 强制刷新网络状态，确保重试按钮生效
- **测试**：新增 `test/features/network_available_provider_test.dart` 4 个测试（冷启动校正 / 真离线 / 在线不重查 / autoDispose invalidate 重新查询），用 MethodChannel mock connectivity_plus
- **验证**：flutter analyze No issues / flutter test 1062 passed / 0 回归

## [v0.24.0] - 2026-07-06

### M25 主题动态取色（Material You 壁纸取色）
- **方案**：dynamic_color 包 + DynamicColorBuilder 包裹 MaterialApp.router，三态决策（动态色可用/不可用/开关关闭）
- **新增**：`useDynamicColorProvider`（bool，默认 false）+ SecureConfigStore key `use_dynamic_color`
- **启动期**：main.dart `Future.wait` 并行读 themeSeed + useDynamicColor（省 100-300ms）
- **UI**：设置页 SwitchListTile + 色板 Opacity 0.38 + AbsorbPointer 硬互斥（开启时色板灰显不可点）
- **minSdk**：24 → 31（dynamic_color 包硬性要求，新增第 7 条硬约束）
- **影响**：Android 12+ 用户开启动态取色后主题跟随壁纸；< 12 自动 fallback 到 fromSeed
- **验证**：flutter analyze No issues / flutter test 1056 passed（基线 1040 + 16 新增）/ 6+1 硬约束满足 / 0 回归

### M25 图标精修重设计
- 对标 MyFitnessPal 圆盘容器语言
- 配色：紫色 #6750A4 → 自然绿 #2E7D32（紫色抑制食欲改绿，WCAG AAA 7.2:1）
- 几何：四角 L 角标（8 线段 36dp span）→ 圆环描边盘（56dp 外径 + 中心实心碗 22×11dp），黄金分割 0.393 + 0.5dp 网格对齐
- 元素：9 个（8 L + 1 碗）减为 2 个（1 圆环 + 1 碗），克制留白足

## [v0.23.0] - 2026-07-06

### M25 方案 D：废弃品类校准 + 酒精豁免 Atwater（米粉汤 bug 修复）
- **根因**：`FoodCategoryDefaults.calibrate` 用"品类均值（soup=30）"覆盖"AI 具体估算（per100g=92.3，比值 3.08>2 触发校准）"，calories 用默认值、宏量保留 AI 值，破坏 Atwater 自洽（4×16+9×13+4×75=481 ≠ 171）
- **修复**：废弃品类校准，4 项全保留 AI 估算值，只做物理 clamp [0,900] + 宏量 [0,100]；酒精饮料（beer/wine/alcohol）豁免 Atwater 校验（酒精 7kcal/g 不在 4p+9f+4c 系数内）
- **清理**：删除历史啤酒补丁（雪花啤酒被识别成雪碧的 workaround，AI 识别精准后无意义）
- **影响场景**：米粉汤/奶油汤/八宝粥等高变异品类不再被误伤；啤酒/葡萄酒/烈酒保留酒精热量
- **验证**：flutter analyze No issues / flutter test 1038 passed（基线 1032 → +6）/ 6 硬约束满足 / 0 回归
- **修复效果**：米粉汤 AI 推理 526 kcal + 16/13/75 → 显示 526 kcal + 16/13/75（Atwater 自洽，偏差 9%）

### M25：GitHub 仓库主页同步完善
- README 重写（87 → 178 行产品级，14 章节 + 6 badges + 功能矩阵 + 技术栈 + 6 硬约束）
- 创建 CHANGELOG.md（Keep a Changelog 格式，16 个版本段）
- 验证 LICENSE（MIT）
- PATCH Release v0.22.0 notes 补 M24 changelog 段
- main 合并 + 同步

## [v0.22.0] - 2026-07-05

### M24：P1 清零（13 项 P1 修复 + 架构重构）
- **快速修复（8 项）**：Sentry tags 脱敏 / dashboard 触控目标 / update release notes 展开 / food_library 搜索 toast / backup 离线队列提示 / insight 周/月切换 loading / food_library + profile ErrorState
- **架构重构（5 项）**：跨层依赖 Provider 注入 / recognize_page _pickAndRecognize 190→23 行 / offline_queue_controller processPending 396→29 行 / multi_dish_page 986→542 行 / dashboard_page 940→304 行
- **验证**：flutter analyze No issues / flutter test 1032 passed / 6 硬约束满足 / 0 回归
- 代码健康度 B+ → A-

## [v0.21.0] - 2026-07-05

### M22：图标精修 + 识别等待动画重构
- 图标反转配色（紫底白前景 → 白底紫前景）+ 几何精修（描边 4→2.5dp / square→round cap / 范围 50→36dp / 碗剪影替代苹果圆 / 移除扫描线）
- 识别进度卡片 TweenAnimationBuilder 平滑插值 + AnimatedSwitcher 图标 morph + done 态弹性 scale-in
- 查库阶段最小展示 300ms + done 态成功停留 400ms

## [v0.20.1] - 2026-07-05

### M21：项目全面审查 + P0/P1 修复
- P0 修复：HANDOFF.md 第 1/2 节严重不同步
- P1 修复：补 glm_4v_provider + qwen_vl_provider isRefusalForTest 单测共 16 个
- 987 测试全过 + 6 硬约束全部通过 + M19/M20 无回归

## [v0.20.0] - 2026-07-05

### M20：Google Lens 风图标 + 识别思考流程 UI
- 图标重设计：紫橙渐变 + 圆角取景框 + 苹果剪影 + 扫描线
- 识别思考流程 UI：识别中显示 AI 思考步骤卡片
- 新增 10 个 widget 测试 + 更新 6 个图标测试

## [v0.19.1] - 2026-07-05

### M19：AI 推荐去重 + 菜名归一化 + 多样性
- AI 推荐结果去重（避免重复推荐同一菜品）
- 菜名归一化（统一不同写法）
- 推荐多样性增强
- 新增 35 个 TDD 测试

## [v0.19.0] - 2026-07-05

### M18：多菜场景 AI 推理可见性 + 三路径一致性
- 多菜场景展示 AI 推理过程
- 三路径（recognize_page / multi_dish_page / offline_queue_controller）行为一致性

## [v0.18.9] - 2026-07-05

### M17：App 图标重设计——M3 抽象几何
- M3 抽象几何图标（同心圆环 + 中心圆点）
- 紫橙双色渐变背景

## [v0.18.8] - 2026-07-05

### M16.9：减小库值重要性——AI 绝对优先
- 查库命中分支重写（AI 与库偏差 > 50% 用 AI 反算 per100g + 更新库）
- 复合菜残留路径修复

## [v0.18.6] - 2026-07-05

### M16.7：Web Interface Guidelines 全 UI 审查修复
- 17 文件 195 问题修复（按 Web Interface Guidelines 规范）

## [v0.18.5] - 2026-07-05

### M16.6：营养数值一致性修复
- 三路径 actualCalories 计算统一（recognize_page / multi_dish_page / offline_queue_controller）
- meal_log.actualCalories 与 food_item.caloriesPer100g 数据一致

## [v0.18.4] - 2026-07-05

### M16.5：bump + HANDOFF 回填

## [v0.18.3] - 2026-07-05

### M16.4：bump + HANDOFF 回填 + spec 文档归档

## [v0.18.1] - 2026-07-05

### M16.2：识别流程修复 6 个 P0/P1 问题
- 用户反馈"相册内识别经常出错"

## [v0.18.0] - 2026-07-04

### M16：应用内自更新
- MainActivity.kt 修复 call.arguments 类型转换（CI build failed）
- 严格 TDD 实现 13 个 Task

## [v0.16.0] - 2026-07-04

### M15：v5 AI 推荐审计修复 + 满意度反馈按钮优化

## [v0.15.0] - 2026-07-04

### M15：UI 优化 + 图标重设计
- 暖橙纯色图标（餐叉餐刀）
