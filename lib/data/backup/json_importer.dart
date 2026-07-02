import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

/// 全表导入 JSON（清空后批量插入，保留原 ID 维持外键关系）
class JsonImporter {
  final EatWiseDatabase _db;
  JsonImporter(this._db);

  /// 从 JSON 字符串导入，返回各表条数统计 + 图片失效检测结果
  Future<({int profiles, int foodItems, int mealLogs, int weightLogs, int insights, int feedbacks, ImageCheckResult imageCheckResult})>
      importFromString(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    return importFromMap(data);
  }

  Future<({int profiles, int foodItems, int mealLogs, int weightLogs, int insights, int feedbacks, ImageCheckResult imageCheckResult})>
      importFromMap(Map<String, dynamic> data) async {
    final schemaVersion = data['schemaVersion'] as int;
    if (schemaVersion != _db.schemaVersion) {
      throw ArgumentError(
          'schemaVersion 不匹配：文件 $schemaVersion vs 当前 ${_db.schemaVersion}');
    }

    final tables = data['tables'] as Map<String, dynamic>;
    // 用 transaction 包裹：DELETE + 批量 INSERT 原子化，中途失败回滚避免半库
    // PRAGMA foreign_keys 在事务外设置无效，故用批量 DELETE 顺序（先子后父）规避级联
    final result = await _db.transaction(() async {
      // 清空 6 表（顺序：先子表后父表，避免外键约束冲突）
      await _db.customStatement('DELETE FROM recognition_feedbacks;');
      await _db.customStatement('DELETE FROM insight_summaries;');
      await _db.customStatement('DELETE FROM weight_logs;');
      await _db.customStatement('DELETE FROM meal_logs;');
      await _db.customStatement('DELETE FROM food_items;');
      await _db.customStatement('DELETE FROM profiles;');

      var profiles = 0, foodItems = 0, mealLogs = 0, weightLogs = 0, insights = 0, feedbacks = 0;

      // 1. profiles
      for (final p in (tables['profiles'] as List)) {
        await _db.into(_db.profiles)
            .insert(_profileFromJson(p as Map<String, dynamic>));
        profiles++;
      }
      // 2. food_items
      for (final f in (tables['food_items'] as List)) {
        await _db.into(_db.foodItems)
            .insert(_foodItemFromJson(f as Map<String, dynamic>));
        foodItems++;
      }
      // 3. meal_logs（依赖 food_items）
      for (final m in (tables['meal_logs'] as List)) {
        await _db.into(_db.mealLogs)
            .insert(_mealLogFromJson(m as Map<String, dynamic>));
        mealLogs++;
      }
      // 4. weight_logs（独立）
      for (final w in (tables['weight_logs'] as List)) {
        await _db.into(_db.weightLogs)
            .insert(_weightLogFromJson(w as Map<String, dynamic>));
        weightLogs++;
      }
      // 5. insight_summaries（独立）
      for (final i in (tables['insight_summaries'] as List)) {
        await _db.into(_db.insightSummaries)
            .insert(_insightFromJson(i as Map<String, dynamic>));
        insights++;
      }
      // 6. recognition_feedbacks（依赖 meal_logs）
      for (final f in (tables['recognition_feedbacks'] as List)) {
        await _db.into(_db.recognitionFeedbacks)
            .insert(_feedbackFromJson(f as Map<String, dynamic>));
        feedbacks++;
      }

      return (
        profiles: profiles,
        foodItems: foodItems,
        mealLogs: mealLogs,
        weightLogs: weightLogs,
        insights: insights,
        feedbacks: feedbacks,
      );
    });
    // 事务外执行图片失效检测（独立操作，避免嵌套事务）
    final imageCheck = await _checkAndCleanImagePaths();
    return (
      profiles: result.profiles,
      foodItems: result.foodItems,
      mealLogs: result.mealLogs,
      weightLogs: result.weightLogs,
      insights: result.insights,
      feedbacks: result.feedbacks,
      imageCheckResult: imageCheck,
    );
  }

  /// 检测 meal_log.original_image_path 与 food_item.thumbnail_path 对应文件是否存在，
  /// 不存在则置空并计数。换机场景：图片未随 JSON 迁移，路径失效。
  Future<ImageCheckResult> _checkAndCleanImagePaths() async {
    int mealLogMissing = 0;
    int foodItemMissing = 0;

    // 检查 meal_log.original_image_path
    final meals = await _db.mealLogs.select().get();
    for (final m in meals) {
      if (m.originalImagePath != null && m.originalImagePath!.isNotEmpty) {
        final file = File(m.originalImagePath!);
        if (!await file.exists()) {
          await (_db.mealLogs.update()..where((row) => row.id.equals(m.id)))
              .write(const MealLogsCompanion(originalImagePath: Value(null)));
          mealLogMissing++;
        }
      }
    }

    // 检查 food_item.thumbnail_path
    final foods = await _db.foodItems.select().get();
    for (final f in foods) {
      if (f.thumbnailPath != null && f.thumbnailPath!.isNotEmpty) {
        final file = File(f.thumbnailPath!);
        if (!await file.exists()) {
          await (_db.foodItems.update()..where((row) => row.id.equals(f.id)))
              .write(const FoodItemsCompanion(thumbnailPath: Value(null)));
          foodItemMissing++;
        }
      }
    }

    return ImageCheckResult(
        mealLogMissing: mealLogMissing, foodItemMissing: foodItemMissing);
  }

