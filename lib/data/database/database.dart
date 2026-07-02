import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../seed/food_seed_importer.dart';
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
  /// [seedOnCreate]：首次创建 DB 时是否自动导入食物种子库。
  /// 默认 false（测试用 memory DB 期望空库）；生产 databaseProvider 传 true。
  EatWiseDatabase(super.executor, {this.seedOnCreate = false});

  final bool seedOnCreate;

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
            // 首次创建时导入食物种子库（1664 条中国食物成分表 + 22 组别名）
            // + 50 条品牌饮料零食（可乐/雪碧/薯片等，USDA 公开值）
            // try-catch：导入失败绝不阻塞 DB 创建（否则 app 起不来）。
            // 测试环境（seedOnCreate=false 或 binding 未初始化）静默跳过。
            if (seedOnCreate) {
              try {
                final importer = FoodSeedImporter(this);
                await importer.importFromAssetsFirstTime();
                await importer.importBrandFoodsFirstTime();
                await importer.supplementAliases();
              } catch (_) {
                // 测试环境 binding 未初始化 / 资源缺失 → 静默跳过（不阻塞 DB 创建）
                // 生产环境 assets 已打包，不会走到这里
              }
            }
          }
        },
      );
}

/// 生产环境 Database Provider（Riverpod）
final databaseProvider = FutureProvider<EatWiseDatabase>((ref) async {
  final executor = await openEncryptedConnection();
  final db = EatWiseDatabase(executor, seedOnCreate: true); // 生产环境首次创建导入食物种子库
  ref.onDispose(db.close);
  return db;
});
