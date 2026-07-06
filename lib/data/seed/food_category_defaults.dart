// 食物品类默认营养值表（每 100g）
//
// 用途：AI 兜底（库未命中 + OFF 未命中）时的最后防线。
//
// 历史：M16.8 曾用"品类均值校准 AI 离谱估算"（偏离 2 倍用默认值替代）。
// 方案 D（M25）废弃品类校准——根因：用"模糊均值"覆盖"AI 具体估算"方向错误，
// 米粉汤 AI 推理 526 kcal（合理）被 soup 默认 30 打成 171 kcal + 75g 碳水（物理不可能自洽）。
// 品类校准造成的误伤比防住的离谱更多。
//
// 现状：
// - `defaults` 表保留：PostProcessor 宏量反推修正（cal>0 但宏量缺失时按比例填充）仍需品类默认比例
// - `calibrate` 只保留物理 clamp（[0,900] 防物理不可能值），不再用品类均值覆盖 AI 估算
// - 防离谱能力由"PostProcessor 重试机制"+"reasoning 透明可审查"+"用户手动纠正"承担
//
// 数据来源：中国食物成分表 + USDA + 业界实测平均值。
// 与 prompts.dart 的 food_category 枚举一一对应。

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
  /// - tea 含糖茶饮：43 kcal（菊花茶/冰红茶/柠檬茶等加糖茶饮，糖含量约 10-11g/100ml）
  /// - protein_drink 蛋白饮料：60 kcal（豆奶/杏仁奶/蛋白饮料均值，蛋白 3g/脂肪 1.5g/碳水 5g）
  /// - energy_drink 功能饮料：45 kcal（红牛/魔爪等，糖含量约 11g/100ml）
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
    'tea': (43, 0.1, 0, 10.6), // v1.10：含糖茶饮（菊花茶/冰红茶等），近似 carbonated
    'protein_drink': (60, 3, 1.5, 5), // v1.10：豆奶/杏仁奶/蛋白饮料
    'energy_drink': (45, 0, 0, 11), // v1.10：红牛/魔爪等功能饮料
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
  /// 方案 D（M25）：废弃品类校准，只保留物理 clamp。
  ///
  /// 历史：M16.8 曾用品类均值校准（偏离 2 倍用默认值替代），但造成误伤：
  /// - 米粉汤 AI 推理 526 kcal（合理）被 soup 默认 30 打成 171 kcal + 75g 碳水（物理不可能自洽）
  /// - 八宝粥/奶油汤等高变异品类全被误伤
  /// - 校准策略本身不自洽（calories 用默认值，宏量用 AI 值，破坏 Atwater）
  ///
  /// 现状规则：
  /// - 4 项全保留 AI 估算值（信任 AI 具体估算 + reasoning 透明可审查）
  /// - calories clamp 到 [0, 900]（防物理不可能值，如 AI 把水估成 5000）
  /// - 蛋白/脂肪/碳水 clamp 到 [0, 100]（不可能超 100g/100g）
  /// - 防离谱能力由 PostProcessor 重试 + reasoning 审查 + 用户手动纠正承担
  ///
  /// [aiCaloriesPer100g] AI 估算的每 100g 热量
  /// [category] food_category（保留参数向后兼容，方案 D 不再使用）
  /// 返回 (calories, protein, fat, carbs) 每 100g
  static (double, double, double, double) calibrate({
    required double aiCaloriesPer100g,
    required double aiProteinPer100g,
    required double aiFatPer100g,
    required double aiCarbsPer100g,
    required String category,
  }) {
    // 方案 D：4 项全保留 AI 估算值，只做物理 clamp
    // calories clamp [0, 900]：900 是 solid 上限（纯脂肪油 889，solid 不含纯油）
    // 宏量 clamp [0, 100]：不可能超 100g/100g，不允许负值
    return (
      aiCaloriesPer100g.clamp(0.0, 900.0),
      aiProteinPer100g.clamp(0.0, 100.0),
      aiFatPer100g.clamp(0.0, 100.0),
      aiCarbsPer100g.clamp(0.0, 100.0),
    );
  }
}
