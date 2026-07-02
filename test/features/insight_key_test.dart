// test/features/insight_key_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/insight/insight_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 Insight 页 GLM key 从 appConfigProvider 读取
/// key 为空时显示"到设置页填写"提示（验证迁移生效）
/// databaseProvider override 为内存 DB（InsightPage._generate 读 DB 取 meal/weight/profile）
void main() {
  testWidgets('GLM key 未配置时显示设置页引导', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // 不 override appConfigProvider：沙箱无 secure_storage，AppConfig.load() 抛 MissingPluginException，
    // appConfigProvider 进入 error 状态，glmApiKeyProvider 的 maybeWhen(orElse: () => '') 返回 ''
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InsightPage()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 点击"生成本周汇总"按钮触发 _generate
    await tester.tap(find.text('生成本周汇总'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 验证显示设置页引导（而非 --dart-define 提示）
    expect(find.textContaining('设置页'), findsWidgets);
    expect(find.textContaining('--dart-define'), findsNothing);
  });
}
