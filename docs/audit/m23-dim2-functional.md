# M23 维度 2：功能完整性审查

## 审查范围

逐个 feature 走查"主路径 + 异常路径 + 边界条件"，列死路 / 未覆盖异常 / 不一致行为。

**审查对象**：EatWise v0.21.0+33（M22 后基线）

**审查的 10 个功能流**：
1. 识别主流程（recognize_page / recognize_controller / writeCalibratedMealLog）
2. AI 兜底三路径一致性（recognize_page / multi_dish_page / offline_queue_controller）
3. 离线队列（pending_recognition_repository / offline_queue_controller）
4. 备份 / 恢复（json_exporter / json_importer / backup_page / auto_backup / image_cleanup）
5. 应用内更新（update_service / apk_downloader / apk_installer / github_release_client / update_page）
6. 洞察生成（insight_page / insight_repository）
7. 推荐系统（ai_recommendation_service / recommendation_service / user_preference_learner / tdee_calibrator）
8. 体重记录（weight_page）
9. 食物库（food_library_page / food_edit_page / food_item_repository）
10. 设置页（settings_page）

**分级标准**：
- **P0**：崩溃 / 数据丢失 / 安全漏洞 / 硬约束违反 / 功能完全不可用
- **P1**：功能可用但关键异常路径未覆盖 / 明显数据不一致 / UX 致用户可预见损失
- **P2**：边界场景体验问题 / 代码注释陈旧 / 轻微不一致 / 防御性兜底污染数据

**6 条硬约束核查结果**：
| # | 硬约束 | 核查位置 | 结果 |
|---|--------|----------|------|
| 1 | build.gradle.kts `isMinifyEnabled=false` + `isShrinkResources=false` | `android/app/build.gradle.kts#L62-L63` | ✅ 满足 |
| 2 | meal_log.food_item_id 非空 FK，哨兵 0 写库前必须替换 | `lib/data/repositories/meal_log_repository.dart#L25-L27` | ✅ 满足（insertMealLog + updateMealLog 双重 ArgumentError 防御） |
| 3 | AI 兜底三路径全覆盖（recognize_page / multi_dish_page / offline_queue_controller） | 见 2.2 节 | ✅ 满足（三处均调 CalibratedNutritionCalculator.compute） |
| 4 | per100g 反算基于 estimatedWeightGMid（非 servingG） | `lib/features/recognize/calibrated_nutrition_calculator.dart`（三路径统一调用） | ✅ 满足 |
| 5 | SecureConfigStore 无 `instance` 静态属性 | `lib/core/config/secure_config_store.dart#L14-L37` | ✅ 满足（仅构造函数 + forTesting） |
| 6 | initSentryAndRunApp 命名参数 `container:` + `app:` | `lib/main.dart#L69-L75` | ✅ 满足 |

---

## 发现清单

### 2.1 识别主流程

**主路径**：拍照 → recognize_controller.recognize → VisionProvider → 结果校验 → 跳校准页 → writeCalibratedMealLog → mealRepo.insertMealLog

**异常路径**：断路器 → L1 重试（429 Retry-After）→ L2 切备 → L3 转手动 → 外层 catch 离线入队

**边界**：哨兵 foodItemId=0 → upsertAiRecognized 替换为真实 id

#### 发现 2.1-1（P2）：单品无营养数据路径静默 return null，UI 反馈链路依赖调用方

`lib/features/recognize/recognize_page.dart#L169-L172`

```dart
} else {
  // 无营养数据（查库未命中），不记录
  return null;
}
```

writeCalibratedMealLog 在「单品查库未命中 + 无 AI 估算」时返回 null。该返回值由调用方（校准页确认按钮）处理。代码本身正确（不写 0 卡 meal_log），但 return null 是"静默不记录"，依赖调用方给用户明确反馈。若调用方未区分"返回 null（无数据）"与"返回 0（成功但 0 卡）"，用户可能困惑为何点击确认后无记录。建议核查所有 writeCalibratedMealLog 调用点对 null 返回值的 toast 处理。

**风险**：低。校准页通常会拦截无营养数据的情况，此分支理论不触达，属防御性兜底。

#### 发现 2.1-2（无发现）：容灾链路完整性

`lib/features/recognize/recognize_controller.dart#L258-L294`

容灾链路设计完备：
- 429 Retry-After ≤ 60s → 等待后 L1 重试，失败转 L2
- 非 retryable（401/403/malformed JSON）→ L3 转手动
- retryable 非 429（网络/超时/5xx）→ L2 切备，失败 rethrow 走外层离线入队
- 断路器 recordSuccess best-effort（持久化失败不阻塞识别结果）

