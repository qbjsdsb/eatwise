import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/date_format.dart';
import '../../core/util/food_name.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/database/database.dart';
import '../food_library/food_library_page.dart';

/// 餐次编辑 dialog 的返回结果
///
/// 字段语义：
/// - [servingG]：新份量（一定写入）
/// - [mealType]：新餐次（一定写入）
/// - [date]：新日期 'YYYY-MM-DD'（一定写入）
/// - [foodItemId]：新 foodItemId，null 表示不换食物（沿用原 id）
/// - [calories]/[proteinG]/[fatG]/[carbsG]：4 个营养值（一定写入）
///
/// 营养值来源（dialog 内部已计算好，调用方直接写入）：
/// - 用户没动 advanced + 没换食物 → 按份量比例重算
/// - 用户换了食物 → 用新食物 per100g × 份量重算
/// - 用户动了 advanced → 用 advanced 输入直接覆盖
class MealEditResult {
  final double servingG;
  final String mealType;
  final String date;
  final int? foodItemId;
  final double calories;
  final double proteinG;
  final double fatG;
  final double carbsG;

  const MealEditResult({
    required this.servingG,
    required this.mealType,
    required this.date,
    this.foodItemId,
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });
}

/// 餐次编辑 dialog：全字段 editable
///
/// 支持：
/// - 改份量（按比例重算营养值，原逻辑）
/// - 改餐次（breakfast/lunch/dinner/snack 4 选 1）
/// - 改日期（DatePicker）
/// - 换食物（跳食物库选，用新食物 per100g × 份量重算营养值）
/// - advanced 可展开：直接编辑 calories/protein/fat/carbs 4 个营养值
///
/// 营养值优先级（dialog 内部已处理，返回的 MealEditResult 直接写库即可）：
/// advanced 手动改 > 换食物重算 > 按份量比例重算
class MealEditDialog extends ConsumerStatefulWidget {
  const MealEditDialog({
    super.key,
    required this.mealLog,
    required this.currentFoodName,
  });

  /// 待编辑的 meal_log
  final MealLog mealLog;

  /// 当前食物名（编辑页 foodNames map 的值，未命中时是 '食物 #id'）

  final String currentFoodName;

  @override
  ConsumerState<MealEditDialog> createState() => _MealEditDialogState();
}

class _MealEditDialogState extends ConsumerState<MealEditDialog> {
  late final TextEditingController _servingCtrl;
  late final TextEditingController _calCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _fatCtrl;
  late final TextEditingController _carbsCtrl;

  late String _mealType;
  late DateTime _selectedDate;
  late String _foodName;
  // null 表示不换食物（沿用 mealLog.foodItemId）
  int? _newFoodItemId;
  // 换食物时的新 FoodItem 缓存（用于 per100g 重算）
  FoodItem? _newFood;
  // advanced 是否展开
  bool _advancedExpanded = false;
  // 用户是否手动改过 advanced 任意一个营养值（决定保存时是否覆盖比例重算）
  bool _nutritionOverridden = false;

  @override
  void initState() {
    super.initState();
    final m = widget.mealLog;
    _servingCtrl =
        TextEditingController(text: m.actualServingG.toStringAsFixed(0));
    _calCtrl =
        TextEditingController(text: m.actualCalories.toStringAsFixed(0));
    _proteinCtrl =
        TextEditingController(text: m.actualProteinG.toStringAsFixed(1));
    _fatCtrl = TextEditingController(text: m.actualFatG.toStringAsFixed(1));
    _carbsCtrl =
        TextEditingController(text: m.actualCarbsG.toStringAsFixed(1));
    _mealType = m.mealType;
    _foodName = widget.currentFoodName;
    _selectedDate = _parseDate(m.date);
    // 监听 advanced 营养值变化，标记 nutritionOverridden
    _calCtrl.addListener(_markOverride);
    _proteinCtrl.addListener(_markOverride);
    _fatCtrl.addListener(_markOverride);
    _carbsCtrl.addListener(_markOverride);
  }

