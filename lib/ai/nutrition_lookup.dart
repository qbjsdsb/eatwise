import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'vision_provider.dart';

/// 烹饪方式用油系数表（设计文档 3.1 节）
/// 默认用油量 g/份
const cookingOilCoefficients = <String, double>{
  'steam': 0, // 蒸
  'boil': 0, // 煮（通常不加油）
  'cold': 8, // 凉拌
  'toss': 8, // 拌（同凉拌）
  'roast': 8, // 烤
  'stir-fry': 12, // 炒
  'pan-fry': 15, // 煎
  'deep-fry': 25, // 炸
  'braise': 10, // 红烧
  'raw': 0, // 生食
};

/// 油的营养素（每 100g，花生油近似值）
const oilCaloriesPer100g = 889.0;
const oilFatPer100g = 99.9;

class NutritionLookup {
  final FoodItemRepository _repo;

  NutritionLookup(this._repo);

  /// 单品查库回填
  /// 返回 null 表示未命中（调用方转手动录入）
  Future<NutritionResult?> lookupSingleItem({
    required String dishName,
    required double servingG,
  }) async {
    final food = await _repo.findByNameOrAlias(dishName);
    if (food == null) return null;

    return NutritionResult(
      foodItemId: food.id,
      calories: food.caloriesPer100g * servingG / 100,
      proteinG: food.proteinPer100g * servingG / 100,
      fatG: food.fatPer100g * servingG / 100,
      carbsG: food.carbsPer100g * servingG / 100,
      oilG: 0,
    );
  }

  /// 复合菜组分累加 + 烹饪用油
  Future<CompositeNutritionResult> lookupCompositeDish({
    required List<FoodComponent> components,
    required String cookingMethod,
  }) async {
    final hits = <ComponentHit>[];
    final misses = <String>[];
    double totalCalories = 0;
    double totalProtein = 0;
    double totalFat = 0;
    double totalCarbs = 0;

    for (final comp in components) {
      final food = await _repo.findByNameOrAlias(comp.name);
      if (food == null) {
        misses.add(comp.name);
        continue;
      }
      final g = comp.estimatedG;
      totalCalories += food.caloriesPer100g * g / 100;
      totalProtein += food.proteinPer100g * g / 100;
      totalFat += food.fatPer100g * g / 100;
      totalCarbs += food.carbsPer100g * g / 100;
      hits.add(
        ComponentHit(
          name: comp.name,
          foodItemId: food.id,
          estimatedG: g,
          caloriesPer100g: food.caloriesPer100g,
          proteinPer100g: food.proteinPer100g,
          fatPer100g: food.fatPer100g,
          carbsPer100g: food.carbsPer100g,
        ),
      );
    }

    // 加烹饪用油
    final oilG = cookingOilCoefficients[cookingMethod] ?? 0;
    if (oilG > 0) {
      totalCalories += oilCaloriesPer100g * oilG / 100;
      totalFat += oilFatPer100g * oilG / 100;
    }

    return CompositeNutritionResult(
      calories: totalCalories,
      proteinG: totalProtein,
      fatG: totalFat,
      carbsG: totalCarbs,
      oilG: oilG,
      componentHits: hits,
      componentMisses: misses,
    );
  }

  /// 单品区间计算（Low/Mid/High 三档份量）
  /// 设计 5.6：估算区间 ±10%（MVP 统一，单品实际 ±3-5% 但 UI 简化展示）
  Future<NutritionRange?> lookupSingleItemWithRange({
    required String dishName,
    required double servingGLow,
    required double servingGMid,
    required double servingGHigh,
  }) async {
    final low = await lookupSingleItem(
      dishName: dishName,
      servingG: servingGLow,
    );
    final mid = await lookupSingleItem(
      dishName: dishName,
      servingG: servingGMid,
    );
    final high = await lookupSingleItem(
      dishName: dishName,
      servingG: servingGHigh,
    );
    if (low == null || mid == null || high == null) return null;
    return NutritionRange(low: low, mid: mid, high: high);
  }

  /// 复合菜区间计算（Low/Mid/High 三档份量，按比例缩放）
  /// 复合菜组分 estimatedG 是单值，区间按 Mid 份量 ±10% 缩放
  Future<CompositeNutritionRange> lookupCompositeDishWithRange({
    required List<FoodComponent> components,
    required String cookingMethod,
  }) async {
    final mid = await lookupCompositeDish(
      components: components,
      cookingMethod: cookingMethod,
    );
    // Low/High 按份量 ±10% 缩放（组分份量按比例）
    final lowComponents = components
        .map((c) => FoodComponent(name: c.name, estimatedG: c.estimatedG * 0.9))
        .toList();
    final highComponents = components
        .map((c) => FoodComponent(name: c.name, estimatedG: c.estimatedG * 1.1))
        .toList();
    final low = await lookupCompositeDish(
      components: lowComponents,
      cookingMethod: cookingMethod,
    );
    final high = await lookupCompositeDish(
      components: highComponents,
      cookingMethod: cookingMethod,
    );
    return CompositeNutritionRange(low: low, mid: mid, high: high);
  }
}

class NutritionResult {
  final int foodItemId;
  final double calories;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final double oilG;

  const NutritionResult({
    required this.foodItemId,
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.oilG,
  });
}

/// 营养素区间（Low/Mid/High 三档，设计 5.6 估算区间）
class NutritionRange {
  final NutritionResult low;
  final NutritionResult mid;
  final NutritionResult high;

  const NutritionRange({
    required this.low,
    required this.mid,
    required this.high,
  });
}

/// 复合菜营养素区间
class CompositeNutritionRange {
  final CompositeNutritionResult low;
  final CompositeNutritionResult mid;
  final CompositeNutritionResult high;

  const CompositeNutritionRange({
    required this.low,
    required this.mid,
    required this.high,
  });
}

class CompositeNutritionResult {
  final double calories;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final double oilG;
  final List<ComponentHit> componentHits;
  final List<String> componentMisses;

  const CompositeNutritionResult({
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.oilG,
    required this.componentHits,
    required this.componentMisses,
  });
}

class ComponentHit {
  final String name;
  final int foodItemId;
  final double estimatedG;
  // per100g 营养素（校准页重算用，lookup 时一次性填充）
  final double caloriesPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;

  const ComponentHit({
    required this.name,
    required this.foodItemId,
    required this.estimatedG,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
  });
}
