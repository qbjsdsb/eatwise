// 食物名占位符工具：foodItemId 反查 food_items 未命中时的兜底显示
// 集中管理避免各处 '食物 #id' 模板分裂（修改格式只改一处）

/// 占位食物名（foodItemId 反查未命中时显示）
String placeholderFoodName(int id) => '食物 #$id';

/// 是否为占位食物名（反馈回流别名学习时排除占位名）
bool isPlaceholderFoodName(String name) => name.startsWith('食物 #');

/// 食物来源标签（food_item.source 字段 → 中文显示）
/// 集中管理避免 food_edit_page / food_library_page 各处 switch 分裂
/// （新增 source 类型时只改一处）
String foodSourceLabel(String source) {
  switch (source) {
    case 'china_fct':
      return '中国成分表';
    case 'usda':
      return 'USDA';
    case 'manual':
      return '手动';
    case 'ai_recognized':
      return 'AI 入库';
    case 'off':
      return 'OFF 云查';
    default:
      return source;
  }
}
