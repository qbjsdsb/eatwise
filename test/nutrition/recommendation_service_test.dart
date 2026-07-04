import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/nutrition/recommendation_service.dart';
import 'package:eatwise/nutrition/user_preference_learner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;
  late MealLogRepository mealRepo;
  late ProfileRepository profileRepo;
  late RecommendationService service;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory(), seedOnCreate: false);
    foodRepo = FoodItemRepository(db);
    mealRepo = MealLogRepository(db);
    profileRepo = ProfileRepository(db);
    service = RecommendationService(foodRepo, mealRepo, profileRepo);

    // 预置 profile（默认 wasCreated 已插 id=1，目标 2000kcal，蛋白 98g）
    // 预置食物库：高蛋白/低蛋白/高热量/低热量各一条
    await _seedFood(db, name: '鸡胸肉', cal: 165, protein: 31, fat: 3.6, carbs: 0);
    await _seedFood(db, name: '鸡蛋', cal: 144, protein: 13, fat: 9, carbs: 1.1);
    await _seedFood(db, name: '可乐', cal: 42, protein: 0, fat: 0, carbs: 10.6);
    await _seedFood(db, name: '薯片', cal: 547, protein: 6, fat: 35, carbs: 53);
    await _seedFood(db, name: '白菜', cal: 17, protein: 1.5, fat: 0.1, carbs: 3.2);
    await _seedFood(db, name: '米饭', cal: 116, protein: 2.6, fat: 0.3, carbs: 25.9);
  });

  tearDown(() async => db.close());

  group('getDailyRemaining 当日剩余额度', () {
    test('无记录 → 剩余=目标', () async {
      final r = await service.getDailyRemaining('2026-07-02');
      expect(r.remainingCalories, 2000); // 目标 2000，已记录 0
      expect(r.remainingProtein, closeTo(98, 0.1)); // 1.4*70
      expect(r.consumedCalories, 0);
    });

    test('有记录 → 剩余=目标-已记录', () async {
      final foods = await db.foodItems.select().get();
      final chicken = foods.firstWhere((f) => f.name == '鸡胸肉');
      await mealRepo.insertMealLog(
        date: '2026-07-02',
        mealType: 'lunch',
        foodItemId: chicken.id,
        actualServingG: 100,
        actualCalories: 165,
        actualProteinG: 31,
        actualFatG: 3.6,
        actualCarbsG: 0,
      );
      final r = await service.getDailyRemaining('2026-07-02');
      expect(r.consumedCalories, 165);
      expect(r.remainingCalories, 2000 - 165);
      expect(r.consumedProtein, 31);
      expect(r.remainingProtein, closeTo(98 - 31, 0.1));
    });

    test('热量超标 → remainingCalories 为负', () async {
      final foods = await db.foodItems.select().get();
      final chips = foods.firstWhere((f) => f.name == '薯片');
      await mealRepo.insertMealLog(
        date: '2026-07-02',
        mealType: 'snack',
        foodItemId: chips.id,
        actualServingG: 500, // 500g 薯片 = 2735 kcal，超标
        actualCalories: 2735,
        actualProteinG: 30,
        actualFatG: 175,
        actualCarbsG: 265,
      );
      final r = await service.getDailyRemaining('2026-07-02');
      expect(r.isCalorieOver, true);
      expect(r.remainingCalories, lessThan(0));
    });

    test('蛋白质缺口判断', () async {
      // 无记录，剩余蛋白 98g > 5 → hasProteinGap=true
      final r = await service.getDailyRemaining('2026-07-02');
      expect(r.hasProteinGap, true);
    });
  });

  group('recommend 推荐算法', () {
    test('蛋白质缺口大 → 高蛋白食物排前', () async {
      final r = await service.getDailyRemaining('2026-07-02'); // 无记录，缺口大
      final recs = await service.recommend(remaining: r, limit: 5);

      expect(recs, isNotEmpty);
      // 鸡胸肉蛋白密度最高（31g/165kcal），应排第一
      expect(recs.first.food.name, '鸡胸肉');
    });

    test('热量已超标 → 低热量食物优先，高热量被惩罚', () async {
      // 构造热量超标场景
      final foods = await db.foodItems.select().get();
      final chips = foods.firstWhere((f) => f.name == '薯片');
      await mealRepo.insertMealLog(
        date: '2026-07-02',
        mealType: 'snack',
        foodItemId: chips.id,
        actualServingG: 500,
        actualCalories: 2735,
        actualProteinG: 30,
        actualFatG: 175,
        actualCarbsG: 265,
      );
      final r = await service.getDailyRemaining('2026-07-02');
      expect(r.isCalorieOver, true);

      final recs = await service.recommend(remaining: r, limit: 5);
      expect(recs, isNotEmpty);
      // 白菜（17kcal）应排在薯片（547kcal）前面
      final cabbageIdx = recs.indexWhere((e) => e.food.name == '白菜');
      final chipsIdx = recs.indexWhere((e) => e.food.name == '薯片');
      // 前置断言：白菜必须在推荐列表中（低热量超标时优先推荐）
      expect(cabbageIdx, greaterThanOrEqualTo(0), reason: '白菜应在推荐列表中');
      // 薯片在超标场景 score<=0 被过滤是设计行为（高热量惩罚生效）；
      // 若未被过滤则在列表中，白菜应排在前面
      if (chipsIdx >= 0) {
        expect(cabbageIdx, lessThan(chipsIdx));
      }
    });

    test('limit 截断', () async {
      final r = await service.getDailyRemaining('2026-07-02');
      final recs = await service.recommend(remaining: r, limit: 3);
      expect(recs.length, lessThanOrEqualTo(3));
    });

    test('空食物库 → 返回空列表', () async {
      // 删除所有食物
      await db.foodItems.delete().go();
      final r = await service.getDailyRemaining('2026-07-02');
      final recs = await service.recommend(remaining: r, limit: 5);
      expect(recs, isEmpty);
    });

    test('推荐理由非空', () async {
      final r = await service.getDailyRemaining('2026-07-02');
      final recs = await service.recommend(remaining: r, limit: 5);
      for (final rec in recs) {
        expect(rec.reason, isNotEmpty);
      }
    });

    test('异常食物（calories=0 且 protein=0）被过滤', () async {
      await _seedFood(db, name: '异常食物', cal: 0, protein: 0, fat: 0, carbs: 0);
      final r = await service.getDailyRemaining('2026-07-02');
      final recs = await service.recommend(remaining: r, limit: 10);
      expect(recs.any((e) => e.food.name == '异常食物'), isFalse);
    });
  });

  // v3 五维评分专项测试
  group('recommend v3 五维评分', () {
    test('冷门降权：常吃高蛋白 > 冷门高蛋白（同密度）', () async {
      // 两条等蛋白密度的食物，一条常吃（频次高），一条冷门（频次 0）
      await _seedFood(db, name: '常吃蛋白棒', cal: 100, protein: 20, fat: 2, carbs: 5);
      await _seedFood(db, name: '冷门蛋白粉', cal: 100, protein: 20, fat: 2, carbs: 5);
      final foods = await db.foodItems.select().get();
      final popular = foods.firstWhere((f) => f.name == '常吃蛋白棒');
      // 给常吃蛋白棒记 3 次历史（频次 > 0）
      for (var i = 0; i < 3; i++) {
        await mealRepo.insertMealLog(
          date: '2026-06-2$i', mealType: 'snack', foodItemId: popular.id,
          actualServingG: 50, actualCalories: 50, actualProteinG: 10,
          actualFatG: 1, actualCarbsG: 2.5,
        );
      }
      final r = await service.getDailyRemaining('2026-07-02');
      final recs = await service.recommend(remaining: r, limit: 10);
      final popularIdx = recs.indexWhere((e) => e.food.name == '常吃蛋白棒');
      final coldIdx = recs.indexWhere((e) => e.food.name == '冷门蛋白粉');
      // 两条都应在列表中，且常吃的排前
      expect(popularIdx, greaterThanOrEqualTo(0));
      expect(coldIdx, greaterThanOrEqualTo(0));
      expect(popularIdx, lessThan(coldIdx));
    });

    test('基础食材白名单：白名单食物有底分不沉底', () async {
      // 鸡蛋（白名单）vs 同营养的非白名单食物，鸡蛋应有底分优势
      await _seedFood(db, name: '鸡蛋', cal: 144, protein: 13, fat: 9, carbs: 1.1);
      await _seedFood(db, name: '某冷门蛋制品', cal: 144, protein: 13, fat: 9, carbs: 1.1);
      final r = await service.getDailyRemaining('2026-07-02');
      final recs = await service.recommend(remaining: r, limit: 10);
      final eggIdx = recs.indexWhere((e) => e.food.name == '鸡蛋');
      final coldIdx = recs.indexWhere((e) => e.food.name == '某冷门蛋制品');
      expect(eggIdx, greaterThanOrEqualTo(0));
      // 前置断言：冷门蛋制品也应在列表中（同营养 score>0，只是降权），
      // 避免 if 守卫静默跳过比较断言（假绿测试）
      expect(coldIdx, greaterThanOrEqualTo(0), reason: '冷门蛋制品应在推荐列表中');
      expect(eggIdx, lessThan(coldIdx));
    });

    test('profile 素食过滤：vegetarian 排除肉类', () async {
      await profileRepo.update(dietPreference: 'vegetarian');
      final profile = await profileRepo.get();
      final r = await service.getDailyRemaining('2026-07-02');
      final recs = await service.recommend(
        remaining: r, limit: 10, profile: profile);
      // 鸡胸肉含"鸡"应被排除（vegetarian 排除肉）
      expect(recs.any((e) => e.food.name == '鸡胸肉'), isFalse);
      // 白菜/米饭应保留
      expect(recs.any((e) => e.food.name == '白菜'), isTrue);
    });

    test('profile 乳糖不耐过滤：排除牛奶保留植物奶', () async {
      await _seedFood(db, name: '纯牛奶', cal: 54, protein: 3, fat: 3.2, carbs: 3.4);
      await _seedFood(db, name: '燕麦奶', cal: 40, protein: 1.5, fat: 1.5, carbs: 6);
      await profileRepo.update(dietPreference: 'lactose_intolerant');
      final profile = await profileRepo.get();
      final r = await service.getDailyRemaining('2026-07-02');
      final recs = await service.recommend(
        remaining: r, limit: 10, profile: profile);
      expect(recs.any((e) => e.food.name == '纯牛奶'), isFalse); // 排除
      expect(recs.any((e) => e.food.name == '燕麦奶'), isTrue); // 保留
    });

    test('时段感知：历史常作早餐的食物在早餐时段加分', () async {
      // 给鸡蛋记 3 次早餐 + 1 次晚餐 → 早餐占比 75%
      final foods = await db.foodItems.select().get();
      final egg = foods.firstWhere((f) => f.name == '鸡蛋');
      for (final mt in ['breakfast', 'breakfast', 'breakfast', 'dinner']) {
        await mealRepo.insertMealLog(
          date: '2026-06-2${mt == 'breakfast' ? '0' : '5'}',
          mealType: mt, foodItemId: egg.id,
          actualServingG: 60, actualCalories: 86, actualProteinG: 7.8,
          actualFatG: 5.4, actualCarbsG: 0.7,
        );
      }
      final r = await service.getDailyRemaining('2026-07-02');
      // 早餐时段推荐
      final breakfastRecs = await service.recommend(
        remaining: r, limit: 10, mealType: 'breakfast');
      // 晚餐时段推荐
      final dinnerRecs = await service.recommend(
        remaining: r, limit: 10, mealType: 'dinner');
      final breakfastEggIdx = breakfastRecs.indexWhere((e) => e.food.name == '鸡蛋');
      final dinnerEggIdx = dinnerRecs.indexWhere((e) => e.food.name == '鸡蛋');
      // 早餐时段鸡蛋应存在（加了时段分）
      expect(breakfastEggIdx, greaterThanOrEqualTo(0));
      // 前置断言：晚餐时段鸡蛋也应在列表中（基础食材 +3 底分，limit=10 足够），
      // 避免 if 守卫静默跳过得分比较断言（假绿测试）
      expect(dinnerEggIdx, greaterThanOrEqualTo(0), reason: '晚餐时段鸡蛋应在推荐列表中');
      // 早餐时段鸡蛋得分应高于晚餐时段（时段加分）
      expect(breakfastRecs[breakfastEggIdx].score,
          greaterThan(dinnerRecs[dinnerEggIdx].score));
    });

    test('多样性：昨日已吃食物降权', () async {
      final foods = await db.foodItems.select().get();
      final egg = foods.firstWhere((f) => f.name == '鸡蛋');
      // 鸡蛋昨日吃
      await mealRepo.insertMealLog(
        date: '2026-07-01', mealType: 'breakfast', foodItemId: egg.id,
        actualServingG: 60, actualCalories: 86, actualProteinG: 7.8,
        actualFatG: 5.4, actualCarbsG: 0.7,
      );
      final r = await service.getDailyRemaining('2026-07-02');
      final withoutYesterday = await service.recommend(remaining: r, limit: 10);
      final withYesterday = await service.recommend(
        remaining: r, limit: 10, yesterdayDate: '2026-07-01');
      final eggIdxA = withoutYesterday.indexWhere((e) => e.food.name == '鸡蛋');
      final eggIdxB = withYesterday.indexWhere((e) => e.food.name == '鸡蛋');
      // 前置断言：两次推荐鸡蛋都应在列表中（基础食材 +3 底分），
      // 避免 if 守卫静默跳过降权比较断言（假绿测试）
      expect(eggIdxA, greaterThanOrEqualTo(0), reason: '无昨日参数时鸡蛋应在列表');
      expect(eggIdxB, greaterThanOrEqualTo(0), reason: '有昨日参数时鸡蛋应在列表');
      // 昨日已吃时鸡蛋得分应更低（降权 -2）
      expect(withYesterday[eggIdxB].score,
          lessThan(withoutYesterday[eggIdxA].score));
    });
  });

  group('recommend v4 用户偏好学习', () {
    test('userPref=null → 不启用偏好加权（向后兼容）', () async {
      final r = await service.getDailyRemaining('2026-07-02');
      final recs = await service.recommend(remaining: r, limit: 5, userPref: null);
      expect(recs, isNotEmpty);
      // 无 userPref 时行为与 v3 一致，鸡胸肉高蛋白排第一
      expect(recs.first.food.name, '鸡胸肉');
    });

    test('userPref 样本不足 → 不启用偏好加权', () async {
      // 仅 2 次记录（< 5 阈值），hasEnoughSamples=false
      final pref = UserPreferenceProfile(
        tasteFreq: {'spicy': 1, 'sweet': 1},
      );
      expect(pref.hasEnoughSamples, false);
      final r = await service.getDailyRemaining('2026-07-02');
      final recs = await service.recommend(remaining: r, limit: 5, userPref: pref);
      // 样本不足时不启用偏好，鸡胸肉仍排第一（与 v3 一致）
      expect(recs.first.food.name, '鸡胸肉');
    });

    test('辣味偏好 → 辣味食物加分排前', () async {
      // 加辣味食物到库里
      await _seedFood(db, name: '麻辣火锅', cal: 200, protein: 10, fat: 12, carbs: 5);
      await _seedFood(db, name: '川菜辣子鸡', cal: 220, protein: 18, fat: 15, carbs: 4);
      // 用户偏好辣味（5 辣 + 1 甜 = 6 样本，spicy 是 top1）
      final pref = UserPreferenceProfile(
        tasteFreq: {'spicy': 5, 'sweet': 1},
      );
      expect(pref.hasEnoughSamples, true);
      expect(pref.hasSignificantTastePref, true);

      final r = await service.getDailyRemaining('2026-07-02');
      final recsNoPref = await service.recommend(remaining: r, limit: 10, userPref: null);
      final recsWithPref = await service.recommend(remaining: r, limit: 10, userPref: pref);

      // 找麻辣火锅在两个列表中的位置
      final spicyFoodIdxNoPref =
          recsNoPref.indexWhere((e) => e.food.name == '麻辣火锅');
      final spicyFoodIdxWithPref =
          recsWithPref.indexWhere((e) => e.food.name == '麻辣火锅');
      // 前置断言：麻辣火锅应在列表中
      expect(spicyFoodIdxNoPref, greaterThanOrEqualTo(0),
          reason: '无偏好时麻辣火锅应在列表');
      expect(spicyFoodIdxWithPref, greaterThanOrEqualTo(0),
          reason: '有偏好时麻辣火锅应在列表');
      // 有辣味偏好时麻辣火锅得分更高（+2.5）
      expect(recsWithPref[spicyFoodIdxWithPref].score,
          greaterThan(recsNoPref[spicyFoodIdxNoPref].score));
      // reason 文案应包含"符合辣口味"
      expect(recsWithPref[spicyFoodIdxWithPref].reason, contains('辣'));
    });

    test('海鲜风格偏好 → 海鲜食物加分', () async {
      // 加海鲜食物
      await _seedFood(db, name: '清蒸鲈鱼', cal: 120, protein: 20, fat: 4, carbs: 0);
      await _seedFood(db, name: '白灼虾', cal: 100, protein: 22, fat: 1, carbs: 0);
      // 用户偏好海鲜（4 海鲜 + 2 家常 = 6 样本）
      final pref = UserPreferenceProfile(
        styleFreq: {'seafood': 4, 'home': 2},
      );
      expect(pref.hasEnoughSamples, true);

      final r = await service.getDailyRemaining('2026-07-02');
      final recsNoPref = await service.recommend(remaining: r, limit: 10, userPref: null);
      final recsWithPref = await service.recommend(remaining: r, limit: 10, userPref: pref);

      final fishIdxNoPref =
          recsNoPref.indexWhere((e) => e.food.name == '清蒸鲈鱼');
      final fishIdxWithPref =
          recsWithPref.indexWhere((e) => e.food.name == '清蒸鲈鱼');
      expect(fishIdxNoPref, greaterThanOrEqualTo(0));
      expect(fishIdxWithPref, greaterThanOrEqualTo(0));
      expect(recsWithPref[fishIdxWithPref].score,
          greaterThan(recsNoPref[fishIdxNoPref].score));
    });

    test('未尝试口味中性：用户从未吃过辣，辣味食物不加分不减分', () async {
      await _seedFood(db, name: '麻辣火锅', cal: 200, protein: 10, fat: 12, carbs: 5);
      // 用户只吃过甜味（5 次），从未吃过辣 → spicy 不在 tasteFreq → weight=0.5 中性
      // 设计原则：不惩罚"未知"（用户没吃过 ≠ 不喜欢）
      final pref = UserPreferenceProfile(
        tasteFreq: {'sweet': 5},
      );
      expect(pref.hasEnoughSamples, true);
      expect(pref.tasteWeight('spicy'), 0.5); // 未尝试 → 中性

      final r = await service.getDailyRemaining('2026-07-02');
      final recsNoPref = await service.recommend(remaining: r, limit: 10, userPref: null);
      final recsWithPref = await service.recommend(remaining: r, limit: 10, userPref: pref);
      final spicyIdxNoPref =
          recsNoPref.indexWhere((e) => e.food.name == '麻辣火锅');
      final spicyIdxWithPref =
          recsWithPref.indexWhere((e) => e.food.name == '麻辣火锅');
      // 前置断言：麻辣火锅应在两个列表中（避免 if 守卫静默跳过断言）
      expect(spicyIdxNoPref, greaterThanOrEqualTo(0),
          reason: '无偏好时麻辣火锅应在列表');
      expect(spicyIdxWithPref, greaterThanOrEqualTo(0),
          reason: '有偏好时麻辣火锅应在列表');
      // 辣味食物在甜味偏好下 weight=0.5（中性），不加分不减分
      // 得分差异应很小（< 0.5，仅基础分微小波动）
      final diff = (recsWithPref[spicyIdxWithPref].score -
              recsNoPref[spicyIdxNoPref].score)
          .abs();
      expect(diff, lessThan(0.5),
          reason: '未尝试口味应中性，得分不应大幅变化');
    });

    test('少碰口味减分：用户吃过辣但很少，辣味食物降权', () async {
      await _seedFood(db, name: '麻辣火锅', cal: 200, protein: 10, fat: 12, carbs: 5);
      // 用户甜味 10 次 + 辣味 1 次 → spicy weight = 1/10 = 0.1 < 0.2 → 减分
      // 设计原则：用户尝试过但很少吃 = 隐式不偏好 → 适度降权
      final pref = UserPreferenceProfile(
        tasteFreq: {'sweet': 10, 'spicy': 1},
      );
      expect(pref.hasEnoughSamples, true);
      expect(pref.tasteWeight('spicy'), closeTo(0.1, 0.01));
      expect(pref.tasteWeight('spicy'), lessThan(0.2)); // 触发减分阈值

      final r = await service.getDailyRemaining('2026-07-02');
      final recsNoPref = await service.recommend(remaining: r, limit: 10, userPref: null);
      final recsWithPref = await service.recommend(remaining: r, limit: 10, userPref: pref);
      final spicyIdxNoPref =
          recsNoPref.indexWhere((e) => e.food.name == '麻辣火锅');
      final spicyIdxWithPref =
          recsWithPref.indexWhere((e) => e.food.name == '麻辣火锅');
      // 前置断言：麻辣火锅应在两个列表中
      expect(spicyIdxNoPref, greaterThanOrEqualTo(0),
          reason: '无偏好时麻辣火锅应在列表');
      expect(spicyIdxWithPref, greaterThanOrEqualTo(0),
          reason: '有偏好时麻辣火锅应在列表');
      // 辣味食物 weight=0.1 < 0.2 → 减分 -1.0
      // 得分应低于无偏好场景（差值 ≈ 1.0，至少 > 0.5）
      expect(recsWithPref[spicyIdxWithPref].score,
          lessThan(recsNoPref[spicyIdxNoPref].score),
          reason: '少碰口味应被减分');
    });
  });
}

/// 辅助：插入一条食物
Future<void> _seedFood(
  EatWiseDatabase db, {
  required String name,
  required double cal,
  required double protein,
  required double fat,
  required double carbs,
}) async {
  await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
        name: name,
        defaultServingG: 100,
        caloriesPer100g: cal,
        proteinPer100g: protein,
        fatPer100g: fat,
        carbsPer100g: carbs,
        source: 'test',
        sourceVersion: 'test_v1',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
}
