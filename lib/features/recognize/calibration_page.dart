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

  @override
  void initState() {
    super.initState();
    _servingG = widget.recognitionResult.estimatedWeightGMid;
    _canSkipCalibration =
        widget.recognitionResult.confidence >= 0.85 && widget.recognitionResult.isSingleItem;
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
            Text('识别结果：${widget.recognitionResult.dishName}',
                style: Theme.of(context).textTheme.headlineSmall),
            Text('置信度：${(widget.recognitionResult.confidence * 100).toStringAsFixed(0)}%'),
            if (isLowConfidence)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('⚠️ 待确认（置信度低，请仔细校准）',
                    style: TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 24),
            Text('份量：${_servingG.toStringAsFixed(0)} g'),
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
            const Spacer(),
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
    if (widget.singleNutrition == null) return const SizedBox.shrink();
    final ratio = _servingG / widget.recognitionResult.estimatedWeightGMid;
    final cal = widget.singleNutrition!.calories * ratio;
    final protein = widget.singleNutrition!.proteinG * ratio;
    final fat = widget.singleNutrition!.fatG * ratio;
    final carbs = widget.singleNutrition!.carbsG * ratio;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('热量：${cal.toStringAsFixed(0)} kcal'),
            Text('蛋白质：${protein.toStringAsFixed(1)} g'),
            Text('脂肪：${fat.toStringAsFixed(1)} g'),
            Text('碳水：${carbs.toStringAsFixed(1)} g'),
          ],
        ),
      ),
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
      widget.onConfirm(
        servingG,
        widget.compositeNutrition!.calories,
        widget.compositeNutrition!.proteinG,
        widget.compositeNutrition!.fatG,
        widget.compositeNutrition!.carbsG,
        componentsSnapshot: _buildSnapshotJson(),
      );
    }
    Navigator.of(context).pop();
  }

  String _buildSnapshotJson() {
    // 复合菜组分快照（设计文档 4.2.3 components_snapshot_json）
    final components = widget.recognitionResult.foodComponents
        .map((c) => {'name': c.name, 'actual_g': c.estimatedG})
        .toList();
    return jsonEncode({
      'components': components,
      'oil_g': widget.compositeNutrition?.oilG ?? 0,
    });
  }
}
