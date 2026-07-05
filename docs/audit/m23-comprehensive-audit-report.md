# M23 项目全面细致审查报告

## 元信息

| 项 | 值 |
|----|----|
| 审查日期 | 2026-07-05 |
| 审查范围 | `/workspace/lib` 全量 + `/workspace/android` 关键文件 + `/workspace/pubspec.yaml`/`pubspec.lock` |
| 基线 commit | `13701c5` |
| 应用版本 | `v0.21.0+33`（M22 图标精修 + 识别等待动画重构后） |
| 测试基线 | 1010 passed（M22 完成时） |
| flutter analyze | 通过（M22 完成时） |
| 审查员 | GLM-5.2（4 维度 sub-agent 并行 + 主 agent 汇总） |
| 审查依据 | Material 3 Expressive 规范 / Web Interface Guidelines / 项目 6 条硬约束 |
| 审查方法 | 静态 grep + 人工读关键文件 + 硬约束逐条核查 |
| 审查纪律 | 本次审查不改任何 lib/ 或 test/ 代码，所有发现只记录在报告里 |

---

## 摘要

### 发现统计总览

| 维度 | P0 | P1 | P2 | 小计 | 详细报告 |
|------|----|----|----|------|----------|
| 维度 1：UI 界面规范 | 0 | 6 | 17 | 23 | [m23-dim1-ui.md](file:///workspace/docs/audit/m23-dim1-ui.md) |
| 维度 2：功能完整性 | 0 | 1 | 10 | 11 | [m23-dim2-functional.md](file:///workspace/docs/audit/m23-dim2-functional.md) |
| 维度 3：代码质量 | 0 | 5 | 16 | 21 | [m23-dim3-quality.md](file:///workspace/docs/audit/m23-dim3-quality.md) |
| 维度 4：安全 | 0 | 1 | 11 | 12 | [m23-dim4-security.md](file:///workspace/docs/audit/m23-dim4-security.md) |
| **合计** | **0** | **13** | **54** | **67** | — |

### 整体评价

EatWise v0.21.0+33 经过 4 维度全面细致审查，**未发现任何 P0 级问题**——6 条项目硬约束全部满足，无崩溃、无数据丢失、无安全漏洞、无功能完全不可用情况。这是连续两个里程碑（M21 + M23）审查后均确认代码层面零 P0 的稳定基线。

13 项 P1 集中在三个方向：(1) **错误态覆盖不完整**（insight/food_library/profile 静默吞异常或仅 toast，与 dashboard 显式 ErrorState + 重试入口模式不一致）；(2) **架构层次违反**（11 个 feature 文件直接 import data/database.dart 绕过 Repository Provider）；(3) **长方法/超长文件**（processPending 396 行、_pickAndRecognize 190 行、multi_dish_page 986 行、dashboard_page 948 行）。这三大方向均不引发即时功能 bug，但影响可测试性、可维护性与生产环境可观测性，是后续里程碑的重点。

54 项 P2 多为视觉一致性小瑕疵（Card padding 12 vs 16 / 徽章 fontSize 10 vs ≥12 / Card 三套风格并存）、UX 优化项（备份导入仅支持粘贴 JSON / APK 下载无断点续传 / 体重无法补录往日）、安全加固空间（备份文件未加密 / 导入缺恶意数据校验 / URL https 校验缺失）。这些均不影响当前功能正确性，可按优先级在 M25+ 排期修复。

**整体健康度评级：B+（良好）**——M3 公共组件抽象到位、写库按钮防重入三件套全覆盖、async gap mounted 检查规范、TODO/FIXME/HACK 零标记、6 硬约束全部满足，代码规范度高；短板集中在错误态一致性、架构分层、长方法拆分三方面，属"可持续维护但需渐进式重构"的状态。

---

## 维度 1：UI 界面规范

> 详细发现见 [m23-dim1-ui.md](file:///workspace/docs/audit/m23-dim1-ui.md)（23 项：0 P0 / 6 P1 / 17 P2）

### 审查范围

14 个 feature 页面 + 1 个公共组件 + 1 个进度卡片（共 17 文件），覆盖 dashboard / today_meals / food_library / insight / manual_entry / me / profile / recognize / calibration / multi_dish / records / settings / update / weight / backup 全量页面。

### 6 项 P1 发现

| # | 位置 | 现状 | 影响 |
|---|------|------|------|
| 1.1 | [insight_page.dart:394-405](file:///workspace/lib/features/insight/insight_page.dart#L394) | 周/月切换时无 loading 指示，图表直接消失再出现 | 用户切换周/月时看到"暂无足够热量数据"闪现，体验突兀 |
| 1.2 | [food_library_page.dart:55-59](file:///workspace/lib/features/food_library/food_library_page.dart#L55) | `_loadFrequent` 异常被静默吞掉，无错误提示 | DB 异常时显示"暂无常用食物"空态，误导用户 |
| 1.3 | [food_library_page.dart:95-102](file:///workspace/lib/features/food_library/food_library_page.dart#L95) | `_doSearch` 异常被静默吞掉，清空结果无提示 | 搜索失败显示"未找到相关食物"，无重试入口 |
| 1.4 | [profile_page.dart:74-78](file:///workspace/lib/features/profile/profile_page.dart#L74) | 档案加载失败仅 toast，UI 显示空白表单 | 用户看到一堆空输入框 + 一个 toast，不知发生了什么 |
| 1.5 | [update_page.dart:213-214](file:///workspace/lib/features/update/update_page.dart#L213) | release notes `maxLines: 10, overflow: TextOverflow.ellipsis` | 长更新日志被尾部省略号截断，无"展开全文"入口 |
| 1.6 | [dashboard_page.dart:519-520](file:///workspace/lib/features/dashboard/dashboard_page.dart#L519) | `_regenerateButton` 触控目标 32dp < 48dp | 违反 MD3 可访问性最小触控目标规范 |

### 17 项 P2 发现（按类别分组）

- **间距类（7 项）**：food_edit/multi_dish/profile/update Card padding=12（应 16）、today_meals ListView padding=12、recognize_page SizedBox height=20（非 8dp grid 倍数）、calibration ExpansionTile tilePadding=12
- **字号类（7 项）**：dashboard/multi_dish 徽章 fontSize=10（应≥12）、calibration 徽章 fontSize=11、calibration 历史提示 fontSize=12、insight 图表轴标签 fontSize=10、multi_dish 营养素行 fontSize=12、backup/settings 说明文字硬编码 fontSize 不跟随系统缩放
- **跨页一致性类（3 项）**：Card 三套风格并存（默认/outlined/tonal）、主操作按钮 FAB vs FilledButton 不统一（settings 用 FAB）、insight AppBar.title 冗长日期范围；外加 AppBar 风格需文档化

### 维度 1 结论

EatWise 14 个 feature 页面整体 UI 规范执行度高——M3 公共组件（LoadingState/ErrorState/EmptyState/HeroCard/SectionTitle/LeadingIconContainer/GroupCard/MacroColors）抽象到位，跨页配色与图标语义统一，数值列普遍使用 `FontFeature.tabularFigures()` 防数字跳动，M22 进度卡片动画重构后达到 M3 Expressive 标准。**未发现 P0 级问题**，6 条硬约束均无违反。建议优先修 6 项 P1（错误态 + 触控目标 + 切换体验，预估 2.5 小时），再批量修 P2 间距/字号（预估 1 小时），Card 风格统一可作为下一里程碑设计任务。

---

## 维度 2：功能完整性

> 详细发现见 [m23-dim2-functional.md](file:///workspace/docs/audit/m23-dim2-functional.md)（11 项：0 P0 / 1 P1 / 10 P2）

### 审查范围

逐个 feature 走查"主路径 + 异常路径 + 边界条件"，列死路 / 未覆盖异常 / 不一致行为。审查 10 个功能流：识别主流程 / AI 兜底三路径一致性 / 离线队列 / 备份恢复 / 应用内更新 / 洞察生成 / 推荐系统 / 体重记录 / 食物库 / 设置页。

### 6 条硬约束核查（全部满足）

| # | 硬约束 | 核查位置 | 结果 |
|---|--------|----------|------|
| 1 | build.gradle.kts `isMinifyEnabled=false` + `isShrinkResources=false` | `android/app/build.gradle.kts#L62-L63` | ✅ 满足 |
| 2 | meal_log.food_item_id 非空 FK，哨兵 0 写库前必须替换 | `lib/data/repositories/meal_log_repository.dart#L25-L27` | ✅ 满足（insertMealLog + updateMealLog 双重 ArgumentError 防御） |
| 3 | AI 兜底三路径全覆盖 | `recognize_page.dart#L85-L112` / `multi_dish_page.dart#L818-L831` / `offline_queue_controller.dart#L231-L247` | ✅ 满足（三路径均调 CalibratedNutritionCalculator.compute） |
| 4 | per100g 反算基于 estimatedWeightGMid | `calibrated_nutrition_calculator.dart`（三路径统一调用） | ✅ 满足 |
| 5 | SecureConfigStore 无 `instance` 静态属性 | `lib/core/config/secure_config_store.dart#L14-L37` | ✅ 满足 |
| 6 | initSentryAndRunApp 命名参数 `container:` + `app:` | `lib/main.dart#L69-L75` | ✅ 满足 |

### 1 项 P1 发现

**2.4-1【P1】备份导入静默清空离线队列（破坏性操作未知情同意）**

| 项 | 值 |
|----|----|
| 位置 | [json_importer.dart:41](file:///workspace/lib/data/backup/json_importer.dart#L41) + [backup_page.dart:155-161](file:///workspace/lib/features/backup/backup_page.dart#L155) |
| 现状 | json_exporter 设计上**不导出** pending_recognitions（临时队列，合理），但 json_importer 导入时 `DELETE FROM pending_recognitions` 清空当前队列，确认弹窗列举"档案、食物库、餐次记录、体重、汇总、反馈"6 项未提及离线队列 |
| 影响 | 用户有 N 条 pending 离线识别（已拍照未上传），导入旧备份后这些记录被清空，对应餐次照片对应的数据丢失，用户无感知。从用户视角是"数据丢失"，违反"破坏性操作需知情同意"原则 |
| 建议 | 确认弹窗补充"离线队列中 N 条待识别记录将被清空"，或导入时保留 pending_recognitions（不清空），仅清空导出包含的 7 张表 |
| 工作量 | 30 分钟 |

### 10 项 P2 发现（按功能流分组）

- **2.1 识别主流程（1 项）**：单品无营养数据路径静默 return null，UI 反馈链路依赖调用方
- **2.2 AI 兜底三路径（1 项）**：multi_dish_page 防御性兜底创建 0 卡 food_item 污染食物库（[multi_dish_page.dart:923-935](file:///workspace/lib/features/recognize/multi_dish_page.dart#L923)）
- **2.3 离线队列（2 项）**：类注释"重试上限 3 次"过时（实际 5 次）/ 永久 failed 项无 UI 入口提示用户
- **2.4 备份恢复（2 项）**：导入仅支持粘贴 JSON 无文件级导入（与导出不对称）/ 自动备份文件名仅含日期同日多次互相覆盖
- **2.5 应用内更新（3 项）**：下载失败后重试按钮走"检查更新"而非"重新下载" / APK 下载无断点续传 78MB 失败需从头重下 / APK 完整性仅校验 content-length 无 SHA256
- **2.6 洞察生成（1 项）**：GLM-4-Flash 调用无重试/退避，与 ai_recommendation_service 不一致

### 维度 2 结论

EatWise v0.21.0+33 功能完整性**整体良好**：无 P0，6 条硬约束全部满足，AI 兜底三路径一致性（历史最易出 bug 处）经核查完全对齐，CalibratedNutritionCalculator 抽象统一了三路径行为。1 个 P1 是备份导入静默清空离线队列且确认弹窗未告知用户，属"破坏性操作未知情同意"，建议优先修复。10 个 P2 多为 UX 优化项与防御性兜底污染。3 个功能流（推荐系统 / 食物库 / 设置页）零发现，状态管理与容错完备。

---

## 维度 3：代码质量

> 详细发现见 [m23-dim3-quality.md](file:///workspace/docs/audit/m23-dim3-quality.md)（21 项：0 P0 / 5 P1 / 16 P2）

### 6 条硬约束核查（全部满足）

| 硬约束 | 文件 | 状态 |
|--------|------|------|
| 1. `isMinifyEnabled=false` + `isShrinkResources=false` | `android/app/build.gradle.kts#L62-63` | ✅ 满足 |
| 2. `meal_log.food_item_id` 非空 FK，foodItemId=0 哨兵须替换 | `recognize_page.dart` / `multi_dish_page.dart` / `offline_queue_controller.dart` | ✅ 满足 |
| 3. AI 兜底三路径全覆盖 | 同上 | ✅ 满足 |
| 4. per100g 反算基于 `estimatedWeightGMid` | `calibrated_nutrition_calculator.dart#L48` / `today_meals_page.dart#L700-702` | ✅ 满足 |
| 5. `SecureConfigStore` 无 `instance` 静态属性 | `secure_config_store.dart` 及 5 处调用 | ✅ 满足 |
| 6. `initSentryAndRunApp` 命名参数 `container:` + `app:` | `main.dart#L69` / `sentry_init.dart#L15` | ✅ 满足 |

### 5 项 P1 发现

| # | 位置 | 现状 | 影响 |
|---|------|------|------|
| 3.1 | 11 个 feature 文件跨层依赖 | 直接 import `data/database/database.dart`，4 个文件还手动 new Repository 绕过 Provider | 破坏分层，测试无法 mock，DB schema 变更需多文件同步 |
| 3.2 | [multi_dish_page.dart](file:///workspace/lib/features/recognize/multi_dish_page.dart) 986 行 | UI + 业务 + 校准逻辑混合 | 单文件职责过载，维护困难 |
| 3.3 | [dashboard_page.dart](file:///workspace/lib/features/dashboard/dashboard_page.dart) 948 行 | 状态卡 + 推荐区 + 餐次列表三大块混合 | 同上 |
| 3.4 | [recognize_page.dart:380-568](file:///workspace/lib/features/recognize/recognize_page.dart#L380) `_pickAndRecognize` ~190 行 | 单方法承担"选图→识别→展示→等待确认→写库→离线入队"全流程 | 圈复杂度高，测试覆盖难 |
| 3.5 | [offline_queue_controller.dart:97-493](file:///workspace/lib/features/offline/offline_queue_controller.dart#L97) `processPending` ~396 行 | 单方法承担遍历 + 单品/复合菜两条路径 + 状态更新 | 项目最长方法，圈复杂度极高 |

**3.1 跨层依赖最严重案例**：[dashboard_page.dart#L70-L73](file:///workspace/lib/features/dashboard/dashboard_page.dart#L70)

```dart
final db = await ref.read(recognize.databaseProvider.future);
final foodRepo = FoodItemRepository(db);
final mealRepo = MealLogRepository(db);
final profileRepo = ProfileRepository(db);
```

**建议**：统一改用 `recognize.foodItemRepoProvider` / `recognize.mealLogRepoProvider` / `recognize.profileRepoProvider` 等 Provider 注入。

### 16 项 P2 发现（按类别分组）

- **超长文件（10 项）**：calibration_page 877 / insight_page 821 / recognize_page 740 / today_meals_page 736 / weight_page 612 / profile_page 577 / food_item_repository 575 / recognize_controller 570 / m3_widgets 534 / offline_queue_controller 517
- **重复代码（1 项）**：三路径哨兵检查代码块轻度重复（已有 DishNameEditor mixin + CalibratedNutritionCalculator 良好抽象范本）
- **错误处理可观测性（1 项）**：40 处 `catch (_)` 中部分关键路径（备份 / AI 推荐 / 别名回流）仅 debugPrint 缺 Sentry 上报
- **硬编码（2 项）**：recognize_progress_card 用 Colors.white 而非 colorScheme.onPrimary / settings_page 用 Colors.black/white 设置状态栏图标色（平台 API 限制可接受）
- **长方法（1 项）**：multi_dish_page._calcNutrition ~100 行 + 深嵌套 4-5 层
- **TODO/FIXME/HACK**：全代码库零标记 ✅
- **async gap mounted 检查**：12 处抽检全部满足 ✅
- **写库按钮防重入三件套**：10 个写库路径全部满足 ✅
- **Riverpod 用法**：规范，无 StateNotifier 残留 ✅
- **命名一致性**：跨文件风格统一 ✅

### 维度 3 结论

**整体质量：良好（B+）**。优点突出：6 硬约束全部满足 / 写库按钮防重入三件套全覆盖 / async gap mounted 检查规范 / TODO/FIXME/HACK 零标记 / DishNameEditor + CalibratedNutritionCalculator 体现良好 DRY 抽象意识。不足集中在跨层依赖（P1）/ 长方法（P1）/ 超长文件（P1+P2）/ 错误处理可观测性（P2）。建议 P1 优先拆分 processPending 和 _pickAndRecognize 长方法 + 统一 feature 层用 Repository Provider，P2 补关键路径 silent catch 的 Sentry 上报。

---

## 维度 4：安全

> 详细发现见 [m23-dim4-security.md](file:///workspace/docs/audit/m23-dim4-security.md)（12 项：0 P0 / 1 P1 / 11 P2）

### 6 条硬约束核查（安全相关 3 条全部满足）

| 硬约束 | 验证位置 | 结论 |
|--------|----------|------|
| 1. `android/app/build.gradle.kts` 保持 `isMinifyEnabled=false` + `isShrinkResources=false` | [build.gradle.kts:62-63](file:///workspace/android/app/build.gradle.kts#L62) | ✅ 满足 |
| 5. `SecureConfigStore` 无 `instance` 静态属性 | grep `SecureConfigStore.instance` 全 lib 无匹配 | ✅ 满足 |
| 6. `initSentryAndRunApp` 参数是命名参数 `container:` + `app:` | [sentry_init.dart:15-18](file:///workspace/lib/core/error/sentry_init.dart#L15) + [main.dart:69-74](file:///workspace/lib/main.dart#L69) | ✅ 满足 |

### 1 项 P1 发现

**4.2【P1】sentry_scrub.dart 注释承诺脱敏 event.tags 但实际未处理**

| 项 | 值 |
|----|----|
| 位置 | [sentry_scrub.dart:9-25](file:///workspace/lib/core/error/sentry_scrub.dart#L9) |
| 现状 | 文件头注释承诺"遍历 event.extra / event.tags，key 或 value 含敏感词的删除"，但实际代码（第 19-25 行）只处理了 `event.extra`，**未处理 `event.tags`** |
| 影响 | 当前项目未主动调用 `Sentry.setTag(...)`（grep 确认无 setTag 调用），实际泄露面有限；但注释与实现不一致，未来若开发者按注释假设信任"tags 已脱敏"而添加 setTag 调用，会直接泄露敏感字段 |
| 建议修复 | 在 `scrubBeforeSend` 第 25 行后补一段 tags 脱敏（与 extra 同模式），或修正注释删除"event.tags"承诺 |
| 工作量 | 15 分钟 |

### 11 项 P2 发现（按类别分组）

- **密钥存储（1 项）**：AppConfig.load() 用 String.fromEnvironment 作 fallback（dart-define key 进 APK，dev 自用风险低）
- **Sentry 脱敏（1 项）**：未处理 event.modules / event.threads（无 native 崩溃捕获需求，影响小）
- **AndroidManifest（2 项）**：缺 `<uses-feature android.hardware.camera required=false>` 声明 / 缺 `android:debuggable="false"` 显式声明 + networkSecurityConfig
- **网络层（2 项）**：settings_page Base URL 输入框无 https 校验 / apk_downloader download(url:) 未校验 scheme == https
- **SQL 注入**：✅ 无发现（drift customSelect 全参数化，3 处 customSelect 均用 `?` 占位符或静态字符串）
- **备份文件安全（3 项）**：导出 JSON 明文未加密（含健康隐私数据）/ 导入缺少文件大小+字段数量+数值范围校验 / 导入前未自动备份当前数据
- **日志脱敏（1 项）**：boot_log.txt 写入未脱敏（dev 自用风险低，建议用 sentry_scrub._scrubString 同款正则）
- **第三方依赖（1 项）**：pubspec.yaml flutter_riverpod 注释过时（3.3.2 已是 stable 但注释仍说 prerelease）

### 维度 4 结论

EatWise 在密钥存储（SecureConfigStore 设计规范，无 instance 静态属性误用，iOS 配置 first_unlock_this_device + synchronizable:false 防 iCloud 备份泄露）/ 网络层（全 HTTPS + 无证书校验绕过 + 无 TrustManager/X509 风险代码）/ SQL 注入防护（drift customSelect 全参数化）/ Android 权限最小化（6 个权限均有必要用途 + allowBackup=false + READ_EXTERNAL_STORAGE 用 maxSdkVersion=32 限定范围）四方面做得**符合最佳实践**，3 条安全相关硬约束（1/5/6）全部满足，无 P0 级安全问题。最严重的 P1 是 sentry_scrub.dart 的 tags 脱敏承诺与实现不一致，但因项目未主动调用 setTag，实际泄露面有限，建议补 tags 脱敏或修正注释。整体安全基线在个人自用 app 中属**良好水平**。

---

## 优先级清单汇总

### P0 级（0 项）

无。6 条项目硬约束全部满足，无崩溃 / 数据丢失 / 安全漏洞 / 功能完全不可用问题。

### P1 级（13 项）— 建议 M24 修复

| # | 维度 | 位置 | 问题摘要 | 工作量 |
|---|------|------|----------|--------|
| 1 | UI | [insight_page.dart:394-405](file:///workspace/lib/features/insight/insight_page.dart#L394) | 周/月切换无 loading 指示 + 图表突兀消失 | 30 分钟 |
| 2 | UI | [food_library_page.dart:55-59](file:///workspace/lib/features/food_library/food_library_page.dart#L55) | `_loadFrequent` 异常静默吞掉无错误提示 | 30 分钟 |
| 3 | UI | [food_library_page.dart:95-102](file:///workspace/lib/features/food_library/food_library_page.dart#L95) | `_doSearch` 异常静默吞掉清空结果无提示 | 15 分钟 |
| 4 | UI | [profile_page.dart:74-78](file:///workspace/lib/features/profile/profile_page.dart#L74) | 档案加载失败仅 toast，UI 显示空白表单 | 30 分钟 |
| 5 | UI | [update_page.dart:213-214](file:///workspace/lib/features/update/update_page.dart#L213) | release notes maxLines:10 截断无展开入口 | 15 分钟 |
| 6 | UI | [dashboard_page.dart:519-520](file:///workspace/lib/features/dashboard/dashboard_page.dart#L519) | `_regenerateButton` 触控目标 32dp < 48dp | 5 分钟 |
| 7 | 功能 | [json_importer.dart:41](file:///workspace/lib/data/backup/json_importer.dart#L41) + [backup_page.dart:155-161](file:///workspace/lib/features/backup/backup_page.dart#L155) | 备份导入静默清空离线队列且确认弹窗未告知 | 30 分钟 |
| 8 | 代码 | 11 个 feature 文件（见 dim3 §3.1） | 跨层依赖直接 import data/database + 手动 new Repository | 2 小时 |
| 9 | 代码 | [multi_dish_page.dart](file:///workspace/lib/features/recognize/multi_dish_page.dart) 986 行 | UI+业务+校准混合，需拆 _CalcNutritionWidget / _CompositeEditor | 4 小时 |
| 10 | 代码 | [dashboard_page.dart](file:///workspace/lib/features/dashboard/dashboard_page.dart) 948 行 | 三大块混合，需按 section 拆 widget | 4 小时 |
| 11 | 代码 | [recognize_page.dart:380-568](file:///workspace/lib/features/recognize/recognize_page.dart#L380) `_pickAndRecognize` ~190 行 | 拆分为 _pickImage/_runRecognize/_showResultAndWaitConfirm/_writeMealLog | 2 小时 |
| 12 | 代码 | [offline_queue_controller.dart:97-493](file:///workspace/lib/features/offline/offline_queue_controller.dart#L97) `processPending` ~396 行 | 拆分为 _processSingleItem/_processComposite | 3 小时 |
| 13 | 安全 | [sentry_scrub.dart:9-25](file:///workspace/lib/core/error/sentry_scrub.dart#L9) | 注释承诺脱敏 event.tags 但实际未处理 | 15 分钟 |

**P1 总工作量估算**：约 17 小时（UI 类 ~2.5h + 功能类 ~0.5h + 代码类 ~13h + 安全类 ~0.25h）

### P2 级（54 项）— 建议 M25+ 排期

按类别分组（每项工作量见各维度详细报告）：

| 类别 | 数量 | 代表问题 |
|------|------|----------|
| 间距不一致（padding 12 vs 16） | 7 | food_edit/multi_dish/profile/update Card padding=12 |
| 字号硬编码（fontSize 10/11/12） | 7 | dashboard/multi_dish 徽章 fontSize=10 |
| 跨页视觉一致性 | 3 | Card 三套风格并存 / FAB vs FilledButton / insight AppBar 冗长标题 |
| 备份恢复 UX 优化 | 5 | 导入仅支持粘贴 JSON / APK 下载无断点续传 / 自动备份同日覆盖 |
| 超长文件拆分 | 10 | calibration 877 / insight 821 / recognize_page 740 等 |
| 错误处理可观测性 | 1 | 关键路径 silent catch 缺 Sentry 上报 |
| 硬编码颜色 | 2 | recognize_progress_card Colors.white / settings 状态栏图标色 |
| 长方法 | 1 | multi_dish_page._calcNutrition ~100 行 |
| AndroidManifest 加固 | 2 | 缺 uses-feature camera / 缺 debuggable=false + networkSecurityConfig |
| 网络层 https 校验 | 2 | settings Base URL / apk_downloader download(url:) |
| 备份文件安全 | 3 | 导出明文未加密 / 导入缺校验 / 导入前未自动备份 |
| 其他 | 11 | boot_log.txt 未脱敏 / pubspec 注释过时 / 离线队列注释陈旧等 |

**P2 总工作量估算**：约 25-30 小时

---

## 后续建议

### M24（建议下一个里程碑）— 修 P1

聚焦 13 项 P1，按"风险高 + 工作量低"优先排序：

1. **快速修复（共 ~2 小时）**：
   - P1 #13 sentry_scrub.dart tags 脱敏（15 分钟）
   - P1 #6 dashboard 触控目标 32→48dp（5 分钟）
   - P1 #5 update release notes 展开/收起（15 分钟）
   - P1 #3 food_library 搜索失败 toast（15 分钟）
   - P1 #7 备份导入弹窗补"离线队列 N 条将被清空"（30 分钟）
   - P1 #1 insight 周/月切换 loading + AnimatedSwitcher（30 分钟）
   - P1 #2 food_library 加载失败 ErrorState（30 分钟）
   - P1 #4 profile 加载失败 ErrorState（30 分钟）

2. **架构重构（共 ~13 小时，可分多个 PR）**：
   - P1 #8 跨层依赖统一用 Repository Provider（2 小时）
   - P1 #11 _pickAndRecognize 拆分（2 小时）
   - P1 #12 processPending 拆分（3 小时）
   - P1 #9 multi_dish_page 拆分（4 小时，可分多次）
   - P1 #10 dashboard_page 拆分（4 小时，可分多次）

**M24 验收标准**：13 项 P1 全部修复 + flutter analyze 通过 + flutter test 全过 + 6 硬约束仍满足。

### M25+ — 修 P2

按类别分批：
- **M25**：P2 间距/字号小瑕疵批量修（7+7+3=17 项，~2 小时）+ 错误处理 Sentry 上报（1 项，~1 小时）
- **M26**：P2 备份恢复 UX 优化（5 项，~4 小时）+ 网络层 https 校验（2 项，~35 分钟）
- **M27**：P2 安全加固（AndroidManifest 2 项 + 备份文件 3 项 + boot_log 1 项，~5 小时）
- **M28+**：P2 超长文件拆分（10 项，~20 小时，可结合日常需求渐进式拆分，无需专门里程碑）

### 长期建议

1. **建立 UI 规范文档**：在 `lib/core/widgets/m3_widgets.dart` 顶部补充 AppBar 选用约定 / Card 风格选用约定 / 主操作按钮选用约定，防新页面选错
2. **建立错误态模式约定**：所有异步加载的页面统一走 `_loading` / `_loadError` / `_data` 三态模式 + ErrorState 重试入口，参考 dashboard / today_meals 实现
3. **建立 Sentry 上报约定**：关键路径 silent catch 必须补 `Sentry.captureException(e, stackTrace: st)`，参考 offline_queue_controller._onError 实现
4. **架构守护测试**：考虑加 lint 规则禁止 feature 层直接 import data/database（可用 dart_code_metrics custom_lint）
5. **持续审查节奏**：每个大里程碑（M20/M25/M30...）后跑一次 4 维度审查，保持代码健康度

---

## 附录：审查方法说明

### 审查流程

1. **Phase 1 准备**：创建报告骨架 + WebFetch 拉取 Web Interface Guidelines 最新规则作为维度 1 审查依据
2. **Phase 2 并行审查**：4 个 sub-agent 并行执行 4 维度审查，各自读代码 + grep + 写独立 markdown 文件
3. **Phase 3 汇总**：主 agent 合并 4 维度发现，生成综合报告 + 优先级清单 + 后续建议
4. **Phase 4 用户审阅**：交付报告，等待用户决定 M24 修复范围

### 审查依据

- **Material 3 Expressive 规范**：基础间距 4/8/16/24 倍数 / Card 圆角 12（medium）/28（hero）/ 触控目标≥48dp / 最小可读字号 12 / 容器色配对色保证 WCAG AA 4.5:1 / 加载空错三态显式区分 / 动效用 transform/opacity
- **Web Interface Guidelines**（拉取日期 2026-07-05，源 https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md）：加载态结尾用 `…` / 错误信息含下一步 / 空态不渲染破损 UI / 长内容用 truncate/line-clamp / 列表 >50 项虚拟化 / 数值列用 tabular-nums / 破坏性操作需二次确认 / 触控目标≥48dp / hover/active 增强对比 / 主动语态 + Title Case / 数字用阿拉伯数字
- **项目 6 条硬约束**：build.gradle minify=false / meal_log.food_item_id 非空 FK / AI 三路径 / per100g 基于 mid / SecureConfigStore 无 instance / initSentryAndRunApp 命名参数

### 审查范围

- `/workspace/lib` 全量（不含 test/）
- `/workspace/android/app/build.gradle.kts`（硬约束 1）
- `/workspace/android/app/src/main/AndroidManifest.xml`（维度 4 权限审查）
- `/workspace/pubspec.yaml` + `/workspace/pubspec.lock`（维度 4 依赖审查）

### 审查纪律

- 审查过程不改任何 lib/ 或 test/ 代码
- 所有发现只记录在报告里，不直接修
- 修复由 M24+ spec 处理（用户审阅报告后决策）

---

**报告完成时间**：2026-07-05
**报告路径**：`/workspace/docs/audit/m23-comprehensive-audit-report.md`
**维度详细报告**：
- [m23-dim1-ui.md](file:///workspace/docs/audit/m23-dim1-ui.md)
- [m23-dim2-functional.md](file:///workspace/docs/audit/m23-dim2-functional.md)
- [m23-dim3-quality.md](file:///workspace/docs/audit/m23-dim3-quality.md)
- [m23-dim4-security.md](file:///workspace/docs/audit/m23-dim4-security.md)
