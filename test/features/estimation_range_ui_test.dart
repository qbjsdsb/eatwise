// test/features/estimation_range_ui_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/core/config/app_config.dart';
import 'package:eatwise/core/config/secure_config_store.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/features/dashboard/dashboard_page.dart';
import 'package:eatwise/features/recognize/calibration_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
            {componentsSnapshot}) async {},
      ),
    ));

    // 验证显示区间（含 "90-110" 或 "估算" 文字）
    expect(find.textContaining('90'), findsWidgets);
    expect(find.textContaining('110'), findsWidgets);
  });

  testWidgets('看板宏量显示 g/kg 双展示', (tester) async {
    // 沙箱无 secure_storage 平台通道，注入内存 mock（v5 看板 initState 会
    // 调 appConfigProvider.future 检查 GLM key，不 mock 会抛 MissingPluginException
    // 导致 AI FutureBuilder 卡在 loading，CircularProgressIndicator 永不停止）
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureConfigStore();

    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // 默认 profile weightKg=70（DB 首次创建时种子）
    // 种子食物 + 今日 meal_log
    final foodId = await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '鸡胸肉', defaultServingG: 100, caloriesPer100g: 165,
          proteinPer100g: 31.0, fatPer100g: 3.6, carbsPer100g: 0.0,
          source: 'manual', sourceVersion: 'test', createdAt: 1000));
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await MealLogRepository(db).insertMealLog(
      date: today,
      mealType: 'lunch',
      foodItemId: foodId,
      actualServingG: 200,
      actualCalories: 330,
      actualProteinG: 62.0,
      actualFatG: 7.2,
      actualCarbsG: 0.0,
    );

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
      secureConfigStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 验证宏量迷你进度条展示（新首页格式：value/goalg）
    // 蛋白质 62g，目标 = proteinGPerKg(1.4) * weightKg(70) = 98g
    expect(find.text('蛋白'), findsOneWidget);
    expect(find.textContaining('62/98g'), findsOneWidget);
  });
}
