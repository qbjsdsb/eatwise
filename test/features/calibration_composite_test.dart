import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/features/recognize/calibration_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复合菜校准页测试
/// 验证：组分滑块渲染 + 用油滑块渲染 + 未命中展示 + 重算后 onConfirm 传调整值
void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    foodRepo = FoodItemRepository(db);
    // 种子：鸡肉 + 花生（组分命中），不插入"黄瓜"（组分未命中）
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

  testWidgets('复合菜显示组分滑块 + 用油滑块 + 未命中展示', (tester) async {
    final recognition = VisionRecognitionResult(
      dishName: '宫保鸡丁',
      estimatedWeightGLow: 200,
      estimatedWeightGMid: 250,
      estimatedWeightGHigh: 300,
      foodComponents: const [
        FoodComponent(name: '鸡肉', estimatedG: 150),
        FoodComponent(name: '花生', estimatedG: 30),
        FoodComponent(name: '黄瓜', estimatedG: 20), // 未命中
      ],
      cookingMethod: 'stir-fry',
      isSingleItem: false,
      confidence: 0.75,
      promptVersion: 'v1.0',
    );
    // 先调 NutritionLookup 生成 compositeNutrition
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
        onConfirm: (_, __, ___, ____, _____, {componentsSnapshot}) async {},
      ),
    ));

    // 验证组分滑块标签
    expect(find.textContaining('鸡肉'), findsWidgets);
    expect(find.textContaining('花生'), findsWidgets);
    // 验证未命中展示
    expect(find.textContaining('待确认组分'), findsOneWidget);
    expect(find.textContaining('黄瓜'), findsWidgets);
    // 验证用油量标签（stir-fry 默认 12g）
    expect(find.textContaining('用油量'), findsOneWidget);
  });

  testWidgets('确认时 onConfirm 传重算值（默认份量）', (tester) async {
    final recognition = VisionRecognitionResult(
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
    final lookup = NutritionLookup(foodRepo);
    final composite = await lookup.lookupCompositeDish(
      components: recognition.foodComponents,
      cookingMethod: recognition.cookingMethod,
    );

    double? capturedCalories;
    double? capturedProtein;
    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: recognition,
        compositeNutrition: composite,
        foodItemRepo: foodRepo,
        onConfirm: (_, calories, protein, __, _____, {componentsSnapshot}) async {
          capturedCalories = calories;
          capturedProtein = protein;
        },
      ),
    ));

    // 点击"确认记录"按钮（用默认份量，应等于 lookupCompositeDish 的原始计算值）
    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    // 验证 onConfirm 被调用且传入了重算值（鸡肉 150g + 花生 30g + 油 12g）
    expect(capturedCalories, isNotNull);
    expect(capturedCalories! > 0, isTrue);
    // 鸡肉 167*1.5 + 花生 567*0.3 + 油 889*0.12 = 250.5 + 170.1 + 106.68 = 527.28
    expect(capturedCalories, closeTo(527.28, 5.0));
    // 鸡肉 19*1.5 + 花生 25*0.3 = 28.5 + 7.5 = 36
    expect(capturedProtein, closeTo(36.0, 5.0));
  });
}
