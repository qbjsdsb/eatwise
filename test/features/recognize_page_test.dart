// M16.6 Task 3：recognize_page AI 兜底哨兵路径 actualCalories 一致性测试
//
// 验证：AI 兜底哨兵分支（foodItemId=0）下，meal_log.actualCalories 必须用
// 校准后 per100g 重算（与 food_item.caloriesPer100g 同源），不能用 onConfirm
// 传入的未校准 calories（来自 _aiFallbackNutrition 的 r.estimatedCalories）。
//
// 方案 D（M25）：废弃品类校准。AI 兜底哨兵下，4 项全保留 AI 估算值（只做物理 clamp）。
// 场景：beer 品类，AI estimatedCalories=600（mid=300，per100g=200）。
// 用户不调整滑块（servingG=300），期望 meal_log.actualCalories=200*300/100=600。
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

  // 历史啤酒哨兵场景已删除（方案 D 废弃品类校准，啤酒补丁无意义）
  // AI 兜底哨兵路径的 actualCalories 一致性由 calibrated_nutrition_calculator_test.dart
  // 与 plan_d_calibrate_removal_test.dart 的 solid/soup 场景覆盖

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

  // M16.8 Task 4：查库命中分支接入差异检测——AI 与库 per100g 偏差 > 50% 时
  // 用 AI 反算 per100g 写库 + 用 AI 估算值记 meal_log；偏差 ≤ 50% 用库值不更新库。
  // 修复根因 A：查库命中分支原完全忽略 AI 估算致与 reasoning 脱节。
  // v2 改动 E：writeCalibratedMealLog 不再重算 actualXxx，用 onConfirm 传入值
  // （CalibrationPage 已用 _applyUserOverrides 算好——AI 值或用户编辑值）。
  // 库 per100g 仍由 CalibratedNutritionCalculator 算（保持库一致性）。
  test(
      'v2: 查库命中 + AI 偏差大时 actualCalories 用 onConfirm 传入值 + 更新库 per100g',
      () async {
    // 库有"番茄炒蛋" per100g=80（脏数据）
    // AI 估 200g/250kcal（库值 160 vs AI 250，偏差 56% > 50%）
    // v2 改动 E：CalibrationPage 传 AI 值 250（_applyUserOverrides 后），
    // writeCalibratedMealLog 不重算，actualCalories=250（onConfirm 传入值）
    // 库 per100g 仍由 CalibratedNutritionCalculator 算 → 更新为 125
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '番茄炒蛋',
          defaultServingG: 100,
          caloriesPer100g: 80,
          proteinPer100g: 6,
          fatPer100g: 10,
          carbsPer100g: 12,
          source: 'china_fct',
          sourceVersion: 'test',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));

    const r = VisionRecognitionResult(
      dishName: '番茄炒蛋',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      estimatedCalories: 250,
      estimatedProteinG: 10,
      estimatedFatG: 15,
      estimatedCarbsG: 20,
      foodComponents: [],
      cookingMethod: 'stir_fry',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.0',
      foodCategory: 'solid',
    );
    final lookupHit = NutritionResult(
      foodItemId: 1, // 查库命中
      calories: 160, // 80 * 200 / 100（库 per100g × mid / 100）
      proteinG: 6,
      fatG: 10,
      carbsG: 12,
      oilG: 0,
    );
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 250,
      proteinG: 10,
      fatG: 15,
      carbsG: 20,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );

    final actualCalories = await RecognizePage.writeCalibratedMealLog(
      foodRepo: foodRepo,
      mealRepo: mealRepo,
      result: r,
      singleNutrition: lookupHit,
      aiFallbackNutrition: aiFallback,
      compositeNutrition: null,
      mealType: 'lunch',
      servingG: 200,
      // v2 改动 E：CalibrationPage 传 AI 值 250（_applyUserOverrides 后），
      // writeCalibratedMealLog 不重算，直接用此值
      calories: 250,
      protein: 10,
      fat: 15,
      carbs: 20,
      componentsSnapshot: null,
      imagePath: null,
    );

    expect(actualCalories, closeTo(250, 0.5),
        reason: 'v2 改动 E：actualCalories 用 onConfirm 传入值（250）');

    // food_item.per100g 应被更新为 AI 反算值 125（= 250 * 100 / 200）
    final foods = await db.foodItems.select().get();
    expect(foods.length, 1, reason: '查库命中不应新增 food_item');
    expect(foods.first.caloriesPer100g, closeTo(125, 0.5),
        reason: '库 per100g 应被 AI 反算值（125）更新纠正脏库');

    // meal_log 应记 250（与 onConfirm 传入值一致）
    final meals = await db.mealLogs.select().get();
    expect(meals.length, 1);
    expect(meals.first.actualCalories, closeTo(250, 0.5),
        reason: 'meal_log.actualCalories 应为 onConfirm 传入值');
  });

  test('v2: 查库命中 + AI 偏差小时 actualCalories 用 onConfirm 传入值（AI 绝对优先）', () async {
    // 库 per100g=80, AI 估 200g/170kcal（库值 160 vs AI 170，偏差 6%）
    // v2 改动 E：CalibrationPage 传 AI 值 170，writeCalibratedMealLog 不重算
    // 库 per100g 仍由 CalibratedNutritionCalculator 算 → 更新为 85
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '番茄炒蛋',
          defaultServingG: 100,
          caloriesPer100g: 80,
          proteinPer100g: 6,
          fatPer100g: 10,
          carbsPer100g: 12,
          source: 'china_fct',
          sourceVersion: 'test',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));

    const r = VisionRecognitionResult(
      dishName: '番茄炒蛋',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      estimatedCalories: 170, // AI 估 170，库值 160，偏差 6%
      estimatedProteinG: 7,
      estimatedFatG: 10,
      estimatedCarbsG: 13,
      foodComponents: [],
      cookingMethod: 'stir_fry',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.0',
      foodCategory: 'solid',
    );
    final lookupHit = NutritionResult(
      foodItemId: 1,
      calories: 160,
      proteinG: 6,
      fatG: 10,
      carbsG: 12,
      oilG: 0,
    );
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 170,
      proteinG: 7,
      fatG: 10,
      carbsG: 13,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );

    final actualCalories = await RecognizePage.writeCalibratedMealLog(
      foodRepo: foodRepo,
      mealRepo: mealRepo,
      result: r,
      singleNutrition: lookupHit,
      aiFallbackNutrition: aiFallback,
      compositeNutrition: null,
      mealType: 'lunch',
      servingG: 200,
      // v2 改动 E：CalibrationPage 传 AI 值 170（_applyUserOverrides 后）
      calories: 170,
      protein: 7,
      fat: 10,
      carbs: 13,
      componentsSnapshot: null,
      imagePath: null,
    );

    expect(actualCalories, closeTo(170, 0.5),
        reason: 'v2 改动 E：actualCalories 用 onConfirm 传入值（170）');

    // food_item.per100g 应被更新为 AI 反算值 85（= 170 * 100 / 200）
    final foods = await db.foodItems.select().get();
    expect(foods.first.caloriesPer100g, closeTo(85, 0.5),
        reason: '库 per100g 应被 AI 反算值（85）更新');

    // meal_log 应记 170（与 onConfirm 传入值一致）
    final meals = await db.mealLogs.select().get();
    expect(meals.first.actualCalories, closeTo(170, 0.5));
  });

  // M16.8 Task 8：验证 writeCalibratedMealLog 记录 recognitionConfidence + componentsSnapshotJson
  // 契约：_showNotFoundDialog 改菜名重试路径改调 writeCalibratedMealLog 后，
  // meal_log 必须有 recognitionConfidence（来自 result.confidence）和 componentsSnapshotJson
  // （来自 componentsSnapshot）。原 _showNotFoundDialog 直接调 mealRepo.insertMealLog 缺这两字段。
  test(
      'M16.8: writeCalibratedMealLog 查库命中时记录 recognitionConfidence + componentsSnapshotJson', () async {
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '番茄炒蛋',
          defaultServingG: 100,
          caloriesPer100g: 80,
          proteinPer100g: 6,
          fatPer100g: 10,
          carbsPer100g: 12,
          source: 'china_fct',
          sourceVersion: 'test',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));

    const r = VisionRecognitionResult(
      dishName: '番茄炒蛋',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      estimatedCalories: 170,
      estimatedProteinG: 7,
      estimatedFatG: 10,
      estimatedCarbsG: 13,
      foodComponents: [],
      cookingMethod: 'stir_fry',
      isSingleItem: true,
      confidence: 0.85, // 识别置信度
      promptVersion: 'v1.0',
      foodCategory: 'solid',
    );
    final lookupHit = NutritionResult(
      foodItemId: 1,
      calories: 160,
      proteinG: 6,
      fatG: 10,
      carbsG: 12,
      oilG: 0,
    );
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 170,
      proteinG: 7,
      fatG: 10,
      carbsG: 13,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );
    const componentsSnapshot = '[{"name":"番茄","weight":100}]';

    await RecognizePage.writeCalibratedMealLog(
      foodRepo: foodRepo,
      mealRepo: mealRepo,
      result: r,
      singleNutrition: lookupHit,
      aiFallbackNutrition: aiFallback,
      compositeNutrition: null,
      mealType: 'lunch',
      servingG: 200,
      calories: 160,
      protein: 6,
      fat: 10,
      carbs: 12,
      componentsSnapshot: componentsSnapshot,
      imagePath: null,
    );

    final meals = await db.mealLogs.select().get();
    expect(meals.length, 1, reason: '应记录一条 meal_log');
    expect(meals.first.recognitionConfidence, closeTo(0.85, 0.001),
        reason: '改菜名重试路径也应记录识别置信度（来自 result.confidence）');
    expect(meals.first.componentsSnapshotJson, componentsSnapshot,
        reason: '改菜名重试路径也应记录组分快照');
  });

  group('M22 done 态成功停留', () {
    test('doneSuccessDwell 常量存在且为 400ms（M22 done 成功停留）', () {
      // M22：done 态成功停留 400ms，让用户看到完成反馈再跳转
      expect(
        RecognizePage.doneSuccessDwell,
        const Duration(milliseconds: 400),
        reason: 'done 态应停留 400ms 让用户看到成功反馈，不再瞬间消失',
      );
    });
  });
}
