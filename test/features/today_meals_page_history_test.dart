import 'package:drift/native.dart';
import 'package:eatwise/core/util/date_format.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/features/dashboard/today_meals_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('B2: 点左箭头切到前一天，加载该日记录', (tester) async {
    final yesterday = formatYmd(DateTime.now().subtract(const Duration(days: 1)));
    await MealLogRepository(db).insertMealLog(
      date: yesterday,
      mealType: 'lunch',
      foodItemId: foodId,
      actualServingG: 150,
      actualCalories: 375,
      actualProteinG: 22,
      actualFatG: 15,
      actualCarbsG: 37,
    );

    await pumpPage(tester);

    // 点左箭头切到前一天
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 标题应变为昨天的日期
    final yesterdayDate = DateTime.now().subtract(const Duration(days: 1));
    final expectedTitle = '${yesterdayDate.month}月${yesterdayDate.day}日 记录';
    expect(find.text(expectedTitle), findsOneWidget);

    // 应显示昨天插入的午餐记录
    expect(find.text('测试食物'), findsOneWidget);

    // 非今日应显示"跳今日"按钮（TextButton.icon 的 label 是 '今日'）
    expect(find.text('今日'), findsOneWidget);
  });

  testWidgets('B2: 后一天按钮在今日时禁用（不能查未来）', (tester) async {
    await pumpPage(tester);

    // 默认今日，后一天按钮应禁用（onPressed 为 null）
    // 注意：chevron_right 在 IconButton 中，IconButton onPressed 为 null 时禁用
    final iconButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      ),
    );
    expect(iconButton.onPressed, isNull, reason: '今日时不能往后翻（不能查未来）');
  });

  testWidgets('B2: 点跳今日按钮回到今日', (tester) async {
    final yesterday = formatYmd(DateTime.now().subtract(const Duration(days: 1)));
    await MealLogRepository(db).insertMealLog(
      date: yesterday,
      mealType: 'lunch',
      foodItemId: foodId,
      actualServingG: 150,
      actualCalories: 375,
      actualProteinG: 22,
      actualFatG: 15,
      actualCarbsG: 37,
    );

    await pumpPage(tester);

    // 先切到昨天
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 点"今日"按钮（TextButton.icon 的 label）
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 应回到今日，标题为"今日记录"
    expect(find.text('今日记录'), findsOneWidget);
    // 不应再显示"今日"按钮（已是今日，TextButton 隐藏）
    // 注：AppBar 标题 '今日记录' 是 Text widget，find.text('今日') 精确匹配不会命中 '今日记录'
    expect(find.text('今日'), findsNothing);
  });

  testWidgets('B3: 点击日期文本弹 DatePicker', (tester) async {
    await pumpPage(tester);

    // 点击日期文本（默认显示"今天"）
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // DatePicker 应弹出
    expect(find.byType(DatePickerDialog), findsOneWidget);

    // 用 escape 关闭 DatePicker（默认 locale 下无 '取消'/'确定' 按钮）
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 关闭后 DatePicker 应消失
    expect(find.byType(DatePickerDialog), findsNothing);
  });
}
