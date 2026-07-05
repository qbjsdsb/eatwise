import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/core/config/secure_config_store.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/pending_recognition_repository.dart';
import 'package:eatwise/features/offline/offline_queue_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  test('markFailed 重试 5 次后标记 failed（不再 pending）', () async {
    final imgPath = await writeFakeImage('a');
    final id = await pendingRepo.enqueue(
        imagePath: imgPath, mealType: 'breakfast', date: '2026-07-02');

    // 第 1-4 次失败：retryCount 0→4，status 仍 pending
    for (var i = 1; i <= 4; i++) {
      await pendingRepo.markFailed(id, '网络超时 $i');
      expect(await pendingRepo.countPending(), 1);
      var row = await (db.pendingRecognitions.select()
            ..where((p) => p.id.equals(id)))
          .getSingle();
      expect(row.retryCount, i);
      expect(row.status, 'pending');
    }

    // 第 5 次失败：retryCount 4→5，status 转 failed（不再 pending）
    await pendingRepo.markFailed(id, '网络超时 5');
    expect(await pendingRepo.countPending(), 0); // 不再 pending
    var row = await (db.pendingRecognitions.select()
          ..where((p) => p.id.equals(id)))
        .getSingle();
    expect(row.retryCount, 5);
    expect(row.status, 'failed');
    expect(row.errorMessage, '网络超时 5');
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

  // M11 修复：后台回补成功计入月度识别次数
  // 原实现：OfflineQueueController.processPending 成功 markDone 时不调
  //   incrementMonthlyCount，设置页"本月识别次数"偏低，T43 计数与实际 token 消耗脱节。
  // 修复：构造器加可选 SecureConfigStore，markDone 前 best-effort 计数
  //   （try-catch 不影响主流程，与 recognize_controller 模式一致）。
  group('M11 后台回补计入月度识别次数', () {
    late SecureConfigStore store;

    setUp(() {
      // 沙箱无平台通道，注入内存 mock 平台实现
      FlutterSecureStorage.setMockInitialValues({});
      store = SecureConfigStore();
    });

    test('M11-RED: 回补成功时调 incrementMonthlyCount（计数 +1）', () async {
      await seedApple(); // 苹果已入库，Fake provider 会识别为苹果
      final imgPath = await writeFakeImage('apple_m11');
      await pendingRepo.enqueue(
          imagePath: imgPath, mealType: 'breakfast', date: '2026-07-02');

      final controller = OfflineQueueController(
        db: db,
        visionProvider: _FakeAppleProvider(),
        nutritionLookup: NutritionLookup(FoodItemRepository(db)),
        secureConfigStore: store, // M11 新增参数
      );
      await controller.processPending();

      // pending 应清空（回补成功）
      expect(await pendingRepo.countPending(), 0);
      // M11 关键断言：月度计数 +1（与前台 recognize_controller 一致）
      final now = DateTime.now();
      final count = await store.getMonthlyCount(now.year, now.month);
      expect(count, 1,
          reason: '后台回补成功应计入月度识别次数，否则设置页计数偏低');
    });

    test('M11: 不传 secureConfigStore 时向后兼容（不计数也不崩溃）', () async {
      await seedApple();
      final imgPath = await writeFakeImage('apple_no_store');
      await pendingRepo.enqueue(
          imagePath: imgPath, mealType: 'breakfast', date: '2026-07-02');

      // 不传 secureConfigStore（旧调用方 background_dispatcher 未传）
      final controller = OfflineQueueController(
        db: db,
        visionProvider: _FakeAppleProvider(),
        nutritionLookup: NutritionLookup(FoodItemRepository(db)),
      );
      await controller.processPending();

      // 回补仍成功（向后兼容，计数可选不影响主流程）
      expect(await pendingRepo.countPending(), 0);
      final meals = await db.mealLogs.select().get();
      expect(meals.length, 1);
    });

    test('M11: 回补失败时 不调 incrementMonthlyCount（与前台一致）', () async {
      // 前台 recognize_controller：离线入队/L3 转手动不计数
      // 后台回补失败（识别异常）也不应计数，否则计数偏高
      final imgPath = await writeFakeImage('fail_m11');
      await pendingRepo.enqueue(
          imagePath: imgPath, mealType: 'breakfast', date: '2026-07-02');

      final controller = OfflineQueueController(
        db: db,
        visionProvider: _ThrowingProvider(),
        nutritionLookup: NutritionLookup(FoodItemRepository(db)),
        secureConfigStore: store,
      );
      await controller.processPending();

      // 回补失败（retryCount +1，仍 pending）
      expect(await pendingRepo.countPending(), 1);
      // M11 关键断言：失败时计数不增加
      final now = DateTime.now();
      final count = await store.getMonthlyCount(now.year, now.month);
      expect(count, 0,
          reason: '回补失败不应计数（与前台 recognize_controller 一致）');
    });

    test('M11: 多条 pending 全部成功时计数 +N（每条计一次）', () async {
      await seedApple();
      final imgPath = await writeFakeImage('apple_multi');
      await pendingRepo.enqueue(
          imagePath: imgPath, mealType: 'breakfast', date: '2026-07-02');
      await pendingRepo.enqueue(
          imagePath: imgPath, mealType: 'lunch', date: '2026-07-02');
      await pendingRepo.enqueue(
          imagePath: imgPath, mealType: 'dinner', date: '2026-07-02');

      final controller = OfflineQueueController(
        db: db,
        visionProvider: _FakeAppleProvider(),
        nutritionLookup: NutritionLookup(FoodItemRepository(db)),
        secureConfigStore: store,
      );
      await controller.processPending();

      // 3 条全部成功
      expect(await pendingRepo.countPending(), 0);
      final meals = await db.mealLogs.select().get();
      expect(meals.length, 3);
      // M11 关键断言：计数 +3（每条计一次）
      final now = DateTime.now();
      final count = await store.getMonthlyCount(now.year, now.month);
      expect(count, 3,
          reason: '3 条 pending 全部成功应计数 +3');
    });
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
