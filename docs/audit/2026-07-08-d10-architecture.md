# D10 架构维度检查报告

**检查日期**：2026-07-08
**检查范围**：EatWise v0.33.0+46（lib/ 全量 + pubspec.yaml + 关键测试文件抽样）
**HEAD commit**：`b140745`（`feat: 了解项目进展`）
**git status**：lib/ 无改动；`docs/audit/` 下存在 D5–D9 未跟踪报告（本次新增 D10）
**检查方法**：LS lib/ 全量目录树 + Grep（`ref.read`/`ref.watch`/`import 'package:eatwise/(features|nutrition|ai)/'`/`Repository\(`/`catch \(_\)`/`StateNotifier|ChangeNotifier|NotifierProvider`/`autoDispose`/`ConsumerStatefulWidget|ConsumerWidget`/`recognize\.databaseProvider`/`import '.*recognize/providers\.dart'`）+ 关键文件通读（`main.dart`、`app.dart`、`main_shell.dart`、`features/recognize/providers.dart`、`features/recognize/recognize_controller.dart`、`features/recognize/recognize_page.dart`、`features/offline/offline_queue_controller.dart`、`background/background_dispatcher.dart`、`data/repositories/{food_item,meal_log,insight,recommendation_feedback}_repository.dart`、`nutrition/{tdee_calibrator,recommendation_service,ai_recommendation_service}.dart`、`core/config/app_config.dart`、`core/error/sentry_init.dart`、`core/util/refresh_bus.dart`、`features/{dashboard/dashboard_page,insight/insight_page,settings/settings_page,profile/profile_page,weight/weight_page,food_library/food_library_page,backup/backup_page,manual_entry/manual_entry_page,recognize/multi_dish_page,recognize/circuit_breaker,profile/nutrition_calculator}.dart` 等）+ 既有 M23 维度 3 报告对照

> 方法论备注：本审计的"统计结论"以 Grep `content` 模式（带行号、可回溯原文）和直接 Read 文件的结果为准。`catch (_)` 43 处 / `ref.read` 103 处 / `ref.watch` 22 处等计数均来自 `count` 模式且与 `content` 模式抽样复核一致。

---

## 总体评价

EatWise 的架构基线**整体健康，处于"分层清晰但执行不彻底"的中间状态**。项目建立了 `data/database + data/repositories + features + core + ai + nutrition + background` 七层目录骨架，Repository 模式统一（8 个 Repository 类签名一致、构造器注入 `EatWiseDatabase`），Riverpod 已升级到 3.3.1，关键 Service（RecognizeController / OfflineQueueController / AiRecommendationService）均采用构造器注入便于测试 mock，主流程依赖方向基本单向（UI → Provider → Repository → DB）。

但执行层面存在 4 个系统性偏差：(1) **`features/recognize/providers.dart` 演化为全应用"上帝 Provider 桶"**——12 个 feature 文件依赖它，`recognize` feature 实际承担了全局 DI 容器角色；(2) **Riverpod 退化为服务定位器**——16 个 `ConsumerStatefulWidget` + 1 个 `ConsumerWidget`，`ref.read`（103 次）vs `ref.watch`（22 次）≈ 5:1，多数页面用 `Future + setState` 管理状态而非 `FutureProvider + ref.watch`；(3) **两处反向依赖**——`background/` → `features/recognize/circuit_breaker` + `features/offline/offline_queue_controller`，`nutrition/tdee_calibrator` → `features/profile/nutrition_calculator`，根因是业务逻辑类（CircuitBreaker / NutritionCalculator / CalibratedNutritionCalculator / OfflineQueueController）错放在 `features/` 下；(4) **领域 Service 全部无 Provider 管理**——`RecommendationService` / `AiRecommendationService` / `TdeeCalibrator` 在 UI 层 `new` 创建，且 `TdeeCalibrator` 直接持 `EatWiseDatabase` 绕过 Repository。

无 P0 架构崩坏（项目能正常编译运行，6 硬约束满足，无编译期循环依赖）；8 项 P1 集中在"上帝模块 / 反向依赖 / Riverpod 退化 / Service 无 DI"；7 项 P2 多为"无 domain 层 / Repository 暴露 Drift 实体 / catch(_) 无日志 / StateNotifier legacy 未迁移"等渐进式重构项。**整体健康度评级：B（中等偏上）**——比 M23 时的 B+ 略有下降，原因是 M24 B1 修复"直接 import database.dart"后留下了"`recognize.databaseProvider` 仍可被 UI 直接访问"的半修复，且本次新发现 nutrition→features、background→features 两处反向依赖。

---

## 一、分层结构现状

```
lib/
├── ai/                      # AI 视觉适配层（9 文件：glm_4v/qwen_vl/glm_flash/off_provider/nutrition_lookup/prompts/vision_provider/...）
│   └── vision_provider.dart # abstract class VisionProvider（QwenVlProvider/Glm4vProvider implements）
├── background/              # 后台任务（独立 isolate，2 文件）
│   ├── background_dispatcher.dart  # callbackDispatcher，硬 new 全部依赖（isolate 限制）
│   └── background_tasks.dart
├── core/                    # 跨层基础设施
│   ├── config/              # app_config / secure_config_store / app_version_provider
│   ├── error/               # sentry_init / sentry_scrub
│   ├── theme/               # theme_controller（NotifierProvider 新 API）
│   ├── update/              # 应用内更新（6 文件）
│   ├── util/                # date_format / food_name / image_quality_checker / recognition_post_processor / recognition_validator / refresh_bus
│   └── widgets/             # m3_widgets（LoadingState/ErrorState/EmptyState 等公共组件）
├── data/
│   ├── database/            # Drift（database.dart + database.g.dart + tables/ 8 表 + connection.dart）
│   ├── repositories/        # 8 个 Repository（food_item/meal_log/profile/weight_log/pending_recognition/insight/recognition_feedback/recommendation_feedback）
│   ├── backup/              # auto_backup / image_cleanup / json_exporter / json_importer
│   ├── bluetooth/           # mi_scale_parser / mi_scale_scanner
│   └── seed/                # food_seed_importer / food_category_defaults / sanotsu_categories
├── features/                # UI 页面（16 ConsumerStatefulWidget + 1 ConsumerWidget）
│   ├── recognize/           # ⚠️ 含 providers.dart（全应用 Provider 桶）+ circuit_breaker + calibrated_nutrition_calculator（业务逻辑错放）
│   ├── offline/             # ⚠️ 含 offline_queue_controller（业务编排错放，被 background 反向依赖）
│   ├── profile/             # ⚠️ 含 nutrition_calculator（纯函数类错放，被 nutrition 反向依赖）
│   ├── dashboard/           # dashboard_page + dashboard/ 子目录（dashboard_data + 5 section widget）
│   ├── food_library/ / insight/ / manual_entry/ / me/ / records/ / settings/ / update/ / weight/ / backup/
├── nutrition/               # 领域服务层（recommendation_service / ai_recommendation_service / tdee_calibrator / body_fat_calculator / dish_name_normalizer / food_profile_tagger / user_preference_learner）
├── main.dart                # 入口（runZonedGuarded + 单 ProviderContainer + Sentry + Workmanager + OfflineQueue）
├── app.dart                 # EatWiseApp（ConsumerWidget）+ GoRouter 路由表
└── main_shell.dart          # 底部导航壳（StatefulWidget + RefreshBus）
```

**关键观察**：

