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
  Future<AiRecommendationResult> _loadAiRecommendations(
      {bool forceRefresh = false}) async {
    final config = ref.read(appConfigProvider);
    return config.maybeWhen(
      data: (c) async {
        // GLM key 未配置 → 静默返回空（v4 兜底，不报错）
        if (c.glmApiKey.isEmpty) {
          return const AiRecommendationResult(
              recommendations: [], fromCache: false);
        }
        // 离线守卫：无网络不调 AI
        final online =
            await ref.read(recognize.networkAvailableProvider.future);
        if (!online) {
          return const AiRecommendationResult(
              recommendations: [], fromCache: false);
        }
        final db = await ref.read(recognize.databaseProvider.future);
        final baseUrl = c.glmBaseUrl.isEmpty
            ? 'https://open.bigmodel.cn/api/paas/v4'
            : c.glmBaseUrl;
        final service = AiRecommendationService(
          GlmFlashProvider(apiKey: c.glmApiKey, baseUrl: baseUrl),
          ProfileRepository(db),
          MealLogRepository(db),
          FoodItemRepository(db),
          RecommendationFeedbackRepository(db),
        );
        final now = DateTime.now();
        return service.recommend(
          AiRecommendationRequest(
            todayDate: todayYmd(),
            mealType: _currentMealType(now.hour),
          ),
          forceRefresh: forceRefresh,
        );
      },
      orElse: () => const AiRecommendationResult(
          recommendations: [], fromCache: false),
    );
  }

  /// 用户点"重新生成"按钮：强制刷新 AI 推荐
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
    } finally {
      if (mounted) setState(() => _aiRegenerating = false);
    }
  }

  /// 用户对某条 AI 推荐打分（1=不喜欢 / 2=一般 / 3=喜欢）
  /// 写库后不重新调 AI（避免频繁调 API），下次推荐时反馈会被注入 prompt
  Future<void> _rateRecommendation(
      AiRecommendation rec, int rating, String mealType) async {
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = RecommendationFeedbackRepository(db);
    await repo.insertFeedback(
      foodName: rec.name,
      rating: rating,
      mealType: mealType,
      recommendDate: todayYmd(),
    );
    if (!mounted) return;
    final label = rating == 3 ? '已记录喜欢' : rating == 2 ? '已记录一般' : '已记录不喜欢';
    showAppToast(context, label);
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
                      // 重新生成按钮：仅 AI 推荐可用时显示
                      FutureBuilder<AiRecommendationResult>(
                        future: _aiRecFuture,
                        builder: (context, aiSnap) {
                          // AI 还在加载或无结果时不显示按钮
                          if (!aiSnap.hasData ||
                              aiSnap.data!.recommendations.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return _regenerateButton(cs);
                        },
                      ),
                    ],
                  ),
                ),
                // AI 推荐区（渐进增强：AI 有结果时显示，loading/失败时回退 v4）
                FutureBuilder<AiRecommendationResult>(
                  future: _aiRecFuture,
                  builder: (context, aiSnap) {
                    // AI loading 中：显示骨架，同时 v4 不显示（避免重复）
                    if (aiSnap.connectionState != ConnectionState.done) {
                      return _aiLoadingSkeleton(textTheme, cs);
                    }
                    // AI 失败/空：回退 v4 本地推荐
                    if (aiSnap.hasError ||
                        !aiSnap.hasData ||
                        aiSnap.data!.recommendations.isEmpty) {
                      return _v4Recommendations(d, textTheme, cs);
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

  /// 重新生成按钮
  Widget _regenerateButton(ColorScheme cs) {
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
      label: Text(_aiRegenerating ? '生成中' : '换一批'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// AI loading 骨架（避免空白闪烁）
  Widget _aiLoadingSkeleton(TextTheme tt, ColorScheme cs) {
    return Column(
      children: List.generate(
        3,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 14,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 180,
                      height: 10,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// AI 推荐列表（含满意度反馈）
  Widget _aiRecommendations(List<AiRecommendation> recs, TextTheme tt,
      ColorScheme cs, String mealType) {
    return Column(
      children: [
        for (final rec in recs) ...[
          Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                const LeadingIconContainer(Icons.auto_awesome_rounded),
                Expanded(
                  child: _aiRecContent(rec, tt, cs, mealType),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// AI 推荐单项内容（标题 + 理由 + 营养 + 反馈按钮）
  Widget _aiRecContent(
      AiRecommendation rec, TextTheme tt, ColorScheme cs, String mealType) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _pushAndRefresh(ManualEntryPage(initialName: rec.name)),
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
                Text(
                  '${rec.estimatedCalories.toStringAsFixed(0)} kcal · 蛋白 ${rec.estimatedProtein.toStringAsFixed(0)}g',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        // 满意度反馈按钮行
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8, bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _feedbackButton(
                icon: Icons.thumb_down_outlined,
                label: '不喜欢',
                color: cs.error,
                onTap: () => _rateRecommendation(rec, 1, mealType),
              ),
              const SizedBox(width: 4),
              _feedbackButton(
                icon: Icons.thumbs_up_down_outlined,
                label: '一般',
                color: cs.onSurfaceVariant,
                onTap: () => _rateRecommendation(rec, 2, mealType),
              ),
              const SizedBox(width: 4),
              _feedbackButton(
                icon: Icons.thumb_up_outlined,
                label: '喜欢',
                color: cs.primary,
                onTap: () => _rateRecommendation(rec, 3, mealType),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 反馈按钮（小尺寸 icon + 文字）
  Widget _feedbackButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
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
