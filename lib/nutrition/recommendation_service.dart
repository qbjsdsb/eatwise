import 'dart:math';

import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';

/// 当日剩余额度（C 功能：智能推荐基础数据）
class DailyRemaining {
  final double remainingCalories; // 剩余热量（目标-已记录），负值表示已超标
  final double remainingProtein; // 剩余蛋白质 g
  final double remainingFat; // 剩余脂肪 g
  final double remainingCarbs; // 剩余碳水 g
  final int targetCalories;
  final double proteinGoal;
  final double fatGoal;
  final double carbGoal;
  final double consumedCalories;
  final double consumedProtein;
  final double consumedFat;
  final double consumedCarbs;

  const DailyRemaining({
    required this.remainingCalories,
    required this.remainingProtein,
    required this.remainingFat,
    required this.remainingCarbs,
    required this.targetCalories,
    required this.proteinGoal,
    required this.fatGoal,
    required this.carbGoal,
    required this.consumedCalories,
    required this.consumedProtein,
    required this.consumedFat,
    required this.consumedCarbs,
  });

  /// 是否有蛋白质缺口（推荐算法关键信号）
  bool get hasProteinGap => remainingProtein > 5;

  /// 是否热量已超标（不再推荐高热量食物）
  bool get isCalorieOver => remainingCalories < 0;
}

/// 推荐食物项（含评分，用于 UI 展示排序原因）
class RecommendedFood {
  final FoodItem food;
  final double score; // 评分越高越优先
  final String reason; // 推荐理由（UI 展示）

  const RecommendedFood({
    required this.food,
    required this.score,
    required this.reason,
  });
}

/// 智能推荐服务（C 功能）
///
/// v3 五维评分（参考业界饮食推荐 + 项目实际数据约束）：
/// 1. 相对缺口匹配（内容推荐 Content-Based）：三大宏量缺口比例，最缺的加权
/// 2. 冷门降权 + 基础食材加权（频次 + 热门度）：避免冷门高密度食物霸榜，
///    常吃/基础食材优先（直击"推荐冷门"痛点）
/// 3. profile 约束过滤（约束推荐 Constraint-Based）：素食/乳糖不耐/无麸质/
///    糖尿病/肾病按 profile 字段过滤或降权（v0.11.1 已加字段但推荐侧未用）
/// 4. 时段感知（Time-aware）：数据驱动学习每个食物的历史 mealType 分布，
///    当前时段匹配则加分（比硬编码"早餐食物"更贴合个人习惯）
/// 5. 多样性（Diversity）：排除今日已吃 + 降权昨日已吃，避免每天重复
///
/// 弃用方案：协同过滤（单机无用户群）、AI 生成食谱（离线 app）、
/// 替换建议（需建食物替代图谱，工程量大留后续）
class RecommendationService {
  final FoodItemRepository _foodRepo;
  final MealLogRepository _mealRepo;
  final ProfileRepository _profileRepo;

  RecommendationService(this._foodRepo, this._mealRepo, this._profileRepo);

  /// 基础食材白名单（常见中式家常食材，硬编码无需改 DB）。
  /// 命中即视为"基础食材"，给底分保证常见食物不沉底。
  /// 来源：参考《中国居民膳食指南》日常推荐 + 薄荷健康/MyFitnessPal 高频食物。
  static const _basicFoodKeywords = [
    // 蛋白来源
    '鸡蛋', '鸡胸', '鸡腿', '鸡肉', '牛奶', '酸奶', '豆腐', '豆浆',
    '瘦牛肉', '牛肉', '瘦猪肉', '猪肉', '三文鱼', '鳕鱼', '鱼', '虾',
    '蛋白', '鸡', '鸭',
    // 主食碳水
    '米饭', '糙米', '燕麦', '全麦', '面包', '馒头', '包子', '粥',
    '面条', '意面', '红薯', '紫薯', '玉米', '土豆', '藜麦', '小米',
    // 蔬果
    '苹果', '香蕉', '橙子', '番茄', '西红柿', '黄瓜', '白菜', '菠菜',
    '西兰花', '生菜', '胡萝卜', '芹菜', '蘑菇', '蓝莓', '梨', '葡萄',
  ];