1. **无独立 `lib/domain/` 层**——domain 实体由 Drift 生成在 `database.g.dart` 中，被 5 个 Repository 通过 `export ... show XxxEntity;` 直接暴露给 UI。`lib/nutrition/` 部分承担领域服务职责，但直接 `import 'package:eatwise/data/database/database.dart'` + `import 'package:eatwise/data/repositories/...'`，无 domain entity 抽象。
2. **`features/` 目录被污染**——`recognize/providers.dart`（Provider 桶）、`recognize/circuit_breaker.dart`（断路器状态机）、`recognize/calibrated_nutrition_calculator.dart`（营养计算）、`offline/offline_queue_controller.dart`（后台回补编排）、`profile/nutrition_calculator.dart`（BMR/TDEE 公式）均是非 UI 的业务/工具逻辑，错放在 `features/` 下，导致 `background/` 和 `nutrition/` 反向依赖 `features/`。
3. **Provider 定义分散在 5 个文件**——`data/database/database.dart`（databaseProvider）、`features/recognize/providers.dart`（17 个 Provider，最大桶）、`core/config/app_version_provider.dart`、`core/theme/theme_controller.dart`、`core/config/app_config.dart`。无 `lib/core/providers/` 或 `lib/providers/` 统一存放。

---

## 二、8 项检查清单逐项分析

| # | 检查项 | 结论 | 关键证据 |
|---|--------|------|---------|
| 1 | 分层清晰度（data/domain/presentation 边界；跨层调用） | ⚠️ 部分 | data/features/core/ai/nutrition 五层目录存在；无独立 domain 层；UI 通过 `recognize.databaseProvider` 直接访问 db（5 文件）；`background/` + `nutrition/` 反向依赖 `features/` |
| 2 | 依赖方向（UI→repository→database 单向；反向依赖） | ⚠️ 两处反向 | UI→Provider→Repository→DB 基本单向；`background_dispatcher.dart:15-16` import `features/recognize/circuit_breaker` + `features/offline/offline_queue_controller`；`nutrition/tdee_calibrator.dart:5` import `features/profile/nutrition_calculator` |
| 3 | Riverpod 使用规范（命名/类型/ref.read/watch/autoDispose） | ⚠️ 退化 | 命名 `xxxProvider` 统一；类型选择合理（FutureProvider 异步 / Provider 同步 / NotifierProvider 新 API）；`ref.read` 103 次 vs `ref.watch` 22 次（5:1）；autoDispose 仅 5 处；RecognizeController 不用 Provider 管理 |
| 4 | Repository 模式（统一/暴露实体/DTO 转换） | ✅ 基本统一 | 8 个 Repository 签名一致（持 `_db` + 构造器注入）；5 个 `export ... show XxxEntity;` 暴露 Drift 实体（food_item/meal_log/pending_recognition/weight_log/profile），3 个不 export（insight/recognition_feedback/recommendation_feedback 用 typedef 或不暴露）；无 DTO 转换 |
| 5 | 错误处理（统一/try-catch 层次/异常吞没） | ⚠️ 不统一 | 无统一 Result/Either 或 AppException；`catch (_)` 43 处（recognize_controller 6 处 best-effort 合理；UI 层多处有 `_loadError` + ErrorState 但无日志）；main.dart `runZonedGuarded` + Sentry 顶层兜底完善 |
| 6 | 状态管理（StateNotifier vs ChangeNotifier/不可变/setState vs Provider） | ⚠️ 退化 | RecognizeController 用 legacy `StateNotifier`（`import 'package:flutter_riverpod/legacy.dart'`）；RefreshBus 单例 `ChangeNotifier` 绕过 Riverpod；16 ConsumerStatefulWidget + 1 ConsumerWidget；insight_page 30+ setState 字段 |
| 7 | 模块耦合（feature 间 import/循环依赖） | ⚠️ 上帝模块 | 12 文件 `import '../recognize/providers.dart' as recognize;`；recognize 成全应用 Provider 桶；feature 间无直接 import UI 页面（仅 navigation push）；无编译期循环 |
| 8 | 可测试性（DI/mock/硬创建） | ✅ 中等 | VisionProvider 抽象 + 构造器注入；mocktail 28 测试文件 130 处；ProviderContainer(overrides:) 模式成熟；但 Repository 无接口抽象（测试用真实 DB + 真实 Repository）；UI 层硬 new Service（RecommendationService/AiRecommendationService/TdeeCalibrator）；offline_queue_controller 5 处 `new Repository(_db)` |

---

### 检查项 1：分层清晰度

**正面**：
- `data/database/`（Drift 表 + 连接）、`data/repositories/`（8 Repository）、`data/backup/`、`data/bluetooth/`、`data/seed/` 数据层职责清晰，互不交叉。
- `core/` 按职责细分（config/error/theme/update/util/widgets），无业务逻辑泄漏。
- `ai/` 是独立适配层，`vision_provider.dart:409` 定义 `abstract class VisionProvider`，`qwen_vl_provider.dart:17` / `glm_4v_provider.dart:9` 均 `implements VisionProvider`，符合端口-适配器模式。
- `features/` 内每个 feature 自包含页面 + 子 widget（如 `dashboard/dashboard/` 拆分 5 个 section widget）。

**问题**：
- **UI 直接访问 database 绕过 Repository**（5 文件）：
  - `weight_page.dart:793` `final db = await ref.read(recognize.databaseProvider.future); final calibrator = TdeeCalibrator(db);` —— UI 拿 db 传给 TdeeCalibrator，TdeeCalibrator 直接持 db 绕过 Repository（**P1-8**）
  - `backup_page.dart:101,185` `final db = await ref.read(recognize.databaseProvider.future);` —— 备份导出/导入直接访问 db（Drift 原生导出，**合理 P2**）
  - `food_library_page.dart:125` / `profile_page.dart:115` `ref.invalidate(recognize.databaseProvider);` —— 备份导入后强制刷新数据库（**合理用法**）
  - `offline_queue_controller.dart:583` `final db = await ref.read(recognize.databaseProvider.future);` —— 后台回补
- **UI 直接 import `data/repositories/` 类**（6 文件，用于类型）：`food_library_page`/`food_edit_page`/`me_page`/`today_meals_page`/`recognize_page`/`meal_edit_dialog` 均 `import '../../data/repositories/xxx_repository.dart';` 拿 Repository 类型作方法参数。M24 B1 注释说"feature 层不再直接 import database.dart"，但 Repository 类仍需直接 import（无 domain entity 抽象，**P2-3**）。
- **无独立 domain 层**：`nutrition/` 直接 `import 'package:eatwise/data/database/database.dart'`（5 文件）+ `import 'package:eatwise/data/repositories/...'`，Drift 实体（FoodItem/MealLog/Profile/WeightLog）直接作为领域服务输入，无 domain entity 抽象（**P2-1**）。

---

### 检查项 2：依赖方向

**正面**：
- 主流程依赖方向基本单向：UI → `recognize/providers.dart`（Provider）→ Repository → `EatWiseDatabase`。
- `lib/ai/` → `lib/data/`（`nutrition_lookup.dart:1` import `food_item_repository`）方向正确。
- `lib/core/` 不依赖 `features/`/`nutrition/`/`ai/`/`data/`（Grep `import '\.\./(features|nutrition|ai|data)/'` in `core/` 0 匹配）。
- `lib/data/` 不依赖 `features/`/`nutrition/`/`ai/`（Grep 0 匹配）。
- 无编译期循环依赖（`recognize/providers.dart:28` `export '../../data/database/database.dart';` 但 `database.dart` 不 import `providers.dart`）。

**问题**：
- **`background/` → `features/` 反向依赖**（**P1-2**）：`background/background_dispatcher.dart:15-16`
  ```dart
  import '../features/recognize/circuit_breaker.dart';
  import '../features/offline/offline_queue_controller.dart';
  ```
  `background/` 是底层后台执行器，`features/` 是 UI 层，底层依赖 UI 层违反分层。根因：`CircuitBreaker`（断路器状态机）和 `OfflineQueueController`（后台回补编排）是业务逻辑，错放在 `features/` 下。
