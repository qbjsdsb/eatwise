# EatWise Sprint 1 实现计划：核心拍照识别闭环

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 跑通"拍一张苹果照片 → AI 识别 → 校准 → 写入今日记录"的端到端闭环，验证 Qwen-VL 中文食物识别 + JSON 结构化输出的最大风险点。

**Architecture:** Flutter + drift 2.34 (sqlite3mc AES 加密) + Riverpod 3.x 状态管理 + go_router 路由 + openai_dart 调用 Qwen-VL (response_format=json_object)。数据层 7 张表，营养数据来自本地《中国食物成分表》而非模型直出。拍照识别走"模型识别菜名+估份量 → 查库回填营养素"两步推理。

**Tech Stack:** Flutter 3.x, drift ^2.34.0, sqlite3 ^3.3.2 (build hooks: sqlite3mc), flutter_secure_storage ^10.3.1, flutter_riverpod ^3.3.2, go_router ^17.2, openai_dart ^7.0, image_picker, flutter_image_compress, connectivity_plus

**参考设计文档:** [`docs/superpowers/specs/2026-07-01-eatwise-design.md`](../specs/2026-07-01-eatwise-design.md)（以下简称"设计文档"）

**Sprint 1 成功标准:** 拍一个苹果 → Qwen-VL 返回 `{dish_name:"苹果", is_single_item:true, confidence:0.9, estimated_weight_g_mid:180}` → 查库命中 → 校准页（置信度≥0.85 允许一键记录）→ 写入 meal_log → 今日额度看板显示热量增加。

---

## 文件结构

Sprint 1 涉及的文件（按职责分层）：

```
lib/
  main.dart                          # App 入口 + ProviderScope + Sentry 初始化占位
  app.dart                           # MaterialApp + go_router 配置
  core/
    error/sentry_init.dart           # Sentry 初始化（Sprint 3 完善，此处占位空函数）
  data/
    database/
      database.dart                  # drift Database 定义 + 加密打开 + 7 张表
      database.g.dart                # build_runner 生成（入库）
      tables/
        profile_table.dart           # profile 表
        food_item_table.dart         # food_item 表
        meal_log_table.dart          # meal_log 表
        weight_log_table.dart        # weight_log 表
        pending_recognition_table.dart # pending_recognition 表
        insight_summary_table.dart   # insight_summary 表
        recognition_feedback_table.dart # recognition_feedback 表
      connection.dart                # 加密 NativeDatabase 打开（PRAGMA key）
    repositories/
      food_item_repository.dart      # food_item CRUD + name/aliases 查询
      meal_log_repository.dart       # meal_log CRUD
      profile_repository.dart        # profile 单行读写
    seed/
      food_seed_importer.dart        # Sanotsu JSON 导入 + 字段映射 + 别名补充
  features/
    profile/
      nutrition_calculator.dart      # BMR/TDEE/宏量计算（纯函数，无 UI）
      profile_page.dart              # 档案录入 UI（Sprint 1 最简版）
    recognize/
      recognize_page.dart            # 拍照入口页
      calibration_page.dart          # 校准页（置信度分级 + 滑块）
      recognize_controller.dart      # 拍照→预处理→调 API→查库 状态机
    dashboard/
      dashboard_page.dart            # 今日额度看板（Sprint 1 最简版）
  ai/
    vision_provider.dart             # VisionProvider 抽象接口 + 数据类
    qwen_vl_provider.dart            # Qwen-VL 实现（openai_dart + response_format=json_object）
    glm_4v_provider.dart             # GLM-4V-Plus 容灾实现
    prompts.dart                     # system prompt + few-shot + 版本号
    nutrition_lookup.dart            # 识别结果→查库回填（单品/复合菜两条路径）
test/
  features/
    nutrition_calculator_test.dart   # 营养公式单元测试
  data/
    food_seed_importer_test.dart     # 导入清洗单元测试
    food_item_repository_test.dart   # 查库 + aliases 匹配测试
  ai/
    vision_response_parser_test.dart # JSON 解析容错测试
    nutrition_lookup_test.dart       # 查库回填路径测试
  fixtures/
    sanotsu_sample.json              # Sanotsu 数据集样本（测试用，入库）
drift_schemas/                       # make-migrations 产物（入库）
build.yaml                           # drift_dev databases 配置
pubspec.yaml                         # 依赖 + sqlite3mc build hooks
```

---

## Task 1: 项目脚手架

**目标:** Flutter 项目初始化、依赖配置、sqlite3mc build hooks、build.yaml、目录结构、App 能编译运行空页面。

**Files:**
- Create: `pubspec.yaml`
- Create: `build.yaml`
- Create: `lib/main.dart`
- Create: `lib/app.dart`
- Create: `lib/core/error/sentry_init.dart`
- Modify: `android/app/build.gradle` (minSdk 23)
- Modify: `ios/Runner/Info.plist` (相机/相册权限)

- [ ] **Step 1: 创建 Flutter 项目**

```bash
cd /workspace
flutter create --org com.eatwise --project-name eatwise .
```

注意：`flutter create .` 在已有文件的目录会保留现有文件（README/.gitignore/LICENSE/docs），只生成 Flutter 工程文件。若提示覆盖，选 No 保留现有。

- [ ] **Step 2: 覆写 pubspec.yaml**

写入以下完整内容（替换 flutter create 生成的默认 pubspec.yaml）：

```yaml
name: eatwise
description: 拍照识别食物热量 + 营养记录 + AI 汇总建议（个人自用）
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter

  # 数据库（drift 2.32+ + sqlite3mc 加密）
  drift: ^2.34.0
  sqlite3: ^3.3.2
  # 注意：不要加 sqlite3_flutter_libs（已 EOL）
  # 注意：不要加 sqlcipher_flutter_libs（已 EOL，drift 2.32+ 用 sqlite3mc 替代）

  # 密钥存储
  flutter_secure_storage: ^10.3.1

  # 状态管理 + 路由
  flutter_riverpod: ^3.3.2
  go_router: ^17.2

  # 拍照 + 图片预处理
  image_picker: ^1.2.2
  flutter_image_compress: ^2.4.0

  # 网络 + 离线检测
  connectivity_plus: ^6.1.0

  # 大模型 API（OpenAI-compatible，百炼/智谱通用）
  openai_dart: ^7.0.0

  # 图表
  fl_chart: ^0.70.0

  # 工具
  path_provider: ^2.1.0
  path: ^1.9.0
  uuid: ^4.5.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

  # drift 代码生成 + 迁移工具
  drift_dev: ^2.34.1
  build_runner: ^2.15.0

  # 测试
  mocktail: ^1.0.0

# sqlite3mc build hooks 配置（drift 2.32+ 加密方案）
# 必须放在 pubspec.yaml 顶层，不是 build.yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlite3mc

flutter:
  uses-material-design: true
```

- [ ] **Step 3: 创建 build.yaml（drift_dev make-migrations 前置配置）**

```yaml
targets:
  $default:
    builders:
      drift_dev:
        options:
          databases:
            eatwise_database: lib/data/database/database.dart
          schema_dir: drift_schemas/
          test_dir: test/drift/
```

- [ ] **Step 4: 修改 Android minSdk 为 23（flutter_secure_storage 10.x 要求）**

修改 `android/app/build.gradle`，在 `defaultConfig` 块中设置：

```gradle
android {
    defaultConfig {
        applicationId "com.eatwise.eatwise"
        minSdkVersion 23  // flutter_secure_storage 10.x 要求
        targetSdkVersion flutter.targetSdkVersion
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
    }
}
```

- [ ] **Step 5: 添加 iOS 权限声明**

修改 `ios/Runner/Info.plist`，在 `<dict>` 内 `<key>CFBundleDisplayName</key>` 之前添加：

```xml
<key>NSCameraUsageDescription</key>
<string>拍照识别食物并记录热量</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>从相册选择食物照片进行识别</string>
```

- [ ] **Step 6: 创建 Sentry 初始化占位**

创建 `lib/core/error/sentry_init.dart`：

```dart
/// Sprint 3 完善，此处占位。
/// Sprint 1 只需 App 能编译运行，不实际接入 Sentry。
Future<void> initSentry() async {
  // TODO Sprint 3: 接入 sentry_flutter
}
```

- [ ] **Step 7: 创建 main.dart**

创建 `lib/main.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/error/sentry_init.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSentry();
  runApp(const ProviderScope(child: EatWiseApp()));
}
```

- [ ] **Step 8: 创建 app.dart（最简路由 + 空首页）**

创建 `lib/app.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EatWiseApp extends StatelessWidget {
  const EatWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'EatWise',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const _PlaceholderPage(title: 'EatWise Sprint 1'),
    ),
  ],
);

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(child: Text('Sprint 1 脚手架就绪')),
    );
  }
}
```

- [ ] **Step 9: 创建目录结构**

```bash
mkdir -p lib/core/error lib/core/monitoring \
  lib/data/database/tables lib/data/repositories lib/data/seed \
  lib/features/profile lib/features/recognize lib/features/dashboard \
  lib/ai \
  test/features test/data test/ai test/fixtures \
  drift_schemas
```

- [ ] **Step 10: 拉取依赖并验证编译**

```bash
flutter pub get
```

预期：无报错，依赖解析成功。

- [ ] **Step 11: 验证 sqlite3mc build hooks 生效**

```bash
flutter analyze
```

预期：0 errors。

- [ ] **Step 12: 运行空 App 验证**

```bash
flutter run -d <设备ID或模拟器>
```

预期：App 启动，显示"Sprint 1 脚手架就绪"。

- [ ] **Step 13: Commit**

```bash
git add pubspec.yaml build.yaml android/app/build.gradle ios/Runner/Info.plist lib/ test/ drift_schemas/
git commit -m "feat: Sprint 1 脚手架 - Flutter 初始化 + drift/sqlite3mc/Riverpod/go_router 依赖配置"
```

---

## Task 2: drift 加密数据库 + 7 张表

**目标:** 定义 7 张表的 drift schema、加密打开数据库、make-migrations 生成迁移代码、加密读写测试通过。

**Files:**
- Create: `lib/data/database/tables/profile_table.dart`
- Create: `lib/data/database/tables/food_item_table.dart`
- Create: `lib/data/database/tables/meal_log_table.dart`
- Create: `lib/data/database/tables/weight_log_table.dart`
- Create: `lib/data/database/tables/pending_recognition_table.dart`
- Create: `lib/data/database/tables/insight_summary_table.dart`
- Create: `lib/data/database/tables/recognition_feedback_table.dart`
- Create: `lib/data/database/connection.dart`
- Create: `lib/data/database/database.dart`
- Test: `test/data/database_test.dart`

- [ ] **Step 1: 创建 profile 表定义**

创建 `lib/data/database/tables/profile_table.dart`：