**结论**：无发现。容灾链路覆盖完整，retryable 与非 retryable 错误分流清晰。

---

### 2.2 AI 兜底三路径一致性（硬约束 3 重点）

**三路径哨兵分支核查**：

| 路径 | 位置 | 处理方式 |
|------|------|----------|
| 前台单品 | `lib/features/recognize/recognize_page.dart#L85-L112` | CalibratedNutritionCalculator.compute + upsertAiRecognized |
| 前台复合菜（多菜页） | `lib/features/recognize/multi_dish_page.dart#L818-L831` | CalibratedNutritionCalculator.compute + upsertAiRecognized |
| 后台回补单品 | `lib/features/offline/offline_queue_controller.dart#L231-L247` | CalibratedNutritionCalculator.compute + upsertAiRecognized |
| 后台回补复合菜 | `lib/features/offline/offline_queue_controller.dart#L301-L322` | 包装 OCR 优先 + packageMacrosAllZero 守卫 + AI 估算回退 |

三路径均统一调用 CalibratedNutritionCalculator.compute，per100g 反算基于 estimatedWeightGMid，包装 OCR 优先级与品类校准由 calculator 内部统一处理。**硬约束 3 满足。**

#### 发现 2.2-1（P2）：multi_dish_page 防御性兜底创建 0 卡 food_item 污染食物库

`lib/features/recognize/multi_dish_page.dart#L923-L935`

```dart
} else {
  // 主菜/附加菜均无营养数据（理论不应到这里，因 _hitFlags[i] 已守卫）
  // 防御性兜底：用 effectiveName 创建空 food_item，避免后续 insertMealLog FK 违规
  foodItemId = await foodRepo.upsertAiRecognized(
    name: effectiveName,
    brand: dish.brand,
    caloriesPer100g: 0,
    proteinPer100g: 0,
    fatPer100g: 0,
    carbsPer100g: 0,
    confidence: dish.confidence,
  );
}
```

该 else 分支位于 `if (_currentSingles[i] != null) ... else if (composite != null) ... else` 链尾。注释自述"理论不应到这里"，因 L796 `if (!_hitFlags[i]) continue` 已守卫。但若因任何逻辑变更导致 `_hitFlags[i]=true` 但 `_currentSingles[i]==null && composite==null` 同时成立，会创建一个 0 卡 / 0 蛋白 / 0 脂 / 0 碳的 food_item 并落库。

**影响**：
- 不崩溃（foodItemId 非 0，FK 不违规，硬约束 2 不触发）
- 但污染食物库：未来该菜名查库命中会返回 0 卡记录，后续识别走"查库命中"分支时营养值全 0
- 且 meal_log.actualCalories 也为 0，用户记录了一条"0 卡餐次"

**建议**：该分支应改为 markFailed 或 throw（与 offline_queue_controller.dart#L257-L259 单品无估算路径一致：标记 failed 让用户手动处理），而非创建 0 卡 food_item 静默落库。

#### 发现 2.2-2（无发现）：三路径 packageMacrosAllZero 守卫一致性

v1.10 含糖饮料碳水缺失修复的三层防御在三路径中均一致实现：
- 前台单品：CalibratedNutritionCalculator 内部
- 前台复合菜：`multi_dish_page.dart` _calcNutrition（与 offline L285-L300 同逻辑）
- 后台复合菜：`offline_queue_controller.dart#L285-L300` + `L354-L357`

**结论**：无发现。三路径防御逻辑一致。

---

### 2.3 离线队列

**主路径**：离线拍照 → enqueue → pending_recognitions 表 → 网络恢复 → processPending → 回补识别 → markDone / markFailed

**异常路径**：重试 5 次后永久 failed / 图片缺失 permanent failed / 事务保护防并发计数丢失

#### 发现 2.3-1（P2）：类注释"重试上限 3 次"过时，实际为 5 次

`lib/features/offline/offline_queue_controller.dart#L23`

```dart
/// 离线队列前台触发控制器
/// 监听 connectivity_plus 网络恢复事件，自动回补 pending 识别（重试上限 3 次）
```

类注释写"重试上限 3 次"，但实际 `pending_recognition_repository.dart#L96-L99` 的 markFailed 用 `retryCount >= 4` 判断（即重试 5 次后标记 failed）。M16.2 已将阈值 3→5，但此处注释未同步更新。

