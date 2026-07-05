import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/vision_provider.dart';
import '../../core/util/date_format.dart';
import '../../core/widgets/m3_widgets.dart';
import '../manual_entry/manual_entry_page.dart';
import 'calibrated_nutrition_calculator.dart';
import 'dish_name_editor.dart';
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
  /// M16.8：主菜 AI 兜底估算，查库命中时用于差异检测（偏差 > 50% 用 AI 反算 per100g）
  final NutritionResult? mainAiFallback;
  final List<MultiDishItem> additionalItems;
  final String mealType;
  final String? imagePath;

  const MultiDishPage({
    super.key,
    required this.mainDish,
    this.mainSingle,
    this.mainComposite,
    this.mainAiFallback,
    required this.additionalItems,
    required this.mealType,
    this.imagePath,
  });

  @override
  ConsumerState<MultiDishPage> createState() => _MultiDishPageState();
}

class _MultiDishPageState extends ConsumerState<MultiDishPage>
    with DishNameEditor<MultiDishPage> {
  // 每菜的份量状态（索引 0=主菜，1..n=additionalDishes）
  late List<double> _servings;
  // v1.3：每菜的数量状态（同物多份，索引与 _servings 对齐）
  late List<int> _quantities;
  // 每菜是否命中库（未命中需标红提示转手动）
  late List<bool> _hitFlags;
  // 防重入：记录中禁止连点
  bool _isRecording = false;
  bool _dirty = false; // 用户是否改过滑块份量/数量（PopScope 未保存确认用）
  // 改菜名支持：每菜当前菜名 + 当前单品营养（命中后 setState 替换）
  // _currentSingles 跟踪每菜的单品营养（rename 后写入；复合菜保留 null）
  late List<String> _currentNames;
  late List<NutritionResult?> _currentSingles;
  // 每菜"改菜名"防重入标志（独立于 _isRecording，允许同时改多个菜名）
  late List<bool> _isRenamingFlags;

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
    // 改菜名：菜名和单品营养从 widget 拷贝到 state（rename 后 setState 替换）
    _currentNames = allDishes.map((d) => d.dishName).toList();
    _currentSingles = [
      widget.mainSingle,
      ...widget.additionalItems.take(5).map((e) => e.singleNutrition),
    ];
    _isRenamingFlags = List.filled(allDishes.length, false);
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
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                Text(
                    '蛋白质 ${totalProtein.toStringAsFixed(1)} g · 脂肪 ${totalFat.toStringAsFixed(0)} g · 碳水 ${totalCarbs.toStringAsFixed(0)} g',
                    style: TextStyle(
                        fontFeatures: const [
                          FontFeature.tabularFigures()
                        ],
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
    // 改菜名按钮显示条件：单品路径（_currentSingles 非空）或完全未命中（无 composite 数据）
    // 复合菜命中（componentHits 非空）不显示，因为多组分改单名语义复杂
    final composite = _getCompositeNutrition(index);
    final canRename = _currentSingles[index] != null ||
        composite == null || composite.componentHits.isEmpty;
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
                  // 改菜名后用 _currentNames[index] 实时刷新
                  child: Text(
                      '${_currentNames[index]}${_quantities[index] > 1 ? " ×${_quantities[index]}" : ""}',
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
                // 改菜名按钮（icon button，紧凑布局）
                if (canRename)
                  IconButton(
                    icon: _isRenamingFlags[index]
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.drive_file_rename_outline,
                            size: 20),
                    onPressed: _isRenamingFlags[index]
                        ? null
                        : () => _handleRename(index),
                    tooltip: '改菜名',
                    // 触控目标 ≥48dp（Material 3 可访问性标准）；
                    // 保留 padding: EdgeInsets.zero 维持紧凑视觉，仅放大 constraints
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 48, minHeight: 48),
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
                  '${cal.toStringAsFixed(0)} kcal · 蛋白 ${p.toStringAsFixed(1)} g · 脂肪 ${f.toStringAsFixed(0)} g · 碳水 ${c.toStringAsFixed(0)} g',
                  style: TextStyle(
                      fontFeatures: const [
                        FontFeature.tabularFigures()
                      ],
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant)),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('库中未找到「${_currentNames[index]}」，记录时将跳过此菜',
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
  /// 改菜名后用 _currentSingles[index]（rename 后实时刷新）
  NutritionResult? _getSingleNutrition(int index) => _currentSingles[index];

  /// 获取某菜的复合菜查库结果（判断是否复合菜路径用）
  /// 改菜名不影响 composite 数据（rename 后 composite 仍来自 widget 原值）
  CompositeNutritionResult? _getCompositeNutrition(int index) {
    if (index == 0) return widget.mainComposite;
    if (index - 1 < widget.additionalItems.length) {
      return widget.additionalItems[index - 1].compositeNutrition;
    }
    return null;
  }

  /// M16.8：获取某菜的 AI 兜底估算（查库命中时用于差异检测）
  /// 主菜用 widget.mainAiFallback，附加菜用 additionalItems[i].aiFallback
  NutritionResult? _getAiFallback(int index) {
    if (index == 0) return widget.mainAiFallback;
    if (index - 1 < widget.additionalItems.length) {
      return widget.additionalItems[index - 1].aiFallback;
    }
    return null;
  }

  /// M16.8：查库命中分支差异检测计算（_calcNutrition 预览 + _recordAll 记录共用，
  /// 保证预览=记录）。
  ///
  /// 条件：_currentSingles[index] 非空 + foodItemId > 0（查库命中）+ aiFallback 非空 +
  ///       无包装营养表（包装是精确值，不走差异检测）。
  /// 返回 null 表示不满足条件，调用方走原逻辑（n.* * ratio）。
  CalibratedNutrition? _computeLookupHitCalibrated(
      int index, VisionRecognitionResult dish, double serving) {
    // 包装营养表优先（精确值，不走差异检测）
    if (dish.hasPackageNutrition) return null;
    final n = _currentSingles[index];
    if (n == null || n.foodItemId <= 0) return null;
    final aiFallback = _getAiFallback(index);
    if (aiFallback == null) return null;
    return CalibratedNutritionCalculator.compute(
      recognitionResult: dish,
      aiFallback: aiFallback,
      servingG: serving,
      lookupHitNutrition: n,
    );
  }

  /// M16.9：复合菜查库命中 + AI 整菜估算 → AI 绝对优先
  /// M18：抽取为 CalibratedNutritionCalculator.computeCompositeLookupHit 公共方法
  /// 三路径（recognize_page / multi_dish_page / offline_queue_controller）共用
  /// per100g 从 0 占位改为 AI 反算值，让 AI 估算进入食物库
  CalibratedNutrition? _computeCompositeLookupHitCalibrated(
      int index, VisionRecognitionResult dish, double serving) {
    // 包装营养表优先（精确值，不走差异检测）
    if (dish.hasPackageNutrition) return null;
    final composite = _getCompositeNutrition(index);
    if (composite == null) return null;
    final aiFallback = _getAiFallback(index);
    if (aiFallback == null) return null;
    // 委托公共方法：AI 有效返回 per100g=AI 反算值 + actualXxx；AI 无效返回 null
    return CalibratedNutritionCalculator.computeCompositeLookupHit(
      aiFallback: aiFallback,
      servingG: serving,
      mid: dish.estimatedWeightGMid,
    );
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
            tooltip: '减少数量',
            onPressed: _quantities[index] > 1
                ? () => _onQuantityChanged(index, _quantities[index] - 1, dish)
                : null,
          ),
          Text('${_quantities[index]} ${dish.unit}',
              style: Theme.of(context).textTheme.bodyMedium),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '增加数量',
            onPressed: _quantities[index] < 20
                ? () => _onQuantityChanged(index, _quantities[index] + 1, dish)
                : null,
          ),
          const SizedBox(width: 8),
          Text('（每${dish.unit} ${dish.perUnitG.toStringAsFixed(0)} g）',
              style: TextStyle(
                  fontFeatures: const [
                    FontFeature.tabularFigures()
                  ],
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
    // v1.9：有包装营养表数据时，按包装 per100g 换算（精确值），跳过库值/AI 估算
    // 包装换算热量 = per100g × serving / 100（直接用份量，与单品 ratio 缩放结果一致）
    // v1.10：包装换算宏量全 0 但 cal>0（含糖饮料 AI 漏填宏量）→ 不返回 0，继续走下游路径
    if (dish.hasPackageNutrition) {
      final per100 = dish.computePackageNutritionPer100g(
        estimatedProteinG: dish.estimatedProteinG,
        estimatedFatG: dish.estimatedFatG,
        estimatedCarbsG: dish.estimatedCarbsG,
      );
      // v1.10：仅当宏量非全 0 才用包装换算结果（含糖饮料兜底走下游 n.* ratio）
      if (per100 != null && (per100.$2 > 0 || per100.$3 > 0 || per100.$4 > 0)) {
        return (
          per100.$1 * serving / 100,
          per100.$2 * serving / 100,
          per100.$3 * serving / 100,
          per100.$4 * serving / 100,
        );
      }
    }
    if (index == 0) {
      // 主菜
      // M16.8：查库命中 + aiFallback → 差异检测（与 _recordAll 一致，保证预览=记录）
      final calibrated = _computeLookupHitCalibrated(0, dish, serving);
      if (calibrated != null) {
        return (
          calibrated.actualCalories,
          calibrated.actualProteinG,
          calibrated.actualFatG,
          calibrated.actualCarbsG,
        );
      }
      // 改菜名后用 _currentSingles[0]（rename 后实时刷新）
      if (_currentSingles[0] != null) {
        final n = _currentSingles[0]!;
        return (
          n.calories * ratio,
          n.proteinG * ratio,
          n.fatG * ratio,
          n.carbsG * ratio,
        );
      }
      // M16.9：复合菜查库命中 + AI 整菜估算 → AI 绝对优先
      final compositeCalibrated = _computeCompositeLookupHitCalibrated(0, dish, serving);
      if (compositeCalibrated != null) {
        return (
          compositeCalibrated.actualCalories,
          compositeCalibrated.actualProteinG,
          compositeCalibrated.actualFatG,
          compositeCalibrated.actualCarbsG,
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
      // M16.8：查库命中 + aiFallback → 差异检测（与 _recordAll 一致，保证预览=记录）
      final calibrated = _computeLookupHitCalibrated(index, dish, serving);
      if (calibrated != null) {
        return (
          calibrated.actualCalories,
          calibrated.actualProteinG,
          calibrated.actualFatG,
          calibrated.actualCarbsG,
        );
      }
      // 改菜名后用 _currentSingles[index]（rename 后实时刷新）
      if (_currentSingles[index] != null) {
        final n = _currentSingles[index]!;
        return (
          n.calories * ratio,
          n.proteinG * ratio,
          n.fatG * ratio,
          n.carbsG * ratio,
        );
      }
      // M16.9：复合菜查库命中 + AI 整菜估算 → AI 绝对优先
      final compositeCalibrated = _computeCompositeLookupHitCalibrated(index, dish, serving);
      if (compositeCalibrated != null) {
        return (
          compositeCalibrated.actualCalories,
          compositeCalibrated.actualProteinG,
          compositeCalibrated.actualFatG,
          compositeCalibrated.actualCarbsG,
        );
      }
      final item = widget.additionalItems[index - 1];
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

  /// 改菜名→搜库→重算 单菜（多菜列表页）
  /// 命中后 setState 替换 _currentNames[i] + _currentSingles[i] + _hitFlags[i]=true
  /// 未命中弹 toast 提示，原菜名和营养保留不变
  /// 取消（newName==null）静默返回，不打扰用户
  Future<void> _handleRename(int index) async {
    if (_isRenamingFlags[index]) return; // 防重入
    setState(() => _isRenamingFlags[index] = true);
    try {
      final lookup = await ref.read(nutritionLookupProvider.future);
      final foodRepo = await ref.read(foodItemRepoProvider.future);
      if (!mounted) return;
      final dish = (index == 0)
          ? widget.mainDish
          : widget.additionalItems[index - 1].dish;
      final result = await editDishNameAndLookup(
        originalName: _currentNames[index],
        // 用 AI 估算 mid 作 servingG（per100g 反算基准，符合硬约束 #4）
        servingG: dish.estimatedWeightGMid,
        foodRepo: foodRepo,
        lookup: lookup,
      );
      if (!mounted) return;
      // 用户取消：静默返回
      if (result.newName == null) return;
      // 命中：替换菜名 + 单品营养 + 标记命中，标记 dirty（PopScope 未保存确认）
      if (result.nutrition != null) {
        setState(() {
          _currentNames[index] = result.newName!;
          _currentSingles[index] = result.nutrition;
          _hitFlags[index] = true;
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
      // 防御性兜底（lookup 内部异常 / provider 异常）
      if (mounted) showAppToast(context, '改菜名失败：$e');
    } finally {
      if (mounted) setState(() => _isRenamingFlags[index] = false);
    }
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
        for (var i = 0; i < allDishes.length; i++) {
          if (!_hitFlags[i]) continue; // 未命中跳过
          final dish = allDishes[i];
          final serving = _servings[i];
          // 注意：哨兵分支会覆盖为校准后的 actualXxx，其他分支保留 _calcNutrition 原值
          var (cal, p, f, c) = _calcNutrition(i, dish);
          // 改菜名后用 _currentNames[i] 写库（rename + 兜底场景才走 upsert）
          final effectiveName = _currentNames[i];

          // 获取 foodItemId：单品用查库命中的 foodItemId，复合菜 upsert ai_recognized
          // v1.4：单品若库未命中走 AI 兜底，foodItemId=0 是哨兵，写库前必须替换为真实 id
          // （meal_log.food_item_id 是非空 FK，PRAGMA foreign_keys=ON 时 id=0 触发外键违规崩溃）
          // 改菜名后 _currentSingles[i] 优先于 widget.mainSingle / additionalItems.single
          int foodItemId;
          String? componentsSnapshot;
          final composite = _getCompositeNutrition(i);
          if (_currentSingles[i] != null) {
            final n = _currentSingles[i]!;
            if (n.foodItemId == 0) {
              // 哨兵：AI 兜底 / 改菜名 + OFF 兜底 → 创建 ai_recognized food_item
              // M16.6：用 CalibratedNutritionCalculator 统一计算 per100g（写库）+ actualXxx（写 meal_log），
              // 保证 meal_log.actualCalories 与 food_item.caloriesPer100g 数据一致，
              // 避免推理过程数值与最终记录数值脱节（包装 OCR / 品类校准由 calculator 内部处理）
              final calibrated = CalibratedNutritionCalculator.compute(
                recognitionResult: dish,
                aiFallback: n,
                servingG: serving,
              );
              foodItemId = await foodRepo.upsertAiRecognized(
                name: effectiveName,
                brand: dish.brand,
                caloriesPer100g: calibrated.caloriesPer100g,
                proteinPer100g: calibrated.proteinPer100g,
                fatPer100g: calibrated.fatPer100g,
                carbsPer100g: calibrated.carbsPer100g,
                confidence: dish.confidence,
              );
              // 用校准后的 actualXxx 覆盖 _calcNutrition 返回的未校准值，
              // 不变量：actualXxx = 校准后 per100g * servingG / 100
              cal = calibrated.actualCalories;
              p = calibrated.actualProteinG;
              f = calibrated.actualFatG;
              c = calibrated.actualCarbsG;
            } else {
              // M16.8：查库命中 + aiFallback → 差异检测（与 _calcNutrition 一致，保证预览=记录）
              // 偏差 > 50% 用 AI 反算 per100g 写库 + 用 AI 值记 meal_log
              // （修复 reasoning 显示 AI 估算但记录用库值致脱节）
              // 偏差 ≤ 50% 用库值（cal/p/f/c 保持 _calcNutrition 返回值，已基于 DB per100g）
              // 无 aiFallback / 有包装营养表时保持原行为（foodItemId = n.foodItemId）
              final calibrated = _computeLookupHitCalibrated(i, dish, serving);
              if (calibrated != null) {
                foodItemId = calibrated.foodItemId;
                cal = calibrated.actualCalories;
                p = calibrated.actualProteinG;
                f = calibrated.actualFatG;
                c = calibrated.actualCarbsG;
                // 偏差大时用 AI 反算 per100g 纠正脏库
                if (calibrated.shouldUpdateFoodItem) {
                  await foodRepo.updatePer100g(
                    foodItemId: calibrated.foodItemId,
                    caloriesPer100g: calibrated.caloriesPer100g,
                    proteinPer100g: calibrated.proteinPer100g,
                    fatPer100g: calibrated.fatPer100g,
                    carbsPer100g: calibrated.carbsPer100g,
                  );
                }
              } else {
                foodItemId = n.foodItemId;
              }
            }
          } else if (composite != null) {
            // M16.9：复合菜查库命中 + AI 整菜估算 → AI 绝对优先
            // 显式覆盖 cal/p/f/c，与 _calcNutrition 保持一致（预览=记录）
            final compositeCalibrated = _computeCompositeLookupHitCalibrated(i, dish, serving);
            if (compositeCalibrated != null) {
              cal = compositeCalibrated.actualCalories;
              p = compositeCalibrated.actualProteinG;
              f = compositeCalibrated.actualFatG;
              c = compositeCalibrated.actualCarbsG;
            }
            final oilG = composite.oilG;
            componentsSnapshot = _encodeComponents(dish, oilG: oilG);
            // v1.9：复合菜有包装营养表数据时（预包装速冻食品等），per100g 用包装换算值（替代 0）
            // v1.10：包装换算宏量全 0 但 cal>0（含糖饮料 AI 漏填宏量）→ per100g 用 0 占位，
            //   避免写入库的 food_item 宏量全 0 误导未来查库（与 offline_queue 复合菜全命中路径一致）
            // M18：AI 有效（compositeCalibrated != null，必然无包装）时 per100g 用 AI 反算值
            //   替代 0 占位，让 AI 估算进入食物库供未来查库复用
            //   AI 无效（compositeCalibrated == null）时保持原逻辑（包装换算 / 0 占位）
            final packagePer100 = dish.hasPackageNutrition
                ? dish.computePackageNutritionPer100g(
                    estimatedProteinG: dish.estimatedProteinG,
                    estimatedFatG: dish.estimatedFatG,
                    estimatedCarbsG: dish.estimatedCarbsG,
                  )
                : null;
            // v1.10：判断包装换算宏量是否全 0（含糖饮料 AI 漏填宏量特征）
            final packageMacrosAllZero = packagePer100 != null &&
                packagePer100.$2 == 0 &&
                packagePer100.$3 == 0 &&
                packagePer100.$4 == 0;
            // M18：AI 有效时 per100g 用 AI 反算值；否则按原包装/0 占位逻辑
            final useAiPer100 = compositeCalibrated != null;
            foodItemId = await foodRepo.upsertAiRecognized(
              name: effectiveName,
              brand: dish.brand,
              caloriesPer100g: useAiPer100
                  ? compositeCalibrated.caloriesPer100g
                  : (packagePer100 != null && !packageMacrosAllZero)
                      ? packagePer100.$1
                      : 0,
              proteinPer100g: useAiPer100
                  ? compositeCalibrated.proteinPer100g
                  : (packagePer100 != null && !packageMacrosAllZero)
                      ? packagePer100.$2
                      : 0,
              fatPer100g: useAiPer100
                  ? compositeCalibrated.fatPer100g
                  : (packagePer100 != null && !packageMacrosAllZero)
                      ? packagePer100.$3
                      : 0,
              carbsPer100g: useAiPer100
                  ? compositeCalibrated.carbsPer100g
                  : (packagePer100 != null && !packageMacrosAllZero)
                      ? packagePer100.$4
                      : 0,
              confidence: dish.confidence,
              componentsJson: componentsSnapshot,
            );
          } else {
            // 主菜/附加菜均无营养数据（理论不应到这里，因 _hitFlags[i] 已守卫）
            // 防御性兜底：用 effectiveName 创建空 food_item，避免后续 insertMealLog FK 违规
            foodItemId = await foodRepo.upsertAiRecognized(
              name: effectiveName,
              brand: dish.brand,
              caloriesPer100g: 0,
              proteinPer100g: 0,
              fatPer100g: 0,
              carbsPer100g: 0,
              confidence: dish.confidence,
            );
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
