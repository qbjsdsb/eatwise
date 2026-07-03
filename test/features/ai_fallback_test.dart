// AI 兜底估算数据流测试
//
// 验证 v1.1 prompt 场景：库未命中的单品用 AI 整菜估算兜底。
// 完整链路：AI 结果(estimatedCalories) → 构造 aiEstimate NutritionResult(foodItemId=0 哨兵)
//          → upsertAiRecognized 创建 food_item 替换哨兵 → insertMealLog FK 约束通过
//
// 不经过 RecognizeController.pickAndRecognize（依赖 ImagePicker 平台插件，沙箱无法跑），
// 直接测 recognize_page onConfirm 的核心数据流逻辑。

import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;
  late MealLogRepository mealRepo;
  late NutritionLookup lookup;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    foodRepo = FoodItemRepository(db);
    mealRepo = MealLogRepository(db);
    lookup = NutritionLookup(foodRepo);
    // 不预置任何食物 → 模拟"库外食物"
  });

  tearDown(() async => db.close());

  test('库未命中 + AI 估算兜底：foodItemId=0 哨兵 → upsert 替换 → FK 通过', () async {
    // 1. 模拟 v1.1 AI 识别结果（菜名不在库 + 含营养估算）
    final aiResult = const VisionRecognitionResult(
      dishName: '螺蛳粉', // 库外食物
      estimatedWeightGLow: 350,
      estimatedWeightGMid: 400,
      estimatedWeightGHigh: 500,
      foodComponents: [],
      cookingMethod: 'boil',
      isSingleItem: true,
      confidence: 0.82,
      promptVersion: 'v1.1',
      estimatedCalories: 580,
      estimatedProteinG: 18,
      estimatedFatG: 22,
      estimatedCarbsG: 75,
    );

    // 2. 查库未命中（lookupSingleItem 返回 null）
    final nutrition = await lookup.lookupSingleItem(
      dishName: aiResult.dishName,
      servingG: aiResult.estimatedWeightGMid,
    );
    expect(nutrition, isNull, reason: '库外食物应返回 null');

    // 3. 模拟 controller _aiFallbackNutrition：构造 aiEstimate 结果（foodItemId=0 哨兵）
    final fallback = NutritionResult(
      foodItemId: 0, // 哨兵
      calories: aiResult.estimatedCalories!,
      proteinG: aiResult.estimatedProteinG!,
      fatG: aiResult.estimatedFatG!,
      carbsG: aiResult.estimatedCarbsG!,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );
    expect(fallback.source, NutritionSource.aiEstimate);
    expect(fallback.foodItemId, 0, reason: '哨兵值，写库前必须替换');

    // 4. 模拟 recognize_page onConfirm：foodItemId==0 走 upsertAiRecognized
    //    per100g 由实际份量反算
    const servingG = 400.0;
    final per100 = servingG > 0 ? 100.0 / servingG : 0.0;
    final foodItemId = await foodRepo.upsertAiRecognized(
      name: aiResult.dishName,
      caloriesPer100g: fallback.calories * per100,
      proteinPer100g: fallback.proteinG * per100,
      fatPer100g: fallback.fatG * per100,
      carbsPer100g: fallback.carbsG * per100,
      confidence: aiResult.confidence,
    );
    expect(foodItemId, greaterThan(0), reason: 'upsert 必须返回有效 id');

    // 5. insertMealLog 用真实 foodItemId（FK 约束应通过，不抛异常）
    final mealId = await mealRepo.insertMealLog(
      date: '2026-07-03',
      mealType: 'lunch',
      foodItemId: foodItemId,
      actualServingG: servingG,
      actualCalories: fallback.calories,
      actualProteinG: fallback.proteinG,
      actualFatG: fallback.fatG,
      actualCarbsG: fallback.carbsG,
    );
    expect(mealId, greaterThan(0));

    // 6. 验证食物名能反查（today_meals 页用 foodItemId 查名）
    final foodItem = await foodRepo.getById(foodItemId);
    expect(foodItem, isNotNull);
    expect(foodItem!.name, '螺蛳粉');
    expect(foodItem.source, 'ai_recognized');
    // per100g 反算值：580 * 100/400 = 145
    expect(foodItem.caloriesPer100g, closeTo(145, 0.01));
  });

  test('库命中时 source=database 且 foodItemId 为真实 id（不走 AI 兜底）', () async {
    // 预置库内食物
    await db
        .into(db.foodItems)
        .insert(
          FoodItemsCompanion.insert(
            name: '苹果',
            defaultServingG: 100,
            caloriesPer100g: 52,
            proteinPer100g: 0.3,
            fatPer100g: 0.2,
            carbsPer100g: 13.8,
            source: 'china_fct',
            sourceVersion: 'test',
            createdAt: 0,
          ),
        );

    final nutrition = await lookup.lookupSingleItem(
      dishName: '苹果',
      servingG: 180,
    );
    expect(nutrition, isNotNull);
    expect(
      nutrition!.source,
      NutritionSource.database,
      reason: '库命中默认 database',
    );
    expect(
      nutrition.foodItemId,
      greaterThan(0),
      reason: '库命中 foodItemId 为真实 id',
    );
    expect(nutrition.calories, closeTo(93.6, 0.01)); // 52 * 180 / 100
  });

  test('upsertAiRecognized 幂等：同名 ai_recognized 食物第二次返回同 id', () async {
    final id1 = await foodRepo.upsertAiRecognized(
      name: '麻辣烫',
      caloriesPer100g: 120,
      proteinPer100g: 8,
      fatPer100g: 5,
      carbsPer100g: 10,
    );
    final id2 = await foodRepo.upsertAiRecognized(
      name: '麻辣烫',
      caloriesPer100g: 130, // 更新值
      proteinPer100g: 9,
      fatPer100g: 6,
      carbsPer100g: 11,
    );
    expect(id2, id1, reason: '幂等：同名同 source 应复用 id');
    final item = await foodRepo.getById(id1);
    expect(item!.caloriesPer100g, 130, reason: '值应被更新');
  });
}