- **`nutrition/` → `features/` 反向依赖**（**P1-3**）：`nutrition/tdee_calibrator.dart:5`
  ```dart
  import 'package:eatwise/features/profile/nutrition_calculator.dart';
  ```
  `nutrition/` 是领域服务层，`features/profile/` 是 UI 层，领域层依赖 UI 层违反分层。根因：`NutritionCalculator`（BMR/TDEE 纯函数类）错放在 `features/profile/` 下，应移到 `nutrition/` 或 `core/util/`。

---

### 检查项 3：Riverpod 使用规范

**正面**：
- Provider 命名统一：所有 Provider 均以 `xxxProvider` 后缀结尾。
- Provider 类型选择合理：
  - `Provider<T>`（同步）：`secureConfigStoreProvider`、`qwenVlProviderProvider`、`glm4vProviderProvider`、`circuitBreakerProvider`、`gitHubReleaseClientProvider`、`apkDownloaderProvider`
  - `FutureProvider<T>`（异步）：`appConfigProvider`、`databaseProvider`、8 个 `xxxRepoProvider`、`nutritionLookupProvider`、`updateServiceProvider`、`appVersionProvider`、`appVersionShortProvider`、`networkAvailableProvider`、`offlineQueueControllerProvider`
  - `NotifierProvider<N, T>`（Riverpod 3.x 新 API）：`themeSeedProvider`、`useDynamicColorProvider`（`theme_controller.dart:20,53`）
- `app.dart` `EatWiseApp extends ConsumerWidget` 在 build 顶层 `ref.watch(themeSeedProvider)` / `ref.watch(useDynamicColorProvider)`，符合 Riverpod 规范。
- `networkAvailableProvider` 用 `autoDispose` + 冷启动校正（`providers.dart:154`），有详细注释说明 autoDispose 必要性（避免冷启动误报 false 永久缓存）。
- `appConfigProvider` 在 `main.dart:55` 提前 `container.read(appConfigProvider.future)` 触发预热，`initSentryAndRunApp` 再 await（注释"多半已就绪秒回"），启动期并行化优化合理。

**问题**：
- **`ref.read` 103 次 vs `ref.watch` 22 次（5:1）**——Riverpod 退化为服务定位器（**P1-4**）：
  - `ref.watch` 仅在 3 文件用：`app.dart`（2，主题色）、`providers.dart`（17，Provider 间依赖）、`settings_page.dart`（3，主题色 + 版本号）。
  - `ref.read` 在 17 文件用，最多的是 `recognize_page.dart`（19）、`dashboard_page.dart`（13）、`weight_page.dart`（10）、`insight_page.dart`（9）、`settings_page.dart`（9）、`today_meals_page.dart`（7）。
  - 典型模式（`dashboard_page.dart:67-71`）：
    ```dart
    Future<List<RecommendedFood>> _loadRecommendations() async {
      final foodRepo = await ref.read(recognize.foodItemRepoProvider.future);
      final mealRepo = await ref.read(recognize.mealLogRepoProvider.future);
      final profileRepo = await ref.read(recognize.profileRepoProvider.future);
      final service = RecommendationService(foodRepo, mealRepo, profileRepo);
      ...
    }
    ```
    UI 在回调中 `ref.read` 拿 repo + 硬 new Service + 存 setState，本应用 `FutureProvider` 管理数据 + `ref.watch` 监听。
- **autoDispose 仅 5 处**——多数 `FutureProvider` 非 autoDispose，全应用长期持有 Repository 实例（个人项目可接受，但 `networkAvailableProvider` 已证明 autoDispose 必要性，**P2**）。
- **RecognizeController 不用 Provider 管理**（**P1-6**）：`providers.dart:136-138` 注释
  ```dart
  // RecognizeController 不用 Provider 管理（依赖 FutureProvider 异步初始化，
  // 与 StateNotifierProvider 同步初始化存在时序冲突）
  // 在 RecognizePage 中用 ref.read 按需创建实例，见 recognize_page.dart
  ```
  `recognize_page.dart:195-244` 在 `_ensureController()` 中 `ref.read` 多个 Provider 拼 `RecognizeController`，`dispose()` 中 `_controller?.dispose()` 手动管理生命周期。Riverpod 3.x 的 `AsyncNotifierProvider` 可解决"异步初始化 + 状态管理"时序问题，未迁移。

---

### 检查项 4：Repository 模式

**正面**：
- 8 个 Repository 类签名一致：`final EatWiseDatabase _db; XxxRepository(this._db);`，构造器注入便于测试。
- `MealLogRepository.insertMealLog`（`meal_log_repository.dart:26-30`）有哨兵防御：
  ```dart
  if (foodItemId <= 0) {
    throw ArgumentError('foodItemId 必须为真实 id，不能是 0 哨兵');
  }
  ```
  对应硬约束 2（`food_item_id` 非空外键），防御编程到位。
- `InsightRepository` 不 export 实体，方法返回基本类型 + `InsightSummary?`（Drift 行类型），保持最小暴露。

**问题**：
- **export DB 实体模式不统一**（**P2-2**）：
  - 5 个 Repository `export 'package:eatwise/data/database/database.dart' show XxxEntity;`：`food_item_repository.dart:7`（FoodItem）、`meal_log_repository.dart:6`（MealLog）、`pending_recognition_repository.dart:6`、`weight_log_repository.dart:6`（WeightLog）、`profile_repository.dart:5`（Profile）
  - 3 个不 export：`insight_repository`（返回 `InsightSummary?` 但不 export）、`recognition_feedback_repository`、`recommendation_feedback_repository.dart:12` 用 `typedef RecommendationFeedbackRow = RecommendationFeedback;`（另一种暴露方式）
  - 模式不统一，调用方需逐个 Repository 查 export 规则。
- **无 DTO 转换**（**P2-3**）：Repository 直接返回 Drift 生成实体（`Future<FoodItem?>`、`Future<List<MealLog>>`、`Future<Profile>`），UI 层直接操作 Drift 行对象。Drift 实体含 `table`、`generatedIntId` 等 ORM 内部字段，且与 DB schema 强耦合（如加字段需重新生成）。个人项目可接受，但严格 Clean Architecture 应有 domain entity 转换层。
- **offline_queue_controller 5 处 `new Repository(_db)` 绕过 Provider**（**P1-8**）：
  - `offline_queue_controller.dart:104` `final pendingRepo = PendingRecognitionRepository(_db);`
  - `:108` `final mealRepo = MealLogRepository(_db);`
  - `:291,324,413,444` `final foodItemRepo = FoodItemRepository(_db);`
  - 注释（`providers.dart:80-82`）说"M24 Task B1：补齐缺失的 Repository Provider，feature 层不再直接 new Repo(db)"，但 `OfflineQueueController` 持有 `_db` 后仍硬创建 Repository，绕过 Provider 体系。`OfflineQueueController` 本身构造器注入 `db`（便于测试传 mock db），但内部 `new Repository(_db)` 导致 Repository 层无法被 mock。

---

### 检查项 5：错误处理

**正面**：
- **顶层兜底完善**（`main.dart:38-134`）：
  - `runZonedGuarded` 包整个 main，捕获同步+异步错误
  - `FlutterError.onError` 兜底框架错误（build/layout/async）+ 写 `boot_log.txt`
  - zone 兜底 `Sentry.captureException`
  - 启动期 4 个 try-catch 块（appConfig / Workmanager / OfflineQueue / ImageCleanup），各自失败降级不阻塞 UI
- **OfflineQueueController 可注入异常上报**（`offline_queue_controller.dart:34-35,48-55`）：
  ```dart
  final void Function(Object error, StackTrace? stackTrace) _onError;
  ...
  _onError = onError ?? _defaultOnError;
  static void _defaultOnError(Object error, StackTrace? stackTrace) {
    Sentry.captureException(error, stackTrace: stackTrace);
  }
  ```
  生产默认 Sentry，测试可注入 mock，可测试性好。
