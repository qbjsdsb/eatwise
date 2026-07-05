// decimal_input_keyboard_test
//
// 验证数值输入框 keyboardType 支持小数点。
// 背景：iOS 上 TextInputType.number 不弹小数点键，导致用户无法输入 70.5kg / 18.5%
// 这类含小数的数值。正确做法是 numberWithOptions(decimal: true)。
//
// 涉及字段（参见 Web Interface Guidelines Forms 审查）：
// - profile_page：身高 / 体重 / 体脂率（年龄是纯整数，validator 用 int.tryParse，保留 number）
// - weight_page：今日体重（与同页编辑 dialog L487 numberWithOptions 不一致，bug）
// - food_edit_page：默认份量 + 4 营养素（蛋白/脂肪/碳水显示 toStringAsFixed(1) 含小数）
// - manual_entry_page：份量 + 4 营养素（自定义模式）
//
// 定位策略：TextField 与 TextFormField 都把 decoration 透传给内部 EditableText，
// 故统一用 find.byWidgetPredicate 匹配 TextField（含 TextFormField 内部那个），
// 按 labelText 过滤后读取 keyboardType。
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/features/food_library/food_edit_page.dart';
import 'package:eatwise/features/manual_entry/manual_entry_page.dart';
import 'package:eatwise/features/profile/profile_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:eatwise/features/weight/weight_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 找到 labelText 为指定字符串的 TextField（TextFormField 会把 decoration
/// 透传给内部 TextField，故此 finder 同时覆盖两种声明方式）
Finder findInputByLabel(String label) {
  return find.byWidgetPredicate((w) {
    if (w is! TextField) return false;
    final dec = w.decoration;
    if (dec?.labelText == label) return true;
    if (dec?.label is Text && (dec!.label as Text).data == label) return true;
    return false;
  });
}

/// 断言指定 label 的输入框 keyboardType.decimal == true（支持小数点）
void expectDecimalEnabled(WidgetTester tester, String label, String reason) {
  final finder = findInputByLabel(label);
  expect(finder, findsOneWidget,
      reason: '应能找到 labelText="$label" 的输入框');
  final kb = tester.widget<TextField>(finder).keyboardType;
  expect(kb, isA<TextInputType>(), reason: 'keyboardType 应为 TextInputType');
  expect(kb.decimal, isTrue, reason: reason);
}

void main() {
  // ===== ProfilePage =====
  // 表单分组到 3 张 Card 后整体变高，用超高视口让全部内容一次性构建
  group('decimal keyboard: ProfilePage', () {
    Future<void> pumpProfile(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      // 初始化 profile 行（_loadProfile 调 repo.get，需有默认行）
      await ProfileRepository(db).update(tdeeAdjustmentKcal: 0);

      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfilePage()),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    testWidgets('身高输入框 keyboardType 支持小数', (tester) async {
      await pumpProfile(tester);
      expectDecimalEnabled(tester, '身高 (cm)',
          '身高可能含小数（如 170.5cm），keyboardType 应 numberWithOptions(decimal: true)');
    });

    testWidgets('体重输入框 keyboardType 支持小数', (tester) async {
      await pumpProfile(tester);
      expectDecimalEnabled(tester, '体重 (kg)',
          '体重可能含小数（如 70.5kg），keyboardType 应 numberWithOptions(decimal: true)');
    });

    testWidgets('体脂率输入框 keyboardType 支持小数', (tester) async {
      await pumpProfile(tester);
      expectDecimalEnabled(
          tester,
          '体脂率 % (可选，填了可用 Katch 公式)',
          '体脂率可能含小数（如 18.5%），keyboardType 应 numberWithOptions(decimal: true)');
    });
  });

  // ===== WeightPage =====
  group('decimal keyboard: WeightPage', () {
    testWidgets('今日体重输入框 keyboardType 支持小数', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WeightPage()),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectDecimalEnabled(
          tester,
          '今日体重 (kg)',
          '体重可能含小数（如 70.5kg），应与同页编辑 dialog 一致用 '
          'numberWithOptions(decimal: true)');
    });
  });

  // ===== FoodEditPage =====
  group('decimal keyboard: FoodEditPage', () {
    late EatWiseDatabase db;
    late FoodItem foodItem;

    setUp(() async {
      db = EatWiseDatabase(NativeDatabase.memory());
      final id = await db.into(db.foodItems).insert(
            FoodItemsCompanion.insert(
              name: '测试菜',
              defaultServingG: 100,
              caloriesPer100g: 250,
              proteinPer100g: 15,
              fatPer100g: 10,
              carbsPer100g: 25,
              source: 'ai_recognized',
              sourceVersion: 'test',
              createdAt: 1000,
            ),
          );
      foodItem = await (db.foodItems.select()
            ..where((f) => f.id.equals(id)))
          .getSingle();
    });

    tearDown(() async => db.close());

    testWidgets('5 个营养素输入框 keyboardType 支持小数', (tester) async {
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: FoodEditPage(foodItem: foodItem)),
      ));
      await tester.pumpAndSettle();

      expectDecimalEnabled(tester, '默认份量 (g)', '份量可能含小数');
      expectDecimalEnabled(tester, '热量 /100 g (kcal)', '热量可能含小数');
      expectDecimalEnabled(tester, '蛋白质 /100 g (g)',
          '蛋白质显示 toStringAsFixed(1) 含小数，应支持小数输入');
      expectDecimalEnabled(tester, '脂肪 /100 g (g)',
          '脂肪显示 toStringAsFixed(1) 含小数，应支持小数输入');
      expectDecimalEnabled(tester, '碳水 /100 g (g)',
          '碳水显示 toStringAsFixed(1) 含小数，应支持小数输入');
    });
  });

  // ===== ManualEntryPage（自定义模式）=====
  group('decimal keyboard: ManualEntryPage custom mode', () {
    testWidgets('份量 + 4 营养素输入框 keyboardType 支持小数', (tester) async {
      // 自定义模式表单分组到 Card 后整体变高，用超高视口让全部内容一次性构建
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ManualEntryPage(initialName: '宫保鸡丁'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expectDecimalEnabled(tester, '份量 (g)', '份量可能含小数');
      expectDecimalEnabled(tester, '热量 (kcal)', '热量可能含小数');
      expectDecimalEnabled(tester, '蛋白质 (g)', '蛋白质可能含小数');
      expectDecimalEnabled(tester, '脂肪 (g)', '脂肪可能含小数');
      expectDecimalEnabled(tester, '碳水 (g)', '碳水可能含小数');
    });
  });
}
