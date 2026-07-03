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
  final void Function(
    double servingG,
    double calories,
    double protein,
    double fat,
    double carbs, {
    String? componentsSnapshot,
  })
  onConfirm;

  const CalibrationPage({
    super.key,
    required this.recognitionResult,
    this.singleNutrition,
    this.compositeNutrition,
    required this.foodItemRepo,
    required this.onConfirm,
  });

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  late double _servingG;
  late bool _canSkipCalibration;
  // 复合菜校准状态
  final Map<int, double> _componentServings = {}; // 组分索引 → 份量 g
  double _oilG = 0; // 用油量 g

  @override
  void initState() {
    super.initState();
    _servingG = widget.recognitionResult.estimatedWeightGMid;
    _canSkipCalibration =
        widget.recognitionResult.confidence >= 0.85 &&
        widget.recognitionResult.isSingleItem;
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
        widget.recognitionResult.confidence >= 0.6 &&
        widget.recognitionResult.confidence < 0.85;

    return Scaffold(
      appBar: AppBar(
        title: const Text('校准份量'),
        actions: [
          if (_canSkipCalibration)
            TextButton(onPressed: _confirmOneClick, child: const Text('一键记录')),
          if (isMidConfidence)
            TextButton(onPressed: _trustAi, child: const Text('信任 AI')),
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
                      '识别结果：${widget.recognitionResult.dishName}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (widget.singleNutrition != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _sourceBadge(widget.singleNutrition!.source),
                      ),
                    Text(
                      '置信度：${(widget.recognitionResult.confidence * 100).toStringAsFixed(0)}%',
                    ),
                    if (isLowConfidence)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '⚠️ 待确认（置信度低，请仔细校准）',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Text(
                      '份量：${_servingG.toStringAsFixed(0)} g'
                      '${widget.singleNutrition != null ? " (估算 ${widget.recognitionResult.estimatedWeightGLow.toStringAsFixed(0)}-${widget.recognitionResult.estimatedWeightGHigh.toStringAsFixed(0)} g)" : ""}',
                    ),
                    Slider(
                      value: _servingG,
                      min: 0,
                      max: 1000,
                      divisions: 100,
                      label: '${_servingG.toStringAsFixed(0)} g',
                      onChanged: (v) => setState(() => _servingG = v),
                    ),
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
      final ratio = _servingG / widget.recognitionResult.estimatedWeightGMid;
      final cal = widget.singleNutrition!.calories * ratio;
      final protein = widget.singleNutrition!.proteinG * ratio;
      final fat = widget.singleNutrition!.fatG * ratio;
      final carbs = widget.singleNutrition!.carbsG * ratio;
      final lowRatio =
          widget.recognitionResult.estimatedWeightGLow /
          widget.recognitionResult.estimatedWeightGMid;
      final highRatio =
          widget.recognitionResult.estimatedWeightGHigh /
          widget.recognitionResult.estimatedWeightGMid;
      final calRange =
          ' (${(cal * lowRatio).toStringAsFixed(0)}-${(cal * highRatio).toStringAsFixed(0)})';
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

  /// 数据来源徽章：库匹配（绿）/ AI 估算（橙），提示用户数据可信度
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

  Widget _nutritionCard(
    double cal,
    double protein,
    double fat,
    double carbs, {
    String? calRange,
  }) {
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
          const Text(
            '⚠ 待确认组分（未在食物库找到）：',
            style: TextStyle(color: Colors.orange),
          ),
          for (final miss in composite.componentMisses)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                '• $miss（请转手动录入或补充食物库）',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text(
          '用油量：${_oilG.toStringAsFixed(0)} g',
          style: Theme.of(context).textTheme.titleSmall,
        ),
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

  void _confirmOneClick() {
    // 一键记录：用 AI 中值，不校准
    _confirmWithServing(widget.recognitionResult.estimatedWeightGMid);
  }

  void _trustAi() {
    _confirmWithServing(widget.recognitionResult.estimatedWeightGMid);
  }

  void _confirmManual() {
    _confirmWithServing(_servingG);
  }

  void _confirmWithServing(double servingG) {
    if (widget.singleNutrition != null) {
      final ratio = servingG / widget.recognitionResult.estimatedWeightGMid;
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
    return jsonEncode({'components': components, 'oil_g': _oilG});
  }
}
