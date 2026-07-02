import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/prompts.dart';
import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/pending_recognition_repository.dart';
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
  Map<int, String> _foodNames = {};
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
    final mealRepo = await ref.read(recognize.mealLogRepoProvider.future);
    final meals = await mealRepo.getMealsByDate(_today);
    // 批量反查食物名
    final db = await ref.read(recognize.databaseProvider.future);
    final foodRepo = FoodItemRepository(db);
    final names = <int, String>{};
    for (final m in meals) {
      if (!names.containsKey(m.foodItemId)) {
        final food = await foodRepo.getById(m.foodItemId);
        names[m.foodItemId] = food?.name ?? '食物 #${m.foodItemId}';
      }
    }
    _meals = meals;
    _foodNames = names;
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
          color: Theme.of(context).colorScheme.errorContainer,
          alignment: Alignment.centerRight,
          child: Icon(Icons.delete,
              color: Theme.of(context).colorScheme.onErrorContainer)),
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
        leading: m.originalImagePath != null
            ? Image.file(File(m.originalImagePath!),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                    Icons.broken_image_outlined,
                    color: Theme.of(context).colorScheme.onSurfaceVariant))
            : Icon(Icons.restaurant_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
        title: Text(_foodNames[m.foodItemId] ?? '食物 #${m.foodItemId}'),
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

    // T45：不准时追加输入正确菜名 + 份量
    String? correctedDishName;
    double? correctedServingG;
    if (!isCorrect) {
      final correction = await showDialog<_CorrectionResult>(
        context: context,
        builder: (ctx) {
          // 【第2轮修正】：MealLog 无 foodItemName 字段（today_meals_page.dart:125 用 _foodNames map 反查）
          final nameCtrl = TextEditingController(text: _foodNames[m.foodItemId] ?? '');
          final servingCtrl = TextEditingController();
          return AlertDialog(
            title: const Text('请输入正确信息'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '正确菜名', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: servingCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '正确份量(g)', border: OutlineInputBorder()),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('跳过')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, _CorrectionResult(
                  nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
                  double.tryParse(servingCtrl.text.trim()),
                )),
                child: const Text('提交'),
              ),
            ],
          );
        },
      );
      if (correction != null) {
        correctedDishName = correction.name;
        correctedServingG = correction.servingG;
      }
    }
    if (!mounted) return;

    // T23：反查 prompt_version（优先从 pending_recognition 按 imagePath 查，
    // fallback Prompts.version）。拍照识别的 meal_log 有 original_image_path，
    // 对应 pending_recognition.image_path
    String promptVersion = Prompts.version;
    if (m.originalImagePath != null) {
      final pendingRepo = PendingRecognitionRepository(db);
      final pendingList = await pendingRepo.listAll();
      final match =
          pendingList.where((p) => p.imagePath == m.originalImagePath).toList();
      if (match.isNotEmpty && match.first.promptVersion != null) {
        promptVersion = match.first.promptVersion!;
      }
    }
    // T45：传 correctedDishName/ServingG
    await feedbackRepo.insert(
      mealLogId: m.id,
      isCorrect: isCorrect,
      correctedDishName: correctedDishName,
      correctedServingG: correctedServingG,
      promptVersion: promptVersion,
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已记录反馈')));
    }
  }
}

// 新增 _CorrectionResult 辅助类：
class _CorrectionResult {
  final String? name;
  final double? servingG;
  const _CorrectionResult(this.name, this.servingG);
}
