import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/glm_flash_provider.dart';
import '../../data/repositories/insight_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/weight_log_repository.dart';
import '../recognize/providers.dart' as recognize;

/// AI 周报页：周视图 + GLM-4-Flash 生成 ≤300 字中文建议（去重 + 可编辑）
class InsightPage extends ConsumerStatefulWidget {
  const InsightPage({super.key});
  @override
  ConsumerState<InsightPage> createState() => _InsightPageState();
}

class _InsightPageState extends ConsumerState<InsightPage> {
  String? _summary;
  bool _loading = false;
  late String _weekStart;
  late String _weekEnd;
  // 本周聚合数据（供 fl_chart 折线图渲染）
  List<double> _dailyCal = []; // 本周每日热量（周一~周日，7 元素）
  List<double> _dailyWeight = []; // 本周每日体重（按 weight_log 记录顺序）
  int _targetCal = 2000; // 目标热量（读自 profile.dailyCalorieTarget）

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    _weekStart = _fmt(monday);
    _weekEnd = _fmt(sunday);
    _loadExisting();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 聚合本周数据（热量按日 + 体重序列 + 目标热量），供图表与 AI 生成共用。
  /// 结果同时写入 state 字段 _dailyCal/_dailyWeight/_targetCal，避免重复查询。
  Future<({List<double> dailyCal, List<double> dailyWeight, int targetCal, String goal})>
      _aggregateWeek() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final mealRepo = MealLogRepository(db);
    final weightRepo = WeightLogRepository(db);
    final profileRepo = ProfileRepository(db);

    final meals = await mealRepo.getRange(_weekStart, _weekEnd);
    final weights = await weightRepo.getRange(_weekStart, _weekEnd);
    final profile = await profileRepo.get();

    // 按日聚合热量（周一~周日 7 天）
    final dailyCal = <double>[];
    for (var i = 0; i < 7; i++) {
      final date = _fmt(DateTime.parse(_weekStart).add(Duration(days: i)));
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
    // 先聚合本周数据填充图表 state 字段（_dailyCal/_dailyWeight/_targetCal）
    await _aggregateWeek();
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = InsightRepository(db);
    final existing = await repo.find('weekly', _weekStart, _weekEnd);
    if (existing != null && mounted) {
      setState(() => _summary = existing.summaryText);
    }
  }

  Future<void> _generate() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      // 复用 _aggregateWeek 的聚合结果（避免重复查询，同时刷新图表 state）
      final agg = await _aggregateWeek();

      final apiKey = ref.read(recognize.glmApiKeyProvider);
      final baseUrl = ref.read(recognize.glmBaseUrlProvider);
      if (apiKey.isEmpty) {
        if (!mounted) return;
        setState(() => _summary = '未配置 GLM API Key，请到设置页填写');
        return;
      }
      final provider = GlmFlashProvider(
        apiKey: apiKey,
        baseUrl: baseUrl.isEmpty
            ? 'https://open.bigmodel.cn/api/paas/v4'
            : baseUrl,
      );
      final text = await provider.generateWeeklySummary({
        'daily_calories': agg.dailyCal,
        'daily_weights': agg.dailyWeight,
        'target_calories': agg.targetCal,
        'goal': agg.goal,
      });

      final db = await ref.read(recognize.databaseProvider.future);
      final insightRepo = InsightRepository(db);
      await insightRepo.regenerate(
        periodType: 'weekly',
        periodStart: _weekStart,
        periodEnd: _weekEnd,
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
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
      final existing = await repo.find('weekly', _weekStart, _weekEnd);
      if (existing != null) {
        await repo.updateText(existing.id, edited);
        if (!mounted) return;
        setState(() => _summary = edited);
      }
    } finally {
      ctrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$_weekStart ~ $_weekEnd'),
        actions: [
          if (_summary != null)
            IconButton(icon: const Icon(Icons.edit), onPressed: _edit),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 周热量折线图（含目标/均值参考线）
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
                child: SelectableText(_summary!,
                    style: const TextStyle(fontSize: 15, height: 1.6)),
              ),
            )
          else
            const Card(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('本周尚未生成汇总，点击下方按钮生成')),
            ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            FilledButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_summary == null ? '生成本周汇总' : '重新生成'),
            ),
        ],
      ),
    );
  }

  /// 周热量折线图：每日摄入 + 目标热量参考线 + 均值参考线
  Widget _buildCaloriesChart() {
    final spots = <FlSpot>[];
    for (var i = 0; i < _dailyCal.length; i++) {
      spots.add(FlSpot(i.toDouble(), _dailyCal[i]));
    }
    final maxCal = _dailyCal.reduce((a, b) => a > b ? a : b);
    final avgCal = _dailyCal.reduce((a, b) => a + b) / _dailyCal.length;

    return LineChart(LineChartData(
      gridData: const FlGridData(show: true),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey.shade300),
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
              const days = ['一', '二', '三', '四', '五', '六', '日'];
              final idx = value.toInt();
              if (idx < 0 || idx >= days.length) {
                return const SizedBox.shrink();
              }
              return Text(days[idx], style: const TextStyle(fontSize: 10));
            },
          ),
        ),
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 40),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          // 目标热量参考线
          HorizontalLine(
            y: _targetCal.toDouble(),
            color: Colors.green,
            strokeWidth: 1,
            dashArray: [5, 5],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: const TextStyle(fontSize: 9, color: Colors.green),
              labelResolver: (_) => '目标 $_targetCal',
            ),
          ),
          // 平均线
          HorizontalLine(
            y: avgCal,
            color: Colors.orange,
            strokeWidth: 1,
            dashArray: [5, 5],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.bottomRight,
              style: const TextStyle(fontSize: 9, color: Colors.orange),
              labelResolver: (_) => '均值 ${avgCal.round()}',
            ),
          ),
        ],
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: Colors.blue,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: Colors.blue.withValues(alpha: 0.1),
          ),
        ),
      ],
    ));
  }

  /// 体重趋势折线图
  Widget _buildWeightChart() {
    final spots = <FlSpot>[];
    for (var i = 0; i < _dailyWeight.length; i++) {
      spots.add(FlSpot(i.toDouble(), _dailyWeight[i]));
    }
    final minW = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxW = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxW - minW) * 0.1 + 0.5;

    return LineChart(LineChartData(
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey.shade300),
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
          color: Colors.purple,
          barWidth: 2,
          dotData: const FlDotData(show: true),
        ),
      ],
    ));
  }
}
