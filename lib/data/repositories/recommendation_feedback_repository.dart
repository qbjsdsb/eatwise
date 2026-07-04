// lib/data/repositories/recommendation_feedback_repository.dart
//
// AI 推荐满意度反馈存储（v5 渐进增强）
//
// 用户对 AI 推荐打分（1=不喜欢 / 2=一般 / 3=喜欢），存 SQLite 持久化，
// 下次推荐时读近 30 条注入 prompt，让 AI 学习用户偏好。

import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

/// 推荐满意度反馈记录（drift 生成的行类型）
typedef RecommendationFeedbackRow = RecommendationFeedback;

class RecommendationFeedbackRepository {
  final EatWiseDatabase _db;

  RecommendationFeedbackRepository(this._db);

  /// 记录一条反馈
  Future<int> insertFeedback({
    required String foodName,
    required int rating, // 1=不喜欢 / 2=一般 / 3=喜欢
    String? mealType,
    String? recommendDate,
  }) async {
    if (rating < 1 || rating > 3) {
      throw ArgumentError('rating 必须在 1-3 范围内，实际：$rating');
    }
    return _db.into(_db.recommendationFeedbacks).insert(
          RecommendationFeedbacksCompanion.insert(
            foodName: foodName,
            rating: rating,
            mealType: mealType == null ? const Value.absent() : Value(mealType),
            recommendDate: recommendDate == null
                ? const Value.absent()
                : Value(recommendDate),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  /// 查询近 N 条反馈（按时间倒序），用于注入 prompt
  Future<List<RecommendationFeedbackRow>> getRecent({int limit = 30}) {
    return (_db.recommendationFeedbacks.select()
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  /// 删除所有反馈（用户清除数据时用）
  Future<int> clearAll() {
    return _db.recommendationFeedbacks.delete().go();
  }
}
