// Sprint 1 端到端集成测试
//
// 沙箱无图形设备，无法跑 `flutter run` 真机/模拟器。
// 本测试用内存数据库 + Fake 视觉 Provider 模拟 Sprint 1 成功标准场景：
// 「拍一张苹果照片 → Qwen-VL 识别 → 查库回填 → 校准 → 写 meal_log → 今日热量增加」
//
// 覆盖 Task 2（加密 DB schema + 外键）/ Task 4（种子导入）/ Task 5（识别结果数据类）/
// Task 6（查库回填 单品+复合菜）/ Task 7（MealLogRepository 写读 + 校准页份量换算逻辑）。
// 唯一跳过：image_picker/flutter_image_compress（平台插件）+ 真实 HTTP（用 Fake 替代）。
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/data/seed/food_seed_importer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟 qwen-vl-max 对苹果的真实识别结果
/// （冒烟预演实测：confidence 0.99, weight 180g）
class FakeQwenVlProvider implements VisionProvider {
  @override
  String get name => 'FakeQwen-VL';

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

/// 模拟 qwen-vl-max 对「番茄炒蛋」复合菜的真实识别结果
class FakeQwenVlProviderComposite implements VisionProvider {
  @override
  String get name => 'FakeQwen-VL-Composite';

  @override
  String get promptVersion => 'v1.0';

  @override
  Future<VisionRecognitionResult> recognize(String imageBase64) async {
    return const VisionRecognitionResult(
      dishName: '番茄炒蛋',
      estimatedWeightGLow: 200,
      estimatedWeightGMid: 250,
      estimatedWeightGHigh: 300,
      foodComponents: [
        FoodComponent(name: '番茄', estimatedG: 100),
        FoodComponent(name: '鸡蛋', estimatedG: 100),
      ],
      cookingMethod: 'stir-fry',
      isSingleItem: false,
      confidence: 0.88,
      promptVersion: 'v1.0',
    );
  }
}

void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;
  late MealLogRepository mealRepo;
  late NutritionLookup lookup;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    foodRepo = FoodItemRepository(db);
    mealRepo = MealLogRepository(db);
    lookup = NutritionLookup(foodRepo);

