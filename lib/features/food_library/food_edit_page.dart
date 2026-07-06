import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/food_name.dart';
import '../../core/widgets/m3_widgets.dart';
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
  // 各字段校验错误（内联显示在 TextField 下方，替代 toast）
  String? _servingError;
  String? _calError;
  String? _proteinError;
  String? _fatError;
  String? _carbsError;

  void _markDirty() {
    // 已 dirty 且无任何错误时不重复 setState（保留原优化）
    if (_dirty &&
        _servingError == null &&
        _calError == null &&
        _proteinError == null &&
        _fatError == null &&
        _carbsError == null) {
      return;
    }
    setState(() {
      _dirty = true;
      // 用户重新编辑任一字段时清掉所有旧错误提示
      _servingError = null;
      _calError = null;
      _proteinError = null;
      _fatError = null;
      _carbsError = null;
    });
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
                  const ExcludeSemantics(child: Icon(Icons.source_outlined)),
                  const SizedBox(width: 8),
                  Text('数据来源：${foodSourceLabel(f.source)} ${f.sourceVersion}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _servingCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
              ],
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                  labelText: '默认份量 (g)', errorText: _servingError)),
          TextField(
              controller: _calCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
              ],
              autocorrect: false,
              enableSuggestions: false,
              enabled: editable,
              decoration: InputDecoration(
                  labelText: '热量 /100 g (kcal)', errorText: _calError)),
          TextField(
              controller: _proteinCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
              ],
              autocorrect: false,
              enableSuggestions: false,
              enabled: editable,
              decoration: InputDecoration(
                  labelText: '蛋白质 /100 g (g)', errorText: _proteinError)),
          TextField(
              controller: _fatCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
              ],
              autocorrect: false,
              enableSuggestions: false,
              enabled: editable,
              decoration: InputDecoration(
                  labelText: '脂肪 /100 g (g)', errorText: _fatError)),
          TextField(
              controller: _carbsCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
              ],
              autocorrect: false,
              enableSuggestions: false,
              enabled: editable,
              decoration: InputDecoration(
                  labelText: '碳水 /100 g (g)', errorText: _carbsError)),
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
      setState(() => _servingError = '份量需大于 0');
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = await ref.read(recognize.foodItemRepoProvider.future);
      await repo.updateDefaultServing(widget.foodItem.id, serving);
      if (mounted) {
        showAppToast(context, '已保存默认份量');
        _dirty = false; // 清 dirty 让 PopScope 放行 programmatic pop
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('保存失败: $e');
      _showError('保存失败，请稍后重试。');
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
    // 逐字段生成错误文案，一次性展示所有错误
    final newServingError =
        (serving == null || serving <= 0) ? '份量需大于 0' : null;
    final newCalError = cal == null ? '请输入有效数字' : null;
    final newProteinError = protein == null ? '请输入有效数字' : null;
    final newFatError = fat == null ? '请输入有效数字' : null;
    final newCarbsError = carbs == null ? '请输入有效数字' : null;
    if (newServingError != null ||
        newCalError != null ||
        newProteinError != null ||
        newFatError != null ||
        newCarbsError != null) {
      setState(() {
        _servingError = newServingError;
        _calError = newCalError;
        _proteinError = newProteinError;
        _fatError = newFatError;
        _carbsError = newCarbsError;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = await ref.read(recognize.foodItemRepoProvider.future);
      // 校验已通过，所有值非空（! 断言安全）
      await repo.updateDefaultServing(widget.foodItem.id, serving!);
      await repo.updateNutrients(
        id: widget.foodItem.id,
        caloriesPer100g: cal!,
        proteinPer100g: protein!,
        fatPer100g: fat!,
        carbsPer100g: carbs!,
      );
      if (mounted) {
        showAppToast(context, '已保存');
        _dirty = false; // 清 dirty 让 PopScope 放行 programmatic pop
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('保存失败: $e');
      _showError('保存失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    showAppToast(context, msg);
  }
}
