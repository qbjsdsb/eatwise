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
/// 基于当日剩余额度，从食物库筛选最"填补缺口"的食物。
/// 评分逻辑：
/// - 蛋白质缺口大时，优先高蛋白食物（蛋白质密度加权）
/// - 热量已超标时，惩罚高热量食物
/// - 脂肪超标时，惩罚高脂食物
class RecommendationService {
  final FoodItemRepository _foodRepo;
  final MealLogRepository _mealRepo;
  final ProfileRepository _profileRepo;

  RecommendationService(this._foodRepo, this._mealRepo, this._profileRepo);

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

  /// 推荐食物（按填补缺口评分排序，取 top limit）
  ///
  /// 升级版（v2）在原"缺口评分"基础上加入：
  /// - 历史食用频次加权：常吃的食物加分（更贴合用户饮食习惯）
  /// - 排除今日已吃食物：避免重复推荐刚吃过的
  /// - 相对缺口评分：不只看蛋白缺口绝对值，看三大宏量哪个缺得最狠（相对目标）
  /// - 具体推荐理由：从"高蛋白"升级为"补 18g 蛋白"等可量化描述
  Future<List<RecommendedFood>> recommend({
    required DailyRemaining remaining,
    int limit = 5,
    String todayDate = '',
  }) async {
    final foods = await _foodRepo.listAllForRecommendation();
    if (foods.isEmpty) return [];

    // 并行获取：今日已吃 foodItemId 集合 + 历史 30 天食用频次
    final todayEatenFuture = todayDate.isEmpty
        ? Future.value(<int>{})
        : _mealRepo.getMealsByDate(todayDate).then(
            (meals) => meals.map((m) => m.foodItemId).toSet());
    final freqFuture = _mealRepo.getRecentFoodCounts(days: 30);
    final todayEaten = await todayEatenFuture;
    final freq = await freqFuture;

    final recommendations = <RecommendedFood>[];
    for (final food in foods) {
      // 排除今日已吃（避免重复推荐刚吃过的）
      if (todayEaten.contains(food.id)) continue;
      final (score, reason) = _scoreFood(food, remaining, freq);
      if (score > 0) {
        recommendations
            .add(RecommendedFood(food: food, score: score, reason: reason));
      }
    }
    recommendations.sort((a, b) => b.score.compareTo(a.score));
    return recommendations.take(limit).toList();
  }

  /// 单个食物评分（v2）
  /// 返回 (score, reason)。score <= 0 表示不推荐（被过滤）。
  ///
  /// 评分维度：
  /// 1. 相对缺口匹配（核心）：计算三大宏量相对目标的缺口比例，哪个缺得最狠，
  ///    食物在该宏量上的密度就加权。比原"只看蛋白绝对缺口"更平衡。
  /// 2. 热量匹配：未超标时偏好接近剩余额度的；超标时惩罚高热量。
  /// 3. 历史频次：常吃加分（饮食习惯贴合），但封顶避免常吃的永远霸榜。
  /// 4. 脂肪超标惩罚。
  (double, String) _scoreFood(
      FoodItem food, DailyRemaining rem, Map<int, int> freq) {
    double score = 0;
    final reasons = <String>[];

    // 过滤异常食物（calories=0 的可能是数据缺失）
    if (food.caloriesPer100g <= 0 && food.proteinPer100g <= 0) {
      return (0, '');
    }

    // 1. 相对缺口匹配：三大宏量缺口比例（remaining / goal），越小越缺
    //    防除零：goal <= 0 时该宏量不参与
    final proteinGapRatio = rem.proteinGoal > 0
        ? (rem.remainingProtein / rem.proteinGoal).clamp(-1.0, 1.0)
        : 1.0;
    final fatGapRatio = rem.fatGoal > 0
        ? (rem.remainingFat / rem.fatGoal).clamp(-1.0, 1.0)
        : 1.0;
    final carbGapRatio = rem.carbGoal > 0
        ? (rem.remainingCarbs / rem.carbGoal).clamp(-1.0, 1.0)
        : 1.0;
    // 缺口比例越小（越负=越超标，越接近 1=越缺），取最小者为"最缺宏量"
    final minGap = [proteinGapRatio, fatGapRatio, carbGapRatio]
        .reduce((a, b) => a < b ? a : b);

    // 蛋白质密度：g per 100 kcal
    final proteinDensity = food.caloriesPer100g > 0
        ? food.proteinPer100g / (food.caloriesPer100g / 100)
        : 0.0;

    // 蛋白缺口评分：与原 hasProteinGap（remainingProtein > 5）语义一致，
    // remainingProtein > 0 即有缺口（ratio < 1.0）。缺口越大权重越高。
    // 原阈值 < 0.3 太严，无记录时 ratio=1.0 不触发，导致高蛋白食物不被推荐。
    final hasProteinGap = rem.remainingProtein > 5;
    if (hasProteinGap) {
      if (minGap == proteinGapRatio) {
        // 蛋白是最缺的宏量：强加权
        score += proteinDensity * 4;
      } else {
        // 蛋白也缺但不是最缺：弱加权
        score += proteinDensity * 1.5;
      }
      if (proteinDensity >= 10 && rem.remainingProtein > 0 && rem.proteinGoal > 0) {
        // 估算 100g 能补多少蛋白（用剩余缺口的占比表达，更直观）
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

    // 2. 热量匹配
    if (rem.isCalorieOver) {
      // 已超标：惩罚高热量食物（>200kcal/100g 扣分）
      if (food.caloriesPer100g > 200) {
        score -= (food.caloriesPer100g - 200) * 0.05;
      } else if (food.caloriesPer100g < 100) {
        score += 5; // 低热量食物加分
        reasons.add('低热量');
      }
    } else {
      // 未超标：热量匹配剩余额度加分（接近剩余热量的食物优先）
      if (food.caloriesPer100g <= rem.remainingCalories.abs() + 100) {
        score += 2;
      }
    }

    // 3. 历史频次加权：常吃加分（贴合饮食习惯），但 log 压缩 + 封顶，
    //    避免"常吃的永远霸榜，新食物永无出头"
    final count = freq[food.id] ?? 0;
    if (count > 0) {
      // log2(count+1)：1次=1分，2次=1.58，4次=2.32，8次=3.17，封顶约 4 分
      score += (log(count + 1) / log(2)).clamp(0.0, 4.0);
      if (count >= 3) reasons.add('常吃');
    }

    // 4. 脂肪超标惩罚
    if (rem.remainingFat < -5 && food.fatPer100g > 15) {
      score -= (food.fatPer100g - 15) * 0.3;
    }

    // 基础分（保证有分，让排序有意义）
    score += 1;

    final reason = reasons.isEmpty ? '营养均衡' : reasons.join('·');
    return (score, reason);
  }
}
