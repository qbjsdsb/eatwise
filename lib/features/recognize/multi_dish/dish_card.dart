import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:flutter/material.dart';

import 'ai_estimate_card.dart';

/// 单道菜品卡片（从 multi_dish_page.dart 拆出，M24 B4）
///
/// 显示菜名 + 命中徽章 + 改菜名按钮 + 份量滑块 + 数量步进器 + 营养素行 + AI 估算卡片。
/// 未命中时显示"库中未找到"提示。
///
/// 数据通过构造函数注入，事件通过回调上抛，不直接访问父 State，
/// 保证 widget 可独立 widget test（无强耦合）。
class DishCard extends StatelessWidget {
  final VisionRecognitionResult dish;
  final bool hit;
  final String currentName;
  final double servings;
  final int quantity;
  final bool isRenaming;
  final NutritionResult? single;
  final CompositeNutritionResult? composite;
  final NutritionResult? aiFallback;

  /// 当前份量的营养素（cal, protein, fat, carbs），由父 State 通过 _calcNutrition 预算后传入
  final (double, double, double, double) nutrition;

  /// 份量滑块变更回调（父 State 更新 _servings + _dirty + 可能反推 _quantities）
  final ValueChanged<double> onServingChanged;

  /// 数量步进器变更回调（父 State 更新 _quantities + _servings + _dirty）
  final ValueChanged<int> onQuantityChanged;

  /// 改菜名按钮回调（父 State 调用 _handleRename）
  final VoidCallback onRenameTap;

  const DishCard({
    super.key,
    required this.dish,
    required this.hit,
    required this.currentName,
    required this.servings,
    required this.quantity,
    required this.isRenaming,
    required this.single,
    required this.composite,
    required this.aiFallback,
    required this.nutrition,
    required this.onServingChanged,
    required this.onQuantityChanged,
    required this.onRenameTap,
  });

  /// v1.3：动态滑块上限（每菜独立）。perUnitG>0 时按 perUnitG×20 扩到 5000 防多份 clamp 少算
  static double sliderMaxFor(VisionRecognitionResult dish) {
    if (dish.perUnitG > 0) {
      return (dish.perUnitG * 20).clamp(1000.0, 5000.0);
    }
    return 1000.0;
  }

  @override
  Widget build(BuildContext context) {
    final (cal, p, f, c) = hit ? nutrition : (0.0, 0.0, 0.0, 0.0);
    // 改菜名按钮显示条件：单品路径（single 非空）或完全未命中（无 composite 数据）
    // 复合菜命中（componentHits 非空）不显示，因为多组分改单名语义复杂
    // 局部变量保证 null 提升跨 || 链生效（final 字段不提升）
    final compositeValue = composite;
    final canRename = single != null ||
        compositeValue == null ||
        compositeValue.componentHits.isEmpty;
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
                  // v1.3：多份时菜名后显示 ×数量（用 state quantity，步进器改后同步）
                  // 改菜名后用 currentName 实时刷新
                  child: Text(
                      '$currentName${quantity > 1 ? " ×$quantity" : ""}',
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
                    icon: isRenaming
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.drive_file_rename_outline,
                            size: 20),
                    onPressed: isRenaming ? null : onRenameTap,
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
              Text('份量：${servings.toStringAsFixed(0)} g'),
              Slider(
                value: servings,
                min: 0,
                max: sliderMaxFor(dish),
                divisions: (sliderMaxFor(dish) / 10).round(),
                label: '${servings.toStringAsFixed(0)} g',
                onChanged: onServingChanged,
              ),
              // v1.3：数量步进器（仅单品命中 + perUnitG > 0 显示）
              _buildQuantityStepper(context),
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
              // M18 Task2: AI 估算卡片（置信度 + 来源徽章 + AI vs 库值对比 + reasoning）
              // 与 calibration_page 风格一致，让用户验证 AI 精度
              const SizedBox(height: 8),
              AiEstimateCard(
                dish: dish,
                single: single,
                composite: composite,
                aiFallback: aiFallback,
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('库中未找到「$currentName」，记录时将跳过此菜',
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

  /// v1.3：数量步进器（同物多份场景，仅单品命中 + perUnitG > 0 显示）
  /// − / 数量+单位 / + 三段式，范围 1-20；改数量时回调父 State 同步 servings = perUnitG × quantity
  Widget _buildQuantityStepper(BuildContext context) {
    if (single == null) return const SizedBox.shrink();
    if (dish.perUnitG <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: '减少数量',
            onPressed: quantity > 1
                ? () => onQuantityChanged(quantity - 1)
                : null,
          ),
          Text('$quantity ${dish.unit}',
              style: Theme.of(context).textTheme.bodyMedium),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '增加数量',
            onPressed: quantity < 20
                ? () => onQuantityChanged(quantity + 1)
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
}
