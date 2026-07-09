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

  // M16.4 P2-4: fire-and-forget processPending 上报 Sentry
  // 原实现：start() 内 processPending().catchError((_) {}) 吞异常，DB 写失败 /
  //   food_item upsert 失败无可观测性，线上问题无法定位。
  // 修复：注入 onError 回调（生产默认 Sentry.captureException），outer catch +
  //   catchError 都 best-effort 上报，保留 fire-and-forget 语义（不阻塞调用方）。
  group('M16.4-P2-4 processPending 异常上报 onError（best-effort Sentry）', () {
    test('processPending 内部异常时通过 onError 上报（生产默认 Sentry.captureException）',
        () async {
      // 先入队一条 pending（用 _ThrowingProvider 触发 per-item catch）
      final imgPath = await writeFakeImage('p24_fail');
      await pendingRepo.enqueue(
          imagePath: imgPath, mealType: 'breakfast', date: '2026-07-02');

      // 用 mock onError 回调捕获异常（生产环境默认 Sentry.captureException）
      final errors = <Object>[];
      final controller = OfflineQueueController(
        db: db,
        visionProvider: _ThrowingProvider(),
        nutritionLookup: NutritionLookup(FoodItemRepository(db)),
        onError: (e, st) => errors.add(e),
      );

      // 关闭 db：markFailed / listPending 抛异常 → 逃逸 per-item catch → outer catch → onError
      await db.close();

      await controller.processPending();

      // 关键断言：异常通过 onError 上报（生产环境默认 Sentry.captureException）
      expect(errors, isNotEmpty,
          reason: 'processPending 内部异常应通过 onError 上报 Sentry，'
              '否则 DB 写失败 / food_item upsert 失败无可观测性');
    });

    test('不传 onError 时向后兼容（默认走 Sentry.captureException，不崩溃）', () async {
      // 旧调用方 / Provider 未传 onError（默认 Sentry.captureException）
      final controller = OfflineQueueController(
        db: db,
        visionProvider: _FakeAppleProvider(),
        nutritionLookup: NutritionLookup(FoodItemRepository(db)),
      );

      // 关闭 db 触发 outer catch（默认 onError 调 Sentry.captureException，
      // 测试环境 Sentry 未初始化，SDK 内部 no-op 不抛异常）
      await db.close();

      // 不应抛异常（fire-and-forget 语义 + best-effort 上报）
      await controller.processPending();
    });
  });

  // M11 修复：后台回补成功计入月度识别次数
  // 原实现：OfflineQueueController.processPending 成功 markDone 时不调
  //   incrementMonthlyCount，设置页"本月识别次数"偏低，T43 计数与实际 token 消耗脱节。
  // 修复：构造器加可选 SecureConfigStore，markDone 前 best-effort 计数
  //   （try-catch 不影响主流程，与 recognize_controller 模式一致）。
  //
  // 双指标扩展：回补成功时同时调 incrementMonthlyCount（识别次数）和
  //   incrementMonthlyApiCalls（API 调用次数，每次成功视觉调用 +1）。
  //   识别次数 = 用户视角成功识别；API 调用次数 = 计费视角实际消耗。
  //   估算费用基于 API 调用次数 × 0.002 元（Qwen3-VL-Flash）。
  group('M11 后台回补计入月度识别次数', () {
    late SecureConfigStore store;

    setUp(() {
      // 沙箱无平台通道，注入内存 mock 平台实现
      FlutterSecureStorage.setMockInitialValues({});
      store = SecureConfigStore();
    });

    test('M11-RED: 回补成功时调 incrementMonthlyCount + incrementMonthlyApiCalls（双指标 +1）',
        () async {
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
      // M11 关键断言：双指标均 +1
      // 识别次数：用户视角成功识别 1 次
      // API 调用次数：主调用成功 1 次（无重试/L2 切备）
      final now = DateTime.now();
      final count = await store.getMonthlyCount(now.year, now.month);
      final apiCalls = await store.getMonthlyApiCalls(now.year, now.month);
      expect(count, 1,
          reason: '后台回补成功应计入月度识别次数，否则设置页计数偏低');
      expect(apiCalls, 1,
          reason: '后台回补成功应计入 API 调用次数（计费视角），'
              '否则估算费用偏低');
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

    test('M11: 回补失败时 不调 incrementMonthlyCount 也不调 incrementMonthlyApiCalls',
        () async {
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
      // M11 关键断言：失败时双指标均不增加
      final now = DateTime.now();
      final count = await store.getMonthlyCount(now.year, now.month);
      final apiCalls = await store.getMonthlyApiCalls(now.year, now.month);
      expect(count, 0,
          reason: '回补失败不应计数（与前台 recognize_controller 一致）');
      expect(apiCalls, 0,
          reason: '回补失败不应计入 API 调用次数（视觉调用未成功，未消耗付费 API）');
    });

    test('M11: 多条 pending 全部成功时双指标均 +N（每条计一次）', () async {
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
      // M11 关键断言：双指标均 +3（每条计一次）
      final now = DateTime.now();
      final count = await store.getMonthlyCount(now.year, now.month);
      final apiCalls = await store.getMonthlyApiCalls(now.year, now.month);
      expect(count, 3, reason: '3 条 pending 全部成功应识别次数 +3');
      expect(apiCalls, 3, reason: '3 条 pending 全部成功应 API 调用次数 +3');
    });
  });

  // M16.8 Task 7：离线回补查库命中 + AI 偏差大时与前台一致——
  // 用 AI 反算 per100g 更新库 + meal_log 记 AI 估算值。
  // 原实现：查库命中分支直接用 nutrition.* 原值（库 per100g × mid / 100），
  // 忽略 AI 估算，前后台行为分叉。
  test('M16.8: 离线回补查库命中 + AI 偏差大时用 AI 估算 + 更新库 per100g', () async {
    // 库"番茄炒蛋" per100g=80（脏数据），AI 估 200g/250kcal
    // 离线回补应与前台一致：actualCalories=250, food_item.caloriesPer100g=125
    await db.into(db.foodItems).insert(
          FoodItemsCompanion.insert(
            name: '番茄炒蛋',
            defaultServingG: 100,
            caloriesPer100g: 80, // 脏库
            proteinPer100g: 6,
            fatPer100g: 10,
            carbsPer100g: 12,
            source: 'china_fct',
            sourceVersion: 'test',
            createdAt: 0,
          ),
        );
    final imgPath = await writeFakeImage('m168_tomato_egg');
    await pendingRepo.enqueue(
        imagePath: imgPath, mealType: 'lunch', date: '2026-07-02');

    final controller = OfflineQueueController(
      db: db,
      visionProvider: _FakeTomatoEggProvider(),
      nutritionLookup: NutritionLookup(FoodItemRepository(db)),
    );
    await controller.processPending();

    // pending 应清空（回补成功）
    expect(await pendingRepo.countPending(), 0);

    // M16.8 关键断言 1：meal_log 记 AI 估算值 250（不是库值 160）
    final meals = await db.mealLogs.select().get();
    expect(meals.length, 1);
    expect(meals.first.actualCalories, closeTo(250, 0.5),
        reason: '查库命中 + AI 偏差大时 meal_log 应记 AI 估算值（与前台一致）');

    // M16.8 关键断言 2：库 per100g 应被 AI 反算值 125 更新
    final food = await (db.foodItems.select()
          ..where((f) => f.name.equals('番茄炒蛋')))
        .getSingle();
    expect(food.caloriesPer100g, closeTo(125, 0.5),
        reason: '库 per100g 应被 AI 反算值更新（纠正脏库）');
  });

  // ============================================================
  // M24 B3 安全网测试：守护 AI 兜底哨兵替换 + markFailed 关键路径
  // 拆分 processPending 前必须建立安全网，确保哨兵替换（硬约束 2）+ per100g 反算
  // （硬约束 4）逻辑在拆分前后行为零变更
  // 覆盖原 processPending 4 个未测分支：
  //   - 单品库未命中 + AI 估算 → 哨兵分支 + upsertAiRecognized 替换 foodItemId=0
  //   - 单品库未命中 + 无 AI 估算 → markFailed（v1.4 行为）
  //   - 复合菜组分全 miss + AI 估算 → AI 兜底哨兵分支
  //   - 复合菜组分全 miss + 无 AI 估算 → markFailed
  // ============================================================

  group('M24 B3 安全网：AI 兜底哨兵替换路径', () {
    test('单品库未命中 + AI 估算 → 哨兵分支 + upsertAiRecognized 替换 foodItemId=0',
        () async {
      // 不种种子（库里没有"蓝莓蛋糕"），强制走 L219-250 哨兵分支
      final imgPath = await writeFakeImage('blueberry_cake');
      await pendingRepo.enqueue(
          imagePath: imgPath, mealType: 'breakfast', date: '2026-07-02');

      final controller = OfflineQueueController(
        db: db,
        visionProvider: _FakeBlueberryCakeProvider(),
        nutritionLookup: NutritionLookup(FoodItemRepository(db)),
      );
      await controller.processPending();

      // pending 应清空（哨兵替换 + 写 meal_log + markDone）
      expect(await pendingRepo.countPending(), 0);

      final meals = await db.mealLogs.select().get();
      expect(meals.length, 1);
      // 硬约束 2 关键断言：food_item_id 不能是 0（哨兵已被 upsert 替换为真实 id）
      expect(meals.first.foodItemId, greaterThan(0),
          reason: '哨兵 foodItemId=0 必须由 upsertAiRecognized 替换为真实 id，'
              '否则 meal_log.food_item_id 非空外键约束违规崩溃');

      // 验证：meal_log.food_item_id 指向真实 food_item 行
      final foodItem = await (db.foodItems.select()
            ..where((f) => f.id.equals(meals.first.foodItemId)))
          .getSingle();
      expect(foodItem.name, '蓝莓蛋糕');
      // 硬约束 4 关键断言：per100g 反算基于 estimatedWeightGMid（150g）
      // AI 估 300kcal/150g → per100g=200
      expect(foodItem.caloriesPer100g, closeTo(200, 0.5),
          reason: 'per100g 反算应基于 estimatedWeightGMid=150');
      // actualCalories = per100g * mid / 100 = 200 * 150 / 100 = 300
      expect(meals.first.actualCalories, closeTo(300, 0.5));

      // pending 标记 done 且 resultFoodItemId 与 meal_log 一致
      final all = await db.pendingRecognitions.select().get();
      expect(all.first.status, 'done');
      expect(all.first.resultFoodItemId, meals.first.foodItemId);
    });

    test('单品库未命中 + 无 AI 估算 → markFailed（不写 meal_log）', () async {
      // 不种种子 + Provider 无 estimatedCalories（旧 prompt）
      final imgPath = await writeFakeImage('unknown_no_ai');
      await pendingRepo.enqueue(
          imagePath: imgPath, mealType: 'breakfast', date: '2026-07-02');

      final controller = OfflineQueueController(
        db: db,
        visionProvider: _FakeUnknownNoAiProvider(),
        nutritionLookup: NutritionLookup(FoodItemRepository(db)),
      );
      await controller.processPending();

      // markFailed 1 次：retryCount=1，仍 pending（非 permanent）
      expect(await pendingRepo.countPending(), 1);
      final meals = await db.mealLogs.select().get();
      expect(meals.length, 0, reason: '库未命中且无 AI 估算不应写 meal_log');

      final all = await db.pendingRecognitions.select().get();
      expect(all.first.retryCount, 1);
      expect(all.first.errorMessage,
          contains('AI 无估算且库未命中，需手动录入或改菜名重试'));
    });

    test('复合菜组分全 miss + AI 估算 → AI 兜底哨兵分支 + upsert 替换', () async {
      // 不种对应组分种子（组分名"鳕鱼"+"芝士"库中不存在），强制走 L266-321 全 miss + AI 兜底
      final imgPath = await writeFakeImage('composite_full_miss_ai');
      await pendingRepo.enqueue(
          imagePath: imgPath, mealType: 'dinner', date: '2026-07-02');

      final controller = OfflineQueueController(
        db: db,
        visionProvider: _FakeCompositeFullMissAiProvider(),
        nutritionLookup: NutritionLookup(FoodItemRepository(db)),
      );
      await controller.processPending();

      expect(await pendingRepo.countPending(), 0);

      final meals = await db.mealLogs.select().get();
      expect(meals.length, 1);
      // 硬约束 2：哨兵 0 必须被替换
      expect(meals.first.foodItemId, greaterThan(0),
          reason: '复合菜 AI 兜底哨兵分支也必须 upsert 替换 foodItemId=0');
      expect(meals.first.actualCalories, greaterThan(0));

      // food_item 应被 upsert 创建（"芝士鳕鱼"）
      final foodItem = await (db.foodItems.select()
            ..where((f) => f.id.equals(meals.first.foodItemId)))
          .getSingle();
      expect(foodItem.name, '芝士鳕鱼');

      // pending 标记 done
      final all = await db.pendingRecognitions.select().get();
      expect(all.first.status, 'done');
      expect(all.first.resultFoodItemId, meals.first.foodItemId);
    });

    test('复合菜组分全 miss + 无 AI 估算 → markFailed（不写 meal_log）', () async {
      final imgPath = await writeFakeImage('composite_full_miss_no_ai');
      await pendingRepo.enqueue(
          imagePath: imgPath, mealType: 'dinner', date: '2026-07-02');

      final controller = OfflineQueueController(
        db: db,
        visionProvider: _FakeCompositeFullMissNoAiProvider(),
        nutritionLookup: NutritionLookup(FoodItemRepository(db)),
      );
      await controller.processPending();

      // markFailed 1 次：仍 pending
      expect(await pendingRepo.countPending(), 1);
      final meals = await db.mealLogs.select().get();
      expect(meals.length, 0, reason: '复合菜组分全 miss 且无 AI 估算不应写 meal_log');

      final all = await db.pendingRecognitions.select().get();
      expect(all.first.retryCount, 1);
      expect(all.first.errorMessage,
          contains('复合菜组分全 miss 且 AI 无估算，需手动录入或改菜名重试'));
    });
  });
}

/// M16.8 测试用：模拟识别"番茄炒蛋"（200g/250kcal），库 per100g=80 偏差大
class _FakeTomatoEggProvider implements VisionProvider {
  @override
  String get name => 'FakeTomatoEgg';

  @override
  String get promptVersion => 'v1.0';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    return const VisionRecognitionResult(
      dishName: '番茄炒蛋',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      estimatedCalories: 250,
      estimatedProteinG: 10,
      estimatedFatG: 15,
      estimatedCarbsG: 20,
      foodComponents: [],
      cookingMethod: 'stir-fry',
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.0',
    );
  }
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

/// M24 B3 安全网用：单品库未命中 + AI 估算（蓝莓蛋糕 150g/300kcal）
/// 触发 L219-250 哨兵分支：CalibratedNutritionCalculator.compute 哨兵路径
/// + upsertAiRecognized 替换 foodItemId=0
/// per100g 反算：300 * 100 / 150 = 200（验证硬约束 4：基于 estimatedWeightGMid）
class _FakeBlueberryCakeProvider implements VisionProvider {
  @override
  String get name => 'FakeBlueberryCake';

  @override
  String get promptVersion => 'v1.10';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    return const VisionRecognitionResult(
      dishName: '蓝莓蛋糕',
      estimatedWeightGLow: 130,
      estimatedWeightGMid: 150,
      estimatedWeightGHigh: 170,
      estimatedCalories: 300,
      estimatedProteinG: 5,
      estimatedFatG: 12,
      estimatedCarbsG: 45,
      foodComponents: [],
      cookingMethod: 'bake',
      isSingleItem: true,
      confidence: 0.85,
      promptVersion: 'v1.10',
    );
  }
}

