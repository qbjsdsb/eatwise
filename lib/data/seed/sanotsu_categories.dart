// Sanotsu 完整数据常吃分类文件清单
// 仓库：https://github.com/Sanotsu/china-food-composition-data
// 数据组织：json_data/merged-{大类}-{子类}.json

/// Sanotsu 完整数据常吃大类前缀（用于过滤 json_data/ 下的文件）
/// 跳过：婴幼儿食品、特殊医学用途婴儿配方食品
const sanotsuEdibleCategories = [
  '蔬菜类', '水果类', '谷类', '薯类', '干豆类', '大豆类',
  '坚果种子类', '畜肉类', '禽肉类', '蛋类', '鱼类', '软体动物类',
  '虾蟹类', '乳类', '调味品类', '菌藻类',
];

/// 油脂类（花生油/大豆油等，用于 nutrition_lookup 的 cookingOilCoefficients 补充）
const sanotsuOilCategories = ['动物油脂类', '植物油脂类'];

/// 判断 Sanotsu json 文件名是否属于常吃分类
/// fileName 格式：merged-蔬菜类及其制品-根菜类.json
bool isEdibleCategory(String fileName) {
  for (final cat in [...sanotsuEdibleCategories, ...sanotsuOilCategories]) {
    if (fileName.contains(cat)) return true;
  }
  return false;
}
