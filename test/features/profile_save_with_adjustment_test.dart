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
void main() {
  testWidgets('切换到减脂后重算 target（goalRate=0 回退 -500）', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ProfileRepository(db);

    final container = ProviderContainer(
      overrides: [recognize.databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 选"减脂"（goal 是第 2 个 DropdownButtonFormField<String>）
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('减脂').last);
    await tester.pumpAndSettle();

    // 点保存（goalRate=0 不触发风险警告，不弹确认框）
    await tester.tap(find.text('保存并重算目标'));
    await tester.pumpAndSettle();

    // 验证 DB
    final saved = await repo.get();
    expect(saved.goal, 'cut');

    // 验证 dailyCalorieTarget 按 cut 公式重算
    // goalRate=0 → 回退默认 deficit=500；tdeeAdjustmentKcal=0（初始 profile 无校准）
    final bmr = NutritionCalculator.bmrMifflin(
      weightKg: 70,
      heightCm: 170,
      age: 30,
      gender: Gender.male,
    );
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
