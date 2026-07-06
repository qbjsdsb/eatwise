import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/features/recognize/calibration_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// v0.28.0 测试：复合菜组分滑块影响热量，预览/记录/编辑对话框三处统一。
///
/// 架构：完全抛弃库参与热量计算，AI 推理组分组分滑块影响热量。
/// - 复合菜路径：总热量 = sum(各组分 per100g × 用户拖动 g / 100)
/// - 自洽缩放：AI 返回的组分热量之和 ≠ estimatedCalories 时按比例缩放各组分
/// - 三处统一：_buildNutritionPreview / _confirmWithServing / _currentDisplayedValues
///   都走 _computeCurrentNutrition，保证显示值与写库值一致
void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    foodRepo = FoodItemRepository(db);
  });
  tearDown(() async => db.close());

  // v1.11 组分带营养字段（calories/proteinG/fatG/carbsG）
  // 鸡肉 150g: cal=250, protein=20, fat=10, carbs=0
  // 花生 30g:  cal=170, protein=8,  fat=14, carbs=5
  // sumCal = 420 = aiFallback.calories → 无需自洽缩放
  VisionRecognitionResult buildRecognition() => VisionRecognitionResult(
        dishName: '宫保鸡丁',
        estimatedWeightGLow: 200,
        estimatedWeightGMid: 250,
        estimatedWeightGHigh: 300,
        foodComponents: const [
          FoodComponent(
            name: '鸡肉',
            estimatedG: 150,
            calories: 250,
            proteinG: 20,
            fatG: 10,
            carbsG: 0,
          ),
          FoodComponent(
            name: '花生',
            estimatedG: 30,
            calories: 170,
            proteinG: 8,
            fatG: 14,
            carbsG: 5,
          ),
        ],
        cookingMethod: 'stir-fry',
        isSingleItem: false,
        confidence: 0.75,
        promptVersion: 'v1.11',
      );

  const aiFallback = NutritionResult(
    foodItemId: 0,
    calories: 420,
    proteinG: 28,
    fatG: 24,
    carbsG: 5,
    oilG: 0,
    source: NutritionSource.aiEstimate,
  );

  // 组分累加期望值（sumCal=aiFallback.calories，无缩放，per100g × g / 100）：
  //   鸡肉 per100g: cal=166.67, protein=13.33, fat=6.67, carbs=0
  //   花生 per100g: cal=566.67, protein=26.67, fat=46.67, carbs=16.67
  //   默认份量（estimatedG）：cal=250+170=420, protein=20+8=28, fat=10+14=24, carbs=0+5=5
  const expectedCal = 420.0;
  const expectedProtein = 28.0;
  const expectedFat = 24.0;
  const expectedCarbs = 5.0;

  double readDisplayed(WidgetTester tester, Key key) {
    final w = tester.widget<Text>(find.byKey(key));
    return double.parse(w.data!.split(' ').first);
  }

  testWidgets('预览 = 组分累加值 + onConfirm 一致（三处统一）', (tester) async {
    final recognition = buildRecognition();

    double? capturedCal, capturedProtein, capturedFat, capturedCarbs;
    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: recognition,
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

    // 预览值 = 组分累加（库不参与热量计算）
    expect(readDisplayed(tester, const ValueKey('cal_value')),
        closeTo(expectedCal, 1.0));
    expect(readDisplayed(tester, const ValueKey('protein_value')),
        closeTo(expectedProtein, 1.0));
    expect(readDisplayed(tester, const ValueKey('fat_value')),
        closeTo(expectedFat, 1.0));
    expect(readDisplayed(tester, const ValueKey('carbs_value')),
        closeTo(expectedCarbs, 1.0));

    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    // onConfirm 捕获值应与预览一致（同一 _computeCurrentNutrition 路径）
    expect(capturedCal, closeTo(expectedCal, 0.5));
    expect(capturedProtein, closeTo(expectedProtein, 0.5));
    expect(capturedFat, closeTo(expectedFat, 0.5));
    expect(capturedCarbs, closeTo(expectedCarbs, 0.5));
  });

  testWidgets('编辑对话框初始值 = 预览值（_currentDisplayedValues 同源）',
      (tester) async {
    final recognition = buildRecognition();

    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: recognition,
        foodItemRepo: foodRepo,
        aiFallbackNutrition: aiFallback,
        onConfirm: (servingG, cal, protein, fat, carbs,
            {componentsSnapshot}) async {},
      ),
    ));
    await tester.pumpAndSettle();

    final previewCal = readDisplayed(tester, const ValueKey('cal_value'));
    final previewProtein =
        readDisplayed(tester, const ValueKey('protein_value'));
    final previewFat = readDisplayed(tester, const ValueKey('fat_value'));
    final previewCarbs = readDisplayed(tester, const ValueKey('carbs_value'));

    // 点热量数值打开编辑对话框
    await tester.tap(find.byKey(const ValueKey('cal_value')));
    await tester.pumpAndSettle();

    final calField =
        tester.widget<TextField>(find.byKey(const ValueKey('edit_cal_field')));
    final proteinField = tester.widget<TextField>(
        find.byKey(const ValueKey('edit_protein_field')));
    final fatField =
        tester.widget<TextField>(find.byKey(const ValueKey('edit_fat_field')));
    final carbsField = tester.widget<TextField>(
        find.byKey(const ValueKey('edit_carbs_field')));

    // 对话框初始值 = 预览值（_currentDisplayedValues 同源）
    expect(double.parse(calField.controller!.text), closeTo(previewCal, 1.0));
    expect(double.parse(proteinField.controller!.text),
        closeTo(previewProtein, 1.0));
    expect(double.parse(fatField.controller!.text), closeTo(previewFat, 1.0));
    expect(
        double.parse(carbsField.controller!.text), closeTo(previewCarbs, 1.0));

    // 锁定组分累加具体值
    expect(double.parse(calField.controller!.text), closeTo(expectedCal, 1.0));
    expect(double.parse(proteinField.controller!.text),
        closeTo(expectedProtein, 1.0));
    expect(
        double.parse(fatField.controller!.text), closeTo(expectedFat, 1.0));
    expect(double.parse(carbsField.controller!.text),
        closeTo(expectedCarbs, 1.0));
  });

  testWidgets('拖动组分滑块 → 热量重算（核心逻辑：组分滑块影响热量）',
      (tester) async {
    final recognition = buildRecognition();

    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: recognition,
        foodItemRepo: foodRepo,
        aiFallbackNutrition: aiFallback,
        onConfirm: (servingG, cal, protein, fat, carbs,
            {componentsSnapshot}) async {},
      ),
    ));
    await tester.pumpAndSettle();

    // 默认预览 = 420 kcal（鸡肉 150g + 花生 30g）
    expect(readDisplayed(tester, const ValueKey('cal_value')),
        closeTo(expectedCal, 1.0));

    // 拖动鸡肉滑块到 300g（翻倍）：鸡肉 cal=166.67*300/100=500，花生 cal=170
    // 总热量 = 500 + 170 = 670 kcal
    final chickenSliderFinder = find.byType(Slider).first;
    await tester.ensureVisible(chickenSliderFinder);
    await tester.pumpAndSettle();
    // 拖动足够距离使滑块到 max（estimatedG*2=300g）：
    // 初值 150g 在轨道 50% 处，drag rect.width → 移到 150% → clamp 到 100%=300g
    final rect = tester.getRect(chickenSliderFinder);
    await tester.drag(chickenSliderFinder, Offset(rect.width, 0));
    await tester.pumpAndSettle();

    // 拖动后热量应重算：500(鸡肉@300g) + 170(花生@30g) = 670 kcal
    expect(readDisplayed(tester, const ValueKey('cal_value')),
        closeTo(670, 1.0),
        reason: '鸡肉 300g → 500kcal + 花生 30g → 170kcal = 670kcal');
  });
}
