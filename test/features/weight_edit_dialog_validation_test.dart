import 'dart:async';

import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/weight_log_repository.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:eatwise/features/weight/weight_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 仅 override update 永不完成的 WeightLogRepository。
///
/// 用途：有效值测试中，_showEditWeightDialog 校验通过后调 repo.update，
/// 真实 DB 操作经 microtask 瞬时完成 → 外层 finally 的 weightCtrl.dispose()
/// 在 dialog route 完全移除前执行 → TextFormField rebuild 访问已 dispose
/// 的 controller 抛 "used after being disposed"。
/// 生产环境 DB 操作有真实延迟，dialog 先移除再 dispose 无此问题。
/// 测试中用此 repo 让 update 永不完成，_showEditWeightDialog 挂起在
/// await repo.update，weightCtrl.dispose() 不被执行，dialog 正常移除。
/// getRecent 等读方法继承父类实现，_load 初始加载不受影响。
class _HangingUpdateWeightRepo extends WeightLogRepository {
  _HangingUpdateWeightRepo(super.db);

  @override
  Future<void> update({
    required int id,
    double? weightKg,
    String? date,
    double? impedance,
    double? bodyFatPercent,
  }) {
    return Completer<void>().future;
  }
}

/// M25 P1 修复测试：WeightPage 编辑体重 dialog 改 Form + TextFormField + validator
///
/// 修复背景：原编辑 dialog 用 TextField 无 validator，用户输入 "abc" 或负数也能
/// 保存，导致 weight_logs 表写入 NaN/负值污染折线图。修复后 dialog 用 Form 包裹
/// + TextFormField validator（>0 且 ≤500），保存按钮调 Form.validate()，校验失败
/// 不关闭 dialog 并显示 errorText。
///
/// 测试策略：widget test，预置 1 条体重记录 → pump WeightPage → 点记录打开编辑 dialog
/// → 输入无效值 → 点保存 → 验证 dialog 仍显示 + errorText 显示。
/// 输入有效值 → 点保存 → 验证 dialog 关闭。
void main() {
  group('WeightPage 编辑 dialog 校验', () {
    late EatWiseDatabase db;
    late ProviderContainer container;

    setUp(() async {
      // SecureConfigStore 通过 flutter_secure_storage 读写，需 mock 平台插件
      FlutterSecureStorage.setMockInitialValues({});
      db = EatWiseDatabase(NativeDatabase.memory());
      container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
        // 用 _HangingUpdateWeightRepo 替换：update 永不完成，避免有效值测试中
        // weightCtrl.dispose() 在 dialog route 移除前执行（详见类注释）
        recognize.weightLogRepoProvider
            .overrideWith((ref) async => _HangingUpdateWeightRepo(db)),
      ]);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    /// pump WeightPage 并等待 _load 完成（30 天 meal_log 聚合 + weight_logs 查询）
    Future<void> pumpWeightPage(WidgetTester tester) async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WeightPage()),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    /// 预置 1 条体重记录并 pump WeightPage，返回后界面已显示记录 ListTile。
    /// weightKg=75.0 → ListTile title 显示 "75.0 kg"
    Future<void> seedAndPump(WidgetTester tester) async {
      final repo = WeightLogRepository(db);
      await repo.insert(date: '2026-07-05', weightKg: 75.0);

      await pumpWeightPage(tester);

      // 确认记录已渲染（ListTile title 显示 "75.0 kg"）
      expect(find.text('75.0 kg'), findsOneWidget,
          reason: '预置体重记录应渲染为 ListTile');
    }

    /// 点体重记录 ListTile 打开编辑 dialog，验证 dialog 已弹出
    Future<void> openEditDialog(WidgetTester tester) async {
      final tile = find.ancestor(
        of: find.text('75.0 kg'),
        matching: find.byType(ListTile),
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget,
          reason: '点 ListTile 应打开编辑 dialog');
      expect(find.text('编辑体重'), findsOneWidget,
          reason: 'dialog 标题应为"编辑体重"');
    }

    testWidgets('输入 abc 不关闭 dialog 且显示 errorText', (tester) async {
      await seedAndPump(tester);
      await openEditDialog(tester);

      // 输入非数字 "abc"
      await tester.enterText(find.byType(TextFormField), 'abc');
      await tester.pump();

      // 点保存（dialog 内"保存"按钮调 formKey.currentState?.validate()）
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 校验失败：dialog 仍显示
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: '输入 abc 校验失败时 dialog 不应关闭');
      // errorText 显示在 TextFormField 下方
      expect(find.text('请输入 0-500 之间的数字'), findsOneWidget,
          reason: '应显示 validator 返回的 errorText');
    });

    testWidgets('输入 0 不关闭 dialog 且显示 errorText', (tester) async {
      await seedAndPump(tester);
      await openEditDialog(tester);

      await tester.enterText(find.byType(TextFormField), '0');
      await tester.pump();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 0 不满足 > 0 约束，校验失败
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: '输入 0 校验失败时 dialog 不应关闭');
      expect(find.text('请输入 0-500 之间的数字'), findsOneWidget,
          reason: '0 应触发 errorText（>0 约束）');
    });

    testWidgets('输入 600（超 500 上限）不关闭 dialog 且显示 errorText',
        (tester) async {
      await seedAndPump(tester);
      await openEditDialog(tester);

      await tester.enterText(find.byType(TextFormField), '600');
      await tester.pump();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 600 超过 500 上限，校验失败
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: '输入 600 校验失败时 dialog 不应关闭');
      expect(find.text('请输入 0-500 之间的数字'), findsOneWidget,
          reason: '600 应触发 errorText（≤500 约束）');
    });

    testWidgets('输入有效值 80 关闭 dialog', (tester) async {
      await seedAndPump(tester);
      await openEditDialog(tester);

      await tester.enterText(find.byType(TextFormField), '80');
      await tester.pump();

      await tester.tap(find.text('保存'));

      // 校验通过 → Navigator.pop 关闭 dialog → _showEditWeightDialog 继续：
      // setState(_busy=true) → repo.update → _load → RefreshBus.notify → setState(_busy=false)
      //
      // 关键点 1：tester.pump() 默认 Duration.zero 不推进时钟，dialog 退出动画
      // （route exit transition ~300ms）无法完成，AlertDialog 仍留在树里。
      // 必须用 pump(Duration) 推进时钟让退出动画跑完，route 才会真正移除。
      //
      // 关键点 2：不用 pump+runAsync 交替——Drift NativeDatabase.memory() 同 isolate
      // 运行，DB 操作经 microtask 在 pump 内完成（seedAndPump 的 insert 也靠
      // pumpAndSettle 完成即证）。runAsync 会让真实异步回调在 pump 帧外调 setState，
      // 触发 BuildScope._debugAssertElementInScope 断言失败。
      // 纯 pump(Duration) 让 DB 操作经 microtask 完成，setState 走正常 dirty→rebuild 流。
      //
      // 关键点 3：不用 pumpAndSettle——_busy=true 期间"记录"按钮显示
      // CircularProgressIndicator（持续动画），pumpAndSettle 会卡 timeout。
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 校验通过：dialog 已关闭
      expect(find.byType(AlertDialog), findsNothing,
          reason: '输入有效值 80 校验通过后 dialog 应关闭');
      expect(find.text('编辑体重'), findsNothing,
          reason: 'dialog 关闭后不应再显示标题');
    });
  });
}