```dart
import 'package:drift/drift.dart';

/// 个人档案表（单行表，id 固定为 1）
class Profiles extends Table {
  IntColumn get id => integer().clientDefault(() => 1)();
  RealColumn get heightCm => real()();
  RealColumn get weightKg => real()();
  RealColumn get bodyFatPct => real().nullable()();
  IntColumn get age => integer()();
  TextColumn get gender => text()(); // 'male' / 'female'
  RealColumn get activityLevel => real()(); // 1.2/1.375/1.55/1.725/1.9
  TextColumn get goal => text()(); // 'cut' / 'bulk' / 'maintain'
  RealColumn get goalRateKgPerWeek => real()();
  TextColumn get formula => text()(); // 'mifflin' / 'katch'
  IntColumn get dailyCalorieTarget => integer()();
  RealColumn get proteinGPerKg => real()();
  RealColumn get fatGPerKg => real()();
  RealColumn get carbGPerKg => real().nullable()();
  IntColumn get tdeeAdjustmentKcal => integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer()(); // UTC 毫秒

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: 创建 food_item 表定义**

创建 `lib/data/database/tables/food_item_table.dart`：

```dart
import 'package:drift/drift.dart';

/// 食物库表（含识别入库和手动入库）
class FoodItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  RealColumn get defaultServingG => real()();
  RealColumn get caloriesPer100g => real()();
  RealColumn get proteinPer100g => real()();
  RealColumn get fatPer100g => real()();
  RealColumn get carbsPer100g => real()();
  TextColumn get aliasesJson => text().nullable()();
  RealColumn get ediblePercent => real().nullable()();
  TextColumn get source => text()(); // china_fct/usda/off/manual/ai_recognized
  TextColumn get sourceVersion => text()();
  RealColumn get confidence => real().nullable()();
  TextColumn get componentsJson => text().nullable()();
  TextColumn get thumbnailPath => text().nullable()();
  IntColumn get createdAt => integer()(); // UTC 毫秒
}
```

- [ ] **Step 3: 创建 meal_log 表定义**

创建 `lib/data/database/tables/meal_log_table.dart`：

```dart
import 'package:drift/drift.dart';
import 'food_item_table.dart';

/// 餐次记录表
class MealLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()(); // 'YYYY-MM-DD' 本地时区自然日
  TextColumn get mealType => text()(); // breakfast/lunch/dinner/snack
  IntColumn get foodItemId => integer().references(FoodItems, #id)();
  RealColumn get actualServingG => real()();
  RealColumn get actualCalories => real()();
  RealColumn get actualProteinG => real()();
  RealColumn get actualFatG => real()();
  RealColumn get actualCarbsG => real()();
  TextColumn get originalImagePath => text().nullable()();
  RealColumn get recognitionConfidence => real().nullable()();
  TextColumn get componentsSnapshotJson => text().nullable()();
  IntColumn get loggedAt => integer()(); // UTC 毫秒
}
```

- [ ] **Step 4: 创建 weight_log 表定义**

创建 `lib/data/database/tables/weight_log_table.dart`：

```dart
import 'package:drift/drift.dart';

/// 体重记录表
class WeightLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()(); // 'YYYY-MM-DD' 本地时区自然日
  RealColumn get weightKg => real()();
}
```

- [ ] **Step 5: 创建 pending_recognition 表定义**

创建 `lib/data/database/tables/pending_recognition_table.dart`：

```dart
import 'package:drift/drift.dart';
import 'food_item_table.dart';

/// 离线识别队列表
class PendingRecognitions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get imagePath => text()();
  TextColumn get mealType => text()();
  TextColumn get date => text()(); // 'YYYY-MM-DD' 本地时区自然日
  TextColumn get status => text()(); // pending/done/failed
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  IntColumn get resultFoodItemId => integer().nullable().references(FoodItems, #id)();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get promptVersion => text().nullable()();
  IntColumn get createdAt => integer()(); // UTC 毫秒
  IntColumn get processedAt => integer().nullable()(); // UTC 毫秒
}
```

- [ ] **Step 6: 创建 insight_summary 表定义**

创建 `lib/data/database/tables/insight_summary_table.dart`：

```dart
import 'package:drift/drift.dart';

/// AI 汇总建议表
class InsightSummaries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get periodType => text()(); // weekly/monthly
  TextColumn get periodStart => text()(); // 'YYYY-MM-DD'
  TextColumn get periodEnd => text()(); // 'YYYY-MM-DD'
  TextColumn get summaryText => text()();
  IntColumn get isEdited => integer().withDefault(const Constant(0))();
  IntColumn get generatedAt => integer()(); // UTC 毫秒
}
```

- [ ] **Step 7: 创建 recognition_feedback 表定义**

创建 `lib/data/database/tables/recognition_feedback_table.dart`：

```dart
import 'package:drift/drift.dart';
import 'meal_log_table.dart';

/// 识别反馈表（prompt 改进数据源）
class RecognitionFeedbacks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get mealLogId => integer().references(MealLogs, #id, onDelete: KeyAction.cascade)();
  IntColumn get isCorrect => integer()();
  TextColumn get correctedDishName => text().nullable()();
  RealColumn get correctedServingG => real().nullable()();
  TextColumn get promptVersion => text()();
  IntColumn get createdAt => integer()(); // UTC 毫秒
}
```

- [ ] **Step 8: 创建加密数据库连接**

创建 `lib/data/database/connection.dart`：

```dart
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

const _dbName = 'eatwise.db';
const _keyStorageKey = 'eatwise_db_key';

/// 获取或生成数据库加密密钥（32 字节密码学安全随机）
Future<String> _getOrCreatePassphrase() async {
  const storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );
  final existing = await storage.read(key: _keyStorageKey);
  if (existing != null) return existing;

  // 生成 32 字节密码学安全随机密钥（256 bits，匹配 AES-256）
  // Random.secure() 底层调用 OS 级 CSPRNG（iOS: SecRandomCopyBytes / Android: SecureRandom）
  final random = Random.secure();
  final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
  final passphrase = keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await storage.write(key: _keyStorageKey, value: passphrase);
  return passphrase;
}

/// debug 模式校验 sqlite3mc 已链接（防止 build hooks 失效静默退回明文）
bool _debugCheckHasCipher(Database database) {
  return database.select('PRAGMA cipher;').isNotEmpty;
}

/// 打开加密数据库连接
Future<QueryExecutor> openEncryptedConnection() async {
  final dir = await getApplicationDocumentsDirectory();
  final dbFile = File(p.join(dir.path, _dbName));
  final passphrase = await _getOrCreatePassphrase();

  return NativeDatabase.createInBackground(
    dbFile,
    setup: (rawDb) {
      assert(_debugCheckHasCipher(rawDb));
      rawDb.execute("PRAGMA key = '$passphrase';");
    },
  );
}
```

- [ ] **Step 9: 创建 Database 主定义**

创建 `lib/data/database/database.dart`：

```dart
import 'package:drift/drift.dart';

import 'connection.dart';
import 'tables/profile_table.dart';
import 'tables/food_item_table.dart';
import 'tables/meal_log_table.dart';
import 'tables/weight_log_table.dart';
import 'tables/pending_recognition_table.dart';
import 'tables/insight_summary_table.dart';
import 'tables/recognition_feedback_table.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Profiles,
  FoodItems,
  MealLogs,
  WeightLogs,
  PendingRecognitions,
  InsightSummaries,
  RecognitionFeedbacks,
])
class EatWiseDatabase extends _$EatWiseDatabase {
  /// 生产环境：传入 openEncryptedConnection() 的 executor
  EatWiseDatabase(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        beforeOpen: (details) async {
          // 启用 SQLite 外键约束（drift NativeDatabase 默认不启用）
          // recognition_feedback.meal_log_id 的 ON DELETE CASCADE 依赖此 PRAGMA
          await customStatement('PRAGMA foreign_keys = ON;');
          if (details.wasCreated) {
            // 首次创建时初始化 profile 单行
            await into(profiles).insert(ProfilesCompanion.insert(
              id: const Value(1),
              heightCm: 170,
              weightKg: 70,
              age: 30,
              gender: 'male',
              activityLevel: 1.375,
              goal: 'maintain',
              goalRateKgPerWeek: 0,
              formula: 'mifflin',
              dailyCalorieTarget: 2000,
              proteinGPerKg: 1.4,
              fatGPerKg: 0.9,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ));
          }
        },
      );
}

/// 生产环境 Database Provider（Riverpod）
final databaseProvider = FutureProvider<EatWiseDatabase>((ref) async {
  final executor = await openEncryptedConnection();
  final db = EatWiseDatabase(executor);
  ref.onDispose(db.close);
  return db;
});
```

- [ ] **Step 10: 运行 build_runner 生成代码**

```bash
dart run build_runner build --delete-conflicting-outputs
```

预期：生成 `lib/data/database/database.g.dart`，无报错。

- [ ] **Step 11: 生成 drift schema 迁移文件**

```bash
dart run drift_dev make-migrations
```

预期：在 `drift_schemas/` 生成 schema_v1.json，在 `lib/data/database/` 生成迁移文件。

- [ ] **Step 12: 写加密数据库读写测试**

创建 `test/data/database_test.dart`：

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/database/tables/food_item_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;

  setUp(() {
    db = EatWiseDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('profile 单行初始化', () async {
    final profile = await db.profiles.where((p) => p.id.equals(1)).getSingle();
    expect(profile.heightCm, 170);
    expect(profile.gender, 'male');
    expect(profile.tdeeAdjustmentKcal, 0);
  });

  test('food_item 插入与查询', () async {
    final id = await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '苹果',
          defaultServingG: 200,
          caloriesPer100g: 52,
          proteinPer100g: 0.3,
          fatPer100g: 0.2,
          carbsPer100g: 14,
          source: 'china_fct',
          sourceVersion: 'test_v1',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
    final item = await db.foodItems.where((f) => f.id.equals(id)).getSingle();
    expect(item.name, '苹果');
    expect(item.caloriesPer100g, 52);
    expect(item.ediblePercent, isNull);
  });

  test('meal_log 外键关联 food_item', () async {
    final foodId = await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '鸡蛋',
          defaultServingG: 60,
          caloriesPer100g: 144,
          proteinPer100g: 13,
          fatPer100g: 9,
          carbsPer100g: 1.1,
          source: 'manual',
          sourceVersion: 'manual',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
    final mealId = await db.into(db.mealLogs).insert(MealLogsCompanion.insert(
          date: '2026-07-01',
          mealType: 'breakfast',
          foodItemId: foodId,
          actualServingG: 60,
          actualCalories: 86.4,
          actualProteinG: 7.8,
          actualFatG: 5.4,
          actualCarbsG: 0.66,
          loggedAt: DateTime.now().millisecondsSinceEpoch,
        ));
    final meal = await db.mealLogs.where((m) => m.id.equals(mealId)).getSingle();
    expect(meal.foodItemId, foodId);
    expect(meal.actualCalories, 86.4);
  });

  test('recognition_feedback 级联删除：删除 meal_log 时 feedback 同步删除', () async {
    final foodId = await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '测试',
          defaultServingG: 100,
          caloriesPer100g: 100,
          proteinPer100g: 10,
          fatPer100g: 5,
          carbsPer100g: 20,
          source: 'manual',
          sourceVersion: 'test',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
    final mealId = await db.into(db.mealLogs).insert(MealLogsCompanion.insert(
          date: '2026-07-01',
          mealType: 'lunch',
          foodItemId: foodId,
          actualServingG: 100,
          actualCalories: 100,
          actualProteinG: 10,
          actualFatG: 5,
          actualCarbsG: 20,
          loggedAt: DateTime.now().millisecondsSinceEpoch,
        ));
    await db.into(db.recognitionFeedbacks).insert(
          RecognitionFeedbacksCompanion.insert(
            mealLogId: mealId,
            isCorrect: 0,
            correctedDishName: const Value('正确菜名'),
            promptVersion: 'v1.0',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );

    expect((await db.recognitionFeedbacks.select().get()).length, 1);

    await db.mealLogs.deleteWhere((m) => m.id.equals(mealId));

    expect((await db.recognitionFeedbacks.select().get()).length, 0);
  });
}
```

