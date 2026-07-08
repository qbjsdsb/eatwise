# P0-D1: 6+1 硬约束回归核查

## 检查日期 / HEAD commit

- **检查日期**：2026-07-08
- **HEAD commit**：`bb308735ff068c9e03b64340e934747a1fe5c8a7`（`bb30873 fix(build): 修复 build_runner 失败——sqlparser 0.44.5 override + 重新生成 database.g.dart`）
- **git status**：clean（无未提交改动）
- **核查范围**：`.trae/rules/project_handoff.md` 列出的 7 条硬约束，按任务要求拆解为 9 项核查条目
- **规则文件一致性**：`project_handoff.md` 实际枚举 **7 条**硬约束（编号 1-7）。任务描述将其拆为 9 项（#1/#7/#8/#9 拆自 build.gradle 相关；其中 #9 与 #1 同源、#8 abiFilters 属 M27 APK 体积优化决策而非规则文件明列的硬约束）。本报告按任务要求逐项核查并标注映射关系。

## 硬约束合规矩阵

| # | 约束条目 | 验证文件 | 实际值 | 合规状态 | 备注 |
|---|---------|---------|--------|---------|------|
| 1 | `isMinifyEnabled = false` + `isShrinkResources = false` | `android/app/build.gradle.kts:70-71` | `isMinifyEnabled = false` / `isShrinkResources = false` | ✅ 合规 | release buildType 内，注释说明 R8 会剥 sentry/workmanager 反射类 |
| 2 | `meal_log.food_item_id` 非空外键 + PRAGMA foreign_keys=ON + 哨兵替换 | `lib/data/database/tables/meal_log_table.dart:9`、`lib/data/database/database.dart:79`、`lib/data/repositories/meal_log_repository.dart:28-30,102-104` | 列定义为 `integer().references(FoodItems, #id)()`（无 `.nullable()`，非空+FK）；启动执行 `PRAGMA foreign_keys = ON;`；insert/update 均有 `foodItemId <= 0` 哨兵防御抛 `ArgumentError` | ✅ 合规 | 哨兵替换由三路径 `upsertAiRecognized` 完成（见 #3） |
| 3 | AI 兜底三路径全部覆盖 `upsertAiRecognized` | `lib/features/recognize/recognize_page.dart:105,154`、`lib/features/recognize/multi_dish_page.dart:379,453,482`、`lib/features/offline/offline_queue_controller.dart:327,414,473,511,527` | 三路径均调用 `upsertAiRecognized` 替换哨兵为真实 id 后再写 meal_log | ✅ 合规 | recognize_page 2 处（单品+复合菜）、multi_dish_page 3 处、offline_queue_controller 5 处（含单品/复合/后台回补） |
| 4 | per100g 反算基于 `estimatedWeightGMid`，不能用 `servingG` | `lib/features/recognize/calibrated_nutrition_calculator.dart:46-49`、`lib/features/recognize/multi_dish/nutrition_preview.dart:86`、`lib/features/offline/offline_queue_controller.dart:387-388` | `final mid = r.estimatedWeightGMid; final per100Ratio = mid > 0 ? 100.0 / mid : 0.0;` per100g 反算基准为 mid；`servingG` 仅用于 `actualXxx = per100g * servingG / 100` 终值缩放 | ✅ 合规 | per100g 反算（写食物库）与 actualXxx 缩放（写 meal_log）职责分离正确 |
| 5 | `SecureConfigStore` 无 `instance` 静态属性 | `lib/core/config/secure_config_store.dart:14-37`；全仓 grep `SecureConfigStore.instance` | 类无 `static instance`；仅有 `static const` 存储 key 常量；构造函数 `SecureConfigStore()`；调用方均用 `SecureConfigStore()` 或 `container.read(secureConfigStoreProvider)` | ✅ 合规 | grep `SecureConfigStore.instance` 零匹配 |
| 6 | `initSentryAndRunApp` 命名参数 `container:` + `app:` | `lib/core/error/sentry_init.dart:15-18`、`lib/main.dart:75-81` | 签名 `Future<Widget> initSentryAndRunApp({ required ProviderContainer container, required Widget app, })`；main.dart 调用 `initSentryAndRunApp(container: container, app: UncontrolledProviderScope(...))` | ✅ 合规 | 命名参数 + required，调用方一致 |
| 7 | `minSdk = 31` | `android/app/build.gradle.kts:25` | `minSdk = 31` | ✅ 合规 | 注释说明 dynamic_color 需 Android 12+ |
| 8 | `abiFilters = arm64-v8a` | `android/app/build.gradle.kts:34-36` | `ndk { abiFilters += "arm64-v8a" }` | ✅ 合规 | 属 M27 APK 体积优化（87MB→~30MB），规则文件未明列为硬约束但实际生效 |
| 9 | `isMinifyEnabled=false` + `isShrinkResources=false`（同 #1） | `android/app/build.gradle.kts:70-71` | 同 #1 | ✅ 合规 | 与 #1 同源，重复核查通过 |

**合规汇总**：9/9 项全部合规，无违规。

## 发现的问题

无 P0 / P1 / P2 级别问题。本次核查未发现任何硬约束违规。

## 额外发现（TODO/FIXME 扫描结果）

- **`lib/` 目录扫描**：grep `TODO|FIXME|HACK|XXX` 在 `lib/` 下 **零匹配**，代码无遗留未完成标记。
- **`android/app/build.gradle.kts:21`**：存在一处 `// TODO: Specify your own unique Application ID`，属 Flutter 项目模板默认注释（applicationId 已实际配置为 `com.eatwise.eatwise`），非功能性遗留，不影响合规。
- **规则文件与实际代码一致性**：`project_handoff.md` 列出 7 条硬约束，逐条比对实际代码全部一致。规则文件未将 `abiFilters = arm64-v8a`（M27 优化）列为硬约束，但该配置在 build.gradle.kts 中实际生效；建议后续视情况决定是否补入规则文件（非阻塞）。

## 结论

EatWise 项目当前 HEAD（commit `bb30873`）**9 项硬约束核查条目全部合规**，无 P0/P1/P2 违规。具体结论：

1. **构建配置（#1/#7/#8/#9）**：`isMinifyEnabled=false`、`isShrinkResources=false`、`minSdk=31`、`abiFilters=arm64-v8a` 均按约束配置，R8 不会剥除 sentry/workmanager 反射类。
2. **数据完整性（#2）**：`meal_log.food_item_id` 为非空外键，`PRAGMA foreign_keys=ON` 启用，repository 层 insert/update 双重哨兵防御（`foodItemId<=0` 抛 `ArgumentError`），杜绝哨兵 0 写入致 FK 约束违规崩溃。
3. **AI 兜底覆盖（#3）**：recognize_page / multi_dish_page / offline_queue_controller 三路径共 10 处 `upsertAiRecognized` 调用，哨兵替换链路完整。
4. **营养反算（#4）**：per100g 反算基准统一为 `estimatedWeightGMid`（`per100Ratio = 100.0 / mid`），`servingG` 仅用于 actualXxx 终值缩放，密度不会随用户校准份量反向偏差。
5. **配置存储（#5）**：`SecureConfigStore` 无 `instance` 静态属性，全部走构造函数或 provider 注入。
6. **Sentry 初始化（#6）**：`initSentryAndRunApp` 签名与调用均为命名参数 `container:` + `app:`。
7. **代码整洁度**：`lib/` 下无 TODO/FIXME/HACK/XXX 残留。

**回归结论**：本次 P0-D1 硬约束回归核查通过，无需修复，可继续后续工作。
