# M23 维度 3：代码质量审查（架构/重复/复杂度）

**审查对象**：EatWise Flutter App v0.21.0+33（commit 13701c5）
**审查范围**：`/workspace/lib` 全量代码
**审查方式**：静态分析 + 人工读关键文件
**审查时间**：2026-07-05
**审查员**：维度 3 审查员（GLM-5.2）
**硬约束**：本次审查不改任何代码，只产出审查发现

---

## 0. 硬约束检查（任一违反 = P0）

| 硬约束 | 文件 | 行号 | 状态 | 证据 |
|--------|------|------|------|------|
| 1. `isMinifyEnabled=false` + `isShrinkResources=false` | `android/app/build.gradle.kts` | 62-63 | ✅ 满足 | 两者均显式为 false |
| 2. `meal_log.food_item_id` 非空外键，foodItemId=0 哨兵须替换 | `recognize_page.dart` / `multi_dish_page.dart` / `offline_queue_controller.dart` | 77 / 813 / 162-260 | ✅ 满足 | 三路径均有 `if (n.foodItemId == 0)` 哨兵检查，调 `upsertAiRecognized` 替换 |
| 3. AI 兜底三路径全覆盖（recognize_page / multi_dish_page / offline_queue_controller） | 同上 | - | ✅ 满足 | 三路径哨兵检查齐备 |
| 4. per100g 反算基于 `estimatedWeightGMid`（不能用 `servingG`） | `calibrated_nutrition_calculator.dart` / `today_meals_page.dart` | 48 / 700-702 | ✅ 满足 | `per100Ratio = 100.0 / mid`；today_meals 用 `actualServingG` 反推（用户校准份量，场景正确） |
| 5. `SecureConfigStore` 无 `instance` 静态属性 | `secure_config_store.dart` 及 5 处调用 | 25 / 82 / 43,67 / 505 | ✅ 满足 | 全部用 `SecureConfigStore()` 构造函数 |
| 6. `initSentryAndRunApp` 参数是命名参数 `container:` + `app:` | `main.dart` / `sentry_init.dart` | 69 / 15 | ✅ 满足 | 签名 `{required ProviderContainer container, required Widget app}`，调用处用命名参数 |

**硬约束结论：6/6 全部满足，无 P0 级问题。**

---

## 1. 审查清单 11 项总览

| 清单项 | 检查方式 | 发现 |
|--------|----------|------|
| 架构层次 | grep 跨层 import + 人工核对 | P1 × 1 |
| 命名一致性 | 人工读关键文件 | 无发现 |
| 重复代码 | 人工比对三路径 + DishNameEditor | P2 × 1（轻微） |
| 圈复杂度 | 人工读长方法 | P1 × 2 |
| 超长文件 | `wc -l` 全量统计 | P1 × 2，P2 × 10 |
| Riverpod 用法 | 人工核对 provider 定义/调用 | 无发现 |
| 错误处理 | grep `catch (_)` + 人工核对上下文 | P2 × 1 |
| async gap（mounted 检查） | 人工读关键文件 | 无发现 |
| 写库按钮防重入 | grep `_busy`/`_isRecording`/`_isRecognizing` | 无发现 |
| 硬编码 | grep `Colors.*` + 人工核对 | P2 × 1 |
| TODO/FIXME/HACK 清单 | grep 全量 | 无发现 |

---

## 3.1 跨层依赖（架构层次）

**检查方式**：grep `import.*data/database/database.dart` in `lib/features/**`，逐文件核对是否绕过 Repository Provider 直接访问 DB。

### 发现 3.1-1【P1】feature 层 11 个文件直接 import data/database/database.dart，绕过 Repository Provider

**严重等级**：P1（架构层次违反，但当前未引发功能 bug）

**问题**：项目已通过 `recognize/providers.dart` 暴露 `databaseProvider` / `foodItemRepoProvider` / `mealLogRepoProvider` 等标准 Repository Provider（推荐模式见 `lib/features/recognize/providers.dart#L64`），但 11 个 feature 文件仍直接 import `data/database/database.dart`，部分文件还直接 `new FoodItemRepository(db)` / `new MealLogRepository(db)` 绕过 Provider 注入，破坏分层。

**证据**（11 处，按严重程度排序）：

