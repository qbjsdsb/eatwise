import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../nutrition/recommendation_service.dart';
import '../backup/backup_page.dart';
import '../food_library/food_library_page.dart';
import '../insight/insight_page.dart';
import '../manual_entry/manual_entry_page.dart';
import '../profile/profile_page.dart';
import '../recognize/providers.dart' as recognize;
import '../recognize/recognize_page.dart';
import '../settings/settings_page.dart';
import '../weight/weight_page.dart';
import 'today_meals_page.dart';

/// 看板：环形进度（热量）+ 三宏量进度条 + 余额预警
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  // 缓存 future 避免每次 build 重建 Future 导致反复查询 + 闪烁
  Future<({double cal, double protein, double fat, double carbs, int target, double proteinGoal, double fatGoal, double carbGoal, double weightKg})>?
      _future;
  // C 智能推荐：独立 future，避免影响主数据加载性能
  Future<List<RecommendedFood>>? _recFuture;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
    _recFuture = _loadRecommendations();
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
    final remaining = await service.getDailyRemaining(today);
    return service.recommend(remaining: remaining, limit: 5);
  }

  Future<({double cal, double protein, double fat, double carbs, int target, double proteinGoal, double fatGoal, double carbGoal, double weightKg})>
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
      weightKg: profile.weightKg,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const TodayMealsPage())),
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const RecognizePage()));
          // 返回后刷新主数据 + 推荐（拍照识别记录后热量/宏量/推荐都应更新）
          if (mounted) {
            setState(() {
              _future = _loadData();
              _recFuture = _loadRecommendations();
            });
          }
        },
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
            double carbGoal,
            double weightKg
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
              _macroBar('蛋白质', d.protein, d.proteinGoal, Colors.blue, d.weightKg),
              _macroBar('脂肪', d.fat, d.fatGoal, Colors.orange, d.weightKg),
              _macroBar('碳水', d.carbs, d.carbGoal, Colors.purple, d.weightKg),
              // C 智能推荐卡片
              const SizedBox(height: 16),
              _buildRecommendationCard(d),
            ],
          );
        },
      ),
    );
  }

  /// C 智能推荐卡片（基于当日剩余额度推荐食物填补缺口）
  Widget _buildRecommendationCard(
      ({double cal, double protein, double fat, double carbs, int target, double proteinGoal, double fatGoal, double carbGoal, double weightKg}) d) {
    return FutureBuilder<List<RecommendedFood>>(
      future: _recFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          // 推荐加载失败不影响主看板，静默不显示
          return const SizedBox.shrink();
        }
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final recs = snap.data!;
        final remain = d.target - d.cal;
        final proteinRemain = d.proteinGoal - d.protein;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 20, color: Colors.amber),
                    const SizedBox(width: 8),
                    Text('智能推荐',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  proteinRemain > 5
                      ? '今日还差 ${proteinRemain.toStringAsFixed(0)}g 蛋白质，推荐：'
                      : remain > 0
                          ? '今日还可摄入 ${remain.toStringAsFixed(0)} kcal，推荐：'
                          : '今日热量已达标，推荐低卡食物：',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                for (final rec in recs)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(rec.food.name),
                    subtitle: Text(
                        '${rec.food.caloriesPer100g.toStringAsFixed(0)} kcal/100g · 蛋白 ${rec.food.proteinPer100g.toStringAsFixed(1)}g',
                        style: const TextStyle(fontSize: 11)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(rec.reason,
                          style: TextStyle(fontSize: 10, color: Colors.green.shade700)),
                    ),
                    onTap: () async {
                      // 点击推荐 → 跳手动录入页快速记录（预填菜名）
                      // 返回后刷新主数据 + 推荐（用户记录后热量/宏量/推荐都应更新）
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ManualEntryPage(
                          initialName: rec.food.name,
                        ),
                      ));
                      if (mounted) {
                        setState(() {
                          _future = _loadData();
                          _recFuture = _loadRecommendations();
                        });
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.green),
            child: Text('EatWise',
                style: TextStyle(color: Colors.white, fontSize: 24)),
          ),
          _drawerItem(Icons.person_outline, '个人档案', () => const ProfilePage()),
          _drawerItem(Icons.monitor_weight_outlined, '体重记录', () => const WeightPage()),
          _drawerItem(Icons.insights_outlined, 'AI 周报', () => const InsightPage()),
          _drawerItem(Icons.restaurant_menu_outlined, '食物库', () => const FoodLibraryPage()),
          _drawerItem(Icons.edit_note_outlined, '手动录入', () => const ManualEntryPage()),
          _drawerItem(Icons.backup_outlined, '数据备份', () => const BackupPage()),
          _drawerItem(Icons.settings_outlined, '设置', () => const SettingsPage()),
        ],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, Widget Function() pageBuilder) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.of(context).pop(); // 先关 Drawer
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => pageBuilder()));
      },
    );
  }

  Widget _macroBar(String label, double value, double goal, Color color, double weightKg) {
    final pct = goal > 0 ? (value / goal).clamp(0.0, 1.0) : 0.0;
    final gPerKg = weightKg > 0 ? (value / weightKg).toStringAsFixed(1) : '-';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text('${value.toStringAsFixed(1)} / ${goal.toStringAsFixed(0)} g ($gPerKg g/kg)'),
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
