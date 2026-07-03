@Tags(['smoke'])
library;

// Sprint 1 终极端到端验证（真实 API + 内存 DB 完整闭环）
//
// 用 flutter test 运行（sqlite3mc FFI 在 flutter test 模式下正常工作），
// 通过 HttpOverrides.global = null 禁用 flutter_test 的 HTTP 劫持，走真实网络。
//
// 运行：
//   flutter test test/smoke/real_api_smoke_test.dart \
//     --dart-define=QWEN_API_KEY=你的key \
//     --dart-define=QWEN_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1
//
// 依赖：网络可用 + /tmp/apple.jpg 存在 + API key 有效
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/qwen_vl_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/data/seed/food_seed_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 禁用 flutter_test 的 HTTP 劫持，允许真实网络请求
  HttpOverrides.global = null;

  final apiKey = const String.fromEnvironment('QWEN_API_KEY');
  final baseUrl = const String.fromEnvironment(
    'QWEN_BASE_URL',
    defaultValue: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
  );
  final imageFile = File('/tmp/apple.jpg');
  final canRun = apiKey.isNotEmpty && imageFile.existsSync();

  group('Sprint 1 终端 E2E（真实 API + 内存 DB）', () {
    test(
      '苹果图 → Qwen-VL → 查库 → 写 meal_log → 今日热量增加',
      skip: canRun ? false : '需 QWEN_API_KEY + /tmp/apple.jpg',
      () async {
        // ── 1. 内存 DB + 种子导入 ──
        final db = EatWiseDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final foodRepo = FoodItemRepository(db);
        final mealRepo = MealLogRepository(db);
        final lookup = NutritionLookup(foodRepo);

        final importer = FoodSeedImporter(db);
        const seedJson = '''
[
  {"foodName":"番茄[西红柿]","energyKCal":"18","protein":"0.9","fat":"0.2","CHO":"3.9","edible":"97"},
  {"foodName":"马铃薯(土豆,洋芋)","energyKCal":"76","protein":"2.0","fat":"0.1","CHO":"16.5","edible":"94"},
  {"foodName":"花生油","energyKCal":"889","protein":"—","fat":"99.9","CHO":"Tr","edible":"100"},
  {"foodName":"苹果","energyKCal":"52","protein":"0.3","fat":"0.2","CHO":"13.8","edible":""}
]
''';
        await importer.importFromJsonList(
          (jsonDecode(seedJson) as List).cast<Map<String, dynamic>>(),
        );
        await importer.supplementAliases();

        final today = _todayLocalDate();
        final initialCalories = await mealRepo.getTotalCaloriesByDate(today);
        // ignore: avoid_print
        print('[1/6] 种子导入完成，今日初始热量：${initialCalories.toStringAsFixed(1)} kcal');
        expect(initialCalories, 0.0);

        // ── 2. 真实 Qwen-VL 识别苹果图 ──
        final imageBase64 = base64Encode(await imageFile.readAsBytes());
        final provider = QwenVlProvider(
          apiKey: apiKey,
          baseUrl: baseUrl,
          modelName: 'qwen-vl-max',
        );
        final result = await provider.recognize(imageBase64);
        // ignore: avoid_print
        print(
          '[2/6] Qwen-VL-max 识别：${result.dishName} '
          'confidence=${result.confidence} weight=${result.estimatedWeightGMid}g',
        );
        expect(result.dishName, contains('苹'), reason: '应识别为苹果');
        expect(result.isSingleItem, isTrue);
        expect(
          result.confidence,
          greaterThanOrEqualTo(0.85),
          reason: 'Sprint 1 成功标准：confidence ≥ 0.85',
        );

        // ── 3. 查库回填营养素 ──
        final nutrition = await lookup.lookupSingleItem(
          dishName: result.dishName,
          servingG: result.estimatedWeightGMid,
        );
        // ignore: avoid_print
        print(
          '[3/6] 查库回填：${nutrition?.calories.toStringAsFixed(2)} kcal '
          '(foodItemId=${nutrition?.foodItemId})',
        );
        expect(nutrition, isNotNull, reason: '苹果应在种子库中命中');
        expect(nutrition!.foodItemId, greaterThan(0));
        expect(nutrition.calories, greaterThan(0));

        // ── 4. 模拟校准页一键记录写 meal_log ──
        final canSkip = result.confidence >= 0.85 && result.isSingleItem;
        // ignore: avoid_print
        print(
          '[4/6] 校准页：confidence ${result.confidence} ${canSkip ? "≥ 0.85 → 一键记录" : "< 0.85"}',
        );
        expect(canSkip, isTrue);

        await mealRepo.insertMealLog(
          date: today,
          mealType: 'snack',
          foodItemId: nutrition.foodItemId,
          actualServingG: result.estimatedWeightGMid,
          actualCalories: nutrition.calories,
          actualProteinG: nutrition.proteinG,
          actualFatG: nutrition.fatG,
          actualCarbsG: nutrition.carbsG,
          originalImagePath: '/tmp/apple.jpg',
          recognitionConfidence: result.confidence,
        );
        // ignore: avoid_print
        print('[5/6] meal_log 已写入');

        // ── 5. 读今日热量 ──
        final finalCalories = await mealRepo.getTotalCaloriesByDate(today);
        // ignore: avoid_print
        print(
          '[6/6] 今日热量：${initialCalories.toStringAsFixed(1)} → ${finalCalories.toStringAsFixed(1)} kcal '
          '(+${(finalCalories - initialCalories).toStringAsFixed(2)})',
        );
        expect(
          finalCalories,
          greaterThan(initialCalories),
          reason: '写库后今日热量应增加',
        );
        expect(finalCalories, closeTo(nutrition.calories, 0.01));

        // ignore: avoid_print
        print(
          '\n✅ Sprint 1 端到端闭环验证通过：'
          '${result.dishName}(${result.confidence}) → 查库 → 写库 → ${finalCalories.toStringAsFixed(1)} kcal',
        );
      },
    );

    test(
      'qwen3-vl-flash 备选模型识别苹果',
      skip: canRun ? false : '需 QWEN_API_KEY + /tmp/apple.jpg',
      () async {
        final imageBase64 = base64Encode(await imageFile.readAsBytes());
        final provider = QwenVlProvider(
          apiKey: apiKey,
          baseUrl: baseUrl,
          modelName: 'qwen3-vl-flash',
        );
        final result = await provider.recognize(imageBase64);
        // ignore: avoid_print
        print(
          'qwen3-vl-flash: ${result.dishName} confidence=${result.confidence} '
          'weight=${result.estimatedWeightGMid}g',
        );
        expect(result.dishName, contains('苹'));
        expect(result.confidence, greaterThan(0.5));
      },
    );
  });
}

String _todayLocalDate() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
