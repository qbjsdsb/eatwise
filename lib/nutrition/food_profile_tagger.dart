// lib/nutrition/food_profile_tagger.dart
//
// 食物画像标签器（v4 推荐算法用）
//
// 用户反馈"智能推荐完全不智能，根据每个人的饮食习惯自己学习，多维度（材质/价格/口味/风格）"。
// 食物库无显式口味/风格/材质/价格档字段，本类用关键词匹配推断 4 维度标签：
//   - taste（口味）：sweet/sour/bitter/spicy/salty/light
//   - style（风格）：chinese/western/japanese/korean/fast_food/home/seafood
//   - texture（材质/烹饪法）：soup/stir_fry/steamed/boiled/grilled/fried/cold
//   - priceTier（价格档）：budget/medium/premium
//
// 关键词匹配是离线友好的（不调 AI），与项目"无网络也能用"硬约束一致。
// AI 接入留待后续 enhancement（见 HANDOFF）。

/// 食物画像标签（4 维度）。
///
/// 每个维度可能为 null（关键词未匹配到）。null 表示"未知"，推荐侧给中性分。
class FoodProfileTags {
  final String? taste;
  final String? style;
  final String? texture;
  final String? priceTier;

  const FoodProfileTags({this.taste, this.style, this.texture, this.priceTier});

  @override
  String toString() =>
      'FoodProfileTags(taste=$taste, style=$style, texture=$texture, priceTier=$priceTier)';
}

/// 食物画像标签器：基于关键词匹配推断 4 维度标签。
///
/// 设计要点：
/// - 关键词表是中餐语境下的常识集合（《中国居民膳食指南》 + 薄荷健康高频食物 + 外卖平台分类）
/// - 一个食物可能命中多个关键词，取第一个匹配（顺序按"特征性强"优先）
/// - 关键词命中即返回，不调用任何外部服务（离线友好）
class FoodProfileTagger {
  FoodProfileTagger._(); // 仅静态方法，禁止实例化

  /// 口味关键词 → taste 标签。
  /// 顺序：特征性强的在前（"麻辣"先于"麻"，避免被通用词抢匹配）。
  static const _tasteKeywords = <String, String>{
    // 甜
    '甜': 'sweet',
    '糖醋': 'sweet',
    '蜜汁': 'sweet',
    '巧克力': 'sweet',
    '蛋糕': 'sweet',
    '冰淇淋': 'sweet',
    '雪糕': 'sweet',
    '饼干': 'sweet',
    '面包': 'sweet',
    '豆沙': 'sweet',
    // 酸
    '酸菜': 'sour',
    '酸辣': 'sour',
    '醋': 'sour',
    '柠檬': 'sour',
    '泡菜': 'sour',
    '酸奶': 'sour',
    // 苦
    '苦瓜': 'bitter',
    '苦菜': 'bitter',
    // 辣（含麻）— 注："酸辣"已归入 sour（酸味更主导），此处不重复
    '麻辣': 'spicy',
    '香辣': 'spicy',
    '辣椒': 'spicy',
    '辣子': 'spicy',
    '川菜': 'spicy',
    '湘菜': 'spicy',
    '渝菜': 'spicy',
    '火锅': 'spicy',
    '麻辣烫': 'spicy',
    '麻婆': 'spicy',
    '辣': 'spicy',
    '麻': 'spicy',
    // 咸
    '咸鱼': 'salty',
    '咸肉': 'salty',
    '咸蛋': 'salty',
    '腊肉': 'salty',
    '火腿': 'salty',
    '香肠': 'salty',
    '腌': 'salty',
    '酱': 'salty',
    // 清淡
    '清淡': 'light',
    '清蒸': 'light',
    '白灼': 'light',
    '清炖': 'light',
    '粥': 'light',
  };

