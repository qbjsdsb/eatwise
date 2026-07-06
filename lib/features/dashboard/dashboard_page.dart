import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai/glm_flash_provider.dart';
import '../../core/config/app_config.dart';
import '../../core/util/date_format.dart';
import '../../core/util/food_name.dart';
import '../../core/util/refresh_bus.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../nutrition/ai_recommendation_prompt.dart';
import '../../nutrition/ai_recommendation_service.dart';
import '../../nutrition/recommendation_service.dart';
import '../../nutrition/user_preference_learner.dart';
import '../recognize/providers.dart' as recognize;
import 'dashboard/dashboard_data.dart';
import 'dashboard/recommendation_section.dart';
import 'dashboard/status_card_section.dart';
import 'dashboard/today_meals_section.dart';

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
    final foodRepo = await ref.read(recognize.foodItemRepoProvider.future);
    final mealRepo = await ref.read(recognize.mealLogRepoProvider.future);
    final profileRepo = await ref.read(recognize.profileRepoProvider.future);
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
      // forceRefresh（用户点重试）时用 ref.refresh 强制刷新网络状态，
      // 避免 connectivity 冷启动误报 false 后 ref.read 拿到缓存 false 导致重试也失败
      // （Bug 2 修复：networkAvailableProvider 已改 autoDispose，但 forceRefresh 场景
      // 仍需 refresh 确保拿到最新网络状态而非本次 session 内的旧缓存）
      final online = forceRefresh
          ? await ref.refresh(recognize.networkAvailableProvider.future)
          : await ref.read(recognize.networkAvailableProvider.future);
      if (!online) {
        return const AiRecommendationResult(
            recommendations: [],
            fromCache: false,
            error: '当前无网络，已切换本地推荐');
      }
      final baseUrl = c.glmBaseUrl.isEmpty
          ? 'https://open.bigmodel.cn/api/paas/v4'
          : c.glmBaseUrl;
      final provider = GlmFlashProvider(apiKey: c.glmApiKey, baseUrl: baseUrl);
      final service = AiRecommendationService(
        provider,
        await ref.read(recognize.profileRepoProvider.future),
        await ref.read(recognize.mealLogRepoProvider.future),
        await ref.read(recognize.foodItemRepoProvider.future),
        await ref.read(
            recognize.recommendationFeedbackRepoProvider.future),
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
  /// 返回 true=成功，false=失败（AiRecItem 据此重置 UI 状态）
  Future<bool> _rateRecommendation(
      AiRecommendation rec, int rating, String mealType) async {
    try {
      final repo = await ref.read(
          recognize.recommendationFeedbackRepoProvider.future);
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
    final mealRepo = await ref.read(recognize.mealLogRepoProvider.future);
    final profileRepo = await ref.read(recognize.profileRepoProvider.future);
    final foodRepo = await ref.read(recognize.foodItemRepoProvider.future);
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
          final mealType = _currentMealType(DateTime.now().hour);
          return CustomScrollView(
            slivers: [
              SliverAppBar.large(title: const Text('今日')),
              SliverToBoxAdapter(child: StatusCardSection(data: d)),
              SliverToBoxAdapter(
                child: RecommendationSection(
                  data: d,
                  aiRecFuture: _aiRecFuture,
                  recFuture: _recFuture,
                  aiRegenerating: _aiRegenerating,
                  mealType: mealType,
                  onRegenerate: _regenerateAiRecommendations,
                  onRateRecommendation: _rateRecommendation,
                  onPushAndRefresh: _pushAndRefresh,
                ),
              ),
              SliverToBoxAdapter(
                child: TodayMealsSection(
                  data: d,
                  onGoToRecognize: () => context.push('/recognize'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
