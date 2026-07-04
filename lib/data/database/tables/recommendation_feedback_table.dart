import 'package:drift/drift.dart';

/// AI 推荐满意度反馈表（v5 渐进增强）
///
/// 用户在 dashboard 推荐卡片上对每条 AI 推荐打分（1=不喜欢 / 2=一般 / 3=喜欢），
/// 用于下次推荐时注入 prompt，让 AI 学习用户偏好。
///
/// 不设外键：foodName 直接存字符串（AI 推荐的食物可能不在食物库），
/// 避免用户记录前先入库的约束。即使食物改名/删除，历史反馈仍保留学习价值。
class RecommendationFeedbacks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get foodName => text()();
  /// 1=不喜欢 / 2=一般 / 3=喜欢
  IntColumn get rating => integer()();
  /// 当时推荐的餐次 breakfast/lunch/dinner/snack，便于时段感知学习
  TextColumn get mealType => text().nullable()();
  /// 当时推荐的日期 YYYY-MM-DD，便于按时间窗口过滤
  TextColumn get recommendDate => text().nullable()();
  IntColumn get createdAt => integer()(); // UTC 毫秒
}