- **sentry_init.dart 降级处理**（`sentry_init.dart:36-55`）：`SentryFlutter.init` 失败时 try-catch 降级返回原 app 不阻塞 runApp，避免永久黑屏。
- **recognize_controller best-effort 模式合理**：`recognize_controller.dart:298-303,381-388,399-416` 等处 `try { ... } catch (_) { /* best-effort：不影响识别结果 */ }` 包裹断路器/月度计数操作，注释明确说明"best-effort：持久化失败不影响识别结果"。

**问题**：
- **无统一 Result/Either 类型或 AppException 域异常**（**P2-4**）：
  - 错误信号机制多样：`RecognizeUiState.errorMessage: String?`、`AiRecommendationResult.error: String?`、`_loadError: bool` 标志、`throw ArgumentError`、`throw VisionRecognitionException`、`return false`（Workmanager）、`Sentry.captureException` 静默上报。
  - UI 层无法统一处理错误，每个页面各自实现 `_loadError` + `ErrorState` 组件。
- **`catch (_)` 43 处，UI 层多处无日志**（**P2-5**）：
  - `recognize_controller.dart` 6 处 `catch (_)` —— best-effort 合理（有注释说明）
  - `today_meals_page.dart` 7 处 —— 多数有 `_loadError = true` + ErrorState UI（`:70` 注释"加载失败：置 _loadError 标志，build 中显 ErrorState 不静默显空态误导用户"），但无 Sentry/debugPrint 日志
  - `weight_page.dart` 4 处 —— `:800` catch(_) 注释"校准失败不影响体重记录主流程"，无日志
  - `food_library_page.dart` 2 处 —— `:55,96` 有 `_loadError` + toast 提示
  - `main.dart` 2 处 —— `:31,69` 写 `_writeBootLog`，合理
  - 数据层 `auto_backup.dart` 4 处、`image_cleanup.dart` 1 处、`food_item_repository.dart:178` 1 处 —— 后台任务 best-effort 合理
  - **核心问题**：UI 层 `catch(_)` 多数有 ErrorState UI 但无 Sentry 上报，生产环境可观测性不足。

---

### 检查项 6：状态管理

**正面**：
- **RecognizeUiState 不可变 + copyWith**（`recognize_controller.dart:21-66`）：所有字段 `final`，`copyWith` 显式 `clearError` 参数控制错误清空，符合不可变状态规范。
- **ThemeNotifier / UseDynamicColorNotifier 用 NotifierProvider**（`theme_controller.dart:20,53`）：Riverpod 3.x 新 API，`Notifier<int>` / `Notifier<bool>` + `set()` 方法，状态不可变。
- **写库按钮防重入三件套**（符合项目规则）：`profile_page.dart:35` `bool _busy`、`settings_page.dart:36` `bool _isSaving`、`recognize_page.dart:197` `bool _isRecognizing`、`backup_page.dart:24` `bool _busy`、`manual_entry_page.dart:34` `bool _busy`，均有 `onPressed: _busy ? null : () => ...` 禁用 + try-catch-finally。
- **async gap 后 mounted 检查**（符合项目规则）：`today_meals_page.dart:76` `if (mounted) setState(() => _loading = false);`、`food_library_page.dart:54,60` `if (mounted) setState(() {});` 等广泛使用。

**问题**：
- **RecognizeController 用 legacy `StateNotifier`**（**P2-6**）：`recognize_controller.dart:5`
  ```dart
  import 'package:flutter_riverpod/legacy.dart'; // Riverpod 3.x：StateNotifier 移至 legacy.dart
  ```
  Riverpod 3.x 已将 `StateNotifier` 移至 `legacy.dart`，推荐迁移到 `NotifierProvider` / `AsyncNotifierProvider`。`theme_controller.dart` 已用新 API，但 `RecognizeController` 未迁移（且不用 Provider 管理，见 P1-6）。
- **RefreshBus 单例 ChangeNotifier 绕过 Riverpod**（**P1-5**）：`core/util/refresh_bus.dart:10-15`
  ```dart
  class RefreshBus extends ChangeNotifier {
    RefreshBus._();
    static final RefreshBus instance = RefreshBus._();
    void notify() => notifyListeners();
  }
  ```
  - `main_shell.dart:69` `RefreshBus.instance.notify();`（FAB 拍照返回后通知刷新）
  - `dashboard_page.dart:42,47` `RefreshBus.instance.addListener(_refresh)` / `removeListener`
  - `today_meals_page` / `insight_page` / `weight_page` / `profile_page` 等均监听
  - 这是与 Riverpod 体系并行的事件总线，违反"单一状态管理"原则。Riverpod 本应负责跨 widget 通信（如 `ref.watch(invalidateProvider)` 触发刷新），但项目用 RefreshBus 绕过。
- **16 ConsumerStatefulWidget + 1 ConsumerWidget**——Riverpod 退化为服务定位器（**P1-4**）：
  - `insight_page.dart` 30+ setState 字段（`_summary`/`_error`/`_loading`/`_periodType`/`_periodStart`/`_periodEnd`/`_dailyCal`/`_dailyWeight`/`_targetCal`/`_recordedDays`/`_totalDays`/`_loadVersion`/`_chartLoading`/`_dailyProtein`/`_dailyFat`/`_dailyCarbs`/`_proteinGoal`/`_fatGoal`/`_carbGoal`/`_mealTypeCalories`/`_streak`/`_avgExcess`/`_goalHitDays`/`_weightFirst`/`_weightLast`/`_weightDiff`/`_preferenceFoods`/`_preferenceFoodCounts`/`_preferenceFoodCalories`/`_weeklyBreakdown`）
  - `_loadVersion` 守卫防 SegmentedButton 切换竞态（`insight_page.dart:36` 注释"M2 修复：SegmentedButton 快速切换时，旧 _loadExisting 的 setState 被版本号守卫丢弃"）——这种竞态用 Riverpod `autoDispose` + `family` 本可自动处理。
  - `dashboard_page.dart` 3 个 Future 字段（`_future`/`_recFuture`/`_aiRecFuture`）+ initState 触发 + RefreshBus 监听刷新。

---

### 检查项 7：模块耦合

**正面**：
- **feature 间无直接 import UI 页面**（除导航）：Grep `import '\.\./\.\./features/'` in `lib/` 0 匹配（用相对路径），feature 间导航用 `Navigator.push(MaterialPageRoute(builder: (_) => const XxxPage()))` + `context.push('/route')`（GoRouter）。
- **无编译期循环依赖**：`recognize/providers.dart` export `database.dart`，但 `database.dart` 不 import `providers.dart`；`recognize_page.dart` import `providers.dart` + `recognize_controller.dart`，但 `recognize_controller.dart` 不 import `recognize_page.dart`。
- **`me_page` 聚合 5 个 feature**（`me_page.dart:8-12` import `backup_page`/`profile_page`/`settings_page`/`weight_page`/`recognize/providers`）：作为"我的"tab 聚合页，合理。

**问题**：
- **`recognize/providers.dart` 上帝模块**（**P1-1**）：12 个 feature 文件 `import '../recognize/providers.dart' as recognize;`：
  - `food_library_page`/`food_edit_page`/`me_page`/`profile_page`/`today_meals_page`/`dashboard_page`/`weight_page`/`backup_page`/`insight_page`/`manual_entry_page`/`update_page`/`offline_queue_controller`
  - `providers.dart` 含 17 个 Provider：3 个 API key Provider、2 个 VisionProvider Provider、8 个 Repository Provider、`nutritionLookupProvider`、`circuitBreakerProvider`、`networkAvailableProvider`、3 个 update Provider。
  - `recognize` feature 本应是"拍照识别"UI 模块，却承担了全应用 DI 容器角色。所有 feature 依赖 `recognize`，`recognize` 成了"上帝模块"。
  - 测试也要 `import '../recognize/providers.dart' as recognize;` 才能 override（`test/features/weight_page_test.dart:8`、`test/app_dynamic_color_test.dart:31` 等）。
