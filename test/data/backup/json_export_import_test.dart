import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/data/backup/json_exporter.dart';
import 'package:eatwise/data/backup/json_importer.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// JSON 导出/导入测试
/// - 数据一致：导出 → 导入到新 DB → 各表条数 + 关键字段一致
/// - schemaVersion 不匹配抛异常
/// - 外键关系完整（meal_log.food_item_id 引用有效）
void main() {
  late EatWiseDatabase srcDb;

  setUp(() {
    srcDb = EatWiseDatabase(NativeDatabase.memory());
  });

  tearDown(() async => srcDb.close());

  // 准备：插入食物 + 餐次记录（建立外键关系）
  Future<void> seedData(EatWiseDatabase db) async {
    final foodId = await db.into(db.foodItems).insert(
          FoodItemsCompanion.insert(
            name: '苹果',
            defaultServingG: 100,
            caloriesPer100g: 52,
            proteinPer100g: 0.3,
            fatPer100g: 0.2,
            carbsPer100g: 13.8,
            source: 'manual',
            sourceVersion: 'test_v1',
            createdAt: 1000,
          ),
        );
    await db.into(db.mealLogs).insert(
          MealLogsCompanion.insert(
            date: '2026-07-02',
            mealType: 'breakfast',
            foodItemId: foodId,
            actualServingG: 150,
            actualCalories: 78,
            actualProteinG: 0.45,
            actualFatG: 0.3,
            actualCarbsG: 20.7,
            loggedAt: 2000,
          ),
        );
    await db.into(db.weightLogs).insert(
          WeightLogsCompanion.insert(date: '2026-07-02', weightKg: 70.5),
        );
    await db.into(db.insightSummaries).insert(
          InsightSummariesCompanion.insert(
            periodType: 'weekly',
            periodStart: '2026-06-30',
            periodEnd: '2026-07-06',
            summaryText: '本周热量偏高',
            generatedAt: 3000,
          ),
        );
    // 反馈需引用 meal_log id（用上面插入的 meal_log，drift autoIncrement 从 1 开始）
    await db.into(db.recognitionFeedbacks).insert(
          RecognitionFeedbacksCompanion.insert(
            mealLogId: 1,
            isCorrect: 1,
            promptVersion: 'v1.0',
            createdAt: 4000,
          ),
        );
    // schema v2 三字段（HANDOFF 陷阱 12：导出导入必须同步）
    // 数据库 onCreate 已插入 id=1 的默认 profile，直接 update
    await (db.update(db.profiles)..where((p) => p.id.equals(1))).write(
          const ProfilesCompanion(
            specialCondition: Value('pregnancy'),
            dietPreference: Value('vegetarian'),
            healthCondition: Value('diabetes'),
          ),
        );
  }

  test('导出 → 导入后数据一致（6 表条数 + 关键字段）', () async {
    await seedData(srcDb);
    // 源库已有 1 条默认 profile（数据库 onCreate 插入），seedData 又加了食物/餐次/体重/汇总/反馈

    final exporter = JsonExporter(srcDb);
    final jsonStr = await exporter.exportAsString();

    // 导入到全新 DB（同样会 onCreate 插入默认 profile，但导入会先清空）
    final dstDb = EatWiseDatabase(NativeDatabase.memory());
    final importer = JsonImporter(dstDb);
    final stats = await importer.importFromString(jsonStr);

    expect(stats.profiles, 1);
    expect(stats.foodItems, 1);
    expect(stats.mealLogs, 1);
    expect(stats.weightLogs, 1);
    expect(stats.insights, 1);
    expect(stats.feedbacks, 1);

    // 关键字段：profile 体重、food 名称、meal_log 份量、weight 体重、insight 文本、feedback 标记
    final profile = await (dstDb.profiles.select()..limit(1)).getSingle();
    expect(profile.weightKg, 70);
    // schema v2 三字段（HANDOFF 陷阱 12：导出导入必须同步，曾漏导出致恢复丢数据）
    expect(profile.specialCondition, 'pregnancy');
    expect(profile.dietPreference, 'vegetarian');
    expect(profile.healthCondition, 'diabetes');

    final food = await (dstDb.foodItems.select()..limit(1)).getSingle();
    expect(food.name, '苹果');
    expect(food.caloriesPer100g, 52);

    final meal = await (dstDb.mealLogs.select()..limit(1)).getSingle();
    expect(meal.actualServingG, 150);
    expect(meal.actualCalories, 78);

    final weight = await (dstDb.weightLogs.select()..limit(1)).getSingle();
    expect(weight.weightKg, 70.5);

    final insight = await (dstDb.insightSummaries.select()..limit(1)).getSingle();
    expect(insight.summaryText, '本周热量偏高');

    final feedback =
        await (dstDb.recognitionFeedbacks.select()..limit(1)).getSingle();
    expect(feedback.isCorrect, 1);

    await dstDb.close();
  });

  test('schemaVersion 不匹配抛 ArgumentError', () async {
    final importer = JsonImporter(srcDb);
    const badJson =
        '{"schemaVersion": 99, "exportedAt": 0, "tables": {}}';
    expect(
      () => importer.importFromString(badJson),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('导入后外键关系完整（meal_log.food_item_id 引用有效）', () async {
    await seedData(srcDb);
    final jsonStr = await JsonExporter(srcDb).exportAsString();

    final dstDb = EatWiseDatabase(NativeDatabase.memory());
    await JsonImporter(dstDb).importFromString(jsonStr);

    // 启用外键后查询 meal_log JOIN food_item 应成功
    final meals = await dstDb.mealLogs.select().get();
    expect(meals.length, 1);
    final food = await dstDb.foodItems.select().getSingle();
    expect(meals.first.foodItemId, food.id); // 外键关系完整

    await dstDb.close();
  });

  test('导出 JSON 包含 schemaVersion 和 exportedAt', () async {
    await seedData(srcDb);
    final data = await JsonExporter(srcDb).export();
    expect(data['schemaVersion'], 3);
    expect(data['exportedAt'], isA<int>());
    expect(data['tables'], isA<Map>());
    expect((data['tables'] as Map).keys.toSet(), {
      'profiles',
      'food_items',
      'meal_logs',
      'weight_logs',
      'insight_summaries',
      'recognition_feedbacks',
      'recommendation_feedbacks',
    });
  });

  // H2 修复：_asInt 注释承诺"用 _asIntOrNull 兜底"但实现没兜底
  // 旧版备份缺必填 int 字段（如 age）时，应抛 ArgumentError（清晰错误）而非 _TypeError
  test('H2: 旧版备份缺必填 int 字段时 _asInt 抛 ArgumentError 而非 _TypeError', () async {
    final brokenData = {
      'schemaVersion': 1,
      'exportedAt': 0,
      'tables': {
        // profile 缺 age 字段（模拟旧版备份极端场景）
        'profiles': [
          {
            'id': 1,
            'heightCm': 170.0,
            'weightKg': 70.0,
            // age 缺失
            'gender': 'male',
            'activityLevel': 1.375,
            'goal': 'maintain',
            'goalRateKgPerWeek': 0.0,
            'formula': 'mifflin',
            'dailyCalorieTarget': 2000,
            'proteinGPerKg': 1.4,
            'fatGPerKg': 0.9,
            'updatedAt': 0,
          }
        ],
        'food_items': [],
        'meal_logs': [],
        'weight_logs': [],
        'insight_summaries': [],
        'recognition_feedbacks': [],
        'recommendation_feedbacks': [],
      },
    };
    final importer = JsonImporter(srcDb);
    // H2 修复前：_asInt(null) 抛 _TypeError 'type 'Null' is not a subtype of type 'num''
    // H2 修复后：抛 ArgumentError '必填 int 字段缺失...'（清晰错误信息）
    expect(
      () => importer.importFromMap(brokenData),
      throwsA(isA<ArgumentError>()),
    );
  });
}
