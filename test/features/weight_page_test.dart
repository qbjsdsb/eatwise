// weight_page widget 测试（M14）
//
// 验证 PopScope 未保存确认：
// - 用户输入体重后未保存返回，应弹"放弃修改？"确认对话框
// - 确认后才退出页面；取消则保留输入继续编辑
import 'package:drift/native.dart';
import 'package:eatwise/core/config/secure_config_store.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:eatwise/features/weight/weight_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('M14 weight_page PopScope', () {
    late EatWiseDatabase db;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      db = EatWiseDatabase(NativeDatabase.memory());
      // weight_logs 表需要 profile 存在（外键？实测 weight_logs 无 FK，
      // 但 _load() 会查 weight_logs + meal_logs，空 DB 即可）
    });

    tearDown(() async => db.close());

    /// 构建 WeightPage 作为 push 路由（带 BackButton），不是 home
    Future<void> pumpWeightPage(WidgetTester tester, ProviderContainer container) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const WeightPage()),
                      );
                    },
                    child: const Text('push'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // 推入 WeightPage
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();
    }

    testWidgets('M14: 体重输入后返回弹放弃确认对话框', (tester) async {
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await pumpWeightPage(tester, container);

      // 输入体重 75
      await tester.enterText(find.byType(TextField).first, '75');
      await tester.pump();

      // 点返回按钮（BackButton 在 AppBar leading）
      final backButton = find.byType(BackButton);
      expect(backButton, findsOneWidget,
          reason: 'WeightPage 非 embedded 应有 AppBar + BackButton');
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // 应弹"放弃修改？"确认对话框
      expect(find.text('放弃修改？'), findsOneWidget,
          reason: '体重输入后未保存返回应弹放弃确认');
      // 对话框有两个按钮
      expect(find.text('继续编辑'), findsOneWidget);
      expect(find.text('放弃'), findsOneWidget);
    });

    testWidgets('M14: 未输入体重时返回不弹确认（_dirty=false 放行）',
        (tester) async {
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await pumpWeightPage(tester, container);

      // 不输入直接点返回
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // 不应弹对话框（_dirty=false，canPop=true 直接放行）
      expect(find.text('放弃修改？'), findsNothing,
          reason: '未输入体重时 _dirty=false，应直接放行不弹确认');
    });

    testWidgets('M14: 点"放弃"确认后退出页面', (tester) async {
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await pumpWeightPage(tester, container);

      await tester.enterText(find.byType(TextField).first, '75');
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // 点"放弃"
      await tester.tap(find.text('放弃'));
      await tester.pumpAndSettle();

      // 应回到 home（push 按钮重新可见）
      expect(find.text('push'), findsOneWidget,
          reason: '点放弃后应退出 WeightPage 回到 home');
    });

    testWidgets('M14: 点"继续编辑"保留输入不退出', (tester) async {
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await pumpWeightPage(tester, container);

      await tester.enterText(find.byType(TextField).first, '75');
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // 点"继续编辑"
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();

      // 应仍在 WeightPage（输入框仍可见，值保留）
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('75'), findsOneWidget,
          reason: '继续编辑应保留用户输入');
    });
  });
}
