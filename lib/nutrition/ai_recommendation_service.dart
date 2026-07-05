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
import 'dish_name_normalizer.dart';
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

/// AI 推荐结果（含缓存元信息 + 失败原因）
class AiRecommendationResult {
  final List<AiRecommendation> recommendations;
  final bool fromCache; // 是否来自缓存（UI 决定是否显示"已刷新"提示）
  final String? error; // 失败原因（null=成功；非 null=AI 失败已 v4 兜底，UI 可 toast 提示）

  const AiRecommendationResult({
    required this.recommendations,
    required this.fromCache,
    this.error,
  });

  /// 是否失败（v4 兜底）
  bool get hasError => error != null && recommendations.isEmpty;
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
  /// 失败时返回 AiRecommendationResult.error 非 null，UI 可据此显示错误提示。
  /// 失败/空结果不缓存（下次进看板允许重试），避免当日永久失效。
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
      // 空结果不缓存（可能是 AI 抽风返回 0 条，下次允许重试）
      if (result.isEmpty) {
        _cache.remove(cacheKey);
        return const AiRecommendationResult(
          recommendations: [],
          fromCache: false,
          error: 'AI 未返回有效推荐，已切换本地推荐',
        );
      }
      return AiRecommendationResult(recommendations: result, fromCache: false);
    } catch (e) {
      // 任何异常静默返回空列表，v4 兜底
      // 失败结果不缓存（删除刚写入的失败 Future，下次进看板允许重试）
      _cache.remove(cacheKey);
      debugPrint('AI 推荐失败（v4 兜底）：$e');
      return AiRecommendationResult(
        recommendations: const [],
        fromCache: false,
        error: _friendlyError(e),
      );
    }
  }

  /// 将异常转为用户友好的错误文案
  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('TimeoutException') || s.contains('timeout')) {
      return 'AI 响应超时，已切换本地推荐';
    }
    if (s.contains('401') || s.contains('Unauthorized')) {
      return 'GLM API Key 无效，已切换本地推荐';
    }
    // L1：403 权限不足（key 有效但无 GLM-4-Flash 调用权限）
    if (s.contains('403') || s.contains('Forbidden')) {
      return 'GLM API Key 权限不足，已切换本地推荐';
    }
    if (s.contains('429') || s.contains('rate limit')) {
      return 'AI 调用太频繁，请稍后重试';
    }
    // L1：5xx 服务器错误（500/502/503/504 等）
    if (RegExp(r'5\d{2}').hasMatch(s) ||
        s.contains('Internal Server Error') ||
        s.contains('server error')) {
      return 'AI 服务暂时不可用，已切换本地推荐';
    }
    if (s.contains('SocketException') || s.contains('network')) {
      return '网络连接失败，已切换本地推荐';
    }
    return 'AI 推荐暂不可用，已切换本地推荐';
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
    // 近 7 天已吃食物名（M19：3→7 天）：从 14 天 recentMeals 内存过滤（避免重复查 DB）
    // 归一化后存入（M19：让"炒鸡胸肉"和"鸡胸肉"在去重时被视为同一道菜）
    final now = DateTime.now();
    final recentFoodNames = <String>{};
    for (var i = 0; i < 7; i++) {
      final d = now.subtract(Duration(days: i));
      final ymd =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      for (final m in recentMeals) {
        if (m.date == ymd) {
          final food = foodMap[m.foodItemId];
          if (food != null) {
            recentFoodNames.add(normalizeDishName(food.name));
          }
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

    // 4. 解析 JSON + 后处理去重（M19：AI 内部去重 + 与近 7 天已吃食物归一化去重）
    final all = _parseRecommendations(raw);
    final deduped = _deduplicateAgainstHistory(all, recentFoodNames);
    return deduped.take(5).toList();
  }

  /// 后处理去重（M19）：AI 返回内部去重 + 与近 7 天已吃食物归一化去重
  ///
  /// 策略：
  /// 1. AI 返回内部去重：同一归一化菜名出现多次，只保留首次
  /// 2. 历史去重：归一化菜名 ∈ recentFoodNames（已归一化）则剔除
  ///
  /// 返回去重后的列表（可能少于 5 道，调用方 take(5) 安全）
  /// 少于 5 道时不补足（避免再调 AI 的成本 + v4 兜底已混合展示）
  static List<AiRecommendation> _deduplicateAgainstHistory(
    List<AiRecommendation> recs,
    Set<String> recentFoodNames,
  ) {
    final seen = <String>{}; // AI 返回内部已见归一化菜名
    final result = <AiRecommendation>[];
    for (final rec in recs) {
      final normalized = normalizeDishName(rec.name);
      // AI 内部去重
      if (seen.contains(normalized)) continue;
      // 历史去重
      if (recentFoodNames.contains(normalized)) continue;
      seen.add(normalized);
      result.add(rec);
    }
    return result;
  }

  /// 调 GLM-4-Flash（封装以便测试 mock）
  /// 含 1 次重试（429/5xx/网络抖动指数退避 1s），401/400 等不可恢复错误不重试
  Future<String> _callGlm(String userPrompt) async {
    try {
      return await _provider.createChatCompletion(
        systemPrompt: AiRecommendationPrompt.systemPrompt,
        userPrompt: userPrompt,
        temperature: 0.85, // M19：略提随机性增加多样性（0.8→0.85，保守避免破坏 JSON 格式）
      );
    } catch (e) {
      final s = e.toString();
      // 不可恢复错误（401 key 失效 / 400 参数错误）不重试，快速失败
      if (s.contains('401') ||
          s.contains('Unauthorized') ||
          s.contains('400') ||
          s.contains('Bad Request')) {
        rethrow;
      }
      // 可恢复错误（429 限流 / 5xx 服务器错误 / 网络抖动）退避 1s 后重试 1 次
      debugPrint('AI 调用失败，1s 后重试：$e');
      await Future.delayed(const Duration(seconds: 1));
      return _provider.createChatCompletion(
        systemPrompt: AiRecommendationPrompt.systemPrompt,
        userPrompt: userPrompt,
        temperature: 0.85,
      );
    }
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
