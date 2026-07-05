// Sprint 2 端到端集成测试
//
// 模拟用户完整一天的使用流程，覆盖 Sprint 2 成功标准：
// 1. 录入档案 → 看板读宏量目标
// 2. 拍照记录早餐（Fake Qwen-VL）→ 今日记录按餐次分组
// 3. 手动录入午餐 → 今日记录 2 条不同餐次
// 4. 编辑份量 → 按比例重算营养素
// 5. 删除 meal_log → recognition_feedback 级联删除
// 6. 食物库搜索 + listFrequent 按引用次数
// 7. 体重记录 → getRange 按日期升序
// 8. insight 同周期去重
// 9. JSON 导出 → 新 DB 导入 → 数据一致 + 外键完整
// 10. 离线入队 → processPending → 写 meal_log
//
// 沙箱不可验证：connectivity_plus 真实网络切换 / image_picker / fl_chart 渲染
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/backup/json_exporter.dart';
import 'package:eatwise/data/backup/json_importer.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/insight_repository.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/data/repositories/pending_recognition_repository.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/data/repositories/recognition_feedback_repository.dart';
import 'package:eatwise/data/repositories/weight_log_repository.dart';
import 'package:eatwise/features/offline/offline_queue_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟 Qwen-VL 识别苹果（单品）
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

