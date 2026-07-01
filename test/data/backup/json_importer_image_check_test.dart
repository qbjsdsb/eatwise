import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/data/backup/json_importer.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// 换机图片失效检测测试（T24）
/// - 导入后失效图片路径置空 + 返回失效条数
/// - 导入有效图片路径不置空
void main() {
  late EatWiseDatabase db;

  setUp(() {
    db = EatWiseDatabase(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  test('导入后失效图片路径置空 + 返回失效条数', () async {
    // 构造一个含失效图片路径的 JSON（路径不存在）
    // 注意：drift schema 中 double 字段用 as double 强转，JSON 中必须写小数形式
    const json = '''
{
  "schemaVersion": 1,
  "exportedAt": 1730000000000,
  "tables": {
    "profiles": [{"id":1,"heightCm":170.0,"weightKg":70.0,"bodyFatPct":null,"age":30,"gender":"male","activityLevel":1.375,"goal":"maintain","goalRateKgPerWeek":0.0,"formula":"mifflin","dailyCalorieTarget":2000,"proteinGPerKg":1.4,"fatGPerKg":0.9,"carbGPerKg":null,"tdeeAdjustmentKcal":0,"updatedAt":1730000000000}],
    "food_items": [{"id":1,"name":"测试","defaultServingG":100.0,"caloriesPer100g":100.0,"proteinPer100g":5.0,"fatPer100g":2.0,"carbsPer100g":20.0,"aliasesJson":null,"ediblePercent":null,"source":"manual","sourceVersion":"manual","confidence":null,"componentsJson":null,"thumbnailPath":"/nonexistent/thumb.png","createdAt":1730000000000}],
    "meal_logs": [{"id":1,"date":"2026-07-01","mealType":"lunch","foodItemId":1,"actualServingG":100.0,"actualCalories":100.0,"actualProteinG":5.0,"actualFatG":2.0,"actualCarbsG":20.0,"originalImagePath":"/nonexistent/photo.jpg","recognitionConfidence":0.9,"componentsSnapshotJson":null,"loggedAt":1730000000000}],
    "weight_logs": [],
    "insight_summaries": [],
    "recognition_feedbacks": []
  }
}
''';
    final importer = JsonImporter(db);
    final result = await importer.importFromString(json);

    // 验证导入成功
    expect(result.profiles, 1);
    expect(result.mealLogs, 1);

    // 验证失效图片检测
    expect(result.imageCheckResult.mealLogMissing, 1);
    expect(result.imageCheckResult.foodItemMissing, 1);
    expect(result.imageCheckResult.totalMissing, 2);

    // 验证 DB 中路径已置空
    final meals = await db.mealLogs.select().get();
    expect(meals.first.originalImagePath, isNull);
    final foods = await db.foodItems.select().get();
    expect(foods.first.thumbnailPath, isNull);
  });

  test('导入有效图片路径不置空', () async {
    // 创建真实存在的临时文件（writeAsString 会自动创建文件）
    final tmpFile = File('${Directory.systemTemp.path}/img_test_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await tmpFile.writeAsString('fake');
    final tmpThumb = File('${Directory.systemTemp.path}/thumb_test_${DateTime.now().microsecondsSinceEpoch}.png');
    await tmpThumb.writeAsString('fake');

    // Linux 沙箱路径用 / 无需转义
    final json = '''
{
  "schemaVersion": 1,
  "exportedAt": 1730000000000,
  "tables": {
    "profiles": [{"id":1,"heightCm":170.0,"weightKg":70.0,"bodyFatPct":null,"age":30,"gender":"male","activityLevel":1.375,"goal":"maintain","goalRateKgPerWeek":0.0,"formula":"mifflin","dailyCalorieTarget":2000,"proteinGPerKg":1.4,"fatGPerKg":0.9,"carbGPerKg":null,"tdeeAdjustmentKcal":0,"updatedAt":1730000000000}],
    "food_items": [{"id":1,"name":"测试","defaultServingG":100.0,"caloriesPer100g":100.0,"proteinPer100g":5.0,"fatPer100g":2.0,"carbsPer100g":20.0,"aliasesJson":null,"ediblePercent":null,"source":"manual","sourceVersion":"manual","confidence":null,"componentsJson":null,"thumbnailPath":"${tmpThumb.path}","createdAt":1730000000000}],
    "meal_logs": [{"id":1,"date":"2026-07-01","mealType":"lunch","foodItemId":1,"actualServingG":100.0,"actualCalories":100.0,"actualProteinG":5.0,"actualFatG":2.0,"actualCarbsG":20.0,"originalImagePath":"${tmpFile.path}","recognitionConfidence":0.9,"componentsSnapshotJson":null,"loggedAt":1730000000000}],
    "weight_logs": [],
    "insight_summaries": [],
    "recognition_feedbacks": []
  }
}
''';

    final importer = JsonImporter(db);
    final result = await importer.importFromString(json);

    expect(result.imageCheckResult.totalMissing, 0);

    final meals = await db.mealLogs.select().get();
    expect(meals.first.originalImagePath, isNotNull); // 未置空

    await tmpFile.delete();
    await tmpThumb.delete();
  });
}
