import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/pending_recognition_repository.dart';
import 'package:eatwise/features/offline/offline_queue_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sprint 5 T30 离线回补复合菜 bug 修复 + GLM fallback 注入测试
/// - 复合菜回补不再静默丢弃（写入 meal_log）
/// - 主视觉模型失败时降级到 fallback provider
void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;
  late NutritionLookup lookup;
  late Directory tmpDir;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    foodRepo = FoodItemRepository(db);
    lookup = NutritionLookup(foodRepo);
    tmpDir = await Directory.systemTemp.createTemp('offline_composite_test_');
    // 种子：鸡肉 + 花生（复合菜组分）
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

  tearDown(() async {
    await db.close();
    await tmpDir.delete(recursive: true);
  });

  Future<String> writeFakeImage(String name) async {
    final file = File('${tmpDir.path}/$name.jpg');
    await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]); // JPEG 头
    return file.path;
  }

  test('复合菜回补写入 meal_log（不再静默丢弃）', () async {
    final pendingRepo = PendingRecognitionRepository(db);
    final imgPath = await writeFakeImage('composite');
    await pendingRepo.enqueue(
      imagePath: imgPath,
      mealType: 'lunch',
      date: '2026-07-02',
      promptVersion: 'v1.0',
    );

    final controller = OfflineQueueController(
      db: db,
      visionProvider: _FakeCompositeProvider(),
      nutritionLookup: lookup,
    );
    await controller.processPending();

    // 验证 meal_log 已写入（修复前不写）
    final mealLogs = await db.select(db.mealLogs).get();
    expect(mealLogs.length, 1);
    expect(mealLogs.first.actualCalories, greaterThan(0)); // 复合菜有热量
    expect(mealLogs.first.actualProteinG, greaterThan(0));
    expect(mealLogs.first.mealType, 'lunch');
    // 第二波：PostProcessor 接入离线回补后，组分份量交叉验证生效
    // 原 sum=180g(鸡肉150+花生30) vs mid=250g，偏差 38.9%>15% → 按 mid 缩放 1.389x
    // 缩放后 鸡肉 208.3g + 花生 41.7g = 250g（= mid）
    expect(mealLogs.first.actualServingG, closeTo(250, 0.5));

    // 验证 pending 标记 done
    final pending = await pendingRepo.listPending();
    expect(pending.length, 0);
  });

  test('主视觉模型失败时降级到 fallback provider', () async {
    final pendingRepo = PendingRecognitionRepository(db);
    final imgPath = await writeFakeImage('fallback');
    await pendingRepo.enqueue(
      imagePath: imgPath,
      mealType: 'dinner',
      date: '2026-07-02',
      promptVersion: 'v1.0',
    );

    final controller = OfflineQueueController(
      db: db,
      visionProvider: _ThrowingProvider(),
      fallbackProvider: _FakeCompositeProvider(),
      nutritionLookup: lookup,
    );
    await controller.processPending();

    // fallback 返回复合菜 → 应正常写 meal_log + markDone
    final mealLogs = await db.select(db.mealLogs).get();
    expect(mealLogs.length, 1);
    expect(mealLogs.first.actualCalories, greaterThan(0));

    final pending = await pendingRepo.listPending();
    expect(pending.length, 0);
  });

  test('主失败且无 fallback 时 markFailed（不写 meal_log）', () async {
    final pendingRepo = PendingRecognitionRepository(db);
    final imgPath = await writeFakeImage('no_fallback');
    await pendingRepo.enqueue(
      imagePath: imgPath,
      mealType: 'dinner',
      date: '2026-07-02',
      promptVersion: 'v1.0',
    );

    final controller = OfflineQueueController(
      db: db,
      visionProvider: _ThrowingProvider(),
      nutritionLookup: lookup,
    );
    await controller.processPending();

    // 无 fallback → 异常向上抛被外层 catch → markFailed
    final mealLogs = await db.select(db.mealLogs).get();
    expect(mealLogs.length, 0);

    final all = await db.pendingRecognitions.select().get();
    expect(all.first.retryCount, 1);
    expect(all.first.status, 'pending'); // 仍待重试
  });

  test('第二波：离线回补密度换算生效（500ml 油 → 460g 写入 meal_log）', () async {
    // 第一波盲区：离线回补原直接用原始 result，包装液体未换算 ml→g
    // 第二波修复：接入 RecognitionPostProcessor，与前台一致
    // 种子：食用油（889 kcal/100g，ediblePercent=null=100%）
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '食用油',
          defaultServingG: 100,
          caloriesPer100g: 889,
          proteinPer100g: 0,
          fatPer100g: 99.9,
          carbsPer100g: 0,
          source: 'manual',
          sourceVersion: 'test',
          createdAt: 1002,
        ));

    final pendingRepo = PendingRecognitionRepository(db);
    final imgPath = await writeFakeImage('oil');
    await pendingRepo.enqueue(
      imagePath: imgPath,
      mealType: 'breakfast',
      date: '2026-07-02',
      promptVersion: 'v1.7',
    );

    final controller = OfflineQueueController(
      db: db,
      visionProvider: _FakeOilProvider(),
      nutritionLookup: lookup,
    );
    await controller.processPending();

    final mealLogs = await db.select(db.mealLogs).get();
    expect(mealLogs.length, 1);
    // 密度换算后 mid = 500 * 0.92 = 460g（不再是原始 500）
    expect(mealLogs.first.actualServingG, closeTo(460, 0.5));
    // 库反算：889 * 460 / 100 = 4089.4 kcal
    expect(mealLogs.first.actualCalories, closeTo(4089.4, 0.5));
  });

  // v1.9 Gap1 集成测试：复合菜有包装营养表数据时，per100g + actualCalories 用包装换算
  test('v1.9 Gap1: 复合菜有包装数据时 per100g 用包装换算值（非 0）', () async {
    final pendingRepo = PendingRecognitionRepository(db);
    final imgPath = await writeFakeImage('composite_pkg');
    await pendingRepo.enqueue(
      imagePath: imgPath,
      mealType: 'lunch',
      date: '2026-07-02',
      promptVersion: 'v1.9',
    );

    final controller = OfflineQueueController(
      db: db,
      visionProvider: _FakeCompositePackageProvider(),
      nutritionLookup: lookup,
    );
    await controller.processPending();

    final mealLogs = await db.select(db.mealLogs).get();
    expect(mealLogs.length, 1);
    // 包装换算：servingKcal=250, servingG=100 → per100g=250
    // actualServingG = 组分总和 = 150+30 = 180g
    // actualCalories = 250 * 180 / 100 = 450 kcal
    expect(mealLogs.first.actualServingG, closeTo(180, 0.5));
    expect(mealLogs.first.actualCalories, closeTo(450, 0.5));

    // food_item 的 per100g 应为包装换算值（250），不是 0
    final foodItems = await db.select(db.foodItems).get();
    final compositeItem = foodItems.firstWhere(
      (f) => f.name == '速冻水饺',
      orElse: () => throw StateError('速冻水饺 food_item 未创建'),
    );
    expect(compositeItem.caloriesPer100g, closeTo(250, 0.5));
    expect(compositeItem.proteinPer100g, greaterThan(0)); // 包装路径蛋白/脂肪/碳水也按比例反算
  });

  // ============================================================
  // M18 Task 3: offline_queue 复合菜命中分支 AI 优先集成测试（3 个）
  // 验证 offline_queue_controller 复合菜命中分支与 multi_dish_page 行为一致：
  // - AI 有效（per100g ∈ [0, 900]）→ 用 AI 整菜估算记 meal_log + per100g 用 AI 反算值
  // - AI mid=0 防除零 → 用组分累加库值兜底 + per100g=0
  // - 无 AI 估算（旧 prompt）→ 用组分累加（向后兼容）+ per100g=0
  //
  // 测试数据设计（避免 PostProcessor 修正干扰）：
  // - mid = 组分 sum（不触发组分缩放）
  // - estimatedCalories 与 Atwater 自洽（4p+9f+4c，不触发 calories 修正）
  // ============================================================

  test('M18: offline_queue 复合菜命中 + AI 有效 → 用 AI 整菜估算（与 multi_dish_page 一致）',
      () async {
    final pendingRepo = PendingRecognitionRepository(db);
    final imgPath = await writeFakeImage('composite_ai_valid');
    await pendingRepo.enqueue(
      imagePath: imgPath,
      mealType: 'lunch',
      date: '2026-07-02',
      promptVersion: 'v1.10',
    );

    final controller = OfflineQueueController(
      db: db,
      visionProvider: _FakeCompositeAiValidProvider(),
      nutritionLookup: lookup,
    );
    await controller.processPending();

    final mealLogs = await db.select(db.mealLogs).get();
    expect(mealLogs.length, 1);

    // AI 有效：estimatedCalories=340, mid=180 → aiPer100=188.9（有效 ∈ [0, 900]）
    // actualServingG = 组分 sum = 180g（mid=sum 不缩放）
    // actualCalories = 340 * 180/180 = 340（AI 估算，与 multi_dish_page 一致）
    expect(mealLogs.first.actualCalories, closeTo(340, 0.5),
        reason: 'M18: AI 有效时用 AI 整菜估算（340），不用组分累加库值（~527）');
    expect(mealLogs.first.actualProteinG, closeTo(35, 0.5),
        reason: 'actualProteinG 用 AI 估算值（35）');

    // food_item 的 per100g 应为 AI 反算值（188.9），不是 0 占位
    final foodItems = await db.select(db.foodItems).get();
    final compositeItem = foodItems.firstWhere(
      (f) => f.name == '宫保鸡丁',
      orElse: () => throw StateError('宫保鸡丁 food_item 未创建'),
    );
    expect(compositeItem.caloriesPer100g, closeTo(188.9, 0.5),
        reason: 'M18: per100g 用 AI 反算值（340 * 100 / 180 ≈ 188.9），'
            '不再 0 占位');
  });

  test('M18: offline_queue 复合菜命中 + AI mid=0 防除零 → 用组分累加库值兜底',
      () async {
    final pendingRepo = PendingRecognitionRepository(db);
    final imgPath = await writeFakeImage('composite_mid_zero');
    await pendingRepo.enqueue(
      imagePath: imgPath,
      mealType: 'lunch',
      date: '2026-07-02',
      promptVersion: 'v1.10',
    );

    final controller = OfflineQueueController(
      db: db,
      visionProvider: _FakeCompositeMidZeroProvider(),
      nutritionLookup: lookup,
    );
    await controller.processPending();

    final mealLogs = await db.select(db.mealLogs).get();
    expect(mealLogs.length, 1);

    // mid=0 防除零：computeCompositeLookupHit 返回 null，走组分累加兜底
    // 组分不缩放（mid=0 不触发缩放）：鸡肉 150g + 花生 30g
    // composite.calories = 150×167/100 + 30×567/100 + 油 12×889/100
    //                    = 250.5 + 170.1 + 106.68 = 527.28
    expect(mealLogs.first.actualCalories, closeTo(527.28, 1.0),
        reason: 'M18: mid=0 防除零时用组分累加库值兜底（~527）');

    // food_item 的 per100g 应为 0（兜底占位，AI 无效不进库）
    final foodItems = await db.select(db.foodItems).get();
    final compositeItem = foodItems.firstWhere(
      (f) => f.name == '宫保鸡丁',
      orElse: () => throw StateError('宫保鸡丁 food_item 未创建'),
    );
    expect(compositeItem.caloriesPer100g, 0,
        reason: 'M18: mid=0 防除零时 per100g=0 占位（兜底，AI 不进库）');
  });

  test('M18: offline_queue 复合菜命中 + 无 AI 估算 → 用组分累加（向后兼容旧 prompt）',
      () async {
    final pendingRepo = PendingRecognitionRepository(db);
    final imgPath = await writeFakeImage('composite_no_ai');
    await pendingRepo.enqueue(
      imagePath: imgPath,
      mealType: 'lunch',
      date: '2026-07-02',
      promptVersion: 'v1.0',
    );

    // _FakeCompositeProvider：estimatedCalories=null（旧 prompt）
    final controller = OfflineQueueController(
      db: db,
      visionProvider: _FakeCompositeProvider(),
      nutritionLookup: lookup,
    );
    await controller.processPending();

    final mealLogs = await db.select(db.mealLogs).get();
    expect(mealLogs.length, 1);

    // 无 AI 估算：用组分累加库值（与 M18 前行为一致，向后兼容）
    // 组分缩放至 mid=250g：鸡肉 208.3g + 花生 41.7g
    // composite.calories = 208.3×167/100 + 41.7×567/100 + 油 12×889/100
    //                    = 347.86 + 236.44 + 106.68 = 690.98
    expect(mealLogs.first.actualCalories, closeTo(690.98, 1.0),
        reason: 'M18: 无 AI 估算时用组分累加库值（~691），向后兼容');

    // food_item 的 per100g 应为 0（无 AI 估算不进库）
    final foodItems = await db.select(db.foodItems).get();
    final compositeItem = foodItems.firstWhere(
      (f) => f.name == '宫保鸡丁',
      orElse: () => throw StateError('宫保鸡丁 food_item 未创建'),
    );
    expect(compositeItem.caloriesPer100g, 0,
        reason: 'M18: 无 AI 估算时 per100g=0 占位（向后兼容）');
  });
}

