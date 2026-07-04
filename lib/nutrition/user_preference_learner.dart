// lib/nutrition/user_preference_learner.dart
//
// 用户偏好学习器（v4 推荐算法用）
//
// 从历史 meal_log 学习用户在 4 个维度（口味/风格/材质/价格档）的偏好分布，
// 推荐时给"用户常吃"的标签加分，"用户少碰"的标签减分。
//
// 学习信号：用户吃过 = 偏好信号（隐式反馈，无需显式问"喜欢吗"）。
// 这与 Spotify "听过 = 喜欢" / 抖音 "看完 = 感兴趣" 的隐式反馈学习一致。
//
// 离线友好：纯本地计算，不调 AI。

import 'package:eatwise/data/database/database.dart';

import 'food_profile_tagger.dart';

/// 用户偏好画像（4 维度频次分布）。
///
/// 每维度是 `标签 → 频次` Map，频次越高表示用户越偏好该标签。
class UserPreferenceProfile {
  final Map<String, int> tasteFreq;
  final Map<String, int> styleFreq;
  final Map<String, int> textureFreq;
  final Map<String, int> priceTierFreq;

  const UserPreferenceProfile({
    this.tasteFreq = const {},
    this.styleFreq = const {},
    this.textureFreq = const {},
    this.priceTierFreq = const {},
  });

  /// 是否有足够样本进行偏好推断。
  /// 总样本 < 5 时不启用偏好加权（避免小样本噪声）。
  bool get hasEnoughSamples {
    final total = tasteFreq.values.fold(0, (a, b) => a + b) +
        styleFreq.values.fold(0, (a, b) => a + b);
    return total >= 5;
  }

  /// 用户对某 taste 标签的偏好权重（0.0-1.0）。
  /// - null 或维度无样本 → 0.5（中性，未知）
  /// - 标签不在频次表（用户从未吃过该口味）→ 0.5（中性，未知）
  /// - 标签在频次表 → 频次/max 频次（0.0-1.0）
  double tasteWeight(String? tag) => _weight(tag, tasteFreq);

  double styleWeight(String? tag) => _weight(tag, styleFreq);

  double textureWeight(String? tag) => _weight(tag, textureFreq);

  double priceTierWeight(String? tag) => _weight(tag, priceTierFreq);

  /// 某维度是否有显著偏好（top1 占比 >= 0.4 且样本 >= 3）。
  /// 用于 reason 文案生成（避免"符合您口味"过度出现）。
  bool get hasSignificantTastePref => _hasSignificantPref(tasteFreq);
  bool get hasSignificantStylePref => _hasSignificantPref(styleFreq);
  bool get hasSignificantTexturePref => _hasSignificantPref(textureFreq);
  bool get hasSignificantPricePref => _hasSignificantPref(priceTierFreq);

  static double _weight(String? tag, Map<String, int> freq) {
    if (tag == null) return 0.5; // 未知 → 中性
    if (freq.isEmpty) return 0.5; // 无样本 → 中性
    if (!freq.containsKey(tag)) return 0.5; // 用户从未吃过该标签 → 中性（不惩罚未知）
    final max = freq.values.reduce((a, b) => a > b ? a : b);
    if (max == 0) return 0.5;
    return freq[tag]! / max; // 0-1
  }

  static bool _hasSignificantPref(Map<String, int> freq) {
    if (freq.length < 2) return false;
    final total = freq.values.fold(0, (a, b) => a + b);
    if (total < 3) return false;
    final max = freq.values.reduce((a, b) => a > b ? a : b);
    return max / total >= 0.4;
  }
}

/// 用户偏好学习器：从 meal_log 历史学习偏好画像。
///
/// 用法：
/// ```dart
/// final foods = await foodRepo.listAllForRecommendation();
/// final foodMap = {for (final f in foods) f.id: f};
/// final meals = await mealRepo.getRecentMeals(days: 30);
/// final pref = UserPreferenceLearner().learn(meals, foodMap);
/// ```
class UserPreferenceLearner {
  UserPreferenceLearner._(); // 仅纯函数，禁止实例化（保持 API 与 FoodProfileTagger 一致）

  /// 从 meal_log 列表学习用户偏好。
  ///
  /// [foodMap] 用于查 food_item_id → FoodItem（取 name 给标签器）。
  /// food_item 已删除的 meal_log 跳过（不计数）。
  /// 返回 [UserPreferenceProfile]。
  static UserPreferenceProfile learn(
    List<MealLog> meals,
    Map<int, FoodItem> foodMap,
  ) {
    final tasteFreq = <String, int>{};
    final styleFreq = <String, int>{};
    final textureFreq = <String, int>{};
    final priceTierFreq = <String, int>{};

    for (final m in meals) {
      final food = foodMap[m.foodItemId];
      if (food == null) continue; // 食物已删除，跳过
      final tags = FoodProfileTagger.tag(food.name);
      if (tags.taste != null) {
        tasteFreq[tags.taste!] = (tasteFreq[tags.taste!] ?? 0) + 1;
      }
      if (tags.style != null) {
        styleFreq[tags.style!] = (styleFreq[tags.style!] ?? 0) + 1;
      }
      if (tags.texture != null) {
        textureFreq[tags.texture!] = (textureFreq[tags.texture!] ?? 0) + 1;
      }
      if (tags.priceTier != null) {
        priceTierFreq[tags.priceTier!] = (priceTierFreq[tags.priceTier!] ?? 0) + 1;
      }
    }

    return UserPreferenceProfile(
      tasteFreq: tasteFreq,
      styleFreq: styleFreq,
      textureFreq: textureFreq,
      priceTierFreq: priceTierFreq,
    );
  }
}
