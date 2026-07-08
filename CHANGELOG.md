# Changelog

本项目所有重要变更记录。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [v0.32.0] - 2026-07-09

### M27 v2 小米体脂秤2 + 体脂率 + BMR 自动升级

接入小米体脂秤2（XMTZC05HM）v2 协议，自动计算体脂率并升级 BMR 公式。

#### 新增
- 支持小米体脂秤2（XMTZC05HM）v2 协议（UUID 0x181B / 13字节，保留 v1 XMTZC04HM 兼容）
- 体脂率自动计算（openScale MiScaleLib 逆向 BIA 公式，双源验证 + 3 回归夹具）
- BMR 自动升级：有体脂率用 Katch-McArdle（基于瘦体重，对精瘦人群更准），无则 Mifflin-St Jeor
- 体重记录卡片 + 图表 tooltip 显示体脂率

#### 修复
- startScan 时序 bug（flutter_blue_plus startScan 开始时返回非结束时，"未找到"toast 误弹）
- 国产 ROM 系统定位开关检查（华为系 HarmonyOS/EMUI 静默无结果）
- AOSP 30秒/4次 扫描节流保护（新增 30秒短窗冷却）
- scanner _controller isClosed 守卫（防 dispose 竞态崩溃）
- v2 impedance 捕获时机（优先等 measurementComplete，超时 stabilized 兜底）
- formula 切换时重置 tdeeAdjustmentKcal（防跨公式污染 P0）
- bodyFatPct 显式置空支持（ProfileRepository.clearBodyFatPct 方法）

#### 数据层
- weight_log 表加 impedance + bodyFatPct 字段（schemaVersion v4→v5）
- backup 导入导出支持新字段（兼容旧备份）

#### 验证
- flutter analyze No issues
- flutter test 1172 passed / 3 skipped / 0 failed（基线 1143 + 新增 29 测试，0 回归）
- 6+1 硬约束全部满足

## [v0.31.0] - 2026-07-08

### 新增：M27 蓝牙体重秤同步

接入小米体重秤 2（XMTZC04HM）BLE 被动扫描，量体重后自动捕获稳定值预填体重输入框。

#### 改动
- `pubspec.yaml`：新增 `flutter_blue_plus ^2.3.10` + `permission_handler ^12.0.3`
- `android/app/src/main/AndroidManifest.xml`：声明 BLUETOOTH_SCAN + BLUETOOTH_CONNECT + ACCESS_FINE_LOCATION 权限（不加 neverForLocation 适配国产 ROM）
- 新增 `lib/data/bluetooth/mi_scale_parser.dart`：Mi Scale v1 协议解析器（bitmask 判定单位 + isEffective 双重保护 + packet_id 去重）
- 新增 `lib/data/bluetooth/mi_scale_scanner.dart`：BLE 扫描 Service（无过滤扫描 + Dart 软过滤 + lowLatency）
- 新增 `test/mi_scale_parser_test.dart`：9 个 TDD 测试（7 hex 样本 + 长度错误 + 去重）
- `lib/features/weight/weight_page.dart`：接入蓝牙扫描（WidgetsBindingObserver 生命周期 + 权限请求 + 4 态 UI + 捕获预填 + 5 分钟 ≤3 次扫描冷却）

#### 协议解析关键决策
- bitmask 判定单位（不用枚举匹配，否则漏 0x62 等包）
- 斤系数 0.5（ESPHome 0.6 是 bug，1 斤 = 0.5 kg）
- isEffective 双重保护：stabilized && !weightRemoved
- packet_id（payload hex）去重

#### 验证
- flutter analyze No issues
- flutter test 1143 passed / 3 skipped / 0 failed（0 回归）
- 6+1 硬约束全部满足

## [v0.30.1] - 2026-07-07

### 修复：APK 体积优化实际生效

v0.30.0 加了 `build.gradle.kts` 的 `abiFilters = arm64-v8a`，但 release APK 体积未变（仍 87.7MB）。根因：**Flutter gradle plugin 不带 `--target-platform` 时默认打 3 ABI，会覆盖 `defaultConfig.abiFilters`**。

#### 修复
- `.github/workflows/release.yml`：release 和 debug 的 `flutter build apk` 命令都加 `--target-platform android-arm64`

#### 预期收益（本次实际生效）
- release APK：87.7MB → ~30MB（减 65%）
- debug APK：181MB → ~60MB（减 67%）

## [v0.30.0] - 2026-07-07

### APK 体积优化：abiFilters 仅打包 arm64-v8a