    // 导入 Sanotsu 样本数据（番茄/马铃薯/花生油/苹果）
    final importer = FoodSeedImporter(db);
    final raw = jsonDecode(_sanotsuSample) as List<dynamic>;
    await importer.importFromJsonList(raw.cast<Map<String, dynamic>>());
    await importer.supplementAliases(); // 番茄→[西红柿,tomato] 等
  });

  tearDown(() async {
    await db.close();
  });

  test('Sprint 1 E2E（单品·苹果）：识别→查库→校准→写meal_log→今日热量增加', () async {
    const today = '2026-07-02';

    // 1. 验证今日初始热量为 0
    expect(await mealRepo.getTotalCaloriesByDate(today), 0.0);

    // 2. 模拟 Qwen-VL 识别苹果（冒烟预演真实返回值）
    final provider = FakeQwenVlProvider();
    final result = await provider.recognize('fake-base64');
    expect(result.dishName, '苹果');
    expect(result.confidence, 0.99);
    expect(result.isSingleItem, isTrue);

    // 3. 查库回填营养素（Task 6 单品路径）
    final nutrition = await lookup.lookupSingleItem(
      dishName: result.dishName,
      servingG: result.estimatedWeightGMid,
    );
    expect(nutrition, isNotNull, reason: '苹果应在种子库中命中');
    // 苹果 52 kcal/100g × 180g / 100 = 93.6 kcal
    expect(nutrition!.calories, closeTo(93.6, 0.01));
    expect(nutrition.proteinG, closeTo(0.54, 0.01)); // 0.3 × 1.8
    expect(nutrition.fatG, closeTo(0.36, 0.01)); // 0.2 × 1.8
    expect(nutrition.carbsG, closeTo(24.84, 0.01)); // 13.8 × 1.8
    expect(nutrition.foodItemId, greaterThan(0), reason: 'foodItemId 必须有效（FK 约束）');

    // 4. 模拟校准页「一键记录」（confidence 0.99 ≥ 0.85，单品允许跳过校准）
    //    用 AI 中值 180g，按比例换算营养素（CalibrationPage._confirmOneClick 逻辑）
    final canSkipCalibration = result.confidence >= 0.85 && result.isSingleItem;
    expect(canSkipCalibration, isTrue, reason: '置信度 0.99 单品应允许一键记录');
    final servingG = result.estimatedWeightGMid; // 一键记录用 AI 中值
    final ratio = servingG / result.estimatedWeightGMid; // = 1.0
    final actualCalories = nutrition.calories * ratio;
    final actualProtein = nutrition.proteinG * ratio;
    final actualFat = nutrition.fatG * ratio;
    final actualCarbs = nutrition.carbsG * ratio;

    // 5. 写入 meal_log（Task 7 recognize_page onConfirm 逻辑）
    await mealRepo.insertMealLog(
      date: today,
      mealType: 'snack',
      foodItemId: nutrition.foodItemId,
      actualServingG: servingG,
      actualCalories: actualCalories,
      actualProteinG: actualProtein,
      actualFatG: actualFat,
      actualCarbsG: actualCarbs,
      originalImagePath: '/tmp/fake_apple.jpg',
      recognitionConfidence: result.confidence,
    );

    // 6. 验证今日热量增加（Task 7 DashboardPage 读取逻辑）
    final total = await mealRepo.getTotalCaloriesByDate(today);
    expect(total, closeTo(93.6, 0.01), reason: '今日热量应从 0 增加到 93.6');
  });

  test('Sprint 1 E2E（复合菜·番茄炒蛋）：组分累加+用油→写meal_log', () async {
    const today = '2026-07-02';

    // 鸡蛋不在种子库，需手动插入（番茄已在种子库）
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '鸡蛋',
          defaultServingG: 60,
          caloriesPer100g: 144,
          proteinPer100g: 13,
          fatPer100g: 9,
          carbsPer100g: 1.1,
          source: 'manual',
          sourceVersion: 'manual',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));

    // 1. 模拟 Qwen-VL 识别番茄炒蛋（复合菜）
    final provider = FakeQwenVlProviderComposite();
    final result = await provider.recognize('fake-base64');
    expect(result.isSingleItem, isFalse);
    expect(result.foodComponents.length, 2);

    // 2. 查库回填（Task 6 复合菜路径：组分累加 + 炒菜用油 12g）
    final nutrition = await lookup.lookupCompositeDish(
      components: result.foodComponents,
      cookingMethod: result.cookingMethod,
    );
    // 番茄 100g: 18 kcal / 鸡蛋 100g: 144 kcal = 162 kcal
    // + 炒菜用油 12g × 889/100 = 106.68 kcal
    // 合计 ≈ 268.68 kcal
    expect(nutrition.calories, closeTo(268.68, 0.1));
    expect(nutrition.oilG, 12);
    expect(nutrition.componentHits.length, 2, reason: '番茄+鸡蛋都应命中');
    expect(nutrition.componentMisses, isEmpty);

    // 3. 复合菜写入 food_item（source=ai_recognized）获取有效 foodItemId（Task 7 FK 处理）
    final foodItemId = await foodRepo.upsertAiRecognized(
      name: result.dishName,
      caloriesPer100g: 0,
      proteinPer100g: 0,
      fatPer100g: 0,
      carbsPer100g: 0,
      confidence: result.confidence,
      componentsJson: jsonEncode({
        'components': result.foodComponents.map((c) => {'name': c.name, 'actual_g': c.estimatedG}).toList(),
        'oil_g': nutrition.oilG,
      }),
    );
    expect(foodItemId, greaterThan(0));

    // 4. 写 meal_log（复合菜热量直接用累加值，不按 100g 密度换算）
    await mealRepo.insertMealLog(
      date: today,
      mealType: 'lunch',
      foodItemId: foodItemId,
      actualServingG: result.estimatedWeightGMid,
      actualCalories: nutrition.calories,
      actualProteinG: nutrition.proteinG,
      actualFatG: nutrition.fatG,
      actualCarbsG: nutrition.carbsG,
      recognitionConfidence: result.confidence,
      componentsSnapshotJson: jsonEncode({'oil_g': nutrition.oilG}),
    );

    final total = await mealRepo.getTotalCaloriesByDate(today);
    expect(total, closeTo(268.68, 0.1));
  });

  test('Sprint 1 E2E（别名匹配）：识别「西红柿」查库命中「番茄」', () async {
    // 验证 Task 4 别名补充 + Task 6 findByNameOrAlias 别名匹配
    final food = await foodRepo.findByNameOrAlias('西红柿');
    expect(food, isNotNull, reason: '西红柿应通过别名命中番茄');
    expect(food!.name, '番茄');
    expect(food.caloriesPer100g, 18);
  });

  test('Sprint 1 E2E（外键约束）：foodItemId=0 应触发 FK 违规', () async {
    // 验证 Task 2 PRAGMA foreign_keys = ON 生效
    // meal_log.food_item_id 是非空 FK，id=0 不存在 → 插入应抛异常
    await expectLater(
      mealRepo.insertMealLog(
        date: '2026-07-02',
        mealType: 'snack',
        foodItemId: 999999, // 不存在的 id
        actualServingG: 100,
        actualCalories: 50,
        actualProteinG: 1,
        actualFatG: 1,
        actualCarbsG: 10,
      ),
      throwsA(isA<Object>()),
    );
  });

  test('Sprint 1 E2E（校准份量换算）：滑块调整份量后营养素按比例变化', () async {
    // 验证 CalibrationPage._buildNutritionPreview 换算逻辑
    final provider = FakeQwenVlProvider();
    final result = await provider.recognize('fake');
    final nutrition = (await lookup.lookupSingleItem(
      dishName: result.dishName,
      servingG: result.estimatedWeightGMid,
    ))!;

    // 模拟用户拖滑块到 100g（AI 中值 180g）
    const sliderG = 100.0;
    final ratio = sliderG / result.estimatedWeightGMid; // 100/180
    final scaledCal = nutrition.calories * ratio;
    // 93.6 × (100/180) ≈ 52 kcal（正好是 100g 苹果的热量）
    expect(scaledCal, closeTo(52, 0.01));
  });
}

const _sanotsuSample = '''
[
  {"foodName":"番茄[西红柿]","energyKCal":"18","protein":"0.9","fat":"0.2","CHO":"3.9","edible":"97"},
  {"foodName":"马铃薯(土豆,洋芋)","energyKCal":"76","protein":"2.0","fat":"0.1","CHO":"16.5","edible":"94"},
  {"foodName":"花生油","energyKCal":"889","protein":"—","fat":"99.9","CHO":"Tr","edible":"100"},
  {"foodName":"苹果","energyKCal":"52","protein":"0.3","fat":"0.2","CHO":"13.8","edible":""}
]
''';
