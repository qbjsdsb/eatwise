import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/database/database.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/weight_log_repository.dart';
import '../../nutrition/tdee_calibrator.dart';
import '../recognize/providers.dart' as recognize;

/// 体重记录页：录入体重 + fl_chart 折线趋势图
class WeightPage extends ConsumerStatefulWidget {
  const WeightPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  ConsumerState<WeightPage> createState() => WeightPageState();
}

/// 公开 State：RecordsTabPage 通过 `GlobalKey<WeightPageState>` 调用 refresh()
class WeightPageState extends ConsumerState<WeightPage> {
  final _weightCtrl = TextEditingController();
  List<WeightLog> _logs = [];
  List<MealLog> _meals = []; // 30 天 meal_log（双轴图热量用）
  Map<String, double> _dailyCalories = {}; // 日期 → 当日总热量
  bool _loading = true;
  bool _busy = false; // 防重入：记录期间禁用按钮，避免双击重复写库

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 公开刷新方法：切换到该页时由父容器调用
  void refresh() => _load();

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final db = await ref.read(recognize.databaseProvider.future);
      final repo = WeightLogRepository(db);
      _logs = await repo.getRecent(days: 30);
      // 加载 30 天 meal_log 并按日聚合热量（双轴图用）
      final mealRepo = MealLogRepository(db);
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 30));
      final startStr =
          '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
      final endStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      _meals = await mealRepo.getRange(startStr, endStr);
      _dailyCalories = {};
      for (final m in _meals) {
        _dailyCalories[m.date] =
            (_dailyCalories[m.date] ?? 0) + m.actualCalories;
      }
    } catch (e) {
      // DB 异常时不卡死 loading，用空数据渲染（用户至少能看到空图表）
      _logs = [];
      _meals = [];
      _dailyCalories = {};
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: widget.embedded ? null : AppBar(title: const Text('体重记录')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('体重记录')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weightCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '今日体重 (kg)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('记录'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_logs.length >= 2)
            SizedBox(height: 250, child: _buildChart())
          else
            _emptyChartHint(),
          const SizedBox(height: 16),
          for (final log in _logs.reversed)
            ListTile(
              leading: const LeadingIconContainer(Icons.monitor_weight_outlined),
              title: Text('${log.weightKg.toStringAsFixed(1)} kg'),
              subtitle: Text(log.date),
            ),
        ],
      ),
    );
  }

  /// 趋势图空数据占位：图标 + 文案，与 insight/today_meals 空态风格一致。
  Widget _emptyChartHint() {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 120,
      child: Card(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.show_chart_rounded, size: 32, color: cs.onSurfaceVariant),
              const SizedBox(height: 8),
              Text('至少记录 2 次才能显示趋势图',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChart() {
    if (_logs.length < 2) {
      return const Center(child: Text('至少记录 2 次才能显示趋势图'));
    }

    final colorScheme = Theme.of(context).colorScheme;
    // 双轴技巧：fl_chart 0.70 不原生支持双 Y 轴。热量用真实值（左轴），
    // 体重按比例映射到热量轴范围；rightTitles 用 getTitlesWidget 反向映射
    // 显示体重刻度（社区常用双轴方案）。
    final weightSpots = <FlSpot>[];
    for (var i = 0; i < _logs.length; i++) {
      weightSpots.add(FlSpot(i.toDouble(), _logs[i].weightKg));
    }
    final weights = _logs.map((l) => l.weightKg).toList();
    final minW = weights.reduce((a, b) => a < b ? a : b);
    final maxW = weights.reduce((a, b) => a > b ? a : b);
    final wPadding = (maxW - minW) * 0.1 + 0.5;

    // 热量数据（主轴/左轴）：按体重记录日期对齐
    final calSpots = <FlSpot>[];
    for (var i = 0; i < _logs.length; i++) {
      final cal = _dailyCalories[_logs[i].date] ?? 0;
      calSpots.add(FlSpot(i.toDouble(), cal));
    }
    final cals = calSpots.map((s) => s.y).toList();
    final maxCal = cals.reduce((a, b) => a > b ? a : b);
    final calPadding = maxCal * 0.1 + 50;
    final calRange = maxCal + calPadding;
    final wMin = minW - wPadding;
    final wMax = maxW + wPadding;

    return LineChart(LineChartData(
      gridData: const FlGridData(show: true),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      minX: 0,
      maxX: (_logs.length - 1).toDouble(),
      minY: 0,
      maxY: calRange,
      titlesData: FlTitlesData(
        bottomTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          axisNameWidget: Text('kcal',
              style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
          sideTitles: const SideTitles(
            showTitles: true,
            reservedSize: 40,
          ),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: AxisTitles(
          axisNameWidget: Text('kg',
              style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            // 双轴：右 Y 轴显示体重刻度。interval 用热量轴单位
            //（getTitlesWidget 收到的 value 是热量轴值，按比例反推体重）
            interval: (calRange / 4).clamp(1, double.infinity),
            getTitlesWidget: (value, meta) {
              // value 是热量轴（左 Y 轴）值，反向映射回体重轴值
              final ratio = value / calRange;
              final w = wMin + (wMax - wMin) * ratio;
              return Text(w.toStringAsFixed(1),
                  style: TextStyle(fontSize: 9, color: colorScheme.onSurfaceVariant));
            },
          ),
        ),
      ),
      lineBarsData: [
        // 热量（左轴，主）
        LineChartBarData(
          spots: calSpots,
          isCurved: true,
          color: colorScheme.tertiary,
          barWidth: 2,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: colorScheme.tertiary.withValues(alpha: 0.1),
          ),
        ),
        // 体重（映射到主轴范围）
        LineChartBarData(
          spots: weightSpots
              .map((s) => FlSpot(
                  s.x, (s.y - wMin) / (wMax - wMin) * calRange))
              .toList(),
          isCurved: true,
          color: colorScheme.primary,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: true),
        ),
      ],
    ));
  }

  Future<void> _save() async {
    if (_busy) return; // 防重入
    if (_weightCtrl.text.isEmpty) return;
    final weight = double.tryParse(_weightCtrl.text);
    if (weight == null || weight <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的体重数字')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final db = await ref.read(recognize.databaseProvider.future);
      final repo = WeightLogRepository(db);
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await repo.insert(date: today, weightKg: weight);

      // 触发 TDEE 自适应校准（Sprint 3 T22）
      try {
        final config = await ref.read(appConfigProvider.future);
        if (config.tdeeAutoCalib) {
          final calibrator = TdeeCalibrator(db);
          final result = await calibrator.runAndApply(enabled: true);
          if (result.adjustmentKcal != 0 && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('TDEE 已调整：${result.reason}')),
            );
          }
        }
      } catch (_) {
        // 校准失败不影响体重记录主流程
      }

      _weightCtrl.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已记录体重')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