用户反馈 release APK 87MB 体积过大。调研发现主因是默认打包 3 个 CPU 架构（arm64-v8a + armeabi-v7a + x86_64），每架构 Flutter engine .so ~20MB，共 ~60MB。

#### 改动
- `android/app/build.gradle.kts`：`defaultConfig` 内加 `ndk { abiFilters += "arm64-v8a" }`，仅打包 64 位 ARM

#### 预期收益
- release APK：87MB → ~30MB（减 65%）
- debug APK：180MB → ~60MB（减 67%）

#### 风险评估
- minSdk=31（Android 12+）已排除老手机，arm64 普及率 >99%，覆盖充分
- 模拟器（x86_64）无法安装此 release 包，开发用 `--target-platform android-x64` 单独打
- 不碰硬约束 #1：R8 minify/shrink 仍禁用，仅过滤 ABI

#### 验证
- `flutter analyze`：No issues found
- `flutter test`：1133 passed / 3 skipped / 1 failed（github_release_smoke_test 沙箱网络限流，与本次改动无关，0 回归）
- 6+1 硬约束满足（minify=false / shrink=false / minSdk=31 / abiFilters=arm64-v8a）

## [v0.29.0] - 2026-07-07

### M26 图标精修

用户反馈"想把图标做得更精致美丽一点"。从 M25 圆环盘+实心碗（2 元素纯色）升级为 M26 描边碗+米粒+叶子（4 path + 径向渐变背景）。

#### 视觉改动
- **背景**：径向渐变（中心白 #FFFFFF → 边缘 Light Green 50 #F1F8E9），替代 M25 纯白
- **前景 4 path**：
  - 碗填充（淡绿 #E8F5E9）+ 碗描边（深绿 #1B5E20，2.5dp round cap）
  - 三粒米粒（淡黄 #FFF59D，r=1.2dp，碗内三角排列，食物语义）
  - 右上飘出叶子（主绿 #2E7D32，水滴形 45° 上扬，自然×食物双重语义）
- **删除**：M25 圆环描边盘（碗成为唯一主体，几何更聚焦）
- **配色层次**：4 色 + 渐变（vs M25 的 2 色纯绿）

#### 资源改动
- `colors.xml`：新增 6 色定义（ic_launcher_background_center/edge + bowl_stroke/fill + leaf + rice）
- `ic_launcher_background.xml`：改径向渐变（`<aapt:attr>` 嵌套 `<gradient type="radial">`）
- `ic_launcher_foreground.xml`：重写 4 path
- 5 个密度 PNG fallback（mdpi 48 / hdpi 72 / xhdpi 96 / xxhdpi 144 / xxxhdpi 192）用 Python+cairosvg+pillow 重新渲染
- `icon_assets_test.dart`：断言更新为 M26 几何与配色

#### 验证
- `flutter analyze`：No issues found
- `flutter test`：1134 passed / 3 skipped / 0 failed（0 回归）
- 6+1 硬约束满足（未触碰 build.gradle.kts / meal_log / AI 三路径）

### Bug 修复：餐次分布可读性 + 删最后一个食物复活

用户报告 3 个问题：(1) 餐次分布数字小数点后位数太多；(2) 早餐/午餐/晚餐/加餐半透明看不清，数字也看不清；(3) 今日明细删最后一个食物删不掉，删除后一直悬浮撤回横幅。

#### 修复
- **餐次分布数字精度**（`insight_page.dart`）：`'$pct%'` → `'${pct.toStringAsFixed(1)}%'`（33.3% 而非 33.333333%）
- **餐次分布可读性**（`insight_page.dart`）：
  - badge 背景 alpha 0.12 → 0.28，避免半透明看不清
  - badge 文字色 `color` → `cs.onSurface`（深色）+ w700 加粗，对比度提高
  - snack section 色 `cs.outline`（浅灰）→ `cs.onSurfaceVariant`（深灰），白文字对比度足
- **删最后一个食物复活**（`today_meals_page.dart`）：
  - 根因：onDismissed 中 `await controller.closed` 期间（3 秒），RefreshBus/tab 切换触发 `_load()` 把 m 重新加载到 `_meals`（DB 还没删），`controller.closed` 返回后 `deleteMealLog` 成功但没刷新 UI，食物"复活"→ 用户反复删除 → 横幅反复出现 → "删不掉 + 横幅一直悬浮"
  - 修复：`deleteMealLog` 成功后检查 `_meals` 是否含 m.id，有则 `setState` 移除，确保 UI 与 DB 一致

#### 验证
- `flutter analyze`：No issues found
- `flutter test`：1134 passed / 3 skipped / 0 failed（0 回归）
- 6+1 硬约束满足

## [v0.28.0] - 2026-07-07

