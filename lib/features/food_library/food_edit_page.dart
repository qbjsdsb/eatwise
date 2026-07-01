import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    return Scaffold(
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
                  Text('数据来源：${_sourceLabel(f.source)} ${f.sourceVersion}'),
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
                onPressed: _saveAll, child: const Text('保存全部修改')),
          if (!editable)
            FilledButton(
                onPressed: _saveServingOnly,
                child: const Text('保存默认份量')),
        ],
      ),
    );
  }

  Future<void> _saveServingOnly() async {
    final serving = double.tryParse(_servingCtrl.text);
    if (serving == null || serving <= 0) {
      _showError('请输入有效的份量');
      return;
    }
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = FoodItemRepository(db);
    await repo.updateDefaultServing(widget.foodItem.id, serving);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存默认份量')));
      Navigator.of(context).pop();
    }
  }

  Future<void> _saveAll() async {
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
      Navigator.of(context).pop();
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'china_fct':
        return '中国成分表';
      case 'usda':
        return 'USDA';
      case 'manual':
        return '手动';
      case 'ai_recognized':
        return 'AI 入库';
      default:
        return source;
    }
  }
}
