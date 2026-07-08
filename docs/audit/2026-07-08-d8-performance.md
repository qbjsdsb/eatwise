# D8 性能检查报告

**检查日期**：2026-07-08
**检查范围**：EatWise v0.33.0+46
**检查人**：性能审计员（AI）
**分支**：trae/agent-wX1X6Q（HEAD = b140745，working tree clean）
**检查方法**：静态代码审查（Grep + Read），未运行性能基准测试

## 检查项与结果

| 维度 | 检查项 | 结论 | 严重度 |
|------|--------|------|--------|
| 1. DB 查询 | N+1 查询 | today_meals/dashboard 已用 getByIds 批量反查（已修复历史 N+1）；findByNameOrAlias 等多处全表扫描 | P1 |
| 1. DB 查询 | 大表无 LIMIT | getRange / getOldImagePaths / getRecentMeals / listAll 等无 LIMIT | P1/P2 |
| 1. DB 查询 | 索引 | **无任何显式索引**（仅 PK 隐式索引），8 张表均缺查询列索引 | P1 |
| 1. DB 查询 | 全表扫描 | food_item_repository 6 处 `select().get()` 全表载入（1700+ 条）做内存匹配 | P1 |
| 2. 列表性能 | ListView.builder | food_library/multi_dish/dish_name_editor 正确用 builder | ✅ |
| 2. 列表性能 | ListView（非 builder） | today_meals/weight/insight/backup/manual_entry/profile/food_edit 用 ListView | P2 |
| 2. 列表性能 | const 构造函数 | 多处已用 const；局部动态 widget 仍有优化空间 | P2 |
| 2. 列表性能 | itemExtent | 均未设置（列表项高度不固定，可接受） | P2 |
| 3. 图片性能 | image_picker 压缩 | maxWidth:1024 + imageQuality:85，合理 | ✅ |
| 3. 图片性能 | 二次压缩 | image_picker q85 → FlutterImageCompress q85，注释说明为 EXIF 校正（合理但累积损失） | P2 |
| 3. 图片性能 | originalImagePath | 存储压缩后路径（非全尺寸），合理 | ✅ |
| 3. 图片性能 | 图片缓存 | 使用默认 Image.file（无显式 cacheWidth/cacheHeight），列表渲染 56×56 缩略图未指定解码尺寸 | P2 |
| 4. rebuild | setState 范围 | weight_page _markDirty 已优化（已 dirty 不重复 setState）；多数 setState 包局部状态 | ✅ |
| 4. rebuild | const widget | 主要静态组件已 const；FutureBuilder/Consumer 模式正确 | ✅ |
| 4. rebuild | Selector/Consumer | 使用 ConsumerStatefulWidget + ref.read 模式，未用 Selector 精细过滤 | P2 |
| 5. 内存 | 大对象释放 | weight_page BLE 订阅/dispose 正确；offline_queue _sub ref.onDispose 取消 | ✅ |
| 5. 内存 | 图片缓存上限 | 未配置 PaintingBinding.imageCacheMaximumSizeBytes（默认 100MB） | P2 |
| 5. 内存 | StreamSubscription | dashboard RefreshBus listener / weight _scanSub / offline _sub 均 dispose 取消 | ✅ |
| 6. 网络 | AI 请求超时 | qwen_vl_provider 60s .timeout；offline_queue 60s .timeout | ✅ |
| 6. 网络 | http.Client 复用 | GitHubReleaseClient 单例；OffProvider 构造注入；GlmFlashProvider dashboard 用完即 close | ✅ |
| 6. 网络 | 并发控制 | dashboard _loadData 三查询并行；recommendation_service 四 Future 并行 | ✅ |
| 7. DB 迁移 | 大表 ALTER | v1→v2/v4→v5 addColumn（drift 推荐）；v3→v4 四条 UPDATE 无事务包裹（migration 隐式事务） | ✅ |
| 7. DB 迁移 | 事务 | migration 默认在事务内执行；json_importer 导入在显式事务内 | ✅ |
| 8. 启动 | main() 阻塞 | themeSeed+useDynamicColor 并行读；appConfig 提前触发不 await；DB/Workmanager/OfflineQueue 均异步不阻塞 runApp | ✅ |
| 8. 启动 | DB 懒加载 | databaseProvider 是 FutureProvider（首次 read 才打开）；ImageCleanup 启动后异步触发 | ✅ |

---

## 发现的问题

### P0（严重）

**无 P0 问题。**

