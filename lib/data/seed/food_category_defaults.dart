// 食物品类默认营养值表（每 100g）
//
// 用途：AI 兜底（库未命中 + OFF 未命中）时的最后防线校准。
// 当 AI 估算的 calories 偏离品类默认值 2 倍以上时，用默认值替代——防 AI 离谱估算
// （如把啤酒估成 200 kcal/100g，实际 43）。只校准离谱值，不限制合理估算。
//
// 数据来源：中国食物成分表 + USDA + 业界实测平均值。
// 与 prompts.dart 的 food_category 枚举一一对应。
//
// 设计原则：
// - 品类默认值是"防离谱"兜底，不是"精确值"——AI 合理估算优先
// - 偏离阈值 2 倍：啤酒默认 43，AI 估 86 仍接受，估 200 则用 43
// - 只校准 calories（最重要），蛋白/脂肪/碳水保留 AI 值（各品类差异大）

/// 品类默认营养值（每 100g）
class FoodCategoryDefaults {
  FoodCategoryDefaults._();

  /// food_category → (caloriesPer100g, proteinPer100g, fatPer100g, carbsPer100g)
  ///
  /// 数据来源说明：
  /// - beer 啤酒：43 kcal（酒精 3.5% × 7 kcal/g + 碳水 3.1g × 4 kcal/g ≈ 37，加残糖 ≈ 43）
  /// - wine 葡萄酒：83 kcal（酒精 12% × 7 ≈ 84）
  /// - alcohol 烈酒（白酒）：298 kcal（酒精 40% × 7 = 280，+ 微量碳水）
  /// - carbonated 碳酸饮料：43 kcal（可乐 42-45 区间均值）
  /// - juice 果汁：46 kcal（橙汁 47/苹果汁 46 均值）
  /// - milk 纯牛奶：61 kcal（全脂牛奶 GB 28050）
  /// - yogurt 酸奶：72 kcal（原味酸奶均值，加糖酸奶更高但按原味兜底）
  /// - cream 奶油：345 kcal
  /// - oil 植物油：889 kcal（花生油近似）
  /// - honey 蜂蜜：321 kcal
  /// - sauce 酱汁：63 kcal（酱油均值，差异大但防离谱够用）
  /// - soup 汤：30 kcal（清汤均值，奶油汤更高但少数）
  /// - water 纯水：0 kcal
  /// - solid 固体/散装：不提供默认值（差异太大，如米饭 116 vs 薯片 547），AI 估算优先
  static const Map<String, (double, double, double, double)> defaults = {
    'beer': (43, 0.5, 0, 3.1),
    'wine': (83, 0.1, 0, 2.6),
    'alcohol': (298, 0, 0, 0),
    'carbonated': (43, 0, 0, 10.6),
    'juice': (46, 0.5, 0.1, 11.2),
    'milk': (61, 3.2, 3.6, 4.8),
    'yogurt': (72, 2.5, 2.7, 9.3),
    'cream': (345, 2.2, 36, 2.9),
    'oil': (889, 0, 99.9, 0),
    'honey': (321, 0.5, 0, 80),
    'sauce': (63, 5, 0.6, 8),
    'soup': (30, 1.5, 0.8, 3.5),
    'water': (0, 0, 0, 0),
    // solid 不在此表，AI 估算优先（差异太大无默认值意义）
  };

  /// 获取品类默认 calories，solid/未知品类返回 null（不校准）
  static double? caloriesPer100g(String category) {
    final v = defaults[category];
    return v?.$1;
  }

  /// 获取品类默认蛋白，solid/未知品类返回 null
  static double? proteinPer100g(String category) {
    final v = defaults[category];
    return v?.$2;
  }

  /// 获取品类默认脂肪，solid/未知品类返回 null
  static double? fatPer100g(String category) {
    final v = defaults[category];
    return v?.$3;
  }

  /// 获取品类默认碳水，solid/未知品类返回 null
  static double? carbsPer100g(String category) {
    final v = defaults[category];
    return v?.$4;
  }

  /// 校准 AI 估算的 per100g 营养值。
  ///
  /// 规则：AI 估算的 caloriesPer100g 偏离品类默认值 2 倍以上（高或低），
  /// 用品类默认值（4 项全替）；否则保留 AI 估算。
  /// solid/未知品类（无默认值）不校准，直接返回 AI 估算。
  ///
  /// [aiCaloriesPer100g] AI 估算的每 100g 热量
  /// [category] food_category（beer/wine/carbonated/solid 等）
  /// 返回 (calories, protein, fat, carbs) 每 100g
  static (double, double, double, double) calibrate({
    required double aiCaloriesPer100g,
    required double aiProteinPer100g,
    required double aiFatPer100g,
    required double aiCarbsPer100g,
    required String category,
  }) {
    final defCal = defaults[category]?.$1;
    // 无默认值的品类（solid 等）不校准，保留 AI 估算
    if (defCal == null) {
      return (aiCaloriesPer100g, aiProteinPer100g, aiFatPer100g, aiCarbsPer100g);
    }
    // 偏离 2 倍以上（高或低）用默认值；defCal=0（water）时 AI 任何正值都算偏离
    final ratio = defCal > 0 ? aiCaloriesPer100g / defCal : (aiCaloriesPer100g > 0 ? 999.0 : 1.0);
    if (ratio > 2.0 || ratio < 0.5) {
      final d = defaults[category]!;
      return (d.$1, d.$2, d.$3, d.$4);
    }
    return (aiCaloriesPer100g, aiProteinPer100g, aiFatPer100g, aiCarbsPer100g);
  }
}