- **feature 间导航耦合**（**P2-7**）：`recognize_page.dart:15` import `../manual_entry/manual_entry_page.dart`、`multi_dish_page.dart:10` import `../manual_entry/manual_entry_page.dart`、`meal_edit_dialog.dart:10` import `../food_library/food_library_page.dart`、`manual_entry_page.dart:9` import `../food_library/food_library_page.dart`。导航用 `Navigator.push(MaterialPageRoute(builder: (_) => const XxxPage()))` 直接 new 页面，未走 GoRouter 路由表（`app.dart:208` 定义的 `/manual_entry` / `/food_library` 等路由未被这些 push 使用）。

---

### 检查项 8：可测试性

**正面**：
- **VisionProvider 抽象 + 构造器注入**（`vision_provider.dart:409` `abstract class VisionProvider`）：`QwenVlProvider` / `Glm4vProvider` 均 `implements VisionProvider`，测试可用 `_FakeVisionProvider implements VisionProvider`（`test/features/recognize_controller_test.dart:20`）。
- **RecognizeController 构造器注入全部依赖**（`recognize_controller.dart:119-133`）：`VisionProvider _primaryProvider` / `VisionProvider? _fallbackProvider` / `NutritionLookup _nutritionLookup` + 可选命名参数 `onOfflineEnqueue` / `onL3Fallback` / `circuitBreaker` / `secureConfigStore`，测试可注入 Fake/Mock。
- **OfflineQueueController 构造器注入 + onError 回调**（`offline_queue_controller.dart:40-55`）：`db` / `visionProvider` / `nutritionLookup` / `circuitBreaker` / `secureConfigStore` / `onError` 全部注入，`_defaultOnError` 默认 Sentry，测试可注入 mock。
- **AiRecommendationService 构造器注入 4 Repository + GlmFlashProvider**（`ai_recommendation_service.dart:73-79`）：可测试性好。
- **mocktail 大量使用**（28 测试文件 130 处）：如 `test/core/update/update_service_test.dart:13-16` `class MockGitHubReleaseClient extends Mock implements GitHubReleaseClient {}`，mock http client / ApkDownloader 等具体类。
- **ProviderContainer(overrides:) 模式成熟**：`test/app_dynamic_color_test.dart:30-34`、`test/features/insight_p2_test.dart:26-27`、`test/features/food_library/food_library_page_test.dart:83-84,131,166` 等广泛用 `recognize.databaseProvider.overrideWith((ref) async => db)` + `secureConfigStoreProvider.overrideWithValue(store)` + `recognize.networkAvailableProvider.overrideWith((ref) async => false)` mock 依赖。

**问题**：
- **Repository 无接口抽象**（**P2-8**）：8 个 Repository 均为具体类，测试只能用真实 `EatWiseDatabase(NativeDatabase.memory())` + 真实 Repository（`test/features/weight_page_test.dart:21` `db = EatWiseDatabase(NativeDatabase.memory());`），无法 mock Repository 行为。测试本质是集成测试，非单元测试。
- **NutritionLookup 是具体类无接口**：测试用 `_FakeNutritionLookup implements NutritionLookup`（`recognize_controller_test.dart:36`）跨库 implements 具体类（Dart 允许但脆弱，新增公开方法需同步改 Fake）。
- **UI 层硬 new Service**（**P1-7**）：
  - `dashboard_page.dart:71` `final service = RecommendationService(foodRepo, mealRepo, profileRepo);`
  - `dashboard_page.dart:129` `final service = AiRecommendationService(...);`
  - `weight_page.dart:794` `final calibrator = TdeeCalibrator(db);`
  - 这些 Service 无 Provider 管理，UI 测试无法 mock Service 行为（需 mock 整条 Repository 链）。
- **TdeeCalibrator 直接持 `EatWiseDatabase`**（`tdee_calibrator.dart:21-22` `final EatWiseDatabase _db; TdeeCalibrator(this._db);`）：绕过 Repository 层，测试需真实 db（**P1-8**）。
- **background_dispatcher 硬 new 全部依赖**（`background_dispatcher.dart:31-110`）：`EatWiseDatabase(executor)` / `SecureConfigStore()` / `AppConfig(store)` / `QwenVlProvider(...)` / `Glm4vProvider(...)` / `FoodItemRepository(db)` / `NutritionLookup(foodRepo)` / `CircuitBreaker(...)` / `OfflineQueueController(...)` 全部硬创建。注释解释"此 isolate 无法访问 main isolate 的 ProviderContainer，需重新初始化依赖"——**isolate 限制，合理但代码与 main isolate 重复**。

---

## 三、发现的问题

### P0（架构崩坏）

无。项目能正常编译运行，6 硬约束满足，无编译期循环依赖，无跨层导致的功能 bug。

### P1（影响可维护性）

#### P1-1：`features/recognize/providers.dart` 演化为全应用"上帝 Provider 桶"

- **位置**：`lib/features/recognize/providers.dart`（17 个 Provider 定义）
- **影响范围**：12 个 feature 文件 + 多个测试文件 `import '../recognize/providers.dart' as recognize;`
- **问题**：`recognize` feature 本应是"拍照识别"UI 模块，却承担了全应用 DI 容器角色。所有 feature（含与拍照识别无关的 `weight_page`/`backup_page`/`settings_page`/`insight_page`/`me_page`/`update_page`）都依赖 `recognize`，`recognize` 成了事实上的全局 Provider 桶。这违反 feature 模块边界，导致：
  - `recognize` feature 无法独立删除/替换（删了会断全应用 Provider）
  - 新增 feature 必须依赖 `recognize`，加剧耦合
  - 测试 mock 依赖必须 `import recognize/providers.dart` 才能 override
- **现状 mitigations**：M24 B1 注释（`providers.dart:80-82`）说"补齐缺失的 Repository Provider，feature 层不再直接 new Repo(db)"，方向正确但 Provider 集中度过高。
- **建议**：按 feature 或 layer 拆分 Provider——Repository Provider 移到 `data/repositories/providers.dart`，AI Provider 移到 `ai/providers.dart`，update Provider 移到 `core/update/providers.dart`，`recognize/providers.dart` 只保留 `recognize` 自身相关 Provider（如 `qwenVlProviderProvider`/`glm4vProviderProvider`/`circuitBreakerProvider`/`nutritionLookupProvider`）。

#### P1-2：`background/` → `features/` 反向依赖

- **位置**：`lib/background/background_dispatcher.dart:15-16`
  ```dart
  import '../features/recognize/circuit_breaker.dart';
  import '../features/offline/offline_queue_controller.dart';
  ```
- **问题**：`background/` 是底层后台执行器（独立 isolate），`features/` 是 UI 层，底层依赖 UI 层违反分层。根因：`CircuitBreaker`（断路器状态机，`features/recognize/circuit_breaker.dart`）和 `OfflineQueueController`（后台回补编排，`features/offline/offline_queue_controller.dart`）是业务逻辑，错放在 `features/` 下。
- **影响**：`background/` 编译依赖 `features/`，无法独立；`features/` 改动可能波及 `background/`。
- **建议**：把 `CircuitBreaker` 移到 `core/util/circuit_breaker.dart` 或新建 `domain/`；把 `OfflineQueueController` 移到 `background/offline_queue_controller.dart` 或新建 `domain/offline/`。

#### P1-3：`nutrition/` → `features/` 反向依赖

- **位置**：`lib/nutrition/tdee_calibrator.dart:5`
  ```dart
  import 'package:eatwise/features/profile/nutrition_calculator.dart';
  ```
