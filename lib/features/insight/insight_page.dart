import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/glm_flash_provider.dart';
import '../../core/util/date_format.dart';
import '../../core/util/refresh_bus.dart';
import '../../core/widgets/m3_widgets.dart';
import '../recognize/providers.dart' as recognize;

/// AI 周报页：周/月视图切换 + GLM-4-Flash 生成中文建议（去重 + 可编辑）
class InsightPage extends ConsumerStatefulWidget {
  const InsightPage({super.key});
  @override
  ConsumerState<InsightPage> createState() => _InsightPageState();
}

class _InsightPageState extends ConsumerState<InsightPage> {
  String? _summary;
  // 错误信息独立字段：与 _summary 严格区分，避免错误文案伪装成 AI 汇总误导用户
  // （原实现把错误塞进 _summary，与 AI 输出在同一 Card 渲染，用户误以为是 AI 输出）
  String? _error;
  bool _loading = false;
  String _periodType = 'weekly'; // 'weekly' | 'monthly'
  late String _periodStart;
  late String _periodEnd;
  // 当前周期聚合数据（供 fl_chart 折线图渲染）
  List<double> _dailyCal = []; // 每日热量（_periodStart ~ _periodEnd）
  List<double> _dailyWeight = []; // 每日体重（按 weight_log 记录顺序）
  int _targetCal = 2000; // 目标热量（读自 profile.dailyCalorieTarget）
  // v1.11：覆盖率（供 UI 提示数据完整度 + 生成守卫）
  int _recordedDays = 0; // 有 meal_log 记录的天数
  int _totalDays = 7; // 窗口总天数（周 7 / 月 30）
  // M2 修复：SegmentedButton 快速切换时，旧 _loadExisting 的 setState 被版本号守卫丢弃
  // 根因：_loadExisting 是 async，切换时旧调用未完成，完成后 setState 旧结果覆盖新状态
  int _loadVersion = 0;
  // M24 Task A6：图表区 loading 标志，周/月切换 + 初次加载时显示 LoadingState，
  // 配合 AnimatedSwitcher 平滑过渡，避免图表直接消失再出现的突兀感
  // 默认 true：initState 立即调 _loadExisting，初次加载也显示 loading
  bool _chartLoading = true;
  // 问题2：新增 UI 维度 state（原本只喂 AI 不展示，现在图表/卡片也要用）
  List<double> _dailyProtein = [];
  List<double> _dailyFat = [];
  List<double> _dailyCarbs = [];
  double _proteinGoal = 0;
  double _fatGoal = 0;
  double _carbGoal = 0;
  Map<String, double> _mealTypeCalories = {}; // 餐次 -> 总热量（环图用）
  int _streak = 0; // 连续记录天数（到今天为止）
  double _avgExcess = 0; // 平均每天超/缺目标热量（负=缺口正=超额）
  int _goalHitDays = 0; // 在目标 ±10% 内的天数
  double? _weightFirst; // 周期首体重
  double? _weightLast; // 周期末体重
  double? _weightDiff; // 体重变化（last - first，负=减重）
  List<String> _preferenceFoods = []; // 偏好食物 Top5（UI 展示用）
  Map<int, int> _preferenceFoodCounts = {}; // 偏好食物频次（UI 展示用）
  Map<int, double> _preferenceFoodCalories = {}; // 偏好食物热量贡献（UI 展示用）
  // 月报周环比（仅 monthly 填充）：每周起止 + 日均热量
  List<({String weekStart, String weekEnd, double avgCal})> _weeklyBreakdown = [];

  /// _mealTypeCalories 总热量（环图显示守卫用，避免空数据渲染环图）
  double get _mealTypeCaloriesTotal =>
      _mealTypeCalories.values.fold(0.0, (s, v) => s + v);

  @override
  void initState() {
    super.initState();
    _calcPeriod();
    _loadExisting();
    // 监听刷新总线：拍照记录返回后刷新图表与汇总数据
    RefreshBus.instance.addListener(_onRefreshBus);
  }

  @override
  void dispose() {
    RefreshBus.instance.removeListener(_onRefreshBus);
    super.dispose();
  }

  /// 收到刷新通知：重新聚合周期数据 + 加载已有汇总
  void _onRefreshBus() {
    if (!mounted) return;
    _loadExisting();
  }

  /// 根据 _periodType 计算 _periodStart/_periodEnd
  ///
  /// 滚动窗口策略（v1.11）：不再用自然周/月，改用"最近 N 天"。
  /// - weekly：最近 7 天（today-6 ~ today）
  /// - monthly：最近 30 天（today-29 ~ today）
  ///
  /// 优势：
  /// 1. 不足一周/月时仍按完整周期算（用户用 3 天也能生成周报，0 填充缺失日）
  /// 2. 始终覆盖最近数据，比"自然周前 6 天 + 今天 0 条"更准
  /// 3. 跨周/跨月自然过渡，避免月末切换 chart 突变
  ///
  /// 缓存策略：_periodStart/_periodEnd 每天变化，InsightRepository.find 找不到
  /// 昨天的汇总（key 不同），用户每天需重新生成。这是预期行为（滚动窗口本就该每天刷新）。
  void _calcPeriod() {
    final now = DateTime.now();
    if (_periodType == 'weekly') {
      // 最近 7 天：today-6 ~ today（含今天）
      final start = now.subtract(const Duration(days: 6));
      _periodStart = formatYmd(start);
      _periodEnd = formatYmd(now);
    } else {
      // 最近 30 天：today-29 ~ today（含今天）
      final start = now.subtract(const Duration(days: 29));
      _periodStart = formatYmd(start);
      _periodEnd = formatYmd(now);
    }
  }

