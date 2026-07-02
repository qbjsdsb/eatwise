import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/features/profile/nutrition_calculator.dart';
import 'package:eatwise/features/profile/profile_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 ProfilePage _save goal 切换重算（Sprint 7 T58 回归）：
/// - 切换 goal 到 cut（goalRate=0）→ 保存 → dailyCalorieTarget 按 cut 公式重算
/// - cut + goalRate=0 回退默认 -500 deficit
/// 注：profile 表单分组到 3 张 Card 后整体变高，用超高视口让全部内容一次性构建，
/// 避免 scrollUntilVisible 在多 EditableText 中报 "Too many elements"。
/// 改用 DropdownMenu 后需点开菜单选目标。
void main() {
  testWidgets('切换到减脂后重算 target（goalRate=0 回退 -500）', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ProfileRepository(db);

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ProfilePage()),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 选"减脂"（goal 是第 2 个 DropdownMenu<String>）
    await _selectGoal(tester, '减脂');

    // 点保存（goalRate=0 不触发风险警告，不弹确认框）
    // tall viewport 下保存按钮已可见，直接点。
    await tester.tap(find.text('保存并重算目标'));
    await tester.pumpAndSettle();

    // 验证 DB
    final saved = await repo.get();
    expect(saved.goal, 'cut');

    // 验证 dailyCalorieTarget 按 cut 公式重算
    // goalRate=0 → 回退默认 deficit=500；tdeeAdjustmentKcal=0（初始 profile 无校准）
    final bmr = NutritionCalculator.bmrMifflin(
      weightKg: 70, heightCm: 170, age: 30, gender: Gender.male);
    final tdee = NutritionCalculator.tdee(bmr: bmr, activityLevel: 1.375);
    final expected = NutritionCalculator.dailyCalorieTarget(
      tdee: tdee,
      goal: Goal.cut,
      tdeeAdjustmentKcal: 0,
      goalRateKgPerWeek: 0, // 回退 -500 默认 deficit
      gender: Gender.male,
    );
    expect(saved.dailyCalorieTarget, expected);
  });
}

/// 选目标：goal 是第 2 个 `DropdownMenu<String>`（gender 第1；activity 是 double）。
/// tall viewport 下目标菜单已可见，直接点开菜单选目标。
Future<void> _selectGoal(WidgetTester tester, String label) async {
  final goalMenu = find.byType(DropdownMenu<String>).last;
  // 点开菜单：点 trailing 图标（arrow_drop_down）
  await tester.tap(find
      .descendant(of: goalMenu, matching: find.byIcon(Icons.arrow_drop_down))
      .first);
  await tester.pumpAndSettle();
  // 点弹窗中的目标项（弹窗 list 中该项文本）
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
