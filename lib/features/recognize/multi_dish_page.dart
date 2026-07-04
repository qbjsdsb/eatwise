import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/vision_provider.dart';
import '../../core/util/date_format.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/seed/food_category_defaults.dart';
import '../manual_entry/manual_entry_page.dart';
import 'providers.dart';
import 'recognize_controller.dart';

/// 一桌多菜列表页（v1.2）
///
/// 拍一桌菜识别出多个菜后，显示所有菜品列表，每菜可单独校准份量，
/// 最后"全部记录"合并写入 meal_log（每菜一条记录，同餐次同日期）。
class MultiDishPage extends ConsumerStatefulWidget {
  final VisionRecognitionResult mainDish;
  final NutritionResult? mainSingle;
  final CompositeNutritionResult? mainComposite;
  final List<MultiDishItem> additionalItems;
  final String mealType;
  final String? imagePath;

  const MultiDishPage({
    super.key,
    required this.mainDish,
    this.mainSingle,
    this.mainComposite,
    required this.additionalItems,
    required this.mealType,
    this.imagePath,
  });

  @override
  ConsumerState<MultiDishPage> createState() => _MultiDishPageState();
}

class _MultiDishPageState extends ConsumerState<MultiDishPage> {
  // 每菜的份量状态（索引 0=主菜，1..n=additionalDishes）
  late List<double> _servings;
  // v1.3：每菜的数量状态（同物多份，索引与 _servings 对齐）
  late List<int> _quantities;
  // 每菜是否命中库（未命中需标红提示转手动）
  late List<bool> _hitFlags;
  // 防重入：记录中禁止连点
  bool _isRecording = false;
  bool _dirty = false; // 用户是否改过滑块份量/数量（PopScope 未保存确认用）

