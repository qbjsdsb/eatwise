# D6 平台生命周期检查报告

**检查日期**：2026-07-08
**检查范围**：EatWise v0.33.0+46（分支 trae/agent-wX1X6Q，Flutter 3.44.4 / Dart 3.12.2）
**检查方法**：Grep 关键词扫描（WidgetsBindingObserver / didChangeAppLifecycleState / StreamSubscription / Timer / TextEditingController / Workmanager / startScan / stopScan / .listen( / addListener / dispose / image_picker / Permission.）+ 逐文件审查（weight_page / mi_scale_scanner / background_dispatcher / background_tasks / main.dart / app.dart / offline_queue_controller / recognize_page / recognize_controller / calibration_page / dish_name_editor / food_library_page / settings_page / image_cleanup / auto_backup / AndroidManifest.xml / build.gradle.kts）+ 配置文件核对（compileSdk / targetSdk / minSdk / configChanges / windowSoftInputMode）

**平台配置基线**：
- `minSdk = 31`（Android 12+，动态取色硬性要求）
- `targetSdk = flutter.targetSdkVersion` → 解析为 **36**（Flutter 3.44.4 `FlutterExtension.kt:34` 定义 `val targetSdkVersion: Int = 36`，即 Android 16）
- `compileSdk = flutter.compileSdkVersion`（同 36）
- `isMinifyEnabled = false` + `isShrinkResources = false`（硬约束，防 R8 剥反射类）
- `configChanges` 声明全量配置变更（orientation|keyboard|screenSize|locale|...）→ Activity 不重建
- `windowSoftInputMode = adjustResize` → 键盘弹出时 UI 自适应

## 检查项与结果

| # | 检查项 | 状态 | 说明 |
|---|--------|------|------|
| 1 | App 生命周期管理（WidgetsBindingObserver） | ⚠️ 部分通过 | WeightPage 正确 addObserver/removeObserver + paused/resumed 处理；但**全 App 仅此一处**有生命周期观察，EatWiseApp 无全局 observer，inactive/detached 未处理 |
| 2 | BLE 扫描生命周期 | ✅ 通过 | MiScaleScanner startScan/stopScan/dispose 时序正确；isClosed 守卫防竞态崩溃；扫描冷却 5min/3次 + 30s/4次 双熔断；dispose 释放 scanner + subscription |
| 3 | 后台任务（Workmanager）注册/调度 | ✅ 通过 | callbackDispatcher top-level + @pragma('vm:entry-point')；独立 isolate 重初始化依赖；try-catch-finally + db.close；existingWorkPolicy.update 防重复注册 |
| 4 | 后台任务超时保护 | ⚠️ 部分通过 | 单条视觉调用有 60s timeout；**但 processPending 批量无总超时**，pending 多时可能超 WorkManager 系统限制（~10min）被强制终止 |
| 5 | 后台任务异常处理 | ✅ 通过 | catch 返回 false 触发指数退避重试；finally 关 DB 防泄漏；OfflineQueueController 单条异常 markFailed 不阻断批次 |
| 6 | 内存泄漏 — StreamSubscription | ✅ 通过 | 全项目仅 3 处 .listen（mi_scale_scanner / weight_page / offline_queue_controller），均在 dispose/stop 中 cancel |
| 7 | 内存泄漏 — Timer | ✅ 通过 | 仅 food_library_page._debounce 一处，dispose 中 cancel |
| 8 | 内存泄漏 — TextEditingController | ⚠️ 部分通过 | 12 个 StatefulWidget 的 state 级 controller 全部 dispose；**但 calibration_page._showEditNutritionDialog 内 4 个局部 controller 未 dispose**（与项目其他对话框不一致） |
| 9 | 内存泄漏 — StateNotifier / Listener | ✅ 通过 | recognize_page._controller dispose 释放；addListener 返回 removeListener 在 finally 调用；RefreshBus 监听 3 处均 addListener+removeListener 配对 |
| 10 | 配置变更处理（横竖屏/键盘） | ✅ 通过 | AndroidManifest configChanges 全量声明 + windowSoftInputMode=adjustResize；Flutter 引擎处理重建，State 保留 |
| 11 | Android 权限 — BLE | ✅ 通过 | Manifest 声明 BLUETOOTH_SCAN/CONNECT/ACCESS_FINE_LOCATION；点击横幅后批量请求；永久拒绝引导设置；系统定位开关检查（华为系适配） |
| 12 | Android 权限 — 相机/存储/通知 | ⚠️ 部分通过 | CAMERA/READ_MEDIA_IMAGES 声明但代码未显式 Permission.request（依赖 image_picker 自动触发，功能不受影响）；**无 POST_NOTIFICATIONS 声明**（当前不需要） |
| 13 | 图片缓存管理 | ⚠️ 部分通过 | ImageCleanup 后台清理 + 启动时 backlog>50 前台清理 + 用户可配保留期；**但 _persistImage 不删原临时文件**，依赖系统清缓存 |
| 14 | 后台隔离 | ⚠️ 部分通过 | callbackDispatcher 独立 isolate + 不访问 main ProviderContainer + 不操作 UI state；**但前后台 processPending 无跨 isolate 互斥**，可能重复处理同一 pending |

## 发现的问题

### P0（严重）

无 P0 问题。BLE 生命周期、后台任务异常处理、核心资源（StreamSubscription/Timer/State-level TextEditingController）释放整体健壮，未发现会导致崩溃/ANR/OOM 的缺陷。

### P1（高优先级）

#### P1-1：前后台 processPending 无跨 isolate 互斥，可能产生重复 meal_log + 双倍 API 消耗

- **位置**：
  - `lib/features/offline/offline_queue_controller.dart:100-128`（processPending 遍历 listPending）
  - `lib/background/background_dispatcher.dart:65-112`（_runOfflineBackfill 调 controller.processPending）
  - `lib/main.dart:106-112`（前台 OfflineQueueController.start 启动监听）
  - `lib/background/background_tasks.dart:19-25`（后台 offlineBackfill 每 15min 周期任务）
- **现状**：
  - 前台 `OfflineQueueController` 实例（main isolate）在网络恢复时调 `processPending()`，内部 `_processing` 标志防同一实例重入。
  - 后台 `callbackDispatcher`（独立 isolate）每 15min 也创建**新的** `OfflineQueueController` 实例调 `processPending()`。
  - 两个实例的 `_processing` 标志**不共享**（不同 isolate 的不同对象），`listPending()` 也无行锁/乐观锁。
  - 事务 `insertMealLog + markDone`（offline_queue_controller.dart:189-204）在单条级别原子化，但**不检查 pending 是否已被另一 isolate 标记 done**。
- **影响**：
  1. 若前后台同时触发（用户网络恢复恰好赶上 15min 周期），同一 pending 可能被处理两次 → **重复 meal_log 记录**（用户餐次翻倍，dashboard 热量虚高）。
  2. 视觉 API 被调用两次 → **双倍 token 消耗**（Qwen/GLM 计费翻倍）。
  3. `upsertAiRecognized` 可能创建重复 food_item（虽然 name+brand 有唯一约束会 upsert，但 id 不同时仍可能重复）。
- **触发概率**：低（需前后台恰好同时运行 + pending 队列非空），但一旦触发后果影响数据准确性。
- **建议**：
  1. **方案 A（推荐，低成本）**：在 `pending_recognition` 表加 `processing_locked_at` 字段，`listPending` 时 `UPDATE ... SET processing_locked_at = now WHERE id IN (...) AND processing_locked_at IS NULL` 乐观锁，处理完后 markDone/markFailed 清锁。后台 worker 启动前先清理超时锁（>10min 视为崩溃残留）。
  2. **方案 B（中等成本）**：用 `Workmanager().registerOneTimeTask` 在网络恢复时由前台触发后台任务（而非前台直接 processPending），统一走后台 isolate 处理，消除前后台并发。
  3. **方案 C（最小改动）**：前台 `OfflineQueueController.start` 时取消后台 `offlineBackfill` 周期任务的当次执行（Workmanager 无此 API，需用 unique work name + KEEP 策略），不推荐。
- **工作量**：方案 A 约 2-3 小时（加字段 + migration + listPending 改造 + 超时锁清理）

#### P1-2：后台离线回补无任务级总超时保护，批量 pending 可能超 WorkManager 系统限制被强制终止

- **位置**：
  - `lib/background/background_dispatcher.dart:26-61`（callbackDispatcher.executeTask）
  - `lib/features/offline/offline_queue_controller.dart:100-128`（processPending 遍历所有 pending）
- **现状**：
  - `callbackDispatcher` 无整体 timeout，依赖 WorkManager 系统级超时（Android 周期任务约 10 分钟）。
  - `processPending` 遍历所有 pending，单条视觉调用有 60s timeout（offline_queue_controller.dart:157,162），但若 pending 积压 20+ 条，总时长 = 20 × 60s = 20min > 系统限制。
  - 系统强制终止任务后：已 markDone 的单条已提交事务（不回滚），但未处理的 pending 丢失本次机会，等下次 15min 周期。`callbackDispatcher` catch 块返回 false 触发重试，但已处理部分不会回滚（无幂等性问题，因事务保护了单条）。
- **影响**：
  1. 大量 pending 积压时回补进度缓慢（每次 15min 只能处理 ~10 条）。
  2. 系统强制终止可能在中途切断 DB 连接（finally 中 db.close() 不保证执行）→ 连接泄漏（下次任务重新开连接，旧连接 GC 回收，但短期可能耗尽连接池）。
  3. 用户感知：离线识别后网络恢复，长时间看不到回补结果。
- **建议**：
  1. 在 `processPending` 加批次上限（如 `pending.take(10)`），单次任务只处理固定数量，剩余等下次周期。
  2. 或在 `callbackDispatcher` 包一层 `Future.any(task, Future.delayed(8min).then(() => throw TimeoutException()))` 留 2min 余量给 finally 关 DB。
- **工作量**：方案 1 约 30 分钟（listPending 加 limit 参数 + processPending 调用处传 10）

### P2（中低优先级）

#### P2-1：calibration_page._showEditNutritionDialog 的 4 个 TextEditingController 未 dispose

- **位置**：`lib/features/recognize/calibration_page.dart:866-873`
- **现状**：`_showEditNutritionDialog` 方法内创建 4 个局部 `TextEditingController`（calCtrl / proteinCtrl / fatCtrl / carbsCtrl），dialog 关闭后方法返回，**无 try-finally dispose**。
- **对比**：同项目 `weight_page._showEditWeightDialog`（weight_page.dart:991-993）和 `dish_name_editor.promptNewDishName`（dish_name_editor.dart:50-52）都有 `} finally { ctrl.dispose(); }` 模式，此处遗漏。
- **影响**：每次打开"手动修改营养值"对话框泄漏 4 个 `ChangeNotifier` 对象。GC 最终回收，但 `dispose()` 不会被调用（listeners 不显式清理）。由于这些 controller 未 `addListener`，实际影响极小，但与项目既有规范不一致。
- **建议**：包 try-finally，在 finally 中 dispose 4 个 controller（与 weight_page._showEditWeightDialog 同构）。
- **工作量**：10 分钟

#### P2-2：_startBleScan 中 isScanning.where(false).first 无 timeout 保护

- **位置**：`lib/features/weight/weight_page.dart:222`
- **现状**：
  ```dart
  await _bleScanner!.startScan(timeout: const Duration(seconds: 15));
  await FlutterBluePlus.isScanning.where((v) => v == false).first;
  ```
  `startScan` 有 15s timeout，正常触发后 `isScanning` 流应发 `false`。但若 `flutter_blue_plus` 在极端情况下（如原生层异常未通知 Dart 层）`isScanning` 不发 `false`，第二行 `await` 会**永久挂起**，导致 `_bleState` 卡在 `scanning`，用户必须手动停止或退出页面。
- **影响**：极低概率（需 flutter_blue_plus 原生层 bug），但一旦发生用户体验差（扫描状态永久卡死）。
- **建议**：第二行加 `.timeout(const Duration(seconds: 20))` 兜底（比 startScan timeout 多 5s 余量），catch TimeoutException 后走"未找到体重秤"分支。
- **工作量**：5 分钟

#### P2-3：_persistImage 不删除 image_picker 原临时文件

- **位置**：`lib/features/recognize/recognize_page.dart:250-267`
- **现状**：`_persistImage` 将图片从 `getTemporaryDirectory()`（image_picker 默认存储位置）`copy` 到 `getApplicationDocumentsDirectory()/pending_images/`，但**不 delete 原临时文件**。
- **影响**：每次拍照/选图识别后，临时目录残留一份图片副本。系统在存储压力下会自动清理临时目录，但短期内（高频使用）会积累数 MB-数十 MB 临时文件。
- **补充**：成功识别的图片也存入 `pending_images` 目录（目录名有误导性，实际存所有持久化原图，非仅离线 pending）。
- **建议**：
  1. `_persistImage` 成功 copy 后 `await src.delete()` 清理原临时文件（catch 异常不阻塞主流程）。
  2. （可选）将持久化目录从 `pending_images` 改名为 `meal_images` 更准确。
- **工作量**：10 分钟

#### P2-4：CAMERA / READ_MEDIA_IMAGES 权限未在代码中显式申请

- **位置**：
  - `android/app/src/main/AndroidManifest.xml:8`（CAMERA）
  - `android/app/src/main/AndroidManifest.xml:7`（READ_MEDIA_IMAGES）
  - 全项目无 `Permission.camera.request()` / `Permission.photos.request()` 调用
- **现状**：Manifest 声明了 CAMERA 和 READ_MEDIA_IMAGES 权限，但代码中未用 `permission_handler` 显式申请。依赖 `image_picker` 插件在调用 `pickImage` 时自动触发系统权限对话框。
- **影响**：功能不受影响（image_picker 自动处理），但：
  1. 首次拍照/选图时权限弹窗与相机/相册启动有延迟，用户体验略差。
  2. 权限被永久拒绝后，image_picker 抛异常，recognize_page 的 catch 块兜底但无引导去设置的入口（对比 BLE 路径有 `openAppSettings` 引导）。
- **建议**：在 `_pickAndRecognize` 调用 image_picker 前预先 `Permission.camera.request()` / `Permission.photos.request()`，被拒时引导设置（与 BLE 权限流程同构）。非阻塞性优化。
- **工作量**：30 分钟

#### P2-5：EatWiseApp 无全局 WidgetsBindingObserver，didChangeAppLifecycleState 未处理 inactive/detached

- **位置**：`lib/app.dart:21`（EatWiseApp extends ConsumerWidget，无生命周期管理）
- **现状**：
  - 全项目仅 `WeightPage`（weight_page.dart:67,90,102-108）使用 `WidgetsBindingObserver`，处理 `paused`/`resumed` 两个状态。
  - `inactive`（权限对话框/系统弹窗覆盖/控制中心）和 `detached`（Activity 销毁）未处理。
  - 无全局 App 级 observer 监听生命周期事件（如 Sentry breadcrumb 记录、全局网络请求暂停等）。
- **影响**：
  1. `inactive` 状态下 BLE 扫描继续（Android 上 inactive 通常由权限对话框触发，扫描继续无影响）。
  2. 无全局生命周期日志，排查后台被杀等问题时缺上下文。
  3. 对当前功能无实际影响（仅 BLE 需生命周期管理，且已局部处理）。
- **建议**：非必要优化。若未来加全局功能（如前台后台切换埋点、全局网络队列暂停），可在 `EatWiseApp` 外层包一个 `_LifecycleObserver` StatefulWidget。当前可接受。
- **工作量**：可选

#### P2-6：无 POST_NOTIFICATIONS 权限声明（前瞻性提醒）

- **位置**：`android/app/src/main/AndroidManifest.xml`（缺失 `android.permission.POST_NOTIFICATIONS`）
- **现状**：Manifest 未声明 `POST_NOTIFICATIONS`。Android 13+（API 33+，minSdk=31 涵盖 Android 12-16，Android 13+ 占多数）需运行时申请通知权限。当前 Workmanager 周期任务不发通知，故不影响。
- **影响**：当前无影响。若未来加通知功能（如"离线回补完成"通知、定时提醒记录饮食），需补声明 + 运行时申请。
- **建议**：暂不处理，未来加通知功能时一并补。
- **工作量**：N/A（未来项）

## 改进建议

### 优先级排序

| 优先级 | 问题 | 建议工作量 | 收益 |
|--------|------|-----------|------|
| P1-1 | 前后台 processPending 无跨 isolate 互斥 | 2-3h | 防重复 meal_log + 双倍 token 消耗 |
| P1-2 | 后台离线回补无任务级总超时 | 30min | 防系统强杀致回补进度停滞 |
| P2-1 | calibration_page 4 个 TextEditingController 未 dispose | 10min | 规范一致性 |
| P2-2 | isScanning.where(false).first 无 timeout | 5min | 防极端卡死 |
| P2-3 | _persistImage 不删原临时文件 | 10min | 减少临时目录膨胀 |
| P2-4 | CAMERA/READ_MEDIA_IMAGES 未显式申请 | 30min | 用户体验 + 拒绝引导 |
| P2-5 | 无全局 WidgetsBindingObserver | 可选 | 未来扩展基础 |
| P2-6 | 无 POST_NOTIFICATIONS 声明 | N/A | 未来通知功能预备 |

### 整体评价

EatWise 的平台生命周期管理**整体健壮**，未发现 P0 级崩溃/OOM 风险：

1. **BLE 生命周期是全项目最严谨的部分**——WeightPage 的 WidgetsBindingObserver 配对完整、MiScaleScanner 的 isClosed 守卫防竞态崩溃、双熔断（5min/3次 + 30s/4次）适配国产 ROM，dispose 链路完整（scanner + subscription + controller）。这块代码质量高于一般 Flutter 项目。

2. **后台任务架构清晰**——callbackDispatcher 独立 isolate + 重新初始化依赖 + try-catch-finally + db.close 是标准最佳实践。主要短板是批量无总超时（P1-2）和跨 isolate 无互斥（P1-1），均影响数据准确性而非稳定性。

3. **内存管理规范**——全项目仅 3 处 StreamSubscription、1 处 Timer、12 个 StatefulWidget 的 state 级 controller 全部 dispose，无 ScrollController/PageController/AnimationController 使用。唯一遗漏是 calibration_page 对话框内的局部 controller（P2-1），影响极小。

4. **配置变更处理标准**——AndroidManifest 的 configChanges 全量声明 + windowSoftInputMode=adjustResize 是 Flutter 项目标准配置，横竖屏切换和键盘适配无需额外处理。

5. **权限处理 BLE 路径优秀、相机/存储路径依赖插件**——BLE 权限流程完整（批量请求 + 永久拒绝引导 + 系统定位检查），但相机/存储权限依赖 image_picker 自动触发，无拒绝后引导（P2-4）。

建议优先处理 P1-1（跨 isolate 互斥）和 P1-2（任务级超时），两者共同影响后台回补的数据准确性和完成率。P2 项可在后续迭代中逐步收敛。
