// 食物品类营养值物理 clamp（每 100g）
//
// 历史：
// - M16.8 曾用"品类均值校准 AI 离谱估算"（偏离 2 倍用默认值替代）+ PostProcessor 宏量反推
// - 方案 D（M25）废弃品类校准——根因：用"模糊均值"覆盖"AI 具体估算"方向错误，
//   米粉汤 AI 推理 526 kcal（合理）被 soup 默认 30 打成 171 kcal + 75g 碳水（物理不可能自洽）
// - v2 改动 F：删除 defaults 表 + 4 个 getter（lib 层已无引用，PostProcessor 宏量反推已删）
//
// 现状：
// - 只保留 calibrate 方法做物理 clamp（[0,900] 防物理不可能值 + 宏量 [0,100]）
// - 防离谱能力由"PostProcessor 重试机制"+"validator warnings 提示"+"reasoning 透明可审查"+"用户手动纠正"承担

/// 品类营养值物理 clamp（v2 改动 F：defaults 表已删，只剩 calibrate）
class FoodCategoryDefaults {
  FoodCategoryDefaults._();

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
  /// - 防离谱能力由 PostProcessor 重试 + validator warnings + reasoning 审查 + 用户手动纠正承担
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
