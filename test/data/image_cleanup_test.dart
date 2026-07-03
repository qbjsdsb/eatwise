import 'dart:io';
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/backup/image_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path/path.dart' as p;

// 简单的内存路径 provider mock（避免真实文件系统）
class _MemoryPathProvider extends PathProviderPlatform {
  final String basePath;
  _MemoryPathProvider(this.basePath);

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

void main() {
  late EatWiseDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('image_cleanup_test');
    PathProviderPlatform.instance = _MemoryPathProvider(tempDir.path);

    // seed 一个 food_item（meal_log 外键依赖）
    final foodRepo = FoodItemRepository(db);
    await foodRepo.upsertAiRecognized(
      name: '测试食物',
      caloriesPer100g: 100,
      proteinPer100g: 5,
      fatPer100g: 2,
      carbsPer100g: 20,
      confidence: 0.9,
    );
  });
  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('删除 30 天前原图 + 清除 DB 引用', () async {
    // 创建一个假的图片文件
    final imgFile = File(p.join(tempDir.path, 'old_photo.jpg'));
    await imgFile.writeAsString('fake image');

    // 插入 35 天前的 meal_log，引用该图片
    final oldDate = DateTime.now().subtract(const Duration(days: 35));
    final dateStr =
        '${oldDate.year}-${oldDate.month.toString().padLeft(2, '0')}-${oldDate.day.toString().padLeft(2, '0')}';
    final mealRepo = MealLogRepository(db);
    await mealRepo.insertMealLog(
      date: dateStr,
      mealType: 'lunch',
      foodItemId: 1,
      actualServingG: 100,
      actualCalories: 100,
      actualProteinG: 5,
      actualFatG: 2,
      actualCarbsG: 20,
      originalImagePath: imgFile.path,
    );

    // 执行清理
    final deleted = await ImageCleanup.run(db);
    expect(deleted, 1);

    // 文件已删除
    expect(await imgFile.exists(), isFalse);

    // DB 引用已清除
    final meals = await mealRepo.getMealsByDate(dateStr);
    expect(meals.first.originalImagePath, isNull);
  });

  test('保留 30 天内的原图', () async {
    final imgFile = File(p.join(tempDir.path, 'recent_photo.jpg'));
    await imgFile.writeAsString('fake');

    final recentDate = DateTime.now().subtract(const Duration(days: 10));
    final dateStr =
        '${recentDate.year}-${recentDate.month.toString().padLeft(2, '0')}-${recentDate.day.toString().padLeft(2, '0')}';
    final mealRepo = MealLogRepository(db);
    await mealRepo.insertMealLog(
      date: dateStr,
      mealType: 'lunch',
      foodItemId: 1,
      actualServingG: 100,
      actualCalories: 100,
      actualProteinG: 5,
      actualFatG: 2,
      actualCarbsG: 20,
      originalImagePath: imgFile.path,
    );

    final deleted = await ImageCleanup.run(db);
    expect(deleted, 0);
    expect(await imgFile.exists(), isTrue);
  });
}
