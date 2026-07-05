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
}
