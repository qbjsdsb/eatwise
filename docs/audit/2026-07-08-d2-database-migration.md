# P0-D2: 数据库迁移完整性 + schema 快照审查

## 检查日期 / HEAD commit / 当前 schemaVersion

| 项目 | 值 |
|---|---|
| 检查日期 | 2026-07-08 |
| HEAD commit | `bb308735ff068c9e03b64340e934747a1fe5c8a7` |
| 最近提交说明 | `fix(build): 修复 build_runner 失败——sqlparser 0.44.5 override + 重新生成 database.g.dart` |
| 当前 schemaVersion | **5**（`database.dart:36`） |
| drift 版本 | `^2.34.0`（pubspec.yaml） |
| drift_dev 版本 | `^2.34.0`（dev_dependencies，sqlparser override 锁 0.44.5） |
| 数据库类 | `EatWiseDatabase`（`lib/data/database/database.dart`） |
| 表数量 | 8 张 |

---

## 迁移链路审查

迁移代码位于 `lib/data/database/database.dart:39-75`，采用 **`if (from < N)` 级联写法**（drift 官方推荐），非 switch-case，因此**不存在 break/fallthrough 问题**。每个版本块独立 `await`，drift 会按 from 值顺序执行所有满足条件的块，自动实现 v1→v2→v3→v4→v5 的逐步升级。

| 版本 | 变更内容 | 代码位置 | 正确性 | 备注 |
|---|---|---|---|---|
| v1→v2 | `profiles` 加 3 列：`specialCondition` / `dietPreference` / `healthCondition`（全部 nullable） | `database.dart:44-48` | ✅ 正确 | `m.addColumn` 三次调用，顺序与表定义一致；nullable 向后兼容，旧数据 null 视为 'none' |
| v2→v3 | 新增 `recommendation_feedbacks` 表 | `database.dart:50-52` | ✅ 正确 | `m.createTable(recommendationFeedbacks)` 仅建表无数据迁移；表定义见 `recommendation_feedback_table.dart`，无外键（设计如此，注释说明 AI 推荐食物可能不在库） |
| v3→v4 | 清理脏营养数据：4 条 `UPDATE food_items SET ... = 0 WHERE ... > 阈值` | `database.dart:59-68` | ✅ 正确（设计如此） | 阈值：蛋白/脂肪/碳水 > 100、热量 > 900；用 `customStatement` 执行原生 SQL；**置 0 不删除**，条目仍存在，靠 `_isDirtyFoodItem` + 全 0 跳过兜底（见 `food_item_repository.dart:121-127` 及 `nutrition_lookup_test.dart` M16.5 测试组） |
| v4→v5 | `weight_logs` 加 `impedance` + `bodyFatPct`（nullable） | `database.dart:71-74` | ✅ 正确 | M27v2 蓝牙体脂秤2 扩展；`m.addColumn` 两次，与 `weight_log_table.dart:9-10` 定义一致 |

**其他迁移策略要素**：

| 要素 | 位置 | 正确性 |
|---|---|---|
| `onCreate` | `database.dart:40` `m.createAll()` | ✅ 首次创建建所有表 |
| `beforeOpen` PRAGMA foreign_keys | `database.dart:79` | ✅ 启用外键约束（recognition_feedbacks ON DELETE CASCADE 依赖此） |
| `schemaVersion` | `database.dart:36` = 5 | ✅ 与最新迁移块 v5 一致 |
| 首次创建 seed profile id=1 | `database.dart:82-96` | ✅ 单行表初始化 |
| `seedOnCreate` 控制食物种子导入 | `database.dart:102-113` | ✅ 测试默认 false（空库），生产 true；try-catch 防资源缺失阻塞 DB 创建 |

**结论**：迁移链路逻辑正确，5 个版本的升级路径完备，无遗漏列/表，无错误的 SQL 语法。

---

## 表结构审查（8 张表完整性）

表文件位于 `lib/data/database/tables/`。

