// test/features/error_message_friendly_test.dart
//
// C 类修复 3：错误文案友好化测试
//
// 验证 3 个代表性页面的 catch 块把 $e 替换为友好文案 + debugPrint：
// - backup_page 导出失败 → toast 含"导出失败"不含异常类名
// - update_page 检查失败 → error 态 Text 含"检查更新失败"不含异常
// - profile_page 保存失败 → toast 含"保存失败"不含异常
//
// 实现方式：widget test，mock 各页依赖抛异常，验证 UI 文案。
import 'package:drift/native.dart';
import 'package:eatwise/core/update/update_service.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/features/backup/backup_page.dart';
import 'package:eatwise/features/profile/profile_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:eatwise/features/update/update_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 返回不存在的路径，让 File.writeAsString 抛 FileSystemException
class _BadPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      '/nonexistent_eatwise_test_dir_xyz';
}

class MockUpdateService extends Mock implements UpdateService {}

class MockProfileRepository extends Mock implements ProfileRepository {}

void main() {
  group('backup_page 导出失败友好文案', () {
    testWidgets('导出失败 toast 含"导出失败"不含异常类名', (tester) async {
      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // 路径返回不存在目录 → File.writeAsString 抛 FileSystemException
      PathProviderPlatform.instance = _BadPathProvider();

      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BackupPage()),
      ));
      await tester.pumpAndSettle();

      // 触发导出：_export 含多段串行真实异步（DB 查询 + path 获取 + 文件写入），
      // 需交替 pump + runAsync 多轮让异步走完
      await tester.tap(find.text('导出为 JSON'));
      for (var i = 0; i < 8; i++) {
        await tester.pump();
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 250));
        });
      }
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 友好文案显示
      expect(find.textContaining('导出失败'), findsOneWidget);
      // 异常类名不泄露给用户
      expect(find.textContaining('FileSystemException'), findsNothing);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('update_page 检查更新失败友好文案', () {
    testWidgets('检查失败 error 态含"检查更新失败"不含异常', (tester) async {
      final service = MockUpdateService();
      // mock checkForUpdate 抛异常 → catch 块设 _errorMsg 为友好文案
      when(() => service.checkForUpdate())
          .thenThrow(Exception('mock check fail'));

      final container = ProviderContainer(overrides: [
        recognize.updateServiceProvider.overrideWith((ref) async => service),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: UpdatePage()),
      ));
      await tester.pump();

      await tester.tap(find.text('检查更新'));
      await tester.pump(); // 触发 checking → mock 抛异常 → catch → error 态
      await tester.pumpAndSettle();

      // 友好文案显示
      expect(find.textContaining('检查更新失败'), findsOneWidget);
      // 异常消息不泄露给用户
      expect(find.textContaining('mock check fail'), findsNothing);
    });
  });

  group('profile_page 保存失败友好文案', () {
    testWidgets('保存失败 toast 含"保存失败"不含异常', (tester) async {
      // 表单分组到 3 张 Card 后整体变高，用超高视口让全部内容一次性构建
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockRepo = MockProfileRepository();
      final testProfile = Profile(
        id: 1,
        heightCm: 170,
        weightKg: 70,
        age: 30,
        gender: 'male',
        activityLevel: 1.375,
        goal: 'maintain',
        goalRateKgPerWeek: 0,
        formula: 'mifflin',
        dailyCalorieTarget: 2000,
        proteinGPerKg: 1.4,
        fatGPerKg: 0.9,
        tdeeAdjustmentKcal: 0,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      // get 成功（_loadProfile 填充表单 + _save 读 existing）
      when(() => mockRepo.get()).thenAnswer((_) async => testProfile);
      // update 抛异常 → catch 块 showAppToast 友好文案
      when(() => mockRepo.update(
            heightCm: any(named: 'heightCm'),
            weightKg: any(named: 'weightKg'),
            bodyFatPct: any(named: 'bodyFatPct'),
            age: any(named: 'age'),
            gender: any(named: 'gender'),
            activityLevel: any(named: 'activityLevel'),
            goal: any(named: 'goal'),
            goalRateKgPerWeek: any(named: 'goalRateKgPerWeek'),
            formula: any(named: 'formula'),
            dailyCalorieTarget: any(named: 'dailyCalorieTarget'),
            proteinGPerKg: any(named: 'proteinGPerKg'),
            fatGPerKg: any(named: 'fatGPerKg'),
            carbGPerKg: any(named: 'carbGPerKg'),
            tdeeAdjustmentKcal: any(named: 'tdeeAdjustmentKcal'),
            specialCondition: any(named: 'specialCondition'),
            dietPreference: any(named: 'dietPreference'),
            healthCondition: any(named: 'healthCondition'),
          )).thenThrow(Exception('mock save fail'));

      final container = ProviderContainer(overrides: [
        recognize.profileRepoProvider.overrideWithValue(
          AsyncValue<ProfileRepository>.data(mockRepo),
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfilePage()),
      ));
      // 等 _loadProfile 完成（mock get 返回 → 填充表单 → _loading=false）
      // 用 pump 而非 pumpAndSettle：LoadingState 的 CircularProgressIndicator 永远
      // 调度下一帧，pumpAndSettle 会卡到 timeout
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 确认表单已加载
      expect(find.text('保存并重算目标'), findsOneWidget);

      // 点保存 → _save → repo.get()（成功）→ repo.update()（抛异常）→ catch → toast
      await tester.tap(find.text('保存并重算目标'));
      // _save 含多个 await，需多轮 pump 让 microtask 跑完
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // 友好文案显示
      expect(find.textContaining('保存失败'), findsOneWidget);
      // 异常消息不泄露给用户
      expect(find.textContaining('mock save fail'), findsNothing);
    });
  });
}