  /// 聚合当前周期数据（热量/体重/宏量/偏好/覆盖率/餐次分布/streak/超额/体重摘要），供图表与 AI 生成共用。
  ///
  /// v1.11 增强：在原热量+体重基础上，新增三大宏量每日序列 + 目标值、记录覆盖率、
  /// 高频食物画像，让 AI 汇总能结合宏量达成率、饮食偏好、数据完整度给出更智能的建议。
  ///
  /// 问题2 增强：新增餐次热量分布、连续记录 streak、平均超额/缺口、目标达成天数、
  /// 体重首末变化、月报周环比分组，UI 同步展示（不再只喂 AI）。
  Future<({
    List<double> dailyCal,
    List<double> dailyWeight,
    int targetCal,
    String goal,
    List<double> dailyProtein,
    List<double> dailyFat,
    List<double> dailyCarbs,
    double proteinGoal,
    double fatGoal,
    double carbGoal,
    int recordedDays,
    int totalDays,
    double coverageRate,
    List<String> preferenceFoods,
    // 问题2 新增字段
    Map<String, double> mealTypeCalories,
    int streak,
    double avgExcess,
    int goalHitDays,
    double? weightFirst,
    double? weightLast,
    double? weightDiff,
    List<({String weekStart, String weekEnd, double avgCal})> weeklyBreakdown,
    String? specialCondition,
    String? dietPreference,
    String? healthCondition,
  })> _aggregatePeriod() async {
    final mealRepo = await ref.read(recognize.mealLogRepoProvider.future);
    final weightRepo = await ref.read(recognize.weightLogRepoProvider.future);
    final profileRepo = await ref.read(recognize.profileRepoProvider.future);
    final foodRepo = await ref.read(recognize.foodItemRepoProvider.future);

    final meals = await mealRepo.getRange(_periodStart, _periodEnd);
    final weights = await weightRepo.getRange(_periodStart, _periodEnd);
    final profile = await profileRepo.get();

    // 按日聚合热量 + 三大宏量（_periodStart ~ _periodEnd，周 7 天 / 月 28~31 天）
    final start = parseYmd(_periodStart);
    final end = parseYmd(_periodEnd);
    final days = end.difference(start).inDays + 1;
    final dailyCal = <double>[];
    final dailyProtein = <double>[];
    final dailyFat = <double>[];
    final dailyCarbs = <double>[];
    var recordedDays = 0;
    var goalHitDays = 0;
    var totalExcess = 0.0;
    // 餐次热量分布：breakfast/lunch/dinner/snack -> 总热量
    final mealTypeCalories = <String, double>{
      'breakfast': 0,
      'lunch': 0,
      'dinner': 0,
      'snack': 0,
    };
    for (var i = 0; i < days; i++) {
      final date = formatYmd(start.add(Duration(days: i)));
      final dayMeals = meals.where((m) => m.date == date).toList();
      if (dayMeals.isNotEmpty) recordedDays++;
      final dayCal =
          dayMeals.fold<double>(0, (s, m) => s + m.actualCalories);
      dailyCal.add(dayCal);
      dailyProtein.add(
          dayMeals.fold<double>(0, (s, m) => s + m.actualProteinG));
      dailyFat.add(dayMeals.fold<double>(0, (s, m) => s + m.actualFatG));
      dailyCarbs.add(dayMeals.fold<double>(0, (s, m) => s + m.actualCarbsG));
      // 餐次热量累加
      for (final m in dayMeals) {
        mealTypeCalories[m.mealType] =
            (mealTypeCalories[m.mealType] ?? 0) + m.actualCalories;
      }
      // 目标达成天数 + 超额累加（仅有记录的天参与）
      if (dayMeals.isNotEmpty && profile.dailyCalorieTarget > 0) {
        final excess = dayCal - profile.dailyCalorieTarget;
        totalExcess += excess;
        if ((excess.abs() / profile.dailyCalorieTarget) < 0.1) {
          goalHitDays++;
        }
      }
    }
    final dailyWeight = weights.map((w) => w.weightKg).toList();
    final targetCal = profile.dailyCalorieTarget;

    // 宏量目标（与 dashboard_page L245-250 一致：carbGPerKg 为 null 时由热量残差反算）
    final proteinGoal = profile.proteinGPerKg * profile.weightKg;
    final fatGoal = profile.fatGPerKg * profile.weightKg;
    final carbGoalRaw = profile.carbGPerKg != null
        ? profile.carbGPerKg! * profile.weightKg
        : (profile.dailyCalorieTarget - proteinGoal * 4 - fatGoal * 9) / 4;
    final carbGoal = carbGoalRaw < 0 ? 0.0 : carbGoalRaw;

    // 覆盖率：有记录天数 / 窗口总天数（让 AI 知道数据完整度）
    final coverageRate = days > 0 ? recordedDays / days : 0.0;

    // 平均超额/缺口（仅有记录的天参与，避免 0 拉低均值）
    final avgExcess = recordedDays > 0 ? totalExcess / recordedDays : 0.0;

    // 连续记录 streak：从今天往前数连续有记录的天数
    var streak = 0;
    for (var i = days - 1; i >= 0; i--) {
      final date = formatYmd(start.add(Duration(days: i)));
      final hasRecord = meals.any((m) => m.date == date);
      if (hasRecord) {
        streak++;
      } else {
        // 今天没记录不算中断（用户可能还没吃），从昨天开始数连续
        if (i == days - 1) continue;
        break;
      }
    }

    // 体重摘要：首末体重 + 变化（last - first，负=减重）
    final weightFirst =
        weights.isNotEmpty ? weights.first.weightKg : null;
    final weightLast =
        weights.isNotEmpty ? weights.last.weightKg : null;
    final weightDiff =
        (weightFirst != null && weightLast != null)
            ? weightLast - weightFirst
            : null;

    // 饮食偏好画像：统计 foodItemId 频次 + 热量贡献，取 top 5
    final foodCounts = <int, int>{};
    final foodCalories = <int, double>{};
    for (final m in meals) {
      foodCounts[m.foodItemId] = (foodCounts[m.foodItemId] ?? 0) + 1;
      foodCalories[m.foodItemId] =
          (foodCalories[m.foodItemId] ?? 0) + m.actualCalories;
    }
    List<String> preferenceFoods = const [];
    final preferenceFoodCounts = <int, int>{};
    final preferenceFoodCalories = <int, double>{};
    if (foodCounts.isNotEmpty) {
      final sortedIds = foodCounts.keys.toList()
        ..sort((a, b) => foodCounts[b]!.compareTo(foodCounts[a]!));
      final topIds = sortedIds.take(5).toList();
      final foods = await foodRepo.getByIds(topIds);
      final idToName = {for (final f in foods) f.id: f.name};
      preferenceFoods = topIds
          .map((id) => idToName[id])
          .whereType<String>()
          .toList();
      for (final id in topIds) {
        preferenceFoodCounts[id] = foodCounts[id] ?? 0;
        preferenceFoodCalories[id] = foodCalories[id] ?? 0;
      }
    }

    // 月报周环比：30 天按 7 天分组（4-5 周），每周算日均热量
    final weeklyBreakdown = <({String weekStart, String weekEnd, double avgCal})>[];
    if (_periodType == 'monthly') {
      for (var w = 0; w < days; w += 7) {
        final wEnd = (w + 6 < days) ? w + 6 : days - 1;
        final wStart = formatYmd(start.add(Duration(days: w)));
        final wEndStr = formatYmd(start.add(Duration(days: wEnd)));
        var wSum = 0.0;
        var wDays = 0;
        for (var i = w; i <= wEnd; i++) {
          if (dailyCal[i] > 0) {
            wSum += dailyCal[i];
            wDays++;
          }
        }
        weeklyBreakdown.add((
          weekStart: wStart,
          weekEnd: wEndStr,
          avgCal: wDays > 0 ? wSum / wDays : 0,
        ));
      }
    }

    if (mounted) {
      setState(() {
        _dailyCal = dailyCal;
        _dailyWeight = dailyWeight;
        _targetCal = targetCal;
        _recordedDays = recordedDays;
        _totalDays = days;
        _dailyProtein = dailyProtein;
        _dailyFat = dailyFat;
        _dailyCarbs = dailyCarbs;
        _proteinGoal = proteinGoal;
        _fatGoal = fatGoal;
        _carbGoal = carbGoal;
        _mealTypeCalories = mealTypeCalories;
        _streak = streak;
        _avgExcess = avgExcess;
        _goalHitDays = goalHitDays;
        _weightFirst = weightFirst;
        _weightLast = weightLast;
        _weightDiff = weightDiff;
        _preferenceFoods = preferenceFoods;
        _preferenceFoodCounts = preferenceFoodCounts;
        _preferenceFoodCalories = preferenceFoodCalories;
        _weeklyBreakdown = weeklyBreakdown;
      });
    }
    return (
      dailyCal: dailyCal,
      dailyWeight: dailyWeight,
      targetCal: targetCal,
      goal: profile.goal,
      dailyProtein: dailyProtein,
      dailyFat: dailyFat,
      dailyCarbs: dailyCarbs,
      proteinGoal: proteinGoal,
      fatGoal: fatGoal,
      carbGoal: carbGoal,
      recordedDays: recordedDays,
      totalDays: days,
      coverageRate: coverageRate,
      preferenceFoods: preferenceFoods,
      mealTypeCalories: mealTypeCalories,
      streak: streak,
      avgExcess: avgExcess,
      goalHitDays: goalHitDays,
      weightFirst: weightFirst,
      weightLast: weightLast,
      weightDiff: weightDiff,
      weeklyBreakdown: weeklyBreakdown,
      specialCondition: profile.specialCondition,
      dietPreference: profile.dietPreference,
      healthCondition: profile.healthCondition,
    );
  }

