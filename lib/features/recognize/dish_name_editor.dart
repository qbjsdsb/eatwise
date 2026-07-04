// lib/features/recognize/dish_name_editor.dart
//
// 改菜名→搜库→重算 共享逻辑
//
// recognize_page / calibration_page / multi_dish_page 三处都需要"识别错误改菜名"
// 的能力，逻辑完全一致（弹输入框 → 搜库 → 候选选择 → 5 级模糊兜底 → 返回 NutritionResult）。
// 抽到 mixin 避免代码重复，命中后由调用方决定如何更新 UI（recognize_page 跳新
// CalibrationPage；calibration_page 用 setState 替换内部 state；multi_dish_page
// 替换对应菜的 state）。

import 'package:flutter/material.dart';

import '../../ai/nutrition_lookup.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';

/// 改菜名→搜库→重算 的共享逻辑
///
/// 使用方需 `with DishNameEditor` 并在调用前确保 mounted。
/// 流程：
/// 1. [_promptNewDishName] 弹输入框（预填原菜名）
/// 2. [_searchAndLookup] 搜库 + 5 级模糊兜底
/// 3. 命中返回 NutritionResult，未命中返回 null（调用方可递归再弹或提示）
mixin DishNameEditor<T extends StatefulWidget> on State<T> {
  /// 弹输入框让用户改菜名，返回新菜名（null=取消/空）
  Future<String?> promptNewDishName(String original) async {
    final ctrl = TextEditingController(text: original);
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('修改菜名'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: '菜名'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  /// 用 FoodItem + 份量构造 NutritionResult（候选列表选中后用）
  ///
  /// 同步 lookupSingleItem 的可食部分系数（servingG 为 AI 整重，需乘 ediblePercent），
  /// 符合硬约束 #4：per100g 反算基于 estimatedWeightGMid。
  NutritionResult nutritionFromFoodItem(FoodItem food, double servingG) {
    final edibleFactor = (food.ediblePercent ?? 100).clamp(1, 100) / 100;
    final effectiveG = servingG * edibleFactor;
    return NutritionResult(
      foodItemId: food.id,
      calories: food.caloriesPer100g * effectiveG / 100,
      proteinG: food.proteinPer100g * effectiveG / 100,
      fatG: food.fatPer100g * effectiveG / 100,
      carbsG: food.carbsPer100g * effectiveG / 100,
      oilG: 0,
    );
  }

  /// 食物候选列表选择对话框（多候选时让用户选）
  Future<FoodItem?> showFoodSelectionDialog(
      List<FoodItem> candidates) async {
    return showDialog<FoodItem>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择匹配的食物'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (ctx, i) {
              final f = candidates[i];
              return ListTile(
                title: Text(f.name),
                subtitle: Text(
                  '${f.caloriesPer100g.toStringAsFixed(0)} kcal/100g',
                ),
                onTap: () => Navigator.pop(ctx, f),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 完整的"改菜名→搜库→重算"流程
  ///
  /// [originalName] 原菜名（预填到输入框）
  /// [servingG] AI 估算份量（用于 per100g 反算，符合硬约束 #4）
  /// [foodRepo] 食物库 repo
  /// [lookup] NutritionLookup 实例（5 级模糊兜底 + OFF 云查）
  ///
  /// 返回 (新菜名, NutritionResult?)，新菜名 null=用户取消，NutritionResult null=未命中
  Future<({String? newName, NutritionResult? nutrition})> editDishNameAndLookup({
    required String originalName,
    required double servingG,
    required FoodItemRepository foodRepo,
    required NutritionLookup lookup,
  }) async {
    final newName = await promptNewDishName(originalName);
    if (newName == null || newName.isEmpty || !mounted) {
      return (newName: null, nutrition: null);
    }

    // L4：改菜名场景用户已输入精准关键词，30 候选在 AlertDialog 内滚动筛选成本高，
    // 10 足够（GLM 5 级模糊兜底仍保留，仍能命中别名/拼音/模糊匹配）
    final candidates = await foodRepo.searchByName(newName, limit: 10);
    if (!mounted) return (newName: newName, nutrition: null);

    NutritionResult? nutrition;
    if (candidates.isEmpty) {
      // searchByName 无结果 → 5 级模糊匹配兜底（含 OFF 云查）
      nutrition = await lookup.lookupSingleItem(
        dishName: newName,
        servingG: servingG,
      );
    } else if (candidates.length == 1) {
      // 唯一候选 → 直接用
      nutrition = nutritionFromFoodItem(candidates.first, servingG);
    } else {
      // 多候选 → 列表选择
      final selected = await showFoodSelectionDialog(candidates);
      if (selected == null || !mounted) {
        return (newName: newName, nutrition: null);
      }
      nutrition = nutritionFromFoodItem(selected, servingG);
    }

    return (newName: newName, nutrition: nutrition);
  }

  /// 未命中时的提示 toast
  void showNotFoundToast() {
    if (!mounted) return;
    showAppToast(context, '食物库未命中「改菜名」，可转手动录入或再试一次');
  }
}