  /// 肉类/海鲜关键词（素食过滤用）
  static const _meatFishKeywords = [
    '鸡', '鸭', '鹅', '猪', '牛', '羊', '鱼', '虾', '蟹', '贝', '蛤',
    '蚝', '鱿鱼', '章鱼', '海参', '肉', '火腿', '培根', '香肠', '腊',
  ];

  /// 蛋奶关键词（纯素过滤用）
  static const _eggDairyKeywords = [
    '鸡蛋', '鸭蛋', '鸡蛋黄', '蛋白', '牛奶', '酸奶', '奶酪', '芝士',
    '奶油', '黄油', '蛋黄',
  ];

  /// 乳制品关键词（乳糖不耐过滤用）
  static const _dairyKeywords = ['牛奶', '酸奶', '奶酪', '芝士', '奶油'];

  /// 麸质关键词（无麸质过滤用）
  static const _glutenKeywords = ['面包', '面条', '馒头', '包子', '饺子',
    '饼干', '蛋糕', '麦', '面粉', '拉面', '意面'];

  /// 高糖关键词（糖尿病降权用）
  static const _highSugarKeywords = ['糖', '糕', '饼', '饮料', '汽水', '果汁',
    '蜜', '巧克力', '冰淇淋', '雪糕', '蛋糕', '甜'];

  /// 计算当日剩余额度
  Future<DailyRemaining> getDailyRemaining(String date) async {
    final macros = await _mealRepo.getMacrosByDate(date);
    final profile = await _profileRepo.get();
    final proteinGoal = profile.proteinGPerKg * profile.weightKg;
    final fatGoal = profile.fatGPerKg * profile.weightKg;
    final carbGoalRaw = profile.carbGPerKg != null
        ? profile.carbGPerKg! * profile.weightKg
        : (profile.dailyCalorieTarget - proteinGoal * 4 - fatGoal * 9) / 4;
    final carbGoal = carbGoalRaw < 0 ? 0.0 : carbGoalRaw;

    return DailyRemaining(
      remainingCalories: profile.dailyCalorieTarget - macros.calories,
      remainingProtein: proteinGoal - macros.protein,
      remainingFat: fatGoal - macros.fat,
      remainingCarbs: carbGoal - macros.carbs,
      targetCalories: profile.dailyCalorieTarget,
      proteinGoal: proteinGoal,
      fatGoal: fatGoal,
      carbGoal: carbGoal,
      consumedCalories: macros.calories,
      consumedProtein: macros.protein,
      consumedFat: macros.fat,
      consumedCarbs: macros.carbs,
    );
  }

  /// 推荐食物（按五维评分排序，取 top limit）
  ///
  /// v3 在 v2（缺口匹配 + 频次 + 排除今日）基础上新增三维度：
  /// - [profile]：传入则按饮食偏好/健康状况过滤或降权；不传则跳过该维度（向后兼容）
  /// - [mealType]：当前时段（breakfast/lunch/dinner/snck），传入则按时段分布加分
  /// - [yesterdayDate]：昨日日期，传入则昨日已吃食物降权（多样性）
  Future<List<RecommendedFood>> recommend({
    required DailyRemaining remaining,
    int limit = 5,
    String todayDate = '',
    Profile? profile,
    String mealType = '',
    String yesterdayDate = '',
  }) async {
    final foods = await _foodRepo.listAllForRecommendation();
    if (foods.isEmpty) return [];

    // 并行获取：今日已吃 + 频次 + 时段分布 + 昨日已吃
    final todayEatenFuture = todayDate.isEmpty
        ? Future.value(<int>{})
        : _mealRepo.getMealsByDate(todayDate).then(
            (meals) => meals.map((m) => m.foodItemId).toSet());
    final yesterdayEatenFuture = yesterdayDate.isEmpty
        ? Future.value(<int>{})
        : _mealRepo.getMealsByDate(yesterdayDate).then(
            (meals) => meals.map((m) => m.foodItemId).toSet());
    final freqFuture = _mealRepo.getRecentFoodCounts(days: 30);
    final distFuture = mealType.isEmpty
        ? Future.value(<int, Map<String, double>>{})
        : _mealRepo.getMealTypeDistribution(days: 60);

    final todayEaten = await todayEatenFuture;
    final yesterdayEaten = await yesterdayEatenFuture;
    final freq = await freqFuture;
    final dist = await distFuture;

    final recommendations = <RecommendedFood>[];
    for (final food in foods) {
      // 排除今日已吃（避免重复推荐刚吃过的）
      if (todayEaten.contains(food.id)) continue;
      // profile 约束硬过滤（素食/乳糖/麸质直接排除）
      if (profile != null && _shouldExcludeByProfile(food, profile)) continue;
      final (score, reason) = _scoreFood(
        food, remaining, freq, dist, yesterdayEaten,
        profile: profile, mealType: mealType,
      );
      if (score > 0) {
        recommendations
            .add(RecommendedFood(food: food, score: score, reason: reason));
      }
    }
    recommendations.sort((a, b) => b.score.compareTo(a.score));
    return recommendations.take(limit).toList();
  }