DB 查询通过 `NativeDatabase.createInBackground` 在后台 isolate 执行，不阻塞 UI 线程；AI 请求有 60s 超时；启动期关键路径已并行化且不阻塞 runApp。未发现会导致 ANR / OOM / 明显卡顿的严重问题。

> 注：以下 P1 问题在数据量增长（meal_log 累积 1000+ 条、food_items 1700+ 条、长期用户 6 个月+）后会逐步影响流畅度，建议在数据量变大前修复。

---

### P1（高优先级）

#### P1-1：数据库无任何显式索引（8 张表仅 PK 隐式索引）

**位置**：`lib/data/database/tables/*.dart`，`lib/data/database/database.dart`

**证据**：Grep `TableIndex|@Index|indexes|customConstraints|UniqueIndex` 在 lib/ 下 **无任何匹配**。所有表定义仅 `integer().autoIncrement()` 主键，无 `@TableIndex` 注解，migration `onCreate` 也未 `customStatement('CREATE INDEX ...')`。

**影响**：以下高频查询随数据量线性变慢（全表扫描）：
- `meal_logs.date`：`getMealsByDate`（dashboard/today_meals 每次进入调用）、`getRange`（insight 月报 30 天）、`getMacrosByDate`
- `meal_logs.food_item_id`：`getMedianServing`（智能份量校准，每次识别调用）、外键 JOIN
- `food_items.name`：`searchByName`（LIKE 查询，食物库搜索）、`findByNameOrAlias`（已被全表内存匹配替代，但仍是根因）
- `food_items.source`：`listAllForRecommendation`（`WHERE source NOT IN ('ai_recognized')`）
- `weight_logs.date`：`getRange`（体重趋势图）
- `pending_recognitions.status`：`listPending`（离线队列轮询）、`countPending`
- `pending_recognitions.image_path`：`getByImagePath`（反馈反查 prompt_version）
- `recognition_feedbacks.meal_log_id`：`hasFeedback`（避免重复反馈）
- `recognition_feedbacks.prompt_version`：`getWrongSamples`

**当前数据量**：food_items ~1755 条（1664 FCT + 50 品牌 + 41 连锁），meal_log 长期累积。当前个人自用数据量下 <50ms，但随使用增长会恶化。

**建议**：在 table 类上添加 drift `@TableIndex` 注解（推荐）或在 migration `onCreate` 中 `customStatement('CREATE INDEX idx_meal_logs_date ON meal_logs(date)')`。需新增 migration v6（`onUpgrade` 内 `CREATE INDEX IF NOT EXISTS`，对存量用户生效）。

```dart
// food_item_table.dart 示例
@TableIndex(name: 'idx_food_items_name', columns: {#name})
@TableIndex(name: 'idx_food_items_source', columns: {#source})
class FoodItems extends Table { ... }

// meal_log_table.dart 示例
@TableIndex(name: 'idx_meal_logs_date', columns: {#date})
@TableIndex(name: 'idx_meal_logs_food_item_id', columns: {#foodItemId})
@TableIndex(name: 'idx_meal_logs_date_mealtype', columns: {#date, #mealType})
class MealLogs extends Table { ... }
```

---

#### P1-2：FoodItemRepository 6 处全表载入做内存匹配/冲突检测

**位置**：`lib/data/repositories/food_item_repository.dart`

**证据**（6 处 `select().get()` 全表载入 ~1755 条）：
- L40 `findByNameOrAlias`：每次 AI 识别调用，6 级优先级全在内存遍历
- L136 `findExactByNameOrAlias`：反馈回流精确匹配，本可用 SQL WHERE
- L244 `addAlias`：冲突检测遍历全表
- L315 `upsertAiRecognized`：新建记录时 brand 别名冲突检测
- L368 `_mergeAliasSafely`：更新记录时别名冲突检测
- L517 `insertManual`：手动录入别名冲突检测

**影响**：每次 AI 识别流程至少触发 1 次（findByNameOrAlias）全表载入 + 可能 1 次（upsertAiRecognized）+ 可能 1 次（_mergeAliasSafely）。1755 条 FoodItem 对象跨 isolate 传输（drift createInBackground）+ 内存遍历 6 级。注释称 "<50ms" 但这是每次识别的固定开销，且 food_items 只增不减。

**根因**：6 级匹配含"双向 contains + 长度约束""编辑距离 ≤1"等 SQL 难以表达的逻辑，但**优先级 1/2（精确匹配）完全可下推 SQL**：`WHERE name = ? OR aliases_json LIKE '%"?"%'` 配合索引可秒级返回，未命中再走内存模糊匹配。

