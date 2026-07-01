import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

/// 全表导入 JSON（清空后批量插入，保留原 ID 维持外键关系）
class JsonImporter {
  final EatWiseDatabase _db;
  JsonImporter(this._db);

  /// 从 JSON 字符串导入，返回各表条数统计
  Future<({int profiles, int foodItems, int mealLogs, int weightLogs, int insights, int feedbacks})>
      importFromString(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    return importFromMap(data);
  }

  Future<({int profiles, int foodItems, int mealLogs, int weightLogs, int insights, int feedbacks})>
      importFromMap(Map<String, dynamic> data) async {
    final schemaVersion = data['schemaVersion'] as int;
    if (schemaVersion != _db.schemaVersion) {
      throw ArgumentError(
          'schemaVersion 不匹配：文件 $schemaVersion vs 当前 ${_db.schemaVersion}');
    }

    final tables = data['tables'] as Map<String, dynamic>;
    // 用 transaction 包裹：DELETE + 批量 INSERT 原子化，中途失败回滚避免半库
    // PRAGMA foreign_keys 在事务外设置无效，故用批量 DELETE 顺序（先子后父）规避级联
    return _db.transaction(() async {
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
  }

  ProfilesCompanion _profileFromJson(Map<String, dynamic> j) =>
      ProfilesCompanion.insert(
        id: Value(j['id'] as int),
        heightCm: j['heightCm'] as double,
        weightKg: j['weightKg'] as double,
        bodyFatPct: Value(j['bodyFatPct'] as double?),
        age: j['age'] as int,
        gender: j['gender'] as String,
        activityLevel: j['activityLevel'] as double,
        goal: j['goal'] as String,
        goalRateKgPerWeek: j['goalRateKgPerWeek'] as double,
        formula: j['formula'] as String,
        dailyCalorieTarget: j['dailyCalorieTarget'] as int,
        proteinGPerKg: j['proteinGPerKg'] as double,
        fatGPerKg: j['fatGPerKg'] as double,
        carbGPerKg: Value(j['carbGPerKg'] as double?),
        tdeeAdjustmentKcal: Value(j['tdeeAdjustmentKcal'] as int),
        updatedAt: j['updatedAt'] as int,
      );

  FoodItemsCompanion _foodItemFromJson(Map<String, dynamic> j) =>
      FoodItemsCompanion.insert(
        id: Value(j['id'] as int), // 保留原 ID（外键依赖）
        name: j['name'] as String,
        defaultServingG: j['defaultServingG'] as double,
        caloriesPer100g: j['caloriesPer100g'] as double,
        proteinPer100g: j['proteinPer100g'] as double,
        fatPer100g: j['fatPer100g'] as double,
        carbsPer100g: j['carbsPer100g'] as double,
        aliasesJson: Value(j['aliasesJson'] as String?),
        ediblePercent: Value(j['ediblePercent'] as double?),
        source: j['source'] as String,
        sourceVersion: j['sourceVersion'] as String,
        confidence: Value(j['confidence'] as double?),
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
        actualServingG: j['actualServingG'] as double,
        actualCalories: j['actualCalories'] as double,
        actualProteinG: j['actualProteinG'] as double,
        actualFatG: j['actualFatG'] as double,
        actualCarbsG: j['actualCarbsG'] as double,
        originalImagePath: Value(j['originalImagePath'] as String?),
        recognitionConfidence: Value(j['recognitionConfidence'] as double?),
        componentsSnapshotJson: Value(j['componentsSnapshotJson'] as String?),
        loggedAt: j['loggedAt'] as int,
      );

  WeightLogsCompanion _weightLogFromJson(Map<String, dynamic> j) =>
      WeightLogsCompanion.insert(
        id: Value(j['id'] as int),
        date: j['date'] as String,
        weightKg: j['weightKg'] as double,
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
        correctedServingG: Value(j['correctedServingG'] as double?),
        promptVersion: j['promptVersion'] as String,
        createdAt: j['createdAt'] as int,
      );
}