  /// 单个食物五维评分（v3）
  /// 返回 (score, reason)。score <= 0 表示不推荐（被过滤）。
  (double, String) _scoreFood(
    FoodItem food,
    DailyRemaining rem,
    Map<int, int> freq,
    Map<int, Map<String, double>> mealTypeDist,
    Set<int> yesterdayEaten, {
    Profile? profile,
    String mealType = '',
  }) {
    double score = 0;
    final reasons = <String>[];

    // 过滤异常食物（calories=0 的可能是数据缺失）
    if (food.caloriesPer100g <= 0 && food.proteinPer100g <= 0) {
      return (0, '');
    }

    // 维度 2（前置）：判断是否常吃/基础食材，决定蛋白加权系数
    final count = freq[food.id] ?? 0;
    final isPopular = count > 0;
    final isBasic = _isBasicFood(food.name);
    // 冷门降权：常吃 *4，基础食材 *3，冷门 *1.5（直击"冷门霸榜"痛点）
    final proteinWeight = isPopular ? 4.0 : (isBasic ? 3.0 : 1.5);

    // 维度 1：相对缺口匹配（三大宏量缺口比例，取最缺者加权）
    final proteinGapRatio = rem.proteinGoal > 0
        ? (rem.remainingProtein / rem.proteinGoal).clamp(-1.0, 1.0)
        : 1.0;
    final fatGapRatio = rem.fatGoal > 0
        ? (rem.remainingFat / rem.fatGoal).clamp(-1.0, 1.0)
        : 1.0;
    final carbGapRatio = rem.carbGoal > 0
        ? (rem.remainingCarbs / rem.carbGoal).clamp(-1.0, 1.0)
        : 1.0;
    final minGap = [proteinGapRatio, fatGapRatio, carbGapRatio]
        .reduce((a, b) => a < b ? a : b);

    final proteinDensity = food.caloriesPer100g > 0
        ? food.proteinPer100g / (food.caloriesPer100g / 100)
        : 0.0;

    final hasProteinGap = rem.remainingProtein > 5;
    if (hasProteinGap) {
      if (minGap == proteinGapRatio) {
        score += proteinDensity * proteinWeight; // v3：用动态权重
      } else {
        score += proteinDensity * (proteinWeight * 0.4);
      }
      if (proteinDensity >= 10 && rem.remainingProtein > 0 && rem.proteinGoal > 0) {
        final canFill = (food.proteinPer100g / rem.proteinGoal * 100).round();
        reasons.add('补蛋白 ${canFill.clamp(1, 999)}%');
      } else if (proteinDensity >= 10) {
        reasons.add('高蛋白');
      }
    }

    // 碳水缺口最大 → 适度碳水食物优先（避免低血糖，尤其运动日）
    if (minGap == carbGapRatio && carbGapRatio < 0.2 && food.carbsPer100g > 15) {
      score += 3;
      reasons.add('补碳水');
    }

    // 维度 1 续：热量匹配
    if (rem.isCalorieOver) {
      if (food.caloriesPer100g > 200) {
        score -= (food.caloriesPer100g - 200) * 0.05;
      } else if (food.caloriesPer100g < 100) {
        score += 5;
        reasons.add('低热量');
      }
    } else {
      if (food.caloriesPer100g <= rem.remainingCalories.abs() + 100) {
        score += 2;
      }
    }

    // 维度 2 续：基础食材白名单底分（保证常见食物不沉底）
    if (isBasic) {
      score += 3;
    }
    // 频次加权：log2 压缩封顶 4（常吃加分，但不让常吃的永远霸榜）
    if (count > 0) {
      score += (log(count + 1) / log(2)).clamp(0.0, 4.0);
      if (count >= 3) reasons.add('常吃');
    }

    // 维度 1 续：脂肪超标惩罚
    if (rem.remainingFat < -5 && food.fatPer100g > 15) {
      score -= (food.fatPer100g - 15) * 0.3;
    }

    // 维度 3：profile 健康状况软降权（硬过滤已在 _shouldExcludeByProfile 处理）
    if (profile != null) {
      final hc = profile.healthCondition ?? 'none';
      // 糖尿病：高糖食物降权（不直接排除，太激进致列表空）
      if (hc == 'diabetes' && _isHighSugar(food)) {
        score *= 0.3;
        reasons.add('高糖谨慎');
      }
      // 肾病：极高蛋白食物降权（cap 总量在 calculator，单食物只降权）
      if (hc == 'kidney_issues' && food.proteinPer100g > 25) {
        score *= 0.5;
      }
    }

    // 维度 4：时段感知（数据驱动，非硬编码"早餐食物"）
    if (mealType.isNotEmpty) {
      final dist = mealTypeDist[food.id];
      if (dist != null) {
        final ratio = dist[mealType] ?? 0;
        if (ratio > 0.5) {
          score += 3;
          if (mealType == 'breakfast') {
            reasons.add('常作早餐');
          } else if (mealType == 'lunch') {
            reasons.add('常作午餐');
          } else if (mealType == 'dinner') {
            reasons.add('常作晚餐');
          }
        } else if (ratio > 0.3) {
          score += 1.5;
        }
      }
    }

    // 维度 5：多样性（昨日已吃降权，避免每天推同样）
    if (yesterdayEaten.contains(food.id)) {
      score -= 2;
    }

    // 基础分（保证有分，让排序有意义）
    score += 1;

    final reason = reasons.isEmpty ? '营养均衡' : reasons.join('·');
    return (score, reason);
  }

