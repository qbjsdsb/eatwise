import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/date_format.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/repositories/food_item_repository.dart';
import '../recognize/providers.dart' as recognize;
import '../food_library/food_library_page.dart';

/// 手动录入页（兜底：搜库→选份量→记录；查不到→自定义→存库→记录）
class ManualEntryPage extends ConsumerStatefulWidget {
  const ManualEntryPage({super.key, this.initialName, this.modelDishName});
  final String? initialName; // 从识别页转来时预填菜名
  // 模型返回的原始菜名（用于自动学习：存为 alias，下次识别同名自动命中）
  // 与 initialName 区别：initialName 是预填到输入框让用户改的，modelDishName 是学习用的原始值
  final String? modelDishName;
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
  late bool _customMode;
  bool _busy = false; // 防重入：记录期间禁用按钮，避免双击重复写库
  bool _dirty = false; // 用户是否改过任意字段（PopScope 未保存确认用）
  // 各字段校验错误（内联显示在 TextField 下方，替代 toast）
  String? _servingError;
  String? _nameError;
  String? _calError;
  String? _proteinError;
  String? _fatError;
  String? _carbsError;

  void _markDirty() {
    // 已 dirty 且无任何错误时不重复 setState（保留原优化）
    if (_dirty &&
        _servingError == null &&
        _nameError == null &&
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
      _nameError = null;
      _calError = null;
      _proteinError = null;
      _fatError = null;
      _carbsError = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _customMode = widget.initialName != null;
    if (widget.initialName != null) _nameCtrl.text = widget.initialName!;
    // listener 在初始赋值之后注册，避免 initialName 赋值误触发 _dirty
    _servingCtrl.addListener(_markDirty);
    _nameCtrl.addListener(_markDirty);
    _calCtrl.addListener(_markDirty);
    _proteinCtrl.addListener(_markDirty);
    _fatCtrl.addListener(_markDirty);
    _carbsCtrl.addListener(_markDirty);
  }

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
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmDiscardChanges(context) && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
      appBar: AppBar(title: const Text('手动录入')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MealTypeSelector(
            value: _mealType,
            onChanged: (v) {
              setState(() => _mealType = v);
              _markDirty();
            },
          ),
          const SizedBox(height: 16),
          if (!_customMode) ...[
            // 搜库模式
            SectionTitle('选择食物'),
            Card(
              child: ListTile(
                leading: const LeadingIconContainer(Icons.search_rounded),
                title: Text(_selected?.name ?? '点击选择食物'),
                subtitle: _selected != null
                    ? Text(
                        '${_selected!.caloriesPer100g.toStringAsFixed(0)} kcal/100 g')
                    : null,
                trailing: const ExcludeSemantics(
                    child: Icon(Icons.chevron_right)),
                onTap: () async {
                  final result = await Navigator.of(context).push<FoodItem>(
                    MaterialPageRoute(
                        builder: (_) =>
                            const FoodLibraryPage(pickForReuse: true)),
                  );
                  if (!mounted) return;
                  if (result != null) {
                    setState(() => _selected = result);
                    _markDirty();
                  }
                },
              ),
            ),
            if (_selected != null) ...[
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
                      labelText: '份量 (g)', errorText: _servingError)),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: _busy ? null : _logFromLibrary,
                  child: _busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary),
                        )
                      : const Text('记录')),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _customMode = true),
              child: const Text('找不到？自定义输入'),
            ),
          ] else ...[
            // 自定义模式：基本信息 + 营养素分组
            SectionTitle('基本信息'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                            labelText: '食物名称', errorText: _nameError)),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _servingCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
                        ],
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                      labelText: '份量 (g)', errorText: _servingError)),
                  ],
                ),
              ),
            ),
            SectionTitle('营养素（每 100 g）'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                        controller: _calCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
                        ],
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                            labelText: '热量 (kcal)', errorText: _calError)),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _proteinCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
                        ],
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                            labelText: '蛋白质 (g)', errorText: _proteinError)),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _fatCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
                        ],
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                            labelText: '脂肪 (g)', errorText: _fatError)),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _carbsCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
                        ],
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                            labelText: '碳水 (g)', errorText: _carbsError)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: _busy ? null : _logCustom,
                child: _busy
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary),
                      )
                    : const Text('存库并记录')),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _customMode = false),
              child: const Text('返回搜库'),
            ),
          ],
        ],
      ),
    ),
    );
  }

  Future<void> _logFromLibrary() async {
    if (_busy) return; // 防重入
    if (_selected == null) return;
    final serving = double.tryParse(_servingCtrl.text);
    if (serving == null || serving <= 0) {
      setState(() => _servingError = '份量需大于 0');
      return;
    }
    setState(() => _busy = true);
    try {
      final ratio = serving / 100;
      final mealRepo = await ref.read(recognize.mealLogRepoProvider.future);
      final today = todayYmd();
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
        showAppToast(context,
            '已记录 ${_selected!.name} ${serving.toStringAsFixed(0)} g');
        _dirty = false; // 保存成功，允许返回不弹确认
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('记录失败: $e');
      if (mounted) {
        showAppToast(context, '记录失败，请稍后重试。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logCustom() async {
    if (_busy) return; // 防重入
    // 自定义模式：6 个字段需逐个校验
    final name = _nameCtrl.text.trim();
    final cal = double.tryParse(_calCtrl.text);
    final protein = double.tryParse(_proteinCtrl.text);
    final fat = double.tryParse(_fatCtrl.text);
    final carbs = double.tryParse(_carbsCtrl.text);
    final serving = double.tryParse(_servingCtrl.text);
    // 逐字段生成错误文案，一次性展示所有错误
    final newNameError = name.isEmpty ? '请输入食物名称' : null;
    final newCalError = cal == null ? '请输入有效数字' : null;
    final newProteinError = protein == null ? '请输入有效数字' : null;
    final newFatError = fat == null ? '请输入有效数字' : null;
    final newCarbsError = carbs == null ? '请输入有效数字' : null;
    final newServingError =
        (serving == null || serving <= 0) ? '份量需大于 0' : null;
    if (newNameError != null ||
        newCalError != null ||
        newProteinError != null ||
        newFatError != null ||
        newCarbsError != null ||
        newServingError != null) {
      setState(() {
        _nameError = newNameError;
        _calError = newCalError;
        _proteinError = newProteinError;
        _fatError = newFatError;
        _carbsError = newCarbsError;
        _servingError = newServingError;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final foodRepo = await ref.read(recognize.foodItemRepoProvider.future);
      final mealRepo = await ref.read(recognize.mealLogRepoProvider.future);

      // 先存库（source=manual，用 T9 新增的 insertManual 方法）
      // 自动学习：若 modelDishName 非空且与用户输入 name 不同，存为 alias，
      // 下次模型返回同名时自动命中（无需用户再手动录入）
      final userInputName = name;
      final modelDishName = widget.modelDishName?.trim();
      final aliases = (modelDishName != null &&
              modelDishName.isNotEmpty &&
              modelDishName != userInputName)
          ? <String>[modelDishName]
          : null;

      final foodId = await foodRepo.insertManual(
        name: userInputName,
        // 校验已通过，所有数值非空（! 断言安全）
        caloriesPer100g: cal!,
        proteinPer100g: protein!,
        fatPer100g: fat!,
        carbsPer100g: carbs!,
        aliases: aliases,
      );

      final ratio = serving! / 100;
      final today = todayYmd();
      // 上方 serving! 及 insertManual 内的 ! 已将 final 局部变量提升为非空
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
        showAppToast(context, '已存库并记录 ${_nameCtrl.text}');
        _dirty = false; // 保存成功，允许返回不弹确认
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('记录失败: $e');
      if (mounted) {
        showAppToast(context, '记录失败，请稍后重试。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
