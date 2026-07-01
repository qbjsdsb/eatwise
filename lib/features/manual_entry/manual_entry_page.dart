import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../recognize/providers.dart' as recognize;
import '../food_library/food_library_page.dart';

/// 手动录入页（兜底：搜库→选份量→记录；查不到→自定义→存库→记录）
class ManualEntryPage extends ConsumerStatefulWidget {
  const ManualEntryPage({super.key});
  @override
  ConsumerState<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends ConsumerState<ManualEntryPage> {
  String _mealType = 'snack';
  FoodItem? _selected;
  final _servingCtrl = TextEditingController(text: '100');

  // 自定义输入字段
  final _nameCtrl = TextEditingController();
  final _calCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  bool _customMode = false;

  @override
  void dispose() {
    _servingCtrl.dispose();
    _nameCtrl.dispose();
    _calCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    _carbsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('手动录入')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButton<String>(
            value: _mealType,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'breakfast', child: Text('早餐')),
              DropdownMenuItem(value: 'lunch', child: Text('午餐')),
              DropdownMenuItem(value: 'dinner', child: Text('晚餐')),
              DropdownMenuItem(value: 'snack', child: Text('加餐')),
            ],
            onChanged: (v) => setState(() => _mealType = v ?? _mealType),
          ),
          const SizedBox(height: 16),
          if (!_customMode) ...[
            // 搜库模式
            ListTile(
              title: Text(_selected?.name ?? '点击选择食物'),
              subtitle: _selected != null
                  ? Text(
                      '${_selected!.caloriesPer100g.toStringAsFixed(0)} kcal/100g')
                  : null,
              trailing: const Icon(Icons.search),
              onTap: () async {
                final result = await Navigator.of(context).push<FoodItem>(
                  MaterialPageRoute(
                      builder: (_) =>
                          const FoodLibraryPage(pickForReuse: true)),
                );
                if (result != null) setState(() => _selected = result);
              },
            ),
            if (_selected != null) ...[
              TextField(
                  controller: _servingCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '份量 (g)')),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: _logFromLibrary, child: const Text('记录')),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _customMode = true),
              child: const Text('找不到？自定义输入'),
            ),
          ] else ...[
            // 自定义模式
            TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: '食物名称')),
            TextField(
                controller: _calCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '热量 /100g (kcal)')),
            TextField(
                controller: _proteinCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '蛋白质 /100g (g)')),
            TextField(
                controller: _fatCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '脂肪 /100g (g)')),
            TextField(
                controller: _carbsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '碳水 /100g (g)')),
            TextField(
                controller: _servingCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '份量 (g)')),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: _logCustom, child: const Text('存库并记录')),
            TextButton(
              onPressed: () => setState(() => _customMode = false),
              child: const Text('返回搜库'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _logFromLibrary() async {
    if (_selected == null) return;
    final serving = double.tryParse(_servingCtrl.text);
    if (serving == null || serving <= 0) {
      _showError('请输入有效的份量');
      return;
    }
    final ratio = serving / 100;
    final db = await ref.read(recognize.databaseProvider.future);
    final mealRepo = MealLogRepository(db);
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await mealRepo.insertMealLog(
      date: today,
      mealType: _mealType,
      foodItemId: _selected!.id,
      actualServingG: serving,
      actualCalories: _selected!.caloriesPer100g * ratio,
      actualProteinG: _selected!.proteinPer100g * ratio,
      actualFatG: _selected!.fatPer100g * ratio,
      actualCarbsG: _selected!.carbsPer100g * ratio,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '已记录 ${_selected!.name} ${serving.toStringAsFixed(0)}g')));
      Navigator.of(context).pop();
    }
  }

  Future<void> _logCustom() async {
    if (_nameCtrl.text.isEmpty) {
      _showError('请输入食物名称');
      return;
    }
    // 自定义模式：5 个数值字段需逐个校验
    final cal = double.tryParse(_calCtrl.text);
    final protein = double.tryParse(_proteinCtrl.text);
    final fat = double.tryParse(_fatCtrl.text);
    final carbs = double.tryParse(_carbsCtrl.text);
    final serving = double.tryParse(_servingCtrl.text);
    if (cal == null || protein == null || fat == null || carbs == null) {
      _showError('热量/蛋白质/脂肪/碳水 必须为数字');
      return;
    }
    if (serving == null || serving <= 0) {
      _showError('请输入有效的份量');
      return;
    }
    final db = await ref.read(recognize.databaseProvider.future);
    final foodRepo = FoodItemRepository(db);
    final mealRepo = MealLogRepository(db);

    // 先存库（source=manual，用 T9 新增的 insertManual 方法）
    final foodId = await foodRepo.insertManual(
      name: _nameCtrl.text,
      caloriesPer100g: cal,
      proteinPer100g: protein,
      fatPer100g: fat,
      carbsPer100g: carbs,
    );

    final ratio = serving / 100;
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await mealRepo.insertMealLog(
      date: today,
      mealType: _mealType,
      foodItemId: foodId,
      actualServingG: serving,
      actualCalories: cal * ratio,
      actualProteinG: protein * ratio,
      actualFatG: fat * ratio,
      actualCarbsG: carbs * ratio,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已存库并记录 ${_nameCtrl.text}')));
      Navigator.of(context).pop();
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
