import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/features/profile/nutrition_calculator.dart';
import 'package:eatwise/features/profile/profile_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 ProfilePage _save 传真实 tdeeAdjustmentKcal：
/// 先 update profile.tdeeAdjustmentKcal=100，再保存表单，
/// 验证 dailyCalorieTarget = 基础值(tdeeAdjustmentKcal=0) + 100
/// 注：表单分组到 3 张 Card 后整体变高，用超高视口让全部内容一次性构建，
/// 避免 scrollUntilVisible 在多 EditableText 中报 "Too many elements"。
void main() {
  testWidgets('保存时 tdeeAdjustmentKcal 生效到 dailyCalorieTarget', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // 先设置 tdeeAdjustmentKcal=100（模拟校准累积值）
    final repo = ProfileRepository(db);
    await repo.update(tdeeAdjustmentKcal: 100);

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ProfilePage()),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 点保存（默认表单值：height=170 weight=70 age=30 male activity=1.375 maintain goalRate=0）
    // maintain + goalRate=0 不触发风险警告弹窗
    // tall viewport 下保存按钮已可见，直接点。
    await tester.tap(find.text('保存并重算目标'));
    await tester.pumpAndSettle();

    // 验证 DB：dailyCalorieTarget 应含 +100 adjustment
    final saved = await repo.get();
    final bmr = NutritionCalculator.bmrMifflin(
      weightKg: 70,
      heightCm: 170,
      age: 30,
      gender: Gender.male,
    );
    final tdee = NutritionCalculator.tdee(bmr: bmr, activityLevel: 1.375);
    final baseTarget = NutritionCalculator.dailyCalorieTarget(
      tdee: tdee,
      goal: Goal.maintain,
      tdeeAdjustmentKcal: 0,
      gender: Gender.male,
    );
    expect(saved.tdeeAdjustmentKcal, 100, reason: 'tdeeAdjustmentKcal 应保留为 100');
    expect(saved.dailyCalorieTarget, baseTarget + 100,
        reason: 'dailyCalorieTarget 应含 +100 adjustment');
  });
}