void main() {
  late EatWiseDatabase db;
  late Directory tmpDir;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    tmpDir = await Directory.systemTemp.createTemp('sprint2_e2e_');
  });

  tearDown(() async {
    await db.close();
    await tmpDir.delete(recursive: true);
  });

  Future<String> writeFakeImage(String name) async {
    final file = File('${tmpDir.path}/$name.jpg');
    await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]);
    return file.path;
  }

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

  test('Sprint 2 全流程：档案→拍照→手动录入→编辑→删除→体重→汇总→导出导入→离线回补',
      () async {
    // ========== 1. profile 录入 → 看板读宏量目标 ==========
    final profileRepo = ProfileRepository(db);
    await profileRepo.update(
      weightKg: 70,
      proteinGPerKg: 1.5,
      fatGPerKg: 0.9,
      dailyCalorieTarget: 1800,
    );
    final profile = await profileRepo.get();
    expect(profile.weightKg, 70);
    expect(profile.dailyCalorieTarget, 1800);
    expect(profile.proteinGPerKg * profile.weightKg, 105); // 蛋白目标 105g

    // ========== 2. 拍照记录早餐（Fake Qwen 识别苹果）==========
    final appleId = await seedApple();
    final imgPath = await writeFakeImage('breakfast_apple');

    // 模拟 controller 的识别流程（不调真实 image_picker）
    final fakeProvider = _FakeAppleProvider();
    final visionResult = await fakeProvider.recognize('fake_base64');
    final lookup = NutritionLookup(FoodItemRepository(db));
    final nutrition = await lookup.lookupSingleItem(
      dishName: visionResult.dishName,
      servingG: visionResult.estimatedWeightGMid,
    );
    expect(nutrition, isNotNull);
    expect(nutrition!.foodItemId, appleId);

    final mealRepo = MealLogRepository(db);
    final mealId1 = await mealRepo.insertMealLog(
      date: '2026-07-02',
      mealType: 'breakfast',
      foodItemId: nutrition.foodItemId,
      actualServingG: visionResult.estimatedWeightGMid,
      actualCalories: nutrition.calories,
      actualProteinG: nutrition.proteinG,
      actualFatG: nutrition.fatG,
      actualCarbsG: nutrition.carbsG,
      originalImagePath: imgPath,
      recognitionConfidence: visionResult.confidence,
    );

    // 今日记录应有 1 条早餐
    var todayMeals = await mealRepo.getMealsByDate('2026-07-02');
    expect(todayMeals.length, 1);
    expect(todayMeals.first.mealType, 'breakfast');

    // 看板宏量：苹果 180g → 93.6 kcal
    final macros = await mealRepo.getMacrosByDate('2026-07-02');
    expect(macros.calories, closeTo(93.6, 0.1));

    // ========== 3. 手动录入午餐（自定义食物存库）==========
    final foodRepo = FoodItemRepository(db);
    final riceId = await foodRepo.insertManual(
      name: '米饭',
      caloriesPer100g: 116,
      proteinPer100g: 2.6,
      fatPer100g: 0.3,
      carbsPer100g: 25.9,
    );
    expect(riceId, greaterThan(0));

    await mealRepo.insertMealLog(
      date: '2026-07-02',
      mealType: 'lunch',
      foodItemId: riceId,
      actualServingG: 200,
      actualCalories: 232,
      actualProteinG: 5.2,
      actualFatG: 0.6,
      actualCarbsG: 51.8,
    );

    todayMeals = await mealRepo.getMealsByDate('2026-07-02');
    expect(todayMeals.length, 2);
    // 按餐次分组
    final byMealType = <String, List<MealLog>>{};
    for (final m in todayMeals) {
      byMealType.putIfAbsent(m.mealType, () => []).add(m);
    }
    expect(byMealType['breakfast']?.length, 1);
    expect(byMealType['lunch']?.length, 1);

    // ========== 4. 编辑早餐份量（180g → 200g，按比例重算）==========
    final ratio = 200 / 180;
    await mealRepo.updateMealLog(
      id: mealId1,
      actualServingG: 200,
      actualCalories: nutrition.calories * ratio,
      actualProteinG: nutrition.proteinG * ratio,
      actualFatG: nutrition.fatG * ratio,
      actualCarbsG: nutrition.carbsG * ratio,
    );
    final updated = await (db.mealLogs.select()
          ..where((m) => m.id.equals(mealId1)))
        .getSingle();
    expect(updated.actualServingG, 200);
    expect(updated.actualCalories, closeTo(104.0, 0.1)); // 93.6 × (200/180)

    // ========== 5. 删除 meal_log → recognition_feedback 级联删除 ==========
    final feedbackRepo = RecognitionFeedbackRepository(db);
    await feedbackRepo.insert(
      mealLogId: mealId1,
      isCorrect: true,
      promptVersion: 'v1.0',
    );
    expect(await feedbackRepo.hasFeedback(mealId1), true);

    await mealRepo.deleteMealLog(mealId1);
    expect(await feedbackRepo.hasFeedback(mealId1), false); // 级联删除

    // ========== 6. 食物库搜索 + listFrequent 按引用次数 ==========
    final searchResults = await foodRepo.searchByName('米');
    expect(searchResults.length, 1);
    expect(searchResults.first.name, '米饭');

    // listFrequent：米饭被 meal_log 引用 1 次，苹果 0 次（mealId1 已删）
    final frequent = await foodRepo.listFrequent();
    expect(frequent.first.name, '米饭'); // 引用次数最高

    // ========== 7. 体重记录 → getRange 按日期升序 ==========
    final weightRepo = WeightLogRepository(db);
    await weightRepo.insert(date: '2026-07-02', weightKg: 70.0);
    await weightRepo.insert(date: '2026-07-01', weightKg: 70.2);
    final weights = await weightRepo.getRange('2026-07-01', '2026-07-02');
    expect(weights.length, 2);
    expect(weights.first.date, '2026-07-01'); // 升序

    // ========== 8. insight 同周期去重 ==========
    final insightRepo = InsightRepository(db);
    await insightRepo.insert(
      periodType: 'weekly',
      periodStart: '2026-06-30',
      periodEnd: '2026-07-06',
      summaryText: '旧汇总',
    );
    await insightRepo.regenerate(
      periodType: 'weekly',
      periodStart: '2026-06-30',
      periodEnd: '2026-07-06',
      summaryText: '新汇总',
    );
    final allInsights = await db.insightSummaries.select().get();
    expect(allInsights.length, 1); // 去重
    expect(allInsights.first.summaryText, '新汇总');

    // ========== 9. JSON 导出 → 新 DB 导入 → 数据一致 + 外键完整 ==========
    final exporter = JsonExporter(db);
    final jsonStr = await exporter.exportAsString();

    final dstDb = EatWiseDatabase(NativeDatabase.memory());
    final stats = await JsonImporter(dstDb).importFromString(jsonStr);

    expect(stats.foodItems, 2); // 苹果 + 米饭
    expect(stats.mealLogs, 1); // 只剩午餐（早餐已删）
    expect(stats.weightLogs, 2);
    expect(stats.insights, 1);

    // 外键完整：导入的 meal_log.food_item_id 在 food_items 表存在
    final dstMeals = await dstDb.mealLogs.select().get();
    final dstFoods = await dstDb.foodItems.select().get();
    final foodIds = dstFoods.map((f) => f.id).toSet();
    expect(foodIds.contains(dstMeals.first.foodItemId), isTrue);

    await dstDb.close();

    // ========== 10. 离线入队 → processPending → 写 meal_log ==========
    final pendingRepo = PendingRecognitionRepository(db);
    final offlineImg = await writeFakeImage('offline_dinner');
    await pendingRepo.enqueue(
      imagePath: offlineImg,
      mealType: 'dinner',
      date: '2026-07-02',
    );
    expect(await pendingRepo.countPending(), 1);

    // 模拟网络恢复 → processPending
    final offlineController = OfflineQueueController(
      db: db,
      visionProvider: _FakeAppleProvider(),
      nutritionLookup: NutritionLookup(FoodItemRepository(db)),
    );
    await offlineController.processPending();

    // pending 应清空，新增 1 条 dinner meal_log
    expect(await pendingRepo.countPending(), 0);
    final dinnerMeals = await (db.mealLogs.select()
          ..where((m) => m.mealType.equals('dinner')))
        .get();
    expect(dinnerMeals.length, 1);
    expect(dinnerMeals.first.mealType, 'dinner');
    expect(dinnerMeals.first.actualCalories, greaterThan(0));
  });

  test('离线重试 5 次后标记 failed（不再 pending）', () async {
    final pendingRepo = PendingRecognitionRepository(db);
    final imgPath = await writeFakeImage('retry_test');
    final id = await pendingRepo.enqueue(
      imagePath: imgPath,
      mealType: 'breakfast',
      date: '2026-07-02',
    );

    // 用抛异常的 Fake provider 模拟连续失败
    final controller = OfflineQueueController(
      db: db,
      visionProvider: _ThrowingProvider(),
      nutritionLookup: NutritionLookup(FoodItemRepository(db)),
    );

    // 第 1-4 次：retryCount 0→4，仍 pending
    for (var i = 1; i <= 4; i++) {
      await controller.processPending();
      expect(await pendingRepo.countPending(), 1);
    }

    // 第 5 次：retryCount 4→5，转 failed
    await controller.processPending();
    expect(await pendingRepo.countPending(), 0); // 不再 pending

    final row = await (db.pendingRecognitions.select()
          ..where((p) => p.id.equals(id)))
        .getSingle();
    expect(row.status, 'failed');
    expect(row.retryCount, 5);
  });
}

class _ThrowingProvider implements VisionProvider {
  @override
  String get name => 'Throwing';

  @override
  String get promptVersion => 'v1.0';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    throw Exception('模拟识别失败');
  }
}
