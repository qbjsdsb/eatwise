import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/insight/insight_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 InsightPage 离线守卫：
/// - networkAvailableProvider 返回 false 时点生成 → 显示无网络提示
/// - 不调用 GLM provider（不产生 API 调用）
void main() {
  testWidgets('离线时点生成显示无网络提示', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
      recognize.glmApiKeyProvider.overrideWith((ref) => 'fake-key'),
      // 模拟离线
      recognize.networkAvailableProvider.overrideWith((ref) async => false),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: InsightPage()),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // _summary 为空时按钮文案是"生成本周汇总"
    expect(find.text('生成本周汇总'), findsOneWidget);
    await tester.tap(find.text('生成本周汇总'));
    await tester.pumpAndSettle();

    // 验证无网络提示出现
    expect(find.textContaining('当前无网络'), findsOneWidget);
  });
}