### 1. `profiles`（`profile_table.dart`）
- 主键：`id`（`clientDefault(() => 1)`，单行表）✅
- nullable：`bodyFatPct` / `carbGPerKg` / `specialCondition` / `dietPreference` / `healthCondition` ✅
- 默认值：`tdeeAdjustmentKcal` 默认 0 ✅
- v2 新增 3 列均 nullable 向后兼容 ✅
- 外键：无（独立配置表）

### 2. `food_items`（`food_item_table.dart`）
- 主键：`id`（`autoIncrement`）✅
- nullable：`aliasesJson` / `ediblePercent` / `confidence` / `componentsJson` / `thumbnailPath` ✅
- NOT NULL：`name` / `defaultServingG` / `caloriesPer100g` / `proteinPer100g` / `fatPer100g` / `carbsPer100g` / `source` / `sourceVersion` / `createdAt` ✅
- 外键：无（食物库根表）✅
- **注意**：`name` 无 UNIQUE 约束，依赖 `name + source` 组合查重（`upsertAiRecognized` 用 `name.equals & source.equals('ai_recognized')`）—— 设计如此

### 3. `meal_logs`（`meal_log_table.dart`）⭐ 硬约束 #2 重点
- 主键：`id`（`autoIncrement`）✅
- **`foodItemId` 非空外键** `integer().references(FoodItems, #id)()` ✅ **满足硬约束 #2**
- 外键未显式指定 `onDelete`，默认 `NO ACTION`（删 food_item 前必须先删引用它的 meal_log，否则 FK 约束违规）—— 设计如此，food_item 极少删除
- nullable：`originalImagePath` / `recognitionConfidence` / `componentsSnapshotJson` ✅
- NOT NULL：`date` / `mealType` / `foodItemId` / `actualServingG` / `actualCalories` / `actualProteinG` / `actualFatG` / `actualCarbsG` / `loggedAt` ✅
- **仓储层哨兵防御**：`meal_log_repository.dart:28-30` 拦截 `foodItemId <= 0`，抛 `ArgumentError`，防止 0 哨兵写入非空 FK ✅

### 4. `weight_logs`（`weight_log_table.dart`）⭐ M27v2 重点
- 主键：`id`（`autoIncrement`）✅
- **`impedance` / `bodyFatPct` 均 nullable** ✅ 向后兼容 v1 蓝牙秤无此数据
- NOT NULL：`date` / `weightKg` ✅
- 外键：无 ✅

### 5. `pending_recognitions`（`pending_recognition_table.dart`）
- 主键：`id`（`autoIncrement`）✅
- `resultFoodItemId` nullable 外键 `references(FoodItems, #id)` ✅（识别失败时为 null）
- 默认值：`retryCount` 默认 0 ✅
- nullable：`resultFoodItemId` / `errorMessage` / `promptVersion` / `processedAt` ✅
- NOT NULL：`imagePath` / `mealType` / `date` / `status` / `createdAt` ✅

### 6. `insight_summaries`（`insight_summary_table.dart`）
- 主键：`id`（`autoIncrement`）✅
- 默认值：`isEdited` 默认 0 ✅
- NOT NULL：`periodType` / `periodStart` / `periodEnd` / `summaryText` / `generatedAt` ✅
- 外键：无 ✅

### 7. `recognition_feedbacks`（`recognition_feedback_table.dart`）
- 主键：`id`（`autoIncrement`）✅
- `mealLogId` 非空外键 `references(MealLogs, #id, onDelete: KeyAction.cascade)` ✅
- **ON DELETE CASCADE** 显式声明，删 meal_log 自动级联删反馈 ✅（`database_test.dart:70-108` 有级联删除测试覆盖）
- nullable：`correctedDishName` / `correctedServingG` ✅
- NOT NULL：`mealLogId` / `isCorrect` / `promptVersion` / `createdAt` ✅

