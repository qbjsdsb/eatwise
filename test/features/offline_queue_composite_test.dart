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
