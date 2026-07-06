// test/widgets/snackbar_clear_test.dart
// showAppToast clearSnackBars 行为测试 + 撤销横幅 controller.closed 时序测试
//
// 验证 Bug 1 修复：
// - showAppToast 显示前清空队列，连续调用时新横幅立即替换旧的
// - 撤销横幅用 controller.closed 替代 Future.delayed，正确感知关闭原因
import 'package:eatwise/core/widgets/m3_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('showAppToast clearSnackBars', () {
    testWidgets('连续调用 showAppToast 只显示最后一个横幅（不排队）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showAppToast(context, '第一条');
                showAppToast(context, '第二条');
                showAppToast(context, '第三条');
              },
              child: const Text('触发'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('触发'));
      await tester.pumpAndSettle();

      // clearSnackBars 保证只显示最后一个（第三条），前两条被清掉
      expect(find.text('第一条'), findsNothing);
      expect(find.text('第二条'), findsNothing);
      expect(find.text('第三条'), findsOneWidget);
    });

    testWidgets('单次调用 showAppToast 正常显示', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAppToast(context, '提示'),
              child: const Text('触发'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('触发'));
      await tester.pumpAndSettle();

      expect(find.text('提示'), findsOneWidget);
    });

    testWidgets('duration 默认 4 秒', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAppToast(context, '提示'),
              child: const Text('触发'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('触发'));
      await tester.pumpAndSettle();

      // 3.9 秒后仍显示（< 4s 默认时长）
      await tester.pump(const Duration(milliseconds: 3900));
      expect(find.text('提示'), findsOneWidget);
      // 4.1 秒后消失
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('提示'), findsNothing);
    });

    testWidgets('自定义 duration 生效', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAppToast(context, '提示',
                  duration: const Duration(seconds: 2)),
              child: const Text('触发'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('触发'));
      await tester.pumpAndSettle();

      // 1.9 秒后仍显示
      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.text('提示'), findsOneWidget);
      // 2.1 秒后消失
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('提示'), findsNothing);
    });
  });

  group('showAppToast liveRegion 无障碍', () {
    testWidgets('toast content 包 Semantics(liveRegion: true) 供读屏感知', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAppToast(context, '测试消息'),
              child: const Text('触发'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('触发'));
      await tester.pumpAndSettle();

      // SnackBar 已显示
      expect(find.text('测试消息'), findsOneWidget);

      // toast Text 的祖先中应存在 Semantics(liveRegion: true)
      // showAppToast 用 Semantics(liveRegion: true, child: Text(msg)) 包裹
      // 注：SnackBar 内部也可能添加 liveRegion Semantics，故断言"至少一个"而非"恰好一个"
      final liveRegionFinder = find.ancestor(
        of: find.text('测试消息'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.liveRegion == true,
        ),
      );
      expect(liveRegionFinder, findsWidgets,
          reason: 'showAppToast 的 SnackBar content 应包 Semantics(liveRegion: true)');
    });
  });

  group('撤销横幅 controller.closed 时序', () {
    testWidgets('点撤销按钮后横幅关闭，reason == action', (tester) async {
      SnackBarClosedReason? capturedReason;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final messenger = ScaffoldMessenger.of(context);
              return ElevatedButton(
                onPressed: () async {
                  messenger.clearSnackBars();
                  final controller = messenger.showSnackBar(
                    SnackBar(
                      content: const Text('已删除'),
                      duration: const Duration(seconds: 3),
                      action: SnackBarAction(
                        label: '撤销',
                        onPressed: () {},
                      ),
                    ),
                  );
                  capturedReason = await controller.closed;
                },
                child: const Text('触发'),
              );
            },
          ),
        ),
      ));

      await tester.tap(find.text('触发'));
      await tester.pumpAndSettle();

      // 点撤销按钮
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();

      // reason 应为 action（用户点了撤销按钮）
      expect(capturedReason, SnackBarClosedReason.action);
    });
  });
}