### 8. `recommendation_feedbacks`（`recommendation_feedback_table.dart`）
- 主键：`id`（`autoIncrement`）✅
- **无外键**（设计如此，注释说明：AI 推荐食物可能不在食物库，避免用户记录前先入库的约束）✅
- nullable：`mealType` / `recommendDate` ✅
- NOT NULL：`foodName` / `rating` / `createdAt` ✅
- **文档不一致**：文件头注释 "v5 渐进增强"，实际迁移代码在 v2→v3 引入（见 P2-6）

### 表结构审查小结
- 8 张表主键、外键、nullable、默认值定义均正确
- 硬约束 #2（`meal_log.food_item_id` 非空外键）满足，仓储层有哨兵防御
- M27v2 字段（`weight_logs.impedance/bodyFatPct`）nullable 正确
- **共性隐患**：无显式索引定义（drift 默认不为外键建索引），高频查询字段如 `meal_logs.food_item_id` / `meal_logs.date` / `weight_logs.date` / `pending_recognitions.status` 全表扫，数据量大时性能下降（见 P2-8）

---

## schema 快照缺失影响分析

### 现状
```
drift_schemas/eatwise_database/
└── drift_schema_v1.json    # 仅 v1，v2-v5 缺失
```

`build.yaml` 已配置：
```yaml
schema_dir: drift_schemas/
test_dir: test/drift/       # 但 test/drift/ 目录不存在
```

### CI 校验现状（`.github/workflows/ci.yml`）

CI **仅有 build_runner 产物同步校验**，无 schema 快照校验：

```yaml
- name: Verify generated code is up to date (build_runner)
  run: |
    dart run build_runner build --delete-conflicting-outputs
    if ! git diff --exit-code -- lib/data/database/database.g.dart; then
      echo "::error::database.g.dart 与 schema 不同步..."
      exit 1
    fi
```

### 影响分析

| 影响项 | 严重度 | 说明 |
|---|---|---|
| **schema-driven 迁移测试无法编写** | P1 | drift 推荐做法：用 `drift_dev schema generate` 从快照生成各版本验证辅助类，写"从 v1 逐步升级到 v5"测试。v2-v5 快照缺失 → 无法写此类测试 |
| **CI 漏检迁移代码与表定义不一致** | P1 | `database.g.dart` 同步校验只能保证"生成代码与表定义一致"，不能发现"表定义加列但 `onUpgrade` 漏写 `addColumn`"类问题。例如：开发者在 `meal_logs` 加了新列，`build_runner` 重新生成 `.g.dart` 通过 CI，但若忘在 migration v5→v6 加 `addColumn`，老用户升级后崩溃，CI 无法捕获 |
| **v2-v5 升级路径无回归保护** | P1 | 当前 `test/data/database_test.dart` 只测 `onCreate`（首次创建），不测 `onUpgrade`。若 migration 代码被误改（如删掉 v3→v4 的某条 UPDATE），无测试会失败 |
| **无法验证迁移幂等性** | P2 | 老用户从 v1 升级 vs 新用户首次创建 v5，两者最终 schema 应一致。无快照无法做等价性校验 |

### drift 正确导出 schema 快照的命令