/// 模拟识别 500ml 食用油（包装标签 + 液体类别，触发密度换算）
class _FakeOilProvider implements VisionProvider {
  @override
  String get name => 'FakeOil';

  @override
  String get promptVersion => 'v1.7';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    return const VisionRecognitionResult(
      dishName: '食用油',
      estimatedWeightGLow: 485,
      estimatedWeightGMid: 500, // ml 数值，后端按密度换算
      estimatedWeightGHigh: 515,
      foodComponents: [],
      cookingMethod: 'raw',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.7',
      quantity: 1,
      unit: '瓶',
      perUnitG: 500,
      weightSource: 'package_label',
      foodCategory: 'oil',
    );
  }
}

/// 模拟识别复合菜（宫保鸡丁 = 鸡肉 + 花生）
class _FakeCompositeProvider implements VisionProvider {
  @override
  String get name => 'FakeComposite';

  @override
  String get promptVersion => 'v1.0';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    return const VisionRecognitionResult(
      dishName: '宫保鸡丁',
      estimatedWeightGLow: 200,
      estimatedWeightGMid: 250,
      estimatedWeightGHigh: 300,
      foodComponents: [
        FoodComponent(name: '鸡肉', estimatedG: 150),
        FoodComponent(name: '花生', estimatedG: 30),
      ],
      cookingMethod: 'stir-fry',
      isSingleItem: false,
      confidence: 0.8,
      promptVersion: 'v1.0',
    );
  }
}

