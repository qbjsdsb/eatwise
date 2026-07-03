// 食物密度表（建议 3）
//
// 解决问题：prompt v1.6 让 AI 读取包装净含量（如"500ml"），但 per_unit_g 填的是 ml 数值，
// 按 1ml=1g 假设换算。这对水基饮料（可乐/雪碧）OK，但对以下品类系统性偏差：
//   - 食用油 1ml≈0.92g → 100ml 油按 100g 算，热量低估 8%
//   - 蜂蜜 1ml≈1.42g → 100ml 蜂蜜按 100g 算，热量低估 42%
//   - 奶油 1ml≈0.95g → 低估 5%
//   - 烈酒 1ml≈0.79g → 低估 21%
//
// 密度值来源：USDA FoodData Central + 食品科学常用值（g/ml）
// 单位：g/ml（1ml 液体的质量克数）
//
// 使用方式：AI 返回 food_category，controller 后处理时若为包装液体（weight_source=package_label
// 且 food_category 非 solid），用密度把 per_unit_g（实为 ml）换算成真实克数。
const Map<String, double> foodDensityTable = <String, double>{
  'water': 1.00, // 纯水
  'carbonated': 1.00, // 碳酸饮料（可乐/雪碧/苏打水，含糖但 CO2 抵消）
  'juice': 1.05, // 果汁（含糖略重于水）
  'milk': 1.03, // 牛奶
  'cream': 0.95, // 奶油/淡奶油
  'oil': 0.92, // 植物油（花生油/橄榄油/菜籽油）
  'honey': 1.42, // 蜂蜜/糖浆
  'sauce': 1.10, // 酱油/酱汁（含盐略重）
  'alcohol': 0.79, // 烈酒（白酒/伏特加/威士忌）
  'beer': 1.01, // 啤酒
  'wine': 0.99, // 葡萄酒
  'yogurt': 1.05, // 酸奶
  'soup': 1.00, // 汤
  'solid': 1.00, // 固体（不换算）
};

/// 查询食物类别的密度（g/ml）
/// 未知类别按 1.0 兜底（水密度，保守不放大误差）
double densityOf(String? foodCategory) {
  if (foodCategory == null || foodCategory.isEmpty) return 1.0;
  return foodDensityTable[foodCategory] ?? 1.0;
}

/// 是否液体类别（需要按密度换算 ml→g）
bool isLiquidCategory(String? foodCategory) {
  if (foodCategory == null || foodCategory.isEmpty) return false;
  return foodCategory != 'solid';
}
