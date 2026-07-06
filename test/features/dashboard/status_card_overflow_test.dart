// test/features/dashboard/status_card_overflow_test.dart
// StatusCardSection 超量显示全面测试
//
// 验证 Bug 修复：摄入超过推荐值时全维度切换显示方式
// - 标题文案切换"今日还可摄入"→"今日已超" + 颜色变 error
// - 大数字加 "+" 前缀 + error 色
// - 副标题切换为"已超 X kcal (Y%) · 已摄入 A / B"
// - 进度条溢出段（主段 error 满格 + 溢出段 onErrorContainer 按 flex 延伸）
// - 三宏超量：文案追加"超Zg" + error 色
import 'package:eatwise/features/dashboard/dashboard/dashboard_data.dart';
import 'package:eatwise/features/dashboard/dashboard/status_card_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造测试用 DashboardData
DashboardData _data({
  double cal = 0,
  double protein = 0,
  double fat = 0,
  double carbs = 0,
  int target = 2000,
  double proteinGoal = 100,
  double fatGoal = 60,
  double carbGoal = 250,
}) {
  return DashboardData(
    cal: cal,
    protein: protein,
    fat: fat,
    carbs: carbs,
    target: target,
    proteinGoal: proteinGoal,
    fatGoal: fatGoal,
    carbGoal: carbGoal,
    weightKg: 70,
    meals: const [],
    foodNames: const {},
  );
}

/// pump StatusCardSection（包 MaterialApp + Theme 提供色板）
Future<void> _pump(WidgetTester tester, DashboardData data) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.green)),
      home: Scaffold(body: StatusCardSection(data: data)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('热量未超量（正常态）', () {
    testWidgets('cal < target：标题"今日还可摄入" + 大数字无+前缀', (tester) async {
      await _pump(tester, _data(cal: 1800, target: 2000));
      expect(find.text('今日还可摄入'), findsOneWidget);
      expect(find.text('今日已超'), findsNothing);
      // 大数字 "200"（剩余）
      expect(find.text('200'), findsOneWidget);
      expect(find.text('+200'), findsNothing);
      // 副标题
      expect(find.text('kcal · 已摄入 1800 / 2000'), findsOneWidget);
    });

    testWidgets('cal == target 临界：未超量，大数字"0"', (tester) async {
      await _pump(tester, _data(cal: 2000, target: 2000));
      expect(find.text('今日还可摄入'), findsOneWidget);
      expect(find.text('今日已超'), findsNothing);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('cal=0 空态：显示"今日还可摄入" + 大数字"2000"', (tester) async {
      await _pump(tester, _data(cal: 0, target: 2000));
      expect(find.text('今日还可摄入'), findsOneWidget);
      expect(find.text('2000'), findsOneWidget);
      expect(find.text('kcal · 已摄入 0 / 2000'), findsOneWidget);
    });
  });

  group('热量超量（overflow）', () {
    testWidgets('cal > target：标题切换"今日已超" + 大数字"+200" + error 色',
        (tester) async {
      await _pump(tester, _data(cal: 2200, target: 2000));
      expect(find.text('今日已超'), findsOneWidget);
      expect(find.text('今日还可摄入'), findsNothing);
      // 大数字 "+200"（带+前缀）
      expect(find.text('+200'), findsOneWidget);
      expect(find.text('200'), findsNothing);
    });

    testWidgets('超量副标题显示"已超 X kcal (Y%)"', (tester) async {
      await _pump(tester, _data(cal: 2200, target: 2000));
      // 2200-2000=200, 200/2000=10%
      expect(find.text('已超 200 kcal (10%) · 已摄入 2200 / 2000'),
          findsOneWidget);
      // 不应显示正常态副标题
      expect(find.text('kcal · 已摄入 2200 / 2000'), findsNothing);
    });

    testWidgets('超量时图标切换为 warning_amber', (tester) async {
      await _pump(tester, _data(cal: 2200, target: 2000));
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
    });

    testWidgets('未超量时图标为 local_fire_department', (tester) async {
      await _pump(tester, _data(cal: 1800, target: 2000));
      expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('超量进度条渲染两段（主段+溢出段 Container），未超量渲染 LinearProgressIndicator',
        (tester) async {
      // 超量：热量条改用 Row（2 Container），三宏仍是 LinearProgressIndicator
      // 所以超量时 LinearProgressIndicator 数 = 3（三宏）
      await _pump(tester, _data(cal: 2200, target: 2000));
      expect(find.byType(LinearProgressIndicator), findsNWidgets(3),
          reason: '超量：热量条改用 Row 两段，只剩三宏 3 个 LinearProgressIndicator');

      // 未超量：热量条用 LinearProgressIndicator + 三宏 3 个 = 4 个
      await _pump(tester, _data(cal: 1800, target: 2000));
      expect(find.byType(LinearProgressIndicator), findsNWidgets(4),
          reason: '未超量：热量条 + 三宏 3 条 = 4 个 LinearProgressIndicator');
    });

    testWidgets('超量大幅（cal=3000, target=2000，超50%）：溢出段封顶 flex 30',
        (tester) async {
      await _pump(tester, _data(cal: 3000, target: 2000));
      expect(find.text('今日已超'), findsOneWidget);
      expect(find.text('+1000'), findsOneWidget);
      expect(find.text('已超 1000 kcal (50%) · 已摄入 3000 / 2000'),
          findsOneWidget);
    });
  });

  group('三宏超量', () {
    testWidgets('蛋白超量：文案追加"超Zg" + error 色', (tester) async {
      await _pump(tester, _data(
        cal: 1800, target: 2000,
        protein: 120, proteinGoal: 100,
      ));
      // 蛋白行文案 "120/100 g 超20"
      expect(find.text('120/100 g 超20'), findsOneWidget);
    });

    testWidgets('脂肪超量：文案追加"超Zg"', (tester) async {
      await _pump(tester, _data(
        cal: 1800, target: 2000,
        fat: 80, fatGoal: 60,
      ));
      expect(find.text('80/60 g 超20'), findsOneWidget);
    });

    testWidgets('碳水超量：文案追加"超Zg"', (tester) async {
      await _pump(tester, _data(
        cal: 1800, target: 2000,
        carbs: 300, carbGoal: 250,
      ));
      expect(find.text('300/250 g 超50'), findsOneWidget);
    });

    testWidgets('三宏未超量：文案"X/Y g"无"超"字', (tester) async {
      await _pump(tester, _data(
        cal: 1800, target: 2000,
        protein: 80, proteinGoal: 100,
        fat: 40, fatGoal: 60,
        carbs: 200, carbGoal: 250,
      ));
      expect(find.text('80/100 g'), findsOneWidget);
      expect(find.text('40/60 g'), findsOneWidget);
      expect(find.text('200/250 g'), findsOneWidget);
      // 不应有"超"字
      expect(find.textContaining('超'), findsNothing);
    });

    testWidgets('三宏临界（value==goal）：不触发超量文案', (tester) async {
      await _pump(tester, _data(
        cal: 1800, target: 2000,
        protein: 100, proteinGoal: 100,
      ));
      expect(find.text('100/100 g'), findsOneWidget);
    });
  });
}