- [ ] **Step 13: 运行测试验证**

```bash
flutter test test/data/database_test.dart
```

预期：4 个测试全部 PASS。

- [ ] **Step 14: Commit**

```bash
git add lib/data/ test/data/database_test.dart drift_schemas/
git commit -m "feat: drift 加密数据库 + 7 张表 + make-migrations 迁移代码 + 读写测试"
```

---

## Task 3: 营养计算模块

**目标:** 实现 BMR/TDEE/目标热量/宏量分配纯函数，覆盖 cut/bulk/maintain × 男女 × 有无体脂率，全部单元测试通过。

**Files:**
- Create: `lib/features/profile/nutrition_calculator.dart`
- Test: `test/features/nutrition_calculator_test.dart`

- [ ] **Step 1: 写营养计算测试（TDD - 先写失败测试）**

创建 `test/features/nutrition_calculator_test.dart`：

```dart
import 'package:eatwise/features/profile/nutrition_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BMR Mifflin-St Jeor', () {
    test('男性', () {
      final bmr = NutritionCalculator.bmrMifflin(
        weightKg: 70,
        heightCm: 175,
        age: 30,
        gender: Gender.male,
      );
      // 10*70 + 6.25*175 - 5*30 + 5 = 700 + 1093.75 - 150 + 5 = 1648.75
      expect(bmr, closeTo(1648.75, 0.01));
    });

    test('女性', () {
      final bmr = NutritionCalculator.bmrMifflin(
        weightKg: 60,
        heightCm: 165,
        age: 25,
        gender: Gender.female,
      );
      // 10*60 + 6.25*165 - 5*25 - 161 = 600 + 1031.25 - 125 - 161 = 1345.25
      expect(bmr, closeTo(1345.25, 0.01));
    });
  });

  group('BMR Katch-McArdle', () {
    test('体脂率 20%', () {
      final bmr = NutritionCalculator.bmrKatch(
        weightKg: 70,
        bodyFatPct: 20,
      );
      // 370 + 21.6 * 70 * (1 - 0.2) = 370 + 21.6 * 56 = 370 + 1209.6 = 1579.6
      expect(bmr, closeTo(1579.6, 0.01));
    });
  });

  group('TDEE', () {
    test('久坐 1.2', () {
      final tdee = NutritionCalculator.tdee(bmr: 1648.75, activityLevel: 1.2);
      expect(tdee, closeTo(1978.5, 0.01));
    });

    test('中度 1.55', () {
      final tdee = NutritionCalculator.tdee(bmr: 1648.75, activityLevel: 1.55);
      expect(tdee, closeTo(2555.56, 0.01));
    });
  });

  group('目标热量', () {
    test('减脂 cut：TDEE - 500', () {
      final target = NutritionCalculator.dailyCalorieTarget(
        tdee: 2000,
        goal: Goal.cut,
        tdeeAdjustmentKcal: 0,
      );
      expect(target, 1500);
    });

    test('增肌 bulk：TDEE + 250', () {
      final target = NutritionCalculator.dailyCalorieTarget(
        tdee: 2000,
        goal: Goal.bulk,
        tdeeAdjustmentKcal: 0,
      );
      expect(target, 2250);
    });

    test('维持 maintain：TDEE', () {
      final target = NutritionCalculator.dailyCalorieTarget(
        tdee: 2000,
        goal: Goal.maintain,
        tdeeAdjustmentKcal: 0,
      );
      expect(target, 2000);
    });

    test('减脂女性硬下限 1200', () {
      final target = NutritionCalculator.dailyCalorieTarget(
        tdee: 1500,
        goal: Goal.cut,
        gender: Gender.female,
        tdeeAdjustmentKcal: 0,
      );
      expect(target, 1200); // 1500-500=1000，但硬下限 1200
    });

    test('减脂男性硬下限 1500', () {
      final target = NutritionCalculator.dailyCalorieTarget(
        tdee: 1700,
        goal: Goal.cut,
        gender: Gender.male,
        tdeeAdjustmentKcal: 0,
      );
      expect(target, 1500); // 1700-500=1200，但硬下限 1500
    });

    test('tdeeAdjustment 生效', () {
      final target = NutritionCalculator.dailyCalorieTarget(
        tdee: 2000,
        goal: Goal.maintain,
        tdeeAdjustmentKcal: -100,
      );
      expect(target, 1900);
    });
  });

  group('宏量分配', () {
    test('减脂默认', () {
      final macros = NutritionCalculator.macros(
        dailyCalorieTarget: 1500,
        weightKg: 70,
        goal: Goal.cut,
      );
      expect(macros.proteinG, closeTo(168, 0.1)); // 2.4 * 70
      expect(macros.fatG, closeTo(63, 0.1)); // 0.9 * 70
      // 碳水 = (1500 - 168*4 - 63*9) / 4 = (1500 - 672 - 567) / 4 = 261/4 = 65.25
      expect(macros.carbG, closeTo(65.25, 0.1));
    });

    test('增肌默认', () {
      final macros = NutritionCalculator.macros(
        dailyCalorieTarget: 2250,
        weightKg: 70,
        goal: Goal.bulk,
      );
      expect(macros.proteinG, closeTo(126, 0.1)); // 1.8 * 70
      expect(macros.fatG, closeTo(70, 0.1)); // 1.0 * 70
      expect(macros.carbG, closeTo(350, 0.1)); // 增肌碳水 5.0 g/kg * 70 = 350
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/features/nutrition_calculator_test.dart
```

预期：FAIL，`NutritionCalculator` 未定义。

- [ ] **Step 3: 实现营养计算模块**

创建 `lib/features/profile/nutrition_calculator.dart`：

```dart
/// 营养计算模块（纯函数，无 UI，无副作用）
/// 依据设计文档 5.1-5.4 节
/// 公式来源：Mifflin-St Jeor (Frankenfield 2005)、Katch-McArdle、ISSN 2017、Morton 2018
class NutritionCalculator {
  NutritionCalculator._();

  /// BMR - Mifflin-St Jeor 公式（AND 官方推荐）
  static double bmrMifflin({
    required double weightKg,
    required double heightCm,
    required int age,
    required Gender gender,
  }) {
    final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
    return gender == Gender.male ? base + 5 : base - 161;
  }

  /// BMR - Katch-McArdle 公式（需体脂率，对精瘦人群更准）
  static double bmrKatch({
    required double weightKg,
    required double bodyFatPct,
  }) {
    final leanMass = weightKg * (1 - bodyFatPct / 100);
    return 370 + 21.6 * leanMass;
  }

  /// TDEE = BMR × 活动系数
  static double tdee({
    required double bmr,
    required double activityLevel,
  }) {
    return bmr * activityLevel;
  }

  /// 每日目标热量（受硬下限约束）
  /// 减脂：TDEE - 500；增肌：TDEE + 250；维持：TDEE
  /// 硬下限：女性 ≥ 1200，男性 ≥ 1500
  static int dailyCalorieTarget({
    required double tdee,
    required Goal goal,
    required int tdeeAdjustmentKcal,
    Gender? gender,
  }) {
    int raw;
    switch (goal) {
      case Goal.cut:
        raw = (tdee - 500 + tdeeAdjustmentKcal).round();
        break;
      case Goal.bulk:
        raw = (tdee + 250 + tdeeAdjustmentKcal).round();
        break;
      case Goal.maintain:
        raw = (tdee + tdeeAdjustmentKcal).round();
        break;
    }
    // 硬下限
    if (gender == Gender.female && raw < 1200) raw = 1200;
    if (gender == Gender.male && raw < 1500) raw = 1500;
    return raw;
  }

  /// 宏量营养素分配
  static Macros macros({
    required int dailyCalorieTarget,
    required double weightKg,
    required Goal goal,
  }) {
    double proteinGPerKg;
    double fatGPerKg;
    double? carbGPerKg;

    switch (goal) {
      case Goal.cut:
        proteinGPerKg = 2.4; // ISSN 2017，减脂期 2.3-2.6 默认 2.4
        fatGPerKg = 0.9; // 0.8-1.0 默认 0.9
        // 碳水填剩余
        break;
      case Goal.bulk:
        proteinGPerKg = 1.8; // Morton 2018，1.6-2.2 默认 1.8
        fatGPerKg = 1.0; // 0.8-1.2 默认 1.0
        carbGPerKg = 5.0; // 4-7 g/kg 取中值
        break;
      case Goal.maintain:
        proteinGPerKg = 1.4; // 1.2-1.6 默认 1.4
        fatGPerKg = 0.9; // 0.8-1.0 默认 0.9
        // 碳水填剩余
        break;
    }

    final proteinG = proteinGPerKg * weightKg;
    final fatG = fatGPerKg * weightKg;
    final proteinCal = proteinG * 4;
    final fatCal = fatG * 9;

    double carbG;
    if (carbGPerKg != null) {
      // 增肌场景：碳水主动设 g/kg 目标
      carbG = carbGPerKg * weightKg;
    } else {
      // 减脂/维持：碳水 = 剩余热量 / 4
      carbG = (dailyCalorieTarget - proteinCal - fatCal) / 4;
      if (carbG < 0) carbG = 0; // 保护：热量不足时碳水不取负
    }

    return Macros(proteinG: proteinG, fatG: fatG, carbG: carbG);
  }
}

enum Gender { male, female }

enum Goal { cut, bulk, maintain }

class Macros {
  final double proteinG;
  final double fatG;
  final double carbG;

  const Macros({
    required this.proteinG,
    required this.fatG,
    required this.carbG,
  });
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/features/nutrition_calculator_test.dart
```

预期：全部 PASS（13 个测试）。

- [ ] **Step 5: Commit**

```bash
git add lib/features/profile/nutrition_calculator.dart test/features/nutrition_calculator_test.dart
git commit -m "feat: 营养计算模块 - Mifflin/Katch BMR + TDEE + 宏量分配 + 单元测试"
```

---

## Task 4: Sanotsu 食材库导入

**目标:** 解析 Sanotsu JSON、字段映射、缺失值清洗（"—"/"Tr"/空串）、别名补充，导入到 food_item 表。

**Files:**
- Create: `test/fixtures/sanotsu_sample.json`
- Create: `lib/data/seed/food_seed_importer.dart`
- Test: `test/data/food_seed_importer_test.dart`