  /// profile 约束硬过滤：素食/纯素/乳糖不耐/无麸质直接排除违规食物。
  /// 糖尿病/肾病用软降权（在 _scoreFood 处理），避免列表空。
  /// 返回 true 表示应排除。
  bool _shouldExcludeByProfile(FoodItem food, Profile profile) {
    final dp = profile.dietPreference ?? 'none';
    final name = food.name;

    // 蛋奶素：排除肉/鱼/海鲜（保留蛋奶）
    if (dp == 'vegetarian') {
      if (_isMeatOrFish(name)) return true;
    }
    // 纯素：排除肉/鱼/海鲜 + 蛋奶
    if (dp == 'vegan') {
      if (_isMeatOrFish(name)) return true;
      if (_isEggOrDairy(name)) return true;
    }
    // 乳糖不耐：排除乳制品（保留无乳糖/植物奶）
    if (dp == 'lactose_intolerant') {
      if (_isDairy(name) &&
          !name.contains('无乳糖') &&
          !name.contains('植物奶') &&
          !name.contains('燕麦奶') &&
          !name.contains('豆奶')) {
        return true;
      }
    }
    // 无麸质：排除含麸质面食
    if (dp == 'gluten_free') {
      if (_isGluten(name)) return true;
    }
    return false;
  }

  bool _isBasicFood(String name) {
    for (final k in _basicFoodKeywords) {
      if (name.contains(k)) return true;
    }
    return false;
  }

  bool _isMeatOrFish(String name) {
    for (final k in _meatFishKeywords) {
      if (name.contains(k)) return true;
    }
    return false;
  }

  bool _isEggOrDairy(String name) {
    for (final k in _eggDairyKeywords) {
      if (name.contains(k)) return true;
    }
    return false;
  }

  bool _isDairy(String name) {
    for (final k in _dairyKeywords) {
      if (name.contains(k)) return true;
    }
    return false;
  }

  bool _isGluten(String name) {
    for (final k in _glutenKeywords) {
      if (name.contains(k)) return true;
    }
    return false;
  }

  /// 糖尿病降权判断：高糖关键词 + 高碳水密度
  bool _isHighSugar(FoodItem food) {
    final hasKeyword = _highSugarKeywords.any((k) => food.name.contains(k));
    return hasKeyword && food.carbsPer100g > 40;
  }
}
