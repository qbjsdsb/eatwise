import 'package:eatwise/features/manual_entry/manual_entry_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 ManualEntryPage 接受 initialName 并预填 + 默认进自定义模式
/// （recognize_page 的弹窗逻辑依赖 image_picker，沙箱无法 widget test，仅验证 ManualEntryPage 侧）
/// 注：自定义模式表单分组到 Card 后整体变高，用超高视口让全部内容一次性构建，避免 ListView 懒加载截断。
void main() {
  testWidgets('initialName 预填菜名并进入自定义模式', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ManualEntryPage(initialName: '宫保鸡丁'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 验证菜名已预填到 TextField
    expect(find.text('宫保鸡丁'), findsOneWidget);
    // 验证进入自定义模式（显示"存库并记录"按钮，而非"找不到？自定义输入"）
    expect(find.text('存库并记录'), findsOneWidget);
    expect(find.text('找不到？自定义输入'), findsNothing);
  });

  testWidgets('无 initialName 时默认搜库模式', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ManualEntryPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 验证默认搜库模式（显示"找不到？自定义输入"）
    expect(find.text('找不到？自定义输入'), findsOneWidget);
    expect(find.text('存库并记录'), findsNothing);
  });
}
