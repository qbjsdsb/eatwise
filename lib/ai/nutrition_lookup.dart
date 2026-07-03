import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'off_provider.dart';
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
  // OFF 云查兜底（可选：生产注入，测试不注入则行为同原逻辑，向后兼容）
  final OffProvider? _offProvider;

  NutritionLookup(this._repo, {OffProvider? offProvider})
      : _offProvider = offProvider;

  /// 单品查库回填
  /// 查库未命中 → OFF 云查兜底（若配置了 offProvider）→ 命中落库（source='off'）
  /// 返回 null 表示未命中（调用方转手动录入）
  ///
  /// 建议 1：可食部分系数（ediblePercent）
  /// servingG 来自 AI 估算的"图中食物整重"（含皮/骨/壳），而 FCT 的 caloriesPer100g
  /// 是"每 100g 可食部分"的营养值。若不乘 ediblePercent，香蕉（edible=65%）、
  /// 带骨排骨（edible=50%）会系统性高估热量 30-100%。
  /// 系数取 (ediblePercent ?? 100).clamp(1,100)/100，null/异常值按 100% 兜底。
  /// 注：复合菜组分（lookupCompositeDish）已是可食部分克数，不乘此系数。
  Future<NutritionResult?> lookupSingleItem({
    required String dishName,
    required double servingG,
    String brand = '',
  }) async {
    final food = await _repo.findByNameOrAlias(dishName, brand: brand);
    if (food != null) {
      // 复合菜以 per100g=0 占位存储（实际热量在 meal_log.componentsSnapshotJson），
      // 单品查库命中这类记录会返回 0 热量造成数据污染。
      // 视为未命中返回 null，让调用方走 AI 兜底或 OFF 云查。
      if (food.componentsJson != null) return null;
      // 建议 1：可食部分系数（仅单品，FCT 水果/带骨肉类需要；包装食品 ediblePercent=null 按 100%）
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

    // miss → OFF 云查兜底（P2-1：传 brand+name 组合查询提升命中率）
    if (_offProvider != null) {
      final off = await _offProvider.lookup(dishName, brand: brand);
      if (off != null) {
        // 命中落库：aliases 传菜名本身，下次同名精确命中（避免重复云查）
        final foodId = await _repo.insertOff(
          name: dishName,
          caloriesPer100g: off.caloriesPer100g,
          proteinPer100g: off.proteinPer100g,
          fatPer100g: off.fatPer100g,
          carbsPer100g: off.carbsPer100g,
          defaultServingG: off.defaultServingG,
          aliases: <String>[dishName],
        );
        return NutritionResult(
          foodItemId: foodId,
          calories: off.caloriesPer100g * servingG / 100,
          proteinG: off.proteinPer100g * servingG / 100,
          fatG: off.fatPer100g * servingG / 100,
          carbsG: off.carbsPer100g * servingG / 100,
          oilG: 0,
        );
      }
    }

    return null;
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

  /// 单品区间计算（Low/Mid/High 三档份量）
  /// 设计 5.6：估算区间 ±10%（MVP 统一，单品实际 ±3-5% 但 UI 简化展示）
  Future<NutritionRange?> lookupSingleItemWithRange({
    required String dishName,
    required double servingGLow,
    required double servingGMid,
    required double servingGHigh,
  }) async {
    final low = await lookupSingleItem(dishName: dishName, servingG: servingGLow);
    final mid = await lookupSingleItem(dishName: dishName, servingG: servingGMid);
    final high = await lookupSingleItem(dishName: dishName, servingG: servingGHigh);
    if (low == null || mid == null || high == null) return null;
    return NutritionRange(low: low, mid: mid, high: high);
  }

  /// 复合菜区间计算（Low/Mid/High 三档份量，按比例缩放）
  /// 复合菜组分 estimatedG 是单值，区间按 Mid 份量 ±10% 缩放
  Future<CompositeNutritionRange> lookupCompositeDishWithRange({
    required List<FoodComponent> components,
    required String cookingMethod,
  }) async {
    final mid = await lookupCompositeDish(components: components, cookingMethod: cookingMethod);
    // Low/High 按份量 ±10% 缩放（组分份量按比例）
    final lowComponents = components.map((c) => FoodComponent(name: c.name, estimatedG: c.estimatedG * 0.9)).toList();
    final highComponents = components.map((c) => FoodComponent(name: c.name, estimatedG: c.estimatedG * 1.1)).toList();
    final low = await lookupCompositeDish(components: lowComponents, cookingMethod: cookingMethod);
    final high = await lookupCompositeDish(components: highComponents, cookingMethod: cookingMethod);
    return CompositeNutritionRange(low: low, mid: mid, high: high);
  }
}

/// 营养数据来源（校准页展示徽章用）
enum NutritionSource { database, aiEstimate }

class NutritionResult {
  final int foodItemId;
  final double calories;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final double oilG;
  /// 数据来源：database=本地食物库命中；aiEstimate=库未命中时 AI 兜底估算
  /// （foodItemId=0 为哨兵，recognize_page 写库前用 upsertAiRecognized 替换为真实 id）
  final NutritionSource source;

  const NutritionResult({
    required this.foodItemId,
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.oilG,
    this.source = NutritionSource.database,
  });
}

/// 营养素区间（Low/Mid/High 三档，设计 5.6 估算区间）
class NutritionRange {
  final NutritionResult low;
  final NutritionResult mid;
  final NutritionResult high;

  const NutritionRange({required this.low, required this.mid, required this.high});
}

/// 复合菜营养素区间
class CompositeNutritionRange {
  final CompositeNutritionResult low;
  final CompositeNutritionResult mid;
  final CompositeNutritionResult high;

  const CompositeNutritionRange({required this.low, required this.mid, required this.high});
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