  Future<void> _loadExisting() async {
    // M2 修复：每次调用版本号 +1，setState 前检查版本，不匹配说明用户已切换周期，丢弃这次结果
    final myVersion = ++_loadVersion;
    try {
      // 先聚当前周期数据填充图表 state 字段
      await _aggregatePeriod();
      final repo = await ref.read(recognize.insightRepoProvider.future);
      final existing = await repo.find(_periodType, _periodStart, _periodEnd);
      if (!mounted) return;
      // M2 修复：版本号不匹配说明用户已切换周期，丢弃这次结果避免旧数据覆盖新状态
      if (myVersion != _loadVersion) return;
      if (existing != null) {
        setState(() {
          _summary = existing.summaryText;
          _error = null; // 加载到已有汇总，清掉历史错误（如上次生成失败的提示）
        });
      }
    } finally {
      // M24 Task A6：加载完成清掉 loading 标志（mounted 检查防 async gap 后 widget 已销毁）
      // 覆盖 initState 初次加载 + onSelectionChanged 切换两条路径，单一来源避免重复
      if (mounted) setState(() => _chartLoading = false);
    }
  }

  Future<void> _generate() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      // 复用 _aggregatePeriod 的聚合结果（避免重复查询，同时刷新图表 state）
      final agg = await _aggregatePeriod();