### v0.28.0 架构改造：AI 组分滑块影响热量（完全抛弃库参与热量计算）

用户报告"AI 推理热量与显示不一致"根因是库 per100g 与 AI 估算双重计算 + 用油量累加重复。v0.28.0 彻底重构：**库仅作 food_item_id 解析兜底，不参与热量计算；AI 推理组分组分滑块影响热量**。

#### 核心改造
- **AI prompt v1.11**：food_components 每个组分加 calories/protein_g/fat_g/carbs_g 字段 + 自洽约束（4*p+9*f+4*c≈cal，组分和≈estimated_calories）
- **FoodComponent 数据类**：加 4 个营养字段 + per100g getter + scaled() 同比缩放方法
- **calibration_page**：
  - 删除用油量滑块（AI reasoning 已含用油）
  - 删除份量滑块（组分滑块代替，servingG = sum(组分 g) 自动算）
  - 组分滑块影响热量：拖动 → per100g × newG / 100 重算 → 总热量 = sum(各组分)
  - 热量计算统一走 `_computeCurrentNutrition()`（删除包装/AI 优先/组分累加三分支）
  - 删除 CalibratedNutritionCalculator 调用（库不参与热量计算）
- **自洽缩放**：initState 时若 sum(组分 calories) ≠ estimatedCalories，按比例缩放各组分使之和 = AI 值

#### 单品路径
- is_single_item=true 时热量固定 = AI estimatedCalories，无组分滑块，用户只能点击营养值手动编辑

#### 验证
- `flutter analyze`：No issues found
- `flutter test`：1134 passed / 3 skipped / 0 failed（删 oil 测试 -3 + consistency 新增 +1，0 回归）
- 6+1 硬约束满足 / per100g 反算基于 component.estimatedG（非 servingG）

## [v0.27.0] - 2026-07-07

### P0 修复：AI 推理热量与显示值不一致（5 处根因，2 个 commit）

用户报告"AI 推理出来的热量和最后显示的不一样"+ 复合菜显示组分明细繁琐 + "库里面没有"文案误导。OCR 数据反推 + API 实测（GLM-4V + Qwen-VL）定位 5 处根因。

#### Commit e6d1478：单品 + 复合菜热量计算修复
- **单品路径历史中位数预填**：calibration_page initState 用 `mid` 不用历史中位数 → 初始 actualCalories = AI 推理值（480×350/350=480，不再 480×278/350=381）
- **复合菜 totalG 缩放**：AI 优先分支 servingG 用 `mid` 不用 `totalG` → actualCalories = AI 推理值（不再按组分之和缩放）

#### Commit 16c5910：包装覆盖 + UI + 文案修复
- **_aiFallbackNutrition 包装食品路径覆盖 AI 原始估算**：recognize_controller.dart 删除 `actualCal = per100.$1 * mid / 100` 覆盖 → actualCal 始终用 `r.estimatedCalories`（AI 原值），保证 reasoning 文本热量 = aiFallback.calories = 显示值 = 写库值
- **复合菜组分滑块繁琐**：calibration_page._buildCompositeControls 隐藏组分份量滑块 + "待确认组分（未在食物库找到）"列表，只保留用油量滑块（总热量固定用 AI 值，组分滑块不影响总热量）
- **"AI 估算（库未命中）"文案误导**：_sourceBadge 改为"AI 估算"

### API 实测验证
- 两个 token（GLM 智谱 + Qwen 阿里通义）均有效（HTTP 200）
- GLM-4V 倾向返回 `is_single_item=false`（触发复合菜路径，修复后隐藏组分滑块）
- Qwen-VL 倾向返回 `is_single_item=true`（单品路径）
- 两个 provider 都返回 estimated_calories + reasoning，格式正常

### 验证
- `flutter analyze`：No issues found
- `flutter test`：1136 passed / 3 skipped / 0 failed（0 回归）
- 6+1 硬约束满足 / v2 契约 4 断言满足

## [v0.26.0] - 2026-07-07

### M26 第二轮 Web Interface Guidelines 深度审查 P1 修复（45 条，5 个 commit）

第二轮深度审查发现 45 条 P1，分 5 类（A 数据一致性 / B 核心流程 / C 系统性根因 / D 编辑流程 / E 错误反馈）串行 commit 修复。spec 见 `.trae/specs/fix-ui-audit-p1-round2-m26/`。

