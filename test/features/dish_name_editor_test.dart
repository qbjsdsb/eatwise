// test/features/dish_name_editor_test.dart
// dish_name_editor 文案修复测试（B 类 P1 修复 3）
//
// 验证修复：showNotFoundToast 文案
//   "食物库未命中「改菜名」" → "食物库未命中此菜名"
//
// 测试策略（混合 widget + unit test）：
// 1. widget test：直接调 showNotFoundToast，验证新文案显示 + 旧文案不存在
//    —— 这是最直接验证"文案修复"的场景，覆盖 fix 3 的全部改动
// 2. unit test：FoodItemRepository.searchByName 对不存在菜名返回空列表
//    —— editDishNameAndLookup 内部判断 candidates.isEmpty 的前置条件
// 3. unit test：NutritionLookup.lookupSingleItem DB miss + 无 offProvider 时返回 null
//    —— editDishNameAndLookup 在 candidates 为空时调用此方法，miss 返回 null 即
//       "搜不到菜名 → nutrition=null" 的核心逻辑
//
// 不再用 widget test 跑完整 editDishNameAndLookup 流程的原因（降级说明）：
// promptNewDishName 在 finally 中 dispose TextEditingController，但 dialog 退出
// 动画仍在运行 → pumpAndSettle 期间 TextField 访问已 dispose 的 controller 抛
// FlutterError，且因重建循环 pumpAndSettle 长时间不返回（实测 > 2 分钟）。
// 这是 production 代码预存 bug（不在本次 P1 修复范围，本次只改 toast 文案）。
// 按"如果某个测试场景实在无法 widget test，降级为 unit test"约定，降级为
// unit test 验证 underlying lookup 行为。
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/features/recognize/dish_name_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试用 host widget：State with DishNameEditor，让测试能调用 mixin 方法。
class _DishNameEditorHost extends StatefulWidget {
  const _DishNameEditorHost();
  @override
  State<_DishNameEditorHost> createState() => _DishNameEditorHostState();
}

class _DishNameEditorHostState extends State<_DishNameEditorHost>
    with DishNameEditor<_DishNameEditorHost> {
  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

void main() {
  group('DishNameEditor 文案修复 - showNotFoundToast', () {
    testWidgets('显示新文案"食物库未命中此菜名"，旧文案不存在', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _DishNameEditorHost()));
      await tester.pump();

      final state = tester.state(find.byType(_DishNameEditorHost))
          as _DishNameEditorHostState;

      // 直接调 showNotFoundToast 验证文案（fix 3 的核心改动）
      state.showNotFoundToast();
      await tester.pumpAndSettle();

      // 新文案存在
      expect(find.textContaining('食物库未命中此菜名'), findsOneWidget);
      // 完整文案
      expect(find.textContaining('食物库未命中此菜名，可转手动录入或再试一次'),
          findsOneWidget);
      // 旧文案不存在
      expect(find.textContaining('食物库未命中「改菜名」'), findsNothing);
    });

    testWidgets('连续调用 showNotFoundToast 只保留最后一个（clearSnackBars 兜底）',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _DishNameEditorHost()));
      await tester.pump();

      final state = tester.state(find.byType(_DishNameEditorHost))
          as _DishNameEditorHostState;

      // 多次调用应不抛异常，showAppToast 内部 clearSnackBars 保证只显示最后一个
      state.showNotFoundToast();
      state.showNotFoundToast();
      await tester.pumpAndSettle();

      // 仍只显示一个新文案 toast
      expect(find.textContaining('食物库未命中此菜名'), findsOneWidget);
    });
  });

  group('DishNameEditor 文案修复 - underlying lookup 行为（unit test）', () {
    // 以下 unit test 验证 editDishNameAndLookup "搜不到菜名 → nutrition=null"
    // 的 underlying 行为。widget test 因 promptNewDishName 预存的 controller
    // dispose bug 导致 pumpAndSettle 长时间不返回（详见文件头注释），降级为 unit test。

    late EatWiseDatabase db;
    late FoodItemRepository repo;

    setUp(() async {
      db = EatWiseDatabase(NativeDatabase.memory());
      repo = FoodItemRepository(db);
    });

    tearDown(() async => db.close());

    test('FoodItemRepository.searchByName 对不存在菜名返回空列表', () async {
      // editDishNameAndLookup 内部第一步：searchByName(newName, limit: 10)
      // 不存在的菜名应返回空列表，触发 candidates.isEmpty 分支
      final candidates = await repo.searchByName('不存在的菜名xyz123', limit: 10);
      expect(candidates, isEmpty,
          reason: '不存在的菜名 searchByName 应返回空列表，触发 lookupSingleItem 兜底');
    });

    test('NutritionLookup.lookupSingleItem DB miss + 无 offProvider → 返回 null',
        () async {
      // editDishNameAndLookup 在 candidates.isEmpty 时调 lookupSingleItem
      // 无 offProvider（测试不注入）→ DB miss 直接返回 null
      // 这就是"搜不到菜名 → nutrition=null"的核心逻辑
      final lookup = NutritionLookup(repo); // 不注入 offProvider → 不触网
      final result = await lookup.lookupSingleItem(
        dishName: '不存在的菜名xyz123',
        servingG: 200,
      );
      expect(result, isNull,
          reason: 'DB miss 且无 offProvider 时 lookupSingleItem 应返回 null，'
              '对应 editDishNameAndLookup 返回 nutrition=null');
    });

    test('NutritionLookup.lookupSingleItem DB 命中 → 返回非 null NutritionResult',
        () async {
      // 反向验证：DB 命中时返回非 null，证明 lookupSingleItem 行为正常
      // 预置一条食物记录
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '番茄',
            defaultServingG: 100,
            caloriesPer100g: 18,
            proteinPer100g: 0.9,
            fatPer100g: 0.2,
            carbsPer100g: 3.9,
            source: 'china_fct',
            sourceVersion: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));

      final lookup = NutritionLookup(repo);
      final result = await lookup.lookupSingleItem(
        dishName: '番茄',
        servingG: 100,
      );
      expect(result, isNotNull,
          reason: 'DB 命中应返回非 null NutritionResult');
      expect(result!.foodItemId, greaterThan(0));
      expect(result.calories, 18);
    });
  });
}
