import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/features/recognize/calibration_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// P1 修复 2 测试：AI 优先路径累加用油量。
///
/// 场景：复合菜 + aiFallback 非空（无包装数据，直接走 AI 优先路径）。
/// 期望：
/// - 默认用油量（stir-fry=12g）时预览 cal = calibrated.actualCalories + oilCaloriesPer100g*oil/100
///   fat = calibrated.actualFatG + oilFatPer100g*oil/100；蛋白/碳水不含油项
/// - 拖动用油滑块到 0g：cal/fat 降到无油基准；蛋白/碳水不变
/// - 拖动用油滑块到 30g：cal/fat 上升；蛋白/碳水不变
/// - onConfirm 捕获值含油量累加
void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    foodRepo = FoodItemRepository(db);
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

  // 无包装数据（hasPackageNutrition=false）→ 直接走 AI 优先路径
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

  // AI 优先路径基准值（v2.1 修复后 servingG=mid=250，actualXxx=aiFallback 对应值=AI 推理值）：
  //   actualCalories = 300 * 250/250 = 300
  //   actualProtein  = 20  * 250/250 = 20
  //   actualFat      = 10  * 250/250 = 10
  //   actualCarbs    = 30  * 250/250 = 30
  const calBase = 300.0;
  const proteinBase = 20.0;
  const fatBase = 10.0;
  const carbsBase = 30.0;
  // 油 12g：cal += 889*12/100=106.68；fat += 99.9*12/100=11.988
  // 油 30g：cal += 889*30/100=266.7；fat += 99.9*30/100=29.97
  final calAtOil12 = calBase + oilCaloriesPer100g * 12 / 100;
  final fatAtOil12 = fatBase + oilFatPer100g * 12 / 100;
  final calAtOil30 = calBase + oilCaloriesPer100g * 30 / 100;
  final fatAtOil30 = fatBase + oilFatPer100g * 30 / 100;

  double readDisplayed(WidgetTester tester, Key key) {
    final w = tester.widget<Text>(find.byKey(key));
    // 热量文本为 "407"，宏量列文本为 "20 g"（带单位后缀），取首段数字解析
    return double.parse(w.data!.split(' ').first);
  }

  /// 把"用油量"滑块（页面最后一个 Slider）设到 target 值。
  /// 复合菜路径 _currentNutrition 为 null → 无主份量滑块/数量步进器，
  /// Slider 仅含各组分滑块 + 用油量滑块，用油量排在最后。
  /// 用油量滑块在长内容底部，需先 ensureVisible 滚入视口，否则 getRect 拿到屏外坐标
  /// 会误触底部"确认记录"按钮。tapAt 点轨道目标位置（Material Slider 支持 tap-to-move），
  /// divisions=50 → 1g 步进吸附。
  Future<void> setOilSlider(WidgetTester tester, double target) async {
    final finder = find.byType(Slider).last;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(finder);
    final rect = tester.getRect(finder);
    final fraction = (target - slider.min) / (slider.max - slider.min);
    final x = rect.left + rect.width * fraction;
    await tester.tapAt(Offset(x, rect.center.dy));
    await tester.pumpAndSettle();
  }

  testWidgets('默认用油量 12g 预览含油累加 + 蛋白碳水无油项', (tester) async {
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

    // cal 含油累加
    expect(readDisplayed(tester, const ValueKey('cal_value')),
        closeTo(calAtOil12, 1.0));
    // 蛋白/碳水不含油项（AI 优先路径蛋白/碳水不加油）
    expect(readDisplayed(tester, const ValueKey('protein_value')),
        closeTo(proteinBase, 1.0));
    expect(readDisplayed(tester, const ValueKey('carbs_value')),
        closeTo(carbsBase, 1.0));
    // 脂肪含油累加
    expect(readDisplayed(tester, const ValueKey('fat_value')),
        closeTo(fatAtOil12, 1.0));
  });

  testWidgets('拖动用油滑块改变 cal/fat，蛋白/碳水不变', (tester) async {
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

    // 蛋白/碳水基准（默认 oil=12）
    final baseProtein = readDisplayed(tester, const ValueKey('protein_value'));
    final baseCarbs = readDisplayed(tester, const ValueKey('carbs_value'));

    // 拖到 0g：cal/fat 降到无油基准
    await setOilSlider(tester, 0);
    expect(readDisplayed(tester, const ValueKey('cal_value')),
        closeTo(calBase, 1.0));
    expect(readDisplayed(tester, const ValueKey('fat_value')),
        closeTo(fatBase, 1.0));
    expect(readDisplayed(tester, const ValueKey('protein_value')),
        closeTo(baseProtein, 0.01));
    expect(readDisplayed(tester, const ValueKey('carbs_value')),
        closeTo(baseCarbs, 0.01));

    // 拖到 30g：cal/fat 上升
    await setOilSlider(tester, 30);
    expect(readDisplayed(tester, const ValueKey('cal_value')),
        closeTo(calAtOil30, 1.0));
    expect(readDisplayed(tester, const ValueKey('fat_value')),
        closeTo(fatAtOil30, 1.0));
    expect(readDisplayed(tester, const ValueKey('protein_value')),
        closeTo(baseProtein, 0.01));
    expect(readDisplayed(tester, const ValueKey('carbs_value')),
        closeTo(baseCarbs, 0.01));
  });

  testWidgets('onConfirm 捕获值含油量累加（默认 12g）', (tester) async {
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

    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    // onConfirm 捕获的 cal/fat 含 12g 油累加，蛋白/碳水为 AI 反算值（无油项）
    expect(capturedCal, closeTo(calAtOil12, 0.5));
    expect(capturedProtein, closeTo(proteinBase, 0.5));
    expect(capturedFat, closeTo(fatAtOil12, 0.5));
    expect(capturedCarbs, closeTo(carbsBase, 0.5));
  });
}
