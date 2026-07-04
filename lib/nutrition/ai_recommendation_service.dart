// lib/nutrition/ai_recommendation_service.dart
//
// AI 个性化推荐服务（v5 渐进增强）
//
// 流程：
// 1. 检查当日缓存 → 命中直接返回
// 2. 检查网络/API key → 不满足静默返回空（v4 兜底）
// 3. 聚合上下文（profile + remaining + 历史 + 反馈）→ 构建 prompt
// 4. 调 GLM-4-Flash（JSON 输出，30s 超时）
// 5. 解析 JSON → List<AiRecommendation>（最多 5 条）
// 6. 失败/超时/解析错误 → 静默返回空（v4 兜底）
// 7. 缓存成功结果（当日有效，profile 变化时自动失效）
//
// 降级原则：AI 是"锦上添花"，任何失败都不应阻塞 UI，v4 本地推荐永远兜底。
// 缓存原则：当日有效（key=date+mealType+profileHash），用户主动"重新生成"时强制刷新。
// 解析失败不缓存（与"AI 真返回 0 条"区分），下次进看板允许重试。

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

  // 当日内存缓存：key = "${date}_${mealType}_${profileHash}"
  // 生命周期：进程内存，App 重启失效。当日有效（用户跨天或改 profile 会重新调 AI）。
  // 用户点"重新生成"时调用方传 forceRefresh=true 跳过缓存。
  //
  // 值用 Future 而非 List：避免并发请求重复调 AI（如用户连点"换一批"），
  // 多个调用方共享同一 Future，结果只算一次。
  static final Map<String, Future<List<AiRecommendation>>> _cache = {};

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
    // 先读 profile 算 cacheKey（含 profileHash，profile 变化时缓存自动失效）
    final profile = await _profileRepo.get();
    final cacheKey =
        '${request.todayDate}_${request.mealType}_${profile.hashCode}';

    // 清理非当日缓存（避免静态 Map 无限增长）
    _evictStaleCache(request.todayDate);

    if (!forceRefresh && _cache.containsKey(cacheKey)) {
      try {
        final cached = await _cache[cacheKey]!;
        return AiRecommendationResult(recommendations: cached, fromCache: true);
      } catch (_) {
        // 缓存的 Future 失败（之前 AI 失败），删除并重新尝试
        _cache.remove(cacheKey);
      }
    }

    // 用 Future 缓存实现互斥：并发调用共享同一 Future
    final future = _fetchFromAi(request, profile);
    _cache[cacheKey] = future;
    try {
      final result = await future;
      return AiRecommendationResult(recommendations: result, fromCache: false);
    } catch (e) {
      // 任何异常静默返回空列表，v4 兜底
      // 失败结果不缓存（删除刚写入的失败 Future，下次进看板允许重试）
      _cache.remove(cacheKey);
      debugPrint('AI 推荐失败（v4 兜底）：$e');
      return const AiRecommendationResult(recommendations: [], fromCache: false);
    }
  }

  /// 清理非当日缓存（避免静态 Map 无限增长）
  void _evictStaleCache(String todayDate) {
    _cache.removeWhere((key, _) {
      // key 格式：${date}_${mealType}_${profileHash}
      // 只保留以 todayDate 开头的 key
      return !key.startsWith('${todayDate}_');
    });
  }

  /// 调 AI 获取推荐（内部方法，可能抛异常由调用方兜底）
  Future<List<AiRecommendation>> _fetchFromAi(
      AiRecommendationRequest request, Profile profile) async {
    // 1. 聚合上下文（并行查询无依赖）
    // profile 由调用方传入，避免与 getDailyRemaining 内部重复查询
    final remaining =
        await RecommendationService(_foodRepo, _mealRepo, _profileRepo)
            .getDailyRemaining(request.todayDate);
    final recentMealsFuture = _mealRepo.getRecentMeals(days: 14);
    final foodsFuture = _foodRepo.listAllForRecommendation();
    final feedbacksFuture = _feedbackRepo.getRecent(limit: 30);

    final recentMeals = await recentMealsFuture;
    final foods = await foodsFuture;
    final feedbacks = await feedbacksFuture;

    final foodMap = {for (final f in foods) f.id: f};
    // 近 3 天已吃食物名：从 14 天 recentMeals 内存过滤（避免重复查 3 次 DB）
    final now = DateTime.now();
    final recentFoodNames = <String>{};
    for (var i = 0; i < 3; i++) {
      final d = now.subtract(Duration(days: i));
      final ymd =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      for (final m in recentMeals) {
        if (m.date == ymd) {
          final food = foodMap[m.foodItemId];
          if (food != null) recentFoodNames.add(food.name);
        }
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

    // 4. 解析 JSON（最多 5 条，避免 AI 返回过多）
    final all = _parseRecommendations(raw);
    return all.take(5).toList();
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
  ///
  /// 解析失败时抛 [FormatException]，让调用方决定是否缓存。
  /// 这样可以区分"AI 真返回 0 条"（缓存空列表）与"解析失败"（不缓存）。
  static List<AiRecommendation> parseRecommendations(String raw) =>
      _parseRecommendations(raw);

  static List<AiRecommendation> _parseRecommendations(String raw) {
    if (raw.isEmpty) return [];
    // 兼容 AI 偶尔在 JSON 外加 markdown 代码块或解释文字
    final jsonStr = _extractJson(raw);
    if (jsonStr == null) {
      throw FormatException('AI 响应无 JSON 对象：$raw');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonStr);
    } catch (e) {
      throw FormatException('AI 响应 JSON 解析失败：$e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('AI 响应非 JSON 对象：$decoded');
    }
    final list = decoded['recommendations'];
    if (list is! List) {
      throw FormatException('AI 响应无 recommendations 数组：$decoded');
    }
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
  }

  /// 从可能含 markdown/解释文字的字符串中提取 JSON 对象
  /// 用括号配对扫描（而非简单的 first/last），支持多个 JSON 对象场景
  static String? _extractJson(String raw) {
    final start = raw.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < raw.length; i++) {
      final c = raw[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (c == '\\') {
        escape = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          return raw.substring(start, i + 1);
        }
      }
    }
    return null; // 未找到匹配的闭合括号
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  /// 清除当日缓存（测试用）
  static void clearCache() => _cache.clear();
}
