import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';
import '../../data/repositories/recognition_feedback_repository.dart';
import '../recognize/providers.dart' as recognize;

/// 今日记录页（按餐次分组 + 编辑份量 + 删除 + 识别反馈）
class TodayMealsPage extends ConsumerStatefulWidget {
  const TodayMealsPage({super.key});
  @override
  ConsumerState<TodayMealsPage> createState() => _TodayMealsPageState();
}

class _TodayMealsPageState extends ConsumerState<TodayMealsPage> {
  late final String _today;
  List<MealLog> _meals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _load();
  }

  Future<void> _load() async {
    final repo = await ref.read(recognize.mealLogRepoProvider.future);
    _meals = await repo.getMealsByDate(_today);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // 按餐次分组
    final groups = <String, List<MealLog>>{};
    for (final m in _meals) {
      groups.putIfAbsent(m.mealType, () => []).add(m);
    }
    const order = ['breakfast', 'lunch', 'dinner', 'snack'];
    const labels = {
      'breakfast': '早餐',
      'lunch': '午餐',
      'dinner': '晚餐',
      'snack': '加餐'
    };

    return Scaffold(
      appBar: AppBar(title: const Text('今日记录')),
      body: _meals.isEmpty
          ? const Center(child: Text('今日暂无记录，去拍一张吧'))
          : ListView(
              children: [
                for (final type in order)
                  if (groups.containsKey(type)) ...[
                    _buildSectionHeader(labels[type]!),
                    for (final m in groups[type]!) _buildMealTile(m),
                  ],
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(label, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _buildMealTile(MealLog m) {
    return Dismissible(
      key: ValueKey(m.id),
      direction: DismissDirection.endToStart,
      background: Container(
          color: Colors.red,
          alignment: Alignment.centerRight,
          child: const Icon(Icons.delete, color: Colors.white)),
      onDismissed: (_) async {
        try {
          final repo = await ref.read(recognize.mealLogRepoProvider.future);
          await repo.deleteMealLog(m.id);
          if (mounted) setState(() => _meals.remove(m));
        } catch (e) {
          // 删除失败：回滚 UI（重新加载）+ 提示
          if (!mounted) return;
          await _load();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败：$e')),
          );
        }
      },
      child: ListTile(
        title: Text('食物ID ${m.foodItemId}'), // MVP：显示 ID（T9 食物库可反查名称）
        subtitle: Text(
            '${m.actualServingG.toStringAsFixed(0)}g · ${m.actualCalories.toStringAsFixed(0)} kcal'),
        trailing: m.recognitionConfidence != null
            ? IconButton(
                icon: const Icon(Icons.feedback_outlined),
                onPressed: () => _showFeedbackDialog(m),
              )
            : null,
        onTap: () => _showEditDialog(m),
      ),
    );
  }

  Future<void> _showEditDialog(MealLog m) async {
    final servingCtrl =
        TextEditingController(text: m.actualServingG.toStringAsFixed(0));
    double? result;
    try {
      result = await showDialog<double>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('编辑份量'),
          content: TextField(
              controller: servingCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '份量 (g)')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, double.tryParse(servingCtrl.text)),
              child: const Text('保存')),
          ],
        ),
      );
    } finally {
      servingCtrl.dispose();
    }
    if (result == null || result <= 0) return;
    // 除零保护：原份量为 0 时直接用新值（比例 1:1 重算为 0）
    if (m.actualServingG <= 0) return;
    final ratio = result / m.actualServingG;
    final repo = await ref.read(recognize.mealLogRepoProvider.future);
    await repo.updateMealLog(
      id: m.id,
      actualServingG: result,
      actualCalories: m.actualCalories * ratio,
      actualProteinG: m.actualProteinG * ratio,
      actualFatG: m.actualFatG * ratio,
      actualCarbsG: m.actualCarbsG * ratio,
    );
    if (mounted) _load();
  }

  Future<void> _showFeedbackDialog(MealLog m) async {
    final db = await ref.read(recognize.databaseProvider.future);
    final feedbackRepo = RecognitionFeedbackRepository(db);
    if (await feedbackRepo.hasFeedback(m.id)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已反馈过')));
      }
      return;
    }
    if (!mounted) return;
    final isCorrect = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('识别准不准？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('准')),
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('不准')),
        ],
      ),
    );
    if (isCorrect == null) return;
    if (!mounted) return;
    await feedbackRepo.insert(
      mealLogId: m.id,
      isCorrect: isCorrect,
      promptVersion: 'v1.0', // Sprint 1 prompts.dart 版本
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已记录反馈')));
    }
  }
}
