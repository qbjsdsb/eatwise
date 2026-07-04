// lib/nutrition/ai_recommendation_service.dart
//
// AI 个性化推荐服务（v5 渐进增强）
//
// 流程：
// 1. 检查当日缓存 → 命中直接返回
// 2. 检查网络/API key → 不满足静默返回空（v4 兜底）
// 3. 聚合上下文（profile + remaining + 历史 + 反馈）→ 构建 prompt
// 4. 调 GLM-4-Flash（JSON 输出，30s 超时）
// 5. 解析 JSON → List<AiRecommendation>
// 6. 失败/超时/解析错误 → 静默返回空（v4 兜底）
// 7. 缓存结果（当日有效）
//
// 降级原则：AI 是"锦上添花"，任何失败都不应阻塞 UI，v4 本地推荐永远兜底。
// 缓存原则：当日有效（key=date+mealType），用户主动"重新生成"时强制刷新。

import 'dart:convert';

import 'package:eatwise/ai/glm_flash_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/data/repositories/recommendation_feedback_repository.dart';
import 'package:flutter/foundation.dart';

import 'ai_recommendation_prompt.dart';
import 'recommendation_service.dart';

/// AI 推荐请求参数（调用方聚合后传入）
class AiRecommendationRequest {
  final String todayDate; // YYYY-MM-DD
  final String mealType; // breakfast/lunch/dinner/snack

  const AiRecommendationRequest({
    required this.todayDate,
    required this.mealType,
  });
}

/// AI 推荐结果（含缓存元信息）
class AiRecommendationResult {
  final List<AiRecommendation> recommendations;
  final bool fromCache; // 是否来自缓存（UI 决定是否显示"已刷新"提示）

  const AiRecommendationResult({
    required this.recommendations,
    required this.fromCache,
  });
}

class AiRecommendationService {
  final GlmFlashProvider _provider;
  final ProfileRepository _profileRepo;
  final MealLogRepository _mealRepo;
  final FoodItemRepository _foodRepo;
  final RecommendationFeedbackRepository _feedbackRepo;

  // 当日内存缓存：key = "${date}_${mealType}"
  // 生命周期：进程内存，App 重启失效。当日有效（用户跨天会重新调 AI）。
  // 用户点"重新生成"时调用方传 forceRefresh=true 跳过缓存。
  static final Map<String, List<AiRecommendation>> _cache = {};

  AiRecommendationService(
    this._provider,
    this._profileRepo,
    this._mealRepo,
    this._foodRepo,
    this._feedbackRepo,
  );

  /// 获取 AI 推荐（渐进增强：失败静默返回空列表，v4 兜底）
  ///
  /// [forceRefresh]：true 时跳过缓存强制刷新（用户点"重新生成"按钮）
  Future<AiRecommendationResult> recommend(
    AiRecommendationRequest request, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${request.todayDate}_${request.mealType}';
    if (!forceRefresh && _cache.containsKey(cacheKey)) {
      return AiRecommendationResult(
        recommendations: _cache[cacheKey]!,
        fromCache: true,
      );
    }

    try {
      final result = await _fetchFromAi(request);
      // 缓存结果（空列表也缓存，避免失败后反复调 AI）
      _cache[cacheKey] = result;
      return AiRecommendationResult(recommendations: result, fromCache: false);
    } catch (e) {
      // 任何异常静默返回空列表，v4 兜底
      // 不缓存失败结果（下次进看板允许重试）
      debugPrint('AI 推荐失败（v4 兜底）：$e');
      return const AiRecommendationResult(recommendations: [], fromCache: false);
    }
  }

