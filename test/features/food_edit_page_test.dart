import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/features/food_library/food_edit_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 FoodEditPage：
/// - ai_recognized 来源 → 显示"保存全部修改"按钮
/// - china_fct 来源 → 显示"保存默认份量"按钮
/// - 保存全部修改 → DB 更新 + SnackBar + pop
Future<FoodItem> _insertFood(EatWiseDatabase db, String source) async {
  final id = await db
      .into(db.foodItems)
      .insert(
        FoodItemsCompanion.insert(
          name: '测试菜',
          defaultServingG: 100,
          caloriesPer100g: 250,
          proteinPer100g: 15,
          fatPer100g: 10,
          carbsPer100g: 25,
          source: source,
          sourceVersion: 'test',
          createdAt: 1000,
        ),
      );
  return (db.foodItems.select()..where((f) => f.id.equals(id))).getSingle();
}

void main() {
  testWidgets('ai_recognized 来源显示保存全部修改按钮', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final foodItem = await _insertFood(db, 'ai_recognized');

    final container = ProviderContainer(
      overrides: [recognize.databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: FoodEditPage(foodItem: foodItem)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('保存全部修改'), findsOneWidget);
    expect(find.text('保存默认份量'), findsNothing);
  });

  testWidgets('china_fct 来源显示保存默认份量按钮', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final foodItem = await _insertFood(db, 'china_fct');

    final container = ProviderContainer(
      overrides: [recognize.databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: FoodEditPage(foodItem: foodItem)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('保存默认份量'), findsOneWidget);
    expect(find.text('保存全部修改'), findsNothing);
  });

  testWidgets('保存全部修改更新 DB 并提示', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final foodItem = await _insertFood(db, 'ai_recognized');

    final container = ProviderContainer(
      overrides: [recognize.databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: FoodEditPage(foodItem: foodItem)),
      ),
    );
    await tester.pumpAndSettle();

    // 修改热量字段
    await tester.enterText(find.widgetWithText(TextField, '250'), '300');
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存全部修改'));
    // _saveAll 含多段串行真实异步（databaseProvider.future +
    // updateDefaultServing + updateNutrients + showSnackBar + pop），
    // 在 testWidgets 的 fake-async zone 下每段真实 I/O 都会挂起，
    // 故需交替 pump（flush microtask 推进到下一段真实 I/O）+ runAsync（在真实事件
    // 循环中完成该段 I/O）多轮，才能让 _saveAll 走完并渲染 SnackBar。
    // 注意：用 pump() 而非 pumpAndSettle()，因为 pumpAndSettle 会完成 pop 动画
    // 并移除 Scaffold（连带 SnackBar），单次 pump 只推进一帧，SnackBar 可见。
    for (var i = 0; i < 8; i++) {
      await tester.pump();
      await tester.runAsync(
        () async => await Future.delayed(const Duration(milliseconds: 250)),
      );
    }
    await tester.pump();

    // 验证 SnackBar
    expect(find.text('已保存'), findsOneWidget);

    // 验证 DB 更新（getById 返回 FoodItem?，用 ! 断言非空）
    final repo = FoodItemRepository(db);
    final updated = (await repo.getById(foodItem.id))!;
    expect(updated.caloriesPer100g, 300);
  });
}
