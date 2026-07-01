import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../recognize/providers.dart' as recognize;
import '../recognize/recognize_page.dart';
import 'today_meals_page.dart';

/// 看板：环形进度（热量）+ 三宏量进度条 + 余额预警
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  // 缓存 future 避免每次 build 重建 Future 导致反复查询 + 闪烁
  Future<({double cal, double protein, double fat, double carbs, int target, double proteinGoal, double fatGoal, double carbGoal})>?
      _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<({double cal, double protein, double fat, double carbs, int target, double proteinGoal, double fatGoal, double carbGoal})>
      _loadData() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final mealRepo = MealLogRepository(db);
    final profileRepo = ProfileRepository(db);
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final macros = await mealRepo.getMacrosByDate(today);
    final profile = await profileRepo.get();
    final proteinGoal = profile.proteinGPerKg * profile.weightKg;
    final fatGoal = profile.fatGPerKg * profile.weightKg;
    // carbGPerKg 可空（减脂/维持时碳水填剩余热量），clamp 避免负值
    final carbGoalRaw = profile.carbGPerKg != null
        ? profile.carbGPerKg! * profile.weightKg
        : (profile.dailyCalorieTarget - proteinGoal * 4 - fatGoal * 9) / 4;
    final carbGoal = carbGoalRaw < 0 ? 0.0 : carbGoalRaw;
    return (
      cal: macros.calories,
      protein: macros.protein,
      fat: macros.fat,
      carbs: macros.carbs,
      target: profile.dailyCalorieTarget,
      proteinGoal: proteinGoal,
      fatGoal: fatGoal,
      carbGoal: carbGoal,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const TodayMealsPage())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const RecognizePage())),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<
          ({
            double cal,
            double protein,
            double fat,
            double carbs,
            int target,
            double proteinGoal,
            double fatGoal,
            double carbGoal
          })>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('数据加载失败：${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red)),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snapshot.data!;
          final remain = d.target - d.cal;
          final overflow = remain < 0;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 环形进度（热量）
              SizedBox(
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(PieChartData(
                      sectionsSpace: 0,
                      centerSpaceRadius: 60,
                      sections: [
                        PieChartSectionData(
                          value: d.cal > d.target
                              ? d.target.toDouble()
                              : d.cal,
                          color: overflow ? Colors.red : Colors.green,
                          radius: 16,
                          showTitle: false,
                        ),
                        if (d.cal < d.target)
                          PieChartSectionData(
                            value: (d.target - d.cal).toDouble(),
                            color: Colors.grey.shade200,
                            radius: 16,
                            showTitle: false,
                          ),
                      ],
                    )),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(d.cal.toStringAsFixed(0),
                            style: Theme.of(context).textTheme.headlineMedium),
                        Text('/ ${d.target} kcal',
                            style: Theme.of(context).textTheme.bodySmall),
                        if (overflow)
                          Text('超 ${(-remain).toStringAsFixed(0)} kcal',
                              style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold)),
                        if (!overflow)
                          Text('余 ${remain.toStringAsFixed(0)} kcal',
                              style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // 三宏量进度条
              _macroBar('蛋白质', d.protein, d.proteinGoal, Colors.blue),
              _macroBar('脂肪', d.fat, d.fatGoal, Colors.orange),
              _macroBar('碳水', d.carbs, d.carbGoal, Colors.purple),
            ],
          );
        },
      ),
    );
  }

  Widget _macroBar(String label, double value, double goal, Color color) {
    final pct = goal > 0 ? (value / goal).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text('${value.toStringAsFixed(1)} / ${goal.toStringAsFixed(0)} g'),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
              value: pct,
              backgroundColor: color.withValues(alpha: 0.1),
              color: color,
              minHeight: 8),
        ],
      ),
    );
  }
}