**建议**：
1. 优先级 1/2 下推 SQL：`_db.foodItems.select()..where((f) => f.name.equals(query) | f.aliasesJson.like('%"$query"%'))..limit(1)`
2. 冲突检测（addAlias/upsert/insertManual）改为 SQL `EXISTS` 子查询，避免全表载入
3. 中期：将别名拆为独立 `food_aliases` 表（food_item_id + alias_text + 唯一索引），消除 JSON 解析 + 内存遍历

---

#### P1-3：listAllForRecommendation 每次进看板全表载入 1700+ 条食物

**位置**：`lib/data/repositories/food_item_repository.dart:451`，调用方 `recommendation_service.dart:171` + `ai_recommendation_service.dart:182` + `dashboard_page.dart:83`

**证据**：`listAllForRecommendation()` 返回所有非 ai_recognized 食物（~1700 条），`dashboard_page._loadRecommendations` 每次进看板调用一次，构建 `foodMap = {for (final f in foods) f.id: f}`。`recommendation_service.recommend` 内对 1700 条逐条评分（_scoreFood）。

**影响**：每次进看板/拍照返回 → 1700 行跨 isolate 传输 + 1700 次 _scoreFood 内存评分。当前 <100ms，但每次都做，且 food_items 只增不减。

**建议**：
1. 短期：Riverpod Provider 缓存 `foodMap`（food_items 变更时 invalidate），避免每次进看板重新查+构建
2. 中期：推荐算法下推 SQL（缺口匹配用 WHERE 过滤 + ORDER BY + LIMIT），而非全表载入评分

---

#### P1-4：insight_page._aggregatePeriod O(N×D) 内存过滤

**位置**：`lib/features/insight/insight_page.dart:176-191`

**证据**：
```dart
for (var i = 0; i < days; i++) {
  final date = formatYmd(start.add(Duration(days: i)));
  final dayMeals = meals.where((m) => m.date == date).toList();  // ← 每天 .where 全量
  ...
}
```
月报 `days=30`，`meals` 约 90 条 → 2700 次比较；如用户用 6 个月 `meals` 约 540 条 → 16200 次。

**影响**：月报聚合期间 UI 卡顿（虽然 _aggregatePeriod 在 FutureBuilder 异步执行，但 Dart 单线程下大量 CPU 计算仍影响响应性）。

**建议**：预分组为 `Map<String, List<MealLog>>`：
```dart
final byDate = <String, List<MealLog>>{};
for (final m in meals) {
  (byDate[m.date] ??= []).add(m);
}
for (var i = 0; i < days; i++) {
  final dayMeals = byDate[formatYmd(start.add(Duration(days: i)))] ?? [];
  ...
}
```
复杂度 O(N+D) 替代 O(N×D)。

---

#### P1-5：json_importer 单行 INSERT 循环 + 图片失效检测串行

**位置**：`lib/data/backup/json_importer.dart`

**证据**：
- L49-93：7 张表逐行 `await _db.into(...).insert(...)`，未用 drift `batch()` API。1700+ food_items + N meal_logs 逐条 INSERT
- L126-149 `_checkAndCleanImagePaths`：加载全部 meal_logs + food_items，逐行 `File.exists()` 异步 I/O + 逐行 UPDATE，串行无并发

**影响**：导入 1700+ food_items + 1000+ meal_logs 的备份文件耗时数十秒到分钟级（在事务内逐行 INSERT，每行都走 isolate 通信）。`_checkAndCleanImagePaths` 对 1000+ 行串行 File.exists + UPDATE，可能数分钟。用户感知"导入卡死"。

**建议**：
1. 用 drift `batch()` API 批量插入：
```dart
await _db.batch((b) {
  b.insertAll(_db.foodItems, foodItemsList.map(_foodItemFromJson).toList());
});
```
2. 图片失效检测：先用 SQL 一次性查出有路径的行（`WHERE original_image_path IS NOT NULL`），再分批并发 File.exists（限并发数），最后批量 UPDATE

---

#### P1-6：repository 多处"全表载入再 Dart 聚合"，应下推 SQL

