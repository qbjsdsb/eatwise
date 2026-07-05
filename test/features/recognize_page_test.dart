// M16.6 Task 3：recognize_page AI 兜底哨兵路径 actualCalories 一致性测试
//
// 验证：AI 兜底哨兵分支（foodItemId=0）下，meal_log.actualCalories 必须用
// 校准后 per100g 重算（与 food_item.caloriesPer100g 同源），不能用 onConfirm
// 传入的未校准 calories（来自 _aiFallbackNutrition 的 r.estimatedCalories）。
//
// 场景：beer 品类，AI estimatedCalories=600（mid=300，per100g=200），
// FoodCategoryDefaults.calibrate 校准为 43（偏离 2 倍以上）。
// 用户不调整滑块（servingG=300），期望 meal_log.actualCalories=43*300/100=129。
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/features/recognize/recognize_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;
  late MealLogRepository mealRepo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    foodRepo = FoodItemRepository(db);
    mealRepo = MealLogRepository(db);
  });

  tearDown(() async => db.close());

  /// beer 场景 VisionRecognitionResult
  /// AI estimatedCalories=600，mid=300 → per100g=200（偏离 beer 默认 43 两倍以上）
  const beerResult = VisionRecognitionResult(
    dishName: '啤酒',
    estimatedWeightGLow: 250,
    estimatedWeightGMid: 300,
    estimatedWeightGHigh: 350,
    foodComponents: [],
    cookingMethod: 'drink',
    isSingleItem: true,
    confidence: 0.9,
    promptVersion: 'v1.4',
    foodCategory: 'beer',
    estimatedCalories: 600,
    estimatedProteinG: 3.0,
    estimatedFatG: 0,
    estimatedCarbsG: 18,
  );

  /// AI 兜底 NutritionResult（foodItemId=0 哨兵，calories 对应 mid 份量）
  final aiFallback = NutritionResult(
    foodItemId: 0,
    calories: 600,
    proteinG: 3.0,
    fatG: 0,
    carbsG: 18,
    oilG: 0,
    source: NutritionSource.aiEstimate,
  );

  test(
      'M16.6: AI 兜底哨兵路径 beer 场景 meal_log.actualCalories 用校准后 per100g 计算',
      () async {
    // 用户不调整滑块，servingG=300
    // CalibrationPage 按 ratio=servingG/mid=1 传 onConfirm：
    //   calories=600*1=600（未校准），protein=3.0，fat=0，carbs=18
    final actualCalories = await RecognizePage.writeCalibratedMealLog(
      foodRepo: foodRepo,
      mealRepo: mealRepo,
      result: beerResult,
      singleNutrition: aiFallback,
      compositeNutrition: null,
      mealType: 'dinner',
      servingG: 300,
      calories: 600,
      protein: 3.0,
      fat: 0,
      carbs: 18,
      componentsSnapshot: null,
      imagePath: null,
    );

    // meal_log 应写入 1 条
    final meals = await db.mealLogs.select().get();
    expect(meals.length, 1, reason: '应写入 1 条 meal_log');

    // food_item 应写入 1 条（ai_recognized）
    final foods = await db.foodItems.select().get();
    expect(foods.length, 1, reason: '应写入 1 条 food_item');

    // 核心断言：food_item.caloriesPer100g 应被品类校准为 43（beer 默认值）
    // AI 估 200 kcal/100g 偏离 43 两倍以上 → 校准为 43
    expect(foods.first.caloriesPer100g, closeTo(43, 0.5),
        reason: 'food_item.caloriesPer100g 应为 beer 品类默认值 43');

    // 核心断言：meal_log.actualCalories 应 = 校准后 per100g * servingG / 100
    // = 43 * 300 / 100 = 129（不是 onConfirm 传入的未校准 600）
    expect(meals.first.actualCalories, closeTo(129, 0.5),
        reason: 'meal_log.actualCalories 应基于校准后 per100g 计算（129），'
            '不能用未校准的 onConfirm calories（600）');

    // actualCalories 返回值应与 meal_log 一致（用于 toast 显示）
    expect(actualCalories, closeTo(129, 0.5),
        reason: '返回的 actualCalories 应为校准后值，与 meal_log 一致');

    // 宏量也应用校准后 per100g 计算（beer 默认 protein=0.5, fat=0, carbs=3.1）
    // actualProteinG = 0.5 * 300 / 100 = 1.5
    expect(meals.first.actualProteinG, closeTo(1.5, 0.05),
        reason: 'actualProteinG 应基于校准后 proteinPer100g 计算');
    // actualFatG = 0 * 300 / 100 = 0
    expect(meals.first.actualFatG, closeTo(0, 0.01),
        reason: 'actualFatG 应基于校准后 fatPer100g 计算');
    // actualCarbsG = 3.1 * 300 / 100 = 9.3
    expect(meals.first.actualCarbsG, closeTo(9.3, 0.05),
        reason: 'actualCarbsG 应基于校准后 carbsPer100g 计算');

    // food_item 的 per100g 宏量也应与 meal_log 同源
    expect(foods.first.proteinPer100g, closeTo(0.5, 0.01));
    expect(foods.first.fatPer100g, closeTo(0, 0.01));
    expect(foods.first.carbsPer100g, closeTo(3.1, 0.01));
  });

  test('M16.6: 查库命中路径（foodItemId>0）不受校准影响，保持原值', () async {
    // 预置一条食物库记录（番茄，id=1）
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '番茄',
          defaultServingG: 100,
          caloriesPer100g: 18,
          proteinPer100g: 0.9,
          fatPer100g: 0.2,
          carbsPer100g: 3.9,
          source: 'china_fct',
          sourceVersion: 'test',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));

    const result = VisionRecognitionResult(
      dishName: '番茄',
      estimatedWeightGLow: 80,
      estimatedWeightGMid: 100,
      estimatedWeightGHigh: 120,
      foodComponents: [],
      cookingMethod: 'raw',
      isSingleItem: true,
      confidence: 0.95,
      promptVersion: 'v1.0',
      foodCategory: 'solid',
    );
    final dbHit = NutritionResult(
      foodItemId: 1, // 查库命中，非哨兵
      calories: 18,
      proteinG: 0.9,
      fatG: 0.2,
      carbsG: 3.9,
      oilG: 0,
    );

    final actualCalories = await RecognizePage.writeCalibratedMealLog(
      foodRepo: foodRepo,
      mealRepo: mealRepo,
      result: result,
      singleNutrition: dbHit,
      compositeNutrition: null,
      mealType: 'lunch',
      servingG: 100,
      calories: 18,
      protein: 0.9,
      fat: 0.2,
      carbs: 3.9,
      componentsSnapshot: null,
      imagePath: null,
    );

    // 查库命中路径：actualCalories 直接用 onConfirm 传入值（已基于 DB per100g，无脱节）
    final meals = await db.mealLogs.select().get();
    expect(meals.length, 1);
    expect(meals.first.actualCalories, closeTo(18, 0.5),
        reason: '查库命中路径应保持原值，不受品类校准影响');
    expect(actualCalories, closeTo(18, 0.5));

    // food_item 不应新增（查库命中，复用 id=1）
    final foods = await db.foodItems.select().get();
    expect(foods.length, 1, reason: '查库命中不应新增 food_item');
  });
}