  void _markOverride() {
    if (_advancedExpanded && !_nutritionOverridden) {
      setState(() => _nutritionOverridden = true);
    }
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

  /// 'YYYY-MM-DD' → DateTime（DatePicker 初始值，失败兜底 now）
  DateTime _parseDate(String date) {
    try {
      final parts = date.split('-').map(int.parse).toList();
      return DateTime(parts[0], parts[1], parts[2]);
    } catch (_) {
      return DateTime.now();
    }
  }

  /// 跳食物库选食物（pickForReuse 模式，pop 返回 FoodItem）
  Future<void> _pickFood() async {
    final food = await Navigator.of(context).push<FoodItem>(
      MaterialPageRoute(
        builder: (_) => const FoodLibraryPage(pickForReuse: true),
      ),
    );
    if (food == null) return;
    setState(() {
      _newFood = food;
      _newFoodItemId = food.id;
      _foodName = food.name.trim().isEmpty
          ? placeholderFoodName(food.id)
          : food.name.trim();
      // 换食物后清空 advanced override 标记（让重算逻辑生效）
      _nutritionOverridden = false;
      _advancedExpanded = false;
    });
    // 立即用新食物的 per100g × 当前份量重算 advanced 4 个值（预填，用户可继续调整）
    _recalcNutritionFromFood();
  }

  /// 用 _newFood 的 per100g × 当前份量重算 4 个营养值 controller
  /// 不修改 _nutritionOverridden（让用户后续手动改才标记 override）
  void _recalcNutritionFromFood() {
    final food = _newFood;
    if (food == null) return;
    final serving = double.tryParse(_servingCtrl.text.trim()) ?? 0;
    if (serving <= 0) return;
    final per100 = serving / 100.0;
    _setCtrlSilently(_calCtrl, (food.caloriesPer100g * per100).toStringAsFixed(0));
    _setCtrlSilently(
        _proteinCtrl, (food.proteinPer100g * per100).toStringAsFixed(1));
    _setCtrlSilently(_fatCtrl, (food.fatPer100g * per100).toStringAsFixed(1));
    _setCtrlSilently(
        _carbsCtrl, (food.carbsPer100g * per100).toStringAsFixed(1));
  }

  /// 静默更新 controller（不触发 _markOverride）
  void _setCtrlSilently(TextEditingController ctrl, String text) {
    _calCtrl.removeListener(_markOverride);
    _proteinCtrl.removeListener(_markOverride);
    _fatCtrl.removeListener(_markOverride);
    _carbsCtrl.removeListener(_markOverride);
    ctrl.text = text;
    _calCtrl.addListener(_markOverride);
    _proteinCtrl.addListener(_markOverride);
    _fatCtrl.addListener(_markOverride);
    _carbsCtrl.addListener(_markOverride);
  }

  /// 计算保存时的营养值
  /// 优先级：advanced override > 换食物重算 > 按份量比例重算
  ({double cal, double protein, double fat, double carbs})
      _computeNutrition() {
    if (_nutritionOverridden) {
      // 用户手动改了 advanced，直接用输入值
      return (
        cal: double.tryParse(_calCtrl.text.trim()) ?? 0,
        protein: double.tryParse(_proteinCtrl.text.trim()) ?? 0,
        fat: double.tryParse(_fatCtrl.text.trim()) ?? 0,
        carbs: double.tryParse(_carbsCtrl.text.trim()) ?? 0,
      );
    }
    if (_newFood != null) {
      // 换了食物但没动 advanced，用新食物 per100g × 份量重算
      final serving = double.tryParse(_servingCtrl.text.trim()) ?? 0;
      final per100 = serving / 100.0;
      return (
        cal: _newFood!.caloriesPer100g * per100,
        protein: _newFood!.proteinPer100g * per100,
        fat: _newFood!.fatPer100g * per100,
        carbs: _newFood!.carbsPer100g * per100,
      );
    }
    // 没换食物也没动 advanced，按份量比例重算（原逻辑）
    final m = widget.mealLog;
    final newServing = double.tryParse(_servingCtrl.text.trim()) ?? 0;
    if (m.actualServingG <= 0) {
      // 原份量异常，无法按比例 → 保留原营养值
      return (
        cal: m.actualCalories,
        protein: m.actualProteinG,
        fat: m.actualFatG,
        carbs: m.actualCarbsG,
      );
    }
    final ratio = newServing / m.actualServingG;
    return (
      cal: m.actualCalories * ratio,
      protein: m.actualProteinG * ratio,
      fat: m.actualFatG * ratio,
      carbs: m.actualCarbsG * ratio,
    );
  }

  void _save() {
    final serving = double.tryParse(_servingCtrl.text.trim());
    if (serving == null || serving <= 0) {
      showAppToast(context, '请输入有效份量');
      return;
    }
    final n = _computeNutrition();
    Navigator.of(context).pop(MealEditResult(
      servingG: serving,
      mealType: _mealType,
      date: formatYmd(_selectedDate),
      foodItemId: _newFoodItemId,
      calories: n.cal,
      proteinG: n.protein,
      fatG: n.fat,
      carbsG: n.carbs,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('编辑餐次'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 食物名（只读 + "换食物"按钮）
              // helperText 提示用户"识别错了可点此换食物"——原 UX 不明显，用户不知道可换
              InkWell(
                onTap: _pickFood,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '食物',
                    suffixIcon: Icon(Icons.swap_horiz),
                    helperText: '识别错了？点此换食物并自动重算营养',
                  ),
                  child: Text(
                    _foodName,
                    style: Theme.of(context).textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 份量
              TextField(
                controller: _servingCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '份量 (g)'),
              ),
              const SizedBox(height: 12),
              // 餐次切换器（复用共享 MealTypeSelector，与 recognize/manual_entry 一致）
              MealTypeSelector(
                value: _mealType,
                onChanged: (v) => setState(() => _mealType = v),
              ),
              const SizedBox(height: 12),
              // 日期选择器
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(formatYmd(_selectedDate)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
              ),
              const Divider(),
              // advanced 折叠区：直接改 4 个营养值
              InkWell(
                onTap: () => setState(
                    () => _advancedExpanded = !_advancedExpanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _advancedExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text('直接修改营养值',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const Spacer(),
                      if (_nutritionOverridden)
                        Text('已修改',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: cs.primary)),
                    ],
                  ),
                ),
              ),
              if (_advancedExpanded) ...[
                TextField(
                  controller: _calCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '热量 (kcal)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _proteinCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '蛋白 (g)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _fatCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '脂肪 (g)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _carbsCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '碳水 (g)'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