drift 2.34 推荐流程（参考 drift 官方文档 [Schema migrations](https://drift.simonbinder.eu/Migrations/tests/)）：

```bash
# 步骤 1：导出所有版本的 schema 快照（一次导出 v1-v5）
# 命令会模拟每个版本的 schema 并导出 JSON
dart run drift_dev schema dump lib/data/database/database.dart drift_schemas/

# 导出后目录结构：
# drift_schemas/eatwise_database/
#   drift_schema_v1.json
#   drift_schema_v2.json
#   drift_schema_v3.json
#   drift_schema_v4.json
#   drift_schema_v5.json

# 步骤 2：从快照生成迁移测试辅助类
dart run drift_dev schema generate drift_schemas/ test/drift/

# 生成后可在 test/drift/ 写迁移测试：
# - migration_test.dart：从 v1 逐步升级到 v5，每步验证 schema
# - 用 GeneratedDatabase.schemaVersion 验证最终版本
# - 用 expect(database.schemaVersion, 5) 等断言
```

**补齐 v2-v5 快照的完整修复步骤**：

1. **确认迁移代码正确**（本次审查已完成，5 个版本迁移链路正确）
2. 跑 `dart run drift_dev schema dump lib/data/database/database.dart drift_schemas/` 生成 v1-v5 全部快照
3. 跑 `dart run drift_dev schema generate drift_schemas/ test/drift/` 生成迁移测试辅助类
4. 编写 `test/drift/migration_test.dart`：
   - 测试 v1→v5 逐步升级，每步验证表/列存在性
   - 测试 v1→v5 一次性升级（跨多版本）
   - 测试 v5 全新创建与 v1 升级到 v5 的 schema 等价性
5. CI 增加步骤：
   ```yaml
   - name: Verify schema snapshots up to date
     run: |
       dart run drift_dev schema dump lib/data/database/database.dart /tmp/schema_check/
       if ! diff -rq /tmp/schema_check/eatwise_database drift_schemas/eatwise_database; then
         echo "::error::schema 快照缺失或过期，请跑 'dart run drift_dev schema dump lib/data/database/database.dart drift_schemas/' 后提交"
         exit 1
       fi
   - name: Migration tests
     run: flutter test test/drift/
   ```

---

## 迁移测试覆盖评估

### 现有测试

| 测试文件 | 覆盖范围 | 是否测迁移 |
|---|---|---|
| `test/data/database_test.dart` | onCreate 路径：profile 初始化、food_item 插入、meal_log 外键、recognition_feedback 级联删除 | ❌ 只测首次创建（`NativeDatabase.memory()` 走 onCreate），不测 onUpgrade |
| `test/ai/nutrition_lookup_test.dart` | nutrition_lookup 业务逻辑，注释提到 M16.3 migration v3→v4 后的脏数据 | ❌ 业务测试，非迁移测试 |
| `test/data/food_seed_importer_dirty_test.dart` | 脏数据导入防护 | ❌ 测导入器，非迁移 |
| `test/data/meal_log_repository_test.dart` | meal_log CRUD | ❌ 不涉及升级 |
| `test/data/weight_log_repository_test.dart` | weight_log CRUD（含 M27v2 字段） | ❌ 不涉及升级 |

### 覆盖缺口

1. **无 v1→v2 升级测试**：未验证老用户升级后 `profiles` 表是否有 3 个新列
2. **无 v2→v3 升级测试**：未验证 `recommendation_feedbacks` 表存在
3. **无 v3→v4 升级测试**：未验证脏数据被置 0（虽然 `nutrition_lookup_test.dart` M16.5 组测了"全 0 条目跳过"，但那是业务逻辑兜底，不是迁移本身）
4. **无 v4→v5 升级测试**：未验证 `weight_logs` 表有 `impedance` / `bodyFatPct` 列
5. **无跨版本升级测试**：未验证 v1→v5 一次性升级的正确性
6. **无 schema 等价性测试**：未验证"新用户 onCreate 创建的 v5"与"老用户 onUpgrade 升级到的 v5"schema 一致

### drift 推荐做法

drift 官方强烈推荐用 schema 快照驱动迁移测试（见上文"补齐步骤"）。当前项目 `build.yaml` 已配 `test_dir: test/drift/` 但目录为空，说明**项目最初设计了 schema-driven 测试但未实施**。

---

## 连接层 + 加密审查

`lib/data/database/connection.dart` 审查：

### ⚠️ 重大发现：加密已移除（与任务描述/项目规则不符）

```dart
/// 打开数据库连接（明文版，移除 sqlite3mc 加密避免 native 库兼容问题）
///
/// 历史：曾用 sqlite3mc 加密，但 build hooks 在 CI release 模式下
/// 可能未正确编译 native 库导致运行时崩溃。个人自用 app 加密是过度设计，
/// 临时移除以排除 native 库问题，恢复稳定后可再评估。
Future<QueryExecutor> openEncryptedConnection() async {
  final dir = await getApplicationDocumentsDirectory();
  final dbFile = File(p.join(dir.path, _dbName));
  return NativeDatabase.createInBackground(dbFile);
}
```

**与多处文档不一致**：
- 任务描述说"sqlite3mc 加密"——实际已明文
- `pubspec.yaml:13` 注释"drift 2.32+ + sqlite3mc 加密"——实际无加密
- 项目规则（`.trae/rules/project_handoff.md`）说"sqlite3mc 加密"——实际无加密
- 函数名仍叫 `openEncryptedConnection`——名不副实

### 其他连接层要素

| 要素 | 状态 | 说明 |
|---|---|---|
| `PRAGMA foreign_keys = ON` | ✅ | 在 `database.dart:79` beforeOpen 设置（非 connection.dart） |
| WAL 模式 | ❌ 未启用 | `NativeDatabase` 默认 rollback journal，未设 `PRAGMA journal_mode=WAL`。个人自用低并发可接受，高并发写略差 |
| 后台 isolate | ✅ | `NativeDatabase.createInBackground` 在独立 isolate 运行，避免主线程 jank |
| 数据库文件路径 | ✅ | `getApplicationDocumentsDirectory()` + `eatwise.db` |

### 加密移除的安全影响

- 数据库文件以明文存储在 app 私有目录（`/data/data/<pkg>/files/eatwise.db`）
- Android 私有目录默认其他 app 不可读，但 root 设备/备份提取可读
- 个人自用 app 风险可接受，但应在文档中明确"已移除加密"避免误判

---

## 仓储层事务完整性

抽查 8 个仓储（`lib/data/repositories/`），重点看 **read-then-write 模式**是否用事务包裹防并发。

### 事务使用统计

| 仓储 | 事务使用 | 评估 |
|---|---|---|
| `food_item_repository` | `addAlias`（L232）✅<br>`upsertAiRecognized`（L286）✅ | read-then-write 都包事务，防并发产生重复记录/反向错配 |
| `pending_recognition_repository` | `markFailed`（L93）✅ | 注释说明防"立即重试"与 workmanager 并发致计数丢失 |
| `insight_repository` | `regenerate`（L55）✅ | delete + insert 原子化，防旧 summary 被删但新 summary 未写入 |
| `meal_log_repository` | 无事务 | 全是单条 CRUD + 只读查询，无需事务 ✅ |
| `weight_log_repository` | 无事务 | 全是单条 CRUD + 只读查询，无需事务 ✅ |
| `profile_repository` | 无事务 | ⚠️ `get()` 行缺失时 select-then-insert 无事务（见 P2-7） |
| `recommendation_feedback_repository` | 无事务 | 单条 insert + clearAll，无需事务 ✅ |
| `recognition_feedback_repository` | 无事务 | 单条 insert + 只读查询，无需事务 ✅ |

### 重点仓储抽查

#### `meal_log_repository`（硬约束 #2 关键）
- `insertMealLog`（L13-45）：单条 insert，**有哨兵防御** `if (foodItemId <= 0) throw ArgumentError` ✅
- `updateMealLog`（L91-124）：单条 update，**有哨兵防御** `if (foodItemId != null && foodItemId <= 0) throw` ✅
- `deleteMealLog`（L127-129）：单条 delete，依赖 `recognition_feedbacks` ON DELETE CASCADE 级联 ✅
- `getRecentFoodCounts` / `getMealTypeDistribution`：原生 SQL `GROUP BY` 聚合，只读 ✅
- **无需事务**：所有写操作都是单条原子操作

#### `weight_log_repository`（M27v2 关键）
- `insert`（L14-29）：支持 `impedance` / `bodyFatPercent` nullable 参数 ✅
- `update`（L39-57）：部分更新，null 跳过（`Value.absent`）✅
- `getRange` / `getRangeForTdee`：同日多条去重在内存做（`byDate` Map 覆盖），非批量写 ✅
- **无需事务**：所有写操作都是单条原子操作

#### `profile_repository`
- `get()`（L16-57）：**select-then-insert 无事务** ⚠️
  - 行缺失时 `getSingleOrNull` 返回 null → insert 默认 profile → 再 select
  - 竞态：两个调用同时读到 null，都尝试 insert id=1，第二个因主键冲突失败
  - 实际风险低：单用户单 profile 行，UI 不太可能并发调用 get()
  - 但若并发发生，第二个调用会抛 `UniqueConstraintException`，调用方无 try-catch 会崩溃
- `update` / `clearBodyFatPct`：单条 update ✅

### 事务完整性结论

仓储层事务使用**整体合理**，所有 read-then-write 模式（`addAlias` / `upsertAiRecognized` / `markFailed` / `regenerate`）都有事务包裹。唯一边界是 `profile_repository.get()` 的 select-then-insert 无事务，实际风险低（见 P2-7）。

---

## 发现的问题（P0/P1/P2 分级）

### P0（阻断级，需立即修复）

**无 P0 问题**。迁移链路逻辑正确，硬约束 #2 满足，无外键约束违规风险。

### P1（高优先级，建议本 sprint 修复）

#### P1-1：schema 快照 v2-v5 缺失
- **位置**：`drift_schemas/eatwise_database/`（仅 v1）
- **影响**：schema-driven 迁移测试无法编写；CI 无法校验迁移代码与表定义一致性
- **修复**：跑 `dart run drift_dev schema dump lib/data/database/database.dart drift_schemas/` 生成 v2-v5 快照并提交
- **验证**：`drift_schemas/eatwise_database/` 应有 5 个 JSON 文件

#### P1-2：迁移测试完全缺失
- **位置**：`test/drift/`（目录不存在，但 `build.yaml` 配了 `test_dir: test/drift/`）
- **影响**：v1→v5 升级路径无回归保护；migration 代码被误改无测试失败
- **修复**：
  1. 跑 `dart run drift_dev schema generate drift_schemas/ test/drift/` 生成辅助类
  2. 编写 `test/drift/migration_test.dart`：v1→v5 逐步升级 + 跨版本升级 + schema 等价性
  3. 测试要点：
     - v1→v2：验证 `profiles` 有 3 个新列
     - v2→v3：验证 `recommendation_feedbacks` 表存在
     - v3→v4：验证脏数据被置 0（插入 carbs=450 的条目，升级后应为 0）
     - v4→v5：验证 `weight_logs` 有 `impedance` / `bodyFatPct` 列
     - v1→v5 一次性升级 + onCreate 创建的 v5 schema 等价

#### P1-3：CI 缺 schema 快照校验步骤
- **位置**：`.github/workflows/ci.yml`
- **影响**：表定义加列但 migration 漏 `addColumn`，CI 不报错，老用户升级崩溃
- **修复**：CI 增加 `Verify schema snapshots up to date` 步骤（见上文修复步骤第 5 步）

### P2（中优先级，可后续 sprint 处理）

#### P2-4：加密已移除但文档未更新
- **位置**：`connection.dart`（已明文）vs `pubspec.yaml:13` 注释 / 项目规则 / 任务描述（仍提 sqlite3mc）
- **影响**：文档与代码不一致，误导审计/新成员
- **修复**：
  1. 更新 `pubspec.yaml:13` 注释为"drift 2.34（明文存储，加密已移除见 connection.dart）"
  2. 评估是否更新项目规则 `.trae/rules/project_handoff.md` 相关描述
  3. 函数名 `openEncryptedConnection` 建议改为 `openConnection`（或加注释说明历史）
- **决策权**：是否恢复加密需用户决定（个人自用可接受明文）

#### P2-5：WAL 模式未启用
- **位置**：`connection.dart`
- **影响**：`NativeDatabase` 默认 rollback journal，高并发写性能略差
- **修复**：在 `beforeOpen` 加 `await customStatement('PRAGMA journal_mode=WAL;');`（drift 推荐做法）
- **优先级**：个人自用低并发可接受，非必须

#### P2-6：`recommendation_feedback_table.dart` 注释版本错误
- **位置**：`recommendation_feedback_table.dart:3` 注释"AI 推荐满意度反馈存储（v5 渐进增强）" 和 `recommendation_feedback_repository.dart:3` 同样注释
- **实际**：该表在 v2→v3 引入（`database.dart:50-52`），非 v5
- **影响**：文档误导，v5 实际变更是 `weight_logs` 加 `impedance`/`bodyFatPct`
- **修复**：注释改为"v3 引入"

#### P2-7：`profile_repository.get()` 无事务
- **位置**：`profile_repository.dart:16-57`
- **影响**：select-then-insert 竞态下可能主键冲突崩溃（id=1 clientDefault）
- **修复**：包事务，或用 `INSERT OR IGNORE` 替代 select-then-insert
- **优先级**：实际风险低（单用户单 profile 行不太可能并发）

#### P2-8：高频查询字段无索引
- **位置**：8 张表均无 `@TableIndex` 或显式索引
- **影响**：`meal_logs.food_item_id`（外键反查）、`meal_logs.date`（按日查询）、`weight_logs.date`、`pending_recognitions.status` 等高频查询全表扫
- **修复**：drift 2.x 用 `@TableIndex(name: 'idx_meal_logs_date', columns: {#date})` 等注解加索引
- **优先级**：当前数据量小无感，数据量大（千条 meal_log）后查询变慢

---

## 结论

### 整体评估

| 维度 | 评分 | 说明 |
|---|---|---|
| 迁移链路正确性 | ✅ 优 | 5 个版本迁移代码逻辑正确，无遗漏列/表，无 SQL 语法错误，`if (from < N)` 级联写法无 break/fallthrough 问题 |
| 表结构完整性 | ✅ 优 | 8 张表主键/外键/nullable/默认值定义正确，硬约束 #2 满足 |
| schema 快照管理 | ❌ 差 | v2-v5 快照缺失，schema-driven 测试无法编写，CI 无快照校验 |
| 迁移测试覆盖 | ❌ 差 | 仅测 onCreate，onUpgrade 完全无测试，`test/drift/` 目录为空 |
| 连接层 | ⚠️ 中 | PRAGMA foreign_keys ON ✅，但加密已移除（文档不一致）、WAL 未启用 |
| 仓储事务完整性 | ✅ 良 | read-then-write 模式都有事务，单条 CRUD 无需事务；`profile_repository.get()` 边界问题 |

### 关键结论

1. **迁移代码本身正确**，老用户从 v1 升级到 v5 不会因迁移逻辑 bug 崩溃
2. **最大风险在测试覆盖缺失**：迁移代码无回归测试保护，未来误改迁移代码（如删某条 `addColumn`）CI 不会失败，只能在生产用户升级时发现
3. **schema 快照缺失是根因**：导致 schema-driven 测试无法编写、CI 无法校验迁移与表定义一致性
4. **加密已移除但文档未同步**：不是 bug，但文档不一致会误导后续审计/开发

### 建议优先级

1. **本 sprint**：补齐 v2-v5 schema 快照（P1-1）+ 编写迁移测试（P1-2）+ CI 加快照校验（P1-3）
2. **下 sprint**：修文档不一致（P2-4 / P2-6）+ `profile_repository.get()` 事务（P2-7）
3. **可选**：WAL 模式（P2-5）+ 索引（P2-8），数据量上来后再加

---

*报告生成 by P0-D2 审查任务，仅检查未改代码。*
