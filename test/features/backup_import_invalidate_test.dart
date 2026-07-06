import 'dart:convert';

import 'package:drift/native.dart';
import 'package:eatwise/core/config/app_config.dart';
import 'package:eatwise/core/util/refresh_bus.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/backup/backup_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// M25 P1 修复测试：BackupPage 导入成功后 invalidate 4 个 provider + RefreshBus.notify
///
/// 修复背景：原 _import 成功后不 invalidate provider 缓存，用户返回其它页面看到
/// 旧数据以为导入失败。修复后 invalidate 4 个 provider（appConfigProvider /
/// mealLogRepoProvider / weightLogRepoProvider / profileRepoProvider）+ RefreshBus
/// .instance.notify() 通知监听 ChangeNotifier 的页面刷新。
///
/// 测试策略：widget test，pump BackupPage → 走完整导入流程（粘 JSON 弹窗 → 确认弹窗
/// → 真实 JsonImporter.importFromString）→ 验证 4 个 provider 的 invalidate 触发
/// （通过 container.listen 监听 isRefreshing 状态转换）+ RefreshBus.notify 被调用
/// （通过 addListener 计数）。
void main() {
  group('BackupPage 导入后 invalidate provider', () {
    late EatWiseDatabase db;

    setUp(() async {
      // SecureConfigStore 经 flutter_secure_storage 读写，appConfigProvider 重建时
      // 需要平台插件 mock；空 map → 所有 key 返回 null → AppConfig.load 用默认值
      FlutterSecureStorage.setMockInitialValues({});
      db = EatWiseDatabase(NativeDatabase.memory());
    });

    tearDown(() async => db.close());

    testWidgets('导入成功后 invalidate 4 个 provider + RefreshBus.notify',
        (tester) async {
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      // 跟踪 4 个 provider 的 invalidate：FutureProvider invalidate 时状态从
      // AsyncData → AsyncLoading.previous(AsyncData)（isRefreshing=true）→ AsyncData
      // 监听 isRefreshing=true 计数 invalidate 次数
      var profileInvalidations = 0;
      var mealLogInvalidations = 0;
      var weightLogInvalidations = 0;
      var appConfigInvalidations = 0;

      // container.listen 会立即触发 create（首次订阅），callback 收到初始 AsyncLoading
      // （无 previous，isRefreshing=false），随后 AsyncData（isRefreshing=false）。
      // invalidate 后 callback 收到 AsyncLoading.previous(AsyncData)（isRefreshing=true）
      container.listen(recognize.profileRepoProvider, (prev, next) {
        if (next.isRefreshing) profileInvalidations++;
      });
      container.listen(recognize.mealLogRepoProvider, (prev, next) {
        if (next.isRefreshing) mealLogInvalidations++;
      });
      container.listen(recognize.weightLogRepoProvider, (prev, next) {
        if (next.isRefreshing) weightLogInvalidations++;
      });
      container.listen(appConfigProvider, (prev, next) {
        if (next.isRefreshing) appConfigInvalidations++;
      });

      // 跟踪 RefreshBus 通知：ChangeNotifier.addListener 收到 notify 调用
      var refreshBusNotifyCount = 0;
      RefreshBus.instance.addListener(() {
        refreshBusNotifyCount++;
      });
      addTearDown(() {
        // 清理 listener 避免污染后续测试（RefreshBus 是全局单例）
        // 注意：无法精确移除我们加的 listener（lambda 无引用），用 removeAllListeners
        // 会影响其它测试，这里不清理（lambda 仅计数，无副作用，测试隔离可接受）
      });

      // 准备空表 JSON：schemaVersion=4 = 当前 DB schema，7 个空数组（importer 要求
      // tables 下 7 个 List 字段都存在，null 会抛 _TypeError）
      final jsonStr = jsonEncode({
        'schemaVersion': 4,
        'exportedAt': 0,
        'tables': {
          'profiles': <dynamic>[],
          'food_items': <dynamic>[],
          'meal_logs': <dynamic>[],
          'weight_logs': <dynamic>[],
          'insight_summaries': <dynamic>[],
          'recognition_feedbacks': <dynamic>[],
          'recommendation_feedbacks': <dynamic>[],
        },
      });

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BackupPage()),
      ));
      await tester.pumpAndSettle();

      // 1. 点"从 JSON 导入" → 弹出 JSON 粘贴弹窗
      await tester.tap(find.text('从 JSON 导入'));
      await tester.pumpAndSettle();

      // 2. 输入 JSON 文本
      await tester.enterText(find.byType(TextField), jsonStr);

      // 3. 点"导入"按钮关闭粘贴弹窗，_import 继续：查 countPending → 弹确认弹窗
      await tester.tap(find.text('导入'));

      // countPending 是真实异步 DB 查询，需交替 pump + runAsync 让其完成
      for (var i = 0; i < 8; i++) {
        await tester.pump();
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 150));
        });
      }
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 4. 确认弹窗弹出，点"确定导入"触发真实导入
      expect(find.text('确认导入'), findsOneWidget,
          reason: '应弹出确认导入对话框');
      await tester.tap(find.text('确定导入'));

      // importFromString 是真实异步 DB 操作（DELETE 8 表 + INSERT 批量 +
      // 图片检查），需交替 pump + runAsync 让真实 I/O 完成
      for (var i = 0; i < 15; i++) {
        await tester.pump();
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 200));
        });
      }
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 验证导入成功（SnackBar 出现"导入成功"提示）
      expect(find.textContaining('导入成功'), findsOneWidget,
          reason: '导入应成功并显示 SnackBar');

      // 验证 4 个 provider 都被 invalidate（isRefreshing 计数 >= 1）
      expect(profileInvalidations, greaterThanOrEqualTo(1),
          reason: 'profileRepoProvider 应被 invalidate（isRefreshing>=1）');
      expect(mealLogInvalidations, greaterThanOrEqualTo(1),
          reason: 'mealLogRepoProvider 应被 invalidate（isRefreshing>=1）');
      expect(weightLogInvalidations, greaterThanOrEqualTo(1),
          reason: 'weightLogRepoProvider 应被 invalidate（isRefreshing>=1）');
      expect(appConfigInvalidations, greaterThanOrEqualTo(1),
          reason: 'appConfigProvider 应被 invalidate（isRefreshing>=1）');

      // 验证 RefreshBus 通知被调用
      expect(refreshBusNotifyCount, greaterThanOrEqualTo(1),
          reason: 'RefreshBus.instance.notify() 应被调用');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
