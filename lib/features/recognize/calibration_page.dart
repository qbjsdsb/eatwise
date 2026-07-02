import 'dart:convert';

import 'package:flutter/material.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/vision_provider.dart';
import '../../data/repositories/food_item_repository.dart';

/// 校准页：按置信度分级
/// - 置信度 ≥ 0.85 且单品：允许"一键记录"跳过校准
/// - 置信度 < 0.6：强制校准，标注"待确认"
/// - 中间区 0.6-0.85：默认进校准页，提供"信任 AI"快捷按钮
class CalibrationPage extends StatefulWidget {
  final VisionRecognitionResult recognitionResult;
  final NutritionResult? singleNutrition;
  final CompositeNutritionResult? compositeNutrition;
  final FoodItemRepository foodItemRepo;
  final void Function(double servingG, double calories, double protein, double fat, double carbs, {String? componentsSnapshot}) onConfirm;
  // 智能份量校准：基于历史记录的中位数（B 功能）。
  // 非空时滑块初值用它（而非 AI 估算 mid），减少手动拖滑块。
  // 仅单品路径生效；复合菜份量按组分，不走此参数。
  final double? suggestedServingG;

  const CalibrationPage({
    super.key,
    required this.recognitionResult,
    this.singleNutrition,
    this.compositeNutrition,
    required this.foodItemRepo,
    required this.onConfirm,
    this.suggestedServingG,
  });

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
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
  }

  @override
  Widget build(BuildContext context) {
    final isLowConfidence = widget.recognitionResult.confidence < 0.6;
    final isMidConfidence =
        widget.recognitionResult.confidence >= 0.6 && widget.recognitionResult.confidence < 0.85;

    return Scaffold(
      appBar: AppBar(
        title: const Text('校准份量'),
        actions: [
          if (_canSkipCalibration)
            TextButton(
              onPressed: _confirmOneClick,
              child: const Text('一键记录'),
            ),
          if (isMidConfidence)
            TextButton(
              onPressed: _trustAi,
              child: const Text('信任 AI'),
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
                        '识别结果：${widget.recognitionResult.dishName}'
                        '${_quantity > 1 ? " ×$_quantity" : ""}',
                        style: Theme.of(context).textTheme.headlineSmall),
                    Text('置信度：${(widget.recognitionResult.confidence * 100).toStringAsFixed(0)}%'),
                    if (isLowConfidence)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('⚠️ 待确认（置信度低，请仔细校准）',
                            style: TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 24),
                    Text('份量：${_servingG.toStringAsFixed(0)} g'
                        '${widget.singleNutrition != null ? " (估算 ${widget.recognitionResult.estimatedWeightGLow.toStringAsFixed(0)}-${widget.recognitionResult.estimatedWeightGHigh.toStringAsFixed(0)} g)" : ""}'),
                    if (_usedHistoryServing)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '📊 已按你历史记录的中位数预填份量',
                          style: TextStyle(
                              fontSize: 12, color: Colors.green[700]),
                        ),
                      ),
                    Slider(
                      value: _servingG,
                      min: 0,
                      max: _sliderMax,
                      divisions: (_sliderMax / 10).round(),
                      label: '${_servingG.toStringAsFixed(0)} g',
                      onChanged: (v) => setState(() {
                        _servingG = v;
                        _usedHistoryServing = false; // 用户手动调整后不再提示
                        // v1.3：拖滑块反推数量（perUnitG > 0 时，保持数量与份量一致）
                        if (_perUnitG > 0) {
                          final q = (v / _perUnitG).round();
                          if (q >= 1 && q <= 20 && q != _quantity) {
                            _quantity = q;
                          }
                        }
                      }),
                    ),
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
                onPressed: _confirmManual,
                child: const Text('确认记录'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionPreview() {
    if (widget.singleNutrition != null) {
      // 单品路径：按总份量滑块比例重算
      // 防除零：AI 返回 estimatedWeightGMid <= 0 时 ratio=1（用原值，不按比例换算）
      final mid = widget.recognitionResult.estimatedWeightGMid;
      final ratio = mid > 0 ? _servingG / mid : 1.0;
      final cal = widget.singleNutrition!.calories * ratio;
      final protein = widget.singleNutrition!.proteinG * ratio;
      final fat = widget.singleNutrition!.fatG * ratio;
      final carbs = widget.singleNutrition!.carbsG * ratio;
      // 防除零：mid <= 0 时 lowRatio/highRatio = 1（不显示区间）
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('热量：${cal.toStringAsFixed(0)} kcal${calRange ?? ""}'),
            Text('蛋白质：${protein.toStringAsFixed(1)} g'),
            Text('脂肪：${fat.toStringAsFixed(1)} g'),
            Text('碳水：${carbs.toStringAsFixed(1)} g'),
          ],
        ),
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
          const Text('⚠ 待确认组分（未在食物库找到）：',
              style: TextStyle(color: Colors.orange)),
          for (final miss in composite.componentMisses)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text('• $miss（请转手动录入或补充食物库）',
                  style: const TextStyle(color: Colors.grey)),
            ),
        ],
        const SizedBox(height: 16),
        Text('用油量：${_oilG.toStringAsFixed(0)} g',
            style: Theme.of(context).textTheme.titleSmall),
        Slider(
          value: _oilG,
          min: 0,
          max: 50,
          divisions: 50,
          label: '${_oilG.toStringAsFixed(0)} g',
          onChanged: (v) => setState(() => _oilG = v),
        ),
      ],
    );
  }

  Widget _buildComponentSlider(int index, ComponentHit hit) {
    final serving = _componentServings[index] ?? hit.estimatedG;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${hit.name}：${serving.toStringAsFixed(0)} g'),
        Slider(
          value: serving,
          min: 0,
          max: (hit.estimatedG * 2).clamp(50, 1000),
          divisions: 50,
          label: '${serving.toStringAsFixed(0)} g',
          onChanged: (v) => setState(() => _componentServings[index] = v),
        ),
      ],
    );
  }

  /// v1.3：数量步进器（同物多份场景，解决"拍两罐可乐只识别一罐"的问题）
  /// 仅单品路径 + perUnitG > 0 时显示；复合菜份量按组分，不走数量步进器
  /// − / 数量+单位 / + 三段式，范围 1-20；改数量时同步 _servingG = perUnitG × quantity
  Widget _buildQuantityStepper() {
    if (widget.singleNutrition == null) return const SizedBox.shrink();
    if (_perUnitG <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: _quantity > 1
                ? () => _onQuantityChanged(_quantity - 1)
                : null,
          ),
          Text('$_quantity ${widget.recognitionResult.unit}',
              style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _quantity < 20
                ? () => _onQuantityChanged(_quantity + 1)
                : null,
          ),
          const SizedBox(width: 8),
          Text(
              '（每${widget.recognitionResult.unit} ${_perUnitG.toStringAsFixed(0)}g）',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
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

  void _confirmWithServing(double servingG) {
    if (widget.singleNutrition != null) {
      // 防除零：AI 返回 estimatedWeightGMid <= 0 时 ratio=1
      final mid = widget.recognitionResult.estimatedWeightGMid;
      final ratio = mid > 0 ? servingG / mid : 1.0;
      widget.onConfirm(
        servingG,
        widget.singleNutrition!.calories * ratio,
        widget.singleNutrition!.proteinG * ratio,
        widget.singleNutrition!.fatG * ratio,
        widget.singleNutrition!.carbsG * ratio,
      );
    } else if (widget.compositeNutrition != null) {
      // 按调整后份量重算
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
      // 复合菜用总组分份量之和
      final totalG = _componentServings.values.fold<double>(0, (s, g) => s + g);
      widget.onConfirm(
        totalG,
        cal,
        protein,
        fat,
        carbs,
        componentsSnapshot: _buildSnapshotJson(),
      );
    }
    Navigator.of(context).pop();
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
}
