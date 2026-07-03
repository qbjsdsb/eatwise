import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

/// 全表导出 JSON（含 schemaVersion）
/// 不导出 pending_recognitions（临时队列）
class JsonExporter {
  final EatWiseDatabase _db;
  JsonExporter(this._db);

  /// 导出全表为 JSON Map
  /// 结构：{ schemaVersion: 1, exportedAt: ms, tables: { profiles: [...], ... } }
  Future<Map<String, dynamic>> export() async {
    final profiles = await _db.profiles.select().get();
    final foodItems = await _db.foodItems.select().get();
    final mealLogs = await _db.mealLogs.select().get();
    final weightLogs = await _db.weightLogs.select().get();
    final insightSummaries = await _db.insightSummaries.select().get();
    final recognitionFeedbacks = await _db.recognitionFeedbacks.select().get();

    return {
      'schemaVersion': _db.schemaVersion,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'tables': {
        'profiles': profiles.map(_profileToJson).toList(),
        'food_items': foodItems.map(_foodItemToJson).toList(),
        'meal_logs': mealLogs.map(_mealLogToJson).toList(),
        'weight_logs': weightLogs.map(_weightLogToJson).toList(),
        'insight_summaries': insightSummaries.map(_insightToJson).toList(),
        'recognition_feedbacks':
            recognitionFeedbacks.map(_feedbackToJson).toList(),
        // 注意：pending_recognitions 不导出（临时队列）
      },
    };
  }

  /// 导出为 JSON 字符串
  Future<String> exportAsString() async {
    final data = await export();
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Map<String, dynamic> _profileToJson(Profile p) => {
        'id': p.id,
        'heightCm': p.heightCm,
        'weightKg': p.weightKg,
        'bodyFatPct': p.bodyFatPct,
        'age': p.age,
        'gender': p.gender,
        'activityLevel': p.activityLevel,
        'goal': p.goal,
        'goalRateKgPerWeek': p.goalRateKgPerWeek,
        'formula': p.formula,
        'dailyCalorieTarget': p.dailyCalorieTarget,
        'proteinGPerKg': p.proteinGPerKg,
        'fatGPerKg': p.fatGPerKg,
        'carbGPerKg': p.carbGPerKg,
        'tdeeAdjustmentKcal': p.tdeeAdjustmentKcal,
        // 特殊人群适配（schema v2 新增，null 表示旧数据未设置）
        'specialCondition': p.specialCondition,
        'dietPreference': p.dietPreference,
        'healthCondition': p.healthCondition,
        'updatedAt': p.updatedAt,
      };

  Map<String, dynamic> _foodItemToJson(FoodItem f) => {
        'id': f.id,
        'name': f.name,
        'defaultServingG': f.defaultServingG,
        'caloriesPer100g': f.caloriesPer100g,
        'proteinPer100g': f.proteinPer100g,
        'fatPer100g': f.fatPer100g,
        'carbsPer100g': f.carbsPer100g,
        'aliasesJson': f.aliasesJson,
        'ediblePercent': f.ediblePercent,
        'source': f.source,
        'sourceVersion': f.sourceVersion,
        'confidence': f.confidence,
        'componentsJson': f.componentsJson,
        // thumbnailPath 导出但标记"可能失效"（不同设备路径不同）
        'thumbnailPath': f.thumbnailPath,
        'createdAt': f.createdAt,
      };

  Map<String, dynamic> _mealLogToJson(MealLog m) => {
        'id': m.id,
        'date': m.date,
        'mealType': m.mealType,
        'foodItemId': m.foodItemId,
        'actualServingG': m.actualServingG,
        'actualCalories': m.actualCalories,
        'actualProteinG': m.actualProteinG,
        'actualFatG': m.actualFatG,
        'actualCarbsG': m.actualCarbsG,
        'originalImagePath': m.originalImagePath,
        'recognitionConfidence': m.recognitionConfidence,
        'componentsSnapshotJson': m.componentsSnapshotJson,
        'loggedAt': m.loggedAt,
      };

  Map<String, dynamic> _weightLogToJson(WeightLog w) => {
        'id': w.id,
        'date': w.date,
        'weightKg': w.weightKg,
      };

  Map<String, dynamic> _insightToJson(InsightSummary i) => {
        'id': i.id,
        'periodType': i.periodType,
        'periodStart': i.periodStart,
        'periodEnd': i.periodEnd,
        'summaryText': i.summaryText,
        'isEdited': i.isEdited,
        'generatedAt': i.generatedAt,
      };

  Map<String, dynamic> _feedbackToJson(RecognitionFeedback f) => {
        'id': f.id,
        'mealLogId': f.mealLogId,
        'isCorrect': f.isCorrect,
        'correctedDishName': f.correctedDishName,
        'correctedServingG': f.correctedServingG,
        'promptVersion': f.promptVersion,
        'createdAt': f.createdAt,
      };
}
