import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  EatWiseDatabase(super.executor);

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
