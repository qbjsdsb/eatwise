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
    // 组分份量累加：鸡肉 150g + 花生 30g = 180g
    expect(mealLogs.first.actualServingG, 180);

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
