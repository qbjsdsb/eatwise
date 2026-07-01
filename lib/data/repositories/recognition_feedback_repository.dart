import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

/// 识别反馈 Repository（prompt 改进数据源）
class RecognitionFeedbackRepository {
  final EatWiseDatabase _db;
  RecognitionFeedbackRepository(this._db);

  /// 写入识别反馈
  /// isCorrect=true 表示识别正确；isCorrect=false 时可填 correctedDishName/correctedServingG
  Future<int> insert({
    required int mealLogId,
    required bool isCorrect,
    String? correctedDishName,
    double? correctedServingG,
    required String promptVersion,
  }) async {
    return _db.into(_db.recognitionFeedbacks).insert(
          RecognitionFeedbacksCompanion.insert(
            mealLogId: mealLogId,
            isCorrect: isCorrect ? 1 : 0,
            correctedDishName: Value(correctedDishName),
            correctedServingG: Value(correctedServingG),
            promptVersion: promptVersion,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  /// 查询某条 meal_log 是否已有反馈（避免重复反馈）
  Future<bool> hasFeedback(int mealLogId) async {
    final rows = await (_db.recognitionFeedbacks.select()
          ..where((f) => f.mealLogId.equals(mealLogId)))
        .get();
    return rows.isNotEmpty;
  }
}
