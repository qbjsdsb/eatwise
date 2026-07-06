import 'package:drift/native.dart';
import 'package:eatwise/core/widgets/m3_widgets.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/features/profile/profile_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// M24 Task A8：profile 加载失败 ErrorState 测试
///
/// 修复背景：M23 审查 P1 - profile_page.dart 档案加载失败仅 toast，
/// UI 显示空白表单，用户不知所措。新增 _loadError 标志 + ErrorState + 重试按钮。
///
/// 与 today_meals_page.dart 的 _loadError + ErrorState 模式同构。
///
/// 测试 mock 策略：用 overrideWithValue(AsyncValue.error(...)) 让 profileRepoProvider
/// 直接进入错误态（riverpod 3.3.x 的 overrideWith + throw 不会把错误传到 .future，
/// 只能用 overrideWithValue）。重试测试用 updateOverrides 切换 error → data。
void main() {
  group('ProfilePage 加载失败 ErrorState', () {
    testWidgets('_loadProfile catch 显示 ErrorState', (tester) async {
      // mock profileRepoProvider 直接进入 AsyncError → _loadProfile catch → 显 ErrorState
      final container = ProviderContainer(overrides: [
        recognize.profileRepoProvider.overrideWithValue(
          AsyncValue<ProfileRepository>.error(
            Exception('mock load fail'),
            StackTrace.empty,
          ),
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfilePage()),
      ));
      // 用 pump 而非 pumpAndSettle：LoadingState 的 CircularProgressIndicator 永远
      // 调度下一帧，pumpAndSettle 会卡到 timeout。pump 推进足够时间让
      // _loadProfile 的 microtask 跑完 + catch + setState 触发 rebuild。
      // 多 pump 几次让 riverpod FutureProvider 状态流转 + await 恢复 + rebuild 链路跑完。
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // 断言显示 ErrorState（而非空白表单）
      expect(find.byType(ErrorState), findsOneWidget,
          reason: '加载失败时应显示 ErrorState');
      // 断言不显示表单字段（"保存并重算目标" 按钮不应出现）
      expect(find.text('保存并重算目标'), findsNothing,
          reason: '加载失败时不应显示空白表单');
    });

    testWidgets('点击重试重新加载', (tester) async {
      // 表单分组到 3 张 Card 后整体变高，用超高视口让全部内容一次性构建
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // 初始 override 为 AsyncError（首次加载失败触发 ErrorState）
      // 用变量持有 override 引用：重试前调 updateOverrides 切到 AsyncData
      // （riverpod 3.3.x overrideWith + throw 不传 .future，必须用 overrideWithValue）
      var override = recognize.profileRepoProvider.overrideWithValue(
        AsyncValue<ProfileRepository>.error(
          Exception('mock load fail'),
          StackTrace.empty,
        ),
      );

      final container = ProviderContainer(overrides: [override]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfilePage()),
      ));
      // pump 推进 microtask + rebuild（同上，避免 LoadingState 卡 pumpAndSettle）
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // 第一次加载失败 → ErrorState
      expect(find.byType(ErrorState), findsOneWidget,
          reason: '首次加载失败应显示 ErrorState');

      // 切换 override 为 AsyncData（模拟重试时 DB 已可读）
      // 必须在点击重试前更新，retry 中 ref.invalidate 会重新读 override
      override = recognize.profileRepoProvider.overrideWithValue(
        AsyncValue<ProfileRepository>.data(ProfileRepository(db)),
      );
      container.updateOverrides([override]);

      // 点击 ErrorState 中的重试按钮
      await tester.tap(find.text('重试'));
      // 多 pump 几次让 retry handler → invalidate → _loadProfile → await →
      // repo.get → setState rebuild 链路跑完
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // 第二次加载成功 → 显示表单（不再显示 ErrorState）
      expect(find.byType(ErrorState), findsNothing,
          reason: '重试成功后应不再显示 ErrorState');
      expect(find.text('保存并重算目标'), findsOneWidget,
          reason: '重试成功后应显示表单');
    });
  });

  /// M25 P1 修复测试：4 个数值字段范围校验 + goalRate 改 TextFormField + 0.1-2.0 校验
  ///
  /// 修复背景：原表单无范围校验，用户可输入身高 0 / 体重 9999 / goalRate 5.0 等
  /// 不合理值，导致 NutritionCalculator 重算出离谱目标（如 -3000 kcal/天）。
  ///
  /// 测试策略：widget test，pump ProfilePage 后通过 labelText 定位 TextFormField，
  /// 输入无效值后点"保存并重算目标"按钮触发 Form.validate()，
  /// 验证 validator 返回的 errorText 显示在界面上。
  group('ProfilePage 字段范围校验', () {
    /// 用内存 DB + 超高视口（1600）pump ProfilePage，让全部 Form 字段一次性构建。
    /// 表单分组到 3 张 Card 后整体变高，避免 ListView 懒加载截断导致字段不可见。
    Future<void> pumpProfilePage(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfilePage()),
      ));
      // _loadProfile 是异步：等 db onCreate 默认 profile 写入 + repo.get 返回 + 字段赋值
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    /// 通过 InputDecoration.labelText 定位字段。
    /// 注：TextFormField 的 decoration 是构造函数参数（非 public getter），
    /// 但其内部构建的 TextField 有 public `decoration` 字段，labelText 透传过去。
    /// 故用 TextField 而非 TextFormField 来匹配 labelText。
    Finder fieldByLabel(String label) => find.byWidgetPredicate((widget) {
          if (widget is TextField) {
            return widget.decoration?.labelText == label;
          }
          return false;
        });

    /// 选目标：用 Key 精确定位 goal DropdownMenu，点开菜单选目标。
    /// 减脂/增肌时 goalRate 字段才会渲染（条件 if (_goal == 'cut' || _goal == 'bulk')）
    Future<void> selectGoal(WidgetTester tester, String label) async {
      final goalMenu = find.byKey(const Key('goal_dropdown'));
      await tester.tap(find
          .descendant(
              of: goalMenu, matching: find.byIcon(Icons.arrow_drop_down))
          .first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('身高 0 报错（含 50-250 提示）', (tester) async {
      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await pumpProfilePage(tester, container);

      await tester.enterText(fieldByLabel('身高 (cm)'), '0');
      await tester.pump();

      await tester.tap(find.text('保存并重算目标'));
      await tester.pump();

      expect(find.text('身高需在 50-250 cm 之间'), findsOneWidget,
          reason: '身高 0 应触发范围校验 errorText');
    });

    testWidgets('身高 999 报错（含 50-250 提示）', (tester) async {
      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await pumpProfilePage(tester, container);

      await tester.enterText(fieldByLabel('身高 (cm)'), '999');
      await tester.pump();

      await tester.tap(find.text('保存并重算目标'));
      await tester.pump();

      expect(find.text('身高需在 50-250 cm 之间'), findsOneWidget,
          reason: '身高 999 应触发范围校验 errorText');
    });

    testWidgets('体重 0 报错（含 20-300 提示）', (tester) async {
      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await pumpProfilePage(tester, container);

      await tester.enterText(fieldByLabel('体重 (kg)'), '0');
      await tester.pump();

      await tester.tap(find.text('保存并重算目标'));
      await tester.pump();

      expect(find.text('体重需在 20-300 kg 之间'), findsOneWidget,
          reason: '体重 0 应触发范围校验 errorText');
    });

    testWidgets('体重 9999 报错（含 20-300 提示）', (tester) async {
      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await pumpProfilePage(tester, container);

      await tester.enterText(fieldByLabel('体重 (kg)'), '9999');
      await tester.pump();

      await tester.tap(find.text('保存并重算目标'));
      await tester.pump();

      expect(find.text('体重需在 20-300 kg 之间'), findsOneWidget,
          reason: '体重 9999 应触发范围校验 errorText');
    });

    testWidgets('goalRate "abc" 报错（非数字）', (tester) async {
      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await pumpProfilePage(tester, container);

      // 选减脂让 goalRate 字段渲染
      await selectGoal(tester, '减脂');

      await tester.enterText(fieldByLabel('目标速率（kg/周）'), 'abc');
      await tester.pump();

      await tester.tap(find.text('保存并重算目标'));
      await tester.pump();

      expect(find.text('请输入有效数字'), findsOneWidget,
          reason: 'goalRate "abc" 应触发"请输入有效数字" errorText');
    });

    testWidgets('goalRate 5.0 报错（超 2.0 上限）', (tester) async {
      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await pumpProfilePage(tester, container);

      await selectGoal(tester, '减脂');

      await tester.enterText(fieldByLabel('目标速率（kg/周）'), '5.0');
      await tester.pump();

      await tester.tap(find.text('保存并重算目标'));
      await tester.pump();

      expect(find.text('目标速率需在 0.1-2.0 kg/周之间'), findsOneWidget,
          reason: 'goalRate 5.0 超过 2.0 上限应触发范围校验 errorText');
    });

    testWidgets('合法值通过校验（无 errorText 显示）', (tester) async {
      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await pumpProfilePage(tester, container);

      // 默认 profile（height=170 weight=70 age=30 maintain goalRate=0）值合法，
      // 不改任何字段直接点保存。validate 通过 → _save 继续 → 不显示 errorText。
      // 注：_save 成功会 Navigator.pop（home 唯一路由），表单可能消失；
      // 关键断言是"无 errorText"，无论表单是否还在都成立。
      await tester.tap(find.text('保存并重算目标'));
      await tester.pump();

      // 所有 validator errorText 都不应显示
      expect(find.text('身高需在 50-250 cm 之间'), findsNothing,
          reason: '合法值不应触发身高 errorText');
      expect(find.text('体重需在 20-300 kg 之间'), findsNothing,
          reason: '合法值不应触发体重 errorText');
      expect(find.text('年龄需在 10-120 岁之间'), findsNothing,
          reason: '合法值不应触发年龄 errorText');
      expect(find.text('目标速率需在 0.1-2.0 kg/周之间'), findsNothing,
          reason: '合法值不应触发 goalRate errorText');
      expect(find.text('请输入有效数字'), findsNothing,
          reason: '合法值不应触发"请输入有效数字" errorText');
    });
  });
}