| # | 文件 | 行号 | 直接 new Repo（绕过 Provider） |
|---|------|------|------------------------------|
| 1 | `lib/features/dashboard/dashboard_page.dart` | [L11](file:///workspace/lib/features/dashboard/dashboard_page.dart#L11) | 是（L70-73: `FoodItemRepository(db)` / `MealLogRepository(db)` / `ProfileRepository(db)`） |
| 2 | `lib/features/offline/offline_queue_controller.dart` | [L14](file:///workspace/lib/features/offline/offline_queue_controller.dart#L14) | 是（L101,105: `PendingRecognitionRepository(_db)` / `MealLogRepository(_db)`） |
| 3 | `lib/features/dashboard/today_meals_page.dart` | [L11](file:///workspace/lib/features/dashboard/today_meals_page.dart#L11) | 否（用 recognize.mealLogRepoProvider） |
| 4 | `lib/features/food_library/food_library_page.dart` | [L8](file:///workspace/lib/features/food_library/food_library_page.dart#L8) | 是（L86-88: `FoodItemRepository(db)`） |
| 5 | `lib/features/weight/weight_page.dart` | [L9](file:///workspace/lib/features/weight/weight_page.dart#L9) | 否（用 recognize.weightLogRepoProvider） |
| 6 | `lib/features/recognize/calibration_page.dart` | - | 否（构造函数注入 FoodItemRepository） |
| 7 | `lib/features/recognize/dish_name_editor.dart` | [L15](file:///workspace/lib/features/recognize/dish_name_editor.dart#L15) | 否（仅 import FoodItem 类型） |
| 8 | `lib/features/dashboard/meal_edit_dialog.dart` | [L7](file:///workspace/lib/features/dashboard/meal_edit_dialog.dart#L7) | 否（仅 import 类型） |
| 9 | `lib/features/food_library/food_edit_page.dart` | [L6](file:///workspace/lib/features/food_library/food_edit_page.dart#L6) | 否（仅 import 类型） |
| 10 | `lib/features/manual_entry/manual_entry_page.dart` | [L6](file:///workspace/lib/features/manual_entry/manual_entry_page.dart#L6) | 否（仅 import 类型） |
| 11 | `lib/features/me/me_page.dart` | [L7](file:///workspace/lib/features/me/me_page.dart#L7) | 否（仅 import 类型） |

**最严重案例**：`dashboard_page.dart#L70-L73` 在 feature 层手动 new 三个 Repository：

```dart
final db = await ref.read(recognize.databaseProvider.future);
final foodRepo = FoodItemRepository(db);
final mealRepo = MealLogRepository(db);
final profileRepo = ProfileRepository(db);
```

**风险**：
- 测试时无法用 Provider override 替换 mock repo
- DB schema 变更需多文件同步修改
- 违反"feature 层只依赖 Repository 接口"的分层原则

**建议**：统一改用 `recognize.foodItemRepoProvider` / `recognize.mealLogRepoProvider` / `recognize.profileRepoProvider` 等 Provider 注入；类型 import 可改为从 repository 文件导出。

---

## 3.2 超长文件清单（>500 行）

**检查方式**：`find lib -name "*.dart" | xargs wc -l | sort -rn`，列出所有 >500 行的文件。

| # | 文件路径 | 行数 | 等级 | 备注 |
|---|---------|------|------|------|
| 1 | [lib/features/recognize/multi_dish_page.dart](file:///workspace/lib/features/recognize/multi_dish_page.dart) | 986 | P1 | UI + 业务 + 校准逻辑混合，可拆出 _CalcNutritionWidget / _CompositeEditor |
| 2 | [lib/features/dashboard/dashboard_page.dart](file:///workspace/lib/features/dashboard/dashboard_page.dart) | 948 | P1 | 含状态卡 + 推荐区 + 餐次列表三大块，可按 section 拆 widget |
| 3 | [lib/features/recognize/calibration_page.dart](file:///workspace/lib/features/recognize/calibration_page.dart) | 877 | P2 | 单页职责清晰但 UI 密度高，可抽 _QuantityStepper / _CompositeServingsEditor |
| 4 | [lib/features/insight/insight_page.dart](file:///workspace/lib/features/insight/insight_page.dart) | 821 | P2 | 多种图表 + 周期切换，可按图表类型拆 widget |
| 5 | [lib/features/recognize/recognize_page.dart](file:///workspace/lib/features/recognize/recognize_page.dart) | 740 | P2 | _pickAndRecognize 长方法（见 3.4-1） |
| 6 | [lib/features/dashboard/today_meals_page.dart](file:///workspace/lib/features/dashboard/today_meals_page.dart) | 736 | P2 | 含日期导航 + 列表 + 编辑弹窗 + 别名回流，可拆 |
| 7 | [lib/features/weight/weight_page.dart](file:///workspace/lib/features/weight/weight_page.dart) | 612 | P2 | 含图表 + 录入 + 历史，可拆 |
| 8 | [lib/features/profile/profile_page.dart](file:///workspace/lib/features/profile/profile_page.dart) | 577 | P2 | 表单字段多 |
| 9 | [lib/data/repositories/food_item_repository.dart](file:///workspace/lib/data/repositories/food_item_repository.dart) | 575 | P2 | findByNameOrAlias 6 级匹配逻辑长（设计合理，可加注释分段） |
| 10 | [lib/features/recognize/recognize_controller.dart](file:///workspace/lib/features/recognize/recognize_controller.dart) | 570 | P2 | _recognize 长方法（含 L1/L2/L3 兜底链） |
| 11 | [lib/core/widgets/m3_widgets.dart](file:///workspace/lib/core/widgets/m3_widgets.dart) | 534 | P2 | 公共组件库，按组件拆文件更佳 |
| 12 | [lib/features/offline/offline_queue_controller.dart](file:///workspace/lib/features/offline/offline_queue_controller.dart) | 517 | P2 | processPending 长方法（见 3.4-2） |

**统计**：>500 行文件 12 个，>800 行 4 个，>900 行 2 个。

---

## 3.3 重复代码（三路径 / 跨页面）

**检查方式**：人工比对 recognize_page / multi_dish_page / calibration_page / offline_queue_controller 三路径的写库 + 校准 + 改菜名逻辑。

### 发现 3.3-1【P2】三路径写库前哨兵检查代码块轻度重复

**严重等级**：P2（已有 DishNameEditor mixin 抽象改菜名，剩余重复可接受）

**问题**：三路径（recognize_page / multi_dish_page / offline_queue_controller）都需在写 meal_log 前检查 `foodItemId == 0` 哨兵并调 `upsertAiRecognized` 替换，代码结构相似但分支略有不同（recognize_page 是单品，multi_dish_page 含附加菜，offline_queue_controller 含复合菜），抽公共方法收益有限。

**证据**：
- [recognize_page.dart#L77](file:///workspace/lib/features/recognize/recognize_page.dart#L77)：`if (n.foodItemId == 0)` 哨兵检查
- [multi_dish_page.dart#L813](file:///workspace/lib/features/recognize/multi_dish_page.dart#L813)：同上
- [multi_dish_page.dart#L426](file:///workspace/lib/features/recognize/multi_dish_page.dart#L426)：复合菜路径哨兵
- [calibration_page.dart#L451](file:///workspace/lib/features/recognize/calibration_page.dart#L451)：校准页哨兵

**好的反例（已抽象）**：
- [dish_name_editor.dart](file:///workspace/lib/features/recognize/dish_name_editor.dart)（158 行）：`DishNameEditor<T extends StatefulWidget> on State<T>` mixin，被 `recognize_page` / `calibration_page` / `multi_dish_page` 复用，DRY 模式良好 ✅
- [calibrated_nutrition_calculator.dart](file:///workspace/lib/features/recognize/calibrated_nutrition_calculator.dart)（241 行）：`compute()` / `computeCompositeLookupHit()` 静态方法被三路径共享，per100g 反算逻辑统一 ✅

**建议**：哨兵检查重复可接受（分支差异大），维持现状。DishNameEditor / CalibratedNutritionCalculator 是良好抽象范本，未来新增类似跨页逻辑应优先抽 mixin / static helper。

---

## 3.4 TODO/FIXME/HACK 清单

**检查方式**：`grep -rn "TODO\|FIXME\|HACK\|XXX" lib/`

| 文件 | 行号 | 内容 |
|------|------|------|
| - | - | **无发现** ✅ |

全量代码无任何 TODO/FIXME/HACK/XXX 标记，代码整洁度高。

---

## 3.5 async gap（mounted 检查）

**检查方式**：人工读关键文件的所有 await 后是否检查 `mounted` / `context.mounted`。

### 结论：无发现 ✅

**抽检证据**（async gap 处理规范，全部满足）：

| 文件 | 行号 | 场景 | 处理 |
|------|------|------|------|
| [recognize_page.dart](file:///workspace/lib/features/recognize/recognize_page.dart#L568) | 568 | _pickAndRecognize finally | `if (mounted) setState(() => _isRecognizing = false)` ✅ |
| [recognize_page.dart](file:///workspace/lib/features/recognize/recognize_page.dart#L410) | 410 后 | `await Future.delayed(doneSuccessDwell)` 后 | `if (!mounted) return;` ✅ |
| [multi_dish_page.dart](file:///workspace/lib/features/recognize/multi_dish_page.dart#L971) | 971 | _confirmRecording finally | `if (mounted) setState(() => _isRecording = false)` ✅ |
| [calibration_page.dart](file:///workspace/lib/features/recognize/calibration_page.dart#L837) | 837 | _confirmOneClick finally | `if (mounted) setState(() => _isRecording = false)` ✅ |
| [offline_queue_controller.dart](file:///workspace/lib/features/offline/offline_queue_controller.dart#L98) | 98 | processPending 入口 | `if (_processing) return;` 防重入 ✅ |
| [dashboard_page.dart](file:///workspace/lib/features/dashboard/dashboard_page.dart#L165) | 165 | _regenerateAiRecommendations | `if (!mounted) return;` ✅ |
| [dashboard_page.dart](file:///workspace/lib/features/dashboard/dashboard_page.dart#L796) | 796 | _rateRecommendation | `final ok = await widget.onRate(rating); if (!mounted) return;` ✅ |
| [today_meals_page.dart](file:///workspace/lib/features/dashboard/today_meals_page.dart#L368) | 368-376 | Dismissible onDismissed | await 4s 后 `if (mounted)` 守卫 + 提前获取 repo 避免 widget 销毁后无法删 ✅ |
| [insight_page.dart](file:///workspace/lib/features/insight/insight_page.dart#L215) | 215 | _aggregatePeriod 后 | `if (!mounted) return;` ✅ |
| [weight_page.dart](file:///workspace/lib/features/weight/weight_page.dart#L434) | 434 | _record finally | `if (mounted) setState(() => _busy = false)` ✅ |
| [food_edit_page.dart](file:///workspace/lib/features/food_library/food_edit_page.dart#L179) | 179 | _save finally | `if (mounted) setState(() => _busy = false)` ✅ |
| [update_page.dart](file:///workspace/lib/features/update/update_page.dart#L56) | 56,76,98,110,121,130 | _check/_download/_install | 全部 `if (!mounted) return;` + `if (mounted) _busy = false` ✅ |

**特别说明**：`today_meals_page.dart#L333-L335` 有优秀注释解释"为何 await 前先获取 repo"——避免 widget 销毁后 DB delete 无法执行导致记录"复活"，体现工程师对 async gap 的深入理解。

---

## 3.6 写库按钮防重入

**检查方式**：grep `_busy` / `_isRecording` / `_isRecognizing` / `_aiRegenerating` / `_processing`，逐个核对"防重入守卫 + setState busy + finally 释放"三件套。

### 结论：无发现 ✅

**抽检证据**（6 个写库路径全部满足三件套）：

| 文件 | 字段 | 守卫行 | setState 行 | finally 释放行 |
|------|------|--------|------------|---------------|
| [recognize_page.dart](file:///workspace/lib/features/recognize/recognize_page.dart#L381) | `_isRecognizing` | L381 `if (_isRecognizing) return;` | L384 `setState(() => _isRecognizing = true)` | L568 `if (mounted) setState(() => _isRecognizing = false)` ✅ |
| [multi_dish_page.dart](file:///workspace/lib/features/recognize/multi_dish_page.dart#L779) | `_isRecording` | L779 `if (_isRecording) return;` | L780 `setState(() => _isRecording = true)` | L971 `if (mounted) setState(() => _isRecording = false)` ✅ |
| [calibration_page.dart](file:///workspace/lib/features/recognize/calibration_page.dart#L764) | `_isRecording` | L764 `if (_isRecording) return;` | L765 `setState(() => _isRecording = true)` | L837 `if (mounted) setState(() => _isRecording = false)` ✅ |
| [today_meals_page.dart](file:///workspace/lib/features/dashboard/today_meals_page.dart#L525) | `_busy` | L525 `if (_busy) return;` | L536 `setState(() => _busy = true)` | L558 `if (mounted) setState(() => _busy = false)` ✅ |
| [food_edit_page.dart](file:///workspace/lib/features/food_library/food_edit_page.dart#L160) | `_busy` | L160,184 `if (_busy) return;` | L166,198 `setState(() => _busy = true)` | L179,218 `if (mounted) setState(() => _busy = false)` ✅ |
| [weight_page.dart](file:///workspace/lib/features/weight/weight_page.dart#L383) | `_busy` | L383,475 `if (_busy) return;` | L391 `setState(() => _busy = true)` | L434 `if (mounted) setState(() => _busy = false)` ✅ |
| [manual_entry_page.dart](file:///workspace/lib/features/manual_entry/manual_entry_page.dart#L227) | `_busy` | L227,266 `if (_busy) return;` | L234,285 `setState(() => _busy = true)` | L261,333 `if (mounted) setState(() => _busy = false)` ✅ |
| [backup_page.dart](file:///workspace/lib/features/backup/backup_page.dart#L35) | `_busy` | L35,41 `_busy ? null : ...`（按钮 disable） | L97,164 `setState(() => _busy = true)` | L115,179 `if (mounted) setState(() => _busy = false)` ✅ |
| [update_page.dart](file:///workspace/lib/features/update/update_page.dart#L47) | `_busy` | L47,81,116 `if (_busy) return;` | L49,85,117 `setState(() => _busy = true)` 或 `_busy = true` | L76,110,130 `if (mounted) _busy = false` ✅ |
| [dashboard_page.dart](file:///workspace/lib/features/dashboard/dashboard_page.dart#L161) | `_aiRegenerating` | L161 `if (_aiRegenerating) return;` | L162 `setState(() => _aiRegenerating = true)` | L178 `if (mounted) setState(() => _aiRegenerating = false)` ✅ |

**特别说明**：`backup_page.dart` 用 `_busy ? null : () => _export()` 直接 disable 按钮，比 `if return` 更优（按钮变灰给用户视觉反馈）。`update_page.dart` 三个方法（_check/_download/_install）共享同一 `_busy` 字段，互斥严格。

---

## 3.7 Riverpod 用法

**检查方式**：人工核对 Provider 定义、ConsumerStatefulWidget 用法、ProviderContainer 生命周期。

### 结论：无发现 ✅

**抽检证据**：

| 检查项 | 文件 | 行号 | 状态 |
|--------|------|------|------|
| ProviderContainer 单例（不 dispose） | [main.dart](file:///workspace/lib/main.dart#L66) | 66 | ✅ 与 app 生命周期一致 |
| FutureProvider 用于异步资源 | [database.dart](file:///workspace/lib/data/database/database.dart#L114) | 114 | ✅ `databaseProvider = FutureProvider<EatWiseDatabase>` |
| FutureProvider 用于 repo | [providers.dart](file:///workspace/lib/features/recognize/providers.dart#L64) | 64-72 | ✅ foodItemRepoProvider / mealLogRepoProvider |
| `ref.read(provider.future)` 异步获取 | dashboard_page.dart | 多处 | ✅ 标准 FutureProvider 用法 |
| ConsumerStatefulWidget 用于需要 ref 的页面 | dashboard_page.dart / today_meals_page.dart 等 | - | ✅ |
| `ref.onDispose(db.close)` 资源释放 | [database.dart](file:///workspace/lib/data/database/database.dart#L117) | 117 | ✅ |
| Provider override 仅在 main.dart 测试用 | [main.dart](file:///workspace/lib/main.dart#L60) | 60 | ✅ |

**说明**：项目用 Riverpod 3.x，未见已废弃的 StateNotifier（已迁移至 legacy.dart）。Provider 命名规范统一（xxxProvider 后缀）。

---

## 3.8 错误处理

**检查方式**：`grep "catch\s*\(\s*_\s*\)" lib/` 全量扫描，逐个核对上下文是否有 Sentry 上报 / 用户提示 / 日志记录。

### 发现 3.8-1【P2】部分 silent catch (_) 缺少 Sentry 上报，仅 best-effort 注释

**严重等级**：P2（多数有注释说明意图，但缺少可观测性）

**问题**：全量 40 处 `catch (_)` 中，多数为合理的 best-effort 模式（断路器持久化、月度计数、别名回流等），但部分关键路径仅 `debugPrint` 或纯静默，未上报 Sentry，生产环境异常不可观测。

**统计**（40 处分类）：

| 类别 | 数量 | 是否合理 | 典型文件 |
|------|------|---------|---------|
| 断路器 / 月度计数 best-effort（有注释） | 8 | ✅ 合理 | recognize_controller.dart#L301,L385,L414 |
| 日期解析 fallback（返回默认值） | 6 | ✅ 合理 | today_meals_page.dart#L89,L103,L161,L179 |
| L1/L2 重试链 rethrow 前 catch | 6 | ✅ 合理 | recognize_controller.dart#L272,L277,L290 |
| 资源获取失败 + toast 提示用户 | 4 | ✅ 合理 | today_meals_page.dart#L338（toast） |
| DB seed 导入失败 fallback | 1 | ✅ 合理 | database.dart#L103（注释说明测试环境） |
| AI 推荐 v4 兜底（debugPrint） | 3 | ⚠️ 缺 Sentry | dashboard_page.dart#L149（仅 debugPrint） |
| 备份 / 图片清理 best-effort | 5 | ⚠️ 缺 Sentry | data/backup/auto_backup.dart#L35,L53,L78 |
| 别名回流 best-effort | 1 | ⚠️ 缺 Sentry | today_meals_page.dart#L714 |
| 其他 | 6 | ⚠️ 需个案评估 | settings_page.dart / off_provider.dart 等 |

**典型问题案例**：
- [dashboard_page.dart#L149](file:///workspace/lib/features/dashboard/dashboard_page.dart#L149)：AI 推荐加载异常仅 `debugPrint('AI 推荐加载异常（v4 兜底）：$e')`，生产环境无法观测 AI 推荐失败率
- [auto_backup.dart#L35](file:///workspace/lib/data/backup/auto_backup.dart#L35)：自动备份失败纯静默，用户数据可能丢失无告警
- [today_meals_page.dart#L714](file:///workspace/lib/features/dashboard/today_meals_page.dart#L714)：别名回流失败纯静默，注释"best-effort"但无 Sentry

**对比良好案例**：
- [offline_queue_controller.dart#L486-L489](file:///workspace/lib/features/offline/offline_queue_controller.dart#L486)：`catch (e, st) { _onError(e, st); }` 其中 `_onError` 默认调 `Sentry.captureException` ✅
- [main.dart#L127](file:///workspace/lib/main.dart#L127)：`Sentry.captureException(error, stackTrace: stack)` ✅

**建议**：关键路径（备份、AI 推荐、别名回流）的 silent catch 应补 `Sentry.captureException(e, stackTrace: st)` 或调统一 `_onError`，保留可观测性。

---

## 3.9 硬编码

**检查方式**：`grep "Colors\.\(white\|black\|red\|green\|blue\|grey\|orange\|yellow\|transparent\)" lib/`，逐个核对是否绕过 colorScheme。

### 发现 3.9-1【P2】recognize_progress_card.dart 用 Colors.white / Colors.transparent 硬编码

**严重等级**：P2（场景合理但未用 colorScheme.onPrimary）

**问题**：[recognize_progress_card.dart#L204](file:///workspace/lib/features/recognize/recognize_progress_card.dart#L204) 和 [L212](file:///workspace/lib/features/recognize/recognize_progress_card.dart#L212) 用 `Colors.white` 作为进度圈和勾选图标颜色，背景是 `colorScheme.primary`（见 L170）。MD3 规范应用 `colorScheme.onPrimary` 保证对比度跟随主题变化（深色主题下 onPrimary 可能非纯白）。

**证据**：
```dart
// L204
valueColor: AlwaysStoppedAnimation(Colors.white),
// L212
color: Colors.white,
```

**风险**：若未来 primary 色调整为浅色，`Colors.white` 在浅色背景上对比度不足。

**建议**：改为 `colorScheme.onPrimary`（需将 colorScheme 传入 _buildChild，或提升为成员变量）。

### 发现 3.9-2【P2】settings_page.dart 用 Colors.black / Colors.white 设置状态栏图标色

**严重等级**：P2（平台 API 限制，可接受）

**证据**：[settings_page.dart#L440-L441](file:///workspace/lib/features/settings/settings_page.dart#L440)
```dart
? Colors.black
: Colors.white,
```

**说明**：这是 `SystemUiOverlayStyle` 设置状态栏图标亮度，Flutter API 仅接受 `Brightness.light/dark` 或具体 Color，此处用 Colors.black/white 是常见做法，可接受。

### 发现 3.9-3【无发现】app.dart 用 Colors.transparent

**说明**：[app.dart#L99](file:///workspace/lib/app.dart#L99) 和 [L175](file:///workspace/lib/app.dart#L175) 用 `surfaceTintColor: Colors.transparent` 是禁用 MD3 surface elevation tint 的标准模式，合理 ✅

---

## 3.10 命名一致性

**检查方式**：人工读关键文件，核对 provider / class / method / 字段命名。

### 结论：无发现 ✅

**抽检证据**：

| 检查项 | 状态 | 证据 |
|--------|------|------|
| Provider 命名 xxxProvider 后缀 | ✅ | databaseProvider / foodItemRepoProvider / mealLogRepoProvider / appConfigProvider / networkAvailableProvider |
| Repository 命名 XxxRepository | ✅ | FoodItemRepository / MealLogRepository / ProfileRepository / PendingRecognitionRepository / WeightLogRepository / RecommendationFeedbackRepository |
| State 类命名 XxxState / XxxUiState | ✅ | RecognizeUiState / DashboardData / AiRecommendationResult |
| 私有字段 _camelCase | ✅ | _busy / _isRecording / _isRecognizing / _aiRegenerating / _processing |
| 常量 kCamelCase 或全大写 | ✅ | lookupMinDwell / doneSuccessDwell（私有常量）/ _dbName |
| 枚举值 camelCase | ✅ | RecognizeState.pickingImage / preprocessing / recognizing / lookupNutrition / done |
| 三路径字段命名一致 | ✅ | 三路径均用 `_isRecording` 或 `_isRecognizing`（语义对应：识别 vs 写库） |
| 中文注释 + 英文标识符 | ✅ | 与项目规则一致 |

**特别说明**：`recognize_page.dart` 用 `_isRecognizing`（识别+写库全流程），`multi_dish_page.dart` / `calibration_page.dart` 用 `_isRecording`（仅写库），`dashboard_page.dart` 用 `_aiRegenerating`（AI 推荐重生成）—— 语义对应各自场景，非命名不一致。

---

## 4. 圈复杂度（长方法）

**检查方式**：人工读关键文件的长方法，估算圈复杂度。

### 发现 4-1【P1】recognize_page._pickAndRecognize 长方法 ~190 行

**严重等级**：P1（单方法 190 行，含 try-catch-finally + 多个 await + 状态机切换）

**证据**：[recognize_page.dart#L380-L568](file:///workspace/lib/features/recognize/recognize_page.dart#L380)
- L380: 方法开始
- L396-L403: try + controller.addListener + try-finally removeListener
- L503-L531: onConfirm callback 含多个 await（mealRepo / foodRepo / upsertAiRecognized / mealLog write）
- L568: finally 释放 _isRecognizing

**问题**：单方法承担"选图 → 识别 → 展示结果 → 等待用户确认 → 写库 → 离线入队"全流程，圈复杂度高，测试覆盖难。

**建议**：拆分为 `_pickImage` / `_runRecognize` / `_showResultAndWaitConfirm` / `_writeMealLog` 四个子方法，主方法只做编排。

### 发现 4-2【P1】offline_queue_controller.processPending 长方法 ~396 行

**严重等级**：P1（单方法 396 行，是项目最长方法）

**证据**：[offline_queue_controller.dart#L97-L493](file:///workspace/lib/features/offline/offline_queue_controller.dart#L97)
- L97: 方法开始
- L107-484: `for (final p in pending)` 循环，每条 pending 含图片读取 + 断路器检查 + 识别 + 查库回填 + 哨兵替换 + 写 meal_log + 标记 done/failed 多个分支
- L162-260: 单品路径（含 foodItemId=0 哨兵处理）
- L261-432: 复合菜路径（含组分份量校准）
- L486-489: 外层 catch + Sentry 上报

**问题**：单方法承担"遍历 pending → 逐条重识别 → 查库 → 哨兵替换 → 写库 → 状态更新"全流程，圈复杂度极高，单品/复合菜两条路径在同一方法内嵌套，维护困难。

**建议**：拆分为 `_processSingleItem(p)` / `_processComposite(p)` 两个子方法，主方法只做遍历和分发。

### 发现 4-3【P2】multi_dish_page._calcNutrition 长方法 ~100 行 + 深嵌套

**严重等级**：P2

**证据**：[multi_dish_page.dart#L627-L727](file:///workspace/lib/features/recognize/multi_dish_page.dart#L627)
- 含多个 if-else 分支（单品/复合菜/附加菜）
- 嵌套层级达 4-5 层

**建议**：抽 `_calcSingleNutrition` / `_calcCompositeNutrition` / `_calcAdditionalNutrition` 三个子方法。

---

## 5. 维度 3 汇总

### 5.1 发现总数与分级

| 等级 | 数量 | 列表 |
|------|------|------|
| **P0** | 0 | 无（6 个硬约束全部满足） |
| **P1** | 4 | 3.1-1 跨层依赖 / 3.2-1 multi_dish_page 986 行 / 3.2-2 dashboard_page 948 行 / 4-1 _pickAndRecognize 长方法 / 4-2 processPending 长方法 |
| **P2** | 16 | 3.2-3 至 3.2-12（10 个超长文件）/ 3.3-1 三路径哨兵重复 / 3.8-1 silent catch 缺 Sentry / 3.9-1 Colors.white 硬编码 / 3.9-2 状态栏图标色 / 4-3 _calcNutrition 长方法 |

**P1 实际为 5 项**（4-1 和 4-2 单列），上表合并计数修正：

| 等级 | 数量 |
|------|------|
| **P0** | 0 |
| **P1** | 5 |
| **P2** | 16 |
| **总计** | 21 |

### 5.2 整体评价

**整体质量：良好（B+）**

**优点**：
1. **6 个硬约束全部满足**，无 P0 级架构性风险
2. **写库按钮防重入** 10 个路径全部满足三件套（守卫 + setState + finally 释放），代码规范度极高
3. **async gap mounted 检查** 全覆盖，部分文件有优秀注释解释设计意图（如 today_meals_page.dart#L333-L335）
4. **TODO/FIXME/HACK 零标记**，代码整洁度高
5. **DishNameEditor mixin / CalibratedNutritionCalculator** 体现了良好的 DRY 抽象意识
6. **三路径哨兵检查**（硬约束 2/3）全覆盖，无外键约束违规风险
7. **per100g 反算**（硬约束 4）严格基于 `estimatedWeightGMid` / `actualServingG`，无密度反向偏差
8. **Riverpod 用法** 规范，ProviderContainer 生命周期正确，无 StateNotifier 残留

**不足**：
1. **跨层依赖**（P1）：11 个 feature 文件直接 import database.dart，其中 4 个还手动 new Repository，破坏分层，影响可测试性
2. **长方法**（P1）：processPending 396 行、_pickAndRecognize 190 行，圈复杂度高，维护困难
3. **超长文件**（P1/P2）：12 个文件 >500 行，2 个 >900 行，需按职责拆分
4. **错误处理可观测性**（P2）：部分 silent catch 缺 Sentry 上报，生产环境异常不可观测
5. **硬编码颜色**（P2）：recognize_progress_card 用 Colors.white 而非 colorScheme.onPrimary

**优先修复建议**：
1. P1：拆分 `processPending` 和 `_pickAndRecognize` 长方法
2. P1：统一 feature 层用 Repository Provider，移除直接 new Repository
3. P1：拆分 multi_dish_page.dart / dashboard_page.dart 超长文件
4. P2：关键路径 silent catch 补 Sentry 上报
5. P2：recognize_progress_card Colors.white 改为 colorScheme.onPrimary

---

## 6. 审查方法说明

- **静态扫描**：grep / wc -l / find 全量扫描
- **人工读关键文件**：recognize_page / multi_dish_page / calibration_page / offline_queue_controller / recognize_controller / dashboard_page / today_meals_page / weight_page / food_edit_page / manual_entry_page / backup_page / update_page / dish_name_editor / calibrated_nutrition_calculator / providers / database / connection / main / sentry_init / secure_config_store / recognize_progress_card
- **硬约束验证**：6 项逐条 grep + 人工核对
- **审查范围**：`/workspace/lib` 全量（不含 test/ 和 android/，android/ 仅核对 build.gradle.kts 硬约束 1）

---

**审查完成时间**：2026-07-05
**审查员**：维度 3 审查员（GLM-5.2）
**报告路径**：`/workspace/docs/audit/m23-dim3-quality.md`
