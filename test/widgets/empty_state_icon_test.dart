// test/widgets/empty_state_icon_test.dart
// EmptyState actionIcon 参数测试（C 类修复 2）
//
// 验证修复：
// - EmptyState 新增 actionIcon 参数（默认 Icons.camera_alt_rounded）
// - 调用方可传自定义图标覆盖默认值
// - 不传 actionLabel/onAction 时按钮不渲染（actionIcon 也不渲染）
import 'package:eatwise/core/widgets/m3_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmptyState actionIcon', () {
    testWidgets('自定义 actionIcon 覆盖默认 camera_alt_rounded', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.inbox,
            title: '暂无数据',
            actionLabel: '添加',
            onAction: () {},
            actionIcon: Icons.add,
          ),
        ),
      ));

      // 传入的 Icons.add 应显示
      expect(find.byIcon(Icons.add), findsOneWidget);
      // 默认值 Icons.camera_alt_rounded 应被覆盖，不显示
      expect(find.byIcon(Icons.camera_alt_rounded), findsNothing);
    });

    testWidgets('不传 actionIcon 时用默认 camera_alt_rounded', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.inbox,
            title: '暂无数据',
            actionLabel: '添加',
            onAction: () {},
          ),
        ),
      ));

      // 默认值 Icons.camera_alt_rounded 应显示
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
    });

    testWidgets('不传 actionLabel/onAction 时不渲染按钮与 actionIcon', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.inbox,
            title: '暂无数据',
          ),
        ),
      ));

      // 无 actionLabel/onAction → FilledButton 不渲染
      expect(find.byType(FilledButton), findsNothing);
      // actionIcon 也不渲染
      expect(find.byIcon(Icons.camera_alt_rounded), findsNothing);
    });
  });
}