  /// 调 AI 获取推荐（内部方法，可能抛异常由调用方兜底）
  Future<List<AiRecommendation>> _fetchFromAi(
      AiRecommendationRequest request) async {
    // 1. 聚合上下文（并行查询无依赖）
    final profileFuture = _profileRepo.get();
    final remainingFuture =
        RecommendationService(_foodRepo, _mealRepo, _profileRepo)
            .getDailyRemaining(request.todayDate);
    final recentMealsFuture = _mealRepo.getRecentMeals(days: 14);
    final foodsFuture = _foodRepo.listAllForRecommendation();
    final feedbacksFuture = _feedbackRepo.getRecent(limit: 30);
    // 近 3 天已吃食物名（避免重复推荐）
    final recent3DaysFutures = <Future<List<MealLog>>>[];
    for (var i = 0; i < 3; i++) {
      final d = DateTime.now().subtract(Duration(days: i));
      final ymd =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      recent3DaysFutures.add(_mealRepo.getMealsByDate(ymd));
    }

    final profile = await profileFuture;
    final remaining = await remainingFuture;
    final recentMeals = await recentMealsFuture;
    final foods = await foodsFuture;
    final feedbacks = await feedbacksFuture;
    final recent3DaysMeals = await Future.wait(recent3DaysFutures);

    final foodMap = {for (final f in foods) f.id: f};
    final recentFoodNames = <String>{};
    for (final meals in recent3DaysMeals) {
      for (final m in meals) {
        final food = foodMap[m.foodItemId];
        if (food != null) recentFoodNames.add(food.name);
      }
    }

    // 2. 构建 prompt
    final ctx = AiRecommendationContext(
      profile: profile,
      remaining: remaining,
      mealType: request.mealType,
      recentMeals: recentMeals,
      foodMap: foodMap,
      recentFoodNames: recentFoodNames,
      feedbacks: feedbacks
          .map((f) => FeedbackRecord(
                foodName: f.foodName,
                rating: f.rating,
                createdAt: DateTime.fromMillisecondsSinceEpoch(f.createdAt),
              ))
          .toList(),
    );
    final userPrompt = AiRecommendationPrompt.buildUserPrompt(ctx);

    // 3. 调 GLM-4-Flash（JSON 输出，30s 超时）
    final raw = await _callGlm(userPrompt).timeout(
      const Duration(seconds: 30),
    );

    // 4. 解析 JSON
    return _parseRecommendations(raw);
  }

  /// 调 GLM-4-Flash（封装以便测试 mock）
  Future<String> _callGlm(String userPrompt) async {
    return _provider.createChatCompletion(
      systemPrompt: AiRecommendationPrompt.systemPrompt,
      userPrompt: userPrompt,
      temperature: 0.8, // 推荐需一定随机性，避免每次都推相同的 5 道菜
    );
  }

  /// 解析 AI 返回的 JSON 为推荐列表（静态方法，易测）
  static List<AiRecommendation> parseRecommendations(String raw) =>
      _parseRecommendations(raw);

  static List<AiRecommendation> _parseRecommendations(String raw) {
    if (raw.isEmpty) return [];
    // 兼容 AI 偶尔在 JSON 外加 markdown 代码块或解释文字
    final jsonStr = _extractJson(raw);
    if (jsonStr == null) return [];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) return [];
      final list = decoded['recommendations'];
      if (list is! List) return [];
      final result = <AiRecommendation>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final name = item['name'];
        final reason = item['reason'];
        if (name is! String || name.trim().isEmpty) continue;
        if (reason is! String || reason.trim().isEmpty) continue;
        result.add(AiRecommendation(
          name: name.trim(),
          reason: reason.trim(),
          estimatedCalories: _toDouble(item['estimatedCalories']),
          estimatedProtein: _toDouble(item['estimatedProtein']),
        ));
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// 从可能含 markdown/解释文字的字符串中提取 JSON 对象
  /// 找第一个 `{` 到最后一个 `}` 的子串
  static String? _extractJson(String raw) {
    final start = raw.indexOf('{');
    if (start < 0) return null;
    final end = raw.lastIndexOf('}');
    if (end <= start) return null;
    return raw.substring(start, end + 1);
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  /// 清除当日缓存（测试用）
  static void clearCache() => _cache.clear();
}