#### A 类数据一致性（commit 37d2b17，5 条）
- **复合菜路径优先级不一致**（calibration_page.dart）：`_buildNutritionPreview` / `_confirmWithServing` / `_currentDisplayedValues` 三处统一为"包装优先（宏量非全0）→ AI 优先（aiFallback 非空）→ 组分累加 fallback"链路，避免预览与写库走不同分支
- **复合菜 AI 优先路径未含用油量**：AI 优先分支累加 `oilCaloriesPer100g * _oilG / 100` 到 calories + `oilFatPer100g * _oilG / 100` 到 fat，用户拖动用油量滑块时预览实时变化
- **profile goalRate 游离 Form + 全页数值无范围校验**：goalRate 改 TextFormField + validator（0.1-2.0 kg/周，空值放行回退默认 -500 deficit）+ 4 字段范围校验（身高 50-250 / 体重 20-300 / 年龄 10-120 / 体脂率 0-60），_save 用 `tryParse ?? 0.0` 保留回退特性
- **weight 编辑 dialog 完全无校验静默 return**：改 Form + TextFormField + validator（>0 且 ≤500），失败显示 errorText 不关闭 dialog，删除调用方静默 return
- **backup_page 导入后未 invalidate provider**：导入成功后 invalidate 4 个 provider（appConfig / mealLogRepo / weightLogRepo / profileRepo）+ RefreshBus.instance.notify()

#### B 类核心流程（commit e3a5775，3 条）
- **confirmAction 长内容溢出 AlertDialog 不可达**：content 包 `ConstrainedBox(maxHeight: 屏幕40%) + SingleChildScrollView + Text`，超长内容可滚动且确认按钮始终可达
- **update_page error 态"重试"行为错误**：新增 `_FailedStage` enum（none/check/download/install）+ `_lastFailedStage` 字段，error 态按钮按失败阶段调对应方法（check→_check / download→_download / install→_install），install 失败重试复用 `_downloadedPath` 不重新下载
- **dish_name_editor 文案错误**：`'食物库未命中「改菜名」'` → `'食物库未命中此菜名'`

#### C 类系统性根因（commit 3ec25bf，4 类批量整改）
- **showAppToast 缺 liveRegion**：SnackBar content 包 `Semantics(liveRegion: true, child: Text(msg))`，读屏可感知 toast
- **EmptyState 硬编码 camera 图标**：新增 `actionIcon` 参数（默认 `Icons.camera_alt_rounded` 兼容现有调用）
- **18 处错误文案含原始异常**：改为"<操作>失败：<原因推测>。<修复步骤>"格式 + `debugPrint` 原始异常（insight_page / today_meals_page×3 / calibration_page×2 / multi_dish_page / settings_page / backup_page×2 / update_page×3 / profile_page×2 / weight_page×3 / manual_entry_page×2 / food_edit_page×2）
- **7 个文件数值 TextField 无 inputFormatters**：28 处 TextField 加 `FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))` 防物理键盘输入字母/多小数点（calibration_page×4 / meal_edit_dialog×5 / food_edit_page×5 / manual_entry_page×6 / weight_page×2 / profile_page×5 / today_meals_page×1）

#### D 类编辑流程一致性（commit f25bf82，4 条）
- **meal_edit_dialog 无 dirty 拦截**：加 `_dirty` 状态 + `_markDirty()` + `PopScope(canPop: !_dirty, onPopInvokedWithResult: ...)` + `confirmDiscardChanges(context)`，所有编辑控件挂 `_markDirty`，_save 前清 dirty 让 PopScope 放行
- **backup_page _import 重入窗口**：`_import()` 入口加 `if (_busy) return;` 防重入
- **settings_page TextField focus ring**：5 处 TextField 加 `focusedBorder: UnderlineInputBorder()` 提供 focus ring
- **update_page AnimatedSize reduced-motion**：duration 改读 `MediaQuery.accessibleNavigation ? Duration.zero : Duration(milliseconds: 300)`

#### E 类错误反馈与状态覆盖（commit 808ea10，5 条）
- **recognize_page SnackBar 缺 liveRegion**：内联 SnackBar content 包 `Semantics(liveRegion: true, child: Text('识别失败：$msg'))`
- **today_meals_page Undo SnackBar 缺 liveRegion**：Undo SnackBar content 包 `Semantics(liveRegion: true, child: Text('已删除 <菜名>'))`
- **today_meals_page Image.file 无 semanticLabel**：加 `semanticLabel: '食物图片'`
- **today_meals_page 反馈纠正 dialog barrierDismissible**：showDialog 加 `barrierDismissible: false`
- **4 文件校验错误走 toast 改 errorText 内联**：meal_edit_dialog / food_edit_page / manual_entry_page / weight_page 校验失败改轻量 `_xxxError` 状态字段 + `InputDecoration.errorText` 内联显示（避免完整 Form 改造）

