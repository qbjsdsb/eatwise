// 转手动录入破坏性操作确认测试（M16.7 可访问性修复）
//
// 复现 bug：multi_dish_page / calibration_page 顶部"转手动"按钮直接
// Navigator.pushReplacement 到 ManualEntryPage，绕过 PopScope dirty 检查，
// dirty 状态下静默丢失未保存滑块改动无确认 modal。
//
// 修复后：dirty 状态下点"转手动"应弹 confirmDiscardChanges 确认 dialog
// （复用现有 helper，文案"放弃修改？" + "继续编辑"/"放弃" 按钮），
// 用户点"放弃"才 pushReplacement；非 dirty 直接跳转。
//
// 测试覆盖：
// 1. multi_dish_page dirty 下点转手动 → 弹确认 dialog
// 2. multi_dish_page 非 dirty 下点转手动 → 直接跳 ManualEntryPage，不弹 dialog
// 3. calibration_page dirty 下点转手动 → 弹确认 dialog
// 4. calibration_page 非 dirty 下点转手动 → 直接跳 ManualEntryPage，不弹 dialog
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/features/manual_entry/manual_entry_page.dart';
import 'package:eatwise/features/recognize/calibration_page.dart';
import 'package:eatwise/features/recognize/multi_dish_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    // 预置库数据：番茄（主菜查库命中，slider 会渲染）
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

  /// 主菜查库命中营养结果（番茄 100g）
  final mainSingle = NutritionResult(
    foodItemId: 1, // 番茄 id（setUp insert）
    calories: 18,
    proteinG: 0.9,
    fatG: 0.2,
    carbsG: 3.9,
    oilG: 0,
  );

  group('M16.7 multi_dish_page 转手动确认', () {
    testWidgets('dirty 状态下点转手动应弹确认 dialog', (tester) async {
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: MultiDishPage(
          mainDish: mainDish,
          mainSingle: mainSingle,
          additionalItems: const [],
          mealType: 'lunch',
        )),
      ));
      await tester.pumpAndSettle();

      // 拖滑块标记 dirty（用户改了份量未保存）
      await tester.drag(find.byType(Slider).first, const Offset(40, 0));
      await tester.pump();

      // 点"转手动"
      await tester.tap(find.text('转手动'));
      await tester.pumpAndSettle();

      // 应弹出 confirmDiscardChanges 确认 dialog（复用现有 helper）
      expect(find.text('放弃修改？'), findsOneWidget,
          reason: 'dirty 状态下点转手动应弹确认 dialog，避免静默丢失未保存滑块改动');
      expect(find.text('继续编辑'), findsOneWidget);
      expect(find.text('放弃'), findsOneWidget);
    });

    testWidgets('非 dirty 状态下点转手动直接跳转（不弹 dialog）',
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
          additionalItems: const [],
          mealType: 'lunch',
        )),
      ));
      await tester.pumpAndSettle();

      // 不拖滑块（dirty=false），直接点转手动
      await tester.tap(find.text('转手动'));
      await tester.pumpAndSettle();

      // 不应有确认 dialog
      expect(find.text('放弃修改？'), findsNothing,
          reason: '非 dirty 状态下点转手动应直接跳转，不弹确认 dialog');
      // 应跳转到 ManualEntryPage
      expect(find.byType(ManualEntryPage), findsOneWidget,
          reason: '非 dirty 状态下点转手动应 pushReplacement 到 ManualEntryPage');
    });
  });

  group('M16.7 calibration_page 转手动确认', () {
    /// beer 单品识别结果（用于 calibration_page）
    VisionRecognitionResult beerRecognition() => const VisionRecognitionResult(
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

    /// AI 兜底哨兵：foodItemId=0（calibration_page slider 渲染仅需 non-null singleNutrition）
    NutritionResult aiFallback() => NutritionResult(
          foodItemId: 0,
          calories: 600,
          proteinG: 2,
          fatG: 1,
          carbsG: 15,
          oilG: 0,
          source: NutritionSource.aiEstimate,
        );

    testWidgets('dirty 状态下点转手动应弹确认 dialog', (tester) async {
      final foodRepo = FoodItemRepository(db);

      // 用 ProviderScope 包裹，因为 pushReplacement 目标 ManualEntryPage 是 Consumer
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: CalibrationPage(
          recognitionResult: beerRecognition(),
          singleNutrition: aiFallback(),
          foodItemRepo: foodRepo,
          suggestedServingG: 200,
          onConfirm: (_, __, ___, ____, _____, {componentsSnapshot}) async {},
        )),
      ));
      await tester.pumpAndSettle();

      // 拖滑块标记 dirty（用户改了份量未保存）
      await tester.drag(find.byType(Slider).first, const Offset(40, 0));
      await tester.pump();

      // 点"转手动"
      await tester.tap(find.text('转手动'));
      await tester.pumpAndSettle();

      // 应弹出 confirmDiscardChanges 确认 dialog
      expect(find.text('放弃修改？'), findsOneWidget,
          reason: 'dirty 状态下点转手动应弹确认 dialog，避免静默丢失未保存滑块改动');
      expect(find.text('继续编辑'), findsOneWidget);
      expect(find.text('放弃'), findsOneWidget);
    });

    testWidgets('非 dirty 状态下点转手动直接跳转（不弹 dialog）',
        (tester) async {
      final foodRepo = FoodItemRepository(db);

      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: CalibrationPage(
          recognitionResult: beerRecognition(),
          singleNutrition: aiFallback(),
          foodItemRepo: foodRepo,
          suggestedServingG: 200,
          onConfirm: (_, __, ___, ____, _____, {componentsSnapshot}) async {},
        )),
      ));
      await tester.pumpAndSettle();

      // 不拖滑块（dirty=false），直接点转手动
      await tester.tap(find.text('转手动'));
      await tester.pumpAndSettle();

      // 不应有确认 dialog
      expect(find.text('放弃修改？'), findsNothing,
          reason: '非 dirty 状态下点转手动应直接跳转，不弹确认 dialog');
      // 应跳转到 ManualEntryPage
      expect(find.byType(ManualEntryPage), findsOneWidget,
          reason: '非 dirty 状态下点转手动应 pushReplacement 到 ManualEntryPage');
    });
  });
}
