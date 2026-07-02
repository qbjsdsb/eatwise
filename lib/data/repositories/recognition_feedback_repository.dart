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

  /// 按 prompt_version 聚合准确率
  /// 返回 {promptVersion: {total, correct, accuracy}}
  Future<Map<String, Map<String, dynamic>>> getAccuracyByPromptVersion() async {
    final rows = await _db.select(_db.recognitionFeedbacks).get();
    final result = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final pv = r.promptVersion;
      result.putIfAbsent(pv, () => {'total': 0, 'correct': 0, 'accuracy': 0.0});
      result[pv]!['total'] = (result[pv]!['total'] as int) + 1;
      if (r.isCorrect == 1) {
        result[pv]!['correct'] = (result[pv]!['correct'] as int) + 1;
      }
    }
    // 计算准确率
    for (final pv in result.keys) {
      final total = result[pv]!['total'] as int;
      final correct = result[pv]!['correct'] as int;
      result[pv]!['accuracy'] = total > 0 ? correct / total : 0.0;
    }
    return result;
  }

  /// 查询某 prompt_version 的错判样本（供动态回归集导出）
  /// 返回含 mealLogId/correctedDishName/correctedServingG 的列表
  Future<List<({int mealLogId, String? correctedDishName, double? correctedServingG})>>
      getWrongSamples(String promptVersion) async {
    final rows = await (_db.recognitionFeedbacks.select()
          ..where((f) => f.promptVersion.equals(promptVersion) & f.isCorrect.equals(0)))
        .get();
    return rows
        .map((r) => (
              mealLogId: r.mealLogId,
              correctedDishName: r.correctedDishName,
              correctedServingG: r.correctedServingG,
            ))
        .toList();
  }
}
