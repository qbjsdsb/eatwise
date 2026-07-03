import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/glm_flash_provider.dart';
import '../../data/repositories/insight_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/weight_log_repository.dart';
import '../recognize/providers.dart' as recognize;

/// AI 周报页：周/月视图切换 + GLM-4-Flash 生成中文建议（去重 + 可编辑）
class InsightPage extends ConsumerStatefulWidget {
  const InsightPage({super.key});
  @override
  ConsumerState<InsightPage> createState() => _InsightPageState();
}

class _InsightPageState extends ConsumerState<InsightPage> {
  String? _summary;
  bool _loading = false;
  String _periodType = 'weekly'; // 'weekly' | 'monthly'
  late String _periodStart;
  late String _periodEnd;
  // 当前周期聚合数据（供 fl_chart 折线图渲染）
  List<double> _dailyCal = []; // 每日热量（_periodStart ~ _periodEnd）
  List<double> _dailyWeight = []; // 每日体重（按 weight_log 记录顺序）
  int _targetCal = 2000; // 目标热量（读自 profile.dailyCalorieTarget）

  @override
  void initState() {
    super.initState();
    _calcPeriod();
    _loadExisting();
  }

  /// 根据 _periodType 计算 _periodStart/_periodEnd
  void _calcPeriod() {
    final now = DateTime.now();
    if (_periodType == 'weekly') {
      // 本周周一到周日
      final weekday = now.weekday;
      final monday = now.subtract(Duration(days: weekday - 1));
      final sunday = monday.add(const Duration(days: 6));
      _periodStart = _fmt(monday);
      _periodEnd = _fmt(sunday);
    } else {
      // 本月 1 到月末
      final first = DateTime(now.year, now.month, 1);
      final last = DateTime(now.year, now.month + 1, 0);
      _periodStart = _fmt(first);
      _periodEnd = _fmt(last);
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 聚合当前周期数据（热量按日 + 体重序列 + 目标热量），供图表与 AI 生成共用。
  /// 结果同时写入 state 字段 _dailyCal/_dailyWeight/_targetCal，避免重复查询。
  Future<
    ({
      List<double> dailyCal,
      List<double> dailyWeight,
      int targetCal,
      String goal,
    })
  >
  _aggregatePeriod() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final mealRepo = MealLogRepository(db);
    final weightRepo = WeightLogRepository(db);
    final profileRepo = ProfileRepository(db);

    final meals = await mealRepo.getRange(_periodStart, _periodEnd);
    final weights = await weightRepo.getRange(_periodStart, _periodEnd);
    final profile = await profileRepo.get();

    // 按日聚合热量（_periodStart ~ _periodEnd，周 7 天 / 月 28~31 天）
    final start = DateTime.parse(_periodStart);
    final end = DateTime.parse(_periodEnd);
    final days = end.difference(start).inDays + 1;
    final dailyCal = <double>[];
    for (var i = 0; i < days; i++) {
      final date = _fmt(start.add(Duration(days: i)));
      final cal = meals
          .where((m) => m.date == date)
          .fold<double>(0, (s, m) => s + m.actualCalories);
      dailyCal.add(cal);
    }
    final dailyWeight = weights.map((w) => w.weightKg).toList();
    final targetCal = profile.dailyCalorieTarget;

    if (mounted) {
      setState(() {
        _dailyCal = dailyCal;
        _dailyWeight = dailyWeight;
        _targetCal = targetCal;
      });
    }
    return (
      dailyCal: dailyCal,
      dailyWeight: dailyWeight,
      targetCal: targetCal,
      goal: profile.goal,
    );
  }

  Future<void> _loadExisting() async {
    // 先聚当前周期数据填充图表 state 字段
    await _aggregatePeriod();
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = InsightRepository(db);
    final existing = await repo.find(_periodType, _periodStart, _periodEnd);
    if (existing != null && mounted) {
      setState(() => _summary = existing.summaryText);
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
        setState(() => _summary = '未配置 GLM API Key，请到设置页填写');
        return;
      }
      // Sprint 7 T54：离线守卫——无网络直接提示，不调 GLM API
      // 置于 apiKey 检查之后：key 未配置时直接提示设置页，避免在无网络/测试沙箱触发 connectivity 平台通道
      final online = await ref.refresh(
        recognize.networkAvailableProvider.future,
      );
      if (!online) {
        if (!mounted) return;
        setState(() => _summary = '当前无网络，请联网后重试');
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
      };
      final text = _periodType == 'weekly'
          ? await provider.generateWeeklySummary(data)
          : await provider.generateMonthlySummary(data);

      final db = await ref.read(recognize.databaseProvider.future);
      final insightRepo = InsightRepository(db);
      await insightRepo.regenerate(
        periodType: _periodType,
        periodStart: _periodStart,
        periodEnd: _periodEnd,
        summaryText: text,
      );
      if (!mounted) return;
      setState(() => _summary = text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _summary = '生成失败：$e');
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
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (edited == null) return;
      final db = await ref.read(recognize.databaseProvider.future);
      final repo = InsightRepository(db);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新生成'),
        content: const Text('重新生成会覆盖当前汇总，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _generate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final periodLabel = _periodType == 'weekly' ? '本周' : '本月';
    return Scaffold(
      appBar: AppBar(
        title: Text('$_periodStart ~ $_periodEnd'),
        actions: [
          if (_summary != null)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: '编辑周报',
              onPressed: _edit,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 周/月切换
          Center(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'weekly', label: Text('周')),
                ButtonSegment(value: 'monthly', label: Text('月')),
              ],
              selected: {_periodType},
              onSelectionChanged: (selection) {
                setState(() {
                  _periodType = selection.first;
                  _calcPeriod();
                  _summary = null;
                  _dailyCal = [];
                  _dailyWeight = [];
                  _loadExisting();
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          // 热量折线图（含目标/均值参考线）
          if (_dailyCal.isNotEmpty) ...[
            SizedBox(height: 200, child: _buildCaloriesChart()),
            const SizedBox(height: 16),
          ],
          // 体重趋势折线图（至少 2 条记录才渲染）
          if (_dailyWeight.length >= 2) ...[
            SizedBox(height: 150, child: _buildWeightChart()),
            const SizedBox(height: 16),
          ],
          if (_summary != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _summary!,
                  style: const TextStyle(fontSize: 15, height: 1.6),
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('$periodLabel尚未生成汇总，点击下方按钮生成'),
              ),
            ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            FilledButton.icon(
              onPressed: _summary == null ? _generate : _confirmRegenerate,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_summary == null ? '生成$periodLabel汇总' : '重新生成'),
            ),
        ],
      ),
    );
  }

  /// 热量折线图：每日摄入 + 目标热量参考线 + 均值参考线
  /// 周视图 X 轴 '一二三四五六日'，月视图按日期每 5 天一个标签。
  Widget _buildCaloriesChart() {
    final cs = Theme.of(context).colorScheme;
    final spots = <FlSpot>[];
    for (var i = 0; i < _dailyCal.length; i++) {
      spots.add(FlSpot(i.toDouble(), _dailyCal[i]));
    }
    final maxCal = _dailyCal.reduce((a, b) => a > b ? a : b);
    final avgCal = _dailyCal.reduce((a, b) => a + b) / _dailyCal.length;
    final start = DateTime.parse(_periodStart);

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: cs.outlineVariant),
        ),
        minX: 0,
        maxX: (_dailyCal.length - 1).toDouble(),
        minY: 0,
        maxY: maxCal * 1.2,
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= _dailyCal.length) {
                  return const SizedBox.shrink();
                }
                if (_periodType == 'weekly') {
                  const days = ['一', '二', '三', '四', '五', '六', '日'];
                  return Text(days[idx], style: const TextStyle(fontSize: 10));
                }
                // 月视图：每 5 天一个标签（1/5/10/15/20/25/30）
                final date = start.add(Duration(days: idx));
                if (date.day == 1 || date.day % 5 == 0) {
                  return Text(
                    '${date.day}',
                    style: const TextStyle(fontSize: 10),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            // 目标热量参考线
            HorizontalLine(
              y: _targetCal.toDouble(),
              color: cs.primary,
              strokeWidth: 1,
              dashArray: [5, 5],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: TextStyle(fontSize: 9, color: cs.primary),
                labelResolver: (_) => '目标 $_targetCal',
              ),
            ),
            // 平均线
            HorizontalLine(
              y: avgCal,
              color: cs.tertiary,
              strokeWidth: 1,
              dashArray: [5, 5],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.bottomRight,
                style: TextStyle(fontSize: 9, color: cs.tertiary),
                labelResolver: (_) => '均值 ${avgCal.round()}',
              ),
            ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: cs.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: cs.primary.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  /// 体重趋势折线图
  Widget _buildWeightChart() {
    final cs = Theme.of(context).colorScheme;
    final spots = <FlSpot>[];
    for (var i = 0; i < _dailyWeight.length; i++) {
      spots.add(FlSpot(i.toDouble(), _dailyWeight[i]));
    }
    final minW = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxW = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxW - minW) * 0.1 + 0.5;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: cs.outlineVariant),
        ),
        minX: 0,
        maxX: (_dailyWeight.length - 1).toDouble(),
        minY: minW - padding,
        maxY: maxW + padding,
        titlesData: const FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: cs.tertiary,
            barWidth: 2,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}
