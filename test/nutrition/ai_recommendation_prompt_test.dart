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
      expect(prompt, contains('## 近 7 天已吃食物'));
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

  group('近 7 天已吃食物段', () {
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

  group('M19 去重强化 + 多样性约束', () {
    test('system prompt 含"禁止"和"7 天"（去重强化）', () {
      final s = AiRecommendationPrompt.systemPrompt;
      expect(s, contains('禁止'),
          reason: 'M19 应把"避免"强化为"禁止"');
      expect(s, contains('7 天'),
          reason: 'M19 时间窗口应从 3 天扩到 7 天');
    });

    test('system prompt 不含旧文案"避免与近 3 天"（旧文案应被替换）', () {
      final s = AiRecommendationPrompt.systemPrompt;
      expect(s, isNot(contains('避免与近 3 天')),
          reason: '旧文案"避免与近 3 天"应被替换');
    });

    test('system prompt 含品类多样性约束（5 道菜覆盖 3 个食材类别）', () {
      final s = AiRecommendationPrompt.systemPrompt;
      expect(s, contains('5 道菜至少覆盖 3 个食材类别'),
          reason: 'M19 应加品类多样性约束');
      expect(s, contains('肉类/水产/蔬菜/豆制品/蛋类/主食/水果'),
          reason: '应列出 7 个食材类别');
    });

    test('system prompt 含烹饪方式多样性约束', () {
      final s = AiRecommendationPrompt.systemPrompt;
      expect(s, contains('烹饪方式尽量多样化'),
          reason: 'M19 应加烹饪方式多样性约束');
    });

    test('去重段标题为"近 7 天已吃食物（禁止重复推荐）"', () async {
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
      expect(prompt, contains('## 近 7 天已吃食物（禁止重复推荐）'),
          reason: 'M19 去重段标题应从"近 3 天已吃食物（避免重复推荐）"改为"近 7 天已吃食物（禁止重复推荐）"');
    });

    test('历史段含"去重约束优先于频次偏好"优先级声明', () async {
      // 预置历史记录（让 _historySection 走非空分支）
      final foods = await foodRepo.listAllForRecommendation();
      final chicken = foods.firstWhere((f) => f.name == '鸡胸肉');
      final foodMap = <int, FoodItem>{for (final f in foods) f.id: f};
      await mealRepo.insertMealLog(
        date: '2026-06-25', mealType: 'lunch', foodItemId: chicken.id,
        actualServingG: 100, actualCalories: 165, actualProteinG: 31,
        actualFatG: 3.6, actualCarbsG: 0,
      );
      final meals = await mealRepo.getRange('2026-06-01', '2026-06-30');
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
      expect(prompt, contains('去重约束优先于频次偏好'),
          reason: 'M19 历史段应加优先级声明，避免 AI 误把高频食物理解为应该推荐');
    });

    test('历史段含"用户近期少吃的食材类别"反向偏好', () async {
      final foods = await foodRepo.listAllForRecommendation();
      final chicken = foods.firstWhere((f) => f.name == '鸡胸肉');
      final foodMap = <int, FoodItem>{for (final f in foods) f.id: f};
      await mealRepo.insertMealLog(
        date: '2026-06-25', mealType: 'lunch', foodItemId: chicken.id,
        actualServingG: 100, actualCalories: 165, actualProteinG: 31,
        actualFatG: 3.6, actualCarbsG: 0,
      );
      final meals = await mealRepo.getRange('2026-06-01', '2026-06-30');
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
      expect(prompt, contains('用户近期少吃的食材类别'),
          reason: 'M19 历史段应加反向偏好提示');
    });

    test('_inferRareCategories：常吃食物只有鸡肉 → 返回水产/蔬菜/豆制品等', () async {
      // 只 seed 鸡胸肉（肉类），其他类别应被识别为"少吃"
      final foods = await foodRepo.listAllForRecommendation();
      final chicken = foods.firstWhere((f) => f.name == '鸡胸肉');
      final foodMap = <int, FoodItem>{for (final f in foods) f.id: f};
      await mealRepo.insertMealLog(
        date: '2026-06-25', mealType: 'lunch', foodItemId: chicken.id,
        actualServingG: 100, actualCalories: 165, actualProteinG: 31,
        actualFatG: 3.6, actualCarbsG: 0,
      );
      final meals = await mealRepo.getRange('2026-06-01', '2026-06-30');
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
      // 只吃鸡肉时，水产/蔬菜/豆制品应被识别为"少吃"
      expect(prompt, contains('水产'),
          reason: '只吃鸡肉时水产应被识别为少吃类别');
      expect(prompt, contains('蔬菜'),
          reason: '只吃鸡肉时蔬菜应被识别为少吃类别');
      expect(prompt, contains('豆制品'),
          reason: '只吃鸡肉时豆制品应被识别为少吃类别');
    });

    test('_inferRareCategories：常吃食物覆盖全部类别 → 无明显缺口', () async {
      // seed 覆盖 7 个类别的食物
      await _seedFood(db, name: '鲈鱼', cal: 100, protein: 18, fat: 3, carbs: 0); // 水产
      await _seedFood(db, name: '白菜', cal: 20, protein: 1.5, fat: 0.1, carbs: 3.5); // 蔬菜
      await _seedFood(db, name: '豆腐', cal: 80, protein: 8, fat: 4, carbs: 2); // 豆制品
      await _seedFood(db, name: '米饭', cal: 130, protein: 2.7, fat: 0.3, carbs: 28); // 主食
      await _seedFood(db, name: '苹果', cal: 52, protein: 0.3, fat: 0.2, carbs: 14); // 水果
      // 鸡胸肉（肉类）+ 鸡蛋（蛋类）已在 setUp 中 seed
      final foods = await foodRepo.listAllForRecommendation();
      final foodMap = <int, FoodItem>{for (final f in foods) f.id: f};
      final chicken = foods.firstWhere((f) => f.name == '鸡胸肉');
      final egg = foods.firstWhere((f) => f.name == '鸡蛋');
      final fish = foods.firstWhere((f) => f.name == '鲈鱼');
      final cabbage = foods.firstWhere((f) => f.name == '白菜');
      final tofu = foods.firstWhere((f) => f.name == '豆腐');
      final rice = foods.firstWhere((f) => f.name == '米饭');
      final apple = foods.firstWhere((f) => f.name == '苹果');
      // 给每个食物插入一条 meal_log
      for (final f in [chicken, egg, fish, cabbage, tofu, rice, apple]) {
        await mealRepo.insertMealLog(
          date: '2026-06-25', mealType: 'lunch', foodItemId: f.id,
          actualServingG: 100, actualCalories: 100, actualProteinG: 10,
          actualFatG: 5, actualCarbsG: 5,
        );
      }
      final meals = await mealRepo.getRange('2026-06-01', '2026-06-30');
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
      expect(prompt, contains('无明显缺口'),
          reason: '常吃食物覆盖全部 7 个类别时，应返回"无明显缺口"');
    });

    test('_inferRareCategories：常吃食物无类别匹配 → 返回前 3 个类别', () async {
      // seed 一个不匹配任何类别关键词的食物名
      await _seedFood(db, name: '神秘料理', cal: 100, protein: 5, fat: 5, carbs: 5);
      final foods = await foodRepo.listAllForRecommendation();
      final mystery = foods.firstWhere((f) => f.name == '神秘料理');
      final foodMap = <int, FoodItem>{for (final f in foods) f.id: f};
      await mealRepo.insertMealLog(
        date: '2026-06-25', mealType: 'lunch', foodItemId: mystery.id,
        actualServingG: 100, actualCalories: 100, actualProteinG: 5,
        actualFatG: 5, actualCarbsG: 5,
      );
      final meals = await mealRepo.getRange('2026-06-01', '2026-06-30');
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
      // 无类别匹配时，前 3 个类别（肉类/水产/蔬菜）应被识别为少吃
      expect(prompt, contains('肉类'),
          reason: '无类别匹配时肉类应被识别为少吃类别（取前 3 个）');
      expect(prompt, contains('水产'),
          reason: '无类别匹配时水产应被识别为少吃类别（取前 3 个）');
      expect(prompt, contains('蔬菜'),
          reason: '无类别匹配时蔬菜应被识别为少吃类别（取前 3 个）');
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