/// M24 B3 安全网用：单品库未命中 + 无 AI 估算（旧 prompt）
/// 触发 L251-258 markFailed 分支
class _FakeUnknownNoAiProvider implements VisionProvider {
  @override
  String get name => 'FakeUnknownNoAi';

  @override
  String get promptVersion => 'v1.0';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    return const VisionRecognitionResult(
      dishName: '神秘菜品',
      estimatedWeightGLow: 100,
      estimatedWeightGMid: 120,
      estimatedWeightGHigh: 140,
      foodComponents: [],
      cookingMethod: 'unknown',
      isSingleItem: true,
      confidence: 0.5,
      promptVersion: 'v1.0',
    );
  }
}

/// M24 B3 安全网用：复合菜组分全 miss + AI 估算（芝士鳕鱼，组分不在库中）
/// 触发 L266-321 全 miss + AI 兜底哨兵分支
class _FakeCompositeFullMissAiProvider implements VisionProvider {
  @override
  String get name => 'FakeCompositeFullMissAi';

  @override
  String get promptVersion => 'v1.10';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    return const VisionRecognitionResult(
      dishName: '芝士鳕鱼',
      estimatedWeightGLow: 180,
      estimatedWeightGMid: 200,
      estimatedWeightGHigh: 220,
      estimatedCalories: 400,
      estimatedProteinG: 30,
      estimatedFatG: 20,
      estimatedCarbsG: 10,
      foodComponents: [
        FoodComponent(name: '鳕鱼', estimatedG: 150),
        FoodComponent(name: '芝士', estimatedG: 50),
      ],
      cookingMethod: 'bake',
      isSingleItem: false,
      confidence: 0.85,
      promptVersion: 'v1.10',
    );
  }
}

/// M24 B3 安全网用：复合菜组分全 miss + 无 AI 估算（旧 prompt）
/// 触发 L322-328 markFailed 分支
class _FakeCompositeFullMissNoAiProvider implements VisionProvider {
  @override
  String get name => 'FakeCompositeFullMissNoAi';

  @override
  String get promptVersion => 'v1.0';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    return const VisionRecognitionResult(
      dishName: '神秘复合菜',
      estimatedWeightGLow: 200,
      estimatedWeightGMid: 250,
      estimatedWeightGHigh: 300,
      foodComponents: [
        FoodComponent(name: '未知食材A', estimatedG: 150),
        FoodComponent(name: '未知食材B', estimatedG: 100),
      ],
      cookingMethod: 'stew',
      isSingleItem: false,
      confidence: 0.5,
      promptVersion: 'v1.0',
    );
  }
}
