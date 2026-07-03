import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/profile/profile_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 ProfilePage goal_rate 输入显示逻辑
/// - 减脂/增肌时显示「目标速率」输入
/// - 维持时不显示
/// databaseProvider override 为内存 DB（绕过 path_provider 平台插件）
/// 注：profile 表单分组到 3 张 Card 后整体变高，用超高视口让全部内容一次性构建，
/// 避免 ListView 懒加载截断 + scrollUntilVisible 在多 EditableText 中报
/// "Too many elements"。改用 DropdownMenu 后需点开菜单选目标。
void main() {
  testWidgets('减脂时显示 goal_rate 输入', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ProfilePage()),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await _selectGoal(tester, '减脂');

    // 验证 goal_rate 输入显示
    expect(find.textContaining('目标速率'), findsOneWidget);
  });

  testWidgets('维持时不显示 goal_rate 输入', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ProfilePage()),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 选维持（默认即维持，重新选中确保状态一致）
    await _selectGoal(tester, '维持');

    // 验证 goal_rate 输入不显示
    expect(find.textContaining('目标速率'), findsNothing);
  });
}

/// 选目标：用 Key 精确定位 goal DropdownMenu（避免新增特殊状况菜单导致 .last 失效）。
/// tall viewport 下目标菜单已可见，直接点开菜单选目标。
Future<void> _selectGoal(WidgetTester tester, String label) async {
  final goalMenu = find.byKey(const Key('goal_dropdown'));
  // 点开菜单：点 trailing 图标（arrow_drop_down）
  await tester.tap(find
      .descendant(of: goalMenu, matching: find.byIcon(Icons.arrow_drop_down))
      .first);
  await tester.pumpAndSettle();
  // 点弹窗中的目标项（弹窗 list 中该项文本）
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
