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
import 'meal_edit_dialog.dart';

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
      // 批量反查食物名（原 N+1 逐条 getById → 1 次 IN 查询）
      final db = await ref.read(recognize.databaseProvider.future);
      final foodRepo = FoodItemRepository(db);
      final names = <int, String>{};
      final uniqueIds = meals.map((m) => m.foodItemId).toSet().toList();
      if (uniqueIds.isNotEmpty) {
        final foods = await foodRepo.getByIds(uniqueIds);
        for (final food in foods) {
          final nm = food.name.trim();
          names[food.id] = nm.isEmpty ? '食物 #${food.id}' : nm;
        }
        // 兜底：未命中的 id（理论不会，外键约束保证存在）
        for (final id in uniqueIds) {
          names.putIfAbsent(id, () => '食物 #$id');
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final type in order)
                  if (groups.containsKey(type)) ...[
                    _buildSectionHeader(labels[type]!, groups[type]!),
                    for (final m in groups[type]!) _buildMealCard(m),
                    const SizedBox(height: 8),
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

  /// 餐次分组标题：用全局 SectionTitle + trailing 显示餐次小计热量
  /// （复用共享组件，与 dashboard/me/settings 等页统一分组标题样式）
  Widget _buildSectionHeader(String label, List<MealLog> meals) {
    final cs = Theme.of(context).colorScheme;
    final sum = meals.fold(0.0, (s, m) => s + m.actualCalories);
    return SectionTitle(
      label,
      trailing: Text('${sum.toStringAsFixed(0)} kcal',
          style: TextStyle(color: cs.onSurfaceVariant)),
    );
  }

  Widget _buildMealCard(MealLog m) {
    final cs = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(m.id),
      direction: DismissDirection.endToStart,
      background: Container(
          color: cs.errorContainer,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: Icon(Icons.delete, color: cs.onErrorContainer)),
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
      // 用 MD3 Card.outlined 变体（替代手写 elevation:0 + outline），
      // 圆角 12（MD3 medium）统一 dashboard，内 padding 16 统一 dashboard
      child: Card.outlined(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showEditDialog(m),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 缩略图（圆角 8 = MD3 small）
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: m.originalImagePath != null
                      ? Image.file(File(m.originalImagePath!),
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 56,
                            height: 56,
                            color: cs.primaryContainer,
                            child: Icon(Icons.broken_image_outlined,
                                color: cs.onPrimaryContainer, size: 24),
                          ))
                      : Container(
                          width: 56,
                          height: 56,
                          color: cs.primaryContainer,
                          child: Icon(Icons.restaurant_rounded,
                              color: cs.onPrimaryContainer, size: 24),
                        ),
                ),
                const SizedBox(width: 12),
                // 名称 + 份量 + 营养素
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _foodNames[m.foodItemId] ?? '食物 #${m.foodItemId}',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // 份量 + 热量
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          _chip(Icons.scale_outlined,
                              '${m.actualServingG.toStringAsFixed(0)} g',
                              cs.secondaryContainer,
                              cs.onSecondaryContainer),
                          _chip(Icons.local_fire_department_outlined,
                              '${m.actualCalories.toStringAsFixed(0)} kcal',
                              cs.tertiaryContainer,
                              cs.onTertiaryContainer),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 三大宏量营养素：用 MacroColors 跨页统一配色（蛋白=tertiary/脂肪=secondary/碳水=primary）
                      Row(
                        children: [
                          _macroDot('蛋白', m.actualProteinG, MacroColors.protein(cs)),
                          const SizedBox(width: 10),
                          _macroDot('脂肪', m.actualFatG, MacroColors.fat(cs)),
                          const SizedBox(width: 10),
                          _macroDot('碳水', m.actualCarbsG, MacroColors.carb(cs)),
                        ],
                      ),
                    ],
                  ),
                ),
                // 反馈按钮：恢复 48x48 触摸目标（MD3 可访问性要求）
                if (m.recognitionConfidence != null)
                  IconButton(
                    icon: const Icon(Icons.feedback_outlined, size: 20),
                    tooltip: '识别反馈',
                    onPressed: () => _showFeedbackDialog(m),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 小标签 chip：图标 + 文字（圆角 8 = MD3 small）
  Widget _chip(
      IconData icon, String text, Color bg, Color fg) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 3),
          Text(text,
              style: textTheme.labelSmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  /// 宏量营养素小圆点 + 数值
  Widget _macroDot(String label, double g, Color color) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text('$label ${g.toStringAsFixed(1)}g',
            style: textTheme.labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Future<void> _showEditDialog(MealLog m) async {
    if (_busy) return; // 防重入
    // dialog 在 root Navigator，避免 tab 页嵌套 Navigator 误 pop（陷阱 7）
    final result = await showDialog<MealEditResult>(
      context: context,
      builder: (ctx) => MealEditDialog(
        mealLog: m,
        currentFoodName: _foodNames[m.foodItemId] ?? '食物 #${m.foodItemId}',
      ),
    );
    if (result == null) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(recognize.mealLogRepoProvider.future);
      // 全字段更新：份量 + 营养值（dialog 内已按优先级算好）+ 餐次 + 日期
      // foodItemId 仅在换了食物时传（null 不更新，沿用原值）
      await repo.updateMealLog(
        id: m.id,
        actualServingG: result.servingG,
        actualCalories: result.calories,
        actualProteinG: result.proteinG,
        actualFatG: result.fatG,
        actualCarbsG: result.carbsG,
        date: result.date,
        mealType: result.mealType,
        foodItemId: result.foodItemId,
      );
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
      // dialog 在 root Navigator，准/不准按钮必须用 dialog 的 ctx pop；
      // 用页面 context 会 pop 掉 RecordsTabPage 嵌套 Navigator 栈顶 → 黑屏
      final isCorrect = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('识别准不准？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('准')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
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

      // 批次 3：反馈闭环回流——用户纠正菜名后，把 AI 错误识别名作为正确菜的别名
      // 下次 AI 识别返回错误名时，findByNameOrAlias 命中别名，直接返回正确菜营养数据
      // best-effort：失败不影响反馈记录（反馈已落库），仅放弃别名学习
      if (!isCorrect && correctedDishName != null && correctedDishName.isNotEmpty) {
        try {
          final foodRepo = FoodItemRepository(db);
          final aiName = _foodNames[m.foodItemId];
          // AI 识别名有效且与纠正名不同（归一化比较）→ 加别名或创建新条目
          if (aiName != null &&
              aiName.isNotEmpty &&
              !aiName.startsWith('食物 #') &&
              aiName.trim().toLowerCase() !=
                  correctedDishName.trim().toLowerCase()) {
            // 查正确菜是否在库：只用精确匹配（name/alias 归一化相等），
            // 不走模糊匹配——避免"雪花啤酒"模糊命中"雪碧"后把"雪碧"写成
            // 雪碧的别名导致反向错配（永久错配且无法自愈）。
            final correctFood =
                await foodRepo.findExactByNameOrAlias(correctedDishName);
            if (correctFood != null && correctFood.id != m.foodItemId) {
              // 在库且不是同一条记录 → 把错误名 A 作为正确菜 B 的别名
              await foodRepo.addAlias(correctFood.id, aiName);
            } else if (correctFood == null) {
              // P2-2：库里无此菜 → 创建新条目（source='manual'，自进化闭环）
              // 营养用 meal_log 实际值反算 per100g，aliases 传 AI 错误名（下次 AI 返回错误名时命中别名）
              // 仅在营养数据有效时创建（防 0 卡污染库）
              final servingG = correctedServingG ?? m.actualServingG;
              if (servingG > 0 && m.actualCalories > 0) {
                final per100 = 100.0 / servingG;
                await foodRepo.insertManual(
                  name: correctedDishName,
                  caloriesPer100g: m.actualCalories * per100,
                  proteinPer100g: m.actualProteinG * per100,
                  fatPer100g: m.actualFatG * per100,
                  carbsPer100g: m.actualCarbsG * per100,
                  aliases: [aiName],
                );
              }
            }
          }
        } catch (_) {
          // best-effort：别名回流失败不影响反馈记录
        }
      }

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