**影响**：误导维护者对重试次数的认知，排障时可能误判 failed 时机。

#### 发现 2.3-2（P2）：永久 failed 项无 UI 入口提示用户

`lib/data/repositories/pending_recognition_repository.dart#L72-L105`

markFailed 在 permanent=true（图片缺失）或 retryCount≥4 时标记 status='failed'，这些记录留在 pending_recognitions 表中不再重试。但 `countPending()` (L108-L113) 仅统计 status='pending'，UI 角标不显示 failed 项数量。

**影响**：用户离线拍照后若图片被清理（image_cleanup 30 天保留期）或重试 5 次仍失败，对应餐次静默丢失，用户无感知（除非主动翻数据库）。建议设置页或离线队列页展示 failed 项数量 + 允许用户手动重试 / 删除。

**风险**：中。30 天保留期 + 5 次重试通常足以在网络恢复前完成回补，但极端场景（长期离线 + 图片清理）会丢餐次。

#### 发现 2.3-3（无发现）：并发安全

`lib/data/repositories/pending_recognition_repository.dart#L88-L104` markFailed 用 `db.transaction` 包裹 read-then-write，防"立即重试"与后台 workmanager 并发读到同一 retryCount 双写 +1。L92 `if (current == null) return` 处理记录已被删除的并发场景。

**结论**：无发现。并发保护完备。

---

### 2.4 备份 / 恢复

**主路径**：导出（全表 → JSON 文件）/ 导入（粘贴 JSON → 清空 8 表 → 批量插入事务）/ 自动备份（每周 + 保留 4 份）/ 图片清理（30 天）

#### 发现 2.4-1（P1）：导入备份清空 pending_recognitions 队列，确认弹窗未告知用户

`lib/data/backup/json_importer.dart#L41`

```dart
await _db.customStatement('DELETE FROM pending_recognitions;');
```

`lib/data/backup/json_exporter.dart#L7` + `L37`

```dart
/// 全表导出 JSON（含 schemaVersion）
/// 不导出 pending_recognitions（临时队列）
... // 注意：pending_recognitions 不导出（临时队列）
```

`lib/features/backup/backup_page.dart#L155-L161`

```dart
final confirmed = await confirmAction(
  context,
  title: '确认导入',
  content: '导入将清空当前所有数据（档案、食物库、餐次记录、体重、汇总、反馈），此操作不可撤销。\n\n确定继续？',
  ...
);
```

**问题**：
1. json_exporter 设计上**不导出** pending_recognitions（临时队列，合理）
2. 但 json_importer **导入时会 DELETE FROM pending_recognitions**（清空当前队列）
3. 备份页确认弹窗列举"档案、食物库、餐次记录、体重、汇总、反馈"6 项，**未提及离线队列**

**影响**：用户有 N 条 pending 离线识别（已拍照未上传），导入一份旧备份后，这 N 条记录被清空，对应餐次照片对应的数据丢失，用户无感知。从用户视角这是"数据丢失"，且未在确认弹窗中告知，违反"破坏性操作需知情同意"原则。

**建议**：
- 确认弹窗补充"离线队列中 N 条待识别记录将被清空"
- 或导入时保留当前 pending_recognitions（不清空），仅清空导出包含的 7 张表

#### 发现 2.4-2（P2）：导入仅支持粘贴 JSON 文本，无文件级导入

`lib/features/backup/backup_page.dart#L119-L150`

```dart
Future<void> _import() async {
  final ctrl = TextEditingController();
  ...
  content: TextField(
    controller: ctrl,
    maxLines: 12,
    ...
    decoration: const InputDecoration(
      hintText: '粘贴之前导出的 JSON 文本…',
    ),
  ),
```

导入入口仅提供一个 12 行的 TextField 让用户粘贴 JSON 文本。但导出（L100-L109）是写文件到 `getApplicationDocumentsDirectory()`，文件可能含数月 meal_logs 历史，JSON 体积可达数百 KB 甚至 MB 级。要求用户手动粘贴大 JSON 不现实（且移动端剪贴板有长度限制）。

**影响**：备份/恢复功能在实际使用中几乎不可用（除非数据量极小）。导出能写文件，导入却不能读文件，UX 不对称。

**建议**：增加文件选择器（file_picker 包）读取 .json 文件导入，与导出对称。

#### 发现 2.4-3（P2）：自动备份文件名仅含日期，同日多次备份互相覆盖

`lib/data/backup/auto_backup.dart#L26-L29`

