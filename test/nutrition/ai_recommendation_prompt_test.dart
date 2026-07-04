// test/nutrition/ai_recommendation_prompt_test.dart
//
// AI 推荐 prompt 构建器单元测试
//
// 覆盖：
// - systemPrompt 非空 + 含 JSON 格式约束
// - buildUserPrompt 含画像/剩余/历史/反馈各段
// - 画像段：性别/年龄/身高/体重/体脂/活动量/目标/特殊人群/健康状况/饮食偏好
// - 剩余段：当前餐次/已摄入/剩余/三宏
// - 历史段：按频次降序取 top 20
// - 反馈段：喜欢/一般/不喜欢标签 + 近 30 条
// - 边界：空历史/空反馈/空近3天食物
// - 标签映射：goal/activity/special/health/diet/mealType

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/nutrition/ai_recommendation_prompt.dart';
import 'package:eatwise/nutrition/recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;
  late MealLogRepository mealRepo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory(), seedOnCreate: false);
    foodRepo = FoodItemRepository(db);
    mealRepo = MealLogRepository(db);
    // 预置食物
    await _seedFood(db, name: '鸡胸肉', cal: 165, protein: 31, fat: 3.6, carbs: 0);
    await _seedFood(db, name: '鸡蛋', cal: 144, protein: 13, fat: 9, carbs: 1.1);
  });

  tearDown(() async => db.close());

  group('systemPrompt', () {
    test('非空 + 含 JSON 格式约束', () {
      expect(AiRecommendationPrompt.systemPrompt, isNotEmpty);
      expect(AiRecommendationPrompt.systemPrompt, contains('recommendations'));
      expect(AiRecommendationPrompt.systemPrompt, contains('estimatedCalories'));
      expect(AiRecommendationPrompt.systemPrompt, contains('JSON'));
      // 营养师人设
      expect(AiRecommendationPrompt.systemPrompt, contains('营养师'));
    });

    test('含 5 项推荐要求约束', () {
      final s = AiRecommendationPrompt.systemPrompt;
      expect(s, contains('健康状况'));
      expect(s, contains('饮食偏好'));
      expect(s, contains('营养缺口'));
      expect(s, contains('满意度反馈'));
      expect(s, contains('30 字'));
    });
  });

  group('buildUserPrompt 基本结构', () {
    test('含所有 6 个段落标题', () async {
      final profile = await _getProfile(db);
      final remaining = _fakeRemaining();
      final ctx = AiRecommendationContext(
        profile: profile,
        remaining: remaining,
        mealType: 'lunch',
        recentMeals: [],
        foodMap: {},
        recentFoodNames: {},
        feedbacks: [],
      );
      final prompt = AiRecommendationPrompt.buildUserPrompt(ctx);
      expect(prompt, contains('## 用户画像'));
      expect(prompt, contains('## 当日营养额度'));
      expect(prompt, contains('## 近 14 天饮食习惯'));
      expect(prompt, contains('## 近 3 天已吃食物'));
      expect(prompt, contains('## 历史推荐反馈'));
      expect(prompt, contains('## 任务'));
    });

    test('任务段含餐次标签', () async {
      final profile = await _getProfile(db);
      final ctx = AiRecommendationContext(
        profile: profile,
        remaining: _fakeRemaining(),
        mealType: 'breakfast',
        recentMeals: [],
        foodMap: {},
        recentFoodNames: {},
        feedbacks: [],
      );
      final prompt = AiRecommendationPrompt.buildUserPrompt(ctx);
      expect(prompt, contains('早餐'));
    });
  });

  group('画像段', () {
    test('含基础字段（性别/年龄/身高/体重）', () async {
      final profile = await _getProfile(db);
      final ctx = AiRecommendationContext(
        profile: profile,
        remaining: _fakeRemaining(),
        mealType: 'lunch',
        recentMeals: [],
        foodMap: {},
        recentFoodNames: {},
        feedbacks: [],
      );
      final prompt = AiRecommendationPrompt.buildUserPrompt(ctx);
      expect(prompt, contains('男'));
      expect(prompt, contains('30 岁'));
      expect(prompt, contains('170 cm'));
      expect(prompt, contains('70 kg'));
    });

    test('体脂率存在时显示', () async {
      final profile = await _getProfile(db);
      final ctx = AiRecommendationContext(
        profile: profile.copyWith(bodyFatPct: const Value(18.5)),
        remaining: _fakeRemaining(),
        mealType: 'lunch',
        recentMeals: [],
        foodMap: {},
        recentFoodNames: {},
        feedbacks: [],
      );
      final prompt = AiRecommendationPrompt.buildUserPrompt(ctx);
      expect(prompt, contains('体脂率：18.5%'));
    });

    test('活动量/目标标签映射', () async {
      final profile = await _getProfile(db);
      final ctx = AiRecommendationContext(
        profile: profile.copyWith(activityLevel: 1.55, goal: 'cut'),
        remaining: _fakeRemaining(),
        mealType: 'lunch',
        recentMeals: [],
        foodMap: {},
        recentFoodNames: {},
        feedbacks: [],
      );
      final prompt = AiRecommendationPrompt.buildUserPrompt(ctx);
      expect(prompt, contains('中度活动'));
      expect(prompt, contains('减脂'));
    });

    test('特殊人群/健康状况/饮食偏好（none 时不显示）', () async {
      final profile = await _getProfile(db); // 默认 specialCondition/health/diet = null
      final ctx = AiRecommendationContext(
        profile: profile,
        remaining: _fakeRemaining(),
        mealType: 'lunch',
        recentMeals: [],
        foodMap: {},
        recentFoodNames: {},
        feedbacks: [],
      );
      final prompt = AiRecommendationPrompt.buildUserPrompt(ctx);
      // null 视为 none，不显示
      expect(prompt, isNot(contains('孕期')));
      expect(prompt, isNot(contains('糖尿病')));
      expect(prompt, isNot(contains('蛋奶素')));
    });

    test('特殊人群/健康状况/饮食偏好（有值时显示）', () async {
      final profile = await _getProfile(db);
      final ctx = AiRecommendationContext(
        profile: profile.copyWith(
          specialCondition: const Value('pregnancy'),
          healthCondition: const Value('diabetes'),
          dietPreference: const Value('vegetarian'),
        ),
        remaining: _fakeRemaining(),
        mealType: 'lunch',
        recentMeals: [],
        foodMap: {},
        recentFoodNames: {},
        feedbacks: [],
      );
      final prompt = AiRecommendationPrompt.buildUserPrompt(ctx);
      expect(prompt, contains('孕期'));
      expect(prompt, contains('糖尿病'));
      expect(prompt, contains('蛋奶素'));
    });
  });

  group('剩余段', () {
    test('含当前餐次/已摄入/剩余/三宏', () async {
      final profile = await _getProfile(db);
      final ctx = AiRecommendationContext(
        profile: profile,
        remaining: DailyRemaining(
          remainingCalories: 500,
          remainingProtein: 30,
          remainingFat: 15,
          remainingCarbs: 60,
          targetCalories: 2000,
          proteinGoal: 98,
          fatGoal: 63,
          carbGoal: 250,
          consumedCalories: 1500,
          consumedProtein: 68,
          consumedFat: 48,
          consumedCarbs: 190,
        ),
        mealType: 'dinner',
        recentMeals: [],
        foodMap: {},
        recentFoodNames: {},
        feedbacks: [],
      );
      final prompt = AiRecommendationPrompt.buildUserPrompt(ctx);
      expect(prompt, contains('晚餐'));
      expect(prompt, contains('1500/2000'));
      expect(prompt, contains('剩余 500'));
      expect(prompt, contains('蛋白质 68/98'));
      expect(prompt, contains('脂肪剩余 15'));
      expect(prompt, contains('碳水剩余 60'));
    });
  });

  group('历史段', () {
    test('空历史 → 显示无记录', () async {
      final profile = await _getProfile(db);
      final ctx = AiRecommendationContext(
        profile: profile,
        remaining: _fakeRemaining(),
        mealType: 'lunch',
        recentMeals: [],
        foodMap: {},
        recentFoodNames: {},
        feedbacks: [],
      );
      final prompt = AiRecommendationPrompt.buildUserPrompt(ctx);
      expect(prompt, contains('（无历史记录）'));
    });

    test('按频次降序取 top 20', () async {
      final foods = await foodRepo.listAllForRecommendation();
      final chicken = foods.firstWhere((f) => f.name == '鸡胸肉');
      final egg = foods.firstWhere((f) => f.name == '鸡蛋');
      final foodMap = <int, FoodItem>{for (final f in foods) f.id: f};
      // 鸡胸肉 3 次，鸡蛋 1 次
      final meals = <MealLog>[];
      for (var i = 0; i < 3; i++) {
        await mealRepo.insertMealLog(
          date: '2026-06-2$i', mealType: 'lunch', foodItemId: chicken.id,
          actualServingG: 100, actualCalories: 165, actualProteinG: 31,
          actualFatG: 3.6, actualCarbsG: 0,
        );
      }
      await mealRepo.insertMealLog(
        date: '2026-06-25', mealType: 'breakfast', foodItemId: egg.id,
        actualServingG: 60, actualCalories: 86, actualProteinG: 7.8,
        actualFatG: 5.4, actualCarbsG: 0.7,
      );
      meals.addAll(await mealRepo.getRange('2026-06-01', '2026-06-30'));
      final profile = await _getProfile(db);
      final ctx = AiRecommendationContext(
        profile: profile,
        remaining: _fakeRemaining(),
        mealType: 'lunch',
        recentMeals: meals,
        foodMap: foodMap,
        recentFoodNames: {},
        feedbacks: [],
      );
      final prompt = AiRecommendationPrompt.buildUserPrompt(ctx);
      expect(prompt, contains('鸡胸肉(3次)'));
      expect(prompt, contains('鸡蛋(1次)'));
      // 鸡胸肉频次高应排在鸡蛋前面
      expect(prompt.indexOf('鸡胸肉(3次)'), lessThan(prompt.indexOf('鸡蛋(1次)')));
    });
  });

  group('近 3 天已吃食物段', () {
    test('空集合 → 显示无记录', () async {
      final profile = await _getProfile(db);
      final ctx = AiRecommendationContext(
        profile: profile,
        remaining: _fakeRemaining(),
        mealType: 'lunch',
        recentMeals: [],
        foodMap: {},
        recentFoodNames: {},
        feedbacks: [],
      );
      final prompt = AiRecommendationPrompt.buildUserPrompt(ctx);
      expect(prompt, contains('（无记录）'));
    });

    test('非空 → 显示食物名（顿号分隔）', () async {
      final profile = await _getProfile(db);
      final ctx = AiRecommendationContext(
        profile: profile,
        remaining: _fakeRemaining(),
        mealType: 'lunch',
        recentMeals: [],
        foodMap: {},
        recentFoodNames: {'鸡胸肉', '米饭', '白菜'},
        feedbacks: [],
      );
      final prompt = AiRecommendationPrompt.buildUserPrompt(ctx);
      expect(prompt, contains('鸡胸肉'));
      expect(prompt, contains('米饭'));
      expect(prompt, contains('白菜'));
    });
  });

  group('反馈段', () {
    test('空反馈 → 显示暂无反馈', () async {
      final profile = await _getProfile(db);
      final ctx = AiRecommendationContext(
        profile: profile,
        remaining: _fakeRemaining(),
        mealType: 'lunch',
        recentMeals: [],
        foodMap: {},
        recentFoodNames: {},
        feedbacks: [],
      );
      final prompt = AiRecommendationPrompt.buildUserPrompt(ctx);
      expect(prompt, contains('（暂无反馈）'));
    });

    test('含喜欢/一般/不喜欢标签', () async {
      final profile = await _getProfile(db);
      final now = DateTime.now();
      final ctx = AiRecommendationContext(
        profile: profile,
        remaining: _fakeRemaining(),
        mealType: 'lunch',
        recentMeals: [],
        foodMap: {},
        recentFoodNames: {},
        feedbacks: [
          FeedbackRecord(foodName: '麻婆豆腐', rating: 3, createdAt: now),
          FeedbackRecord(foodName: '白粥', rating: 2, createdAt: now),
          FeedbackRecord(foodName: '生鱼片', rating: 1, createdAt: now),
        ],
      );
      final prompt = AiRecommendationPrompt.buildUserPrompt(ctx);
      expect(prompt, contains('麻婆豆腐：喜欢'));
      expect(prompt, contains('白粥：一般'));
      expect(prompt, contains('生鱼片：不喜欢'));
    });
  });
}

/// 辅助：seed 一条食物
Future<void> _seedFood(EatWiseDatabase db,
    {required String name,
    required double cal,
    required double protein,
    required double fat,
    required double carbs}) async {
  await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
        name: name,
        defaultServingG: 100,
        caloriesPer100g: cal,
        proteinPer100g: protein,
        fatPer100g: fat,
        carbsPer100g: carbs,
        source: 'manual',
        sourceVersion: 'test',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
}

/// 辅助：读默认 profile（id=1）
Future<Profile> _getProfile(EatWiseDatabase db) async {
  return ProfileRepository(db).get();
}

/// 辅助：构造一个假的 DailyRemaining
DailyRemaining _fakeRemaining() {
  return DailyRemaining(
    remainingCalories: 1000,
    remainingProtein: 50,
    remainingFat: 25,
    remainingCarbs: 120,
    targetCalories: 2000,
    proteinGoal: 98,
    fatGoal: 63,
    carbGoal: 250,
    consumedCalories: 1000,
    consumedProtein: 48,
    consumedFat: 38,
    consumedCarbs: 130,
  );
}