/// 模拟识别抛异常的 Provider（主模型失败场景）
class _ThrowingProvider implements VisionProvider {
  @override
  String get name => 'Throwing';

  @override
  String get promptVersion => 'v1.0';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    throw Exception('识别异常：模拟主模型失败');
  }
}

/// v1.9 Gap1 测试用：模拟识别复合菜（速冻水饺）+ 包装营养表数据
/// 验证复合菜分支 hasPackageNutrition 优先路径实际接入
class _FakeCompositePackageProvider implements VisionProvider {
  @override
  String get name => 'FakeCompositePackage';

  @override
  String get promptVersion => 'v1.9';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    return const VisionRecognitionResult(
      dishName: '速冻水饺',
      brand: '必品阁',
      estimatedWeightGLow: 170,
      estimatedWeightGMid: 180,
      estimatedWeightGHigh: 190,
      foodComponents: [
        FoodComponent(name: '面粉', estimatedG: 100),
        FoodComponent(name: '猪肉', estimatedG: 80),
      ],
      cookingMethod: 'boil',
      isSingleItem: false,
      confidence: 0.85,
      promptVersion: 'v1.9',
      estimatedCalories: 450,
      estimatedProteinG: 18,
      estimatedFatG: 15,
      estimatedCarbsG: 60,
      // 包装营养表：每份 100g，能量 250kcal
      packageNutritionTableOcr: '每份100g 能量250kcal',
      packageServingG: 100,
      packageServingKcal: 250,
      packageTotalG: 300,
      packageServingsPerPack: 3,
    );
  }
}

