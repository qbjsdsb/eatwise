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
  Future<List<RecommendedFood>> recommend({
    required DailyRemaining remaining,
    int limit = 5,
  }) async {
    final foods = await _foodRepo.listAllForRecommendation();
    if (foods.isEmpty) return [];

    final recommendations = <RecommendedFood>[];
    for (final food in foods) {
      final (score, reason) = _scoreFood(food, remaining);
      if (score > 0) {
        recommendations.add(RecommendedFood(food: food, score: score, reason: reason));
      }
    }
    recommendations.sort((a, b) => b.score.compareTo(a.score));
    return recommendations.take(limit).toList();
  }

  /// 单个食物评分
  /// 返回 (score, reason)。score <= 0 表示不推荐（被过滤）。
  (double, String) _scoreFood(FoodItem food, DailyRemaining rem) {
    double score = 0;
    final reasons = <String>[];

    // 蛋白质缺口评分（核心信号）
    if (rem.hasProteinGap) {
      // 蛋白质密度：蛋白质 g per 100 kcal（0 卡食物密度视为 0，避免单位不一致偏置）
      final proteinDensity = food.caloriesPer100g > 0
          ? food.proteinPer100g / (food.caloriesPer100g / 100)
          : 0.0;
      // 蛋白质密度 > 10（如鸡胸肉 24g/165kcal=14.5）优先
      score += proteinDensity * 3;
      if (proteinDensity >= 10) {
        reasons.add('高蛋白');
      }
    }

    // 热量匹配评分
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

    // 脂肪缺口/超标
    if (rem.remainingFat < -5) {
      // 脂肪超标：惩罚高脂食物
      if (food.fatPer100g > 15) {
        score -= (food.fatPer100g - 15) * 0.3;
      }
    }

    // 基础分（保证有分，让排序有意义）
    score += 1;

    // 过滤异常食物（calories=0 的可能是数据缺失）
    if (food.caloriesPer100g <= 0 && food.proteinPer100g <= 0) {
      return (0, '');
    }

    final reason = reasons.isEmpty ? '营养均衡' : reasons.join('·');
    return (score, reason);
  }
}
