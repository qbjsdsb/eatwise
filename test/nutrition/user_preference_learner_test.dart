// test/nutrition/user_preference_learner_test.dart
//
// 用户偏好学习器单元测试（v4 推荐算法核心组件）
// 覆盖：从 meal_log 学习偏好画像 + 权重计算 + 显著偏好判断 + 边界场景

import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/nutrition/user_preference_learner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory(), seedOnCreate: false);
    foodRepo = FoodItemRepository(db);
    // 预置食物库（覆盖多口味/多风格/多材质/多价格档）
    await _seedFood(db, name: '麻辣火锅', cal: 200, protein: 10, fat: 12, carbs: 5);
    await _seedFood(db, name: '川菜辣子鸡', cal: 250, protein: 18, fat: 15, carbs: 4);
    await _seedFood(db, name: '糖醋排骨', cal: 280, protein: 15, fat: 18, carbs: 12);
    await _seedFood(db, name: '巧克力蛋糕', cal: 350, protein: 5, fat: 18, carbs: 45);
    await _seedFood(db, name: '清蒸鲈鱼', cal: 120, protein: 20, fat: 4, carbs: 0);
    await _seedFood(db, name: '白灼虾', cal: 100, protein: 22, fat: 1, carbs: 0);
    await _seedFood(db, name: '菲力牛排', cal: 250, protein: 26, fat: 15, carbs: 0);
    await _seedFood(db, name: '米饭', cal: 116, protein: 2.6, fat: 0.3, carbs: 25.9);
    await _seedFood(db, name: '凉拌黄瓜', cal: 30, protein: 1, fat: 0.5, carbs: 4);
  });

  tearDown(() async => db.close());

  group('UserPreferenceLearner.learn 偏好学习', () {
    test('空 meal_log → 全维度空 Map', () {
      final foods = <int, FoodItem>{};
      final pref = UserPreferenceLearner.learn([], foods);
      expect(pref.tasteFreq, isEmpty);
      expect(pref.styleFreq, isEmpty);
      expect(pref.textureFreq, isEmpty);
      expect(pref.priceTierFreq, isEmpty);
      expect(pref.hasEnoughSamples, false);
    });

    test('样本不足 → hasEnoughSamples=false', () async {
      final foods = await foodRepo.listAllForRecommendation();
      final foodMap = {for (final f in foods) f.id: f};
      // 仅 2 次记录（< 5 阈值）
      final spicy1 = foods.firstWhere((f) => f.name == '麻辣火锅');
      final spicy2 = foods.firstWhere((f) => f.name == '川菜辣子鸡');
      final meals = [
        _mockMeal(spicy1.id),
        _mockMeal(spicy2.id),
      ];
      final pref = UserPreferenceLearner.learn(meals, foodMap);
      expect(pref.hasEnoughSamples, false);
    });

    test('辣味偏好学习 → spicy 频次最高', () async {
      final foods = await foodRepo.listAllForRecommendation();
      final foodMap = {for (final f in foods) f.id: f};
      final spicy1 = foods.firstWhere((f) => f.name == '麻辣火锅');
      final spicy2 = foods.firstWhere((f) => f.name == '川菜辣子鸡');
      final sweet = foods.firstWhere((f) => f.name == '糖醋排骨');
      final sweet2 = foods.firstWhere((f) => f.name == '巧克力蛋糕');
      final light = foods.firstWhere((f) => f.name == '清蒸鲈鱼');
      // 3 辣 + 2 甜 + 1 清淡 = 6 次（>= 5 阈值）
      final meals = [
        _mockMeal(spicy1.id),
        _mockMeal(spicy2.id),
        _mockMeal(spicy1.id),
        _mockMeal(sweet.id),
        _mockMeal(sweet2.id),
        _mockMeal(light.id),
      ];
      final pref = UserPreferenceLearner.learn(meals, foodMap);
      expect(pref.hasEnoughSamples, true);
      expect(pref.tasteFreq['spicy'], 3);
      expect(pref.tasteFreq['sweet'], 2);
      expect(pref.tasteFreq['light'], 1);
      // spicy 是 top1，weight = 1.0
      expect(pref.tasteWeight('spicy'), 1.0);
      // sweet = 2/3
      expect(pref.tasteWeight('sweet'), closeTo(2 / 3, 0.01));
      // light = 1/3
      expect(pref.tasteWeight('light'), closeTo(1 / 3, 0.01));
      // 显著偏好（top1 占比 3/6=0.5 >= 0.4）
      expect(pref.hasSignificantTastePref, true);
    });

    test('海鲜风格偏好学习', () async {
      final foods = await foodRepo.listAllForRecommendation();
      final foodMap = {for (final f in foods) f.id: f};
      final fish = foods.firstWhere((f) => f.name == '清蒸鲈鱼');
      final shrimp = foods.firstWhere((f) => f.name == '白灼虾');
      final steak = foods.firstWhere((f) => f.name == '菲力牛排');
      // 4 海鲜 + 2 西式（牛排）= 6 次
      final meals = [
        _mockMeal(fish.id),
        _mockMeal(shrimp.id),
        _mockMeal(fish.id),
        _mockMeal(shrimp.id),
        _mockMeal(steak.id),
        _mockMeal(steak.id),
      ];
      final pref = UserPreferenceLearner.learn(meals, foodMap);
      expect(pref.styleFreq['seafood'], 4);
      expect(pref.styleFreq['western'], 2);
      expect(pref.styleWeight('seafood'), 1.0);
      expect(pref.hasSignificantStylePref, true);
    });

    test('价格档偏好学习（经济档）', () async {
      final foods = await foodRepo.listAllForRecommendation();
      final foodMap = {for (final f in foods) f.id: f};
      final rice = foods.firstWhere((f) => f.name == '米饭');
      final steak = foods.firstWhere((f) => f.name == '菲力牛排');
      // 5 经济 + 1 精致
      final meals = [
        _mockMeal(rice.id),
        _mockMeal(rice.id),
        _mockMeal(rice.id),
        _mockMeal(rice.id),
        _mockMeal(rice.id),
        _mockMeal(steak.id),
      ];
      final pref = UserPreferenceLearner.learn(meals, foodMap);
      expect(pref.priceTierFreq['budget'], 5);
      expect(pref.priceTierFreq['premium'], 1);
      expect(pref.priceTierWeight('budget'), 1.0);
      expect(pref.priceTierWeight('premium'), closeTo(0.2, 0.01));
      expect(pref.hasSignificantPricePref, true);
    });

    test('food_item 已删除 → 跳过不计数', () {
      final foods = <int, FoodItem>{};
      // foodMap 空，所有 meal_log 都查不到 food → 全跳过
      final meals = [
        _mockMeal(999),
        _mockMeal(998),
        _mockMeal(997),
      ];
      final pref = UserPreferenceLearner.learn(meals, foods);
      expect(pref.tasteFreq, isEmpty);
      expect(pref.hasEnoughSamples, false);
    });

    test('weight 边界：null 标签 → 0.5 中性', () {
      final pref = UserPreferenceProfile(
        tasteFreq: {'spicy': 5},
      );
      expect(pref.tasteWeight(null), 0.5);
    });

    test('weight 边界：未知标签（用户从未吃过）→ 0.5 中性', () {
      final pref = UserPreferenceProfile(
        tasteFreq: {'spicy': 5},
      );
      // 'sweet' 不在 freq 里 → 用户从未吃过甜味 → 中性 0.5
      // 设计原则：不惩罚"未知"（没吃过 ≠ 不喜欢）
      expect(pref.tasteWeight('sweet'), 0.5);
    });

    test('weight 边界：空 freq → 0.5 中性', () {
      const pref = UserPreferenceProfile();
      expect(pref.tasteWeight('spicy'), 0.5);
      expect(pref.hasSignificantTastePref, false);
    });

    test('显著偏好判断：仅 1 个标签 → 不算显著', () {
      final pref = UserPreferenceProfile(
        tasteFreq: {'spicy': 10}, // 只有 1 个标签
      );
      expect(pref.hasSignificantTastePref, false); // length < 2
    });

    test('显著偏好判断：样本 < 3 → 不算显著', () {
      final pref = UserPreferenceProfile(
        tasteFreq: {'spicy': 2, 'sweet': 0}, // 总样本 2 < 3
      );
      expect(pref.hasSignificantTastePref, false);
    });

    test('材质偏好学习（清蒸）', () async {
      final foods = await foodRepo.listAllForRecommendation();
      final foodMap = {for (final f in foods) f.id: f};
      final fish = foods.firstWhere((f) => f.name == '清蒸鲈鱼');
      final shrimp = foods.firstWhere((f) => f.name == '白灼虾'); // 白灼 → light taste, 无 texture
      final coldCucumber = foods.firstWhere((f) => f.name == '凉拌黄瓜');
      // 4 清蒸 + 1 凉拌 + 1 白灼（无 texture 标签）
      final meals = [
        _mockMeal(fish.id),
        _mockMeal(fish.id),
        _mockMeal(fish.id),
        _mockMeal(fish.id),
        _mockMeal(coldCucumber.id),
        _mockMeal(shrimp.id),
      ];
      final pref = UserPreferenceLearner.learn(meals, foodMap);
      expect(pref.textureFreq['steamed'], 4);
      expect(pref.textureFreq['cold'], 1);
      expect(pref.textureWeight('steamed'), 1.0);
      expect(pref.hasSignificantTexturePref, true);
    });
  });

  group('hasEnoughSamples 4 维度统计', () {
    test('仅 texture 标签 → total >= 5 → hasEnoughSamples=true', () {
      // 用户所有食物仅有 texture 标签（无 taste/style/priceTier）
      // 修复前：total = tasteFreq(0) + styleFreq(0) = 0 → false（错误禁用偏好加权）
      // 修复后：total = tasteFreq(0) + styleFreq(0) + textureFreq(5) + priceTierFreq(0) = 5 → true
      final pref = UserPreferenceProfile(
        textureFreq: {'steamed': 3, 'cold': 2},
      );
      expect(pref.hasEnoughSamples, true);
    });

    test('仅 priceTier 标签 → total >= 5 → hasEnoughSamples=true', () {
      // 用户所有食物仅有 priceTier 标签（无 taste/style/texture）
      // 修复前：total = tasteFreq(0) + styleFreq(0) = 0 → false（错误禁用偏好加权）
      // 修复后：total = tasteFreq(0) + styleFreq(0) + textureFreq(0) + priceTierFreq(5) = 5 → true
      final pref = UserPreferenceProfile(
        priceTierFreq: {'budget': 4, 'premium': 1},
      );
      expect(pref.hasEnoughSamples, true);
    });

    test('4 维度都有标签 → 回归测试（不破坏现有行为）', () {
      // taste(5) + style(3) + texture(2) + priceTier(3) = 13 >= 5 → true
      // 修复前 taste+style=8 >= 5 → true；修复后 13 >= 5 → true（行为一致）
      final pref = UserPreferenceProfile(
        tasteFreq: {'spicy': 3, 'sweet': 2},
        styleFreq: {'seafood': 2, 'western': 1},
        textureFreq: {'steamed': 1, 'cold': 1},
        priceTierFreq: {'budget': 2, 'premium': 1},
      );
      expect(pref.hasEnoughSamples, true);
    });
  });
}

/// 构造 mock MealLog（仅 foodItemId 用于学习）
MealLog _mockMeal(int foodItemId) {
  return MealLog(
    id: 0,
    date: '2026-07-01',
    mealType: 'lunch',
    foodItemId: foodItemId,
    actualServingG: 100,
    actualCalories: 100,
    actualProteinG: 10,
    actualFatG: 5,
    actualCarbsG: 10,
    loggedAt: 0,
  );
}

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