  @override
  void initState() {
    super.initState();
    // 主菜 + additionalDishes 组成完整列表（additionalDishes 防 >5 截断）
    final allDishes = [
      widget.mainDish,
      ...widget.additionalItems.take(5).map((e) => e.dish),
    ];
    // 份量初值 clamp 到滑块范围 [0, _sliderMaxFor] 防 Slider 越界崩溃
    _servings = allDishes
        .map((d) => d.estimatedWeightGMid.clamp(0.0, _sliderMaxFor(d)))
        .toList();
    // v1.3：数量初值取 AI 识别的 quantity（默认 1）
    _quantities = allDishes.map((d) => d.quantity).toList();
    // 命中标志：主菜 single 非空或 composite 有组分命中即命中；additionalDish 同理
    // composite 永不返回 null，但 componentHits 为空表示组分全 miss（无有效营养数据）
    _hitFlags = [
      widget.mainSingle != null ||
          (widget.mainComposite != null &&
              widget.mainComposite!.componentHits.isNotEmpty),
      ...widget.additionalItems.take(5).map((e) =>
          e.singleNutrition != null ||
          (e.compositeNutrition != null &&
              e.compositeNutrition!.componentHits.isNotEmpty)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final allDishes = [
      widget.mainDish,
      ...widget.additionalItems.take(5).map((e) => e.dish),
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
        title: Text('一桌多菜（共 ${allDishes.length} 道）'),
        actions: [
          // 识别不准？转手动录入（避免用户被迫记录错误识别结果）
          TextButton.icon(
            onPressed: _isRecording
                ? null
                : () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (_) => const ManualEntryPage()),
                    ),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('转手动'),
          ),
        ],
      ),
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
              border: Border(
                  top: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant)),
            ),
            child: Column(
              children: [
                Text('本餐合计：${totalCal.toStringAsFixed(0)} kcal',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                    '蛋白质 ${totalProtein.toStringAsFixed(1)}g · 脂肪 ${totalFat.toStringAsFixed(0)}g · 碳水 ${totalCarbs.toStringAsFixed(0)}g',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    // 防重入：记录中禁用按钮
                    onPressed: _isRecording ? null : _recordAll,
                    child: _isRecording
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimary))
                        : const Text('全部记录'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
                  // v1.3：多份时菜名后显示 ×数量（用 state _quantities，步进器改后同步）
                  child: Text(
                      '${dish.dishName}${_quantities[index] > 1 ? " ×${_quantities[index]}" : ""}',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (!hit)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .tertiaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('未命中',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .tertiary)),
                  ),
              ],
            ),
            if (hit) ...[
              const SizedBox(height: 8),
              Text('份量：${_servings[index].toStringAsFixed(0)} g'),
              Slider(
                value: _servings[index],
                min: 0,
                max: _sliderMaxFor(dish),
                divisions: (_sliderMaxFor(dish) / 10).round(),
                label: '${_servings[index].toStringAsFixed(0)} g',
                onChanged: (v) => setState(() {
                  _servings[index] = v;
                  _dirty = true; // 用户拖滑块改份量，标记 dirty（PopScope 未保存确认）
                  // v1.3：仅单品路径 + perUnitG > 0 时反推数量（复合菜无步进器，不写 _quantities）
                  if (_getSingleNutrition(index) != null && dish.perUnitG > 0) {
                    final q = (v / dish.perUnitG).round();
                    if (q >= 1 && q <= 20 && q != _quantities[index]) {
                      _quantities[index] = q;
                    }
                  }
                }),
              ),
              // v1.3：数量步进器（仅单品命中 + perUnitG > 0 显示）
              _buildQuantityStepper(index, dish),
              Text(
                  '${cal.toStringAsFixed(0)} kcal · 蛋白 ${p.toStringAsFixed(1)}g · 脂肪 ${f.toStringAsFixed(0)}g · 碳水 ${c.toStringAsFixed(0)}g',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant)),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('库中未找到「${dish.dishName}」，记录时将跳过此菜',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }

  /// v1.3：动态滑块上限（每菜独立）。perUnitG>0 时按 perUnitG×20 扩到 5000 防多份 clamp 少算
  double _sliderMaxFor(VisionRecognitionResult dish) {
    if (dish.perUnitG > 0) {
      return (dish.perUnitG * 20).clamp(1000.0, 5000.0);
    }
    return 1000.0;
  }

  /// v1.3：获取某菜的单品查库结果（判断是否单品路径用）
  NutritionResult? _getSingleNutrition(int index) {
    if (index == 0) return widget.mainSingle;
    return widget.additionalItems[index - 1].singleNutrition;
  }

  /// v1.3：数量步进器（同物多份场景，仅单品命中 + perUnitG > 0 显示）
  /// − / 数量+单位 / + 三段式，范围 1-20；改数量时同步 _servings[index] = perUnitG × quantity
  Widget _buildQuantityStepper(int index, VisionRecognitionResult dish) {
    if (_getSingleNutrition(index) == null) return const SizedBox.shrink();
    if (dish.perUnitG <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: _quantities[index] > 1
                ? () => _onQuantityChanged(index, _quantities[index] - 1, dish)
                : null,
          ),
          Text('${_quantities[index]} ${dish.unit}',
              style: Theme.of(context).textTheme.bodyMedium),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _quantities[index] < 20
                ? () => _onQuantityChanged(index, _quantities[index] + 1, dish)
                : null,
          ),
          const SizedBox(width: 8),
          Text('（每${dish.unit} ${dish.perUnitG.toStringAsFixed(0)}g）',
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant)),
        ],
      ),
    );
  }

  /// v1.3：数量变更联动份量（perUnitG × quantity，clamp 到 _sliderMaxFor 防滑块越界）
  void _onQuantityChanged(int index, int newQ, VisionRecognitionResult dish) {
    setState(() {
      _quantities[index] = newQ;
      _servings[index] = (dish.perUnitG * newQ).clamp(0.0, _sliderMaxFor(dish));
      _dirty = true; // 用户改数量，标记 dirty（PopScope 未保存确认）
    });
  }

  /// 计算某菜当前份量的营养素（基于查库结果按比例缩放）
  /// 单品和复合菜都按 ratio = serving / estimatedWeightGMid 缩放
  (double, double, double, double) _calcNutrition(
      int index, VisionRecognitionResult dish) {
    final serving = _servings[index];
    // 防除零：estimatedWeightGMid <= 0 时 ratio=1（用原值）
    final mid = dish.estimatedWeightGMid;
    final ratio = mid > 0 ? serving / mid : 1.0;
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
        return (
          n.calories * ratio,
          n.proteinG * ratio,
          n.fatG * ratio,
          n.carbsG * ratio,
        );
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
        return (
          n.calories * ratio,
          n.proteinG * ratio,
          n.fatG * ratio,
          n.carbsG * ratio,
        );
      }
    }
    return (0, 0, 0, 0);
  }

  /// 全部记录：对每个命中菜品写一条 meal_log（同日期同餐次）
  /// 事务包裹整个循环：保证原子性，避免部分成功部分失败导致重复写入
  Future<void> _recordAll() async {
    if (_isRecording) return; // 防重入
    setState(() => _isRecording = true);
    try {
      final mealRepo = await ref.read(mealLogRepoProvider.future);
      final foodRepo = await ref.read(foodItemRepoProvider.future);
      final db = await ref.read(databaseProvider.future);
      final today = todayYmd();
      final allDishes = [
        widget.mainDish,
        ...widget.additionalItems.take(5).map((e) => e.dish),
      ];

      int recordedCount = 0;
      double totalCal = 0;
      // 事务包裹：所有菜品 upsert + insertMealLog 原子化，任一失败整体回滚不产生部分记录
      await db.transaction(() async {
        // v1.9：单品哨兵分支的 foodItemId 解析（包装 OCR 优先 + 品类校准兜底）
        // i==0 主菜和 i>0 附加菜共用同一逻辑，避免代码重复
        Future<int> resolveSingleFoodItemId(
          VisionRecognitionResult dish,
          NutritionResult n,
          FoodItemRepository foodRepo,
        ) async {
          final mid = dish.estimatedWeightGMid;
          final per100 = mid > 0 ? 100.0 / mid : 0.0;
          // v1.9：包装食品 OCR 优先路径——有包装营养表数据时按包装换算，
          // 跳过品类校准（包装数据是精确值，不需要校准）
          // 参考 prompts.dart v1.9 规则 10 + 示例 7（珍宝珠酸条）
          final packagePer100 = dish.hasPackageNutrition
              ? dish.computePackageNutritionPer100g(
                  estimatedProteinG:
                      n.proteinG == 0 ? dish.estimatedProteinG : n.proteinG,
                  estimatedFatG:
                      n.fatG == 0 ? dish.estimatedFatG : n.fatG,
                  estimatedCarbsG:
                      n.carbsG == 0 ? dish.estimatedCarbsG : n.carbsG,
                )
              : null;
          final (caloriesPer100g, proteinPer100g, fatPer100g, carbsPer100g) =
              packagePer100 ??
                  (() {
                    // 无包装数据 → 走原 AI 估算 + 品类校准路径
                    // P0：品类默认值校准——AI 估算的 per100g 偏离品类默认值 2 倍以上
                    // 用默认值替代（防 AI 离谱估算，如啤酒估成 200 kcal/100g 实际 43）
                    final rawCalPer100 = n.calories * per100;
                    return FoodCategoryDefaults.calibrate(
                      aiCaloriesPer100g: rawCalPer100,
                      aiProteinPer100g: n.proteinG * per100,
                      aiFatPer100g: n.fatG * per100,
                      aiCarbsPer100g: n.carbsG * per100,
                      category: dish.foodCategory,
                    );
                  })();
          if (!dish.hasPackageNutrition) {
            final rawCalPer100 = n.calories * per100;
            if (caloriesPer100g != rawCalPer100) {
              debugPrint(
                  '[FoodCategoryDefaults] ${dish.dishName}(${dish.foodCategory}) '
                  'AI per100g=$rawCalPer100 偏离品类默认值，校准为 $caloriesPer100g');
            }
          } else {
            debugPrint(
                '[PackageOCR] ${dish.dishName} 使用包装营养表换算 per100g=$caloriesPer100g '
                '(serving=${dish.packageServingG}g/${dish.packageServingKj}kJ/${dish.packageServingKcal}kcal)');
          }
          return foodRepo.upsertAiRecognized(
            name: dish.dishName,
            brand: dish.brand,
            caloriesPer100g: caloriesPer100g,
            proteinPer100g: proteinPer100g,
            fatPer100g: fatPer100g,
            carbsPer100g: carbsPer100g,
            confidence: dish.confidence,
          );
        }

        for (var i = 0; i < allDishes.length; i++) {
          if (!_hitFlags[i]) continue; // 未命中跳过
          final dish = allDishes[i];
          final serving = _servings[i];
          final (cal, p, f, c) = _calcNutrition(i, dish);

          // 获取 foodItemId：单品用查库命中的 foodItemId，复合菜 upsert ai_recognized
          // v1.4：单品若库未命中走 AI 兜底，foodItemId=0 是哨兵，写库前必须替换为真实 id
          // （meal_log.food_item_id 是非空 FK，PRAGMA foreign_keys=ON 时 id=0 触发外键违规崩溃）
          int foodItemId;
          String? componentsSnapshot;
          if (i == 0) {
            if (widget.mainSingle != null) {
              final n = widget.mainSingle!;
              if (n.foodItemId == 0) {
                // 哨兵：AI 兜底结果 → 创建 ai_recognized food_item
                // v1.9：包装 OCR 优先 + 品类校准兜底（共用 resolveSingleFoodItemId）
                foodItemId =
                    await resolveSingleFoodItemId(dish, n, foodRepo);
              } else {
                foodItemId = n.foodItemId;
              }
            } else {
              final oilG = widget.mainComposite?.oilG ?? 0;
              componentsSnapshot = _encodeComponents(dish, oilG: oilG);
              foodItemId = await foodRepo.upsertAiRecognized(
                name: dish.dishName,
                brand: dish.brand,
                caloriesPer100g: 0,
                proteinPer100g: 0,
                fatPer100g: 0,
                carbsPer100g: 0,
                confidence: dish.confidence,
                componentsJson: componentsSnapshot,
              );
            }
          } else {
            final item = widget.additionalItems[i - 1];
            if (item.singleNutrition != null) {
              final n = item.singleNutrition!;
              if (n.foodItemId == 0) {
                // 哨兵：附加菜 AI 兜底 → 创建 ai_recognized food_item
                // v1.9：包装 OCR 优先 + 品类校准兜底（共用 resolveSingleFoodItemId）
                foodItemId =
                    await resolveSingleFoodItemId(dish, n, foodRepo);
              } else {
                foodItemId = n.foodItemId;
              }
            } else {
              final oilG = item.compositeNutrition?.oilG ?? 0;
              componentsSnapshot = _encodeComponents(dish, oilG: oilG);
              foodItemId = await foodRepo.upsertAiRecognized(
                name: dish.dishName,
                brand: dish.brand,
                caloriesPer100g: 0,
                proteinPer100g: 0,
                fatPer100g: 0,
                carbsPer100g: 0,
                confidence: dish.confidence,
                componentsJson: componentsSnapshot,
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
            componentsSnapshotJson: componentsSnapshot,
          );
          recordedCount++;
          totalCal += cal;
        }
      });

      if (!mounted) return;
      if (recordedCount == 0) {
        // 全未命中兜底：引导转手动录入
        showAppToast(context, '所有菜品均未命中库，请转手动录入');
      } else {
        showAppToast(
            context, '已记录 $recordedCount 道菜，合计 ${totalCal.toStringAsFixed(0)} kcal');
        _dirty = false; // 记录成功，允许返回不弹确认
        Navigator.of(context).pop();
      }
    } catch (e) {
      // 异常处理：提示用户，事务已回滚无部分记录
      if (mounted) {
        showAppToast(context, '记录失败：$e');
      }
    } finally {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  /// 把复合菜组分序列化为 JSON 字符串（落库 food_item.components_json + meal_log.components_snapshot_json 用）
  /// 格式与 offline_queue_controller 一致：{components:[{name,estimated_g}], oil_g}
  String? _encodeComponents(VisionRecognitionResult dish, {double oilG = 0}) {
    if (dish.foodComponents.isEmpty) return null;
    return jsonEncode({
      'components': dish.foodComponents
          .map((c) => {'name': c.name, 'estimated_g': c.estimatedG})
          .toList(),
      'oil_g': oilG,
    });
  }
}
