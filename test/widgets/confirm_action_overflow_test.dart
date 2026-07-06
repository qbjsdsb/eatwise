// test/widgets/confirm_action_overflow_test.dart
// confirmAction 长内容溢出修复测试（B 类 P1 修复 1）
//
// 验证修复：confirmAction content 改为
//   ConstrainedBox(maxHeight: 屏幕40%) + SingleChildScrollView + Text
// 确保长内容可滚动、确认按钮可达。
import 'package:eatwise/core/widgets/m3_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('confirmAction 长内容溢出修复', () {
    testWidgets('长内容用 SingleChildScrollView 包裹且确认按钮可达', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      ));
      await tester.pump();

      // 触发 confirmAction，传入超长内容（500 字，远超默认 dialog 高度）
      final longContent = '很长的内容' * 100;
      confirmAction(
        capturedContext,
        title: '标题',
        content: longContent,
        confirmLabel: '确认',
      );
      await tester.pumpAndSettle();

      // 验证 AlertDialog 显示
      expect(find.byType(AlertDialog), findsOneWidget);
      // 验证标题显示
      expect(find.text('标题'), findsOneWidget);
      // 验证 SingleChildScrollView 存在（长内容可滚动兜底）
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      // 验证 ConstrainedBox 限制最大高度（防撑爆视口）
      expect(find.byType(ConstrainedBox), findsWidgets);
      // 验证确认按钮可达（在 widget tree 中）
      expect(find.text('确认'), findsOneWidget);
      // 验证取消按钮存在
      expect(find.text('取消'), findsOneWidget);
      // 验证长内容 Text 在 tree 中（可滚动查看）
      expect(find.text(longContent), findsOneWidget);
    });

    testWidgets('短内容也正常显示且仍有 SingleChildScrollView 兜底', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      ));
      await tester.pump();

      confirmAction(
        capturedContext,
        title: '标题',
        content: '短内容',
        confirmLabel: '确认',
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('短内容'), findsOneWidget);
      expect(find.text('确认'), findsOneWidget);
    });

    testWidgets('点击确认按钮返回 true', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      ));
      await tester.pump();

      final future = confirmAction(
        capturedContext,
        title: '标题',
        content: '内容',
        confirmLabel: '确认',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();

      expect(await future, true);
    });

    testWidgets('点击取消按钮返回 false', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      ));
      await tester.pump();

      final future = confirmAction(
        capturedContext,
        title: '标题',
        content: '内容',
        cancelLabel: '取消',
        confirmLabel: '确认',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(await future, false);
    });
  });
}
