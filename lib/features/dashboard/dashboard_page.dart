import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai/glm_flash_provider.dart';
import '../../core/config/app_config.dart';
import '../../core/util/date_format.dart';
import '../../core/util/food_name.dart';
import '../../core/util/refresh_bus.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/recommendation_feedback_repository.dart';
import '../../nutrition/ai_recommendation_prompt.dart';
import '../../nutrition/ai_recommendation_service.dart';
import '../../nutrition/recommendation_service.dart';
import '../../nutrition/user_preference_learner.dart';
import '../manual_entry/manual_entry_page.dart';
import '../recognize/providers.dart' as recognize;

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  Future<DashboardData>? _future;
  Future<List<RecommendedFood>>? _recFuture;
  // v5 AI 推荐：独立 Future，渐进增强（v4 秒出，AI 返回后替换）
  Future<AiRecommendationResult>? _aiRecFuture;
  // 用户是否点过"重新生成"（控制按钮 disabled 状态 + 提示文案）
  bool _aiRegenerating = false;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
    _recFuture = _loadRecommendations();
    _aiRecFuture = _loadAiRecommendations();
    // 监听刷新总线：拍照记录返回后刷新首页数据
    RefreshBus.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    RefreshBus.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = _loadData();
      _recFuture = _loadRecommendations();
      // AI 推荐不随 RefreshBus 刷新（避免记录一条就重新调 AI），
      // 当日缓存有效，用户主动点"重新生成"才强制刷新
    });
  }

  Future<void> _pushAndRefresh(Widget page) async {
    await Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => page));
    _refresh();
  }

  Future<List<RecommendedFood>> _loadRecommendations() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final foodRepo = FoodItemRepository(db);
    final mealRepo = MealLogRepository(db);
    final profileRepo = ProfileRepository(db);
    final service = RecommendationService(foodRepo, mealRepo, profileRepo);
    final now = DateTime.now();
    final today = todayYmd();
    // 推荐算法 v4：v3 基础上新增用户偏好学习（口味/风格/材质/价格档）
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayDate = formatYmd(yesterday);
    final profile = await profileRepo.get();
    final mealType = _currentMealType(now.hour);
    final remaining = await service.getDailyRemaining(today);
    // v4：并行学习用户偏好（30 天 meal_log + food_item name 标签化）
    // 用 listAllForRecommendation 拿到食物建 map，避免逐条 findById IO
    final recentMealsFuture = mealRepo.getRecentMeals(days: 30);
    final foodsFuture = foodRepo.listAllForRecommendation();
    final recentMeals = await recentMealsFuture;
    final foods = await foodsFuture;
    final foodMap = {for (final f in foods) f.id: f};
    final userPref = UserPreferenceLearner.learn(recentMeals, foodMap);
    return service.recommend(
      remaining: remaining,
      limit: 5,
      todayDate: today,
      profile: profile,
      mealType: mealType,
      yesterdayDate: yesterdayDate,
      userPref: userPref,
    );
  }

  /// v5 AI 推荐：渐进增强，失败静默返回空列表（v4 兜底）
  /// 任何异常（config/网络/AI）都包内兜底返回带 error 的 result，不向上抛
  Future<AiRecommendationResult> _loadAiRecommendations(
      {bool forceRefresh = false}) async {
    try {
      // await config future 避免冷启动竞态（config 异步从 SecureConfigStore 加载）
      final c = await ref.read(appConfigProvider.future);
      // GLM key 未配置 → 静默返回空（v4 兜底，不报错，不显示重试按钮）
      if (c.glmApiKey.isEmpty) {
        return const AiRecommendationResult(
            recommendations: [], fromCache: false);
      }
      // 离线守卫：无网络不调 AI
      final online = await ref.read(recognize.networkAvailableProvider.future);
      if (!online) {
        return const AiRecommendationResult(
            recommendations: [],
            fromCache: false,
            error: '当前无网络，已切换本地推荐');
      }
      final db = await ref.read(recognize.databaseProvider.future);
      final baseUrl = c.glmBaseUrl.isEmpty
          ? 'https://open.bigmodel.cn/api/paas/v4'
          : c.glmBaseUrl;
      final provider = GlmFlashProvider(apiKey: c.glmApiKey, baseUrl: baseUrl);
      final service = AiRecommendationService(
        provider,
        ProfileRepository(db),
        MealLogRepository(db),
        FoodItemRepository(db),
        RecommendationFeedbackRepository(db),
      );
      try {
        final now = DateTime.now();
        return await service.recommend(
          AiRecommendationRequest(
            todayDate: todayYmd(),
            mealType: _currentMealType(now.hour),
          ),
          forceRefresh: forceRefresh,
        );
      } finally {
        // 用完即关，避免 OpenAIClient 连接泄漏（每次进看板都新建 provider）
        provider.close();
      }
    } catch (e) {
      // config/网络/DB 异常兜底（不向上抛，避免 FutureBuilder hasError）
      debugPrint('AI 推荐加载异常（v4 兜底）：$e');
      return const AiRecommendationResult(
        recommendations: [],
        fromCache: false,
        error: 'AI 推荐加载失败，已切换本地推荐',
      );
    }
  }

  /// 用户点"重新生成"按钮：强制刷新 AI 推荐
  /// 失败时显示 toast + 保留按钮（让用户可重试）
  Future<void> _regenerateAiRecommendations() async {
    if (_aiRegenerating) return; // 防重入
    setState(() => _aiRegenerating = true);
    try {
      final result = await _loadAiRecommendations(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        // 用新 Future 承载结果，触发 FutureBuilder 重建
        _aiRecFuture = Future.value(result);
      });
      // 失败时 toast 提示（成功时不打扰）
      if (result.hasError && mounted) {
        showAppToast(context, result.error!);
      }
    } catch (e) {
      // _loadAiRecommendations 内部已 try-catch，理论不会冒泡；防御性兜底
      if (mounted) showAppToast(context, '重新生成失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _aiRegenerating = false);
    }
  }

  /// 用户对某条 AI 推荐打分（1=不喜欢 / 2=一般 / 3=喜欢）
  /// 写库后不重新调 AI（避免频繁调 API），下次推荐时反馈会被注入 prompt
  /// 返回 true=成功，false=失败（_AiRecItem 据此重置 UI 状态）
  Future<bool> _rateRecommendation(
      AiRecommendation rec, int rating, String mealType) async {
    try {
      final db = await ref.read(recognize.databaseProvider.future);
      final repo = RecommendationFeedbackRepository(db);
      await repo.insertFeedback(
        foodName: rec.name,
        rating: rating,
        mealType: mealType,
        recommendDate: todayYmd(),
      );
      if (!mounted) return true;
      final label =
          rating == 3 ? '已记录喜欢' : rating == 2 ? '已记录一般' : '已记录不喜欢';
      showAppToast(context, label);
      return true;
    } catch (e) {
      debugPrint('反馈写入失败：$e');
      if (!mounted) return false;
      showAppToast(context, '反馈失败，请重试');
      return false;
    }
  }

  /// 按当前小时推断餐次（推荐算法 v3 时段感知用）。
  /// 5-10 早餐 / 11-13 午餐 / 14-16 加餐 / 17-21 晚餐 / 其他 加餐。
  static String _currentMealType(int hour) {
    if (hour >= 5 && hour <= 10) return 'breakfast';
    if (hour >= 11 && hour <= 13) return 'lunch';
    if (hour >= 17 && hour <= 21) return 'dinner';
    return 'snack'; // 14-16 加餐 + 22-4 深夜
  }

  Future<DashboardData> _loadData() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final mealRepo = MealLogRepository(db);
    final profileRepo = ProfileRepository(db);
    final foodRepo = FoodItemRepository(db);
    final today = todayYmd();
    // 三查询无依赖，并行执行（原串行 await 总时间 = sum，并行后 = max）
    // 用"同时启动 + 分别 await"模式，类型安全且并行（Future.wait 因三类型不同会退化为 Object）
    final macrosFuture = mealRepo.getMacrosByDate(today);
    final profileFuture = profileRepo.get();
    final mealsFuture = mealRepo.getMealsByDate(today);
    final macros = await macrosFuture;
    final profile = await profileFuture;
    final meals = await mealsFuture;
    // 食物名批量查询（原 N+1 逐条 getById → 1 次 IN 查询）
    final foodNames = <int, String>{};
    final uniqueIds = meals.map((m) => m.foodItemId).toSet().toList();
    if (uniqueIds.isNotEmpty) {
      final foods = await foodRepo.getByIds(uniqueIds);
      for (final food in foods) {
        foodNames[food.id] = food.name;
      }
      // 兜底：未命中的 id（理论不会，外键约束保证存在）显示占位名
      for (final id in uniqueIds) {
        foodNames.putIfAbsent(id, () => placeholderFoodName(id));
      }
    }
    final proteinGoal = profile.proteinGPerKg * profile.weightKg;
    final fatGoal = profile.fatGPerKg * profile.weightKg;
    final carbGoalRaw = profile.carbGPerKg != null
        ? profile.carbGPerKg! * profile.weightKg
        : (profile.dailyCalorieTarget - proteinGoal * 4 - fatGoal * 9) / 4;
    final carbGoal = carbGoalRaw < 0 ? 0.0 : carbGoalRaw;
    return DashboardData(
      cal: macros.calories,
      protein: macros.protein,
      fat: macros.fat,
      carbs: macros.carbs,
      target: profile.dailyCalorieTarget,
      proteinGoal: proteinGoal,
      fatGoal: fatGoal,
      carbGoal: carbGoal,
      weightKg: profile.weightKg,
      meals: meals,
      foodNames: foodNames,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<DashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(onRetry: _refresh);
          }
          if (!snapshot.hasData) {
            return const LoadingState();
          }
          final d = snapshot.data!;
          return CustomScrollView(
            slivers: [
              SliverAppBar.large(title: const Text('今日')),
              SliverToBoxAdapter(child: _statusCard(d)),
              SliverToBoxAdapter(child: _recommendationSection(d)),
              SliverToBoxAdapter(child: _mealsSection(d)),
            ],
          );
        },
      ),
    );
  }

  Widget _statusCard(DashboardData d) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final remain = d.target - d.cal;
    final overflow = remain < 0;
    final pct = d.target > 0 ? (d.cal / d.target).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: HeroCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department_rounded,
                    color: cs.onPrimaryContainer, size: 20),
                const SizedBox(width: 8),
                Text('今日还可摄入',
                    style: textTheme.labelLarge?.copyWith(
                        color: cs.onPrimaryContainer)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              overflow ? (-remain).toStringAsFixed(0) : remain.toStringAsFixed(0),
              style: textTheme.displaySmall?.copyWith(
                color: overflow ? cs.error : cs.onPrimaryContainer,
                fontWeight: FontWeight.w400,
                height: 1.1,
              ),
            ),
            Text('kcal · 已摄入 ${d.cal.toStringAsFixed(0)} / ${d.target}',
                style: textTheme.bodySmall
                    ?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: cs.onPrimaryContainer.withValues(alpha: 0.12),
                color: overflow ? cs.error : cs.onPrimaryContainer,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 16),
            // 三宏用 MD3 三角色（tertiary/secondary/primary），跟随 seed 变化且色弱友好。
            // primaryContainer 深底上用 onTertiaryContainer/onSecondaryContainer/onPrimaryContainer
            // 保证对比度（容器色配对色），与 today_meals 跨页统一。
            _miniMacro('蛋白', d.protein, d.proteinGoal,
                MacroColors.protein(cs), cs.onTertiaryContainer),
            _miniMacro('脂肪', d.fat, d.fatGoal,
                MacroColors.fat(cs), cs.onSecondaryContainer),
            _miniMacro('碳水', d.carbs, d.carbGoal,
                MacroColors.carb(cs), cs.onPrimaryContainer),
          ],
        ),
      ),
    );
  }

  Widget _miniMacro(String label, double value, double goal, Color barColor, Color labelColor) {
    final textTheme = Theme.of(context).textTheme;
    final pct = goal > 0 ? (value / goal).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
              width: 40,
              child: Text(label,
                  style: textTheme.bodySmall?.copyWith(color: labelColor))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: barColor.withValues(alpha: 0.12),
                color: barColor,
                minHeight: 6,
              ),
            ),
          ),
          SizedBox(
              width: 80,
              child: Text(
                  '${value.toStringAsFixed(0)}/${goal.toStringAsFixed(0)}g',
                  textAlign: TextAlign.right,
                  style: textTheme.labelSmall?.copyWith(color: labelColor))),
        ],
      ),
    );
  }

  Widget _recommendationSection(DashboardData d) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final remain = d.target - d.cal;
    final proteinRemain = d.proteinGoal - d.protein;
    final mealType = _currentMealType(DateTime.now().hour);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle('智能推荐'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            proteinRemain > 5
                                ? '今日还差 ${proteinRemain.toStringAsFixed(0)}g 蛋白质'
                                : remain > 0
                                    ? '今日还可摄入 ${remain.toStringAsFixed(0)} kcal'
                                    : '今日热量已达标，推荐低卡食物',
                            style: textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                      // 重新生成按钮：AI 推荐成功或曾失败时都显示（失败时文案改"重试"）
                      FutureBuilder<AiRecommendationResult>(
                        future: _aiRecFuture,
                        builder: (context, aiSnap) {
                          // 加载中或未配置（无 error 且无数据）时不显示
                          if (aiSnap.connectionState !=
                              ConnectionState.done) {
                            return const SizedBox.shrink();
                          }
                          // key 未配置：无数据无 error，不显示按钮
                          if (!aiSnap.hasData) {
                            return const SizedBox.shrink();
                          }
                          final data = aiSnap.data!;
                          // key 未配置的静默回退（无 error）：不显示
                          if (data.recommendations.isEmpty &&
                              data.error == null) {
                            return const SizedBox.shrink();
                          }
                          // 成功或失败（带 error）都显示按钮，失败时文案改"重试"
                          return _regenerateButton(cs,
                              isRetry: data.hasError);
                        },
                      ),
                    ],
                  ),
                ),
                // AI 推荐区（渐进增强：AI loading 时先显示 v4 + 加载提示，
                // AI 返回后替换为 AI 推荐；AI 失败/空时保持 v4 + 错误提示）
                FutureBuilder<AiRecommendationResult>(
                  future: _aiRecFuture,
                  builder: (context, aiSnap) {
                    // AI loading 中：先显示 v4 本地推荐（秒出）+ 顶部加载提示
                    // 这是真正的渐进增强——用户不空等，v4 立即可点
                    if (aiSnap.connectionState != ConnectionState.done) {
                      return Column(
                        children: [
                          _aiLoadingHint(cs),
                          _v4Recommendations(d, textTheme, cs),
                        ],
                      );
                    }
                    // AI 失败/空：回退 v4 本地推荐
                    if (aiSnap.hasError ||
                        !aiSnap.hasData ||
                        aiSnap.data!.recommendations.isEmpty) {
                      final err = aiSnap.hasData
                          ? aiSnap.data!.error
                          : (aiSnap.hasError ? 'AI 推荐失败' : null);
                      return Column(
                        children: [
                          if (err != null) _aiErrorHint(cs, err),
                          _v4Recommendations(d, textTheme, cs),
                        ],
                      );
                    }
                    // AI 成功：显示 AI 推荐 + 满意度反馈
                    final aiRecs = aiSnap.data!.recommendations;
                    return _aiRecommendations(
                        aiRecs, textTheme, cs, mealType);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 重新生成按钮（isRetry=true 时文案改"重试"）
  Widget _regenerateButton(ColorScheme cs, {bool isRetry = false}) {
    return TextButton.icon(
      onPressed: _aiRegenerating ? null : _regenerateAiRecommendations,
      icon: _aiRegenerating
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            )
          : const Icon(Icons.refresh_rounded, size: 18),
      label: Text(_aiRegenerating
          ? '生成中'
          : isRetry
              ? '重试'
              : '换一批'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// AI loading 提示（渐进增强：v4 已秒出，AI 在后台生成）
  ///
  /// 用线性进度条 + 文案提示用户 AI 正在生成更精准推荐，
  /// 不用骨架屏（避免与下方 v4 推荐重复占位），保持视觉简洁。
  Widget _aiLoadingHint(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: cs.primary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'AI 正在生成个性化推荐…',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// AI 失败提示（小尺寸 errorContainer 行，告诉用户已切本地推荐）
  Widget _aiErrorHint(ColorScheme cs, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: cs.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// AI 推荐列表（含满意度反馈，点开才显示）
  Widget _aiRecommendations(List<AiRecommendation> recs, TextTheme tt,
      ColorScheme cs, String mealType) {
    return Column(
      children: [
        for (final rec in recs) ...[
          Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
          // ValueKey(rec.name)：换一批后 rec.name 变化 → 强制新建 State，
          // 避免旧 _ratedRating 状态泄漏到新推荐
          _AiRecItem(
            key: ValueKey(rec.name),
            rec: rec,
            mealType: mealType,
            onTap: () => _pushAndRefresh(ManualEntryPage(initialName: rec.name)),
            onRate: (rating) => _rateRecommendation(rec, rating, mealType),
          ),
        ],
      ],
    );
  }

  /// v4 本地推荐列表（AI 失败/loading 时兜底）
  Widget _v4Recommendations(
      DashboardData d, TextTheme tt, ColorScheme cs) {
    return FutureBuilder<List<RecommendedFood>>(
      future: _recFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('v4 推荐加载失败：${snap.error}');
          return const SizedBox.shrink();
        }
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final recs = snap.data!;
        return Column(
          children: [
            for (final rec in recs) ...[
              Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
              ListTile(
                leading: const LeadingIconContainer(Icons.restaurant_rounded),
                title: Text(rec.food.name),
                subtitle: Text(
                    '${rec.food.caloriesPer100g.toStringAsFixed(0)} kcal/100g · 蛋白 ${rec.food.proteinPer100g.toStringAsFixed(1)}g',
                    style: tt.labelSmall),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pushAndRefresh(
                    ManualEntryPage(initialName: rec.food.name)),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _mealsSection(DashboardData d) {
    if (d.meals.isEmpty) {
      return EmptyState(
        icon: Icons.restaurant_menu,
        title: '今日还没有记录',
        subtitle: '点下方拍照按钮开始记录',
        actionLabel: '去拍照',
        onAction: () => context.push('/recognize'),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final groups = <String, List<MealLog>>{};
    for (final m in d.meals) {
      groups.putIfAbsent(m.mealType, () => []).add(m);
    }
    final mealOrder = ['breakfast', 'lunch', 'dinner', 'snack'];
    // 先算出最后一个有记录的餐次
    final presentMealTypes =
        mealOrder.where((mt) => groups[mt] != null).toList();
    final lastPresentMt =
        presentMealTypes.isEmpty ? null : presentMealTypes.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle('今日餐次'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Column(
              children: [
                for (final mt in mealOrder)
                  if (groups[mt] != null)
                    for (final m in groups[mt]!) ...[
                      ListTile(
                        leading: LeadingIconContainer(_mealIcon(mt),
                            containerColor: cs.tertiaryContainer,
                            iconColor: cs.onTertiaryContainer),
                        title: Text(d.foodNames[m.foodItemId] ?? '食物'),
                        subtitle: Text(
                            '${_mealLabel(mt)} · ${_formatTime(m.loggedAt)}',
                            style: textTheme.labelSmall),
                        trailing: Text('${m.actualCalories.toStringAsFixed(0)} kcal',
                            style: textTheme.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                      // 只在非"最后一条记录"时显示分割线
                      if (!(m == groups[mt]!.last && mt == lastPresentMt))
                        Divider(
                            height: 1,
                            indent: 56,
                            endIndent: 16,
                            color: cs.outlineVariant),
                    ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  IconData _mealIcon(String mt) => {
        'breakfast': Icons.free_breakfast_rounded,
        'lunch': Icons.lunch_dining_rounded,
        'dinner': Icons.dinner_dining_rounded,
        'snack': Icons.cookie_rounded,
      }[mt] ??
      Icons.restaurant_rounded;

  String _mealLabel(String mt) => {
        'breakfast': '早餐',
        'lunch': '午餐',
        'dinner': '晚餐',
        'snack': '加餐',
      }[mt] ??
      '加餐';

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class DashboardData {
  final double cal;
  final double protein;
  final double fat;
  final double carbs;
  final int target;
  final double proteinGoal;
  final double fatGoal;
  final double carbGoal;
  final double weightKg;
  final List<MealLog> meals;
  final Map<int, String> foodNames;

  DashboardData({
    required this.cal,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.target,
    required this.proteinGoal,
    required this.fatGoal,
    required this.carbGoal,
    required this.weightKg,
    required this.meals,
    required this.foodNames,
  });
}

/// AI 推荐单项组件（StatefulWidget 维护"已反馈"状态）
///
/// 反馈按钮设计为点开才显示（PopupMenuButton 三点菜单），
/// 避免每条推荐占用过多垂直空间。反馈后图标变为已反馈状态。
class _AiRecItem extends StatefulWidget {
  final AiRecommendation rec;
  final String mealType;
  final VoidCallback onTap;
  // rating: 1=不喜欢 / 2=一般 / 3=喜欢。返回 true=成功，false=失败
  final Future<bool> Function(int rating) onRate;

  const _AiRecItem({
    super.key,
    required this.rec,
    required this.mealType,
    required this.onTap,
    required this.onRate,
  });

  @override
  State<_AiRecItem> createState() => _AiRecItemState();
}

class _AiRecItemState extends State<_AiRecItem> {
  // 已反馈的 rating（null=未反馈）。反馈后立即更新 UI，避免重复点。
  int? _ratedRating;
  bool _rating = false; // 防重入

  // 反馈选项配置
  static const _feedbackOptions = <_FeedbackOption>[
    _FeedbackOption(rating: 3, label: '喜欢', icon: Icons.thumb_up_outlined),
    _FeedbackOption(rating: 2, label: '一般', icon: Icons.thumbs_up_down_outlined),
    _FeedbackOption(rating: 1, label: '不喜欢', icon: Icons.thumb_down_outlined),
  ];

  Future<void> _handleRate(int rating) async {
    if (_rating || _ratedRating != null) return; // 防重入 + 已反馈不重复
    setState(() {
      _rating = true;
      _ratedRating = rating; // 乐观更新
    });
    try {
      final ok = await widget.onRate(rating);
      if (!mounted) return;
      if (!ok) {
        // 失败：重置 UI 状态，允许重试
        setState(() => _ratedRating = null);
      }
    } catch (_) {
      // onRate 内部已 try/catch，理论上不会冒泡；防御性兜底
      if (mounted) setState(() => _ratedRating = null);
    } finally {
      if (mounted) setState(() => _rating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rec = widget.rec;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const LeadingIconContainer(Icons.auto_awesome_rounded),
          Expanded(
            child: InkWell(
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(rec.name,
                              style: tt.titleSmall,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(rec.reason,
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${rec.estimatedCalories.toStringAsFixed(0)} kcal · 蛋白 ${rec.estimatedProtein.toStringAsFixed(0)}g',
                          style: tt.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        // 已反馈时显示标签
                        if (_ratedRating != null) ...[
                          const SizedBox(width: 8),
                          _ratedChip(cs),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 三点菜单：点开才显示反馈选项
          PopupMenuButton<int>(
            icon: _rating
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : Icon(
                    _ratedRating != null
                        ? Icons.check_circle_outline
                        : Icons.more_vert,
                    size: 20,
                    color: _ratedRating != null
                        ? cs.primary
                        : cs.onSurfaceVariant,
                  ),
            tooltip: _rating
                ? '提交中'
                : _ratedRating != null
                    ? '已反馈'
                    : '反馈满意度',
            enabled: !_rating && _ratedRating == null,
            onSelected: (rating) => _handleRate(rating),
            itemBuilder: (context) => [
              for (final opt in _feedbackOptions)
                PopupMenuItem<int>(
                  value: opt.rating,
                  child: Row(
                    children: [
                      Icon(opt.icon, size: 18, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(opt.label),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 已反馈标签（小尺寸 chip）
  Widget _ratedChip(ColorScheme cs) {
    final label = _ratedRating == 3
        ? '已喜欢'
        : _ratedRating == 2
            ? '已评一般'
            : '已不喜欢';
    final color = _ratedRating == 3
        ? cs.primary
        : _ratedRating == 1
            ? cs.error
            : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}

/// 反馈选项配置（内部用）
class _FeedbackOption {
  final int rating;
  final String label;
  final IconData icon;

  const _FeedbackOption({
    required this.rating,
    required this.label,
    required this.icon,
  });
}
