// test/features/dashboard/dashboard_page_test.dart
// Dashboard 页面可访问性 + 关键分支守护测试
import 'package:drift/native.dart';
import 'package:eatwise/core/config/app_config.dart';
import 'package:eatwise/core/config/secure_config_store.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/dashboard/dashboard_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dashboard 页面关键分支守护测试（M24 B5 拆分前先建安全网）
///
/// 覆盖：
/// - _regenerateButton 触控目标 ≥48dp（A2 修复，避免回归）
/// - 状态卡渲染（"今日还可摄入" + kcal 文案）
/// - 空态显示（无 meal_log 时"今日还没有记录"）
/// - AI 失败时 v4 兜底显示（"已切换本地推荐"错误提示）
void main() {
  // 共用 setup：fake GLM key + 强制离线，触发 _regenerateButton 渲染（isRetry=true）
  Future<ProviderContainer> buildContainer({
    required EatWiseDatabase db,
  }) async {
    FlutterSecureStorage.setMockInitialValues({
      'glm_api_key': 'fake-key-for-test',
    });
    final store = SecureConfigStore();
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
      secureConfigStoreProvider.overrideWithValue(store),
      // 强制离线：触发 _loadAiRecommendations 返回 error，渲染重试按钮
      recognize.networkAvailableProvider.overrideWith((ref) async => false),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpDashboard(WidgetTester tester, ProviderContainer container,
      {EatWiseDatabase? db}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  testWidgets('_regenerateButton 触控目标 ≥48dp', (tester) async {
    // 注入 fake GLM key：使 _loadAiRecommendations 走到"离线守卫"分支，
    // 返回带 error 的 AiRecommendationResult，从而触发 _regenerateButton
    // 以 isRetry=true（文案"重试"）渲染。
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = await buildContainer(db: db);
    await pumpDashboard(tester, container);

    // 找到"重试"按钮（_regenerateButton 在 isRetry=true 时文案为"重试"）
    final retryBtn = find.ancestor(
      of: find.text('重试'),
      matching: find.byType(TextButton),
    );
    expect(retryBtn, findsOneWidget, reason: '_regenerateButton（重试）应渲染');

    // 触控目标 = 渲染尺寸（Material 3 最小 48×48dp 可访问性规范）
    final size = tester.getSize(retryBtn);
    expect(size.width, greaterThanOrEqualTo(48.0),
        reason: '_regenerateButton 触控目标宽度应 ≥48dp (MD3 可访问性)');
    expect(size.height, greaterThanOrEqualTo(48.0),
        reason: '_regenerateButton 触控目标高度应 ≥48dp (MD3 可访问性)');
  });

  testWidgets('状态卡渲染：显示"今日还可摄入" + kcal 文案', (tester) async {
    // 守护 _statusCard 关键文案渲染（M24 B5 拆分前先建安全网）
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = await buildContainer(db: db);
    await pumpDashboard(tester, container);

    // 状态卡标题"今日还可摄入"
    expect(find.text('今日还可摄入'), findsOneWidget,
        reason: '_statusCard 应显示"今日还可摄入"标题');
    // 副标题含 "kcal"（"kcal · 已摄入 X / Y"）
    expect(find.textContaining('kcal'), findsWidgets,
        reason: '_statusCard 应显示 kcal 单位文案');
    // 三宏标签
    expect(find.text('蛋白'), findsOneWidget,
        reason: '_statusCard 应显示"蛋白"宏量行');
    expect(find.text('脂肪'), findsOneWidget,
        reason: '_statusCard 应显示"脂肪"宏量行');
    expect(find.text('碳水'), findsOneWidget,
        reason: '_statusCard 应显示"碳水"宏量行');
  });

  testWidgets('空态显示：无 meal_log 时显示"今日还没有记录"', (tester) async {
    // 守护 _mealsSection 空态分支（M24 B5 拆分前先建安全网）
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = await buildContainer(db: db);
    await pumpDashboard(tester, container);

    // 空态标题
    expect(find.text('今日还没有记录'), findsOneWidget,
        reason: '_mealsSection 空态应显示"今日还没有记录"标题');
    // 空态副标题
    expect(find.text('点下方拍照按钮开始记录'), findsOneWidget,
        reason: '_mealsSection 空态应显示副标题');
    // 空态操作按钮
    expect(find.text('去拍照'), findsOneWidget,
        reason: '_mealsSection 空态应显示"去拍照"按钮');
  });

  testWidgets('AI 失败时 v4 兜底显示"已切换本地推荐"提示', (tester) async {
    // 守护 _recommendationSection AI 失败分支（M24 B5 拆分前先建安全网）
    // fake GLM key + 强制离线 → _loadAiRecommendations 返回 error="当前无网络，已切换本地推荐"
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = await buildContainer(db: db);
    await pumpDashboard(tester, container);

    // AI 错误提示（_aiErrorHint 显示 message）
    expect(find.text('当前无网络，已切换本地推荐'), findsOneWidget,
        reason: '_aiErrorHint 应显示离线错误提示');
    // 智能推荐章节标题（_recommendationSection 顶层）
    expect(find.text('智能推荐'), findsOneWidget,
        reason: '_recommendationSection 应显示"智能推荐"标题');
  });
}