**位置**：
- `recognition_feedback_repository.dart:41` `getAccuracyByPromptVersion`：`select().get()` 全表载入 → Dart for 循环聚合
- `recognition_feedback_repository.dart:31` `hasFeedback`：`select().get()` 载入所有匹配行 → `.isNotEmpty`
- `pending_recognition_repository.dart:113` `countPending`：`select().get()` 载入所有 pending → `.length`
- `meal_log_repository.dart:79` `getTotalCaloriesByDate`：`getMealsByDate` 全部载入 → Dart fold 求和
- `meal_log_repository.dart:133` `getMacrosByDate`：同上，4 项 fold
- `weight_log_repository.dart:69` `getRange`：全部载入 → Dart byDate 去重

**影响**：
- `hasFeedback`/`countPending` 载入 N 行只取 1 个 bool/int，浪费传输+内存
- `getAccuracyByPromptVersion` 应 `GROUP BY prompt_version` + `COUNT`/`SUM`，下推 SQL
- `getTotalCaloriesByDate`/`getMacrosByDate` 应 `SELECT SUM(actual_calories), SUM(actual_protein_g)...`，避免载入全部 meal_log 行

**建议**：
```dart
// hasFeedback
Future<bool> hasFeedback(int mealLogId) async {
  final row = await (_db.recognitionFeedbacks.select()
    ..where((f) => f.mealLogId.equals(mealLogId))
    ..limit(1)).getSingleOrNull();
  return row != null;
}

// countPending
Future<int> countPending() async {
  final count = await _db.recognitionFeedbacks.count(
    where: (f) => f.status.equals('pending'));
  ...
}

// getMacrosByDate（customSelect）
SELECT SUM(actual_calories) AS cal, SUM(actual_protein_g) AS p, ... FROM meal_logs WHERE date = ?

// getAccuracyByPromptVersion
SELECT prompt_version, COUNT(*) AS total, SUM(is_correct) AS correct FROM recognition_feedbacks GROUP BY prompt_version
```

---

### P2（中低优先级）

#### P2-1：多处用 ListView 而非 ListView.builder（列表项较少，影响有限）

**位置**：
- `today_meals_page.dart:281` ListView + for 循环构建所有 meal card（含 Image.file）
- `weight_page.dart:369` ListView + for 循环构建 weight tile（~30 条）
- `insight_page.dart:592` ListView 构建整个页面（图表 + 卡片，主要为固定内容）
- `backup_page.dart:33` / `manual_entry_page.dart:104` / `profile_page.dart:137` / `food_edit_page.dart:101`（表单页，固定项）

**影响**：today_meals 每日记录通常 <10 条，影响轻微；但含 Image.file 的 card 一次性构建多张图片可能造成首帧卡顿。

**建议**：today_meals 改 ListView.builder 懒加载（Dismissible 包裹不影响 builder 使用）；其余表单页可保持 ListView。

---

#### P2-2：image_cleanup.runIfBacklogLarge 双重查询

**位置**：`lib/data/backup/image_cleanup.dart:42-49`

**证据**：
```dart
static Future<void> runIfBacklogLarge(...) async {
  final candidates = await mealRepo.getOldImagePaths(days);  // 第 1 次查询
  if (candidates.length > 50) {
    await run(db, retentionDays: days);  // run 内 L19 又查一次 getOldImagePaths
  }
}
```

**影响**：启动期 ImageCleanup 若触发清理，重复查询一次 meal_logs（含 originalImagePath 非空过滤）。

**建议**：`runIfBacklogLarge` 改为直接复用已查到的 candidates 传给 `run`，避免二次查询。

---

#### P2-3：today_meals_page Image.file 未指定 cacheWidth/cacheHeight

**位置**：`lib/features/dashboard/today_meals_page.dart:414`

**证据**：`Image.file(File(m.originalImagePath!), width: 56, height: 56, fit: BoxFit.cover, ...)` 仅指定显示尺寸 56×56，未指定 `cacheWidth: 56*3, cacheHeight: 56*3`（dpr×3）。

**影响**：Flutter 默认按图片原始分辨率解码到内存，再缩放到 56×56 显示。原图虽经 image_picker maxWidth:1024 + q85 压缩（~100-300KB），但解码后位图仍占 1024×1024×4 = 4MB 内存。列表 10 张图 = 40MB 解码位图。

**建议**：
```dart
Image.file(
  File(m.originalImagePath!),
  width: 56, height: 56, fit: BoxFit.cover,
  cacheWidth: (56 * MediaQuery.devicePixelRatioOf(context) * 2).round(),  // 2x 够清晰
  cacheHeight: (56 * MediaQuery.devicePixelRatioOf(context) * 2).round(),
  ...
)
```
解码内存从 4MB 降到 ~150KB/张。

---

#### P2-4：json_exporter 全表载入 + 内存序列化

