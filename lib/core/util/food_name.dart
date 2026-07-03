// 食物名占位符工具：foodItemId 反查 food_items 未命中时的兜底显示
// 集中管理避免各处 '食物 #id' 模板分裂（修改格式只改一处）

/// 占位食物名（foodItemId 反查未命中时显示）
String placeholderFoodName(int id) => '食物 #$id';

/// 是否为占位食物名（反馈回流别名学习时排除占位名）
bool isPlaceholderFoodName(String name) => name.startsWith('食物 #');
