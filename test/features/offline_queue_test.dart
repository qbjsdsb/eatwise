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

/// Sprint 2 T14 离线队列测试
/// - PendingRecognitionRepository: enqueue/listPending/markDone/markFailed/countPending
/// - OfflineQueueController.processPending: 完整回补流程 + 重试上限 + 图片缺失
///
/// connectivity_plus 真实网络切换是平台插件，沙箱无法模拟，标注为"已知不可验证项"
/// （沙箱可验证：业务逻辑层全部覆盖）
void main() {
  late EatWiseDatabase db;
  late PendingRecognitionRepository pendingRepo;
  late Directory tmpDir;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    pendingRepo = PendingRecognitionRepository(db);
    tmpDir = await Directory.systemTemp.createTemp('offline_queue_test_');
  });

  tearDown(() async {
    await db.close();
    await tmpDir.delete(recursive: true);
  });

  /// 写一个临时图片文件（模拟离线拍照保存的图片）
  Future<String> writeFakeImage(String name) async {
    final file = File('${tmpDir.path}/$name.jpg');
    await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]); // JPEG 头
    return file.path;
  }

  /// 插入食物种子（查库回填用）
  Future<int> seedApple() async {
    return db.into(db.foodItems).insert(
          FoodItemsCompanion.insert(
            name: '苹果',
            defaultServingG: 100,
            caloriesPer100g: 52,
            proteinPer100g: 0.3,
            fatPer100g: 0.2,
            carbsPer100g: 13.8,
            source: 'manual',
            sourceVersion: 'test_v1',
            createdAt: 0,
          ),
        );
  }

  test('enqueue + listPending + countPending', () async {
    final imgPath = await writeFakeImage('a');
    await pendingRepo.enqueue(
        imagePath: imgPath, mealType: 'breakfast', date: '2026-07-02');
    await pendingRepo.enqueue(
        imagePath: imgPath, mealType: 'lunch', date: '2026-07-02');

    final pending = await pendingRepo.listPending();
    expect(pending.length, 2);
    expect(pending.first.mealType, 'breakfast'); // FIFO 升序
    expect(pending.last.mealType, 'lunch');

    expect(await pendingRepo.countPending(), 2);
  });

  test('markDone 标记成功', () async {
    final foodId = await seedApple();
    final imgPath = await writeFakeImage('a');
    final id = await pendingRepo.enqueue(
        imagePath: imgPath, mealType: 'breakfast', date: '2026-07-02');

    await pendingRepo.markDone(id, foodId);
    expect(await pendingRepo.countPending(), 0); // 不再 pending
    final all = await db.pendingRecognitions.select().get();
    expect(all.first.status, 'done');
    expect(all.first.resultFoodItemId, foodId);
    expect(all.first.processedAt, isNotNull);
  });

  test('markFailed 重试 3 次后标记 failed（不再 pending）', () async {
    final imgPath = await writeFakeImage('a');
    final id = await pendingRepo.enqueue(
        imagePath: imgPath, mealType: 'breakfast', date: '2026-07-02');

    // 第 1 次失败：retryCount 0→1，status 仍 pending
    await pendingRepo.markFailed(id, '网络超时 1');
    expect(await pendingRepo.countPending(), 1);
    var row = await (db.pendingRecognitions.select()
          ..where((p) => p.id.equals(id)))
        .getSingle();
    expect(row.retryCount, 1);
    expect(row.status, 'pending');

    // 第 2 次失败：retryCount 1→2，status 仍 pending
    await pendingRepo.markFailed(id, '网络超时 2');
    expect(await pendingRepo.countPending(), 1);
    row = await (db.pendingRecognitions.select()
          ..where((p) => p.id.equals(id)))
        .getSingle();
    expect(row.retryCount, 2);
    expect(row.status, 'pending');

    // 第 3 次失败：retryCount 2→3，status 转 failed（不再 pending）
    await pendingRepo.markFailed(id, '网络超时 3');
    expect(await pendingRepo.countPending(), 0); // 不再 pending
    row = await (db.pendingRecognitions.select()
          ..where((p) => p.id.equals(id)))
        .getSingle();
    expect(row.retryCount, 3);
    expect(row.status, 'failed');
    expect(row.errorMessage, '网络超时 3');
  });

  test('processPending 图片不存在时 markFailed', () async {
    // 入队一个不存在的图片路径
    await pendingRepo.enqueue(
      imagePath: '${tmpDir.path}/not_exist.jpg',
      mealType: 'breakfast',
      date: '2026-07-02',
    );

    final controller = OfflineQueueController(
      db: db,
      visionProvider: _ThrowingProvider(),
      nutritionLookup: NutritionLookup(FoodItemRepository(db)),
    );
    await controller.processPending();

    expect(await pendingRepo.countPending(), 0); // 图片缺失直接 markFailed
    final all = await db.pendingRecognitions.select().get();
    expect(all.first.status, 'failed');
    expect(all.first.errorMessage, contains('图片文件不存在'));
  });

  test('processPending 完整回补：入队 → Fake 识别 → 写 meal_log → markDone',
      () async {
    await seedApple(); // 苹果已入库，Fake provider 会识别为苹果
    final imgPath = await writeFakeImage('apple');
    await pendingRepo.enqueue(
        imagePath: imgPath, mealType: 'breakfast', date: '2026-07-02');

    final controller = OfflineQueueController(
      db: db,
      visionProvider: _FakeAppleProvider(),
      nutritionLookup: NutritionLookup(FoodItemRepository(db)),
    );
    await controller.processPending();

    // pending 应清空
    expect(await pendingRepo.countPending(), 0);

    // meal_log 应有 1 条
    final meals = await db.mealLogs.select().get();
    expect(meals.length, 1);
    expect(meals.first.mealType, 'breakfast');
    expect(meals.first.actualCalories, greaterThan(0));

    // pending 记录应标记 done
    final all = await db.pendingRecognitions.select().get();
    expect(all.first.status, 'done');
    expect(all.first.resultFoodItemId, isNotNull);
  });

  test('processPending 识别异常时 markFailed（重试计数 +1）', () async {
    final imgPath = await writeFakeImage('fail');
    await pendingRepo.enqueue(
        imagePath: imgPath, mealType: 'breakfast', date: '2026-07-02');

    final controller = OfflineQueueController(
      db: db,
      visionProvider: _ThrowingProvider(),
      nutritionLookup: NutritionLookup(FoodItemRepository(db)),
    );
    await controller.processPending();

    // 异常 → markFailed（retryCount 0→1，仍 pending 待重试）
    expect(await pendingRepo.countPending(), 1);
    final all = await db.pendingRecognitions.select().get();
    expect(all.first.retryCount, 1);
    expect(all.first.errorMessage, contains('识别异常'));
  });
}

/// 模拟识别苹果的 Provider（单品，查库命中）
class _FakeAppleProvider implements VisionProvider {
  @override
  String get name => 'FakeApple';

  @override
  String get promptVersion => 'v1.0';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    return const VisionRecognitionResult(
      dishName: '苹果',
      estimatedWeightGLow: 150,
      estimatedWeightGMid: 180,
      estimatedWeightGHigh: 210,
      foodComponents: [],
      cookingMethod: 'raw',
      isSingleItem: true,
      confidence: 0.99,
      promptVersion: 'v1.0',
    );
  }
}

/// 模拟识别抛异常的 Provider（网络失败场景）
class _ThrowingProvider implements VisionProvider {
  @override
  String get name => 'Throwing';

  @override
  String get promptVersion => 'v1.0';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    throw Exception('识别异常：模拟网络失败');
  }
}
