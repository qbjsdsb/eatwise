import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/vision_provider.dart';
import '../../data/repositories/food_item_repository.dart';
import 'providers.dart';
import 'recognize_controller.dart';

/// 一桌多菜列表页（v1.2）
///
/// 拍一桌菜识别出多个菜后，显示所有菜品列表，每菜可单独校准份量，
/// 最后"全部记录"合并写入 meal_log（每菜一条记录，同餐次同日期）。
///
/// 设计：每菜一个 ExpansionTile，展开后内嵌校准控件（复用 CalibrationPage 的逻辑思路，
/// 但为列表紧凑性简化为行内滑块）。主菜 + additionalDishes 全部列出。
class MultiDishPage extends ConsumerStatefulWidget {
  final VisionRecognitionResult mainDish;
  final NutritionResult? mainSingle;
  final CompositeNutritionResult? mainComposite;
  final List<MultiDishItem> additionalItems;
  final String mealType;
  final String? imagePath;
  final FoodItemRepository foodItemRepo;

  const MultiDishPage({
    super.key,
    required this.mainDish,
    this.mainSingle,
    this.mainComposite,
    required this.additionalItems,
    required this.mealType,
    this.imagePath,
    required this.foodItemRepo,
  });

  @override
  ConsumerState<MultiDishPage> createState() => _MultiDishPageState();
}

class _MultiDishPageState extends ConsumerState<MultiDishPage> {
  // 每菜的份量状态（索引 0=主菜，1..n=additionalDishes）
  late List<double> _servings;
  // 每菜是否命中库（未命中需标红提示转手动）
  late List<bool> _hitFlags;