- **问题**：`nutrition/` 是领域服务层，`features/profile/` 是 UI 层，领域层依赖 UI 层违反分层。根因：`NutritionCalculator`（BMR/TDEE 纯函数类，`features/profile/nutrition_calculator.dart`）是纯计算逻辑（无 UI 无副作用），错放在 `features/profile/` 下。
- **影响**：`nutrition/` 编译依赖 `features/profile/`，领域层无法独立复用。
- **建议**：把 `NutritionCalculator` 移到 `nutrition/nutrition_calculator.dart` 或 `core/util/nutrition_calculator.dart`。

#### P1-4：Riverpod 退化为服务定位器（`ref.read` 103 vs `ref.watch` 22，16 ConsumerStatefulWidget + 1 ConsumerWidget）

- **位置**：全应用 17 个 widget 文件
- **问题**：
  - `ref.read` 103 次（17 文件）vs `ref.watch` 22 次（3 文件），比例 5:1。`ref.watch` 仅在 `app.dart`（主题色）、`providers.dart`（Provider 间依赖）、`settings_page.dart`（主题色 + 版本号）用。
  - 16 个 `ConsumerStatefulWidget` + 仅 1 个 `ConsumerWidget`（`EatWiseApp`），所有页面都用 StatefulWidget + setState 管理状态。
  - 典型模式：UI 在回调中 `ref.read(xxxRepoProvider.future)` 拿 Repository + 硬 new Service + 存 setState 字段，本应用 `FutureProvider` 管理数据 + `ref.watch` 监听。
  - `insight_page.dart` 30+ setState 字段 + `_loadVersion` 守卫防 SegmentedButton 切换竞态——这种竞态用 Riverpod `autoDispose` + `family` 本可自动处理。
- **影响**：Riverpod 退化为"服务定位器"（ref.read 拿 repo），未发挥状态管理能力。状态分散在 16 个 StatefulWidget 中，跨页面状态共享需 RefreshBus（见 P1-5）。
- **现状 mitigations**：`theme_controller.dart` 已用 `NotifierProvider` 新 API；`networkAvailableProvider` 已用 `autoDispose`；写库按钮防重入三件套 + mounted 检查规范。
- **建议**：渐进式迁移——新页面优先用 `FutureProvider` + `ref.watch`；`insight_page` / `dashboard_page` 等重状态页面优先重构为 `AsyncNotifierProvider`。

#### P1-5：`RefreshBus` 单例 `ChangeNotifier` 绕过 Riverpod

- **位置**：`lib/core/util/refresh_bus.dart:10-15`
  ```dart
  class RefreshBus extends ChangeNotifier {
    RefreshBus._();
    static final RefreshBus instance = RefreshBus._();
    void notify() => notifyListeners();
  }
  ```
- **影响范围**：`main_shell.dart:69`（FAB 拍照返回后 notify）、`dashboard_page.dart:42,47`、`today_meals_page`、`insight_page`、`weight_page`、`profile_page` 等均 `addListener` / `removeListener`
- **问题**：与 Riverpod 体系并行的事件总线，违反"单一状态管理"原则。Riverpod 本应负责跨 widget 通信（如 `ref.watch(invalidateProvider)` 触发刷新），但项目用 RefreshBus 绕过。
- **现状 mitigations**：注释（`backup_page.dart:198`）承认"部分 tab 页用 RefreshBus（ChangeNotifier）而非 Riverpod 监听刷新"，是设计妥协。
- **建议**：用 Riverpod `StateProvider<int>` 或 `ChangeNotifierProvider` 替代 RefreshBus——FAB 拍照返回后 `ref.read(refreshTickProvider.notifier).state++`，各 tab 页 `ref.watch(refreshTickProvider)` 触发刷新。

#### P1-6：`RecognizeController` 不用 Provider 管理（`ref.read` 创建 + 手动 dispose）

- **位置**：`lib/features/recognize/providers.dart:136-138`（注释）+ `lib/features/recognize/recognize_page.dart:195-244`
- **问题**：
  ```dart
  // providers.dart:136-138
  // RecognizeController 不用 Provider 管理（依赖 FutureProvider 异步初始化，
  // 与 StateNotifierProvider 同步初始化存在时序冲突）
  // 在 RecognizePage 中用 ref.read 按需创建实例，见 recognize_page.dart
  ```
  `recognize_page.dart:195` `RecognizeController? _controller;`，`:206` `_controller?.dispose();`，`:210-244` `_ensureController()` 用 `ref.read` 多个 Provider 拼 `RecognizeController`。StateNotifier 不被 Provider 管理，需 StatefulWidget 手动管理生命周期。
- **影响**：违反 Riverpod"状态由 Provider 管理"原则；`RecognizeController` 无法被其他 widget `ref.watch`（如想在外部监听识别状态变化）；测试需手动 new RecognizeController。
- **现状 mitigations**：注释解释了"FutureProvider 异步初始化与 StateNotifierProvider 同步初始化时序冲突"，是 Riverpod 2.x 时代限制。
- **建议**：Riverpod 3.x 的 `AsyncNotifierProvider<RecognizeController, RecognizeUiState>` 可解决"异步初始化 + 状态管理"时序问题，迁移后 `RecognizeController` 由 Provider 管理，`ref.watch(recognizeControllerProvider)` 监听状态。

#### P1-7：领域 Service 全部无 Provider 管理（UI 层硬 new）

- **位置**：
  - `dashboard_page.dart:71` `final service = RecommendationService(foodRepo, mealRepo, profileRepo);`
  - `dashboard_page.dart:129` `final service = AiRecommendationService(...);`
  - `weight_page.dart:794` `final calibrator = TdeeCalibrator(db);`
- **问题**：`RecommendationService` / `AiRecommendationService` / `TdeeCalibrator` / `UserPreferenceLearner` 等领域 Service 均无 Provider 管理，UI 层每次需要时 `new` 创建。Grep `aiRecommendationServiceProvider|recommendationServiceProvider|tdeeCalibratorProvider` 0 匹配。
- **影响**：
  - Service 实例无法复用（每次进 dashboard 都 new `RecommendationService` + `AiRecommendationService`）
  - UI 测试无法 mock Service 行为（需 mock 整条 Repository 链）
  - `AiRecommendationService` 有静态内存缓存（`ai_recommendation_service.dart:71` `static final Map<String, Future<List<AiRecommendation>>> _cache = {}`），但 Service 实例每次 new，缓存却静态共享——状态管理割裂
- **建议**：为领域 Service 加 Provider：
  ```dart
  final recommendationServiceProvider = Provider<RecommendationService>((ref) {
    // 读 3 个 repoProvider 构造
  });
  final aiRecommendationServiceProvider = FutureProvider<AiRecommendationService>((ref) async {
    final provider = ref.watch(glmFlashProviderProvider);
    final profileRepo = await ref.watch(profileRepoProvider.future);
    ...
  });
  ```

#### P1-8：UI 直接访问 database 绕过 Repository（`TdeeCalibrator` 持 db + `offline_queue_controller` 5 处 new Repository）

- **位置**：
  - `weight_page.dart:793-794` `final db = await ref.read(recognize.databaseProvider.future); final calibrator = TdeeCalibrator(db);`
  - `nutrition/tdee_calibrator.dart:21-22` `final EatWiseDatabase _db; TdeeCalibrator(this._db);`
  - `offline_queue_controller.dart:104,108,291,324,413,444` 5 处 `final xxxRepo = XxxRepository(_db);`
