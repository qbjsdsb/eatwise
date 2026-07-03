import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/food_name.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../recognize/providers.dart' as recognize;

/// 食物编辑页（编辑默认份量 + 营养素 + 来源标注）
/// china_fct/usda 来源只允许改默认份量；ai_recognized/manual 允许改全部
class FoodEditPage extends ConsumerStatefulWidget {
  const FoodEditPage({super.key, required this.foodItem});
  final FoodItem foodItem;

  @override
  ConsumerState<FoodEditPage> createState() => _FoodEditPageState();
}

class _FoodEditPageState extends ConsumerState<FoodEditPage> {
  late final TextEditingController _servingCtrl;
  late final TextEditingController _calCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _fatCtrl;
  late final TextEditingController _carbsCtrl;
  bool _busy = false; // 防重入：保存期间禁用按钮，避免双击重复写库
  bool _dirty = false; // 用户是否改过任意字段（PopScope 未保存确认用）

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void initState() {
    super.initState();
    final f = widget.foodItem;
    _servingCtrl =
        TextEditingController(text: f.defaultServingG.toStringAsFixed(0));
    _calCtrl =
        TextEditingController(text: f.caloriesPer100g.toStringAsFixed(0));
    _proteinCtrl =
        TextEditingController(text: f.proteinPer100g.toStringAsFixed(1));
    _fatCtrl = TextEditingController(text: f.fatPer100g.toStringAsFixed(1));
    _carbsCtrl =
        TextEditingController(text: f.carbsPer100g.toStringAsFixed(1));
    // 任意 controller 变化标记 dirty（PopScope 拦截返回用）
    _servingCtrl.addListener(_markDirty);
    _calCtrl.addListener(_markDirty);
    _proteinCtrl.addListener(_markDirty);
    _fatCtrl.addListener(_markDirty);
    _carbsCtrl.addListener(_markDirty);
  }

  @override
  void dispose() {
    _servingCtrl.dispose();
    _calCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    _carbsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.foodItem;
    final editable = f.source == 'ai_recognized' || f.source == 'manual';
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmDiscardChanges(context) && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
      appBar: AppBar(title: Text(f.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.source_outlined),
                  const SizedBox(width: 8),
                  Text('数据来源：${foodSourceLabel(f.source)} ${f.sourceVersion}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _servingCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '默认份量 (g)')),
          TextField(
              controller: _calCtrl,
              keyboardType: TextInputType.number,
              enabled: editable,
              decoration: const InputDecoration(labelText: '热量 /100g (kcal)')),
          TextField(
              controller: _proteinCtrl,
              keyboardType: TextInputType.number,
              enabled: editable,
              decoration: const InputDecoration(labelText: '蛋白质 /100g (g)')),
          TextField(
              controller: _fatCtrl,
              keyboardType: TextInputType.number,
              enabled: editable,
              decoration: const InputDecoration(labelText: '脂肪 /100g (g)')),
          TextField(
              controller: _carbsCtrl,
              keyboardType: TextInputType.number,
              enabled: editable,
              decoration: const InputDecoration(labelText: '碳水 /100g (g)')),
          const SizedBox(height: 24),
          if (editable)
            FilledButton(
                onPressed: _busy ? null : _saveAll,
                child: _busy
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary),
                      )
                    : const Text('保存全部修改')),
          if (!editable)
            FilledButton(
                onPressed: _busy ? null : _saveServingOnly,
                child: _busy
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary),
                      )
                    : const Text('保存默认份量')),
        ],
      ),
    ),
    );
  }

  Future<void> _saveServingOnly() async {
    if (_busy) return; // 防重入
    final serving = double.tryParse(_servingCtrl.text);
    if (serving == null || serving <= 0) {
      _showError('请输入有效的份量');
      return;
    }
    setState(() => _busy = true);
    try {
      final db = await ref.read(recognize.databaseProvider.future);
      final repo = FoodItemRepository(db);
      await repo.updateDefaultServing(widget.foodItem.id, serving);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存默认份量')));
        _dirty = false; // 清 dirty 让 PopScope 放行 programmatic pop
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAll() async {
    if (_busy) return; // 防重入
    final serving = double.tryParse(_servingCtrl.text);
    final cal = double.tryParse(_calCtrl.text);
    final protein = double.tryParse(_proteinCtrl.text);
    final fat = double.tryParse(_fatCtrl.text);
    final carbs = double.tryParse(_carbsCtrl.text);
    if (serving == null || serving <= 0) {
      _showError('请输入有效的份量');
      return;
    }
    if (cal == null || protein == null || fat == null || carbs == null) {
      _showError('热量/蛋白质/脂肪/碳水 必须为数字');
      return;
    }
    setState(() => _busy = true);
    try {
      final db = await ref.read(recognize.databaseProvider.future);
      final repo = FoodItemRepository(db);
      await repo.updateDefaultServing(widget.foodItem.id, serving);
      await repo.updateNutrients(
        id: widget.foodItem.id,
        caloriesPer100g: cal,
        proteinPer100g: protein,
        fatPer100g: fat,
        carbsPer100g: carbs,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存')));
        _dirty = false; // 清 dirty 让 PopScope 放行 programmatic pop
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
