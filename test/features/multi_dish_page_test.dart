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
  // 历史场景曾用啤酒（雪花啤酒被识别成雪碧的 workaround），方案 D（M25）废弃品类校准后
  // 啤酒补丁已无意义。AI 兜底哨兵路径的 actualCalories 一致性由 recognize_page_test.dart
  // 与 calibrated_nutrition_calculator_test.dart 的 solid/soup 场景覆盖。

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

  // M16.9：复合菜分支接入 AI 绝对优先
  // 复合菜 lookupCompositeDish 返回组分累加库值（鸡肉 150g×150kcal/100 + 油 10g×889/100 ≈ 225+89=314）
  // AI 整菜估算 estimatedCalories=500（per100g=250，有效区间 [0,900] 内，偏差 59%）
  // M16.8：用组分累加库值（314），AI 整菜估算被丢弃
  // M16.9：AI 绝对优先，用 AI 整菜估算记 meal_log（500），复合菜 per100g=0 占位不更新库
  testWidgets(
      'M16.9: 复合菜查库命中 + AI 整菜估算有效时用 AI 值记录（AI 绝对优先）',
      (tester) async {
    // 独立 db：只预置鸡肉（复合菜组分），避免与 setUp 番茄/米饭 id 冲突
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '鸡肉',
          defaultServingG: 100,
          caloriesPer100g: 150,
          proteinPer100g: 20,
          fatPer100g: 8,
          carbsPer100g: 0,
          source: 'china_fct',
          sourceVersion: 'test',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) => db),
    ]);
    addTearDown(container.dispose);

    // 主菜：宫保鸡丁（复合菜，组分鸡肉 150g + 用油 10g）
    // estimatedWeightGMid=200g, AI 整菜估算 500kcal（per100g=250，有效）
    const r = VisionRecognitionResult(
      dishName: '宫保鸡丁',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      estimatedCalories: 500, // AI 整菜估算（对应 mid=200g）
      estimatedProteinG: 35,
      estimatedFatG: 20,
      estimatedCarbsG: 5,
      foodComponents: [],
      cookingMethod: 'stir_fry',
      isSingleItem: false, // 复合菜
      confidence: 0.9,
      promptVersion: 'v1.10',
      foodCategory: 'solid',
    );
    // 复合菜查库结果：组分累加库值
    // 鸡肉 150g × 150kcal/100 = 225 kcal；油 10g × 889/100 ≈ 89 kcal → 整菜 314 kcal
    // （简化：oilG 单独存于 CompositeNutritionResult.oilG，不进 componentHits）
    final composite = CompositeNutritionResult(
      calories: 225, // 鸡肉组分累加（不含油）
      proteinG: 30, // 20 * 150 / 100
      fatG: 12, // 8 * 150 / 100
      carbsG: 0,
      oilG: 10, // 用油 10g（_calcNutrition 会加 889*10/100≈89 kcal）
      componentHits: [
        ComponentHit(
          name: '鸡肉',
          foodItemId: 1,
          estimatedG: 150,
          caloriesPer100g: 150,
          proteinPer100g: 20,
          fatPer100g: 8,
          carbsPer100g: 0,
        ),
      ],
      componentMisses: [],
    );
    final aiFallback = NutritionResult(
      foodItemId: 0, // AI 兜底哨兵（复合菜 _recordAll 仍走 upsertAiRecognized）
      calories: 500, // AI 整菜估算（对应 mid=200g）
      proteinG: 35,
      fatG: 20,
      carbsG: 5,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: MultiDishPage(
        mainDish: r,
        mainSingle: null, // 复合菜：单品 null
        mainComposite: composite,
        mainAiFallback: aiFallback,
        additionalItems: [],
        mealType: 'lunch',
      )),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部记录'));
    await tester.pumpAndSettle();

    final meals = await db.mealLogs.select().get();
    expect(meals.length, 1, reason: '复合菜应写入 1 条 meal_log');

    // 核心断言：meal_log.actualCalories 用 AI 整菜估算（500），不用组分累加库值（225+89=314）
    expect(meals.first.actualCalories, closeTo(500, 0.5),
        reason: 'M16.9 复合菜 AI 绝对优先：用 AI 整菜估算（500），'
            '不用组分累加库值（~314）');

    // 宏量也用 AI 值（按 serving/mid=1 比例缩放，serving=mid=200）
    expect(meals.first.actualProteinG, closeTo(35, 0.5),
        reason: 'actualProteinG 用 AI 估算值');
    expect(meals.first.actualFatG, closeTo(20, 0.5),
        reason: 'actualFatG 用 AI 估算值');
    expect(meals.first.actualCarbsG, closeTo(5, 0.5),
        reason: 'actualCarbsG 用 AI 估算值');

    // M18：复合菜 food_item 通过 upsertAiRecognized 创建，per100g 用 AI 反算值
    // （M16.9 时为 0 占位；M18 改为 AI 反算值让 AI 估算进入食物库供未来查库复用）
    // AI 估算：calories=500, protein=35, fat=20, carbs=5，mid=200
    // per100g = AI 估算 * 100 / mid
    final food = await (db.foodItems.select()
          ..where((f) => f.name.equals('宫保鸡丁') & f.source.equals('ai_recognized')))
        .getSingle();
    expect(food.caloriesPer100g, closeTo(250, 0.5),
        reason: 'M18: 复合菜 per100g 用 AI 反算值（500 * 100 / 200 = 250），'
            '不再 0 占位');
    expect(food.proteinPer100g, closeTo(17.5, 0.5),
        reason: 'M18: proteinPer100g = 35 * 100 / 200 = 17.5');
    expect(food.fatPer100g, closeTo(10, 0.5),
        reason: 'M18: fatPer100g = 20 * 100 / 200 = 10');
    expect(food.carbsPer100g, closeTo(2.5, 0.5),
        reason: 'M18: carbsPer100g = 5 * 100 / 200 = 2.5');
  });

  // v2 重构：复合菜 AI 整菜估算离谱（per100g > 900）时仍用 AI 值记录
  // 旧逻辑（M16.9）：AI 离谱返回 null，调用方走组分累加库值兜底
  // 新逻辑（v2）：删除 aiValid 检查，始终用 AI 反算值，warnings 提示用户手动纠正
  testWidgets(
      'v2: 复合菜 AI 整菜估算离谱（per100g>900）时仍用 AI 值记录',
      (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '鸡肉',
          defaultServingG: 100,
          caloriesPer100g: 150,
          proteinPer100g: 20,
          fatPer100g: 8,
          carbsPer100g: 0,
          source: 'china_fct',
          sourceVersion: 'test',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) => db),
    ]);
    addTearDown(container.dispose);

    // AI 估 2000kcal（mid=200g → per100g=1000 > 900 离谱）
    const r = VisionRecognitionResult(
      dishName: '宫保鸡丁',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      estimatedCalories: 2000, // AI 离谱值
      estimatedProteinG: 100,
      estimatedFatG: 80,
      estimatedCarbsG: 50,
      foodComponents: [],
      cookingMethod: 'stir_fry',
      isSingleItem: false,
      confidence: 0.9,
      promptVersion: 'v1.10',
      foodCategory: 'solid',
    );
    final composite = CompositeNutritionResult(
      calories: 225, // 鸡肉组分累加
      proteinG: 30,
      fatG: 12,
      carbsG: 0,
      oilG: 10,
      componentHits: [
        ComponentHit(
          name: '鸡肉',
          foodItemId: 1,
          estimatedG: 150,
          caloriesPer100g: 150,
          proteinPer100g: 20,
          fatPer100g: 8,
          carbsPer100g: 0,
        ),
      ],
      componentMisses: [],
    );
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 2000, // AI 离谱
      proteinG: 100,
      fatG: 80,
      carbsG: 50,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: MultiDishPage(
        mainDish: r,
        mainSingle: null,
        mainComposite: composite,
        mainAiFallback: aiFallback,
        additionalItems: [],
        mealType: 'lunch',
      )),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部记录'));
    await tester.pumpAndSettle();

    final meals = await db.mealLogs.select().get();
    expect(meals.length, 1);

    // v2 新逻辑：AI 离谱时仍用 AI 值记录（2000），不再用组分累加库值兜底
    // per100g = 2000 * 100 / 200 = 1000，actualCalories = 1000 * 200 / 100 = 2000
    // AI 离谱值通过 validator warnings 提示用户手动纠正
    expect(meals.first.actualCalories, closeTo(2000, 0.5),
        reason: 'v2 AI 离谱时仍用 AI 值 2000 记录，不用组分累加库值 225 兜底');
  });

  // ============================================================
  // M24 B4: 包装 OCR 优先路径 characterization test（拆分前安全网）
  // 验证 multi_dish_page 哨兵分支（foodItemId=0）+ 有包装营养表数据时，
  // meal_log.actualCalories 用包装换算值（per100g × serving / 100），
  // food_item.caloriesPer100g 用包装换算值，不走 AI 估算/品类校准。
  // 硬约束 4：per100g 反算基于 estimatedWeightGMid（包装路径用 packageServingG 换算）
  // ============================================================
  testWidgets(
      'M24 B4: 包装 OCR 优先路径——哨兵 + 包装数据时用包装换算值记录（不是 AI 估算）',
      (tester) async {
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    // 速冻水饺：包装营养表（单份 50g / 100kcal / 蛋白3g / 脂肪2g / 碳水15g）
    // estimatedWeightGMid=200g（用户份量），AI 估算 500kcal（应被包装路径短路）
    const r = VisionRecognitionResult(
      dishName: '速冻水饺',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      foodComponents: [],
      cookingMethod: 'steam',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.10',
      estimatedCalories: 500, // AI 估算（应被包装路径短路）
      estimatedProteinG: 10,
      estimatedFatG: 5,
      estimatedCarbsG: 50,
      foodCategory: 'solid',
      packageServingG: 50, // 单份 50g
      packageServingKcal: 100, // 单份 100kcal
      packageServingProteinG: 3,
      packageServingFatG: 2,
      packageServingCarbsG: 15,
    );
    final aiFallback = NutritionResult(
      foodItemId: 0, // 哨兵：写库前必须 upsertAiRecognized 替换为真实 id
      calories: 500, // AI 估算整菜（mid=200g）
      proteinG: 10,
      fatG: 5,
      carbsG: 50,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: MultiDishPage(
        mainDish: r,
        // 哨兵路径：mainSingle 非空 + foodItemId=0 触发 _hitFlags=true + 哨兵分支
        // （与 M16.6 beerDish 用 singleNutrition=beerAiFallback 同模式）
        mainSingle: aiFallback,
        additionalItems: const [],
        mealType: 'dinner',
      )),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部记录'));
    await tester.pumpAndSettle();

    final meals = await db.mealLogs.select().get();
    expect(meals.length, 1, reason: '速冻水饺应写入 1 条 meal_log');

    // 包装换算：per100g kcal = 100 * 100 / 50 = 200
    // actualCalories = 200 * 200 / 100 = 400（不是 AI 估算的 500）
    expect(meals.first.actualCalories, closeTo(400, 0.5),
        reason: '包装 OCR 优先：actualCalories 用包装换算值（400），不是 AI 估算（500）');
    // 包装换算宏量：per100g = 单份值 * 100 / 50
    // actualProteinG = 6 * 200 / 100 = 12
    expect(meals.first.actualProteinG, closeTo(12, 0.1),
        reason: '包装换算蛋白 = 3*100/50 * 200/100 = 12');
    expect(meals.first.actualFatG, closeTo(8, 0.1),
        reason: '包装换算脂肪 = 2*100/50 * 200/100 = 8');
    expect(meals.first.actualCarbsG, closeTo(60, 0.1),
        reason: '包装换算碳水 = 15*100/50 * 200/100 = 60');

    // food_item.caloriesPer100g 应为包装换算值 200（不是 AI 反算的 250）
    final food = await (db.foodItems.select()
          ..where((f) => f.name.equals('速冻水饺') & f.source.equals('ai_recognized')))
        .getSingle();
    expect(food.caloriesPer100g, closeTo(200, 0.5),
        reason: 'food_item.caloriesPer100g 用包装换算值 200');
    expect(food.proteinPer100g, closeTo(6, 0.1),
        reason: 'food_item.proteinPer100g = 3*100/50 = 6');
    expect(food.fatPer100g, closeTo(4, 0.1),
        reason: 'food_item.fatPer100g = 2*100/50 = 4');
    expect(food.carbsPer100g, closeTo(30, 0.1),
        reason: 'food_item.carbsPer100g = 15*100/50 = 30');
  });

  // ============================================================
  // M18 Task 2: AI 估算卡片 UI 测试（5 个）
  // 验证 multi_dish_page 新增 _buildAiEstimateCard 渲染：
  // - 置信度百分比（<60% 红色警告）
  // - 来源徽章（AI 优先 / 库匹配 / AI 估算）
  // - AI vs 库值对比行（仅查库命中时显示）
  // - reasoning 折叠面板（reasoning 非空时显示）
  // ============================================================

  /// M18 Task 2 helper：构建主菜查库命中 + AI 估算有效的 MultiDishPage
  /// 用于复用渲染逻辑，避免每个测试都重复 pumpWidget 样板
  Future<void> pumpAiEstimateCardPage(
    WidgetTester tester, {
    required VisionRecognitionResult mainDish,
    required NutritionResult mainSingle,
    required NutritionResult mainAiFallback,
  }) async {
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: MultiDishPage(
          mainDish: mainDish,
          mainSingle: mainSingle,
          mainAiFallback: mainAiFallback,
          additionalItems: const [],
          mealType: 'lunch',
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'M18 Task2: AI 估算卡片显示置信度百分比（confidence=0.92 → "92%"）',
      (tester) async {
    const r = VisionRecognitionResult(
      dishName: '番茄',
      estimatedWeightGLow: 80,
      estimatedWeightGMid: 100,
      estimatedWeightGHigh: 120,
      foodComponents: [],
      cookingMethod: 'raw',
      isSingleItem: true,
      confidence: 0.92, // 高置信度
      promptVersion: 'v1.10',
      estimatedCalories: 18,
      estimatedProteinG: 0.9,
      estimatedFatG: 0.2,
      estimatedCarbsG: 3.9,
    );
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 18,
      proteinG: 0.9,
      fatG: 0.2,
      carbsG: 3.9,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );

    await pumpAiEstimateCardPage(
      tester,
      mainDish: r,
      mainSingle: mainSingle,
      mainAiFallback: aiFallback,
    );

    // M18：AI 估算卡片应显示置信度 92%
    expect(find.textContaining('92%'), findsWidgets,
        reason: 'M18: AI 估算卡片显示置信度 92%');
  });

  testWidgets(
      'M18 Task2: 低置信度（confidence=0.45）时显示红色警告文本（"待确认"）',
      (tester) async {
    const r = VisionRecognitionResult(
      dishName: '番茄',
      estimatedWeightGLow: 80,
      estimatedWeightGMid: 100,
      estimatedWeightGHigh: 120,
      foodComponents: [],
      cookingMethod: 'raw',
      isSingleItem: true,
      confidence: 0.45, // 低置信度 < 60%
      promptVersion: 'v1.10',
      estimatedCalories: 18,
      estimatedProteinG: 0.9,
      estimatedFatG: 0.2,
      estimatedCarbsG: 3.9,
    );
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 18,
      proteinG: 0.9,
      fatG: 0.2,
      carbsG: 3.9,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );

    await pumpAiEstimateCardPage(
      tester,
      mainDish: r,
      mainSingle: mainSingle,
      mainAiFallback: aiFallback,
    );

    // M18：低置信度应显示警告文本（待确认 或 红色样式）
    expect(find.textContaining('待确认'), findsOneWidget,
        reason: 'M18: confidence < 0.6 时显示"待确认"警告');
  });

  testWidgets(
      'M18 Task2: 查库命中 + AI 优先时显示"AI 优先"徽章',
      (tester) async {
    // 主菜查库命中（mainSingle.foodItemId > 0）+ AI 有效
    // 库 per100g = 18（番茄），AI per100g = 20（500/100=20... 用 estimatedCalories=20）
    // diffRatio > 0 → shouldUpdateFoodItem=true → "AI 优先"徽章
    const r = VisionRecognitionResult(
      dishName: '番茄',
      estimatedWeightGLow: 80,
      estimatedWeightGMid: 100,
      estimatedWeightGHigh: 120,
      foodComponents: [],
      cookingMethod: 'raw',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.10',
      estimatedCalories: 20, // AI 估算 per100g=20（与库 18 偏差 11%）
      estimatedProteinG: 0.9,
      estimatedFatG: 0.2,
      estimatedCarbsG: 3.9,
    );
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 20,
      proteinG: 0.9,
      fatG: 0.2,
      carbsG: 3.9,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );

    await pumpAiEstimateCardPage(
      tester,
      mainDish: r,
      mainSingle: mainSingle,
      mainAiFallback: aiFallback,
    );

    // M18：查库命中 + AI 优先时应显示"AI 优先"徽章
    expect(find.text('AI 优先'), findsOneWidget,
        reason: 'M18: 查库命中 + AI 有效时显示"AI 优先"徽章');
  });

  testWidgets(
      'M18 Task2: 查库命中时显示 AI vs 库值对比行（含 "AI:" "库:" "偏差"）',
      (tester) async {
    // 主菜查库命中 + AI 有效，对比行应显示
    const r = VisionRecognitionResult(
      dishName: '番茄',
      estimatedWeightGLow: 80,
      estimatedWeightGMid: 100,
      estimatedWeightGHigh: 120,
      foodComponents: [],
      cookingMethod: 'raw',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.10',
      estimatedCalories: 20, // AI per100g=20
      estimatedProteinG: 0.9,
      estimatedFatG: 0.2,
      estimatedCarbsG: 3.9,
    );
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 20,
      proteinG: 0.9,
      fatG: 0.2,
      carbsG: 3.9,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );

    await pumpAiEstimateCardPage(
      tester,
      mainDish: r,
      mainSingle: mainSingle,
      mainAiFallback: aiFallback,
    );

    // M18：查库命中时显示 AI vs 库值对比行
    // mid=100，aiPer100 = 20*100/100 = 20，dbPer100 = 18*100/100 = 18
    expect(find.textContaining('AI:'), findsOneWidget,
        reason: 'M18: 对比行包含 "AI:"');
    expect(find.textContaining('库:'), findsOneWidget,
        reason: 'M18: 对比行包含 "库:"');
    expect(find.textContaining('偏差'), findsOneWidget,
        reason: 'M18: 对比行包含 "偏差"');
  });

  testWidgets(
      'M18 Task2: reasoning 非空时显示 AI 推理过程折叠面板',
      (tester) async {
    const r = VisionRecognitionResult(
      dishName: '番茄',
      estimatedWeightGLow: 80,
      estimatedWeightGMid: 100,
      estimatedWeightGHigh: 120,
      foodComponents: [],
      cookingMethod: 'raw',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.10',
      estimatedCalories: 18,
      estimatedProteinG: 0.9,
      estimatedFatG: 0.2,
      estimatedCarbsG: 3.9,
      reasoning: '识别为番茄，红色圆形，重量约 100g，含水量高，热量较低。',
    );
    final aiFallback = NutritionResult(
      foodItemId: 0,
      calories: 18,
      proteinG: 0.9,
      fatG: 0.2,
      carbsG: 3.9,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );

    await pumpAiEstimateCardPage(
      tester,
      mainDish: r,
      mainSingle: mainSingle,
      mainAiFallback: aiFallback,
    );

    // M18：reasoning 非空时显示 AI 推理过程折叠面板
    expect(find.text('AI 推理过程'), findsOneWidget,
        reason: 'M18: reasoning 非空时显示折叠面板标题');
  });
}
