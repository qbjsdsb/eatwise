import 'package:drift/native.dart';
import 'package:eatwise/core/util/date_format.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/features/dashboard/today_meals_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 TodayMealsPage 日期切换功能（M15-B：每日历史记录查看）
void main() {
  late EatWiseDatabase db;
  late ProviderContainer container;
  late int foodId;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    // 插入测试食物（meal_log.foodItemId 是 FK，必须先插食物）
    foodId = await db.into(db.foodItems).insert(
          FoodItemsCompanion.insert(
            name: '测试食物',
            defaultServingG: 100,
            caloriesPer100g: 250,
            proteinPer100g: 15,
            fatPer100g: 10,
            carbsPer100g: 25,
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

  testWidgets('B1: 默认显示今日记录（_selectedDate 初始化为今日）', (tester) async {
    final today = todayYmd();
    await MealLogRepository(db).insertMealLog(
      date: today,
      mealType: 'breakfast',
      foodItemId: foodId,
      actualServingG: 200,
      actualCalories: 500,
      actualProteinG: 30,
      actualFatG: 20,
      actualCarbsG: 50,
    );

    await pumpPage(tester);

    // 标题应含"今日记录"（默认今日）
    expect(find.text('今日记录'), findsOneWidget);
    // 应显示今日插入的早餐记录
    expect(find.text('测试食物'), findsOneWidget);
  });

  testWidgets('B1: 日期切换栏渲染（左箭头/日期文本/右箭头）', (tester) async {
    await pumpPage(tester);

    // 日期切换栏应存在
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    // 日期文本应显示"今天"（isToday 时显示"今天"）
    expect(find.text('今天'), findsOneWidget);
  });
}