  /// 风格关键词 → style 标签。
  /// 顺序：海鲜优先（"三文鱼刺身" 应归 seafood 而非 japanese，海鲜是更具体的标签）
  static const _styleKeywords = <String, String>{
    // 海鲜（独立风格，跨中西）— 优先匹配
    '海鲜': 'seafood',
    '龙虾': 'seafood',
    '扇贝': 'seafood',
    '生蚝': 'seafood',
    '三文鱼': 'seafood',
    '鳕鱼': 'seafood',
    '鲈鱼': 'seafood',
    '虾': 'seafood',
    '蟹': 'seafood',
    '贝': 'seafood',
    // 西式
    '牛排': 'western',
    '披萨': 'western',
    '意面': 'western',
    '汉堡': 'western',
    '三明治': 'western',
    '沙拉': 'western',
    '西餐': 'western',
    '炸鸡': 'western',
    '薯条': 'western',
    // 日式
    '寿司': 'japanese',
    '刺身': 'japanese',
    '天妇罗': 'japanese',
    '日式': 'japanese',
    '拉面': 'japanese',
    '味噌': 'japanese',
    '饭团': 'japanese',
    // 韩式
    '韩式': 'korean',
    '石锅': 'korean',
    '部队锅': 'korean',
    '韩餐': 'korean',
    '烤肉': 'korean',
    // 快餐/外卖
    '快餐': 'fast_food',
    '外卖': 'fast_food',
    '盒饭': 'fast_food',
    '便当': 'fast_food',
    '麦当劳': 'fast_food',
    '肯德基': 'fast_food',
    // 家常（默认中式家常）
    '家常': 'home',
    '小炒': 'home',
    '炒饭': 'home',
    '炒面': 'home',
  };

  /// 材质/烹饪法关键词 → texture 标签。
  static const _textureKeywords = <String, String>{
    // 汤羹
    '汤': 'soup',
    '羹': 'soup',
    '煲': 'soup',
    '炖汤': 'soup',
    // 炒
    '小炒': 'stir_fry',
    '爆炒': 'stir_fry',
    '炒': 'stir_fry',
    // 蒸
    '清蒸': 'steamed',
    '蒸': 'steamed',
    // 煮/炖
    '炖': 'boiled',
    '煮': 'boiled',
    '煲汤': 'boiled',
    '卤': 'boiled',
    // 烤/烧
    '烤': 'grilled',
    '烧': 'grilled',
    '叉烧': 'grilled',
    // 炸/煎
    '油炸': 'fried',
    '酥炸': 'fried',
    '炸': 'fried',
    '煎': 'fried',
    '生煎': 'fried',
    // 凉拌
    '凉拌': 'cold',
    '冷盘': 'cold',
    '凉菜': 'cold',
    '冰': 'cold',
  };

  /// 价格档关键词 → priceTier 标签。
  /// 推断依据：食材本身的市价档位（非品牌溢价）。
  static const _priceTierKeywords = <String, String>{
    // 经济（主食/快餐）
    '米饭': 'budget',
    '馒头': 'budget',
    '包子': 'budget',
    '面条': 'budget',
    '粥': 'budget',
    '盒饭': 'budget',
    '快餐': 'budget',
    // 精致（高价食材）
    '牛排': 'premium',
    '龙虾': 'premium',
    '三文鱼': 'premium',
    '海参': 'premium',
    '鱼翅': 'premium',
    '鲍鱼': 'premium',
    '松露': 'premium',
    '和牛': 'premium',
  };

  /// 给食物打 4 维度标签。
  ///
  /// 每维度按关键词表顺序匹配，命中即返回；多关键词命中取第一个。
  /// 全部未命中返回 `FoodProfileTags()`（全 null）。
  static FoodProfileTags tag(String name) {
    return FoodProfileTags(
      taste: _matchFirst(name, _tasteKeywords),
      style: _matchFirst(name, _styleKeywords),
      texture: _matchFirst(name, _textureKeywords),
      priceTier: _matchFirst(name, _priceTierKeywords),
    );
  }

  /// 按 keyword 表顺序匹配，返回第一个命中值。
  static String? _matchFirst(String name, Map<String, String> keywords) {
    for (final entry in keywords.entries) {
      if (name.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// taste 标签 → 中文展示文案（reason 文案用）
  static String tasteLabel(String taste) => const {
        'sweet': '甜',
        'sour': '酸',
        'bitter': '苦',
        'spicy': '辣',
        'salty': '咸',
        'light': '清淡',
      }[taste] ??
      taste;

  /// style 标签 → 中文展示文案
  static String styleLabel(String style) => const {
        'chinese': '中式',
        'western': '西式',
        'japanese': '日式',
        'korean': '韩式',
        'fast_food': '快餐',
        'home': '家常',
        'seafood': '海鲜',
      }[style] ??
      style;

  /// texture 标签 → 中文展示文案
  static String textureLabel(String texture) => const {
        'soup': '汤水',
        'stir_fry': '小炒',
        'steamed': '清蒸',
        'boiled': '炖煮',
        'grilled': '烧烤',
        'fried': '煎炸',
        'cold': '凉拌',
      }[texture] ??
      texture;

  /// priceTier 标签 → 中文展示文案
  static String priceTierLabel(String priceTier) => const {
        'budget': '经济',
        'medium': '适中',
        'premium': '精致',
      }[priceTier] ??
      priceTier;
}