```dart
final fileName =
    'eatwise_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';
final file = File('${backupDir.path}/$fileName');
await file.writeAsString(jsonStr);
```

文件名格式 `eatwise_backup_YYYYMMDD.json`，无时分秒。若同一天自动备份 + 手动导出触发多次 run()，后者覆盖前者（writeAsString 默认 overwrite）。手动导出（backup_page L104-L106）文件名含时分，不冲突；但自动备份同日多次会丢前面的版本。

**影响**：低。自动备份通常每周一次，同日多次概率低；且保留 4 份的逻辑基于修改时间，覆盖后仍是最新的。但若用户同日手动触发多次后台任务，会少一份备份。

#### 发现 2.4-4（无发现）：导入事务原子性 + 图片失效检测

`lib/data/backup/json_importer.dart#L33-L44` 清空 + 插入用 `db.transaction` 包裹，中途失败回滚避免半库。DELETE 顺序先子后父规避 FK 级联。ImageCheckResult 检测图片缺失并提示用户。

**结论**：无发现。事务设计与图片失效检测完备。

---

### 2.5 应用内更新

**主路径**：检查更新（GitHub Releases API）→ semver 比较 → 下载 APK（流式）→ 触发系统安装器

**异常路径**：版本号解析失败 / 网络错误 / HTTP 非 200 / 下载中断 / 写盘失败 / 安装器触发失败

#### 发现 2.5-1（P2）：下载失败后重试按钮重新走"检查更新"而非"重新下载"

`lib/features/update/update_page.dart#L268-L284`

```dart
case _UpdateState.error:
  return [
    ...
    FilledButton.icon(
      onPressed: _busy ? null : _check,  // 调 _check 而非 _download
      icon: const Icon(Icons.refresh),
      label: const Text('重试'),
    ),
  ];
```

error 状态下"重试"按钮无差别调 `_check`（重新检查更新）。若错误来源是下载失败（_state 从 downloading → error），用户点重试后会被带回 idle/checking 流程，需重新检查→重新点"下载并安装"，多一次交互。

**影响**：低。功能可用，仅 UX 多一步。建议根据 _state 前态（downloading vs checking）智能选择重试动作。

#### 发现 2.5-2（P2）：APK 下载无断点续传，78MB 失败需从头重下

`lib/core/update/apk_downloader.dart#L39-L113`

download 方法用 `http.Request('GET', ...)` 全量流式下载，无 Range 请求头支持。若下载到 70MB 时网络中断，下次重试从 0 开始。L80-L82 下载前删除旧文件（避免半截残留），逻辑正确但意味着无续传。

**影响**：中低端网络环境下大版本更新体验差。78MB APK 在弱网下可能多次失败无法完成更新。

**建议**：可用 Range 请求实现续传（记录已下载字节数，重试时从断点继续），但实现复杂度较高，属优化项非 bug。

#### 发现 2.5-3（P2）：APK 完整性仅校验 content-length，无 SHA256

`lib/core/update/apk_downloader.dart#L106-L110`

```dart
// 校验下载完整性（仅 content-length 已知时）
if (total > 0 && received != total) {
  throw ApkDownloadException(
      '下载不完整：$received / $total bytes（可能网络中断）');
}
```

仅校验字节数一致，未校验内容哈希。若 CDN 中间人篡改 APK 字节数不变但内容被替换，下载层无法发现。

**缓解**：Android 系统安装器会校验 APK 签名（与 build.gradle.kts 固定 keystore 一致），篡改 APK 签名不匹配会安装失败。故此为纵深防御缺失而非实际漏洞。

**影响**：低。依赖系统签名校验兜底，但纵深防御最佳实践建议下载层也校验 release notes 中公布的 SHA256。

#### 发现 2.5-4（无发现）：版本比较与错误处理

`lib/core/update/version_comparator.dart` semver 比较正确。`update_service.dart#L29-L47` checkForUpdate 捕获 ReleaseFetchFailedException / ReleaseAssetNotFoundException / FormatException / 未知错误，全部转为 CheckFailed 不向 UI 抛。

**结论**：无发现。错误处理完备。

---

### 2.6 洞察生成

**主路径**：选周期（周/月）→ 聚合数据 → 检查 key/网络/数据 → 调 GLM-4-Flash → 落库 insight_summaries

**异常路径**：key 未配置 / 无网络 / 0 天记录 / AI 调用失败

#### 发现 2.6-1（P2）：GLM-4-Flash 调用无重试/退避，与 ai_recommendation_service 不一致

`lib/features/insight/insight_page.dart#L287-L289`