- **问题**：
  - `TdeeCalibrator` 是领域 Service，却直接持 `EatWiseDatabase` 绕过 Repository 层。`weight_page` UI 拿 db 传给 `TdeeCalibrator`，注释（`:792`）承认"TdeeCalibrator 非 Repository，仍需 db 实例（db 走 databaseProvider 注入）"——明知反模式但未修。
  - `OfflineQueueController` 持有 `_db` 后内部 5 处 `new Repository(_db)` 绕过 Provider 体系。注释（`providers.dart:80-82`）说"M24 Task B1：feature 层不再直接 new Repo(db)"，但 `OfflineQueueController` 仍硬创建。
- **影响**：Repository 层无法被 mock（`TdeeCalibrator` 测试需真实 db；`OfflineQueueController` 内部 Repository 行为无法 mock）；UI 层拿到 `EatWiseDatabase` 实例后理论上可直接访问任意表，破坏 Repository 封装。
- **现状 mitigations**：`OfflineQueueController` 构造器注入 `db`（便于测试传 mock db），但内部 `new Repository(_db)` 仍绕过 Provider；`backup_page` 直接访问 db 做备份导出是 Drift 原生能力（合理）。
- **建议**：`TdeeCalibrator` 改为依赖 `WeightLogRepository` + `ProfileRepository` 而非 `EatWiseDatabase`；`OfflineQueueController` 改为构造器注入 3 个 Repository（`pendingRecognitionRepo` / `mealLogRepo` / `foodItemRepo`）而非 `db`。

### P2（改进建议）

#### P2-1：无独立 `lib/domain/` 层，`nutrition/` 直接依赖 `data/database` + `data/repositories`

- **位置**：`lib/nutrition/` 下 5 文件 import `data/database/database.dart`（`tdee_calibrator.dart:2`、`user_preference_learner.dart:13`、`ai_recommendation_prompt.dart:14`、`recommendation_service.dart:3`、`ai_recommendation_service.dart` 间接）
- **问题**：无 domain entity 抽象，Drift 生成实体（FoodItem/MealLog/Profile/WeightLog）直接作为领域服务输入。Drift 实体含 `table`、`generatedIntId` 等 ORM 内部字段，且与 DB schema 强耦合（加字段需重新生成）。
- **现状 mitigations**：个人项目可接受，Drift 实体本身就是 POJO；5 个 Repository `export ... show XxxEntity;` 限制了暴露范围。
- **建议**：长期可引入 domain entity 层（`domain/entities/food_item.dart` 等），Repository 内部 Drift ↔ domain 转换。短期可不改。

#### P2-2：Repository export DB 实体模式不统一

- **位置**：5 个 Repository `export ... show XxxEntity;`（food_item/meal_log/pending_recognition/weight_log/profile），3 个不 export（insight/recognition_feedback/recommendation_feedback，后者用 `typedef RecommendationFeedbackRow = RecommendationFeedback;`）
- **问题**：模式不统一，调用方需逐个 Repository 查 export 规则。
- **建议**：统一规则——要么全部 export 实体，要么全部不 export（用 typedef 或 domain entity）。

#### P2-3：Repository 无 DTO 转换，直接暴露 Drift 实体给 UI

- **位置**：5 个 Repository `export ... show XxxEntity;`，UI 直接操作 `FoodItem`/`MealLog`/`Profile`/`WeightLog`
- **问题**：UI 层直接操作 Drift 行对象，与 DB schema 强耦合。
- **现状 mitigations**：个人项目可接受；`DashboardData`（`dashboard/dashboard_data.dart`）是聚合 DTO，部分缓解。
- **建议**：长期可加 DTO 转换层，短期可不改。

#### P2-4：无统一 Result/Either 类型或 AppException 域异常

- **位置**：全应用
- **问题**：错误信号机制多样——`RecognizeUiState.errorMessage: String?`、`AiRecommendationResult.error: String?`、`_loadError: bool` 标志、`throw ArgumentError`、`throw VisionRecognitionException`、`return false`（Workmanager）、`Sentry.captureException` 静默上报。UI 层无法统一处理错误。
- **建议**：引入 `sealed class Result<T>` 或 `Either<Failure, T>`，统一 Repository 返回类型；定义 `AppException` 域异常基类。

#### P2-5：`catch (_)` 43 处，UI 层多处无日志

- **位置**：`today_meals_page.dart`（7）、`weight_page.dart`（4）、`settings_page.dart`（3）、`food_library_page.dart`（2）、`meal_edit_dialog.dart`（1）、`ai_rec_item.dart`（1）等
- **问题**：UI 层 `catch(_)` 多数有 `_loadError` + ErrorState UI 但无 Sentry/debugPrint 日志，生产环境可观测性不足。
- **现状 mitigations**：`recognize_controller.dart` 6 处 best-effort 有注释说明；`main.dart` 2 处写 `_writeBootLog`；`offline_queue_controller` 有 `_onError` 回调注入 Sentry。
- **建议**：UI 层 `catch(_)` 至少加 `debugPrint` 或 `Sentry.captureException`（Sentry 未初始化时 no-op，安全）。

#### P2-6：`StateNotifier` legacy 未迁移到 Riverpod 3.x 新 API

- **位置**：`recognize_controller.dart:5` `import 'package:flutter_riverpod/legacy.dart';` + `:87` `class RecognizeController extends StateNotifier<RecognizeUiState>`
- **问题**：Riverpod 3.x 已将 `StateNotifier` 移至 `legacy.dart`，推荐迁移到 `NotifierProvider` / `AsyncNotifierProvider`。`theme_controller.dart` 已用新 API（`NotifierProvider<ThemeNotifier, int>`），但 `RecognizeController` 未迁移。
- **现状 mitigations**：能用，注释明确说明"Riverpod 3.x：StateNotifier 移至 legacy.dart"。
- **建议**：与 P1-6 一起迁移——`RecognizeController` 改为 `AsyncNotifier<RecognizeUiState>` + `AsyncNotifierProvider`。

#### P2-7：业务逻辑类位置错误（错放在 `features/` 下）

- **位置**：
  - `features/recognize/circuit_breaker.dart`（断路器状态机，被 background + offline_queue 用）
  - `features/recognize/calibrated_nutrition_calculator.dart`（营养计算，被 offline_queue 用）
  - `features/offline/offline_queue_controller.dart`（后台回补编排，被 background 用）
  - `features/profile/nutrition_calculator.dart`（BMR/TDEE 纯函数类，被 nutrition 用）
- **问题**：这些是非 UI 的业务/工具逻辑，错放在 `features/` 下，导致 P1-2 / P1-3 反向依赖。
- **建议**：与 P1-2 / P1-3 一起处理——移到 `core/util/`、`nutrition/` 或新建 `domain/`。

---

## 四、与 M23 维度 3 对比

| M23 发现 | 严重级 | 本次状态 | 说明 |
|---------|--------|---------|------|
| 3.1-1：feature 层 11 个文件直接 import `data/database/database.dart` 绕过 Repository Provider | P1 | ✅ 半修复 | M24 Task B1 已修复 import 路径（feature 不再直接 import database.dart），但通过 `recognize.databaseProvider` 仍可访问 db 实例（5 文件 ref.read/ref.invalidate recognize.databaseProvider）。`weight_page` 拿 db 给 TdeeCalibrator 仍绕过 Repository（P1-8） |
| 3.4-1：`processPending` 396 行单方法圈复杂度过高 | P1 | ✅ 已修复 | M24 B3 已拆为 `processPending` + `_processOnePending` + `_processSingleItem` / `_processComposite`（见 `offline_queue_controller.dart:97-99` 注释） |
| 3.5-1：超长文件（multi_dish_page 986 行 / dashboard_page 948 行） | P1 | ⚠️ 部分修复 | M24 B4/B5 拆分了 multi_dish/ 子目录 + dashboard/ 子目录，但主文件仍较长 |
| 3.7-1：`catch (_)` 静默吞异常 | P2 | ⚠️ 仍存在 | 本次发现 43 处 `catch(_)`，UI 层多数有 ErrorState UI 但无日志（P2-5） |
| Riverpod 用法 | 无发现 | ⚠️ 新发现 | M23 评级"无发现"，本次发现 Riverpod 退化为服务定位器（P1-4）+ RecognizeController 不用 Provider 管理（P1-6）+ RefreshBus 绕过 Riverpod（P1-5） |