/// M18 Task3 测试用：复合菜（宫保鸡丁）+ AI 整菜估算有效
/// mid=180（= 组分 150+30 sum，不触发缩放）
/// estimatedCalories=340, protein=35, fat=20, carbs=5（Atwater 自洽：4*35+9*20+4*5=340）
class _FakeCompositeAiValidProvider implements VisionProvider {
  @override
  String get name => 'FakeCompositeAiValid';

  @override
  String get promptVersion => 'v1.10';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    return const VisionRecognitionResult(
      dishName: '宫保鸡丁',
      estimatedWeightGLow: 160,
      estimatedWeightGMid: 180, // = 组分 sum，不触发 PostProcessor 组分缩放
      estimatedWeightGHigh: 200,
      foodComponents: [
        FoodComponent(name: '鸡肉', estimatedG: 150),
        FoodComponent(name: '花生', estimatedG: 30),
      ],
      cookingMethod: 'stir-fry',
      isSingleItem: false,
      confidence: 0.9,
      promptVersion: 'v1.10',
      estimatedCalories: 340, // Atwater 自洽：4*35+9*20+4*5=340
      estimatedProteinG: 35,
      estimatedFatG: 20,
      estimatedCarbsG: 5,
    );
  }
}

/// M18 Task3 测试用：复合菜（宫保鸡丁）+ mid=0 防除零兜底
/// mid=0 时 computeCompositeLookupHit 返回 null，走组分累加兜底
class _FakeCompositeMidZeroProvider implements VisionProvider {
  @override
  String get name => 'FakeCompositeMidZero';

  @override
  String get promptVersion => 'v1.10';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    return const VisionRecognitionResult(
      dishName: '宫保鸡丁',
      estimatedWeightGLow: 0,
      estimatedWeightGMid: 0, // mid=0 防除零
      estimatedWeightGHigh: 0,
      foodComponents: [
        FoodComponent(name: '鸡肉', estimatedG: 150),
        FoodComponent(name: '花生', estimatedG: 30),
      ],
      cookingMethod: 'stir-fry',
      isSingleItem: false,
      confidence: 0.9,
      promptVersion: 'v1.10',
      estimatedCalories: 340, // 任意值，mid=0 时 AI 路径返回 null
      estimatedProteinG: 35,
      estimatedFatG: 20,
      estimatedCarbsG: 5,
    );
  }
}