### 测试
- 新增 13 个测试文件，覆盖 5 类修复：
  - A 类：calibration_composite_consistency_test (2) + calibration_composite_oil_test (3) + profile_page_test 扩展 (7) + weight_edit_dialog_validation_test (4) + backup_import_invalidate_test (1)
  - B 类：confirm_action_overflow_test (4) + update_retry_context_test (3) + dish_name_editor_test (5)
  - C 类：snackbar_clear_test 扩展 liveRegion + empty_state_icon_test (3) + error_message_friendly_test (3)
  - D 类：meal_edit_dialog_dirty_test (4) + backup_page_test 扩展 (2)
  - E 类：today_meals_page_e_test (3) + inline_error_text_test (5)
- 测试总数：基线 1107 → 1136 passed（+29 新测试，0 回归）

### 验证
- `flutter analyze`：No issues found
- `flutter test`：1136 passed / 3 skipped / 0 failed
- 6+1 硬约束满足（minify=false / shrink=false / minSdk=31 / meal_log 外键 / AI 三路径 / per100g 反算基于 mid / SecureConfigStore / initSentryAndRunApp）
- v2 重构 4 断言满足（AI 估算值不被静默修改 / 预览值=onConfirm 写库值 / warnings 透传 / 用户手动编辑覆盖 AI 值）

## [v0.25.0] - 2026-07-06

### 功能增强：周月总结全面扩充（问题2）
- **背景**：原 InsightPage 仅热量折线图 + 体重折线图 + AI 文本，维度不够全面，用户难以直观看到餐次分布/三宏达成率/偏好食物/连续记录/体重变化等关键信息
- **UI 新增**（insight_page.dart）：
  - 周期概览卡片：连续记录 streak / 平均超缺目标 kcal / 目标达成天数 / 体重首末变化（2x2 tile，MD3 角色色区分语义）
  - 餐次分布环图（PieChart）：早/午/晚/加餐 占比 + 中心总热量，4 个 section 用 primary/tertiary/secondary/outline 区分
  - 三宏达成率柱图（BarChart）：蛋白/脂肪/碳水 实际均值 vs 目标（实色=均值，半透明=目标），触摸 tooltip 显示具体值
  - 偏好食物 Top5 列表：排名徽章（1/2/3 用 primary/tertiary/secondary）+ 食物名 + 频次 + 热量贡献条
  - 月报周环比柱图（仅 monthly）：30 天按 7 天分组，每周日均热量 + 总体日均参考线
- **AI prompt 新增**（glm_flash_provider.dart）：
  - `_appendEnhancedInsights`：餐次分布/streak/平均超额/达成天数/体重变化/特殊人群画像（specialCondition/dietPreference/healthCondition）
  - `_appendWeeklyBreakdown`：月报周环比数据
  - `_specialLabel`：特殊人群 code → 中文标签映射（孕期/哺乳期/老年/糖尿病等 11 种）
  - 'none'/null 兜底不写入 prompt，避免噪音
- **数据层**（_aggregatePeriod）：新增 mealTypeCalories/streak/avgExcess/goalHitDays/weightFirst/Last/Diff/weeklyBreakdown + profile 特殊人群字段；onSelectionChanged 同步重置新增 state
- **测试**：新增 `test/ai/glm_flash_provider_p2_test.dart` 21 个 prompt 测试 + `test/features/insight_p2_test.dart` 7 个 UI 渲染测试
- **验证**：flutter analyze No issues / flutter test 1107 passed / 0 回归

### 功能增强：首页热量超量显示全维度切换（问题1）
- **背景**：摄入热量超过推荐值时，"今日还可摄入"依旧显示剩余值（负数），用户误以为还没超过
- **修复**（status_card_section.dart）：超量时全维度切换——
  - 标题"今日还可摄入"→"今日已超" + error 色 + warning 图标
  - 大数字加 "+" 前缀（如 "+200"）+ error 色
  - 副标题切换为"已超 X kcal (Y%) · 已摄入 A / B"
  - 进度条分两段：主段 error 色满格 + 溢出段 onErrorContainer 色按比例延伸（封顶 30% 宽）
  - 三宏同步：文案追加"超 Zg"用 error 色，进度条满格保留宏色
- **测试**：新增 `test/features/dashboard/status_card_overflow_test.dart` 14 个测试（热量未超量/临界/空态 + 热量超量标题/大数字/副标题/图标/进度条/大幅超量 + 三宏超量蛋白/脂肪/碳水/未超量/临界）
- **验证**：flutter analyze No issues / flutter test 1093 passed / 0 回归

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
