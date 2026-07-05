import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:eatwise/core/widgets/m3_widgets.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/features/food_library/food_library_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// M24 Task A4：food_library _doSearch 异常必须显示 toast，且结果清空、loading 关闭。
/// 历史 bug：catch 静默吞掉异常，UI 仅显示"未找到相关食物"无重试入口。
///
/// 用 [_ThrowingQueryExecutor] 作为异常源：databaseProvider 仍正常返回 db 对象，
/// food_items 查询（searchByName）会抛异常触发 _doSearch catch（应弹 toast）。
/// meal_logs 查询返回空列表让 listFrequent 成功返回 []，避免触发 _loadFrequent
/// catch（A7 后会显 ErrorState 遮挡搜索框，无法进入 _doSearch 测试路径）。
/// 避免直接让 databaseProvider 抛异常 —— Riverpod 3.x 会缓存 error 状态，
/// 导致 _doSearch 中 `await ref.read(databaseProvider.future)` 永不完成。
/// 也不能用"关闭的 db"——drift 对已关闭的内存 db 仍返回空结果而非抛错。
class _ThrowingQueryExecutor implements QueryExecutor {
  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async => true;

  @override
  Future<List<Map<String, Object?>>> runSelect(
      String statement, List<Object?> args) async {
    // 仅 food_items 查询抛异常（触发 searchByName catch）；
    // meal_logs 查询返回空列表（让 listFrequent 成功返回 []，不触发 A7 ErrorState）
    if (statement.contains('food_items')) {
      throw Exception('db boom');
    }
    return const [];
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    throw Exception('db boom');
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    throw Exception('db boom');
  }

  @override
  Future<int> runDelete(String statement, List<Object?> args) async {
    throw Exception('db boom');
  }

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) async {
    throw Exception('db boom');
  }

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    throw Exception('db boom');
  }

  @override
  TransactionExecutor beginTransaction() {
    throw Exception('db boom');
  }

  @override
  QueryExecutor beginExclusive() {
    throw Exception('db boom');
  }

  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('_doSearch catch 显示 toast', (tester) async {
    final db = EatWiseDatabase(_ThrowingQueryExecutor());

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FoodLibraryPage()),
    ));
    // _loadFrequent 也会失败但被静默吞掉，等待首屏稳定。
    // 注意：不能用 pumpAndSettle —— _initialLoading=true 期间 LoadingState 的
    // CircularProgressIndicator 是无限动画，pumpAndSettle 会超时。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 输入关键词触发 _search → 300ms debounce → _doSearch
    await tester.enterText(find.byType(SearchBar), '测试');
    await tester.pump();
    // 推进 debounce 计时器 + flush 异步 _doSearch（searchByName 抛异常 → catch）
    // 用多次小步 pump 避免推进到 SnackBar 4s 自动消失
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 断言：catch 内调用 showAppToast 显示 toast
    expect(find.text('搜索失败，请重试'), findsOneWidget,
        reason: '_doSearch catch 应调用 showAppToast 提示用户');
    // 断言：结果被清空 → 显示"未找到相关食物"占位
    expect(find.text('未找到相关食物'), findsOneWidget,
        reason: 'catch 应清空 _searchResults，UI 显示空搜索占位');
    // 断言：loading 已关闭
    expect(find.byType(LoadingState), findsNothing,
        reason: 'catch 应关闭 _searchLoading，不再显示 LoadingState');
  });

  group('FoodLibraryPage _loadFrequent 加载失败 ErrorState', () {
    /// M24 Task A7：_loadFrequent 异常应显 ErrorState + 重试，而非静默显空态。
    /// 历史 bug：catch 静默吞掉异常，UI 显示"暂无常用食物"空态误导用户。
    ///
    /// 测试 mock 策略与 A8 profile_page_test 一致：用 overrideWithValue(
    /// AsyncValue.error(...)) 让 foodItemRepoProvider 直接进入错误态，
    /// 触发 _loadFrequent 的 `await ref.read(foodItemRepoProvider.future)` 抛异常 → catch。
    /// 重试测试用 updateOverrides 切换 error → data（重试前切，retry 中
    /// ref.invalidate 会重新读 override 拿到新值）。
    testWidgets('_loadFrequent catch 显示 ErrorState', (tester) async {
      // mock foodItemRepoProvider 直接进入 AsyncError → _loadFrequent catch → 显 ErrorState
      final container = ProviderContainer(overrides: [
        recognize.foodItemRepoProvider.overrideWithValue(
          AsyncValue<FoodItemRepository>.error(
            Exception('mock load fail'),
            StackTrace.empty,
          ),
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FoodLibraryPage()),
      ));
      // 用 pump 而非 pumpAndSettle：LoadingState 的 CircularProgressIndicator 永远
      // 调度下一帧，pumpAndSettle 会卡到 timeout。多 pump 几次让 riverpod
      // FutureProvider 错误态流转 + _loadFrequent await 恢复 + catch + setState rebuild 链路跑完。
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // 断言显示 ErrorState（而非空态）
      expect(find.byType(ErrorState), findsOneWidget,
          reason: '加载失败时应显示 ErrorState');
      // 断言不显示"暂无常用食物"空态（避免误导用户以为无数据）
      expect(find.text('暂无常用食物'), findsNothing,
          reason: '加载失败时不应显示空态误导用户');
    });

    testWidgets('点击重试重新加载', (tester) async {
      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // 初始 override 为 AsyncError（首次加载失败触发 ErrorState）
      // 用变量持有 override 引用：重试前调 updateOverrides 切到 AsyncData
      // （riverpod 3.3.x overrideWith + throw 不传 .future，必须用 overrideWithValue）
      var override = recognize.foodItemRepoProvider.overrideWithValue(
        AsyncValue<FoodItemRepository>.error(
          Exception('mock load fail'),
          StackTrace.empty,
        ),
      );

      final container = ProviderContainer(overrides: [override]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FoodLibraryPage()),
      ));
      // pump 推进 microtask + rebuild（避免 LoadingState 卡 pumpAndSettle）
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // 第一次加载失败 → ErrorState
      expect(find.byType(ErrorState), findsOneWidget,
          reason: '首次加载失败应显示 ErrorState');

      // 切换 override 为 AsyncData（模拟重试时 DB 已可读）
      // 必须在点击重试前更新，retry 中 ref.invalidate 会重新读 override
      override = recognize.foodItemRepoProvider.overrideWithValue(
        AsyncValue<FoodItemRepository>.data(FoodItemRepository(db)),
      );
      container.updateOverrides([override]);

      // 点击 ErrorState 中的重试按钮
      await tester.tap(find.text('重试'));
      // 多 pump 几次让 retry handler → invalidate → _loadFrequent → await →
      // repo.listFrequent → setState rebuild 链路跑完
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // 第二次加载成功 → 不再显示 ErrorState，回到食物库正常 UI（含 SearchBar）
      expect(find.byType(ErrorState), findsNothing,
          reason: '重试成功后应不再显示 ErrorState');
      expect(find.byType(SearchBar), findsOneWidget,
          reason: '重试成功后应显示食物库正常 UI（含搜索框）');
    });
  });
}
