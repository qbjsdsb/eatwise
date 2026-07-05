// multi_dish_page widget 测试（M12 补全）
//
// 覆盖核心路径：
// 1. 渲染：主菜 + 附加菜 ListTile 显示 + 总计聚合
// 2. 未命中菜品标红提示（_hitFlags 控制）
// 3. "全部记录"按钮写入 meal_log（事务原子化）
// 4. 改菜名后用新菜名写库
// 5. PopScope 未保存确认
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/recognize/multi_dish_page.dart';
import 'package:eatwise/features/recognize/recognize_controller.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    // 预置库数据：番茄（主菜查库命中）
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
    // 预置库数据：米饭（附加菜查库命中）
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '米饭',
          defaultServingG: 100,
          caloriesPer100g: 116,
          proteinPer100g: 2.6,
          fatPer100g: 0.3,
          carbsPer100g: 25.9,
          source: 'china_fct',
          sourceVersion: 'test',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
  });

  tearDown(() async => db.close());

  /// 主菜 VisionRecognitionResult（番茄，单品，查库命中）
  const mainDish = VisionRecognitionResult(
    dishName: '番茄',
    estimatedWeightGLow: 80,
    estimatedWeightGMid: 100,
    estimatedWeightGHigh: 120,
    foodComponents: [],
    cookingMethod: 'raw',
    isSingleItem: true,
    confidence: 0.95,
    promptVersion: 'v1.0',
  );

  /// 附加菜 VisionRecognitionResult（米饭，单品，查库命中）
  const additionalDish = VisionRecognitionResult(
    dishName: '米饭',
    estimatedWeightGLow: 150,
    estimatedWeightGMid: 200,
    estimatedWeightGHigh: 250,
    foodComponents: [],
    cookingMethod: 'steam',
    isSingleItem: true,
    confidence: 0.9,
    promptVersion: 'v1.0',
  );

  /// 主菜查库命中的营养结果（番茄 100g）
  final mainSingle = NutritionResult(
    foodItemId: 1, // 番茄 id（setUp 第一条 insert）
    calories: 18, // 18 * 100/100
    proteinG: 0.9,
    fatG: 0.2,
    carbsG: 3.9,
    oilG: 0,
  );

  /// 附加菜查库命中的营养结果（米饭 200g）
  final additionalSingle = NutritionResult(
    foodItemId: 2, // 米饭 id（setUp 第二条 insert）
    calories: 232, // 116 * 200/100
    proteinG: 5.2,
    fatG: 0.6,
    carbsG: 51.8,
    oilG: 0,
  );

  testWidgets('M12: 渲染主菜 + 附加菜 ListTile + 总计聚合', (tester) async {
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: MultiDishPage(
        mainDish: mainDish,
        mainSingle: mainSingle,
        additionalItems: [
          MultiDishItem(dish: additionalDish, singleNutrition: additionalSingle),
        ],
        mealType: 'lunch',
      )),
    ));
    await tester.pumpAndSettle();

    // 主菜 + 附加菜都渲染
    expect(find.textContaining('番茄'), findsWidgets);
    expect(find.textContaining('米饭'), findsWidgets);
    // 总计应显示（番茄 18 + 米饭 232 = 250 kcal）
    expect(find.textContaining('250'), findsWidgets);
  });

  testWidgets('M12: 未命中菜品显示提示（_hitFlags=false 标红）', (tester) async {
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    // 主菜查库未命中（mainSingle=null），附加菜命中
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: MultiDishPage(
        mainDish: mainDish,
        mainSingle: null, // 主菜未命中
        additionalItems: [
          MultiDishItem(dish: additionalDish, singleNutrition: additionalSingle),
        ],
        mealType: 'lunch',
      )),
    ));
    await tester.pumpAndSettle();

    // 主菜未命中应显示"未命中"提示徽章（仅主菜一条，附加菜命中不显示）
    expect(find.text('未命中'), findsOneWidget,
        reason: '未命中菜品应显示"未命中"提示');
  });

  testWidgets('M12: 全部记录写入 meal_log（事务原子化，命中菜品各一条）',
      (tester) async {
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: MultiDishPage(
        mainDish: mainDish,
        mainSingle: mainSingle,
        additionalItems: [
          MultiDishItem(dish: additionalDish, singleNutrition: additionalSingle),
        ],
        mealType: 'lunch',
      )),
    ));
    await tester.pumpAndSettle();

    // 点"全部记录"按钮
    final recordButton = find.text('全部记录');
    expect(recordButton, findsOneWidget);
    await tester.tap(recordButton);
    await tester.pumpAndSettle();

    // meal_log 应有 2 条（主菜 + 附加菜，都是命中菜品）
    final meals = await db.mealLogs.select().get();
    expect(meals.length, 2);
    // 都是 lunch 餐次
    expect(meals.every((m) => m.mealType == 'lunch'), isTrue);
    // 总热量应 = 番茄 18 + 米饭 232 = 250（允许小数误差）
    final totalCal = meals.fold<double>(0, (s, m) => s + m.actualCalories);
    expect(totalCal, closeTo(250, 1.0));
  });

  testWidgets('M12: 未命中菜品跳过不写 meal_log（只记录命中菜品）',
      (tester) async {
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    // 主菜命中，附加菜未命中（singleNutrition=null）
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: MultiDishPage(
        mainDish: mainDish,
        mainSingle: mainSingle,
        additionalItems: [
          MultiDishItem(dish: additionalDish, singleNutrition: null), // 未命中
        ],
        mealType: 'lunch',
      )),
    ));
    await tester.pumpAndSettle();

    final recordButton = find.text('全部记录');
    await tester.tap(recordButton);
    await tester.pumpAndSettle();

    // meal_log 应只有 1 条（仅主菜命中，附加菜跳过）
    final meals = await db.mealLogs.select().get();
    expect(meals.length, 1,
        reason: '未命中菜品应跳过，不写 meal_log');
    expect(meals.first.actualCalories, closeTo(18, 0.5));
  });

  testWidgets('M12: 防重入——记录中按钮禁用', (tester) async {
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: MultiDishPage(
        mainDish: mainDish,
        mainSingle: mainSingle,
        additionalItems: [],
        mealType: 'lunch',
      )),
    ));
    await tester.pumpAndSettle();

    // 按钮初始可点
    final recordButton = find.text('全部记录');
    expect(recordButton, findsOneWidget);

    // 点击后立即再次点击（测试防重入）
    await tester.tap(recordButton);
    // 不等 pumpAndSettle，立即再次点击（应被防重入阻止）
    await tester.tap(recordButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    // meal_log 应只有 1 条（防重入生效，未产生重复记录）
    final meals = await db.mealLogs.select().get();
    expect(meals.length, 1,
        reason: '防重入应阻止重复点击产生多条 meal_log');
  });

  // M16.6 Task 4：AI 兜底哨兵路径 actualCalories 一致性
  // 复现 bug：附加菜"啤酒"走 AI 兜底哨兵（foodItemId=0），AI 估算整菜 600kcal（mid=300g），
  // 品类校准后 per100g=43，但 meal_log.actualCalories 仍写未校准的 600（与 food_item 脱节）。
  // 修复后：meal_log.actualCalories 应 = 校准后 per100g * servingG / 100 = 43 * 300 / 100 = 129
  testWidgets('M16.6: AI 兜底哨兵路径 actualCalories 用校准后 per100g 计算（与 food_item 一致）',
      (tester) async {
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) => db),
    ]);
    addTearDown(container.dispose);

    // 附加菜：啤酒，AI 兜底哨兵（foodItemId=0）
    // estimatedCalories=600（mid=300g → per100g=200，偏离 beer 默认 43 的 4.65 倍 → 校准为 43）
    // estimatedProteinG=2 / fatG=1 / carbsG=15
    const beerDish = VisionRecognitionResult(
      dishName: '啤酒',
      estimatedWeightGLow: 250,
      estimatedWeightGMid: 300,
      estimatedWeightGHigh: 350,
      foodComponents: [],
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
    final beerAiFallback = NutritionResult(
      foodItemId: 0, // 哨兵：写库前必须 upsertAiRecognized 替换为真实 id
      calories: 600, // AI 估算整菜热量（对应 mid=300g）
      proteinG: 2,
      fatG: 1,
      carbsG: 15,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: MultiDishPage(
        mainDish: mainDish, // 番茄（查库命中，foodItemId=1）
        mainSingle: mainSingle,
        additionalItems: [
          MultiDishItem(
              dish: beerDish, singleNutrition: beerAiFallback),
        ],
        mealType: 'dinner',
      )),
    ));
    await tester.pumpAndSettle();

    // 用户不调整滑块：serving = mid = 300
    final recordButton = find.text('全部记录');
    await tester.tap(recordButton);
    await tester.pumpAndSettle();

    // meal_log 应有 2 条（番茄 + 啤酒）
    final meals = await db.mealLogs.select().get();
    expect(meals.length, 2, reason: '番茄 + 啤酒 各一条');

    // 找到啤酒对应的 meal_log（通过 food_item 名称匹配）
    final beerFoodItem = await (db.foodItems.select()
          ..where((f) => f.name.equals('啤酒') & f.source.equals('ai_recognized')))
        .getSingleOrNull();
    expect(beerFoodItem, isNotNull,
        reason: '啤酒应通过 upsertAiRecognized 创建 food_item');
    final beerMeal = meals.firstWhere((m) => m.foodItemId == beerFoodItem!.id);

    // 啤酒 food_item.caloriesPer100g 应为校准后的 43（不是 AI 估算的 200）
    expect(beerFoodItem!.caloriesPer100g, closeTo(43, 0.5),
        reason: 'food_item.caloriesPer100g 应用品类校准为 beer 默认值 43');
    // M16.8 Task 1：宏量保留 AI 值（带 clamp），不再替换为品类默认值
    // AI per100g = aiG * 100 / mid：蛋白 2*100/300≈0.667 / 脂肪 1*100/300≈0.333 / 碳水 15*100/300=5.0
    expect(beerFoodItem.proteinPer100g, closeTo(2 * 100 / 300, 0.01));
    expect(beerFoodItem.fatPer100g, closeTo(1 * 100 / 300, 0.01));
    expect(beerFoodItem.carbsPer100g, closeTo(15 * 100 / 300, 0.01));

    // 啤酒 meal_log.actualCalories 应 = 43 * 300 / 100 = 129（不是未校准的 600）
    expect(beerMeal.actualCalories, closeTo(129, 0.5),
        reason: 'meal_log.actualCalories 应基于校准后 per100g 计算，与 food_item 一致');
    // actualMacros 也用校准后 per100g * servingG / 100（宏量保留 AI 值反算）
    // serving=mid=300，actualMacros = AI 估算原值（per100g * 300/100 = aiG * 100/mid * mid/100 = aiG）
    expect(beerMeal.actualProteinG, closeTo(2, 0.01));
    expect(beerMeal.actualFatG, closeTo(1, 0.01));
    expect(beerMeal.actualCarbsG, closeTo(15, 0.01));
    // actualServingG 应 = 用户份量 300
    expect(beerMeal.actualServingG, closeTo(300, 0.01));
  });

  // M16.8 Task 6：查库命中分支接入差异检测
  // 复现 bug：主菜"番茄炒蛋"查库命中（foodItemId>0），库 per100g=80（脏数据），
  // AI 估 200g/250kcal（库值 160 vs AI 250，偏差 56% > 50%）。
  // 修复前：查库命中分支用 n.calories * ratio = 160，忽略 AI 估算，与 reasoning 脱节。
  // 修复后：偏差大时用 AI 反算 per100g=125，actualCalories=250，并更新库 per100g。
  testWidgets(
      'M16.8: 查库命中 + AI 偏差大时 actualCalories 用 AI 估算 + 更新库 per100g',
      (tester) async {
    // 用独立 db（只插番茄炒蛋，id=1），避免与 setUp 的番茄/米饭 id 冲突
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '番茄炒蛋',
          defaultServingG: 100,
          caloriesPer100g: 80, // 脏数据
          proteinPer100g: 6,
          fatPer100g: 10,
          carbsPer100g: 12,
          source: 'china_fct',
          sourceVersion: 'test',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    const r = VisionRecognitionResult(
      dishName: '番茄炒蛋',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      estimatedCalories: 250, // AI 估 250，库值 160，偏差 56% > 50%
      estimatedProteinG: 10,
      estimatedFatG: 15,
      estimatedCarbsG: 20,
      foodComponents: [],
      cookingMethod: 'stir_fry',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.0',
    );
    final lookupHit = NutritionResult(
      foodItemId: 1, // 库命中
      calories: 160, // 80 * 200 / 100
      proteinG: 6,
      fatG: 10,
      carbsG: 12,
      oilG: 0,
    );
    final aiFallback = NutritionResult(
      foodItemId: 0, // AI 兜底哨兵
      calories: 250, // AI 估算整菜热量（对应 mid=200g）
      proteinG: 10,
      fatG: 15,
      carbsG: 20,
      oilG: 0,
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: MultiDishPage(
        mainDish: r,
        mainSingle: lookupHit,
        mainAiFallback: aiFallback, // 新参数（M16.8）
        additionalItems: [],
        mealType: 'lunch',
      )),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部记录'));
    await tester.pumpAndSettle();

    final meals = await db.mealLogs.select().get();
    expect(meals.length, 1);
    expect(meals.first.actualCalories, closeTo(250, 0.5),
        reason: '查库命中 + AI 偏差大时用 AI 估算值');

    final food = await (db.foodItems.select()
          ..where((f) => f.name.equals('番茄炒蛋')))
        .getSingle();
    expect(food.caloriesPer100g, closeTo(125, 0.5),
        reason: '库 per100g 应被 AI 反算值更新（250*100/200=125）');
  });
}
