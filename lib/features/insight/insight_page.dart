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

  Future<void> _loadExisting() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = InsightRepository(db);
    final existing = await repo.find('weekly', _weekStart, _weekEnd);
    if (existing != null) {
      setState(() => _summary = existing.summaryText);
    }
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      final db = await ref.read(recognize.databaseProvider.future);
      final mealRepo = MealLogRepository(db);
      final weightRepo = WeightLogRepository(db);
      final profileRepo = ProfileRepository(db);

      final meals = await mealRepo.getRange(_weekStart, _weekEnd);
      final weights = await weightRepo.getRange(_weekStart, _weekEnd);
      final profile = await profileRepo.get();

      // 按日聚合热量
      final dailyCal = <double>[];
      for (var i = 0; i < 7; i++) {
        final date = _fmt(DateTime.parse(_weekStart).add(Duration(days: i)));
        final cal = meals
            .where((m) => m.date == date)
            .fold<double>(0, (s, m) => s + m.actualCalories);
        dailyCal.add(cal);
      }
      final dailyWeight = weights.map((w) => w.weightKg).toList();

      final apiKey = const String.fromEnvironment('GLM_API_KEY');
      if (apiKey.isEmpty) {
        setState(() =>
            _summary = '未配置 GLM_API_KEY（用 --dart-define=GLM_API_KEY=xxx 启动）');
        return;
      }
      final provider = GlmFlashProvider(apiKey: apiKey);
      final text = await provider.generateWeeklySummary({
        'daily_calories': dailyCal,
        'daily_weights': dailyWeight,
        'target_calories': profile.dailyCalorieTarget,
        'goal': profile.goal,
      });

      final insightRepo = InsightRepository(db);
      await insightRepo.regenerate(
        periodType: 'weekly',
        periodStart: _weekStart,
        periodEnd: _weekEnd,
        summaryText: text,
      );
      setState(() => _summary = text);
    } catch (e) {
      setState(() => _summary = '生成失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    if (_summary == null) return;
    final ctrl = TextEditingController(text: _summary);
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
      setState(() => _summary = edited);
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
}
