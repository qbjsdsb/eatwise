// v2 改动 E：UI warnings 显示 + 手动编辑营养值测试
//
// 用户指令「兜底也用AI，进行严谨的验证，但是最后用户可以手动修改」：
// 1. warnings 非空时在校准页显示警告横幅（物理约束提示，不修改值）
// 2. 用户点击营养数值 → 弹出编辑对话框 → 输入新值 → 预览/记录用新值
// 3. 用户编辑后 _dirty=true（PopScope 未保存确认）
//
// 手动编辑是用户作为最终兜底，覆盖 AI 估算值。
// 单品 + 复合菜路径都生效，与 _buildNutritionPreview / _confirmWithServing 共用。
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

  // 单品查库命中场景的公共数据
  VisionRecognitionResult buildResult({List<String> warnings = const []}) {
    return VisionRecognitionResult(
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
      warnings: warnings,
    );
  }

  NutritionResult buildLookupHit(int foodItemId) => NutritionResult(
        foodItemId: foodItemId,
        calories: 18,
        proteinG: 0.9,
        fatG: 0.2,
        carbsG: 3.9,
        oilG: 0,
        source: NutritionSource.database,
      );

  NutritionResult buildAiFallback() => NutritionResult(
        foodItemId: 0,
        calories: 18,
        proteinG: 0.9,
        fatG: 0.2,
        carbsG: 3.9,
        oilG: 0,
        source: NutritionSource.aiEstimate,
      );

  testWidgets('warnings 非空时显示警告横幅', (tester) async {
    final food = await (db.select(db.foodItems)
          ..where((t) => t.name.equals('番茄')))
        .getSingle();
    final r = buildResult(warnings: const [
      '⚠ 宏量与热量不自洽：AI 估算 400kcal，宏量加成 290kcal（偏差 27%），请核对',
      '⚠ 密度异常高（5000kcal/100g），请核对',
    ]);
    final lookupHit = buildLookupHit(food.id);

    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: r,
        singleNutrition: lookupHit,
        foodItemRepo: foodRepo,
        onConfirm: (servingG, calories, protein, fat, carbs,
            {componentsSnapshot}) async {},
      ),
    ));
    await tester.pumpAndSettle();

    // 两条 warning 文案都应显示
    expect(
        find.textContaining('宏量与热量不自洽'), findsOneWidget,
        reason: 'warnings 非空时第一条警告应显示');
    expect(
        find.textContaining('密度异常高'), findsOneWidget,
        reason: 'warnings 非空时第二条警告应显示');
  });

  testWidgets('warnings 为空时不显示警告横幅', (tester) async {
    final food = await (db.select(db.foodItems)
          ..where((t) => t.name.equals('番茄')))
        .getSingle();
    final r = buildResult(); // warnings = []
    final lookupHit = buildLookupHit(food.id);

    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: r,
        singleNutrition: lookupHit,
        foodItemRepo: foodRepo,
        onConfirm: (servingG, calories, protein, fat, carbs,
            {componentsSnapshot}) async {},
      ),
    ));
    await tester.pumpAndSettle();

    // 没有 warning 文案
    expect(find.textContaining('宏量与热量不自洽'), findsNothing);
    expect(find.textContaining('密度异常高'), findsNothing);
  });

  // 单品路径手动编辑：用户点击 cal 数值 → 弹对话框 → 输入新值 → 预览/记录用新值
  testWidgets('手动编辑 cal：用户输入 600 → 预览显示 600 + onConfirm 传 600',
      (tester) async {
    final food = await (db.select(db.foodItems)
          ..where((t) => t.name.equals('番茄')))
        .getSingle();
    final r = buildResult();
    final lookupHit = buildLookupHit(food.id);
    final aiFallback = buildAiFallback();

    double? capturedCalories;
    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: r,
        singleNutrition: lookupHit,
        aiFallbackNutrition: aiFallback,
        foodItemRepo: foodRepo,
        onConfirm: (servingG, calories, protein, fat, carbs,
            {componentsSnapshot}) async {
          capturedCalories = calories;
        },
      ),
    ));
    await tester.pumpAndSettle();

    // 默认预览显示 AI 值（mid=100, cal=18, servingG 默认=mid=100 → actualCalories=18）
    // 用 Key 定位 cal 数值文本（_nutritionCard 的 cal Text 带 ValueKey('cal_value')）
    final calValue = find.byKey(const ValueKey('cal_value'));
    expect(calValue, findsOneWidget, reason: 'cal 数值应有 ValueKey 标识');
    expect(
        (calValue.evaluate().single.widget as Text).data, '18',
        reason: '默认预览应显示 AI 值 18');

    // 点击 cal 数值 → 弹出编辑对话框
    await tester.tap(calValue);
    await tester.pumpAndSettle();

    // 对话框应出现（标题含"手动修改营养值"）
    expect(find.textContaining('手动修改营养值'), findsOneWidget,
        reason: '点击 cal 数值应弹出编辑对话框');

    // 输入新 cal 值 600（清空原值后输入）
    final calField = find.byKey(const ValueKey('edit_cal_field'));
    expect(calField, findsOneWidget, reason: '对话框应有 cal 输入框');
    await tester.enterText(calField, '600');
    await tester.pumpAndSettle();

    // 点确认
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    // 对话框关闭，预览应显示 600（用户输入值，覆盖 AI 的 18）
    final calValueAfter = find.byKey(const ValueKey('cal_value'));
    expect((calValueAfter.evaluate().single.widget as Text).data, '600',
        reason: '用户编辑后预览应显示用户输入值 600');

    // 点确认记录
    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    // onConfirm 应传用户输入值 600（用户最终兜底覆盖 AI 值）
    expect(capturedCalories, isNotNull);
    expect(capturedCalories, closeTo(600, 0.5),
        reason: 'onConfirm 应传用户手动编辑值 600，覆盖 AI 估算');
  });

  // 用户编辑后再次点击可重新编辑（_userOverrides 被新值替换）
  testWidgets('手动编辑可重复：用户编辑 cal 600 → 再编辑为 800', (tester) async {
    final food = await (db.select(db.foodItems)
          ..where((t) => t.name.equals('番茄')))
        .getSingle();
    final r = buildResult();
    final lookupHit = buildLookupHit(food.id);
    final aiFallback = buildAiFallback();

    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: r,
        singleNutrition: lookupHit,
        aiFallbackNutrition: aiFallback,
        foodItemRepo: foodRepo,
        onConfirm: (servingG, calories, protein, fat, carbs,
            {componentsSnapshot}) async {},
      ),
    ));
    await tester.pumpAndSettle();

    // 第一次编辑：输入 600
    await tester.tap(find.byKey(const ValueKey('cal_value')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('edit_cal_field')), '600');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(
        (find.byKey(const ValueKey('cal_value')).evaluate().single.widget
                as Text)
            .data,
        '600');

    // 第二次编辑：输入 800
    await tester.tap(find.byKey(const ValueKey('cal_value')));
    await tester.pumpAndSettle();
    // 对话框再次出现，输入框应预填上次的 600
    expect(
        find.byKey(const ValueKey('edit_cal_field')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('edit_cal_field')), '800');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(
        (find.byKey(const ValueKey('cal_value')).evaluate().single.widget
                as Text)
            .data,
        '800',
        reason: '重复编辑应替换为新值 800');
  });

  // 用户取消编辑（点取消/空白处）→ 预览保持原值
  testWidgets('用户取消编辑：预览保持原值', (tester) async {
    final food = await (db.select(db.foodItems)
          ..where((t) => t.name.equals('番茄')))
        .getSingle();
    final r = buildResult();
    final lookupHit = buildLookupHit(food.id);
    final aiFallback = buildAiFallback();

    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: r,
        singleNutrition: lookupHit,
        aiFallbackNutrition: aiFallback,
        foodItemRepo: foodRepo,
        onConfirm: (servingG, calories, protein, fat, carbs,
            {componentsSnapshot}) async {},
      ),
    ));
    await tester.pumpAndSettle();

    // 默认 18
    expect(
        (find.byKey(const ValueKey('cal_value')).evaluate().single.widget
                as Text)
            .data,
        '18');

    // 点 cal → 输入 600 → 点取消
    await tester.tap(find.byKey(const ValueKey('cal_value')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('edit_cal_field')), '600');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 预览应保持 18（取消不应用编辑）
    expect(
        (find.byKey(const ValueKey('cal_value')).evaluate().single.widget
                as Text)
            .data,
        '18',
        reason: '取消编辑后预览应保持原值 18');
  });

  // 复合菜路径手动编辑也生效（用户兜底覆盖所有路径）
  testWidgets('复合菜路径手动编辑 cal：用户输入 800 覆盖 AI 值', (tester) async {
    const r = VisionRecognitionResult(
      dishName: '宫保鸡丁',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      estimatedCalories: 250,
      estimatedProteinG: 10,
      estimatedFatG: 15,
      estimatedCarbsG: 20,
      foodComponents: [],
      cookingMethod: 'stir_fry',
      isSingleItem: false,
      confidence: 0.9,
      promptVersion: 'v1.10',
      foodCategory: 'solid',
    );
    final composite = CompositeNutritionResult(
      calories: 160,
      proteinG: 10,
      fatG: 8,
      carbsG: 5,
      oilG: 0,
      componentHits: [
        ComponentHit(
          name: '鸡肉',
          foodItemId: 1,
          estimatedG: 200,
          caloriesPer100g: 80,
          proteinPer100g: 10,
          fatPer100g: 8,
          carbsPer100g: 5,
        ),
      ],
      componentMisses: [],
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

    double? capturedCalories;
    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: r,
        compositeNutrition: composite,
        aiFallbackNutrition: aiFallback,
        foodItemRepo: foodRepo,
        onConfirm: (servingG, calories, protein, fat, carbs,
            {componentsSnapshot}) async {
          capturedCalories = calories;
        },
      ),
    ));
    await tester.pumpAndSettle();

    // 默认预览显示 AI 值 250（v2 改动 D 复合菜 AI 优先）
    expect(
        (find.byKey(const ValueKey('cal_value')).evaluate().single.widget
                as Text)
            .data,
        '250');

    // 用户手动编辑为 800
    await tester.tap(find.byKey(const ValueKey('cal_value')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('edit_cal_field')), '800');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    // 预览显示 800
    expect(
        (find.byKey(const ValueKey('cal_value')).evaluate().single.widget
                as Text)
            .data,
        '800');

    // 点确认记录
    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    expect(capturedCalories, isNotNull);
    expect(capturedCalories, closeTo(800, 0.5),
        reason: '复合菜路径手动编辑也应生效，onConfirm 传用户值 800');
  });
}
