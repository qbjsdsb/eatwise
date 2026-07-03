import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai/prompts.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/pending_recognition_repository.dart';
import '../../data/repositories/recognition_feedback_repository.dart';
import '../recognize/providers.dart' as recognize;

/// 今日记录页（按餐次分组 + 编辑份量 + 删除 + 识别反馈）
class TodayMealsPage extends ConsumerStatefulWidget {
  const TodayMealsPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  ConsumerState<TodayMealsPage> createState() => TodayMealsPageState();
}

/// 公开 State：RecordsTabPage 通过 `GlobalKey<TodayMealsPageState>` 调用 refresh()
class TodayMealsPageState extends ConsumerState<TodayMealsPage> {
  late final String _today;
  List<MealLog> _meals = [];
  Map<int, String> _foodNames = {};
  bool _loading = true;
  bool _busy = false; // 编辑/删除防重入

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _load();
  }

  /// 公开刷新方法：切换到该页时由父容器调用
  void refresh() => _load();

  Future<void> _load() async {
    try {
      final mealRepo = await ref.read(recognize.mealLogRepoProvider.future);
      final meals = await mealRepo.getMealsByDate(_today);
      // 批量反查食物名
      final db = await ref.read(recognize.databaseProvider.future);
      final foodRepo = FoodItemRepository(db);
      final names = <int, String>{};
      for (final m in meals) {
        if (!names.containsKey(m.foodItemId)) {
          final food = await foodRepo.getById(m.foodItemId);
          final nm = food?.name ?? '';
          names[m.foodItemId] = nm.trim().isEmpty ? '食物 #${m.foodItemId}' : nm;
        }
      }
      _meals = meals;
      _foodNames = names;
    } catch (_) {
      // 加载失败保持空列表，避免 _loading 永久 true 卡死
      _meals = [];
      _foodNames = {};
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: widget.embedded ? null : AppBar(title: const Text('今日记录')),
        body: const Center(child: CircularProgressIndicator()),
      );
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
      appBar: widget.embedded ? null : AppBar(title: const Text('今日记录')),
      body: _meals.isEmpty
          ? _buildEmptyState()
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

  /// 空态：图标 + 文案 + CTA（与 dashboard 空态一致）
  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('今日暂无记录', style: TextStyle(color: cs.onSurface)),
            const SizedBox(height: 8),
            Text('点下方拍照按钮开始记录',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push('/recognize'),
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('去拍照'),
            ),
          ],
        ),
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
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(m.originalImagePath!),
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const LeadingIconContainer(Icons.broken_image_outlined)),
              )
            : const LeadingIconContainer(Icons.restaurant_rounded),
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
    if (_busy) return; // 防重入
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
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(recognize.mealLogRepoProvider.future);
      if (m.actualServingG <= 0) {
        // 原份量异常（≤0），无法按比例重算 → 直接用新份量，营养素保持原值
        await repo.updateMealLog(
          id: m.id,
          actualServingG: result,
          actualCalories: m.actualCalories,
          actualProteinG: m.actualProteinG,
          actualFatG: m.actualFatG,
          actualCarbsG: m.actualCarbsG,
        );
      } else {
        final ratio = result / m.actualServingG;
        await repo.updateMealLog(
          id: m.id,
          actualServingG: result,
          actualCalories: m.actualCalories * ratio,
          actualProteinG: m.actualProteinG * ratio,
          actualFatG: m.actualFatG * ratio,
          actualCarbsG: m.actualCarbsG * ratio,
        );
      }
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showFeedbackDialog(MealLog m) async {
    try {
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
        // controller 提到外层，try/finally 释放（避免泄漏）
        final nameCtrl =
            TextEditingController(text: _foodNames[m.foodItemId] ?? '');
        final servingCtrl = TextEditingController();
        try {
          final correction = await showDialog<_CorrectionResult>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('请输入正确信息'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: '正确菜名', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: servingCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: '正确份量(g)', border: OutlineInputBorder()),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('跳过')),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, _CorrectionResult(
                    nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
                    double.tryParse(servingCtrl.text.trim()),
                  )),
                  child: const Text('提交'),
                ),
              ],
            ),
          );
          if (correction != null) {
            correctedDishName = correction.name;
            correctedServingG = correction.servingG;
          }
        } finally {
          nameCtrl.dispose();
          servingCtrl.dispose();
        }
      }
      if (!mounted) return;

      // T23：反查 prompt_version（精准 where 查询，替代 listAll 全表扫）
      // 拍照识别的 meal_log 有 original_image_path，对应 pending_recognition.image_path
      String promptVersion = Prompts.version;
      if (m.originalImagePath != null) {
        final pendingRepo = PendingRecognitionRepository(db);
        final pending = await pendingRepo.getByImagePath(m.originalImagePath!);
        if (pending?.promptVersion != null) {
          promptVersion = pending!.promptVersion!;
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
    } catch (e) {
      // 整个反馈流程异常兜底：给用户反馈，不静默卡住
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('反馈失败：$e')));
      }
    }
  }
}

// 新增 _CorrectionResult 辅助类：
class _CorrectionResult {
  final String? name;
  final double? servingG;
  const _CorrectionResult(this.name, this.servingG);
}
