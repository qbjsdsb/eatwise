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
      hits.add(ComponentHit(
        name: comp.name,
        foodItemId: food.id,
        estimatedG: g,
        caloriesPer100g: food.caloriesPer100g,
        proteinPer100g: food.proteinPer100g,
        fatPer100g: food.fatPer100g,
        carbsPer100g: food.carbsPer100g,
      ));
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
