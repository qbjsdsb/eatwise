// CalibrationPage 单品识别校准页测试
//
// 方案 D（M25）：废弃品类校准。历史啤酒场景（雪花啤酒被识别成雪碧的 workaround）
// 已删除——AI 识别精准后啤酒补丁无意义。
//
// 保留测试：
//   1. 查库命中 + AI 偏差大：预览与 onConfirm 用 AI 估算值（M16.8 差异检测）
//   2. 查库命中 + aiFallbackNutrition=null 老调用方兼容（走原 ratio 逻辑）
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/features/recognize/calibration_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    foodRepo = FoodItemRepository(db);
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
  });
  tearDown(() async => db.close());

  testWidgets('查库命中 + aiFallbackNutrition=null：走原 ratio 逻辑兼容老调用方',
      (tester) async {
    // 老调用方未传 aiFallbackNutrition（M16.8 前的接口）
    // 查库命中分支应保持原 ratio 逻辑：calories * servingG / mid
    final r = VisionRecognitionResult(
      dishName: '番茄',
      estimatedWeightGLow: 90,
      estimatedWeightGMid: 100,
      estimatedWeightGHigh: 110,
      estimatedCalories: 18,
      estimatedProteinG: 0.9,
      estimatedFatG: 0.2,
      estimatedCarbsG: 3.9,
      foodComponents: const [],
      cookingMethod: '',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.10',
    );
    final food = await (db.select(db.foodItems)
          ..where((t) => t.name.equals('番茄')))
        .getSingle();
    final lookupHit = NutritionResult(
      foodItemId: food.id,
      calories: 18, // 库 per100g=18, mid=100 → calories=18
      proteinG: 0.9,
      fatG: 0.2,
      carbsG: 3.9,
      oilG: 0,
      source: NutritionSource.database,
    );

    double? capturedCalories;
    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: r,
        singleNutrition: lookupHit,
        foodItemRepo: foodRepo,
        suggestedServingG: 200,
        onConfirm: (servingG, calories, protein, fat, carbs,
            {componentsSnapshot}) async {
          capturedCalories = calories;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    // 查库命中 + 无 aiFallback：走原 ratio 逻辑
    // 18 * 200 / 100 = 36
    expect(capturedCalories, closeTo(36, 0.5),
        reason: '查库命中 + 无 aiFallback 走原 ratio：18 * 200 / 100 = 36');
  });

  // M16.8 Task 5：查库命中分支预览与 onConfirm 同步用差异检测。
  //
  // 库"番茄炒蛋" per100g=80（脏数据），AI 估 200g/250kcal（库值 160 vs AI 250，偏差 56% > 50%）。
  // 期望：预览显示 250（AI 估算值，与 reasoning 一致），onConfirm 传 250（与预览一致），
  // 不再走原 ratio 逻辑显示 160（库值，与 AI reasoning 脱节）。
  testWidgets(
      'M16.8: 查库命中 + AI 偏差大预览用 AI 估算值（与记录一致）', (tester) async {
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
    final food = await (db.select(db.foodItems)
          ..where((t) => t.name.equals('番茄炒蛋')))
        .getSingle();

    final r = VisionRecognitionResult(
      dishName: '番茄炒蛋',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      estimatedCalories: 250,
      estimatedProteinG: 10,
      estimatedFatG: 15,
      estimatedCarbsG: 20,
      foodComponents: const [],
      cookingMethod: 'stir_fry',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.10',
    );
    // 查库命中：foodItemId > 0，calories = 80 * 200 / 100 = 160
    final lookupHit = NutritionResult(
      foodItemId: food.id,
      calories: 160,
      proteinG: 6,
      fatG: 10,
      carbsG: 12,
      oilG: 0,
      source: NutritionSource.database,
    );
    // AI 兜底：foodItemId=0，calories 对应 mid=200 份量
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 250,
      proteinG: 10,
      fatG: 15,
      carbsG: 20,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );

    double? capturedCalories;
    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: r,
        singleNutrition: lookupHit,
        aiFallbackNutrition: aiFallback,
        foodItemRepo: foodRepo,
        // 用 suggestedServingG=200 锁定滑块初值，避开拖滑块精度问题
        suggestedServingG: 200,
        onConfirm: (servingG, calories, protein, fat, carbs,
            {componentsSnapshot}) async {
          capturedCalories = calories;
        },
      ),
    ));
    await tester.pumpAndSettle();

    // 预览应显示 250（AI 估算值，与 reasoning 一致），不是 160（库值 × ratio）
    expect(find.text('250'), findsOneWidget,
        reason: '查库命中 + AI 偏差大预览应显示 AI 估算值 250，而非库值 160');

    // 点确认：onConfirm 传值应与预览一致
    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    expect(capturedCalories, isNotNull);
    expect(capturedCalories, closeTo(250, 0.5),
        reason: 'onConfirm 传值应与预览一致（AI 估算 250，与记录同源）');
  });
}
