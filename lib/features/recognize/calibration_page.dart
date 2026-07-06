import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/vision_provider.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/repositories/food_item_repository.dart';
import '../manual_entry/manual_entry_page.dart';
import 'dish_name_editor.dart';

/// 校准页：按置信度分级
/// - 置信度 ≥ 0.85 且单品：允许"一键记录"跳过校准
/// - 置信度 < 0.6：强制校准，标注"待确认"
/// - 中间区 0.6-0.85：默认进校准页，提供"信任 AI"快捷按钮
class CalibrationPage extends StatefulWidget {
  final VisionRecognitionResult recognitionResult;
  final NutritionResult? singleNutrition;
  final CompositeNutritionResult? compositeNutrition;
  final FoodItemRepository foodItemRepo;
  final Future<void> Function(double servingG, double calories, double protein, double fat, double carbs, {String? componentsSnapshot}) onConfirm;
  // 智能份量校准：基于历史记录的中位数（B 功能）。
  // 非空时滑块初值用它（而非 AI 估算 mid），减少手动拖滑块。
  // 仅单品路径生效；复合菜份量按组分，不走此参数。
  final double? suggestedServingG;
  // 改菜名→搜库→重算 用的 NutritionLookup 实例（recognize_page 注入）
  // null 时隐藏"改菜名"按钮（单品路径才有此按钮；复合菜改菜名语义复杂，跳过）
  final NutritionLookup? nutritionLookup;
  // AI 兜底营养（foodItemId=0，calories 对应 mid 份量）。
  // v0.28.0：库不参与热量计算，aiFallback 非空时单品路径热量固定 = AI 值，
  // 复合菜路径用 food_components 自洽缩放后累加；为 null 时（老调用方）查库命中分支走原 ratio 逻辑。
  final NutritionResult? aiFallbackNutrition;