      final apiKey = ref.read(recognize.glmApiKeyProvider);
      final baseUrl = ref.read(recognize.glmBaseUrlProvider);
      if (apiKey.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = '未配置 GLM API Key，请到设置页填写';
          _summary = null;
        });
        return;
      }
      // Sprint 7 T54：离线守卫——无网络直接提示，不调 GLM API
      // 置于 apiKey 检查之后：key 未配置时直接提示设置页，避免在无网络/测试沙箱触发 connectivity 平台通道
      final online = await ref.refresh(recognize.networkAvailableProvider.future);
      if (!online) {
        if (!mounted) return;
        setState(() {
          _error = '当前无网络，请联网后重试';
          _summary = null;
        });
        return;
      }
      // v1.11 数据不足守卫：0 天有记录时不调 AI（全 0 数据生成的建议无意义，浪费 API 调用）
      // 置于 key/网络检查之后：config/网络问题更基础，应优先提示；key+网络 OK 但无数据时才提示记录
      if (agg.recordedDays == 0) {
        if (!mounted) return;
        setState(() {
          _error = '近 ${agg.totalDays} 天无饮食记录，请先记录至少 1 天再生成汇总';
          _summary = null;
        });
        return;
      }
      final provider = GlmFlashProvider(
        apiKey: apiKey,
        baseUrl: baseUrl.isEmpty
            ? 'https://open.bigmodel.cn/api/paas/v4'
            : baseUrl,
      );
      final data = {
        'daily_calories': agg.dailyCal,
        'daily_weights': agg.dailyWeight,
        'target_calories': agg.targetCal,
        'goal': agg.goal,
        // v1.11 增强：宏量 + 偏好 + 覆盖率，让 AI 给出更智能的建议
        'daily_protein': agg.dailyProtein,
        'daily_fat': agg.dailyFat,
        'daily_carbs': agg.dailyCarbs,
        'protein_goal': agg.proteinGoal,
        'fat_goal': agg.fatGoal,
        'carb_goal': agg.carbGoal,
        'recorded_days': agg.recordedDays,
        'total_days': agg.totalDays,
        'coverage_rate': agg.coverageRate,
        'preference_foods': agg.preferenceFoods,
        // 问题2 增强：餐次分布/streak/超额/达成天数/体重变化/特殊人群/周环比
        'meal_type_calories': agg.mealTypeCalories,
        'streak': agg.streak,
        'avg_excess': agg.avgExcess,
        'goal_hit_days': agg.goalHitDays,
        'weight_diff': agg.weightDiff,
        'weekly_breakdown': agg.weeklyBreakdown
            .map((w) => {
                  'weekStart': w.weekStart,
                  'weekEnd': w.weekEnd,
                  'avgCal': w.avgCal,
                })
            .toList(),
        'special_condition': agg.specialCondition,
        'diet_preference': agg.dietPreference,
        'health_condition': agg.healthCondition,
      };
      final text = _periodType == 'weekly'
          ? await provider.generateWeeklySummary(data)
          : await provider.generateMonthlySummary(data);

      final insightRepo = await ref.read(recognize.insightRepoProvider.future);
      await insightRepo.regenerate(
        periodType: _periodType,
        periodStart: _periodStart,
        periodEnd: _periodEnd,
        summaryText: text,
      );
      if (!mounted) return;
      setState(() {
        _summary = text;
        _error = null;
      });
    } catch (e) {
      debugPrint('生成失败: $e');
      if (!mounted) return;
      setState(() {
        _error = '生成失败：AI 服务暂不可用，请检查网络后重试。';
        _summary = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    if (_summary == null) return;
    final ctrl = TextEditingController(text: _summary);
    try {
      final edited = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('编辑汇总'),
          content: TextField(
            controller: ctrl,
            maxLines: 10,
            // 自然语言汇总文本：保留默认 autocorrect/enabledSuggestions
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: '编辑 AI 汇总文本…',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (edited == null) return;
      final repo = await ref.read(recognize.insightRepoProvider.future);
      final existing = await repo.find(_periodType, _periodStart, _periodEnd);
      if (existing != null) {
        await repo.updateText(existing.id, edited);
        if (!mounted) return;
        setState(() => _summary = edited);
      }
    } finally {
      ctrl.dispose();
    }
  }

  /// 重新生成二次确认（避免覆盖用户编辑过的汇总）
  Future<void> _confirmRegenerate() async {
    final confirmed = await confirmAction(
      context,
      title: '重新生成',
      content: '重新生成会覆盖当前汇总，是否继续？',
      confirmLabel: '继续',
    );
    if (confirmed == true) {
      await _generate();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 滚动窗口文案：不再用"本周/本月"（自然周/月），改"近 7 天/近 30 天"明确窗口长度
    final periodLabel = _periodType == 'weekly' ? '近 7 天' : '近 30 天';
    return Scaffold(
      appBar: AppBar(
        title: Text('$_periodStart ~ $_periodEnd'),
        actions: [
          if (_summary != null)
            IconButton(
                icon: const Icon(Icons.edit),
                tooltip: '编辑汇总',
                onPressed: _edit),
        ],
        // 周/月切换器 pin 在 AppBar.bottom（不随 ListView 滚动消失，与 records_tab 统一）
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'weekly', label: Text('周')),
                ButtonSegment(value: 'monthly', label: Text('月')),
              ],
              selected: {_periodType},
              onSelectionChanged: (v) {
                setState(() {
                  _periodType = v.first;
                  _calcPeriod();
                  _summary = null;
                  _error = null;
                  _dailyCal = [];
                  _dailyWeight = [];
                  _recordedDays = 0;
                  _totalDays = v.first == 'weekly' ? 7 : 30;
                  // 问题2：切换周期时同步重置新增 state，避免图表闪现旧数据
                  _dailyProtein = [];
                  _dailyFat = [];
                  _dailyCarbs = [];
                  _proteinGoal = 0;
                  _fatGoal = 0;
                  _carbGoal = 0;
                  _mealTypeCalories = {};
                  _streak = 0;
                  _avgExcess = 0;
                  _goalHitDays = 0;
                  _weightFirst = null;
                  _weightLast = null;
                  _weightDiff = null;
                  _preferenceFoods = [];
                  _preferenceFoodCounts = {};
                  _preferenceFoodCalories = {};
                  _weeklyBreakdown = [];
                  // M24 Task A6：切换周期时立即显示 loading，_loadExisting
                  // finally 内置 _chartLoading=false（async gap 后 mounted 已检查）
                  _chartLoading = true;
                });
                _loadExisting();
              },
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 热量折线图（含目标/均值参考线，至少 2 天数据才渲染）
          // M24 Task A6：AnimatedSwitcher 包裹 loading/chart/empty 三态，300ms 过渡
          // 避免 周/月切换时图表直接消失再出现的突兀感
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _chartLoading
                ? const LoadingState(key: ValueKey('insight-calories-loading'))
                : _dailyCal.length >= 2
                    ? SizedBox(
                        key: const ValueKey('insight-calories-chart'),
                        height: 200,
                        child: _buildCaloriesChart(),
                      )
                    : const EmptyChartHint(
                        '暂无足够热量数据，至少记录 2 天',
                        key: ValueKey('insight-calories-empty'),
                      ),
          ),
          const SizedBox(height: 16),
          // 体重趋势折线图（至少 2 条记录才渲染）
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _chartLoading
                ? const LoadingState(key: ValueKey('insight-weight-loading'))
                : _dailyWeight.length >= 2
                    ? SizedBox(
                        key: const ValueKey('insight-weight-chart'),
                        height: 150,
                        child: _buildWeightChart(),
                      )
                    : const EmptyChartHint(
                        '暂无足够体重数据，至少记录 2 次',
                        key: ValueKey('insight-weight-empty'),
                      ),
          ),
          const SizedBox(height: 16),
          // 问题2：统计数字卡片（streak / 平均超额 / 达成天数 / 体重变化）
          // 仅在有记录数据时显示，避免空态占位噪音
          if (!_chartLoading && _recordedDays > 0) ...[
            _buildStatCards(),
            const SizedBox(height: 16),
          ],
          // 问题2：餐次分布环图（早/午/晚/加餐 占比）
          if (!_chartLoading && _mealTypeCaloriesTotal > 0) ...[
            _buildMealTypeChart(),
            const SizedBox(height: 16),
          ],
          // 问题2：三宏达成率柱图（实际均值 vs 目标）
          // 守卫用 _recordedDays > 0（不用 _dailyProtein.isNotEmpty）：
          // 空数据库时 _dailyProtein=[0,0,0,0,0,0,0] 长度 7 但全 0，不应渲染柱图
          if (!_chartLoading && _recordedDays > 0) ...[
            _buildMacroBarChart(),
            const SizedBox(height: 16),
          ],
          // 问题2：偏好食物 Top5 列表（带频次 + 热量贡献）
          if (!_chartLoading && _preferenceFoods.isNotEmpty) ...[
            _buildPreferenceFoodsCard(),
            const SizedBox(height: 16),
          ],
          // 问题2：月报周环比（仅 monthly 显示，30 天按 7 天分组）
          if (!_chartLoading &&
              _periodType == 'monthly' &&
              _weeklyBreakdown.isNotEmpty) ...[
            _buildWeeklyBreakdownCard(),
            const SizedBox(height: 16),
          ],
          // v1.11：覆盖率提示（让用户知道数据完整度，覆盖率低时建议多记录）
          // 守卫已保证 recordedDays >= 1 才调 AI，但提示仍展示完整度供用户参考
          if (_totalDays > 0 && _recordedDays < _totalDays)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(Icons.info_outline,
                        size: 16,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '已记录 $_recordedDays/$_totalDays 天'
                      '（${(_recordedDays * 100 / _totalDays).round()}%），'
                      '数据不完整时建议仅供参考',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ]),
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null)
            // 错误态独立 Card：errorContainer 背景 + error 图标，与 AI 汇总 Card 视觉区分
            // （原实现把错误塞进 _summary 同一 Card 渲染，用户误以为是 AI 输出）
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Icon(Icons.error_outline,
                          color:
                              Theme.of(context).colorScheme.onErrorContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_error!,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer)),
                    ),
                  ],
                ),
              ),
            )
          else if (_summary != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(_summary!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(height: 1.6)),
              ),
            )
          else
            Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('$periodLabel尚未生成汇总，点击下方按钮生成')),
            ),
          const SizedBox(height: 16),
          // loading 内置按钮（与 calibration 一致），避免单独转圈占行
          FilledButton.icon(
            onPressed: _loading
                ? null
                : (_summary == null ? _generate : _confirmRegenerate),
            icon: _loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary))
                : const Icon(Icons.auto_awesome),
            label: Text(_summary == null ? '生成$periodLabel汇总' : '重新生成'),
          ),
        ],
      ),
    );
  }

  /// 热量折线图：每日摄入 + 目标热量参考线 + 均值参考线
  /// 滚动窗口（v1.11）：周/月都用 M/D 格式 X 轴标签（rolling window 跨自然周/月）。
  ///
  /// 美化要点（解决"数字重叠"和"不够美观"）：
  /// - Y 轴设 interval（按 maxCal/4 取整到 50 的倍数），避免默认刻度挤成一堆
  /// - 边框只留左 + 下（现代图表风格，去掉上/右多余的线）
  /// - 网格线只画水平方向且按 Y 轴 interval，垂直网格去掉减少视觉噪音
  /// - 数据点变小（radius 3）+ 描边，曲线 + 半透明渐变填充
  /// - 触摸节点显示 tooltip（具体哪天多少 kcal）
  /// - 参考线标签左对齐避开 Y 轴标签区，目标/均值上下错开防重叠
  Widget _buildCaloriesChart() {
    final cs = Theme.of(context).colorScheme;
    final spots = <FlSpot>[];
    for (var i = 0; i < _dailyCal.length; i++) {
      spots.add(FlSpot(i.toDouble(), _dailyCal[i]));
    }
    final maxCal = _dailyCal.reduce((a, b) => a > b ? a : b);
    final avgCal = _dailyCal.reduce((a, b) => a + b) / _dailyCal.length;
    final start = parseYmd(_periodStart);

    // Y 轴 interval：取 maxCal 的 1/4，向上取整到 50 的倍数（刻度整齐不重叠）
    final yInterval = ((maxCal * 1.2 / 4) / 50).ceil() * 50.0;
    final effectiveInterval = yInterval < 50 ? 50.0 : yInterval;

    return LineChart(LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false, // 只留水平网格，去掉垂直线减少噪音
        horizontalInterval: effectiveInterval,
        getDrawingHorizontalLine: (v) => FlLine(
          color: cs.outlineVariant.withValues(alpha: 0.4),
          strokeWidth: 1,
          dashArray: [3, 3],
        ),
      ),
      borderData: FlBorderData(
        show: true,
        // 只留左 + 下边框（现代图表风格）
        border: Border(
          left: BorderSide(color: cs.outlineVariant),
          bottom: BorderSide(color: cs.outlineVariant),
          top: BorderSide.none,
          right: BorderSide.none,
        ),
      ),
      minX: 0,
      maxX: (_dailyCal.length - 1).toDouble(),
      minY: 0,
      maxY: maxCal * 1.2,
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          axisNameWidget: const SizedBox.shrink(),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            getTitlesWidget: (value, meta) {
              final idx = value.toInt();
              if (idx < 0 || idx >= _dailyCal.length) {
                return const SizedBox.shrink();
              }
              // 滚动窗口（v1.11）：周/月都用 M/D 格式，不再用"一二三四五六日"
              // （rolling window 跨自然周/月，day-of-week 误导）
              // 周视图：7 天全显示 M/D（标签短，7 个不挤）
              // 月视图：每 5 天显示一个 M/D（30 个标签太密）
              final date = start.add(Duration(days: idx));
              if (_periodType == 'weekly') {
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${date.month}/${date.day}',
                      style: TextStyle(
                          fontSize: 10, color: cs.onSurfaceVariant)),
                );
              }
              // 月视图：每 5 天一个标签（idx 0/5/10/15/20/25）
              if (idx == 0 || idx % 5 == 0) {
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${date.month}/${date.day}',
                      style: TextStyle(
                          fontSize: 10, color: cs.onSurfaceVariant)),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: effectiveInterval, // 关键：固定间隔防重叠
            getTitlesWidget: (value, meta) {
              // 0 不显示（避免和 X 轴标签挤）
              if (value == 0) return const SizedBox.shrink();
              return Text('${value.round()}',
                  style: TextStyle(
                      fontSize: 10, color: cs.onSurfaceVariant));
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          // 目标热量参考线（标签左上，避开 Y 轴标签）
          HorizontalLine(
            y: _targetCal.toDouble(),
            color: cs.primary.withValues(alpha: 0.7),
            strokeWidth: 1.5,
            dashArray: [6, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topLeft,
              padding: const EdgeInsets.only(left: 44, bottom: 4),
              style: TextStyle(fontSize: 10, color: cs.primary, fontWeight: FontWeight.w600),
              labelResolver: (_) => '目标 $_targetCal',
            ),
          ),
          // 平均线（标签左下，与目标线错开防重叠）
          HorizontalLine(
            y: avgCal,
            color: cs.tertiary.withValues(alpha: 0.7),
            strokeWidth: 1.5,
            dashArray: [6, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.only(left: 44, top: 4),
              style: TextStyle(fontSize: 10, color: cs.tertiary, fontWeight: FontWeight.w600),
              labelResolver: (_) => '均值 ${avgCal.round()}',
            ),
          ),
        ],
      ),
      lineTouchData: LineTouchData(
        // 触摸节点显示具体值
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final idx = spot.spotIndex;
              final date = start.add(Duration(days: idx));
              // 滚动窗口：周/月都用 M/D 格式（rolling window 跨自然周/月）
              final label = '${date.month}/${date.day}';
              return LineTooltipItem(
                '$label\n${spot.y.round()} kcal',
                TextStyle(
                  color: cs.onInverseSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              );
            }).toList();
          },
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.35,
          color: cs.primary,
          barWidth: 2.5,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
              radius: 3,
              color: cs.primary,
              strokeWidth: 1.5,
              strokeColor: cs.surface,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.primary.withValues(alpha: 0.18),
                cs.primary.withValues(alpha: 0.02),
              ],
            ),
          ),
        ),
      ],
    ));
  }

  /// 体重趋势折线图
  /// 美化：Y 轴 interval 固定（防小数重叠）+ 边框只留左下 + 点变小 + 触摸 tooltip
  Widget _buildWeightChart() {
    final cs = Theme.of(context).colorScheme;
    final spots = <FlSpot>[];
    for (var i = 0; i < _dailyWeight.length; i++) {
      spots.add(FlSpot(i.toDouble(), _dailyWeight[i]));
    }
    final minW = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxW = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxW - minW) * 0.15 + 0.5;
    // Y 轴 interval：范围/4，至少 0.2（体重波动小时刻度别太密）
    final range = (maxW - minW) + padding * 2;
    final yInterval = (range / 4).clamp(0.2, double.infinity);

    return LineChart(LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: yInterval,
        getDrawingHorizontalLine: (v) => FlLine(
          color: cs.outlineVariant.withValues(alpha: 0.4),
          strokeWidth: 1,
          dashArray: [3, 3],
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          left: BorderSide(color: cs.outlineVariant),
          bottom: BorderSide(color: cs.outlineVariant),
          top: BorderSide.none,
          right: BorderSide.none,
        ),
      ),
      minX: 0,
      maxX: (_dailyWeight.length - 1).toDouble(),
      minY: minW - padding,
      maxY: maxW + padding,
      titlesData: FlTitlesData(
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: yInterval, // 固定间隔防小数重叠
            getTitlesWidget: (value, meta) {
              return Text(value.toStringAsFixed(1),
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant));
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              return LineTooltipItem(
                '${spot.y.toStringAsFixed(1)} kg',
                TextStyle(
                  color: cs.onInverseSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList();
          },
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.35,
          color: cs.secondary,
          barWidth: 2.5,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
              radius: 3,
              color: cs.secondary,
              strokeWidth: 1.5,
              strokeColor: cs.surface,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.secondary.withValues(alpha: 0.15),
                cs.secondary.withValues(alpha: 0.02),
              ],
            ),
          ),
        ),
      ],
    ));
  }

  // ============= 问题2：新增 UI 组件 =============

  /// 统计数字卡片：2x2 网格，展示 streak / 平均超额 / 达成天数 / 体重变化
  ///
  /// 仅在 _recordedDays > 0 时调用（build 守卫已保证）。
  /// 4 个卡片用 MD3 角色色区分语义：primary(记录) / tertiary(超额) / secondary(达成) / error或primary(体重)
  Widget _buildStatCards() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // 平均超额文案：正=超目标，负=缺目标，0=刚好
    final excessDir = _avgExcess > 1
        ? '超'
        : _avgExcess < -1
            ? '缺'
            : '持平';
    final excessColor = _avgExcess.abs() < 1
        ? cs.primary
        : (_avgExcess > 0 ? cs.error : cs.tertiary);
    // 体重变化文案：负=减重（减脂目标下好），正=增重
    // 首末体重都有时显示"70.5→69.8"作为 value，"减 0.7 kg"作为 label
    final hasWeight = _weightFirst != null && _weightLast != null;
    final weightValue = hasWeight
        ? '${_weightFirst!.toStringAsFixed(1)}→${_weightLast!.toStringAsFixed(1)}'
        : '—';
    final weightLabel = !hasWeight
        ? '体重变化(kg)'
        : (_weightDiff! == 0
            ? '体重持平'
            : _weightDiff! < 0
                ? '减 ${_weightDiff!.abs().toStringAsFixed(1)} kg'
                : '增 ${_weightDiff!.toStringAsFixed(1)} kg');
    final weightColor = !hasWeight
        ? cs.onSurfaceVariant
        : (_weightDiff! == 0
            ? cs.primary
            : (_weightDiff! < 0 ? cs.tertiary : cs.error));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text('周期概览',
                    style: tt.titleSmall
                        ?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _statTile(
                  icon: Icons.local_fire_department_outlined,
                  value: '$_streak 天',
                  label: '连续记录',
                  color: cs.primary,
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: _statTile(
                  icon: Icons.trending_up_rounded,
                  value:
                      '$excessDir ${_avgExcess.abs() < 1 ? 0 : _avgExcess.abs().round()}',
                  label: '平均 kcal/天',
                  color: excessColor,
                )),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _statTile(
                  icon: Icons.check_circle_outline,
                  value: '$_goalHitDays/$_totalDays',
                  label: '目标达成',
                  color: cs.secondary,
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: _statTile(
                  icon: Icons.monitor_weight_outlined,
                  value: weightValue,
                  label: weightLabel,
                  color: weightColor,
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 单个统计数字 tile（图标 + 大数字 + 标签）
  Widget _statTile({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label,
                    style: tt.labelSmall?.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              style: tt.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ],
      ),
    );
  }

  /// 餐次分布环图：早/午/晚/加餐 占比 + 中心总热量
  ///
  /// 用 PieChart（ring 模式，centerSpaceRadius 留白显示总热量）。
  /// 4 个 section 用 MD3 角色色：primary/tertiary/secondary/outline（避免与三宏色冲突）。
  Widget _buildMealTypeChart() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final total = _mealTypeCaloriesTotal;
    final sections = <PieChartSectionData>[];
    final mealConfig = [
      ('breakfast', '早餐', cs.primary),
      ('lunch', '午餐', cs.tertiary),
      ('dinner', '晚餐', cs.secondary),
      ('snack', '加餐', cs.onSurfaceVariant), // snack 用 onSurfaceVariant（深灰）替代 outline（浅灰），避免 section 白文字对比度不足
    ];
    for (final (key, label, color) in mealConfig) {
      final cal = _mealTypeCalories[key] ?? 0;
      if (cal <= 0) continue;
      final pct = total > 0 ? cal / total * 100 : 0.0;
      sections.add(PieChartSectionData(
        value: cal,
        color: color,
        radius: 36,
        title: '${pct.toStringAsFixed(1)}%', // 保留 1 位小数（如 33.3%），避免 33.333333% 长字符串
        titleStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cs.onPrimary,
        ),
        badgeWidget: _mealBadge(label, cal.round(), color, cs),
        badgePositionPercentageOffset: 1.15,
      ));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart_outline_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text('餐次分布',
                    style: tt.titleSmall
                        ?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: PieChart(PieChartData(
                sections: sections,
                centerSpaceRadius: 42,
                sectionsSpace: 2,
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    // 触摸交互预留（暂不实现 tooltip，避免复杂度）
                  },
                ),
              )),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '总摄入 ${total.round()} kcal',
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 餐次环图 badge（标签 + kcal，环外显示）
  Widget _mealBadge(String label, int kcal, Color color, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        // alpha 0.12 → 0.28：提高背景不透明度，避免半透明看不清
        color: color.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label $kcal',
        style: TextStyle(
          fontSize: 10,
          // 文字色用 onSurface（深色）替代 color 本身（如 outline 灰），
          // 深色文字 + 淡色背景对比度更高，可读性更好；餐次区分靠背景色调
          color: cs.onSurface,
          fontWeight: FontWeight.w700, // w500 → w700 加粗提高可读性
        ),
      ),
    );
  }

  /// 三宏达成率柱图：蛋白/脂肪/碳水 实际均值 vs 目标
  ///
  /// 用 BarChart，3 组柱（每组 2 个柱：实际均值 + 目标）。
  /// 实际柱用 MD3 三角色（tertiary=蛋白/secondary=脂肪/primary=碳水，与 MacroColors 一致）。
  /// 目标柱用半透明同色，让用户直观看到"达成/超出/不足"。
  Widget _buildMacroBarChart() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // 计算实际均值（只统计热量>0 的天，避免 0 拉低）
    var sumP = 0.0, sumF = 0.0, sumC = 0.0;
    var n = 0;
    for (var i = 0; i < _dailyProtein.length; i++) {
      if (i < _dailyCal.length && _dailyCal[i] > 0) {
        n++;
        sumP += _dailyProtein[i];
        sumF += _dailyFat[i];
        sumC += _dailyCarbs[i];
      }
    }
    if (n == 0) return const SizedBox.shrink();
    final avgP = sumP / n;
    final avgF = sumF / n;
    final avgC = sumC / n;
    // BarChartGroupData 3 组，每组 2 个柱
    final groups = [
      BarChartGroupData(
        x: 0,
        barRods: [
          BarChartRodData(
            toY: avgP,
            color: MacroColors.protein(cs),
            width: 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
          BarChartRodData(
            toY: _proteinGoal,
            color: MacroColors.protein(cs).withValues(alpha: 0.3),
            width: 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ),
      BarChartGroupData(
        x: 1,
        barRods: [
          BarChartRodData(
            toY: avgF,
            color: MacroColors.fat(cs),
            width: 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
          BarChartRodData(
            toY: _fatGoal,
            color: MacroColors.fat(cs).withValues(alpha: 0.3),
            width: 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ),
      BarChartGroupData(
        x: 2,
        barRods: [
          BarChartRodData(
            toY: avgC,
            color: MacroColors.carb(cs),
            width: 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
          BarChartRodData(
            toY: _carbGoal,
            color: MacroColors.carb(cs).withValues(alpha: 0.3),
            width: 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ),
    ];
    // Y 轴最大值：取四值（avgP/avgF/avgC/proteinGoal/fatGoal/carbGoal）最大 *1.2
    final maxV = [
      avgP, avgF, avgC, _proteinGoal, _fatGoal, _carbGoal
    ].reduce((a, b) => a > b ? a : b);
    final maxY = (maxV * 1.2).clamp(10.0, double.infinity);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text('三宏达成率',
                    style: tt.titleSmall
                        ?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
                const Spacer(),
                // 图例：实色=实际均值，半透明=目标
                _legendDot(MacroColors.protein(cs), '蛋白', cs),
                const SizedBox(width: 8),
                _legendDot(MacroColors.fat(cs), '脂肪', cs),
                const SizedBox(width: 8),
                _legendDot(MacroColors.carb(cs), '碳水', cs),
              ],
            ),
            const SizedBox(height: 4),
            Text('实色=记录日均值，半透明=目标值',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 11)),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: BarChart(BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                groupsSpace: 24,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, gIdx, rod, rIdx) {
                      final labels = ['蛋白', '脂肪', '碳水'];
                      final kind = rIdx == 0 ? '均值' : '目标';
                      return BarTooltipItem(
                        '${labels[gIdx]} $kind\n${rod.toY.toStringAsFixed(1)} g',
                        TextStyle(
                          color: cs.onInverseSurface,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final labels = ['蛋白', '脂肪', '碳水'];
                        final idx = value.toInt();
                        if (idx < 0 || idx >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(labels[idx],
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant)),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: (maxY / 4).clamp(5.0, double.infinity),
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        return Text('${value.round()}',
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant));
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (maxY / 4).clamp(5.0, double.infinity),
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                    strokeWidth: 1,
                    dashArray: [3, 3],
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(color: cs.outlineVariant),
                    bottom: BorderSide(color: cs.outlineVariant),
                    top: BorderSide.none,
                    right: BorderSide.none,
                  ),
                ),
                barGroups: groups,
              )),
            ),
          ],
        ),
      ),
    );
  }

  /// 图例圆点（柱图用）：色块 + 文案
  Widget _legendDot(Color color, String label, ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
      ],
    );
  }

  /// 偏好食物 Top5 列表：排名 + 食物名 + 频次 + 热量贡献
  ///
  /// 数据来自 _preferenceFoods（已按频次降序取 top 5）+ _preferenceFoodCounts/FoodCalories。
  /// 用 Card + ListView(shrinkWrap)，每行带排名徽章 + 食物名 + 频次 + 热量贡献条。
  Widget _buildPreferenceFoodsCard() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // 总热量贡献（用于计算每项占比，渲染热量条）
    final totalCal = _preferenceFoodCalories.values.fold<double>(0.0, (s, v) => s + v);
    // _preferenceFoods 是 List<String>（按频次降序），但需要 id 找频次/热量
    // _preferenceFoodCounts/FoodCalories 的 key 是 foodItemId，与 _preferenceFoods 顺序一致
    // （_aggregatePeriod 内 topIds 顺序与 preferenceFoods 一致）
    final ids = _preferenceFoodCounts.keys.toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restaurant_menu, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text('常吃食物 Top ${_preferenceFoods.length}',
                    style: tt.titleSmall
                        ?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _preferenceFoods.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    // 排名徽章（1/2/3 用 primary/tertiary/secondary，其余用 outline）
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: i == 0
                            ? cs.primary
                            : i == 1
                                ? cs.tertiary
                                : i == 2
                                    ? cs.secondary
                                    : cs.outline,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: i < 3 ? cs.onPrimary : cs.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 食物名 + 频次
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_preferenceFoods[i],
                              style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          if (i < ids.length)
                            Text(
                              '${_preferenceFoodCounts[ids[i]] ?? 0} 次',
                              style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    // 热量贡献条 + 数字
                    if (i < ids.length && totalCal > 0)
                      SizedBox(
                        width: 80,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${(_preferenceFoodCalories[ids[i]] ?? 0).round()} kcal',
                              style: tt.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: ((_preferenceFoodCalories[ids[i]] ?? 0) /
                                        totalCal)
                                    .clamp(0.0, 1.0),
                                backgroundColor: cs.primary.withValues(alpha: 0.1),
                                color: cs.primary,
                                minHeight: 4,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 月报周环比卡片：30 天按 7 天分组（4-5 周），每周算日均热量
  ///
  /// 仅 monthly 显示。用 BarChart 展示每周日均热量，让用户看到周环比趋势。
  /// 配合参考线显示总体日均，方便对比。
  Widget _buildWeeklyBreakdownCard() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (_weeklyBreakdown.isEmpty) return const SizedBox.shrink();
    // 总体日均（参考线）
    final validWeeks = _weeklyBreakdown.where((w) => w.avgCal > 0).toList();
    final overallAvg = validWeeks.isEmpty
        ? 0.0
        : validWeeks.map((w) => w.avgCal).reduce((a, b) => a + b) /
            validWeeks.length;
    final maxCal = _weeklyBreakdown
        .map((w) => w.avgCal)
        .fold<double>(0.0, (a, b) => a > b ? a : b);
    final maxY = (maxCal * 1.2).clamp(100.0, double.infinity);
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < _weeklyBreakdown.length; i++) {
      final w = _weeklyBreakdown[i];
      groups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: w.avgCal,
            color: cs.primary,
            width: 22,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_view_week_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text('周环比',
                    style: tt.titleSmall
                        ?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text('每周日均热量（kcal），参考线=总体日均',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontSize: 11)),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: BarChart(BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                groupsSpace: 12,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, gIdx, rod, rIdx) {
                      final w = _weeklyBreakdown[gIdx];
                      return BarTooltipItem(
                        '第${gIdx + 1}周\n${w.weekStart}~${w.weekEnd}\n日均 ${rod.toY.round()} kcal',
                        TextStyle(
                          color: cs.onInverseSurface,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= _weeklyBreakdown.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('W${idx + 1}',
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant)),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: (maxY / 4).clamp(50.0, double.infinity),
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        return Text('${value.round()}',
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant));
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (maxY / 4).clamp(50.0, double.infinity),
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                    strokeWidth: 1,
                    dashArray: [3, 3],
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(color: cs.outlineVariant),
                    bottom: BorderSide(color: cs.outlineVariant),
                    top: BorderSide.none,
                    right: BorderSide.none,
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (overallAvg > 0)
                      HorizontalLine(
                        y: overallAvg,
                        color: cs.tertiary.withValues(alpha: 0.7),
                        strokeWidth: 1.5,
                        dashArray: [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topLeft,
                          padding: const EdgeInsets.only(left: 44, bottom: 4),
                          style: TextStyle(
                              fontSize: 10,
                              color: cs.tertiary,
                              fontWeight: FontWeight.w600),
                          labelResolver: (_) => '总体日均 ${overallAvg.round()}',
                        ),
                      ),
                  ],
                ),
                barGroups: groups,
              )),
            ),
          ],
        ),
      ),
    );
  }
}