```dart
final text = _periodType == 'weekly'
    ? await provider.generateWeeklySummary(data)
    : await provider.generateMonthlySummary(data);
```

`lib/nutrition/ai_recommendation_service.dart#L1-L16`（注释说明有缓存 + 退避重试 + dedup）

洞察生成调 GLM-4-Flash 后直接 await，无重试/退避。若遇网络抖动或 429，直接进 catch (L304) 显示"生成失败：$e"。对比 ai_recommendation_service 有缓存 + 退避重试 + dedup 完整容灾。

**影响**：低。用户可手动点"重新生成"重试，但周报/月报生成场景下数据已聚合，重试成本不高，缺重试仅是多一次点击。两处 AI 调用容灾策略不一致属代码风格问题。

#### 发现 2.6-2（无发现）：守卫链路完整性

`lib/features/insight/insight_page.dart#L226-L263` 守卫顺序合理：
1. L235 key 未配置 → 提示去设置页
2. L245 无网络 → 提示联网
3. L256 0 天记录 → 提示先记录

key/网络/数据三层守卫齐全，且顺序正确（config 优先于网络优先于数据）。

**结论**：除 2.6-1 外无发现。

---

### 2.7 推荐系统

**主路径**：v4 九维评分本地推荐 + v5 AI 个性化推荐（渐进增强，失败 v4 兜底）

**异常路径**：AI 失败/超时/解析错误 → 静默返回空 → v4 本地推荐兜底

#### 发现 2.7-1（无发现）：降级原则与缓存设计

`lib/nutrition/ai_recommendation_service.dart#L1-L16` 注释清晰描述降级原则："AI 是锦上添花，任何失败都不应阻塞 UI，v4 本地推荐永远兜底"。缓存当日有效（key=date+mealType+profileHash），解析失败不缓存（区分"AI 返回 0 条"与"解析失败"）。

#### 发现 2.7-2（无发现）：TDEE 自适应校准

`lib/features/weight/weight_page.dart#L405-L417` TDEE 校准包裹在 try-catch 中，失败不影响体重记录主流程。校准开关由 SecureConfigStore.tdeeAutoCalib 控制（默认开启）。

**结论**：无发现。推荐系统降级链路与 TDEE 校准容错完备。

---

### 2.8 体重记录

**主路径**：输入体重 → 校验 → 写 weight_logs + 同步 profile.weightKg → 触发 TDEE 校准 → RefreshBus 通知

**异常路径**：输入无效 / 写库失败 / TDEE 校准失败（不阻塞主流程）

#### 发现 2.8-1（P2）：新记录仅支持今日，无法补录往日体重

`lib/features/weight/weight_page.dart#L382-L396`

```dart
Future<void> _save() async {
  if (_busy) return; // 防重入
  if (_weightCtrl.text.isEmpty) return;
  final weight = double.tryParse(_weightCtrl.text);
  ...
  await repo.insert(date: today, weightKg: weight);  // date 硬编码 today
```

`_save` 中 `final today = todayYmd()`（L395）硬编码为今日，新记录只能写入今日。若用户忘记录昨日体重，无法补录往日记录。编辑已有记录（L440 Dismissible + onTap）可能支持改日期，但新增入口不支持。

**影响**：中。体重追踪连续性受影响，TDEE 校准（基于 4 周观察窗口）若缺数据会降低准确性。属产品设计取舍，但与"餐次记录支持选日期"不一致。

#### 发现 2.8-2（无发现）：防重入与状态同步

L383 `_busy` 防重入 ✓，L403 同步 profile.weightKg ✓，L423 RefreshBus.notify() 通知 dashboard 刷新 ✓，L426 `_dirty = false` 防止 clear 误触发未保存确认 ✓。

**结论**：除 2.8-1 外无发现。

---

### 2.9 食物库

**主路径**：列表（常吃 + 搜索）→ 编辑 / 复用

**异常路径**：搜索竞态 / 加载失败

#### 发现 2.9-1（无发现）：搜索防抖与竞态保护

`lib/features/food_library/food_library_page.dart#L62-L80` 搜索 debounce 300ms + 序列号校验（_searchSeq），丢弃乱序到达的旧结果。L55-L56 加载失败保持空列表显示空态，不崩溃。

**结论**：无发现。搜索竞态保护完备。

---

### 2.10 设置页

**主路径**：加载配置 → 编辑（key/url/开关）→ 保存

**异常路径**：加载失败 / 保存失败 / 未保存确认

