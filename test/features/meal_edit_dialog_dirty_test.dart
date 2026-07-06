// MealEditDialog PopScope dirty 拦截 widget 测试
//
// 验证 D 类修复 1：meal_edit_dialog 加 _dirty + _markDirty + PopScope(canPop: !_dirty) +
// onPopInvokedWithResult → confirmDiscardChanges。调用方 today_meals_page 加
// barrierDismissible: false 防点 barrier 误丢弃修改。
//
// 测试场景：
// - 未修改时系统返回直接关闭 dialog（_dirty=false 放行）
// - 修改份量后系统返回弹"放弃修改？"确认（_dirty=true 拦截）
// - 点"继续编辑"留在 dialog 且保留输入
// - 点"放弃"关闭 dialog 回到 home
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/dashboard/meal_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MealLog mealLog;

  setUp(() {
    mealLog = MealLog(
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
  });

  /// 用按钮触发 showDialog 打开 MealEditDialog。
  /// PopScope 需挂在 ModalRoute 上才生效，直接 pumpWidget(dialog) 无 route 可挂载。
  /// barrierDismissible:false 与 today_meals_page 调用方一致（防点 barrier 误丢弃）。
  Future<void> pumpOpener(WidgetTester tester) async {
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

  testWidgets('未修改时系统返回直接关闭 dialog（_dirty=false 放行）', (tester) async {
    await pumpOpener(tester);
    expect(find.text('编辑餐次'), findsOneWidget);

    // 模拟系统返回键（Android back）
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // _dirty=false → canPop=true → 直接关闭，不弹确认
    expect(find.text('放弃修改？'), findsNothing,
        reason: '未修改 _dirty=false，不应弹确认对话框');
    expect(find.text('编辑餐次'), findsNothing,
        reason: '未修改 _dirty=false，系统返回应直接关闭 dialog');
    expect(find.text('open'), findsOneWidget, reason: '应回到 home 页');
  });

  testWidgets('修改份量后系统返回弹放弃确认（_dirty=true 拦截）', (tester) async {
    await pumpOpener(tester);

    // 修改份量 TextField → _servingCtrl listener → _markDirty → _dirty=true
    // dialog 初始 advanced 折叠，只有 1 个 TextField（份量）
    await tester.enterText(find.byType(TextField), '300');
    await tester.pump();

    // 系统返回键 → canPop=false → onPopInvokedWithResult → confirmDiscardChanges
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('放弃修改？'), findsOneWidget, reason: '_dirty=true 应弹放弃确认');
    expect(find.text('继续编辑'), findsOneWidget);
    expect(find.text('放弃'), findsOneWidget);
    // 编辑 dialog 仍在下层（确认弹窗是叠加的）
    expect(find.text('编辑餐次'), findsOneWidget);
  });

  testWidgets('点继续编辑留在 dialog 且保留输入', (tester) async {
    await pumpOpener(tester);

    await tester.enterText(find.byType(TextField), '300');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 点"继续编辑" → confirmDiscardChanges 返回 false → 不 pop → 留在编辑 dialog
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();

    expect(find.text('放弃修改？'), findsNothing, reason: '确认弹窗应关闭');
    expect(find.text('编辑餐次'), findsOneWidget, reason: '继续编辑应留在 MealEditDialog');
    // 份量输入应保留
    expect(find.text('300'), findsOneWidget, reason: '继续编辑应保留用户输入');
  });

  testWidgets('点放弃关闭 dialog 回到 home', (tester) async {
    await pumpOpener(tester);

    await tester.enterText(find.byType(TextField), '300');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 点"放弃" → confirmDiscardChanges 返回 true → Navigator.pop(context) → 关闭编辑 dialog
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();

    expect(find.text('编辑餐次'), findsNothing, reason: '放弃应关闭编辑 dialog');
    expect(find.text('放弃修改？'), findsNothing, reason: '确认弹窗应已关闭');
    expect(find.text('open'), findsOneWidget, reason: '应回到 home 页');
  });
}
