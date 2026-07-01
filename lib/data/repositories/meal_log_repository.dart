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
    return meals.fold<double>(0.0, (sum, m) => sum + m.actualCalories);
  }
}
