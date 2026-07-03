// 保存→RefreshBus 通知链路测试
//
// 修复验证：profile_page / weight_page 保存后必须调 RefreshBus.notify()，
// 否则 dashboard（唯一刷新入口是 RefreshBus 监听）不会刷新，主页目标/宏量仍是旧值。
//
// 测试策略：注册 RefreshBus 监听器 → 触发保存 → 断言监听器被调用。
import 'package:drift/native.dart';
import 'package:eatwise/core/config/app_config.dart';
import 'package:eatwise/core/config/secure_config_store.dart';
import 'package:eatwise/core/util/refresh_bus.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/features/profile/profile_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:eatwise/features/weight/weight_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('RefreshBus 通知链路', () {
    testWidgets('ProfilePage 保存后 RefreshBus 收到通知', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      // 注册 RefreshBus 监听器
      int notifyCount = 0;
      void listener() => notifyCount++;
      RefreshBus.instance.addListener(listener);
      addTearDown(() => RefreshBus.instance.removeListener(listener));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfilePage()),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(notifyCount, 0, reason: '保存前不应有通知');

      // 点保存（默认表单值 maintain + goalRate=0 不触发风险弹窗）
      await tester.tap(find.text('保存并重算目标'));
      await tester.pumpAndSettle();

      expect(notifyCount, 1, reason: 'ProfilePage 保存后应通知 RefreshBus');
    });

    testWidgets('WeightPage 保存后 RefreshBus 收到通知', (tester) async {
      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // mock SecureConfigStore：tdeeAutoCalib=false 跳过 TDEE 校准块
      // （校准块调 appConfigProvider，依赖 flutter_secure_storage 平台通道，测试环境会卡）
      final mockStorage = _MockSecureStorage();
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      final store = SecureConfigStore.forTesting(mockStorage);

      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
        secureConfigStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);

      int notifyCount = 0;
      void listener() => notifyCount++;
      RefreshBus.instance.addListener(listener);
      addTearDown(() => RefreshBus.instance.removeListener(listener));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WeightPage()),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(notifyCount, 0, reason: '保存前不应有通知');

      // 输入体重并保存
      await tester.enterText(find.byType(TextField), '72.5');
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(notifyCount, 1, reason: 'WeightPage 保存后应通知 RefreshBus');
    });

    testWidgets('WeightPage 保存后同步 profile.weightKg', (tester) async {
      // 验证修复3：weight_page 录入体重后 profile.weightKg 同步更新
      // 否则 dashboard 宏量目标（proteinGPerKg * weightKg）仍用旧体重
      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final mockStorage = _MockSecureStorage();
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      final store = SecureConfigStore.forTesting(mockStorage);

      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
        secureConfigStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);

      final profileRepo = ProfileRepository(db);
      final before = await profileRepo.get();
      expect(before.weightKg, 70, reason: '默认 profile 体重应为 70');

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WeightPage()),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.enterText(find.byType(TextField), '72.5');
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final after = await profileRepo.get();
      expect(after.weightKg, 72.5,
          reason: 'weight_page 保存后 profile.weightKg 应同步为 72.5');
    });

    testWidgets('WeightPage 保存后 weight_logs 表也有记录', (tester) async {
      // 验证：同步 profile.weightKg 不影响 weight_logs 表写入
      final db = EatWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final mockStorage = _MockSecureStorage();
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      final store = SecureConfigStore.forTesting(mockStorage);

      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
        secureConfigStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WeightPage()),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.enterText(find.byType(TextField), '72.5');
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final logs = await db.select(db.weightLogs).get();
      expect(logs.length, 1);
      expect(logs.first.weightKg, 72.5);
    });
  });
}