**本次新增发现**（M23 未覆盖）：
- P1-1：`recognize/providers.dart` 上帝模块（12 文件依赖）
- P1-2：`background/` → `features/` 反向依赖
- P1-3：`nutrition/` → `features/` 反向依赖
- P1-5：RefreshBus 单例绕过 Riverpod
- P1-7：领域 Service 全部无 Provider 管理
- P2-1/P2-3：无 domain 层 + Repository 无 DTO 转换

---

## 五、建议改进路线

### 短期（低风险，1-2 天）

1. **P1-3 修复**：把 `features/profile/nutrition_calculator.dart` 移到 `nutrition/nutrition_calculator.dart`，更新 `tdee_calibrator.dart` import。同时修复 `profile_page.dart` import。**收益**：消除 nutrition→features 反向依赖。
2. **P1-2 修复**：把 `features/recognize/circuit_breaker.dart` 移到 `core/util/circuit_breaker.dart`；把 `features/offline/offline_queue_controller.dart` 移到 `background/offline_queue_controller.dart`。更新 `background_dispatcher.dart` import 为同目录。**收益**：消除 background→features 反向依赖。
3. **P2-5 部分修复**：UI 层 `catch(_)` 加 `debugPrint` 或 `Sentry.captureException`（Sentry 未初始化时 no-op，安全）。

### 中期（中风险，3-5 天）

4. **P1-1 部分修复**：拆分 `recognize/providers.dart`——Repository Provider 移到 `data/repositories/providers.dart`，AI Provider 移到 `ai/providers.dart`，update Provider 移到 `core/update/providers.dart`，`recognize/providers.dart` 只保留 recognize 自身相关。各 feature 改 import 路径。**收益**：消除"上帝模块"。
5. **P1-7 修复**：为 `RecommendationService` / `AiRecommendationService` / `TdeeCalibrator` 加 Provider，UI 层 `ref.read(xxxServiceProvider)` 拿实例。**收益**：Service 实例复用 + UI 测试可 mock Service。
6. **P1-8 修复**：`TdeeCalibrator` 改为依赖 `WeightLogRepository` + `ProfileRepository` 而非 `EatWiseDatabase`；`OfflineQueueController` 改为构造器注入 3 个 Repository 而非 `db`。**收益**：Repository 层可 mock。

### 长期（高风险，建议大重构，1-2 周）

7. **P1-4 + P1-6 修复**：迁移 `RecognizeController` 到 `AsyncNotifierProvider`（Riverpod 3.x），删除 legacy `StateNotifier`；UI 页面从 `ConsumerStatefulWidget + Future + setState` 渐进迁移到 `FutureProvider + ref.watch`，优先重构 `insight_page` / `dashboard_page` 等重状态页面。**收益**：Riverpod 真正承担状态管理，消除 setState 竞态守卫。
8. **P1-5 修复**：用 Riverpod `StateProvider<int>` 或 `ChangeNotifierProvider` 替代 `RefreshBus`——FAB 拍照返回后 `ref.read(refreshTickProvider.notifier).state++`，各 tab 页 `ref.watch(refreshTickProvider)` 触发刷新。**收益**：统一状态管理。
9. **P2-1/P2-3 修复**：引入 `lib/domain/entities/` 层，Repository 内部 Drift ↔ domain 转换，UI 层操作 domain entity 而非 Drift 实体。**收益**：解耦 UI 与 DB schema。

---

## 六、附录

### Provider 定义分布（5 文件）

| 文件 | Provider 数 | 类型分布 |
|------|------------|---------|
| `data/database/database.dart` | 1 | FutureProvider（databaseProvider） |
| `features/recognize/providers.dart` | 17 | Provider × 6 + FutureProvider × 10 + FutureProvider.autoDispose × 1 |
| `core/config/app_config.dart` | 2 | Provider（secureConfigStoreProvider）+ FutureProvider（appConfigProvider） |
| `core/config/app_version_provider.dart` | 2 | FutureProvider × 2 |
| `core/theme/theme_controller.dart` | 2 | NotifierProvider × 2 |

### Repository export 实体分布

| Repository | export 实体 | 暴露方式 |
|-----------|------------|---------|
| food_item_repository | FoodItem | `export ... show FoodItem;` |
| meal_log_repository | MealLog | `export ... show MealLog;` |
| pending_recognition_repository | (多实体) | `export ...` |
| weight_log_repository | WeightLog | `export ... show WeightLog;` |
| profile_repository | Profile | `export ... show Profile;` |
| insight_repository | — | 不 export（返回 `InsightSummary?`） |
| recognition_feedback_repository | — | 不 export |
| recommendation_feedback_repository | RecommendationFeedback | `typedef RecommendationFeedbackRow = RecommendationFeedback;` |

### 跨 feature import 统计

| 被依赖的 feature/文件 | 依赖方数量 | 依赖方 |
|---------------------|----------|--------|
| `recognize/providers.dart` | 12 | food_library_page / food_edit_page / me_page / profile_page / today_meals_page / dashboard_page / weight_page / backup_page / insight_page / manual_entry_page / update_page / offline_queue_controller |
| `manual_entry/manual_entry_page.dart` | 2 | recognize_page / multi_dish_page（导航） |
| `food_library/food_library_page.dart` | 2 | manual_entry_page / meal_edit_dialog（导航） |
| `backup/backup_page.dart` / `profile/profile_page.dart` / `settings/settings_page.dart` / `weight/weight_page.dart` | 各 1 | me_page（聚合） |

### 状态管理统计

| 类型 | 数量 | 说明 |
|------|------|------|
| ConsumerStatefulWidget | 16 | 所有页面（含 setState 字段） |
| ConsumerWidget | 1 | EatWiseApp（仅 ref.watch 主题色） |
| StatefulWidget（非 Consumer） | 1 | MainShell（用 RefreshBus） |
| StateNotifier（legacy） | 1 | RecognizeController |
| NotifierProvider（新 API） | 2 | ThemeNotifier / UseDynamicColorNotifier |
| ChangeNotifier（单例） | 1 | RefreshBus |
| `ref.read` 调用 | 103 | 17 文件 |
| `ref.watch` 调用 | 22 | 3 文件 |
| `autoDispose` Provider | 5 | networkAvailableProvider 等 |

### 错误处理统计

| 机制 | 位置 | 说明 |
|------|------|------|
| `runZonedGuarded` + `FlutterError.onError` + Sentry | `main.dart` | 顶层兜底 |
| `try-catch + state.error` | `recognize_controller.dart` | 业务层错误状态 |
| `_onError` 回调注入 | `offline_queue_controller.dart` | 可测试异常上报 |
| `_loadError: bool` 标志 + ErrorState UI | today_meals/food_library/profile 等 | UI 层错误展示 |
| `throw ArgumentError` | `meal_log_repository.dart:28` | 哨兵防御 |
| `throw VisionRecognitionException` | `qwen_vl_provider.dart` 等 | AI 层域异常 |
| `catch (_)` | 43 处 | 异常吞没（部分 best-effort 合理，部分 UI 层无日志） |

---

**报告完成**。本次 D10 架构审计共发现 **0 P0 + 8 P1 + 7 P2**，整体健康度评级 **B（中等偏上）**。核心问题是"`recognize/providers.dart` 上帝模块 + Riverpod 退化 + 两处反向依赖"，建议按"短期移文件 → 中期拆 Provider + 加 Service Provider → 长期迁移 AsyncNotifierProvider"的渐进路线重构。所有发现均未修改任何代码，仅记录在报告中。
