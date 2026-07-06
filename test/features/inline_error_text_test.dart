/// M26 E 类 P1 修复测试
///
/// 修复背景：M26 审查 E 类 P1 - 4 个表单文件的 TextField 校验失败时仅 toast，
/// 用户不知道哪个字段错。修复后改用 errorText 内联显示在 TextField 下方，
/// 替代 toast 提示。
///
/// 覆盖 4 个文件：
/// - meal_edit_dialog.dart: _servingError（份量 <= 0 显示 '份量需大于 0'）
/// - food_edit_page.dart: 5 个 errorText（_servingError/_calError/_proteinError/_fatError/_carbsError）
/// - manual_entry_page.dart: 6 个 errorText（_servingError/_nameError/_calError/_proteinError/_fatError/_carbsError）
/// - weight_page.dart: _weightError（体重 <= 0 显示 '体重需大于 0'）
///
/// 测试策略：轻量级 smoke 测试。每个文件至少 1 个测试，覆盖"无效输入触发 errorText 显示"。
/// 校验失败路径在调用 repo 前 return，无需 mock DB（weight_page 除外，因 _load 在
/// initState 读 repo，需 override databaseProvider 用内存 DB）。
library;

import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/dashboard/meal_edit_dialog.dart';
import 'package:eatwise/features/food_library/food_edit_page.dart';
import 'package:eatwise/features/manual_entry/manual_entry_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:eatwise/features/weight/weight_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('meal_edit_dialog errorText 内联', () {
    /// 通过按钮触发 showDialog 打开 MealEditDialog。
    /// PopScope 需挂在 ModalRoute 上才生效，直接 pumpWidget(dialog) 无 route 可挂载。
    /// barrierDismissible:false 与 today_meals_page 调用方一致。
    Future<void> pumpDialog(WidgetTester tester, MealLog mealLog) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog<MealEditResult>(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) => MealEditDialog(
                          mealLog: mealLog,
                          currentFoodName: '宫保鸡丁',
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('份量输入 0 显示 份量需大于 0 errorText', (tester) async {
      final mealLog = MealLog(
        id: 1,
        date: '2026-07-07',
        mealType: 'lunch',
        foodItemId: 10,
        actualServingG: 150,
        actualCalories: 300,
        actualProteinG: 22.5,
        actualFatG: 15,
        actualCarbsG: 12,
        loggedAt: 1000,
      );
      await pumpDialog(tester, mealLog);

      // dialog 初始 advanced 折叠，只有 1 个 TextField（份量）
      // 份量输入 0 → _save 中 serving=0 <= 0 → _servingError='份量需大于 0'
      await tester.enterText(find.byType(TextField), '0');
      await tester.pump();

      // 点保存 → 校验失败 → setState(_servingError) → 不 pop
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('份量需大于 0'), findsOneWidget,
          reason: '份量 0 应触发 _servingError 内联显示在 TextField 下方');
      // 校验失败不关闭 dialog
      expect(find.text('编辑餐次'), findsOneWidget,
          reason: '校验失败 dialog 不应关闭');
    });
  });

  group('food_edit_page errorText 内联', () {
    /// 构造 ai_recognized 来源的 FoodItem（editable=true → _saveAll 路径）
    FoodItem editableFoodItem() => FoodItem(
          id: 1,
          name: '测试食物',
          defaultServingG: 100,
          caloriesPer100g: 200,
          proteinPer100g: 10,
          fatPer100g: 5,
          carbsPer100g: 30,
          source: 'ai_recognized',
          sourceVersion: '1',
          createdAt: 0,
        );

    /// pump FoodEditPage。校验失败在调 repo 前 return，无需 mock DB。
    Future<void> pumpPage(WidgetTester tester, FoodItem item) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: FoodEditPage(foodItem: item),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('份量输入 0 显示 份量需大于 0 errorText', (tester) async {
      await pumpPage(tester, editableFoodItem());

      // 5 个 TextField 顺序：份量(0) / 热量(1) / 蛋白质(2) / 脂肪(3) / 碳水(4)
      // 份量输入 0 → _saveAll 中 serving=0 <= 0 → _servingError='份量需大于 0'
      await tester.enterText(find.byType(TextField).at(0), '0');
      await tester.pump();

      await tester.tap(find.text('保存全部修改'));
      await tester.pumpAndSettle();

      expect(find.text('份量需大于 0'), findsOneWidget,
          reason: '份量 0 应触发 _servingError 内联显示');
    });

    testWidgets('清空热量字段显示 请输入有效数字 errorText', (tester) async {
      await pumpPage(tester, editableFoodItem());

      // 清空热量字段（index 1）→ _saveAll 中 cal=null → _calError='请输入有效数字'
      await tester.enterText(find.byType(TextField).at(1), '');
      await tester.pump();

      await tester.tap(find.text('保存全部修改'));
      await tester.pumpAndSettle();

      expect(find.text('请输入有效数字'), findsOneWidget,
          reason: '清空热量应触发 _calError 内联显示');
    });
  });

  group('manual_entry_page errorText 内联', () {
    /// pump ManualEntryPage。校验失败在调 repo 前 return，无需 mock DB。
    Future<void> pumpPage(WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ManualEntryPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('自定义模式空字段显示名称与数字 errorText', (tester) async {
      // 自定义模式字段多（6 个 TextField + 2 个 Card + 按钮），默认 800x600 视口
      // 无法一次显示全部，ListView 懒加载会导致"存库并记录"按钮未 build。
      // 拉高视口让全部内容一次性构建（与 profile_page_test 同策略）
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpPage(tester);

      // 默认搜库模式，点"找不到？自定义输入"切到自定义模式
      await tester.tap(find.text('找不到？自定义输入'));
      await tester.pumpAndSettle();

      // 自定义模式初始：serving='100'（有效），name/cal/protein/fat/carbs 均空
      // 直接点"存库并记录" → _logCustom 校验失败 → 一次性展示所有错误
      await tester.tap(find.text('存库并记录'));
      await tester.pumpAndSettle();

      // name 空 → '请输入食物名称'
      expect(find.text('请输入食物名称'), findsOneWidget,
          reason: '食物名称为空应触发 _nameError 内联显示');
      // cal/protein/fat/carbs 空 → '请输入有效数字'（4 个）
      expect(find.text('请输入有效数字'), findsNWidgets(4),
          reason: '4 个营养素字段为空应各显示 请输入有效数字');
    });
  });

  group('weight_page errorText 内联', () {
    late EatWiseDatabase db;
    late ProviderContainer container;

    setUp(() async {
      // SecureConfigStore 通过 flutter_secure_storage 读写，需 mock 平台插件
      FlutterSecureStorage.setMockInitialValues({});
      db = EatWiseDatabase(NativeDatabase.memory());
      container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    /// pump WeightPage 并等待 _load 完成（weight_logs + 30 天 meal_log 聚合）
    Future<void> pumpWeightPage(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: WeightPage()),
        ),
      );
      // pumpAndSettle 给 _load 的 microtask 跑完时间，_loading=false 后渲染主表单
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    testWidgets('体重输入 0 显示 体重需大于 0 errorText', (tester) async {
      await pumpWeightPage(tester);

      // 主表单只有 1 个 TextField（体重输入）
      // 输入 0 → _save 中 weight=0 <= 0 → _weightError='体重需大于 0'
      await tester.enterText(find.byType(TextField), '0');
      await tester.pump();

      // 点记录 → 校验失败 → setState(_weightError) → 不写库不 pop
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();

      expect(find.text('体重需大于 0'), findsOneWidget,
          reason: '体重 0 应触发 _weightError 内联显示在 TextField 下方');
    });
  });
}