  ProfilesCompanion _profileFromJson(Map<String, dynamic> j) =>
      ProfilesCompanion.insert(
        id: Value(j['id'] as int),
        heightCm: _asDouble(j['heightCm']),
        weightKg: _asDouble(j['weightKg']),
        bodyFatPct: Value(_asDoubleOrNull(j['bodyFatPct'])),
        age: j['age'] as int,
        gender: j['gender'] as String,
        activityLevel: _asDouble(j['activityLevel']),
        goal: j['goal'] as String,
        goalRateKgPerWeek: _asDouble(j['goalRateKgPerWeek']),
        formula: j['formula'] as String,
        dailyCalorieTarget: j['dailyCalorieTarget'] as int,
        proteinGPerKg: _asDouble(j['proteinGPerKg']),
        fatGPerKg: _asDouble(j['fatGPerKg']),
        carbGPerKg: Value(_asDoubleOrNull(j['carbGPerKg'])),
        tdeeAdjustmentKcal: Value(j['tdeeAdjustmentKcal'] as int),
        updatedAt: j['updatedAt'] as int,
      );

  FoodItemsCompanion _foodItemFromJson(Map<String, dynamic> j) =>
      FoodItemsCompanion.insert(
        id: Value(j['id'] as int), // 保留原 ID（外键依赖）
        name: j['name'] as String,
        defaultServingG: _asDouble(j['defaultServingG']),
        caloriesPer100g: _asDouble(j['caloriesPer100g']),
        proteinPer100g: _asDouble(j['proteinPer100g']),
        fatPer100g: _asDouble(j['fatPer100g']),
        carbsPer100g: _asDouble(j['carbsPer100g']),
        aliasesJson: Value(j['aliasesJson'] as String?),
        ediblePercent: Value(_asDoubleOrNull(j['ediblePercent'])),
        source: j['source'] as String,
        sourceVersion: j['sourceVersion'] as String,
        confidence: Value(_asDoubleOrNull(j['confidence'])),
        componentsJson: Value(j['componentsJson'] as String?),
        thumbnailPath: Value(j['thumbnailPath'] as String?),
        createdAt: j['createdAt'] as int,
      );

  MealLogsCompanion _mealLogFromJson(Map<String, dynamic> j) =>
      MealLogsCompanion.insert(
        id: Value(j['id'] as int),
        date: j['date'] as String,
        mealType: j['mealType'] as String,
        foodItemId: j['foodItemId'] as int,
        actualServingG: _asDouble(j['actualServingG']),
        actualCalories: _asDouble(j['actualCalories']),
        actualProteinG: _asDouble(j['actualProteinG']),
        actualFatG: _asDouble(j['actualFatG']),
        actualCarbsG: _asDouble(j['actualCarbsG']),
        originalImagePath: Value(j['originalImagePath'] as String?),
        recognitionConfidence: Value(_asDoubleOrNull(j['recognitionConfidence'])),
        componentsSnapshotJson: Value(j['componentsSnapshotJson'] as String?),
        loggedAt: j['loggedAt'] as int,
      );

  WeightLogsCompanion _weightLogFromJson(Map<String, dynamic> j) =>
      WeightLogsCompanion.insert(
        id: Value(j['id'] as int),
        date: j['date'] as String,
        weightKg: _asDouble(j['weightKg']),
      );

  InsightSummariesCompanion _insightFromJson(Map<String, dynamic> j) =>
      InsightSummariesCompanion.insert(
        id: Value(j['id'] as int),
        periodType: j['periodType'] as String,
        periodStart: j['periodStart'] as String,
        periodEnd: j['periodEnd'] as String,
        summaryText: j['summaryText'] as String,
        isEdited: Value(j['isEdited'] as int),
        generatedAt: j['generatedAt'] as int,
      );

  RecognitionFeedbacksCompanion _feedbackFromJson(Map<String, dynamic> j) =>
      RecognitionFeedbacksCompanion.insert(
        id: Value(j['id'] as int),
        mealLogId: j['mealLogId'] as int,
        isCorrect: j['isCorrect'] as int,
        correctedDishName: Value(j['correctedDishName'] as String?),
        correctedServingG: Value(_asDoubleOrNull(j['correctedServingG'])),
        promptVersion: j['promptVersion'] as String,
        createdAt: j['createdAt'] as int,
      );

  /// JSON 数值类型安全转换：JSON 数字可能是 int 或 double，直接 `as double` 会在 int 时抛 _TypeError
  double _asDouble(dynamic v) => (v as num).toDouble();

  /// 可空版本
  double? _asDoubleOrNull(dynamic v) => v == null ? null : (v as num).toDouble();
}

/// 图片失效检测结果（换机场景：图片未随 JSON 迁移）
class ImageCheckResult {
  final int mealLogMissing;
  final int foodItemMissing;
  ImageCheckResult({required this.mealLogMissing, required this.foodItemMissing});
  int get totalMissing => mealLogMissing + foodItemMissing;
}
