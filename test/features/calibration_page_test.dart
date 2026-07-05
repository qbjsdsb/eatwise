import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/features/recognize/calibration_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// CalibrationPage 单品 AI 兜底哨兵路径（foodItemId=0）一致性测试
///
/// M16.6 Task 5：验证预览显示值与 onConfirm 传入值都用品类校准后的 per100g 计算，
/// 与 recognize_page 写食物库 per100g 逻辑一致，避免"推理过程数值与最终记录数值不一致"。
///
/// 场景：beer 品类，AI 估 600kcal（mid=300g，per100g=200 偏离 beer 默认 43 → 校准）
/// 用户调整滑块到 servingG=200
/// 期望：预览 + onConfirm 都用 43 * 200 / 100 = 86（不是未校准的 600 * 200/300 = 400）
void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    foodRepo = FoodItemRepository(db);
  });
  tearDown(() async => db.close());

  // 构造 beer 单品 AI 兜底场景的 RecognitionResult
  VisionRecognitionResult beerRecognition() => VisionRecognitionResult(
        dishName: '啤酒',
        estimatedWeightGLow: 250,
        estimatedWeightGMid: 300,
        estimatedWeightGHigh: 350,
        foodComponents: const [],
        cookingMethod: '',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.10',
        estimatedCalories: 600,
        estimatedProteinG: 2,
        estimatedFatG: 1,
        estimatedCarbsG: 15,
        foodCategory: 'beer',
      );

  // AI 兜底哨兵：foodItemId=0，calories=600 对应 mid=300 份量
  NutritionResult aiFallback() => NutritionResult(
        foodItemId: 0,
        calories: 600,
        proteinG: 2,
        fatG: 1,
        carbsG: 15,
        oilG: 0,
        source: NutritionSource.aiEstimate,
      );

  testWidgets(
      'AI 兜底哨兵路径：预览显示校准后 actualCalories（beer 86，非未校准 400）',
      (tester) async {
    // 用 suggestedServingG=200 把初始滑块值定为 200（避开手动拖滑块的精度问题）
    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: beerRecognition(),
        singleNutrition: aiFallback(),
        foodItemRepo: foodRepo,
        suggestedServingG: 200,
        onConfirm: (_, __, ___, ____, _____, {componentsSnapshot}) async {},
      ),
    ));
    await tester.pumpAndSettle();

    // 校准后 per100g=43，actualCalories = 43 * 200 / 100 = 86（不是 600*200/300=400）
    // 预览卡片用 headlineMedium 显示热量整数：'86'
    expect(find.text('86'), findsOneWidget,
        reason: '预览应显示校准后 86 kcal，而非未校准 400 kcal');
    // 不应出现 '400'（未校准值的特征字符串）
    expect(find.text('400'), findsNothing,
        reason: '预览不应出现未校准的 400 kcal');
  });

  testWidgets(
      'AI 兜底哨兵路径：onConfirm 传入校准后 actualCalories（beer 86，与预览一致）',
      (tester) async {
    double? capturedCalories;
    double? capturedProtein;
    double? capturedFat;
    double? capturedCarbs;

    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: beerRecognition(),
        singleNutrition: aiFallback(),
        foodItemRepo: foodRepo,
        suggestedServingG: 200,
        onConfirm: (servingG, calories, protein, fat, carbs,
            {componentsSnapshot}) async {
          capturedCalories = calories;
          capturedProtein = protein;
          capturedFat = fat;
          capturedCarbs = carbs;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    expect(capturedCalories, isNotNull);
    // 校准后 actualCalories = 43 * 200 / 100 = 86（不是 400）
    expect(capturedCalories, closeTo(86, 0.5),
        reason: 'onConfirm 应传入校准后 86 kcal，与预览一致');
    // M16.8 Task 1：calibrate 只替换 calories，宏量保留 AI 值（带 clamp）
    // beer AI per100g: protein=2*100/300=0.667, fat=1*100/300=0.333, carbs=15*100/300=5
    // 触发校准（200/43=4.65 > 2）→ calories=43（默认），宏量保留 AI 值
    // actualProtein = 0.667 * 200 / 100 = 1.333
    // actualFat = 0.333 * 200 / 100 = 0.667
    // actualCarbs = 5 * 200 / 100 = 10
    expect(capturedProtein, closeTo(1.333, 0.05));
    expect(capturedFat, closeTo(0.667, 0.05));
    expect(capturedCarbs, closeTo(10, 0.1));
  });

  testWidgets(
      'AI 兜底哨兵路径：预览与 onConfirm 传入值严格一致（同一 CalibratedNutrition 计算）',
      (tester) async {
    // 同一 servingG 下，预览显示的 cal 必须等于 onConfirm 传入的 cal
    double? previewCal;
    double? capturedCalories;

    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: beerRecognition(),
        singleNutrition: aiFallback(),
        foodItemRepo: foodRepo,
        suggestedServingG: 200,
        onConfirm: (servingG, calories, protein, fat, carbs,
            {componentsSnapshot}) async {
          capturedCalories = calories;
        },
      ),
    ));
    await tester.pumpAndSettle();

    // 从预览卡片读取热量值（headlineMedium Text 节点）
    // 卡片结构：Text(cal.toStringAsFixed(0)) 后跟 Text('kcal')
    final kcalText = find.ancestor(
      of: find.text('kcal'),
      matching: find.byType(Row),
    );
    expect(kcalText, findsOneWidget);
    // 在该 Row 内找第一个 Text（就是 cal 数字）
    final calTextWidget = tester.widgetList<Text>(
      find.descendant(of: kcalText, matching: find.byType(Text)),
    ).first;
    previewCal = double.parse(calTextWidget.data!);

    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    expect(capturedCalories, isNotNull);
    // 预览与 onConfirm 必须严格一致（同一 CalibratedNutritionCalculator.compute 结果）
    expect(capturedCalories, closeTo(previewCal, 0.001),
        reason: '预览值与 onConfirm 传入值必须完全一致');
  });

  testWidgets(
      '查库命中路径（foodItemId>0）保持原 ratio 逻辑，不受 AI 兜底校准影响',
      (tester) async {
    // 写入一份 beer 食物库记录，caloriesPer100g=43（已校准）
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '啤酒',
          defaultServingG: 100,
          caloriesPer100g: 43,
          proteinPer100g: 0.5,
          fatPer100g: 0,
          carbsPer100g: 3.1,
          source: 'manual',
          sourceVersion: 'test',
          createdAt: 1000,
        ));
    final food = await (db.select(db.foodItems)
          ..where((t) => t.name.equals('啤酒')))
        .getSingle();

    // 查库命中：foodItemId > 0，calories 对应 mid=300 份量（43 * 300 / 100 = 129）
    final dbHit = NutritionResult(
      foodItemId: food.id,
      calories: 129, // 43 * 300 / 100
      proteinG: 1.5,
      fatG: 0,
      carbsG: 9.3,
      oilG: 0,
      source: NutritionSource.database,
    );

    double? capturedCalories;
    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: beerRecognition(),
        singleNutrition: dbHit,
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

    // 查库命中分支保持原 ratio 逻辑：129 * 200/300 = 86
    // （DB per100g 已是校准值，无需再次校准，原 ratio 换算即正确）
    expect(capturedCalories, closeTo(86, 0.5),
        reason: '查库命中路径走原 ratio 逻辑，43 * 200 / 100 = 86');
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
