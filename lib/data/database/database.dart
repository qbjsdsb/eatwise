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
import 'tables/recommendation_feedback_table.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Profiles,
  FoodItems,
  MealLogs,
  WeightLogs,
  PendingRecognitions,
  InsightSummaries,
  RecognitionFeedbacks,
  RecommendationFeedbacks,
])
class EatWiseDatabase extends _$EatWiseDatabase {
  /// 生产环境：传入 openEncryptedConnection() 的 executor
  /// [seedOnCreate]：首次创建 DB 时是否自动导入食物种子库。
  /// 默认 false（测试用 memory DB 期望空库）；生产 databaseProvider 传 true。
  EatWiseDatabase(super.executor, {this.seedOnCreate = false});

  final bool seedOnCreate;

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v1 → v2：profile 表加 3 个特殊人群适配列（全部 nullable，向后兼容）
          // 旧用户升级时自动加列，旧数据保持 null（视为 'none' 默认行为）
          if (from < 2) {
            await m.addColumn(profiles, profiles.specialCondition);
            await m.addColumn(profiles, profiles.dietPreference);
            await m.addColumn(profiles, profiles.healthCondition);
          }
          // v2 → v3：新增 recommendation_feedbacks 表（AI 推荐满意度反馈）
          if (from < 3) {
            await m.createTable(recommendationFeedbacks);
          }
          // v3 → v4：M16.3 修复 P0 —— 清理已入库的脏营养数据
          // sanotsu_common.json 历史版本含 foodCode 134001 (CHO=450) / 134002 (CHO=420300)
          // 等列错位脏数据，已通过 _parseItem 加合理性校验防新导入，但已安装用户
          // DB 里仍有脏数据，需 migration 主动清理。
          // 策略：营养素 > 100g/100g（蛋白/脂肪/碳水）或 > 900 kcal/100g 的条目
          //       视为脏数据，将对应字段置 0（保守降级，避免被 findByNameOrAlias 命中污染复合菜）
          if (from < 4) {
            await customStatement(
                'UPDATE food_items SET carbs_per100g = 0 WHERE carbs_per100g > 100');
            await customStatement(
                'UPDATE food_items SET protein_per100g = 0 WHERE protein_per100g > 100');
            await customStatement(
                'UPDATE food_items SET fat_per100g = 0 WHERE fat_per100g > 100');
            await customStatement(
                'UPDATE food_items SET calories_per100g = 0 WHERE calories_per100g > 900');
          }
          // v4 → v5：M27 v2 —— weight_log 表加 impedance + bodyFatPct 字段
          // 蓝牙体脂秤2（XMTZC05HM）扩展，nullable 向后兼容
          if (from < 5) {
            await m.addColumn(weightLogs, weightLogs.impedance);
            await m.addColumn(weightLogs, weightLogs.bodyFatPct);
          }
          // v5 → v6：D8 性能优化 —— 给高频查询列加索引
          // meal_logs.date（每日查询/趋势图）、meal_logs.food_item_id（中位数份量查询）
          // food_items.name（查库命中 findByNameOrAlias）、food_items.source（过滤 ai_recognized）
          // weight_logs.date（趋势图）、pending_recognitions.status（后台回补取 pending）
          if (from < 6) {
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_meal_logs_date ON meal_logs(date)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_meal_logs_food_item_id ON meal_logs(food_item_id)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_food_items_name ON food_items(name)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_food_items_source ON food_items(source)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_weight_logs_date ON weight_logs(date)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_pending_recognitions_status ON pending_recognitions(status)');
          }
        },
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
            // + 41 条连锁茶饮咖啡品牌官方热量（喜茶/霸王茶姬/瑞幸等 10 品牌招牌，P1）
            // try-catch：导入失败绝不阻塞 DB 创建（否则 app 起不来）。
            // 测试环境（seedOnCreate=false 或 binding 未初始化）静默跳过。
            if (seedOnCreate) {
              try {
                final importer = FoodSeedImporter(this);
                await importer.importFromAssetsFirstTime();
                await importer.importBrandFoodsFirstTime();
                await importer.importChainDrinksFirstTime();
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