#### 发现 2.10-1（无发现）：防重入与未保存确认

`lib/features/settings/settings_page.dart#L36-L43` `_isSaving` 防重入 + `_dirty` 未保存确认 + `_loading` 守门防初始赋值误标 dirty。PopScope 拦截返回键提示未保存。

**结论**：无发现。设置页状态管理完备。

---

## 维度 2 汇总

### 发现统计

| 严重度 | 数量 | 占比 |
|--------|------|------|
| P0 | 0 | 0% |
| P1 | 1 | 9% |
| P2 | 10 | 91% |
| **合计** | **11** | 100% |

### 各功能流发现分布

| 功能流 | P0 | P1 | P2 | 小计 |
|--------|----|----|----|----|
| 2.1 识别主流程 | 0 | 0 | 1 | 1 |
| 2.2 AI 兜底三路径一致性 | 0 | 0 | 1 | 1 |
| 2.3 离线队列 | 0 | 0 | 2 | 2 |
| 2.4 备份/恢复 | 0 | 1 | 2 | 3 |
| 2.5 应用内更新 | 0 | 0 | 3 | 3 |
| 2.6 洞察生成 | 0 | 0 | 1 | 1 |
| 2.7 推荐系统 | 0 | 0 | 0 | 0 |
| 2.8 体重记录 | 0 | 0 | 1 | 1 |
| 2.9 食物库 | 0 | 0 | 0 | 0 |
| 2.10 设置页 | 0 | 0 | 0 | 0 |

### 6 条硬约束核查

**全部满足（0 违反）**：
1. ✅ build.gradle.kts R8 关闭
2. ✅ foodItemId 哨兵防御（insertMealLog + updateMealLog 双重 ArgumentError）
3. ✅ AI 兜底三路径全覆盖（均调 CalibratedNutritionCalculator.compute）
4. ✅ per100g 反算基于 estimatedWeightGMid
5. ✅ SecureConfigStore 无 instance 静态属性
6. ✅ initSentryAndRunApp 命名参数

### 整体评价

EatWise v0.21.0+33 功能完整性**整体良好**：

1. **无 P0**：6 条硬约束全部满足，无崩溃/数据丢失/安全漏洞/功能完全不可用问题。AI 兜底三路径一致性（历史最易出 bug 处）经核查完全对齐，CalibratedNutritionCalculator 抽象统一了三路径行为。

2. **1 个 P1**：备份导入清空 pending_recognitions 队列且确认弹窗未告知用户，属"破坏性操作未知情同意"。建议优先修复（补弹窗提示 or 导入时保留 pending 表）。

3. **10 个 P2**：多为 UX 优化项与防御性兜底污染：
   - 备份导入仅支持粘贴 JSON（与导出不对称）
   - APK 下载无断点续传 / 无 SHA256 校验
   - 洞察 GLM 调用无重试（与推荐服务不一致）
   - 体重记录无法补录往日
   - 离线队列永久 failed 项无 UI 入口
   - multi_dish_page 防御性兜底创建 0 卡 food_item
   - 注释陈旧（重试上限 3→5 未同步）

4. **3 个功能流零发现**（推荐系统 / 食物库 / 设置页）：状态管理与容错完备。

### TOP 3 最严重问题摘要

1. **【P1】备份导入静默清空离线队列**（`lib/data/backup/json_importer.dart#L41`）
   - 导入备份会 DELETE FROM pending_recognitions，但 json_exporter 不导出该表，确认弹窗也未提及。用户有 pending 离线识别时导入旧备份会丢失这些餐次记录且无感知。建议补弹窗提示或导入时保留 pending 表。

2. **【P2】multi_dish_page 防御性兜底创建 0 卡 food_item 污染食物库**（`lib/features/recognize/multi_dish_page.dart#L923-L935`）
   - "理论不应到这里"的 else 分支会 upsertAiRecognized 一个全 0 营养的 food_item 并落库 meal_log。虽不崩溃（FK 不违规），但污染食物库未来查库命中。建议改为 markFailed 或 throw，与 offline_queue_controller 单品无估算路径一致。

3. **【P2】备份导入仅支持粘贴 JSON 文本，无文件级导入**（`lib/features/backup/backup_page.dart#L119-L150`）
   - 导出能写文件，导入却只能粘贴 12 行 TextField。大备份文件（含数月 meal_logs）粘贴不现实，移动端剪贴板有长度限制。备份/恢复功能在实际数据量下几乎不可用。建议增加 file_picker 读取 .json 文件导入。