- [ ] **Step 1: 创建 Sanotsu 样本数据（测试用）**

创建 `test/fixtures/sanotsu_sample.json`（模拟真实数据集结构，字段值为字符串）：

```json
[
  {
    "foodName": "番茄[西红柿]",
    "energyKCal": "18",
    "protein": "0.9",
    "fat": "0.2",
    "CHO": "3.9",
    "edible": "97"
  },
  {
    "foodName": "马铃薯(土豆,洋芋)",
    "energyKCal": "76",
    "protein": "2.0",
    "fat": "0.1",
    "CHO": "16.5",
    "edible": "94"
  },
  {
    "foodName": "花生油",
    "energyKCal": "889",
    "protein": "—",
    "fat": "99.9",
    "CHO": "Tr",
    "edible": "100"
  },
  {
    "foodName": "苹果",
    "energyKCal": "52",
    "protein": "0.3",
    "fat": "0.2",
    "CHO": "13.8",
    "edible": ""
  }
]
```

- [ ] **Step 2: 写导入器测试（TDD）**

创建 `test/data/food_seed_importer_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/seed/food_seed_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;

  setUp(() {
    db = EatWiseDatabase(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('解析 Sanotsu JSON：字段映射正确', () {
    final json = jsonDecode(File('test/fixtures/sanotsu_sample.json').readAsStringSync())
        as List<dynamic>;
    final items = FoodSeedImporter.parseJson(json.cast<Map<String, dynamic>>());

    expect(items.length, 4);

    // 番茄：去除 [西红柿] 后缀
    // 注意：parseJson 返回 List<FoodItemsCompanion>，字段是 Value<T>，需用 .value 访问
    expect(items[0].name.value, '番茄');
    expect(items[0].caloriesPer100g.value, 18);
    expect(items[0].ediblePercent.value, 97);

    // 马铃薯：去除 (土豆,洋芋) 后缀
    expect(items[1].name.value, '马铃薯');
    expect(items[1].carbsPer100g.value, 16.5);

    // 花生油："—" → 0（protein_per_100g 非空，用 _parseDouble），"Tr" → 0.05
    expect(items[2].name.value, '花生油');
    expect(items[2].proteinPer100g.value, 0); // "—" → 0（非空字段）
    expect(items[2].carbsPer100g.value, 0.05);

    // 苹果：edible 空串 → null
    expect(items[3].name.value, '苹果');
    expect(items[3].ediblePercent.value, isNull);
  });

  test('导入到数据库：去重 + source 标注', () async {
    final json = jsonDecode(File('test/fixtures/sanotsu_sample.json').readAsStringSync())
        as List<dynamic>;
    final importer = FoodSeedImporter(db);

    final count = await importer.importFromJsonList(json.cast<Map<String, dynamic>>());
    expect(count, 4);

    final items = await db.foodItems.select().get();
    expect(items.length, 4);
    expect(items.every((i) => i.source == 'china_fct'), true);
    expect(items.every((i) => i.sourceVersion == 'china_fct_v6_251206'), true);
  });

  test('别名补充：番茄补充 aliases=["西红柿","tomato"]', () async {
    final json = jsonDecode(File('test/fixtures/sanotsu_sample.json').readAsStringSync())
        as List<dynamic>;
    final importer = FoodSeedImporter(db);
    await importer.importFromJsonList(json.cast<Map<String, dynamic>>());
    await importer.supplementAliases();

    final tomato = await (db.foodItems.select()
          ..where((f) => f.name.equals('番茄')))
        .getSingle();
    expect(tomato.aliasesJson, isNotNull);
    final aliases = jsonDecode(tomato.aliasesJson!) as List;
    expect(aliases, containsAll(['西红柿', 'tomato']));
  });

  test('重复导入：同 name+source 去重，更新而非新增', () async {
    final json = jsonDecode(File('test/fixtures/sanotsu_sample.json').readAsStringSync())
        as List<dynamic>;
    final importer = FoodSeedImporter(db);

    await importer.importFromJsonList(json.cast<Map<String, dynamic>>());
    await importer.importFromJsonList(json.cast<Map<String, dynamic>>());

    final items = await db.foodItems.select().get();
    expect(items.length, 4); // 仍是 4 条，非 8 条
  });
}
```

- [ ] **Step 3: 运行测试确认失败**

```bash
flutter test test/data/food_seed_importer_test.dart
```

预期：FAIL，`FoodSeedImporter` 未定义。

- [ ] **Step 4: 实现食材库导入器**

创建 `lib/data/seed/food_seed_importer.dart`：

```dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

/// Sanotsu/china-food-composition-data 食材库导入器
/// 依据设计文档 6.4 节字段映射规则
class FoodSeedImporter {
  final EatWiseDatabase _db;

  static const _sourceVersion = 'china_fct_v6_251206';

  /// 常见别名映射（20-30 组，覆盖常见同物异名）
  static const _aliasMap = <String, List<String>>{
    '番茄': ['西红柿', 'tomato'],
    '马铃薯': ['土豆', '洋芋', 'potato'],
    '甘薯': ['红薯', '地瓜', 'sweet potato'],
    '猕猴桃': ['奇异果', 'kiwi'],
    '花生': ['花生米', 'peanut'],
    '鸡肉': ['鸡胸肉', '鸡'],
    '猪大排': ['排骨', '猪排'],
    '鸡蛋': ['鸡蛋清', '鸡蛋黄', '蛋'],
  };

  FoodSeedImporter(this._db);

  /// 解析 Sanotsu JSON 列表为 FoodItemsCompanion 列表（不入库）
  static List<FoodItemsCompanion> parseJson(List<Map<String, dynamic>> jsonList) {
    return jsonList.map(_parseItem).toList();
  }

  static FoodItemsCompanion _parseItem(Map<String, dynamic> raw) {
    final rawName = raw['foodName'] as String;
    final name = _cleanName(rawName);

    return FoodItemsCompanion.insert(
      name: name,
      defaultServingG: 100,
      caloriesPer100g: _parseDouble(raw['energyKCal']),
      proteinPer100g: _parseDouble(raw['protein']),
      fatPer100g: _parseDouble(raw['fat']),
      carbsPer100g: _parseTrValue(raw['CHO']),
      ediblePercent: _parseNullableDouble(raw['edible']),
      source: 'china_fct',
      sourceVersion: _sourceVersion,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 去除别名括号后缀：[干酪]、(代表值)、(土豆,洋芋)
  static String _cleanName(String name) {
    return name.replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), '').trim();
  }

  /// 字符串转 double；"—"/空串 → null
  static double? _parseNullableDouble(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty || str == '—' || str == '-') return null;
    if (str == 'Tr') return 0.05;
    return double.tryParse(str);
  }

  /// 必填 double；"—" → null（数据缺失，导入时允许 null 供后续人工补）
  static double _parseDouble(dynamic value) {
    return _parseNullableDouble(value) ?? 0;
  }

  /// "Tr"（微量）→ 0.05；"—" → null
  static double _parseTrValue(dynamic value) {
    return _parseNullableDouble(value) ?? 0;
  }

  /// 导入 JSON 列表到数据库（去重：name + source）
  Future<int> importFromJsonList(List<Map<String, dynamic>> jsonList) async {
    final companions = parseJson(jsonList);
    var count = 0;
    for (final companion in companions) {
      // 查重：name + source
      final existing = await (_db.foodItems.select()
            ..where((f) => f.name.equals(companion.name.value) & f.source.equals('china_fct')))
          .get();

      if (existing.isEmpty) {
        await _db.into(_db.foodItems).insert(companion);
        count++;
      } else {
        // 已存在，更新营养值
        await (_db.foodItems.update()..where((f) => f.id.equals(existing.first.id))).write(
          FoodItemsCompanion(
            caloriesPer100g: companion.caloriesPer100g,
            proteinPer100g: companion.proteinPer100g,
            fatPer100g: companion.fatPer100g,
            carbsPer100g: companion.carbsPer100g,
            ediblePercent: Value(companion.ediblePercent.value),
          ),
        );
      }
    }
    return count;
  }

  /// 补充别名（导入后人工补充的 20-30 组）
  Future<void> supplementAliases() async {
    for (final entry in _aliasMap.entries) {
      final items = await (_db.foodItems.select()..where((f) => f.name.equals(entry.key))).get();
      for (final item in items) {
        await (_db.foodItems.update()..where((f) => f.id.equals(item.id))).write(
          FoodItemsCompanion(aliasesJson: Value(jsonEncode(entry.value))),
        );
      }
    }
  }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
flutter test test/data/food_seed_importer_test.dart
```

预期：4 个测试全部 PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/data/seed/ test/fixtures/sanotsu_sample.json test/data/food_seed_importer_test.dart
git commit -m "feat: Sanotsu 食材库导入 - 字段映射 + 缺失值清洗 + 别名补充 + 去重"
```

---

## Task 5: VisionProvider + Qwen-VL + GLM-4V-Plus 容灾

**目标:** 定义 VisionProvider 抽象接口、Qwen-VL 实现（response_format=json_object）、GLM-4V-Plus 容灾、prompt 版本管理、JSON 解析容错测试。

**Files:**
- Create: `lib/ai/vision_provider.dart`
- Create: `lib/ai/prompts.dart`
- Create: `lib/ai/qwen_vl_provider.dart`
- Create: `lib/ai/glm_4v_provider.dart`
- Test: `test/ai/vision_response_parser_test.dart`

- [ ] **Step 1: 定义 VisionProvider 抽象接口 + 数据类**

创建 `lib/ai/vision_provider.dart`：

```dart
/// 视觉大模型识别结果
class VisionRecognitionResult {
  final String dishName;
  final double estimatedWeightGLow;
  final double estimatedWeightGMid;
  final double estimatedWeightGHigh;
  final List<FoodComponent> foodComponents;
  final String cookingMethod; // steam/boil/cold/toss/roast/stir-fry/pan-fry/deep-fry/braise
  final bool isSingleItem;
  final double confidence;
  final String promptVersion;

  const VisionRecognitionResult({
    required this.dishName,
    required this.estimatedWeightGLow,
    required this.estimatedWeightGMid,
    required this.estimatedWeightGHigh,
    required this.foodComponents,
    required this.cookingMethod,
    required this.isSingleItem,
    required this.confidence,
    required this.promptVersion,
  });

  factory VisionRecognitionResult.fromJson(Map<String, dynamic> json, String promptVersion) {
    return VisionRecognitionResult(
      dishName: json['dish_name'] as String,
      estimatedWeightGLow: (json['estimated_weight_g_low'] as num).toDouble(),
      estimatedWeightGMid: (json['estimated_weight_g_mid'] as num).toDouble(),
      estimatedWeightGHigh: (json['estimated_weight_g_high'] as num).toDouble(),
      foodComponents: ((json['food_components'] as List?) ?? [])
          .map((e) => FoodComponent.fromJson(e as Map<String, dynamic>))
          .toList(),
      cookingMethod: json['cooking_method'] as String,
      isSingleItem: json['is_single_item'] as bool,
      confidence: (json['confidence'] as num).toDouble(),
      promptVersion: promptVersion,
    );
  }
}

