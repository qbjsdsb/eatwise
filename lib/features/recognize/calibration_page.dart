import 'dart:convert';

import 'package:flutter/material.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/vision_provider.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/repositories/food_item_repository.dart';
import '../manual_entry/manual_entry_page.dart';
import 'calibrated_nutrition_calculator.dart';
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

  const CalibrationPage({
    super.key,
    required this.recognitionResult,
    this.singleNutrition,
    this.compositeNutrition,
    required this.foodItemRepo,
    required this.onConfirm,
    this.suggestedServingG,
    this.nutritionLookup,
  });

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> with DishNameEditor<CalibrationPage> {
  late double _servingG;
  late bool _canSkipCalibration;
  // 是否用了历史中位数作初值（UI 提示用）
  late bool _usedHistoryServing;
  // 复合菜校准状态
  final Map<int, double> _componentServings = {}; // 组分索引 → 份量 g
  double _oilG = 0; // 用油量 g
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

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
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
    final isMulti = widget.recognitionResult.isMultiQuantity;
    // 智能份量校准：单品路径优先用历史中位数，无历史回退 AI 估算 mid
    // 历史中位数需 >0（0 通常是数据质量问题）且 clamp 到滑块范围 [_sliderMax] 防崩溃
    // 多份场景不用历史中位数（历史记录可能是单份的，会与 quantity 冲突），用 AI mid
    final suggested = widget.suggestedServingG;
    if (!isMulti &&
        widget.singleNutrition != null &&
        suggested != null &&
        suggested > 0) {
      _servingG = suggested.clamp(1.0, _sliderMax);
      _usedHistoryServing = true;
      // M1：历史中位数与步进器保持一致（perUnitG>0 时反推 quantity）
      if (_perUnitG > 0) {
        final q = (_servingG / _perUnitG).round();
        if (q >= 1 && q <= 20) _quantity = q;
      }
    } else {
      _servingG = widget.recognitionResult.estimatedWeightGMid.clamp(0.0, _sliderMax);
      _usedHistoryServing = false;
    }
    _canSkipCalibration =
        widget.recognitionResult.confidence >= 0.85 && widget.recognitionResult.isSingleItem;
    // 复合菜初始化组分份量 + 用油量
    if (widget.compositeNutrition != null) {
      final hits = widget.compositeNutrition!.componentHits;
      for (var i = 0; i < hits.length; i++) {
        _componentServings[i] = hits[i].estimatedG;
      }
      _oilG = widget.compositeNutrition!.oilG;
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
                    // 复合菜：份量由各组分滑块累加，主滑块无效故隐藏，避免"调了没反应"困惑
                    // 改菜名后 _currentNutrition 仍非空，滑块继续显示
                    if (_currentNutrition != null) ...[
                      Text('份量：${_servingG.toStringAsFixed(0)} g'
                          ' (估算 ${widget.recognitionResult.estimatedWeightGLow.toStringAsFixed(0)}-${widget.recognitionResult.estimatedWeightGHigh.toStringAsFixed(0)} g)',
                          style: const TextStyle(
                              fontFeatures: [
                                FontFeature.tabularFigures()
                              ])),
                      if (_usedHistoryServing)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '📊 已按你历史记录的中位数预填份量',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary),
                          ),
                        ),
                      Slider(
                        value: _servingG,
                        min: 0,
                        max: _sliderMax,
                        divisions: (_sliderMax / 10).round(),
                        label: '${_servingG.toStringAsFixed(0)} g',
                        onChanged: (v) {
                          setState(() {
                            _servingG = v;
                            _usedHistoryServing = false; // 用户手动调整后不再提示
                            // v1.3：拖滑块反推数量（perUnitG > 0 时，保持数量与份量一致）
                            if (_perUnitG > 0) {
                              final q = (v / _perUnitG).round();
                            if (q >= 1 && q <= 20 && q != _quantity) {
                              _quantity = q;
                            }
                          }
                          });
                          _markDirty();
                        },
                      ),
                    ], // end if singleNutrition != null
                    // v1.3：数量步进器（同物多份场景，仅单品 + perUnitG > 0 显示）
                    _buildQuantityStepper(),
                    const SizedBox(height: 24),
                    // 实时营养素预览（基于当前滑块值重算）
                    _buildNutritionPreview(),
                    if (widget.compositeNutrition != null) ...[
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

  /// 单品路径：根据 servingG 计算 (calories, protein, fat, carbs) 实际摄入值。
  ///
  /// M16.6 Task 5：AI 兜底哨兵路径（foodItemId=0）必须用品类校准后的 per100g 计算，
  /// 与 recognize_page 写食物库 per100g 逻辑一致（CalibratedNutritionCalculator），
  /// 否则预览/记录值与食物库 per100g 数据脱节，用户感知"数值乱跳"。
  /// 查库命中路径（foodItemId>0）保持原 ratio 逻辑（DB per100g 已是真实值，无需校准）。
  ///
  /// 预览（_buildNutritionPreview）和确认（_confirmWithServing）共用此方法，
  /// 保证显示值与记录值完全一致。
  (double, double, double, double) _computeSingleItemActual(double servingG) {
    final n = _currentNutrition!;
    if (n.foodItemId == 0) {
      // AI 兜底哨兵：用品类校准后的 per100g 反算 actualXxx（与 recognize_page 一致）
      final calibrated = CalibratedNutritionCalculator.compute(
        recognitionResult: widget.recognitionResult,
        aiFallback: n,
        servingG: servingG,
      );
      return (
        calibrated.actualCalories,
        calibrated.actualProteinG,
        calibrated.actualFatG,
        calibrated.actualCarbsG,
      );
    }
    // 查库命中：DB per100g 已是真实值，按 servingG/mid 比例换算即可
    // 防除零：AI 返回 estimatedWeightGMid <= 0 时 ratio=1（用原值，不按比例换算）
    final mid = widget.recognitionResult.estimatedWeightGMid;
    final ratio = mid > 0 ? servingG / mid : 1.0;
    return (
      n.calories * ratio,
      n.proteinG * ratio,
      n.fatG * ratio,
      n.carbsG * ratio,
    );
  }

  Widget _buildNutritionPreview() {
    if (_currentNutrition != null) {
      // 单品路径：用 _computeSingleItemActual 重算（改菜名后用 _currentNutrition，营养会随之刷新）
      final (cal, protein, fat, carbs) = _computeSingleItemActual(_servingG);
      // 防除零：mid <= 0 时 lowRatio/highRatio = 1（不显示区间）
      final mid = widget.recognitionResult.estimatedWeightGMid;
      final lowRatio = mid > 0 ? widget.recognitionResult.estimatedWeightGLow / mid : 1.0;
      final highRatio = mid > 0 ? widget.recognitionResult.estimatedWeightGHigh / mid : 1.0;
      final calRange = ' (${(cal * lowRatio).toStringAsFixed(0)}-${(cal * highRatio).toStringAsFixed(0)})';
      return _nutritionCard(cal, protein, fat, carbs, calRange: calRange);
    }
    if (widget.compositeNutrition != null) {
      // 复合菜路径：按各组分滑块 + 用油量实时重算
      final composite = widget.compositeNutrition!;
      double cal = 0, protein = 0, fat = 0, carbs = 0;
      for (var i = 0; i < composite.componentHits.length; i++) {
        final hit = composite.componentHits[i];
        final g = _componentServings[i] ?? hit.estimatedG;
        cal += hit.caloriesPer100g * g / 100;
        protein += hit.proteinPer100g * g / 100;
        fat += hit.fatPer100g * g / 100;
        carbs += hit.carbsPer100g * g / 100;
      }
      cal += oilCaloriesPer100g * _oilG / 100;
      fat += oilFatPer100g * _oilG / 100;
      return _nutritionCard(cal, protein, fat, carbs);
    }
    return const SizedBox.shrink();
  }

  Widget _nutritionCard(double cal, double protein, double fat, double carbs, {String? calRange}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 热量突出：大数字 + primary 色
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(cal.toStringAsFixed(0),
                    style: tt.headlineMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [
                          FontFeature.tabularFigures()
                        ])),
                const SizedBox(width: 4),
                Text('kcal',
                    style: tt.labelLarge
                        ?.copyWith(color: cs.onSurfaceVariant)),
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
            // 三大宏量均分三列
            Row(
              children: [
                _macroColumn('蛋白', protein, cs.tertiary),
                _macroColumn('脂肪', fat, cs.secondary),
                _macroColumn('碳水', carbs, cs.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 宏量列：label 小字 + 数值 titleMedium，均分一行
  Widget _macroColumn(String label, double value, Color color) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('${value.toStringAsFixed(0)} g',
              style: tt.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  Widget _buildCompositeControls() {
    final composite = widget.compositeNutrition!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('组分份量调整', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (var i = 0; i < composite.componentHits.length; i++)
          _buildComponentSlider(i, composite.componentHits[i]),
        if (composite.componentMisses.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(Icons.warning_amber_rounded,
                    size: 16, color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(width: 6),
              Text('待确认组分（未在食物库找到）：',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ],
          ),
          for (final miss in composite.componentMisses)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text('• $miss（请转手动录入或补充食物库）',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant)),
            ),
        ],
        const SizedBox(height: 16),
        Text('用油量：${_oilG.toStringAsFixed(0)} g',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()])),
        Slider(
          value: _oilG,
          min: 0,
          max: 50,
          divisions: 50,
          label: '${_oilG.toStringAsFixed(0)} g',
          onChanged: (v) {
            setState(() => _oilG = v);
            _markDirty();
          },
        ),
      ],
    );
  }

  Widget _buildComponentSlider(int index, ComponentHit hit) {
    final serving = _componentServings[index] ?? hit.estimatedG;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${hit.name}：${serving.toStringAsFixed(0)} g',
            style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()])),
        Slider(
          value: serving,
          min: 0,
          max: (hit.estimatedG * 2).clamp(50, 1000),
          divisions: 50,
          label: '${serving.toStringAsFixed(0)} g',
          onChanged: (v) {
            setState(() => _componentServings[index] = v);
            _markDirty();
          },
        ),
      ],
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
      _usedHistoryServing = false;
    });
    _markDirty();
  }

  void _confirmOneClick() {
    // 一键记录：用当前滑块值（无历史预填时 _servingG 默认就是 AI mid，行为不变；
    // 有历史预填时用历史中位数更准，与 UI 显示一致，避免"显示历史值却记录 AI 值"的语义冲突）
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
        setState(() {
          _currentDishName = result.newName!;
          _currentNutrition = result.nutrition;
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
      if (mounted) showAppToast(context, '改菜名失败：$e');
    } finally {
      if (mounted) setState(() => _isRenaming = false);
    }
  }

  Future<void> _confirmWithServing(double servingG) async {
    if (_isRecording) return; // 防重入
    setState(() => _isRecording = true);
    try {
      if (_currentNutrition != null) {
        // 与 _buildNutritionPreview 共用 _computeSingleItemActual，
        // 保证预览显示值与 onConfirm 传入值完全一致
        // （AI 兜底哨兵路径用品类校准后 per100g，查库命中路径用原 ratio 逻辑）
        final (cal, protein, fat, carbs) =
            _computeSingleItemActual(servingG);
        await widget.onConfirm(servingG, cal, protein, fat, carbs);
      } else if (widget.compositeNutrition != null) {
        // 复合菜用总组分份量之和
        final totalG = _componentServings.values.fold<double>(0, (s, g) => s + g);
        // v1.9：复合菜有包装营养表数据时（预包装速冻食品等），按包装换算（精确值），
        // 跳过组分累加。包装 per100g × totalG / 100 = 整菜热量，与份量一致
        // v1.10：包装换算后宏量全 0 但 cal>0（含糖饮料 AI 漏填宏量）→ 回退组分累加，
        //   避免复合菜路径宏量显示 0（与 recognize_page / multi_dish_page 哨兵分支一致）
        final packagePer100 =
            widget.recognitionResult.hasPackageNutrition
                ? widget.recognitionResult.computePackageNutritionPer100g(
                    estimatedProteinG:
                        widget.recognitionResult.estimatedProteinG,
                    estimatedFatG: widget.recognitionResult.estimatedFatG,
                    estimatedCarbsG: widget.recognitionResult.estimatedCarbsG,
                  )
                : null;
        // v1.10：判断包装换算宏量是否全 0（含糖饮料 AI 漏填宏量特征）
        final packageMacrosAllZero = packagePer100 != null &&
            packagePer100.$2 == 0 &&
            packagePer100.$3 == 0 &&
            packagePer100.$4 == 0;
        if (packagePer100 != null && !packageMacrosAllZero) {
          await widget.onConfirm(
            totalG,
            packagePer100.$1 * totalG / 100,
            packagePer100.$2 * totalG / 100,
            packagePer100.$3 * totalG / 100,
            packagePer100.$4 * totalG / 100,
            componentsSnapshot: _buildSnapshotJson(),
          );
        } else {
          // 无包装数据 / 包装换算宏量全 0 → 按调整后组分份量重算（原逻辑）
          final composite = widget.compositeNutrition!;
          double cal = 0, protein = 0, fat = 0, carbs = 0;
          for (var i = 0; i < composite.componentHits.length; i++) {
            final hit = composite.componentHits[i];
            final g = _componentServings[i] ?? hit.estimatedG;
            cal += hit.caloriesPer100g * g / 100;
            protein += hit.proteinPer100g * g / 100;
            fat += hit.fatPer100g * g / 100;
            carbs += hit.carbsPer100g * g / 100;
          }
          cal += oilCaloriesPer100g * _oilG / 100;
          fat += oilFatPer100g * _oilG / 100;
          await widget.onConfirm(
            totalG,
            cal,
            protein,
            fat,
            carbs,
            componentsSnapshot: _buildSnapshotJson(),
          );
        }
      }
      if (mounted) {
        _dirty = false; // 清 dirty 让 PopScope 放行 programmatic pop
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '记录失败：$e');
      }
    } finally {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  String _buildSnapshotJson() {
    if (widget.compositeNutrition == null) return '{}';
    final composite = widget.compositeNutrition!;
    final components = <Map<String, dynamic>>[];
    for (var i = 0; i < composite.componentHits.length; i++) {
      final hit = composite.componentHits[i];
      components.add({
        'name': hit.name,
        'actual_g': _componentServings[i] ?? hit.estimatedG,
      });
    }
    return jsonEncode({
      'components': components,
      'oil_g': _oilG,
    });
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
        isDb ? '库匹配' : 'AI 估算（库未命中）',
        style: TextStyle(fontSize: 11, color: isDb ? cs.primary : cs.tertiary),
      ),
    );
  }
}