  @override
  void initState() {
    super.initState();
    // 主菜 + additionalDishes 组成完整列表
    final allDishes = [
      widget.mainDish,
      ...widget.additionalItems.map((e) => e.dish),
    ];
    _servings = allDishes.map((d) => d.estimatedWeightGMid).toList();
    // 命中标志：主菜 single/composite 任一非空即命中；additionalDish 同理
    _hitFlags = [
      widget.mainSingle != null || widget.mainComposite != null,
      ...widget.additionalItems.map(
          (e) => e.singleNutrition != null || e.compositeNutrition != null),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final allDishes = [
      widget.mainDish,
      ...widget.additionalItems.map((e) => e.dish),
    ];
    // 合并营养素总计（仅命中菜品）
    double totalCal = 0, totalProtein = 0, totalFat = 0, totalCarbs = 0;
    for (var i = 0; i < allDishes.length; i++) {
      if (!_hitFlags[i]) continue;
      final (cal, p, f, c) = _calcNutrition(i, allDishes[i]);
      totalCal += cal;
      totalProtein += p;
      totalFat += f;
      totalCarbs += c;
    }

    return Scaffold(
      appBar: AppBar(title: Text('一桌多菜（共 ${allDishes.length} 道）')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: allDishes.length,
              itemBuilder: (ctx, i) => _buildDishCard(i, allDishes[i]),
            ),
          ),
          // 总计卡片
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Column(
              children: [
                Text('本餐合计：${totalCal.toStringAsFixed(0)} kcal',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                    '蛋白质 ${totalProtein.toStringAsFixed(1)}g · 脂肪 ${totalFat.toStringAsFixed(0)}g · 碳水 ${totalCarbs.toStringAsFixed(0)}g',
                    style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _recordAll,
                    child: const Text('全部记录'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDishCard(int index, VisionRecognitionResult dish) {
    final hit = _hitFlags[index];
    final (cal, p, f, c) = hit ? _calcNutrition(index, dish) : (0.0, 0.0, 0.0, 0.0);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(dish.dishName,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (!hit)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('未命中',
                        style: TextStyle(fontSize: 11, color: Colors.orange)),
                  ),
              ],
            ),
            if (hit) ...[
              const SizedBox(height: 8),
              Text('份量：${_servings[index].toStringAsFixed(0)} g'),
              Slider(
                value: _servings[index],
                min: 0,
                max: 1000,
                divisions: 100,
                label: '${_servings[index].toStringAsFixed(0)} g',
                onChanged: (v) => setState(() => _servings[index] = v),
              ),
              Text(
                  '${cal.toStringAsFixed(0)} kcal · 蛋白 ${p.toStringAsFixed(1)}g · 脂肪 ${f.toStringAsFixed(0)}g · 碳水 ${c.toStringAsFixed(0)}g',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('库中未找到「${dish.dishName}」，记录时将跳过此菜',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }

  /// 计算某菜当前份量的营养素（基于查库结果按比例）
  (double, double, double, double) _calcNutrition(
      int index, VisionRecognitionResult dish) {
    final serving = _servings[index];
    final ratio = serving / dish.estimatedWeightGMid;
    if (index == 0) {
      // 主菜
      if (widget.mainSingle != null) {
        final n = widget.mainSingle!;
        return (
          n.calories * ratio,
          n.proteinG * ratio,
          n.fatG * ratio,
          n.carbsG * ratio,
        );
      }
      if (widget.mainComposite != null) {
        final n = widget.mainComposite!;
        return (n.calories, n.proteinG, n.fatG, n.carbsG);
      }
    } else {
      // additionalDishes（index-1 对应 additionalItems）
      final item = widget.additionalItems[index - 1];
      if (item.singleNutrition != null) {
        final n = item.singleNutrition!;
        return (
          n.calories * ratio,
          n.proteinG * ratio,
          n.fatG * ratio,
          n.carbsG * ratio,
        );
      }
      if (item.compositeNutrition != null) {
        final n = item.compositeNutrition!;
        return (n.calories, n.proteinG, n.fatG, n.carbsG);
      }
    }
    return (0, 0, 0, 0);
  }

  /// 全部记录：对每个命中菜品写一条 meal_log（同日期同餐次）
  Future<void> _recordAll() async {
    final mealRepo = await ref.read(mealLogRepoProvider.future);
    final foodRepo = await ref.read(foodItemRepoProvider.future);
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final allDishes = [
      widget.mainDish,
      ...widget.additionalItems.map((e) => e.dish),
    ];

    int recordedCount = 0;
    double totalCal = 0;
    for (var i = 0; i < allDishes.length; i++) {
      if (!_hitFlags[i]) continue; // 未命中跳过
      final dish = allDishes[i];
      final serving = _servings[i];
      final (cal, p, f, c) = _calcNutrition(i, dish);

      // 获取 foodItemId：单品用查库命中的 foodItemId，复合菜 upsert ai_recognized
      int foodItemId;
      if (i == 0) {
        if (widget.mainSingle != null) {
          foodItemId = widget.mainSingle!.foodItemId;
        } else {
          foodItemId = await foodRepo.upsertAiRecognized(
            name: dish.dishName,
            caloriesPer100g: 0,
            proteinPer100g: 0,
            fatPer100g: 0,
            carbsPer100g: 0,
            confidence: dish.confidence,
          );
        }
      } else {
        final item = widget.additionalItems[i - 1];
        if (item.singleNutrition != null) {
          foodItemId = item.singleNutrition!.foodItemId;
        } else {
          foodItemId = await foodRepo.upsertAiRecognized(
            name: dish.dishName,
            caloriesPer100g: 0,
            proteinPer100g: 0,
            fatPer100g: 0,
            carbsPer100g: 0,
            confidence: dish.confidence,
          );
        }
      }

      await mealRepo.insertMealLog(
        date: today,
        mealType: widget.mealType,
        foodItemId: foodItemId,
        actualServingG: serving,
        actualCalories: cal,
        actualProteinG: p,
        actualFatG: f,
        actualCarbsG: c,
        originalImagePath: i == 0 ? widget.imagePath : null,
        recognitionConfidence: dish.confidence,
      );
      recordedCount++;
      totalCal += cal;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '已记录 $recordedCount 道菜，合计 ${totalCal.toStringAsFixed(0)} kcal')),
      );
      Navigator.of(context).pop();
    }
  }
}