**位置**：`lib/data/backup/json_exporter.dart:14-39`

**证据**：8 张表 `select().get()` 全部载入内存，`exportAsString` 用 `JsonEncoder.withIndent` 在内存构建完整 JSON 字符串。

**影响**：长期用户 meal_logs 1000+ 条 + food_items 1700+ 条，导出 JSON 可能 5-10MB 字符串驻留内存。低内存设备可能 OOM。仅在手动备份时触发（罕见）。

**建议**：用流式 JSON 写入（`JsonEncoder.startChunkedConversion` + StreamSink）或 drift 的 `Stream<List<int>>` 导出，避免全量驻留。

---

#### P2-5：getRange / getOldImagePaths / getRecentMeals 无 LIMIT

**位置**：`meal_log_repository.dart:145` getRange、L183 getRecentMeals、L54 getOldImagePaths；`weight_log_repository.dart:69` getRange

**影响**：当前调用方传入的日期范围受限（insight 7/30 天，weight 30 天），数据量可控。但若未来扩展任意日期范围查询，无 LIMIT 保护。

**建议**：getRange 增加可选 `limit` 参数（默认 1000）防退化；getOldImagePaths 分批处理（每次 200 条）。

---

#### P2-6：recognize_controller 每次创建 ImagePicker 实例 + 双重压缩

**位置**：`lib/features/recognize/recognize_controller.dart:183`（`final picker = ImagePicker()`），L188-210

**证据**：
- L183 每次 pickAndRecognize 创建新 ImagePicker（无状态 API，影响极小）
- L188-193 image_picker imageQuality:85 → L203-210 FlutterImageCompress quality:85，注释说明为 EXIF 方向校正

**影响**：双重 JPEG 编解码（每次 ~50-100ms）。image_picker 已 maxWidth:1024，compress 又 minWidth:1024，参数一致故分辨率不再缩放，仅重编码。

**建议**：可评估 `image_picker` 的 `imageQuality` 设 100（不压缩）+ 仅靠 FlutterImageCompress 一次压缩，省一次编码。需 A/B 对比文件大小与耗时。

---

#### P2-7：WeightLogRepository.getRange 内存去重

**位置**：`lib/data/repositories/weight_log_repository.dart:69-83`（及 L96-116 getRangeForTdee 重复逻辑）

**证据**：加载范围内全部 weight_logs，Dart `byDate` Map 覆盖去重（同日取最大 id）。

**建议**：下推 SQL `SELECT * FROM weight_logs WHERE date BETWEEN ? AND ? GROUP BY date HAVING id = MAX(id)`，避免内存去重。getRange 和 getRangeForTdee 逻辑完全重复，可合并参数化。

---

#### P2-8：未配置图片缓存上限

**位置**：全项目未设置 `PaintingBinding.instance.imageCache.maximumSizeBytes`

**影响**：Flutter 默认图片缓存 100MB + 1000 张。today_meals 列表 Image.file 渲染历史食物图，长期滚动可能累积缓存。

**建议**：main.dart 启动期设置 `PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;`（个人自用 app 50MB 足够）。

---

## 改进建议

### 优先级排序（按投入产出比）

| 优先级 | 建议 | 预期收益 | 工作量 |
|--------|------|----------|--------|
| 🔴 高 | **P1-1 加 DB 索引**（meal_logs.date/food_item_id, food_items.name/source, weight_logs.date, pending_recognitions.status/image_path, recognition_feedbacks.meal_log_id/prompt_version） | 所有查询从 O(N) 全表扫描降为 O(log N)，数据量增长后效果显著 | 小（migration v6 + 重跑 build_runner） |
| 🔴 高 | **P1-4 insight 预分组 byDate** | 月报聚合从 O(N×D) 降为 O(N+D)，消除卡顿 | 极小（改 _aggregatePeriod 一处） |
| 🔴 高 | **P1-6 hasFeedback/countPending/getMacrosByDate 下推 SQL** | 减少跨 isolate 传输 + 内存分配，dashboard/feedback 路径受益 | 小（3 个方法改写） |
| 🟡 中 | **P1-2 findByNameOrAlias 优先级 1/2 下推 SQL** | AI 识别热路径减少全表载入（命中率高时秒回） | 中（需保留内存模糊匹配兜底） |
| 🟡 中 | **P1-3 listAllForRecommendation 加 Provider 缓存** | 进看板减少 1700 行重复载入 | 中（food_items 变更处 invalidate） |
| 🟡 中 | **P1-5 json_importer 用 batch() + 图片检测并发** | 备份导入从分钟级降到秒级 | 中（importer 重构） |
| 🟢 低 | **P2-3 today_meals Image.file 加 cacheWidth/Height** | 列表解码内存降 95%（4MB→150KB/张） | 极小 |
| 🟢 低 | **P2-1 today_meals 改 ListView.builder** | 大餐次日（>10 条）首帧更流畅 | 极小 |
| 🟢 低 | **P2-2 image_cleanup 去双重查询** | 启动期省一次 DB 查询 | 极小 |
| 🟢 低 | **P2-8 配置 imageCache 上限** | 长期滚动列表内存可控 | 极小 |

