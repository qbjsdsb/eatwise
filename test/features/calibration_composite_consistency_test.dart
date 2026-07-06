import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/features/recognize/calibration_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// P1 修复 1 测试：复合菜预览 / 记录 / 编辑对话框初始值三处统一走 AI 优先路径。
///
/// 场景：包装有数据但宏量全 0（packageMacrosAllZero=true）+ aiFallback 非空 + 组分命中。
/// 期望：_buildNutritionPreview / _confirmWithServing / _currentDisplayedValues 三处
///      都走 AI 优先路径（cal = calibrated.actualCalories + oilCaloriesPer100g*_oilG/100），
///      而非组分累加 fallback。
void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    foodRepo = FoodItemRepository(db);
    // 种子：鸡肉 + 花生（组分命中）
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '鸡肉',
          defaultServingG: 100,
          caloriesPer100g: 167,
          proteinPer100g: 19,
          fatPer100g: 9,
          carbsPer100g: 0,
          source: 'manual',
          sourceVersion: 'test',
          createdAt: 1000,
        ));
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '花生',
          defaultServingG: 100,
          caloriesPer100g: 567,
          proteinPer100g: 25,
          fatPer100g: 49,
          carbsPer100g: 16,
          source: 'manual',
          sourceVersion: 'test',
          createdAt: 1001,
        ));
  });
  tearDown(() async => db.close());

  // 包装有数据（hasPackageNutrition=true）但宏量全 0（packageMacrosAllZero=true）
  // → 跳过包装优先路径，落到 AI 优先路径（aiFallbackNutrition 非空）
  VisionRecognitionResult buildRecognition() => VisionRecognitionResult(
        dishName: '宫保鸡丁',
        estimatedWeightGLow: 200,
        estimatedWeightGMid: 250,
        estimatedWeightGHigh: 300,
        foodComponents: const [
          FoodComponent(name: '鸡肉', estimatedG: 150),
          FoodComponent(name: '花生', estimatedG: 30),
        ],
        cookingMethod: 'stir-fry',
        isSingleItem: false,
        confidence: 0.75,
        promptVersion: 'v1.0',
        packageServingG: 100,
        packageServingKcal: 200,
        packageServingProteinG: 0,
        packageServingFatG: 0,
        packageServingCarbsG: 0,
      );

  const aiFallback = NutritionResult(
    foodItemId: 0,
    calories: 300,
    proteinG: 20,
    fatG: 10,
    carbsG: 30,
    oilG: 0,
    source: NutritionSource.aiEstimate,
  );

  // AI 优先路径期望值（totalG=150+30=180, mid=250, oil=stir-fry 默认 12g）：
  //   actualCalories = 300 * 180/250 = 216；+ 889*12/100 = 106.68 → 322.68
  //   actualProtein  = 20  * 180/250 = 14.4
  //   actualFat      = 10  * 180/250 = 7.2；+ 99.9*12/100 = 11.988 → 19.188
  //   actualCarbs    = 30  * 180/250 = 21.6
  // 组分累加 fallback 期望值（不应出现）：
  //   鸡肉 250.5 + 花生 170.1 + 油 106.68 = 527.28 cal
  const expectedCal = 322.68;
  const expectedProtein = 14.4;
  const expectedFat = 19.188;
  const expectedCarbs = 21.6;
  const fallbackCal = 527.28;

  double readDisplayed(WidgetTester tester, Key key) {
    final w = tester.widget<Text>(find.byKey(key));
    // 热量文本为 "323"，宏量列文本为 "14 g"（带单位后缀），取首段数字解析
    return double.parse(w.data!.split(' ').first);
  }

  testWidgets('预览显示 AI 优先值（非组分累加 fallback）+ onConfirm 一致', (tester) async {
    final recognition = buildRecognition();
    final lookup = NutritionLookup(foodRepo);
    final composite = await lookup.lookupCompositeDish(
      components: recognition.foodComponents,
      cookingMethod: recognition.cookingMethod,
    );

    double? capturedCal, capturedProtein, capturedFat, capturedCarbs;
    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: recognition,
        compositeNutrition: composite,
        foodItemRepo: foodRepo,
        aiFallbackNutrition: aiFallback,
        onConfirm: (servingG, cal, protein, fat, carbs,
            {componentsSnapshot}) async {
          capturedCal = cal;
          capturedProtein = protein;
          capturedFat = fat;
          capturedCarbs = carbs;
        },
      ),
    ));
    await tester.pumpAndSettle();

    // 预览值 = AI 优先路径（含油累加），toStringAsFixed(0) → "323"
    final previewCal = readDisplayed(tester, const ValueKey('cal_value'));
    expect(previewCal, closeTo(expectedCal, 1.0));
    // 反向断言：绝不能是组分累加 fallback 的 "527"
    expect((previewCal - fallbackCal).abs(), greaterThan(10));

    // onConfirm 捕获值应与预览值一致（同一 AI 优先路径，未拖滑块所以 oil=12）
    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    expect(capturedCal, isNotNull);
    expect(capturedCal, closeTo(expectedCal, 0.5));
    expect(capturedProtein, closeTo(expectedProtein, 0.5));
    expect(capturedFat, closeTo(expectedFat, 0.5));
    expect(capturedCarbs, closeTo(expectedCarbs, 0.5));
  });

  testWidgets('编辑对话框初始值 = 预览值（_currentDisplayedValues 同源）', (tester) async {
    final recognition = buildRecognition();
    final lookup = NutritionLookup(foodRepo);
    final composite = await lookup.lookupCompositeDish(
      components: recognition.foodComponents,
      cookingMethod: recognition.cookingMethod,
    );

    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: recognition,
        compositeNutrition: composite,
        foodItemRepo: foodRepo,
        aiFallbackNutrition: aiFallback,
        onConfirm: (servingG, cal, protein, fat, carbs,
            {componentsSnapshot}) async {},
      ),
    ));
    await tester.pumpAndSettle();

    final previewCal = readDisplayed(tester, const ValueKey('cal_value'));
    final previewProtein = readDisplayed(tester, const ValueKey('protein_value'));
    final previewFat = readDisplayed(tester, const ValueKey('fat_value'));
    final previewCarbs = readDisplayed(tester, const ValueKey('carbs_value'));

    // 点热量数值打开编辑对话框（_nutritionCard 中 InkWell 包裹数值）
    await tester.tap(find.byKey(const ValueKey('cal_value')));
    await tester.pumpAndSettle();

    // 对话框 4 个 TextField 初始值应等于预览值（_currentDisplayedValues 同源）
    final calField =
        tester.widget<TextField>(find.byKey(const ValueKey('edit_cal_field')));
    final proteinField = tester.widget<TextField>(
        find.byKey(const ValueKey('edit_protein_field')));
    final fatField =
        tester.widget<TextField>(find.byKey(const ValueKey('edit_fat_field')));
    final carbsField = tester.widget<TextField>(
        find.byKey(const ValueKey('edit_carbs_field')));

    expect(double.parse(calField.controller!.text), closeTo(previewCal, 1.0));
    expect(
        double.parse(proteinField.controller!.text), closeTo(previewProtein, 1.0));
    expect(double.parse(fatField.controller!.text), closeTo(previewFat, 1.0));
    expect(
        double.parse(carbsField.controller!.text), closeTo(previewCarbs, 1.0));

    // 进一步锁定 AI 优先路径具体值（非 fallback 的 527/36/40/5）
    expect(double.parse(calField.controller!.text), closeTo(expectedCal, 1.0));
    expect(double.parse(proteinField.controller!.text),
        closeTo(expectedProtein, 1.0));
    expect(
        double.parse(fatField.controller!.text), closeTo(expectedFat, 1.0));
    expect(double.parse(carbsField.controller!.text),
        closeTo(expectedCarbs, 1.0));
  });
}