class FoodComponent {
  final String name;
  final double estimatedG;

  const FoodComponent({required this.name, required this.estimatedG});

  factory FoodComponent.fromJson(Map<String, dynamic> json) {
    return FoodComponent(
      name: json['name'] as String,
      estimatedG: (json['estimated_g'] as num).toDouble(),
    );
  }
}

/// 视觉大模型抽象接口
abstract class VisionProvider {
  String get name;
  String get promptVersion;

  /// 识别图片，返回结构化结果
  /// [imageBase64] base64 编码的 JPEG 图片
  Future<VisionRecognitionResult> recognize(String imageBase64);
}

/// 识别异常
class VisionRecognitionException implements Exception {
  final String reason;
  final bool retryable; // malformed=false(带错误信息重发), timeout=true, rate_limit=true

  VisionRecognitionException(this.reason, {this.retryable = false});

  @override
  String toString() => 'VisionRecognitionException: $reason';
}
```

- [ ] **Step 2: 创建 prompts.dart（含版本号）**

创建 `lib/ai/prompts.dart`：

```dart
// prompt v1.0 - 2026-07-01
// Sprint 1 初始版本，聚焦单品识别 + 复合菜拆组分

class Prompts {
  Prompts._();

  static const version = 'v1.0';

  /// Qwen-VL system prompt（response_format=json_object 模式）
  static const systemPrompt = '''
你是食物识别助手。分析图片中的食物，返回 JSON 格式结果。

JSON schema：
{
  "dish_name": "食物名称（中文）",
  "estimated_weight_g_low": 估算重量下限(克,整数),
  "estimated_weight_g_mid": 估算重量中值(克,整数),
  "estimated_weight_g_high": 估算重量上限(克,整数),
  "is_single_item": true表示单品(苹果/鸡蛋/牛奶等),false表示复合菜(宫保鸡丁/番茄炒蛋等),
  "food_components": [{"name":"组分名","estimated_g":估算克数}],
  "cooking_method": "烹饪方式: raw/steam/boil/cold/toss/roast/stir-fry/pan-fry/deep-fry/braise 之一",
  "confidence": 0.0-1.0 置信度
}

规则：
1. 单品(is_single_item=true)时 food_components 为空数组 []
2. 复合菜(is_single_item=false)时 food_components 必须列出 2-8 个主要食材组分
3. 只返回 JSON，不要任何解释文字

示例1（苹果）：
{"dish_name":"苹果","estimated_weight_g_low":150,"estimated_weight_g_mid":180,"estimated_weight_g_high":220,"is_single_item":true,"food_components":[],"cooking_method":"raw","confidence":0.9}

示例2（番茄炒蛋）：
{"dish_name":"番茄炒蛋","estimated_weight_g_low":200,"estimated_weight_g_mid":250,"estimated_weight_g_high":300,"is_single_item":false,"food_components":[{"name":"鸡蛋","estimated_g":120},{"name":"番茄","estimated_g":150}],"cooking_method":"stir-fry","confidence":0.85}
''';
}
```

- [ ] **Step 3: 写 JSON 解析容错测试（TDD）**

创建 `test/ai/vision_response_parser_test.dart`：

```dart
import 'package:eatwise/ai/vision_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VisionRecognitionResult.fromJson', () {
    test('正常单品响应解析', () {
      final json = {
        'dish_name': '苹果',
        'estimated_weight_g_low': 150,
        'estimated_weight_g_mid': 180,
        'estimated_weight_g_high': 220,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'raw',
        'confidence': 0.9,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.0');

      expect(result.dishName, '苹果');
      expect(result.estimatedWeightGMid, 180);
      expect(result.isSingleItem, true);
      expect(result.foodComponents, isEmpty);
      expect(result.confidence, 0.9);
      expect(result.promptVersion, 'v1.0');
    });

    test('复合菜响应解析（含组分）', () {
      final json = {
        'dish_name': '番茄炒蛋',
        'estimated_weight_g_low': 200,
        'estimated_weight_g_mid': 250,
        'estimated_weight_g_high': 300,
        'is_single_item': false,
        'food_components': [
          {'name': '鸡蛋', 'estimated_g': 120},
          {'name': '番茄', 'estimated_g': 150}
        ],
        'cooking_method': 'stir-fry',
        'confidence': 0.85,
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.0');

      expect(result.isSingleItem, false);
      expect(result.foodComponents.length, 2);
      expect(result.foodComponents[0].name, '鸡蛋');
      expect(result.foodComponents[0].estimatedG, 120);
    });

    test('food_components 字段缺失时默认空数组', () {
      final json = {
        'dish_name': '苹果',
        'estimated_weight_g_low': 150,
        'estimated_weight_g_mid': 180,
        'estimated_weight_g_high': 220,
        'is_single_item': true,
        'cooking_method': 'raw',
        'confidence': 0.9,
        // food_components 缺失
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.0');
      expect(result.foodComponents, isEmpty);
    });

    test('字段类型为 int 时正确转 double', () {
      final json = {
        'dish_name': '米饭',
        'estimated_weight_g_low': 100,
        'estimated_weight_g_mid': 150,
        'estimated_weight_g_high': 200,
        'is_single_item': true,
        'food_components': [],
        'cooking_method': 'boil',
        'confidence': 1, // int 而非 double
      };
      final result = VisionRecognitionResult.fromJson(json, 'v1.0');
      expect(result.confidence, 1.0);
      expect(result.estimatedWeightGMid, 150.0);
    });
  });
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/ai/vision_response_parser_test.dart
```

预期：4 个测试全部 PASS（fromJson 已在 Step 1 实现）。

- [ ] **Step 5: 实现 Qwen-VL Provider（含公共静态方法供 GLM-4V-Plus 容灾复用）**

创建 `lib/ai/qwen_vl_provider.dart`：

```dart
import 'dart:convert';

import 'package:openai_dart/openai_dart.dart';

import 'prompts.dart';
import 'vision_provider.dart';

/// Qwen-VL 视觉模型 Provider（阿里云百炼，OpenAI-compatible）
/// 使用 response_format=json_object 强制合法 JSON（不用 function calling）
class QwenVlProvider implements VisionProvider {
  final OpenAIClient _client;
  final String _modelName;

  QwenVlProvider({
    required String apiKey,
    required String baseUrl,
    String modelName = 'qwen3-vl-flash',
  })  : _modelName = modelName,
        _client = OpenAIClient(
          config: OpenAIConfig(
            apiKey: apiKey,
            baseUrl: baseUrl,
          ),
        );

  @override
  String get name => 'Qwen-VL';

  @override
  String get promptVersion => Prompts.version;

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) =>
      recognizeWithClient(_client, _modelName, imageBase64, promptVersion);

  /// 公共识别逻辑（供 GLM-4V-Plus 容灾 Provider 复用）
  /// 两个 Provider 仅 client/baseUrl/modelName 不同，识别流程完全一致
  static Future<VisionRecognitionResult> recognizeWithClient(
    OpenAIClient client,
    String modelName,
    String imageBase64,
    String promptVersion,
  ) async {
    try {
      final response = await client.chat.createChatCompletion(
        request: CreateChatCompletionRequest(
          model: ChatCompletionModel.modelId(modelName),
          responseFormat: const ResponseFormat.jsonObject(),
          messages: [
            ChatCompletionMessage.system(content: Prompts.systemPrompt),
            ChatCompletionMessage.user(
              content: [
                ChatCompletionMessageContentPart.textImagePart(
                  ChatCompletionMessageContentPartType.image,
                  imageUrl: ChatCompletionMessageImageData(
                    url: 'data:image/jpeg;base64,$imageBase64',
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      final content = response.choices.first.message.content;
      if (content == null || content.isEmpty) {
        throw VisionRecognitionException('空响应', retryable: false);
      }
      final jsonStr = content.first.text;
      if (jsonStr == null) {
        throw VisionRecognitionException('响应无文本内容', retryable: false);
      }

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return VisionRecognitionResult.fromJson(json, promptVersion);
    } on FormatException catch (e) {
      throw VisionRecognitionException('JSON 解析失败: ${e.message}', retryable: false);
    } on OpenAIClientException catch (e) {
      if (e.statusCode == 429) {
        throw VisionRecognitionException('限流 429', retryable: true);
      }
      if (e.statusCode == 401 || e.statusCode == 403) {
        throw VisionRecognitionException('认证失败 ${e.statusCode}', retryable: false);
      }
      throw VisionRecognitionException('API 错误: ${e.message}', retryable: true);
    } catch (e) {
      if (e is VisionRecognitionException) rethrow;
      throw VisionRecognitionException('未知错误: $e', retryable: true);
    }
  }
}
```

- [ ] **Step 6: 实现 GLM-4V-Plus 容灾 Provider（复用 QwenVlProvider.recognizeWithClient）**

创建 `lib/ai/glm_4v_provider.dart`：

```dart
import 'package:openai_dart/openai_dart.dart';

import 'prompts.dart';
import 'qwen_vl_provider.dart';
import 'vision_provider.dart';

/// GLM-4V-Plus 视觉模型 Provider（智谱 AI，OpenAI-compatible）
/// Qwen-VL 失败时容灾降级，识别逻辑与 Qwen-VL 完全一致，仅 client/modelName 不同
class Glm4vProvider implements VisionProvider {
  final OpenAIClient _client;
  final String _modelName;

  Glm4vProvider({
    required String apiKey,
    required String baseUrl,
    String modelName = 'glm-4v-plus',
  })  : _modelName = modelName,
        _client = OpenAIClient(
          config: OpenAIConfig(apiKey: apiKey, baseUrl: baseUrl),
        );

  @override
  String get name => 'GLM-4V-Plus';

  @override
  String get promptVersion => Prompts.version;

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) =>
      QwenVlProvider.recognizeWithClient(_client, _modelName, imageBase64, promptVersion);
}
```

- [ ] **Step 7: 运行全部 AI 测试**

```bash
flutter test test/ai/
```

预期：4 个测试 PASS。

- [ ] **Step 8: flutter analyze 验证编译**

```bash
flutter analyze lib/ai/
```

预期：0 errors。

- [ ] **Step 9: Commit**

```bash
git add lib/ai/ test/ai/
git commit -m "feat: VisionProvider 抽象 + Qwen-VL + GLM-4V-Plus 容灾 + prompt 版本管理 + JSON 解析测试"
```

---

## Task 6: 营养查库层

**目标:** 实现单品查库 + 复合菜组分累加 + name/aliases 匹配 + 烹饪用油系数表，单元测试覆盖。

**Files:**
- Create: `lib/ai/nutrition_lookup.dart`
- Create: `lib/data/repositories/food_item_repository.dart`
- Test: `test/ai/nutrition_lookup_test.dart`

- [ ] **Step 1: 实现 FoodItemRepository（含 aliases 查询）**

创建 `lib/data/repositories/food_item_repository.dart`：

```dart
import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

class FoodItemRepository {
  final EatWiseDatabase _db;

  FoodItemRepository(this._db);

  /// 按 name 或 aliases 精确匹配（解决"西红柿/番茄"同物异名）
  Future<FoodItem?> findByNameOrAlias(String name) async {
    // 先精确匹配 name
    final byName = await (_db.foodItems.select()
          ..where((f) => f.name.equals(name))
          ..limit(1))
        .getSingleOrNull();
    if (byName != null) return byName;

    // 再遍历查 aliases_json（SQLite 无原生 JSON 查询，应用层过滤）
    final all = await _db.foodItems.select().get();
    for (final item in all) {
      if (item.aliasesJson == null) continue;
      // 简单包含匹配（MVP 够用，数据量小）
      if (item.aliasesJson!.contains('"$name"')) {
        return item;
      }
    }
    return null;
  }

  /// 插入或更新（去重键 name + source）
  Future<int> upsertAiRecognized({
    required String name,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double fatPer100g,
    required double carbsPer100g,
    double? confidence,
    String? componentsJson,
  }) async {
    final existing = await (_db.foodItems.select()
          ..where((f) => f.name.equals(name) & f.source.equals('ai_recognized')))
        .getSingleOrNull();

    if (existing != null) {
      await (_db.foodItems.update()..where((f) => f.id.equals(existing.id))).write(
        FoodItemsCompanion(
          caloriesPer100g: Value(caloriesPer100g),
          proteinPer100g: Value(proteinPer100g),
          fatPer100g: Value(fatPer100g),
          carbsPer100g: Value(carbsPer100g),
          confidence: Value(confidence),
        ),
      );
      return existing.id;
    }

    return _db.into(_db.foodItems).insert(FoodItemsCompanion.insert(
          name: name,
          defaultServingG: 100,
          caloriesPer100g: caloriesPer100g,
          proteinPer100g: proteinPer100g,
          fatPer100g: fatPer100g,
          carbsPer100g: carbsPer100g,
          source: 'ai_recognized',
          sourceVersion: 'ai',
          confidence: Value(confidence),
          componentsJson: Value(componentsJson),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
  }
}
```

- [ ] **Step 2: 实现营养查库层 + 用油系数表**

创建 `lib/ai/nutrition_lookup.dart`：

```dart
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/database/database.dart';
import 'vision_provider.dart';

/// 烹饪方式用油系数表（设计文档 3.1 节）
/// 默认用油量 g/份
const cookingOilCoefficients = <String, double>{
  'steam': 0, // 蒸
  'boil': 0, // 煮（通常不加油）
  'cold': 8, // 凉拌
  'toss': 8, // 拌（同凉拌）
  'roast': 8, // 烤
  'stir-fry': 12, // 炒
  'pan-fry': 15, // 煎
  'deep-fry': 25, // 炸
  'braise': 10, // 红烧
  'raw': 0, // 生食
};

/// 油的营养素（每 100g，花生油近似值）
const oilCaloriesPer100g = 889.0;
const oilFatPer100g = 99.9;

class NutritionLookup {
  final FoodItemRepository _repo;

  NutritionLookup(this._repo);

  /// 单品查库回填
  /// 返回 null 表示未命中（调用方转手动录入）
  Future<NutritionResult?> lookupSingleItem({
    required String dishName,
    required double servingG,
  }) async {
    final food = await _repo.findByNameOrAlias(dishName);
    if (food == null) return null;

    return NutritionResult(
      foodItemId: food.id,
      calories: food.caloriesPer100g * servingG / 100,
      proteinG: food.proteinPer100g * servingG / 100,
      fatG: food.fatPer100g * servingG / 100,
      carbsG: food.carbsPer100g * servingG / 100,
      oilG: 0,
    );
  }

  /// 复合菜组分累加 + 烹饪用油
  Future<CompositeNutritionResult> lookupCompositeDish({
    required List<FoodComponent> components,
    required String cookingMethod,
  }) async {
    final hits = <ComponentHit>[];
    final misses = <String>[];
    double totalCalories = 0;
    double totalProtein = 0;
    double totalFat = 0;
    double totalCarbs = 0;

    for (final comp in components) {
      final food = await _repo.findByNameOrAlias(comp.name);
      if (food == null) {
        misses.add(comp.name);
        continue;
      }
      final g = comp.estimatedG;
      totalCalories += food.caloriesPer100g * g / 100;
      totalProtein += food.proteinPer100g * g / 100;
      totalFat += food.fatPer100g * g / 100;
      totalCarbs += food.carbsPer100g * g / 100;
      hits.add(ComponentHit(name: comp.name, foodItemId: food.id, estimatedG: g));
    }

    // 加烹饪用油
    final oilG = cookingOilCoefficients[cookingMethod] ?? 0;
    if (oilG > 0) {
      totalCalories += oilCaloriesPer100g * oilG / 100;
      totalFat += oilFatPer100g * oilG / 100;
    }

    return CompositeNutritionResult(
      calories: totalCalories,
      proteinG: totalProtein,
      fatG: totalFat,
      carbsG: totalCarbs,
      oilG: oilG,
      componentHits: hits,
      componentMisses: misses,
    );
  }
}

class NutritionResult {
  final int foodItemId;
  final double calories;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final double oilG;

  const NutritionResult({
    required this.foodItemId,
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.oilG,
  });
}

class CompositeNutritionResult {
  final double calories;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final double oilG;
  final List<ComponentHit> componentHits;
  final List<String> componentMisses;

  const CompositeNutritionResult({
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.oilG,
    required this.componentHits,
    required this.componentMisses,
  });
}

class ComponentHit {
  final String name;
  final int foodItemId;
  final double estimatedG;

  const ComponentHit({
    required this.name,
    required this.foodItemId,
    required this.estimatedG,
  });
}
```

- [ ] **Step 3: 写查库层测试**

创建 `test/ai/nutrition_lookup_test.dart`：

```dart
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/database/tables/food_item_table.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late NutritionLookup lookup;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    // 预置测试数据
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '番茄',
          defaultServingG: 100,
          caloriesPer100g: 18,
          proteinPer100g: 0.9,
          fatPer100g: 0.2,
          carbsPer100g: 3.9,
          aliasesJson: '["西红柿","tomato"]',
          source: 'china_fct',
          sourceVersion: 'test',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '鸡蛋',
          defaultServingG: 60,
          caloriesPer100g: 144,
          proteinPer100g: 13,
          fatPer100g: 9,
          carbsPer100g: 1.1,
          source: 'china_fct',
          sourceVersion: 'test',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
    lookup = NutritionLookup(FoodItemRepository(db));
  });

  tearDown(() async => db.close());

  test('单品查库：按 name 命中', () async {
    final result = await lookup.lookupSingleItem(dishName: '番茄', servingG: 200);
    expect(result, isNotNull);
    expect(result!.calories, closeTo(36, 0.01)); // 18 * 200 / 100
  });

  test('单品查库：按 aliases 命中（西红柿→番茄）', () async {
    final result = await lookup.lookupSingleItem(dishName: '西红柿', servingG: 100);
    expect(result, isNotNull);
    expect(result!.calories, 18);
  });

  test('单品查库：未命中返回 null', () async {
    final result = await lookup.lookupSingleItem(dishName: '不存在的食物', servingG: 100);
    expect(result, isNull);
  });

  test('复合菜：组分累加 + 炒菜用油', () async {
    final result = await lookup.lookupCompositeDish(
      components: [
        FoodComponent(name: '鸡蛋', estimatedG: 120),
        FoodComponent(name: '番茄', estimatedG: 150),
      ],
      cookingMethod: 'stir-fry',
    );

    expect(result.componentMisses, isEmpty);
    expect(result.componentHits.length, 2);
    // 鸡蛋 144*1.2=172.8 + 番茄 18*1.5=27 = 199.8 + 油 889*0.12=106.68 = 306.48
    expect(result.calories, closeTo(306.48, 0.5));
    expect(result.oilG, 12); // 炒 12g
  });

  test('复合菜：组分部分未命中', () async {
    final result = await lookup.lookupCompositeDish(
      components: [
        FoodComponent(name: '鸡蛋', estimatedG: 100),
        FoodComponent(name: '不存在的食材', estimatedG: 50),
      ],
      cookingMethod: 'boil',
    );

    expect(result.componentMisses, ['不存在的食材']);
    expect(result.componentHits.length, 1);
    expect(result.oilG, 0); // 煮 0g 油
  });
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/ai/nutrition_lookup_test.dart
```

预期：5 个测试全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/ai/nutrition_lookup.dart lib/data/repositories/food_item_repository.dart test/ai/nutrition_lookup_test.dart
git commit -m "feat: 营养查库层 - 单品/复合菜路径 + name/aliases 匹配 + 烹饪用油系数 + 测试"
```

---

## Task 7: 拍照流程 + 校准页 UI

**目标:** 实现拍照→预处理→调 API→查库→校准页→写 meal_log 端到端闭环。校准页按置信度分级（≥0.85 单品允许一键记录）。

**Files:**
- Create: `lib/features/recognize/recognize_controller.dart`
- Create: `lib/features/recognize/recognize_page.dart`
- Create: `lib/features/recognize/calibration_page.dart`
- Create: `lib/features/dashboard/dashboard_page.dart`
- Modify: `lib/app.dart`（路由）
- Modify: `lib/data/repositories/meal_log_repository.dart`

- [ ] **Step 1: 实现 MealLogRepository**

创建 `lib/data/repositories/meal_log_repository.dart`：

```dart
import 'package:eatwise/data/database/database.dart';
import 'package:drift/drift.dart';

class MealLogRepository {
  final EatWiseDatabase _db;

  MealLogRepository(this._db);

  Future<int> insertMealLog({
    required String date,
    required String mealType,
    required int foodItemId,
    required double actualServingG,
    required double actualCalories,
    required double actualProteinG,
    required double actualFatG,
    required double actualCarbsG,
    String? originalImagePath,
    double? recognitionConfidence,
    String? componentsSnapshotJson,
  }) async {
    return _db.into(_db.mealLogs).insert(MealLogsCompanion.insert(
          date: date,
          mealType: mealType,
          foodItemId: foodItemId,
          actualServingG: actualServingG,
          actualCalories: actualCalories,
          actualProteinG: actualProteinG,
          actualFatG: actualFatG,
          actualCarbsG: actualCarbsG,
          originalImagePath: Value(originalImagePath),
          recognitionConfidence: Value(recognitionConfidence),
          componentsSnapshotJson: Value(componentsSnapshotJson),
          loggedAt: DateTime.now().millisecondsSinceEpoch,
        ));
  }

  /// 查询某日全部记录
  Future<List<MealLog>> getMealsByDate(String date) {
    return (_db.mealLogs.select()..where((m) => m.date.equals(date))).get();
  }

  /// 查询某日总热量
  Future<double> getTotalCaloriesByDate(String date) async {
    final meals = await getMealsByDate(date);
    return meals.fold(0.0, (sum, m) => sum + m.actualCalories);
  }
}
```

- [ ] **Step 2: 实现 recognize_controller（拍照→预处理→调 API→查库 状态机）**

创建 `lib/features/recognize/recognize_controller.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/vision_provider.dart';
import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';

/// 拍照识别状态
enum RecognizeState { idle, pickingImage, preprocessing, recognizing, lookupNutrition, done, error }

class RecognizeState_ {
  final RecognizeState state;
  final String? errorMessage;
  final VisionRecognitionResult? recognitionResult;
  final NutritionResult? singleNutrition;
  final CompositeNutritionResult? compositeNutrition;
  final String? imagePath;

  RecognizeState_({
    this.state = RecognizeState.idle,
    this.errorMessage,
    this.recognitionResult,
    this.singleNutrition,
    this.compositeNutrition,
    this.imagePath,
  });

  RecognizeState_ copyWith({
    RecognizeState? state,
    String? errorMessage,
    VisionRecognitionResult? recognitionResult,
    NutritionResult? singleNutrition,
    CompositeNutritionResult? compositeNutrition,
    String? imagePath,
  }) {
    return RecognizeState_(
      state: state ?? this.state,
      errorMessage: errorMessage,
      recognitionResult: recognitionResult ?? this.recognitionResult,
      singleNutrition: singleNutrition ?? this.singleNutrition,
      compositeNutrition: compositeNutrition ?? this.compositeNutrition,
      imagePath: imagePath ?? this.imagePath,
    );
  }
}

class RecognizeController extends StateNotifier<RecognizeState_> {
  final VisionProvider _primaryProvider;
  final VisionProvider? _fallbackProvider;
  final NutritionLookup _nutritionLookup;
  final FoodItemRepository _foodItemRepo;

  RecognizeController(
    this._primaryProvider,
    this._fallbackProvider,
    this._nutritionLookup,
    this._foodItemRepo,
  ) : super(RecognizeState_());

  /// 拍照入口
  Future<void> pickAndRecognize(ImageSource source) async {
    state = state.copyWith(state: RecognizeState.pickingImage);
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(source: source, maxWidth: 1024, maxHeight: 1024);
      if (xFile == null) {
        state = state.copyWith(state: RecognizeState.idle);
        return;
      }

      // 预处理：压缩 + 默认剥离 EXIF + 方向校正
      state = state.copyWith(state: RecognizeState.preprocessing);
      final compressedBytes = await FlutterImageCompress.compressWithFile(
        xFile.path,
        minWidth: 1024,
        minHeight: 1024,
        quality: 85,
        // keepExif 默认 false，EXIF 默认剥离
        // autoCorrectionAngle 默认 true，方向校正
      );
      if (compressedBytes == null) {
        state = state.copyWith(state: RecognizeState.error, errorMessage: '图片压缩失败');
        return;
      }

      final imageBase64 = base64Encode(compressedBytes);

      // 调 Vision API（主→备降级）
      state = state.copyWith(state: RecognizeState.recognizing);
      VisionRecognitionResult result;
      try {
        result = await _primaryProvider.recognize(imageBase64);
      } catch (e) {
        if (_fallbackProvider == null) rethrow;
        // 主失败，转备
        result = await _fallbackProvider.recognize(imageBase64);
      }

      // 查库回填营养素
      state = state.copyWith(
        state: RecognizeState.lookupNutrition,
        recognitionResult: result,
        imagePath: xFile.path,
      );

      if (result.isSingleItem) {
        final nutrition = await _nutritionLookup.lookupSingleItem(
          dishName: result.dishName,
          servingG: result.estimatedWeightGMid,
        );
        state = state.copyWith(state: RecognizeState.done, singleNutrition: nutrition);
      } else {
        final nutrition = await _nutritionLookup.lookupCompositeDish(
          components: result.foodComponents,
          cookingMethod: result.cookingMethod,
        );
        state = state.copyWith(state: RecognizeState.done, compositeNutrition: nutrition);
      }
    } catch (e) {
      state = state.copyWith(state: RecognizeState.error, errorMessage: e.toString());
    }
  }
}
```

- [ ] **Step 3: 实现校准页（置信度分级）**

创建 `lib/features/recognize/calibration_page.dart`：

```dart
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/vision_provider.dart';
import '../../data/repositories/food_item_repository.dart';

/// 校准页：按置信度分级
/// - 置信度 ≥ 0.85 且单品：允许"一键记录"跳过校准
/// - 置信度 < 0.6：强制校准，标注"待确认"
/// - 中间区 0.6-0.85：默认进校准页，提供"信任 AI"快捷按钮
class CalibrationPage extends StatefulWidget {
  final VisionRecognitionResult recognitionResult;
  final NutritionResult? singleNutrition;
  final CompositeNutritionResult? compositeNutrition;
  final FoodItemRepository foodItemRepo;
  final void Function(double servingG, double calories, double protein, double fat, double carbs, {String? componentsSnapshot}) onConfirm;

  const CalibrationPage({
    super.key,
    required this.recognitionResult,
    this.singleNutrition,
    this.compositeNutrition,
    required this.foodItemRepo,
    required this.onConfirm,
  });

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  late double _servingG;
  late bool _canSkipCalibration;

  @override
  void initState() {
    super.initState();
    _servingG = widget.recognitionResult.estimatedWeightGMid;
    _canSkipCalibration =
        widget.recognitionResult.confidence >= 0.85 && widget.recognitionResult.isSingleItem;
  }

  @override
  Widget build(BuildContext context) {
    final isLowConfidence = widget.recognitionResult.confidence < 0.6;
    final isMidConfidence =
        widget.recognitionResult.confidence >= 0.6 && widget.recognitionResult.confidence < 0.85;

    return Scaffold(
      appBar: AppBar(
        title: const Text('校准份量'),
        actions: [
          if (_canSkipCalibration)
            TextButton(
              onPressed: _confirmOneClick,
              child: const Text('一键记录'),
            ),
          if (isMidConfidence)
            TextButton(
              onPressed: _trustAi,
              child: const Text('信任 AI'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('识别结果：${widget.recognitionResult.dishName}',
                style: Theme.of(context).textTheme.headlineSmall),
            Text('置信度：${(widget.recognitionResult.confidence * 100).toStringAsFixed(0)}%'),
            if (isLowConfidence)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('⚠️ 待确认（置信度低，请仔细校准）',
                    style: TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 24),
            Text('份量：${_servingG.toStringAsFixed(0)} g'),
            Slider(
              value: _servingG,
              min: 0,
              max: 1000,
              divisions: 100,
              label: '${_servingG.toStringAsFixed(0)} g',
              onChanged: (v) => setState(() => _servingG = v),
            ),
            const SizedBox(height: 24),
            // 实时营养素预览（基于当前滑块值重算）
            _buildNutritionPreview(),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _confirmManual,
                child: const Text('确认记录'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionPreview() {
    if (widget.singleNutrition == null) return const SizedBox.shrink();
    final ratio = _servingG / widget.recognitionResult.estimatedWeightGMid;
    final cal = widget.singleNutrition!.calories * ratio;
    final protein = widget.singleNutrition!.proteinG * ratio;
    final fat = widget.singleNutrition!.fatG * ratio;
    final carbs = widget.singleNutrition!.carbsG * ratio;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('热量：${cal.toStringAsFixed(0)} kcal'),
            Text('蛋白质：${protein.toStringAsFixed(1)} g'),
            Text('脂肪：${fat.toStringAsFixed(1)} g'),
            Text('碳水：${carbs.toStringAsFixed(1)} g'),
          ],
        ),
      ),
    );
  }

  void _confirmOneClick() {
    // 一键记录：用 AI 中值，不校准
    _confirmWithServing(widget.recognitionResult.estimatedWeightGMid);
  }

  void _trustAi() {
    _confirmWithServing(widget.recognitionResult.estimatedWeightGMid);
  }

  void _confirmManual() {
    _confirmWithServing(_servingG);
  }

  void _confirmWithServing(double servingG) {
    if (widget.singleNutrition != null) {
      final ratio = servingG / widget.recognitionResult.estimatedWeightGMid;
      widget.onConfirm(
        servingG,
        widget.singleNutrition!.calories * ratio,
        widget.singleNutrition!.proteinG * ratio,
        widget.singleNutrition!.fatG * ratio,
        widget.singleNutrition!.carbsG * ratio,
      );
    } else if (widget.compositeNutrition != null) {
      widget.onConfirm(
        servingG,
        widget.compositeNutrition!.calories,
        widget.compositeNutrition!.proteinG,
        widget.compositeNutrition!.fatG,
        widget.compositeNutrition!.carbsG,
        componentsSnapshot: _buildSnapshotJson(),
      );
    }
    Navigator.of(context).pop();
  }

  String _buildSnapshotJson() {
    // 复合菜组分快照（设计文档 4.2.3 components_snapshot_json）
    final components = widget.recognitionResult.foodComponents
        .map((c) => {'name': c.name, 'actual_g': c.estimatedG})
        .toList();
    return jsonEncode({
      'components': components,
      'oil_g': widget.compositeNutrition?.oilG ?? 0,
    });
  }
}
```

- [ ] **Step 4: 创建 providers.dart（Riverpod 依赖注入）**

创建 `lib/features/recognize/providers.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/glm_4v_provider.dart';
import '../../ai/nutrition_lookup.dart';
import '../../ai/qwen_vl_provider.dart';
import '../../ai/vision_provider.dart';
import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import 'recognize_controller.dart';

/// API key（Sprint 3 改从 secure_storage 读，Sprint 1 用 --dart-define 注入）
final qwenApiKeyProvider = Provider<String>(
  (ref) => const String.fromEnvironment('QWEN_API_KEY', defaultValue: ''),
);
final qwenBaseUrlProvider = Provider<String>(
  (ref) => const String.fromEnvironment('QWEN_BASE_URL', defaultValue: ''),
);
final glmApiKeyProvider = Provider<String>(
  (ref) => const String.fromEnvironment('GLM_API_KEY', defaultValue: ''),
);
final glmBaseUrlProvider = Provider<String>(
  (ref) => const String.fromEnvironment('GLM_BASE_URL', defaultValue: ''),
);

final qwenVlProviderProvider = Provider<QwenVlProvider>((ref) {
  return QwenVlProvider(
    apiKey: ref.watch(qwenApiKeyProvider),
    baseUrl: ref.watch(qwenBaseUrlProvider),
  );
});

final glm4vProviderProvider = Provider<Glm4vProvider?>((ref) {
  final key = ref.watch(glmApiKeyProvider);
  final url = ref.watch(glmBaseUrlProvider);
  if (key.isEmpty || url.isEmpty) return null;
  return Glm4vProvider(apiKey: key, baseUrl: url);
});

final foodItemRepoProvider = FutureProvider<FoodItemRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return FoodItemRepository(db);
});

final mealLogRepoProvider = FutureProvider<MealLogRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return MealLogRepository(db);
});

final nutritionLookupProvider = FutureProvider<NutritionLookup>((ref) async {
  final repo = await ref.watch(foodItemRepoProvider.future);
  return NutritionLookup(repo);
});

// RecognizeController 不用 Provider 管理（依赖 FutureProvider 异步初始化，
// 与 StateNotifierProvider 同步初始化存在时序冲突）
// 在 RecognizePage 中用 ref.read 按需创建实例，见 Step 5
```

- [ ] **Step 5: 实现 recognize_page（用 ref.read 按需初始化 controller）**

创建 `lib/features/recognize/recognize_page.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/vision_provider.dart';
import 'calibration_page.dart';
import 'providers.dart';
import 'recognize_controller.dart';

class RecognizePage extends ConsumerStatefulWidget {
  const RecognizePage({super.key});

  @override
  ConsumerState<RecognizePage> createState() => _RecognizePageState();
}

class _RecognizePageState extends ConsumerState<RecognizePage> {
  RecognizeController? _controller;

  Future<RecognizeController> _ensureController() async {
    if (_controller != null) return _controller!;
    final qwen = ref.read(qwenVlProviderProvider);
    final glm = ref.read(glm4vProviderProvider);
    final lookup = await ref.read(nutritionLookupProvider.future);
    final foodRepo = await ref.read(foodItemRepoProvider.future);
    _controller = RecognizeController(qwen, glm, lookup, foodRepo);
    return _controller!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('拍照识别')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => _pickAndRecognize(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('拍照'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _pickAndRecognize(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('从相册选择'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndRecognize(ImageSource source) async {
    final controller = await _ensureController();
    await controller.pickAndRecognize(source);

    // 监听状态变化跳转校准页
    final state = controller.state;
    if (state.state == RecognizeState.done && state.recognitionResult != null) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CalibrationPage(
          recognitionResult: state.recognitionResult!,
          singleNutrition: state.singleNutrition,
          compositeNutrition: state.compositeNutrition,
          foodItemRepo: await ref.read(foodItemRepoProvider.future),
          onConfirm: (servingG, calories, protein, fat, carbs, {componentsSnapshot}) async {
            final mealRepo = await ref.read(mealLogRepoProvider.future);
            final foodRepo = await ref.read(foodItemRepoProvider.future);
            final result = state.recognitionResult!;

            // 获取 foodItemId：单品用查库命中，复合菜创建 ai_recognized 记录
            // 必须有有效 food_item_id（meal_log.food_item_id 是非空 FK，
            // Task 2 已启用 PRAGMA foreign_keys = ON，id=0 会触发外键约束违规）
            int foodItemId;
            if (state.singleNutrition != null) {
              foodItemId = state.singleNutrition!.foodItemId;
            } else if (state.compositeNutrition != null) {
              // 复合菜：存入 food_item（source=ai_recognized，components_json 存组分快照）
              foodItemId = await foodRepo.upsertAiRecognized(
                name: result.dishName,
                caloriesPer100g: 0, // 复合菜热量不按 100g 密度存储，实际值在 meal_log
                proteinPer100g: 0,
                fatPer100g: 0,
                carbsPer100g: 0,
                confidence: result.confidence,
                componentsJson: componentsSnapshot,
              );
            } else {
              // 无营养数据（查库未命中），不记录
              return;
            }

            await mealRepo.insertMealLog(
              date: _todayLocalDate(),
              mealType: 'snack', // Sprint 2 加餐次选择 UI
              foodItemId: foodItemId,
              actualServingG: servingG,
              actualCalories: calories,
              actualProteinG: protein,
              actualFatG: fat,
              actualCarbsG: carbs,
              originalImagePath: state.imagePath,
              recognitionConfidence: result.confidence,
              componentsSnapshotJson: componentsSnapshot,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已记录：${calories.toStringAsFixed(0)} kcal')),
              );
            }
          },
        ),
      ));
    } else if (state.state == RecognizeState.error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('识别失败：${state.errorMessage}')),
      );
    }
  }

  String _todayLocalDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
```

- [ ] **Step 6: 实现 dashboard_page（今日额度看板最简版）**

创建 `lib/features/dashboard/dashboard_page.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recognize/providers.dart' as recognize;
import '../recognize/recognize_page.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('今日')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RecognizePage()),
        ),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<double>(
        future: _getTodayCalories(ref),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('今日已摄入', style: Theme.of(context).textTheme.titleMedium),
                Text('${snapshot.data!.toStringAsFixed(0)} kcal',
                    style: Theme.of(context).textTheme.displaySmall),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<double> _getTodayCalories(WidgetRef ref) async {
    final repo = await ref.read(recognize.mealLogRepoProvider.future);
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return repo.getTotalCaloriesByDate(date);
  }
}
```

说明：`mealLogRepoProvider` 定义在 `lib/features/recognize/providers.dart`（Step 4），dashboard_page 用 `as recognize` 别名导入避免命名冲突。Sprint 2 若新增更多页面级 Provider，可提取到 `lib/features/providers.dart` 统一出口；Sprint 1 不预先创建空文件（YAGNI）。

- [ ] **Step 7: 更新 app.dart 路由**

覆盖 `lib/app.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/dashboard/dashboard_page.dart';

class EatWiseApp extends StatelessWidget {
  const EatWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'EatWise',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const DashboardPage(),
    ),
  ],
);
```

- [ ] **Step 8: flutter analyze 验证编译**

```bash
flutter analyze
```

预期：0 errors（warning 允许）。

- [ ] **Step 9: 端到端手动验证（需真实 API key）**

```bash
flutter run -d <设备> --dart-define=QWEN_API_KEY=你的key --dart-define=QWEN_BASE_URL=https://你的workspaceid.cn-beijing.maas.aliyuncs.com/compatible-mode/v1
```

操作步骤：
1. 打开 App → 今日页
2. 点 "+" → 拍一张苹果照片
3. 等待 Qwen-VL 识别 → 校准页弹出
4. 置信度 ≥ 0.85 → 点"一键记录"
5. 回到今日页 → 热量增加

预期：今日页显示已摄入热量增加，Sprint 1 成功。

- [ ] **Step 10: Commit**

```bash
git add lib/
git commit -m "feat: Sprint 1 拍照识别闭环 - 拍照→预处理→Qwen-VL→查库→校准页→写meal_log"
```

---

## Self-Review

完成计划编写后，对照设计文档逐项检查：

**1. Spec 覆盖检查（Sprint 1 范围 7 项）：**

| Sprint 1 项 | 对应 Task | 覆盖 |
|---|---|---|
| 1. 项目脚手架 | Task 1 | ✅ |
| 2. 数据层（7 张表 + 加密 + 迁移） | Task 2 | ✅ |
| 3. 营养计算模块 | Task 3 | ✅ |
| 4. 食材库导入（字段映射 + 别名） | Task 4 | ✅ |
| 5. 拍照识别模块（Qwen-VL + 容灾 + prompt_version） | Task 5 | ✅ |
| 6. 营养查库层（单品/复合菜 + aliases + 用油） | Task 6 | ✅ |
| 7. 校准页 UI（置信度分级） | Task 7 | ✅ |

**2. Placeholder 扫描：**
- Task 1 Step 6 有 `TODO Sprint 3` — 这是合理的跨 Sprint 标注，非占位
- Task 5 Step 5/6 已消除"先错后改"反模式（原 Step 6 Glm4vProvider 含 TODO + 临时实现，原 Step 7/8 重构）— 现直接在 Step 5 写带 `recognizeWithClient` 静态方法的 QwenVlProvider，Step 6 直接写调用静态方法的 Glm4vProvider
- Task 7 Step 6 已消除"先错后改"反模式（原 Step 6 dashboard 用错误 import `'providers.dart'`，原 Step 7 修正）— 现 Step 6 直接写正确的 `import '../recognize/providers.dart' as recognize;`，并删除从未被引用的死代码 `lib/features/providers.dart`
- Task 7 已删除 `UnimplementedError` 占位代码（recognize_page 初版 + providers.dart 的 recognizeControllerProvider），改为 Step 4 providers.dart + Step 5 recognize_page 正式版直接衔接
- 无 "TBD"/"implement later"/"add appropriate error handling" 模式

**3. 类型一致性检查：**
- `VisionRecognitionResult` 在 Task 5 定义，Task 7 引用 — 字段名一致（dishName/estimatedWeightGMid/confidence/isSingleItem/foodComponents）✅
- `NutritionResult` / `CompositeNutritionResult` 在 Task 6 定义，Task 7 引用 — 字段名一致（calories/proteinG/fatG/carbsG/foodItemId/oilG）✅
- `FoodItemRepository.findByNameOrAlias` 在 Task 6 定义，Task 5 无引用 — ✅
- `FoodItemRepository.upsertAiRecognized` 在 Task 6 定义，Task 7 recognize_page onConfirm 引用 — 方法签名一致（name/caloriesPer100g/proteinPer100g/fatPer100g/carbsPer100g/confidence/componentsJson）✅
- `cookingOilCoefficients` 在 Task 6 定义，key 使用 `raw`/`stir-fry`/`boil` 等 — 与 prompt 中 cooking_method 取值一致（含 `raw`）✅
- `food.proteinPer100g` / `fatPer100g` / `carbsPer100g` 在 FoodItems 表定义为 `real()()`（非空），drift 生成的 FoodItem 数据类对应字段为 `double`（非空）— Task 6 NutritionLookup 直接用 `food.proteinPer100g` 而非 `food.proteinPer100g ?? 0`，避免死代码警告 ✅

**4. 外键约束完整性检查（第三轮严审发现并修复）：**
- Task 2 `beforeOpen` 启用 `PRAGMA foreign_keys = ON;` — drift NativeDatabase 默认不启用外键约束 ✅
- Task 2 `recognition_feedback.meal_log_id` 定义 `onDelete: KeyAction.cascade` — 依赖 PRAGMA foreign_keys 生效，级联删除测试通过 ✅
- Task 7 recognize_page onConfirm：复合菜 `foodItemId` 原为 `state.singleNutrition?.foodItemId ?? 0`（id=0 不存在 → FK 违规崩溃）— 已修复为通过 `foodRepo.upsertAiRecognized` 创建 `source=ai_recognized` 的 food_item 记录获取有效 id ✅
- Task 7 recognize_page onConfirm：单品 `foodItemId` = `state.singleNutrition!.foodItemId`（查库命中的有效 id）✅
- Task 7 recognize_page onConfirm：查库未命中（singleNutrition 和 compositeNutrition 均为 null）时 `return` 不写入 — 避免无效 FK ✅

**5. 已知简化项（Sprint 1 故意简化，Sprint 2/3 完善）：**
- Task 7 餐次硬编码 `mealType: 'snack'` — Sprint 2 加餐次选择 UI
- Task 7 API key 用 `--dart-define` — Sprint 3 改 secure_storage + 设置页
- Task 1 Sentry 占位空函数 — Sprint 3 接入
- Task 2 `databaseProvider` 用 `NativeDatabase.memory()` 测试 — 生产用 `openEncryptedConnection()`

---

## 执行交接

计划已完成并保存至 `docs/superpowers/plans/2026-07-01-sprint1-core-recognition.md`。有两种执行方案：

**1. Subagent-Driven（推荐）** - 每个 Task 派发一个新的 subagent，任务间进行审核，迭代速度快。

**2. Inline Execution** - 在本会话中按任务执行，批量执行并设置检查点进行审核。

选择哪种方式？