### 架构层面建议（中长期）

1. **food_aliases 独立表**：将 `food_items.aliasesJson`（JSON 字符串）拆为 `food_aliases(food_item_id, alias, normalized)` 表 + 唯一索引。消除 JSON 解析 + 内存遍历，findByNameOrAlias/addAlias/upsert 全部下推 SQL，性能与可维护性双赢。

2. **recommendation 算法下推 SQL**：当前 `listAllForRecommendation` + Dart 评分遍历 1700 条。可改为 SQL 预过滤（`WHERE calories_per100g BETWEEN ? AND ?` 按缺口粗筛）+ ORDER BY + LIMIT，再对 Top 50 Dart 精细评分。

3. **Drift Stream 查询替代 FutureBuilder 轮询**：当前 dashboard/today_meals 用 RefreshBus + setState 触发 _load。可改用 drift `.watch()` 流式查询（drift 自动监听表变更），数据变更自动刷新 UI，省去 RefreshBus 总线 + 手动 _load 逻辑。

### 不建议改动（已合理）

- **DB 迁移 v4 的 4 条 UPDATE**：food_items ~1755 条，UPDATE 在 migration 隐式事务内，毫秒级完成，无需优化
- **AI 请求超时 60s**：复杂图识别确实需要时间，过短会误杀
- **image_picker maxWidth:1024 + q85**：合理的尺寸/质量平衡
- **启动期并行化**：themeSeed/useDynamicColor Future.wait + appConfig 提前触发 + DB/Workmanager/OfflineQueue 异步不阻塞，已是最优
- **NativeDatabase.createInBackground**：DB 操作在后台 isolate，不阻塞 UI

---

## 验证方法

本报告为静态代码审查结论。建议修复后用以下方式验证：

1. **DB 索引效果**：`EXPLAIN QUERY PLAN SELECT * FROM meal_logs WHERE date = '2026-07-08'` 修复前为 `SCAN TABLE meal_logs`，修复后应为 `SEARCH TABLE meal_logs USING INDEX idx_meal_logs_date`
2. **insight 聚合**：用 6 个月 mock 数据（540 条 meal_log）测月报 `_aggregatePeriod` 耗时，应从 >50ms 降到 <10ms
3. **json_importer**：用 1700 food_items + 1000 meal_logs 的备份文件测导入耗时，batch() 后应从 >30s 降到 <3s
4. **flutter analyze + flutter test**：修复后跑全量回归（基线 1172 passed）

---

## 附录：检查的文件清单

**已读关键文件**：
- `lib/data/database/database.dart`（schema v5 + migration + databaseProvider）
- `lib/data/database/connection.dart`（NativeDatabase.createInBackground）
- `lib/data/database/tables/{food_item,meal_log,weight_log}_table.dart`
- `lib/data/repositories/{food_item,meal_log,weight_log,pending_recognition,recognition_feedback}_repository.dart`
- `lib/data/backup/{json_exporter,json_importer,image_cleanup}.dart`
- `lib/main.dart`（启动流程）
- `lib/features/dashboard/{dashboard_page,today_meals_page}.dart`
- `lib/features/weight/weight_page.dart`（fl_chart 双轴图）
- `lib/features/insight/insight_page.dart`（fl_chart 多图表 + 聚合）
- `lib/features/food_library/food_library_page.dart`（ListView.builder + 防抖搜索）
- `lib/features/recognize/{recognize_controller,multi_dish_page}.dart`
- `lib/features/offline/offline_queue_controller.dart`（后台回补第三路径）
- `lib/ai/{qwen_vl,glm_4v}_provider.dart`（AI 请求超时）
- `lib/nutrition/recommendation_service.dart`（推荐算法）

**Grep 覆盖**：ListView 模式 / drift .get().watch() / image_picker / http.Client / @TableIndex（无匹配）/ getRange 等大查询调用点
