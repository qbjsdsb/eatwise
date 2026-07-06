/// M26 E 类 P1 修复测试
///
/// 覆盖 today_meals_page.dart 三处 P1 UI 审查修复：
/// 1. Undo SnackBar content 包 Semantics(liveRegion: true)（删除后无障碍播报）
/// 2. Image.file 缩略图带 semanticLabel: '食物图片'（无障碍图说）
/// 3. 反馈纠正 dialog barrierDismissible: false（点 barrier 不丢用户输入）
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:eatwise/core/util/date_format.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/features/dashboard/today_meals_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TodayMealsPage E 类 P1 修复', () {
    late EatWiseDatabase db;
    late ProviderContainer container;
    late int foodId;

    setUp(() async {
      db = EatWiseDatabase(NativeDatabase.memory());
      // meal_log.foodItemId 是 FK，必须先插食物
      foodId = await db.into(db.foodItems).insert(
            FoodItemsCompanion.insert(
              name: '宫保鸡丁',
              defaultServingG: 100,
              caloriesPer100g: 200,
              proteinPer100g: 15,
              fatPer100g: 10,
              carbsPer100g: 8,
              source: 'manual',
              sourceVersion: 'test',
              createdAt: 1000,
            ),
          );
      container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: TodayMealsPage()),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    testWidgets('删除后 SnackBar 含 liveRegion semantics', (tester) async {
      await MealLogRepository(db).insertMealLog(
        date: todayYmd(),
        mealType: 'lunch',
        foodItemId: foodId,
        actualServingG: 150,
        actualCalories: 300,
        actualProteinG: 22.5,
        actualFatG: 15,
        actualCarbsG: 12,
      );
      await pumpPage(tester);

      // 触发 Dismissible（endToStart 滑动删除）
      await tester.drag(
        find.byType(Dismissible),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // SnackBar 应出现，content 含 Semantics(liveRegion: true)
      // properties 在私有基类 _SemanticsBase 上，但属 public 字段，可经 Semantics 访问
      final deletedText = find.textContaining('已删除');
      expect(deletedText, findsOneWidget);
      // "已删除" 文本的祖先中应含 Semantics(liveRegion: true)
      final liveRegionAncestor = find.ancestor(
        of: deletedText,
        matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true),
      );
      expect(liveRegionAncestor, findsWidgets);
    });

    testWidgets('Image.file 缩略图带 semanticLabel 食物图片', (tester) async {
      // 创建最小 JPEG header，避免 Image.file throw（走 errorBuilder 但
      // semanticLabel 仍设置在 Image widget 上）
      final imgFile = File('/tmp/test_food_image_e_test.jpg');
      imgFile.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0]);
      addTearDown(() {
        if (imgFile.existsSync()) imgFile.deleteSync();
      });

      await MealLogRepository(db).insertMealLog(
        date: todayYmd(),
        mealType: 'lunch',
        foodItemId: foodId,
        actualServingG: 150,
        actualCalories: 300,
        actualProteinG: 22.5,
        actualFatG: 15,
        actualCarbsG: 12,
        originalImagePath: imgFile.path,
      );
      await pumpPage(tester);

      // 验证带 '食物图片' semanticLabel 的 Image 存在
      expect(
        find.byWidgetPredicate(
            (w) => w is Image && w.semanticLabel == '食物图片'),
        findsOneWidget,
      );
    });

    testWidgets('反馈纠正 dialog barrierDismissible false 点 barrier 不关闭',
        (tester) async {
      // recognitionConfidence 非 null → 显示反馈 IconButton
      await MealLogRepository(db).insertMealLog(
        date: todayYmd(),
        mealType: 'lunch',
        foodItemId: foodId,
        actualServingG: 150,
        actualCalories: 300,
        actualProteinG: 22.5,
        actualFatG: 15,
        actualCarbsG: 12,
        recognitionConfidence: 0.85,
      );
      await pumpPage(tester);

      // 点反馈 IconButton（Icons.feedback_outlined）
      await tester.tap(find.byIcon(Icons.feedback_outlined));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 第一个 dialog："识别准不准？" 点"不准" → 弹反馈纠正 dialog
      expect(find.text('识别准不准？'), findsOneWidget);
      await tester.tap(find.text('不准'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 反馈纠正 dialog 应出现（barrierDismissible: false）
      expect(find.text('请输入正确信息'), findsOneWidget);

      // 点 barrier（dialog 外区域）：barrierDismissible: false 不应关闭
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 反馈纠正 dialog 应仍然存在
      expect(find.text('请输入正确信息'), findsOneWidget);
    });
  });
}
