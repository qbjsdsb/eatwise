// test/features/estimation_range_ui_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/features/recognize/calibration_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('校准页显示份量区间', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // 种子食物
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '米饭', defaultServingG: 100, caloriesPer100g: 116,
          proteinPer100g: 2.6, fatPer100g: 0.3, carbsPer100g: 25.9,
          source: 'manual', sourceVersion: 'test', createdAt: 1000));

    final result = VisionRecognitionResult(
      dishName: '米饭',
      estimatedWeightGLow: 90,
      estimatedWeightGMid: 100,
      estimatedWeightGHigh: 110,
      foodComponents: const [],
      cookingMethod: 'boil',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.0',
    );
    final nutrition = await NutritionLookup(FoodItemRepository(db))
        .lookupSingleItem(dishName: '米饭', servingG: 100);

    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: result,
        singleNutrition: nutrition,
        foodItemRepo: FoodItemRepository(db),
        onConfirm: (servingG, calories, protein, fat, carbs,
            {componentsSnapshot}) {},
      ),
    ));

    // 验证显示区间（含 "90-110" 或 "估算" 文字）
    expect(find.textContaining('90'), findsWidgets);
    expect(find.textContaining('110'), findsWidgets);
  });
}
