import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/recognize/dish_name_editor.dart';
import 'package:eatwise/features/recognize/recognize_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// M3 验证：recognize_page State 混入 DishNameEditor mixin（DRY 重构）
/// 重构前：recognize_page 有私有重复方法 _promptNewDishName/_showFoodSelectionDialog/_nutritionFromFoodItem
/// 重构后：State with DishNameEditor，复用 mixin 的公共方法
void main() {
  testWidgets('M3: recognize_page State 混入 DishNameEditor mixin', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: RecognizePage()),
    ));
    await tester.pump();

    final state = tester.state(find.byType(RecognizePage));
    // M3: 验证 state 混入了 DishNameEditor mixin（消除重复代码）
    expect(state, isA<DishNameEditor>(),
        reason: '_RecognizePageState 应 with DishNameEditor 复用 mixin 而非重复实现');
  });
}
