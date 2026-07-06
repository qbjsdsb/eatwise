import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/features/recognize/calibration_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// v0.28.0 复合菜校准页测试
/// - v1.11 组分（带营养字段）→ 组分滑块显示，用油量滑块已删除
/// - 旧 prompt 组分（无营养字段）→ 组分滑块不显示，走单品 AI 路径（向后兼容）
void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    foodRepo = FoodItemRepository(db);
  });
  tearDown(() async => db.close());

  testWidgets('v0.28.0：v1.11 组分显示组分滑块，无用油量滑块', (tester) async {
    final recognition = VisionRecognitionResult(
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

    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: recognition,
        foodItemRepo: foodRepo,
        aiFallbackNutrition: aiFallback,
        onConfirm: (_, __, ___, ____, _____, {componentsSnapshot}) async {},
      ),
    ));
    await tester.pumpAndSettle();

    // v0.28.0：组分滑块恢复显示，应看到组分名
    expect(find.textContaining('鸡肉'), findsWidgets,
        reason: 'v0.28.0：v1.11 组分有营养字段，组分滑块应显示"鸡肉"');
    expect(find.textContaining('花生'), findsWidgets,
        reason: 'v0.28.0：v1.11 组分有营养字段，组分滑块应显示"花生"');
    // v0.28.0：用油量滑块已删除（AI reasoning 已含用油）
    expect(find.textContaining('用油量'), findsNothing,
        reason: 'v0.28.0：用油量滑块已删除');
    // v0.28.0：组分明细标题显示
    expect(find.textContaining('组分明细'), findsOneWidget);
  });

  testWidgets('v0.28.0：旧 prompt 组分（无营养字段）不显示组分滑块，走 AI 路径',
      (tester) async {
    final recognition = VisionRecognitionResult(
      dishName: '宫保鸡丁',
      estimatedWeightGLow: 200,
      estimatedWeightGMid: 250,
      estimatedWeightGHigh: 300,
      foodComponents: const [
        // 旧 prompt：无 calories/proteinG/fatG/carbsG 字段（默认 0）
        FoodComponent(name: '鸡肉', estimatedG: 150),
        FoodComponent(name: '花生', estimatedG: 30),
      ],
      cookingMethod: 'stir-fry',
      isSingleItem: false,
      confidence: 0.75,
      promptVersion: 'v1.10',
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

    double? capturedCalories;
    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: recognition,
        foodItemRepo: foodRepo,
        aiFallbackNutrition: aiFallback,
        onConfirm: (_, calories, __, ___, _____, {componentsSnapshot}) async {
          capturedCalories = calories;
        },
      ),
    ));
    await tester.pumpAndSettle();

    // 旧 prompt 组分无营养字段（sumCal=0）→ _hasComponentNutrition=false → 组分滑块不显示
    expect(find.textContaining('组分明细'), findsNothing,
        reason: '旧 prompt 组分无营养字段，不显示组分明细');
    expect(find.textContaining('用油量'), findsNothing,
        reason: 'v0.28.0：用油量滑块已删除');
    // 走单品 AI 路径：预览显示 aiFallback.calories = 420
    expect(find.text('420'), findsOneWidget,
        reason: '旧 prompt 组分走单品 AI 路径，预览显示 aiFallback.calories');

    await tester.tap(find.text('确认记录'));
    await tester.pumpAndSettle();

    // onConfirm 传 AI 值（库不参与热量计算）
    expect(capturedCalories, closeTo(420, 0.5),
        reason: '旧 prompt 组分 onConfirm 传 AI 值 420');
  });
}