  const CalibrationPage({
    super.key,
    required this.recognitionResult,
    this.singleNutrition,
    this.compositeNutrition,
    required this.foodItemRepo,
    required this.onConfirm,
    this.suggestedServingG,
    this.nutritionLookup,
    this.aiFallbackNutrition,
  });

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> with DishNameEditor<CalibrationPage> {
  late double _servingG;
  late bool _canSkipCalibration;
  // v0.28.0：复合菜校准状态——组分滑块影响热量
  // _componentServings: 组分索引 → 用户拖动后的份量 g（null 表示未拖动，用 estimatedG）
  // _scaledComponents: 自洽缩放后的组分列表（initState 一次性处理，用户拖滑块后不再缩放）
  final Map<int, double> _componentServings = {}; // 组分索引 → 份量 g
  List<FoodComponent> _scaledComponents = const []; // v1.11 自洽缩放后的组分
  // v1.3：同物多份数量步进器（解决拍两罐可乐只识别一罐的问题）
  // _quantity 当前数量，_perUnitG 单份克数；仅单品路径 + perUnitG > 0 时显示步进器
  // 份量联动：调数量 → _servingG = perUnitG × quantity；拖滑块 → 反推 _quantity
  late int _quantity;
  late double _perUnitG;
  // 防重入：写入 meal_log 期间禁用按钮，避免双击重复记录
  bool _isRecording = false;
  bool _dirty = false; // 用户是否拖过滑块（PopScope 未保存确认用）

  // 改菜名后的可变状态（initState 从 widget 初始化，改菜名命中后 setState 替换）
  // 让菜名和营养展示读 state 而非 widget 字段，实现"改菜名后 UI 实时刷新"
  late String _currentDishName;
  late NutritionResult? _currentNutrition;
  bool _isRenaming = false; // 改菜名防重入
  // v2 改动 E：用户手动编辑的营养值覆盖（用户最终兜底）。
  // 键 'cal'/'protein'/'fat'/'carbs'，值是 actualXxx（摄入值，对应 servingG 份量）。
  // _applyUserOverrides 优先用 _userOverrides，否则用 AI 估算值。
  // 编辑后 _dirty=true（PopScope 未保存确认），onConfirm 传用户输入值。
  final Map<String, double> _userOverrides = {};

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  /// v2 改动 E：用户手动编辑值优先（最终兜底覆盖 AI 估算）。
  /// 未编辑的字段保持 AI 估算值（_computeCurrentNutrition 的结果）。
  (double, double, double, double) _applyUserOverrides(
    double cal,
    double protein,
    double fat,
    double carbs,
  ) {
    return (
      _userOverrides['cal'] ?? cal,
      _userOverrides['protein'] ?? protein,
      _userOverrides['fat'] ?? fat,
      _userOverrides['carbs'] ?? carbs,
    );
  }

  /// v0.28.0：当前份量 g（用于写库 servingG + UI 份量显示）
  /// 单品路径：_servingG（= AI mid，固定不调）
  /// 复合菜路径：sum(各组分滑块值)
  double _currentServingG() {
    if (_scaledComponents.isEmpty) return _servingG;
    double total = 0;
    for (var i = 0; i < _scaledComponents.length; i++) {
      total += _componentServings[i] ?? _scaledComponents[i].estimatedG;
    }
    return total;
  }

  /// v0.28.0：核心热量计算（预览/确认/编辑对话框初始值三处共用，保证一致）
  ///
  /// 架构：完全抛弃库参与热量计算，库仅作 food_item_id 解析兜底。
  /// - 复合菜路径（_scaledComponents 有营养，sumCal > 0）：
  ///   总热量 = sum(各组分 per100g × 用户拖动 g / 100)
  ///   per100g 基于 component.estimatedG 反算（硬约束 #4 精神）
  /// - 单品路径（无组分 或 组分无营养）：
  ///   热量固定 = AI 值（aiFallback.calories），用户只能点击营养值手动编辑
  /// - 向后兼容（aiFallback == null + 查库命中）：走原 ratio 逻辑（老调用方）
  (double, double, double, double) _computeCurrentNutrition() {
    final components = _scaledComponents;
    // 复合菜路径：组分有营养字段时按组分 per100g × g / 100 累加
    final sumCal = components.fold(0.0, (s, c) => s + c.calories);
    if (components.isNotEmpty && sumCal > 0) {
      double cal = 0, protein = 0, fat = 0, carbs = 0;
      for (var i = 0; i < components.length; i++) {
        final g = _componentServings[i] ?? components[i].estimatedG;
        cal += components[i].caloriesPer100g * g / 100;
        protein += components[i].proteinPer100g * g / 100;
        fat += components[i].fatPer100g * g / 100;
        carbs += components[i].carbsPer100g * g / 100;
      }
      return _applyUserOverrides(cal, protein, fat, carbs);
    }
    // 单品路径：AI 值固定（库不参与热量计算）
    final ai = widget.aiFallbackNutrition;
    if (ai != null) {
      return _applyUserOverrides(ai.calories, ai.proteinG, ai.fatG, ai.carbsG);
    }
    // 向后兼容：aiFallback 为 null（老调用方）+ 查库命中 → 走原 ratio 逻辑
    if (_currentNutrition != null) {
      final n = _currentNutrition!;
      final mid = widget.recognitionResult.estimatedWeightGMid;
      final ratio = mid > 0 ? _servingG / mid : 1.0;
      return _applyUserOverrides(
        n.calories * ratio,
        n.proteinG * ratio,
        n.fatG * ratio,
        n.carbsG * ratio,
      );
    }
    return (0, 0, 0, 0);
  }

  /// v1.3：动态滑块上限。多份场景 perUnitG×20 可能超 1000（如 5 碗米饭=1250g），
  /// 静态 max=1000 会被 clamp 致静默少算。perUnitG>0 时按 perUnitG×20 扩到上限 5000，
  /// 否则用默认 1000（复合菜/无 perUnitG 的单品）。
  double get _sliderMax {
    if (_perUnitG > 0) {
      return (_perUnitG * 20).clamp(1000.0, 5000.0);
    }
    return 1000.0;
  }

  @override
  void initState() {
    super.initState();
    _quantity = widget.recognitionResult.quantity;
    _perUnitG = widget.recognitionResult.perUnitG;
    // v2.1 修复：单品路径初始用 AI 估算 mid，不再用历史中位数预填
    // 原因：历史中位数预填导致 initial servingG ≠ mid，actualCalories 按比例缩放后
    // 偏离 AI 推理值（如 AI 推理 480 kcal/mid=350g，历史预填 278g → 显示 381 kcal），
    // 用户感知"AI 推理值被静默修改"。改用 mid 后 initial actualCalories = AI 推理值，
    // 用户拖滑块调整份量时才按比例缩放。
    // 多份场景同样用 mid（与原逻辑一致）。
    // suggestedServingG 参数保留（构造函数兼容），但 initState 不再读它。
    _servingG = widget.recognitionResult.estimatedWeightGMid.clamp(0.0, _sliderMax);
    // perUnitG>0 时反推 quantity（保持步进器与份量一致）
    if (_perUnitG > 0) {
      final q = (_servingG / _perUnitG).round();
      if (q >= 1 && q <= 20) _quantity = q;
    }
    _canSkipCalibration =
        widget.recognitionResult.confidence >= 0.85 && widget.recognitionResult.isSingleItem;
    // v0.28.0：复合菜组分初始化——从 AI 推理的 foodComponents 读取（不再用库 componentHits）
    // 自洽缩放：AI 返回的组分热量之和可能 ≠ estimatedCalories，按比例缩放各组分
    // 使 sum(component.calories) = aiFallback.calories（用户拖滑块后不再缩放）
    final rawComponents = widget.recognitionResult.foodComponents;
    final ai = widget.aiFallbackNutrition;
    if (rawComponents.isNotEmpty && ai != null && ai.calories > 0) {
      final sumCal = rawComponents.fold(0.0, (s, c) => s + c.calories);
      if (sumCal > 0) {
        final diff = (sumCal - ai.calories).abs() / ai.calories;
        if (diff > 0.01) {
          // 偏差 > 1% → 按比例缩放各组分（calories/proteinG/fatG/carbsG 同比，per100g 不变）
          final scale = ai.calories / sumCal;
          _scaledComponents = rawComponents.map((c) => c.scaled(scale)).toList();
        } else {
          _scaledComponents = rawComponents;
        }
      } else {
        // sumCal == 0（旧 prompt 无营养字段）→ 不缩放，_computeCurrentNutrition 走单品路径
        _scaledComponents = rawComponents;
      }
    } else {
      _scaledComponents = rawComponents;
    }
    // 组分滑块初值 = 各组分 estimatedG
    for (var i = 0; i < _scaledComponents.length; i++) {
      _componentServings[i] = _scaledComponents[i].estimatedG;
    }
    // 改菜名支持：菜名和单品营养从 widget 拷贝到 state（改菜名命中后 setState 替换）
    _currentDishName = widget.recognitionResult.dishName;
    _currentNutrition = widget.singleNutrition;
  }

  @override
  Widget build(BuildContext context) {
    final isLowConfidence = widget.recognitionResult.confidence < 0.6;
    final isMidConfidence =
        widget.recognitionResult.confidence >= 0.6 && widget.recognitionResult.confidence < 0.85;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmDiscardChanges(context) && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('校准份量'),
        actions: [
          if (_canSkipCalibration)
            TextButton(
              onPressed: _isRecording ? null : _confirmOneClick,
              child: const Text('一键记录'),
            ),
          if (isMidConfidence)
            TextButton(
              onPressed: _isRecording ? null : _trustAi,
              child: const Text('信任 AI'),
            ),
          // 识别错了？改菜名重算（仅单品路径 + 注入 lookup 时显示）
          // 复合菜改菜名语义复杂（涉及多组分），不在此处提供，引导用户转手动
          if (widget.nutritionLookup != null &&
              widget.singleNutrition != null)
            TextButton.icon(
              onPressed: _isRecording || _isRenaming
                  ? null
                  : _handleRename,
              icon: _isRenaming
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.drive_file_rename_outline),
              label: const Text('改菜名'),
            ),
          // 识别不准？转手动录入（避免用户被迫记录错误识别结果）
          TextButton.icon(
            onPressed: _isRecording
                ? null
                : () async {
                    // M16.7: dirty 状态下转手动应确认（避免静默丢失未保存滑块改动）
                    if (_dirty && !(await confirmDiscardChanges(context))) {
                      return; // 用户取消
                    }
                    if (!context.mounted) return;
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (_) => const ManualEntryPage()),
                    );
                  },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('转手动'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '识别结果：$_currentDishName'
                        '${_quantity > 1 ? " ×$_quantity" : ""}',
                        style: Theme.of(context).textTheme.headlineSmall),
                    if (_currentNutrition != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _sourceBadge(_currentNutrition!.source),
                      ),
                    Text('置信度：${(widget.recognitionResult.confidence * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            fontFeatures: [
                              FontFeature.tabularFigures()
                            ])),
                    if (isLowConfidence)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            ExcludeSemantics(
                              child: Icon(Icons.warning_amber_rounded,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.error),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('待确认（置信度低，请仔细校准）',
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error)),
                            ),
                          ],
                        ),
                      ),
                    // v1.9：展示 AI 推理过程（CoT），让用户看到识别思路，错了能精准纠正
                    // 默认折叠避免占空间，用户主动展开查看
                    if (widget.recognitionResult.reasoning != null &&
                        widget.recognitionResult.reasoning!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Card(
                        margin: EdgeInsets.zero,
                        child: ExpansionTile(
                          tilePadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          title: Row(
                            children: [
                              ExcludeSemantics(
                                child: Icon(Icons.psychology_outlined,
                                    size: 18,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary),
                              ),
                              const SizedBox(width: 8),
                              Text('AI 推理过程',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall),
                            ],
                          ),
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Text(
                                widget.recognitionResult.reasoning!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // 多份识别警告：AI 识别为多份时显眼提示，避免用户忽略数量错识
                    // （如一罐芬达被识别成两罐，用户直接确认会记录两罐的克数）
                    if (_quantity > 1) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .tertiaryContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .onTertiaryContainer
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(
                              child: Icon(Icons.inventory_2_outlined,
                                  size: 20,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onTertiaryContainer),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '识别为 $_quantity ${widget.recognitionResult.unit}，对吗？',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onTertiaryContainer),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '若实际只有 1 ${widget.recognitionResult.unit}，点下方 − 调整数量',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onTertiaryContainer),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    // v0.28.0：份量显示（不可调——单品固定 = AI mid，复合菜 = sum(组分 g)）
                    // 单品路径：显示 AI 估算份量 + 区间（改菜名后 _currentNutrition 仍非空时也显示）
                    // 复合菜路径：份量由各组分滑块累加，在 _buildCompositeControls 内展示
                    if (_currentNutrition != null && _scaledComponents.isEmpty) ...[
                      Text('份量：${_currentServingG().toStringAsFixed(0)} g'
                          ' (估算 ${widget.recognitionResult.estimatedWeightGLow.toStringAsFixed(0)}-${widget.recognitionResult.estimatedWeightGHigh.toStringAsFixed(0)} g)',
                          style: const TextStyle(
                              fontFeatures: [
                                FontFeature.tabularFigures()
                              ])),
                    ], // end if 单品路径份量显示
                    // v1.3：数量步进器（同物多份场景，仅单品 + perUnitG > 0 显示）
                    _buildQuantityStepper(),
                    const SizedBox(height: 24),
                    // v2 改动 E：物理约束警告横幅（warnings 非空时显示）
                    // validator 检测的物理约束（Atwater 偏差/密度异常/宏量缺失/宏量超限）
                    // 不修改 AI 值，只提示用户核对，用户可点击下方数值手动编辑
                    if (widget.recognitionResult.warnings.isNotEmpty) ...[
                      _buildWarningsBanner(),
                      const SizedBox(height: 12),
                    ],
                    // 实时营养素预览（基于当前滑块值重算）
                    _buildNutritionPreview(),
                    // v0.28.0：复合菜组分滑块（组分有营养字段时显示，拖动影响热量）
                    if (_hasComponentNutrition) ...[
                      const SizedBox(height: 16),
                      _buildCompositeControls(),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isRecording ? null : _confirmManual,
                child: _isRecording
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary),
                      )
                    : const Text('确认记录'),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  /// v0.28.0：是否有组分营养（决定是否走复合菜路径 + 显示组分滑块）
  bool get _hasComponentNutrition {
    if (_scaledComponents.isEmpty) return false;
    return _scaledComponents.fold(0.0, (s, c) => s + c.calories) > 0;
  }

  Widget _buildNutritionPreview() {
    final (cal, protein, fat, carbs) = _computeCurrentNutrition();
    // 单品路径（无组分）显示估算区间；复合菜路径（有组分）不显示区间
    if (_hasComponentNutrition) {
      return _nutritionCard(cal, protein, fat, carbs);
    }
    // 单品路径：显示估算区间（基于 AI 估算 low/mid/high 比例）
    // 防除零：mid <= 0 时 lowRatio/highRatio = 1（不显示区间）
    final mid = widget.recognitionResult.estimatedWeightGMid;
    final lowRatio = mid > 0 ? widget.recognitionResult.estimatedWeightGLow / mid : 1.0;
    final highRatio = mid > 0 ? widget.recognitionResult.estimatedWeightGHigh / mid : 1.0;
    final calRange = ' (${(cal * lowRatio).toStringAsFixed(0)}-${(cal * highRatio).toStringAsFixed(0)})';
    return _nutritionCard(cal, protein, fat, carbs, calRange: calRange);
  }

  Widget _nutritionCard(double cal, double protein, double fat, double carbs, {String? calRange}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // v2 改动 E：所有数值可点击 → 弹出手动编辑对话框（用户最终兜底）
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 热量突出：大数字 + primary 色，点击可手动编辑
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                InkWell(
                  onTap: _showEditNutritionDialog,
                  borderRadius: BorderRadius.circular(8),
                  child: Text(cal.toStringAsFixed(0),
                      key: const ValueKey('cal_value'),
                      style: tt.headlineMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                          decoration: TextDecoration.underline,
                          decorationColor: cs.primary.withValues(alpha: 0.3),
                          decorationStyle: TextDecorationStyle.dotted)),
                ),
                const SizedBox(width: 4),
                Text('kcal',
                    style: tt.labelLarge
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(width: 6),
                // 编辑提示图标（视觉暗示可点击编辑）
                ExcludeSemantics(
                  child: Icon(Icons.edit_outlined,
                      size: 14, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            if (calRange != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('估算区间 $calRange',
                    style: tt.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ),
            const SizedBox(height: 16),
            // 三大宏量均分三列，点击也可手动编辑
            Row(
              children: [
                _macroColumn('蛋白', protein, cs.tertiary,
                    valueKey: const ValueKey('protein_value')),
                _macroColumn('脂肪', fat, cs.secondary,
                    valueKey: const ValueKey('fat_value')),
                _macroColumn('碳水', carbs, cs.primary,
                    valueKey: const ValueKey('carbs_value')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 宏量列：label 小字 + 数值 titleMedium，均分一行。点击数值可手动编辑。
  Widget _macroColumn(String label, double value, Color color, {Key? valueKey}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          InkWell(
            onTap: _showEditNutritionDialog,
            borderRadius: BorderRadius.circular(8),
            child: Text('${value.toStringAsFixed(0)} g',
                key: valueKey,
                style: tt.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    decoration: TextDecoration.underline,
                    decorationColor: color.withValues(alpha: 0.3),
                    decorationStyle: TextDecorationStyle.dotted)),
          ),
        ],
      ),
    );
  }

  /// v0.28.0：复合菜组分滑块列表（拖动影响热量）
  /// 每个组分一个滑块：min=0, max=estimatedG*2, value=estimatedG
  /// 拖动 → setState 更新 _componentServings[i] → _computeCurrentNutrition 重算总热量
  Widget _buildCompositeControls() {
    final components = _scaledComponents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('组分明细（拖动调整份量）',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        // 总份量由各组分滑块累加，用户拖动时实时刷新
        Text('总份量：${_currentServingG().toStringAsFixed(0)} g',
            style: TextStyle(
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        for (int i = 0; i < components.length; i++)
          _buildComponentSlider(i, components[i]),
      ],
    );
  }

  Widget _buildComponentSlider(int index, FoodComponent component) {
    final serving = _componentServings[index] ?? component.estimatedG;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '${component.name}：${serving.toStringAsFixed(0)} g'
              '（${(component.caloriesPer100g * serving / 100).toStringAsFixed(0)} kcal）',
              style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()])),
          Slider(
            value: serving,
            min: 0,
            max: (component.estimatedG * 2).clamp(50.0, 1000.0),
            divisions: 50,
            label: '${serving.toStringAsFixed(0)} g',
            onChanged: (v) {
              setState(() => _componentServings[index] = v);
              _markDirty();
            },
          ),
        ],
      ),
    );
  }

  /// v1.3：数量步进器（同物多份场景，解决"拍两罐可乐只识别一罐"的问题）
  /// 仅单品路径 + perUnitG > 0 时显示；复合菜份量按组分，不走数量步进器
  /// − / 数量+单位 / + 三段式，范围 1-20；改数量时同步 _servingG = perUnitG × quantity
  Widget _buildQuantityStepper() {
    if (_currentNutrition == null) return const SizedBox.shrink();
    if (_perUnitG <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: '减少数量',
            onPressed: _quantity > 1
                ? () => _onQuantityChanged(_quantity - 1)
                : null,
          ),
          Text('$_quantity ${widget.recognitionResult.unit}',
              style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '增加数量',
            onPressed: _quantity < 20
                ? () => _onQuantityChanged(_quantity + 1)
                : null,
          ),
          const SizedBox(width: 8),
          Text(
              '（每${widget.recognitionResult.unit} ${_perUnitG.toStringAsFixed(0)} g）',
              style: TextStyle(
                  fontFeatures: const [
                    FontFeature.tabularFigures()
                  ],
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant)),
        ],
      ),
    );
  }

  /// v1.3：数量变更联动份量（perUnitG × quantity，clamp 到 _sliderMax 防滑块越界）
  void _onQuantityChanged(int newQ) {
    setState(() {
      _quantity = newQ;
      _servingG = (_perUnitG * newQ).clamp(1.0, _sliderMax);
    });
    _markDirty();
  }

  void _confirmOneClick() {
    // 一键记录：用当前滑块值（v2.1 后 _servingG 初值 = AI mid，与 _trustAi 行为一致）
    _confirmWithServing(_servingG);
  }

  void _trustAi() {
    _confirmWithServing(_servingG);
  }

  void _confirmManual() {
    _confirmWithServing(_servingG);
  }

  /// 改菜名→搜库→重算 单品路径
  /// 命中后 setState 替换 _currentDishName + _currentNutrition，UI 实时刷新
  /// 未命中弹 toast 提示，原菜名和营养保留不变（避免显示新菜名 + 错误营养）
  /// 取消（newName==null）静默返回，不打扰用户
  Future<void> _handleRename() async {
    if (_isRenaming) return; // 防重入
    final lookup = widget.nutritionLookup;
    if (lookup == null) return; // 没注入 lookup 不应该出现（AppBar 已守卫）
    setState(() => _isRenaming = true);
    try {
      final result = await editDishNameAndLookup(
        originalName: _currentDishName,
        // 用 AI 估算 mid 作 servingG（per100g 反算基准，符合硬约束 #4）
        servingG: widget.recognitionResult.estimatedWeightGMid,
        foodRepo: widget.foodItemRepo,
        lookup: lookup,
      );
      if (!mounted) return;
      // 用户取消：静默返回
      if (result.newName == null) return;
      // 命中：替换菜名 + 营养，标记 dirty（PopScope 未保存确认）
      if (result.nutrition != null) {
        // v2 改动 E：清空用户手动编辑覆盖——新菜营养与旧编辑值无关，
        // 保留旧 _userOverrides 会导致显示旧编辑值（与新菜 per100g 不匹配）
        setState(() {
          _currentDishName = result.newName!;
          _currentNutrition = result.nutrition;
          _userOverrides.clear();
          _dirty = true;
        });
        if (mounted) {
          showAppToast(context, '已按「${result.newName}」重算营养');
        }
      } else {
        // 未命中：保留原菜名 + 原营养，提示用户
        showNotFoundToast();
      }
    } catch (e) {
      // 防御性兜底（lookup 内部异常）
      debugPrint('改菜名失败: $e');
      if (mounted) showAppToast(context, '改菜名失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _isRenaming = false);
    }
  }

  Future<void> _confirmWithServing(double servingG) async {
    if (_isRecording) return; // 防重入
    setState(() => _isRecording = true);
    try {
      // v0.28.0：预览/确认统一走 _computeCurrentNutrition，保证显示值与写库值一致。
      // servingG 参数保留兼容三处调用（_confirmOneClick/_trustAi/_confirmManual），
      // 实际写库用 _currentServingG()（单品=AI mid，复合菜=sum(组分滑块)）。
      final (cal, protein, fat, carbs) = _computeCurrentNutrition();
      final actualServingG = _currentServingG();
      final hasComponents = _scaledComponents.isNotEmpty;
      await widget.onConfirm(
        actualServingG,
        cal,
        protein,
        fat,
        carbs,
        componentsSnapshot: hasComponents ? _buildSnapshotJson() : null,
      );
      if (mounted) {
        _dirty = false; // 清 dirty 让 PopScope 放行 programmatic pop
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('记录失败: $e');
      if (mounted) {
        showAppToast(context, '记录失败，请稍后重试。');
      }
    } finally {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  /// v0.28.0：组分快照（仅复合菜路径调用，单品路径 _confirmWithServing 传 null）
  /// 记录各组分 estimated_g（AI 估算）+ actual_g（用户拖动后份量），便于事后追溯
  String _buildSnapshotJson() {
    if (_scaledComponents.isEmpty) return '{}';
    final components = <Map<String, dynamic>>[];
    for (var i = 0; i < _scaledComponents.length; i++) {
      final c = _scaledComponents[i];
      components.add({
        'name': c.name,
        'estimated_g': c.estimatedG,
        'actual_g': _componentServings[i] ?? c.estimatedG,
      });
    }
    return jsonEncode({'components': components});
  }

  /// v2 改动 E：物理约束警告横幅。
  /// validator 检测的物理约束（Atwater 偏差/密度异常/宏量缺失/宏量超限）不修改 AI 值，
  /// 只通过 warnings 提示用户核对。用户可点击下方营养数值手动编辑（最终兜底）。
  Widget _buildWarningsBanner() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cs.onTertiaryContainer.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.warning_amber_rounded,
                size: 20, color: cs.onTertiaryContainer),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '请核对以下异常（点下方数值可手动修改）',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: cs.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                for (final w in widget.recognitionResult.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(w,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onTertiaryContainer,
                        )),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// v2 改动 E：手动编辑营养值对话框（用户最终兜底）。
  /// 4 个 TextField 预填当前显示值，用户输入新值后 _userOverrides 覆盖 AI 估算。
  /// 编辑后 _dirty=true（PopScope 未保存确认），_buildNutritionPreview / _confirmWithServing
  /// 都通过 _applyUserOverrides 应用覆盖。
  Future<void> _showEditNutritionDialog() async {
    // 当前显示值（已应用 _userOverrides 的）作为对话框初始值
    final (curCal, curProtein, curFat, curCarbs) = _currentDisplayedValues();
    final calCtrl =
        TextEditingController(text: curCal.toStringAsFixed(0));
    final proteinCtrl =
        TextEditingController(text: curProtein.toStringAsFixed(0));
    final fatCtrl =
        TextEditingController(text: curFat.toStringAsFixed(0));
    final carbsCtrl =
        TextEditingController(text: curCarbs.toStringAsFixed(0));

    final result = await showDialog<Map<String, double>?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动修改营养值'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '修改后预览和记录都用你输入的值，覆盖 AI 估算。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('edit_cal_field'),
                controller: calCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
                ],
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '热量 (kcal)',
                  helperText: '本次摄入热量',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('edit_protein_field'),
                controller: proteinCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
                ],
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: '蛋白质 (g)'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('edit_fat_field'),
                controller: fatCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
                ],
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: '脂肪 (g)'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('edit_carbs_field'),
                controller: carbsCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
                ],
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: '碳水 (g)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final cal = double.tryParse(calCtrl.text.trim());
              final protein = double.tryParse(proteinCtrl.text.trim());
              final fat = double.tryParse(fatCtrl.text.trim());
              final carbs = double.tryParse(carbsCtrl.text.trim());
              Navigator.of(ctx).pop(<String, double>{
                if (cal != null) 'cal': cal,
                if (protein != null) 'protein': protein,
                if (fat != null) 'fat': fat,
                if (carbs != null) 'carbs': carbs,
              });
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );

    // 用户取消（result == null）→ 不修改
    if (result == null) return;
    if (!mounted) return;
    // 用户确认 → 应用覆盖
    setState(() {
      _userOverrides.addAll(result);
      _dirty = true;
    });
  }

  /// v0.28.0：取当前预览显示的 4 个数值（已应用 _userOverrides），
  /// 用于编辑对话框初始值。与 _buildNutritionPreview / _confirmWithServing 同源，
  /// 三处统一走 _computeCurrentNutrition，保证显示值与写库值一致。
  (double, double, double, double) _currentDisplayedValues() {
    return _computeCurrentNutrition();
  }

  /// 数据来源徽章：库匹配 / AI 估算，提示用户数据可信度
  Widget _sourceBadge(NutritionSource source) {
    final cs = Theme.of(context).colorScheme;
    final isDb = source == NutritionSource.database;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (isDb ? cs.primary : cs.tertiary).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (isDb ? cs.primary : cs.tertiary).withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        isDb ? '库匹配' : 'AI 估算',
        style: TextStyle(fontSize: 11, color: isDb ? cs.primary : cs.tertiary),
      ),
    );
  }
}
