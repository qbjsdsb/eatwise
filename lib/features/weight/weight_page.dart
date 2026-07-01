import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/database/database.dart';
import '../../data/repositories/weight_log_repository.dart';
import '../../nutrition/tdee_calibrator.dart';
import '../recognize/providers.dart' as recognize;

/// 体重记录页：录入体重 + fl_chart 折线趋势图
class WeightPage extends ConsumerStatefulWidget {
  const WeightPage({super.key});
  @override
  ConsumerState<WeightPage> createState() => _WeightPageState();
}

class _WeightPageState extends ConsumerState<WeightPage> {
  final _weightCtrl = TextEditingController();
  List<WeightLog> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = WeightLogRepository(db);
    _logs = await repo.getRecent(days: 30);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('体重记录')),
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
              FilledButton(onPressed: _save, child: const Text('记录')),
            ],
          ),
          const SizedBox(height: 24),
          if (_logs.length >= 2)
            SizedBox(height: 250, child: _buildChart())
          else
            const Center(child: Text('至少记录 2 次才能显示趋势图')),
          const SizedBox(height: 16),
          for (final log in _logs.reversed)
            ListTile(
              leading: const Icon(Icons.monitor_weight_outlined),
              title: Text('${log.weightKg.toStringAsFixed(1)} kg'),
              subtitle: Text(log.date),
            ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    // fl_chart 0.70.2: LineChartBarData(color: Color?) 单色，无 colors 列表
    final spots = <FlSpot>[];
    for (var i = 0; i < _logs.length; i++) {
      spots.add(FlSpot(i.toDouble(), _logs[i].weightKg));
    }
    final weights = _logs.map((l) => l.weightKg).toList();
    final minW = weights.reduce((a, b) => a < b ? a : b);
    final maxW = weights.reduce((a, b) => a > b ? a : b);
    final padding = (maxW - minW) * 0.1 + 0.5;

    return LineChart(LineChartData(
      gridData: const FlGridData(show: true),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey.shade300),
      ),
      minX: 0,
      maxX: (_logs.length - 1).toDouble(),
      minY: minW - padding,
      maxY: maxW + padding,
      titlesData: const FlTitlesData(
        bottomTitles:
            AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
          ),
        ),
        topTitles:
            AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: Colors.green,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: Colors.green.withValues(alpha: 0.1),
          ),
        ),
      ],
    ));
  }

  Future<void> _save() async {
    if (_weightCtrl.text.isEmpty) return;
    final weight = double.tryParse(_weightCtrl.text);
    if (weight == null || weight <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的体重数字')),
      );
      return;
    }
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
  }
}
