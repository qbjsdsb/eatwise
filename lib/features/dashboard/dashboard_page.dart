import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/util/refresh_bus.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../nutrition/recommendation_service.dart';
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

  @override
  void initState() {
    super.initState();
    _future = _loadData();
    _recFuture = _loadRecommendations();
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
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    // 推荐算法 v3：传 profile（偏好/健康过滤）+ mealType（时段感知）+ 昨日（多样性）
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayDate =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    final profile = await profileRepo.get();
    final mealType = _currentMealType(now.hour);
    final remaining = await service.getDailyRemaining(today);
    return service.recommend(
      remaining: remaining,
      limit: 5,
      todayDate: today,
      profile: profile,
      mealType: mealType,
      yesterdayDate: yesterdayDate,
    );
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
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
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
        foodNames.putIfAbsent(id, () => '食物 #$id');
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 16),
                    const Text('数据加载失败'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
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
      child: Card(
        color: cs.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(24),
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
    return FutureBuilder<List<RecommendedFood>>(
      future: _recFuture,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final recs = snap.data!;
        final remain = d.target - d.cal;
        final proteinRemain = d.proteinGoal - d.protein;
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
                    for (final rec in recs) ...[
                      Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
                      ListTile(
                        leading: const LeadingIconContainer(
                            Icons.restaurant_rounded),
                        title: Text(rec.food.name),
                        subtitle: Text(
                            '${rec.food.caloriesPer100g.toStringAsFixed(0)} kcal/100g · 蛋白 ${rec.food.proteinPer100g.toStringAsFixed(1)}g',
                            style: textTheme.labelSmall),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _pushAndRefresh(
                            ManualEntryPage(initialName: rec.food.name)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _mealsSection(DashboardData d) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (d.meals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.restaurant_menu, size: 48,
                  color: cs.onSurfaceVariant),
              const SizedBox(height: 16),
              Text('今日还没有记录',
                  style: textTheme.titleMedium?.copyWith(color: cs.onSurface)),
              const SizedBox(height: 8),
              Text('点下方拍照按钮开始记录',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.push('/recognize'),
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('去拍照'),
              ),
            ],
          ),
        ),
      );
    }
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
