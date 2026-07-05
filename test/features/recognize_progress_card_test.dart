// M20 Round 2 Red：RecognizeProgressCard widget 测试
//
// 验证 4 阶段进度卡片（选图→压缩→AI 推理→查库回填）的状态切换、
// 进度条 value、文案加粗、勾图标/转圈图标显示。
//
// 设计：监听 RecognizeState，4 阶段逐步打勾 + 顶部进度条。
// - pickingImage：第 1 阶段 active
// - preprocessing：第 1 done + 第 2 active
// - recognizing：1-2 done + 第 3 active
// - lookupNutrition：1-3 done + 第 4 active
// - done：4 全 done
// - error/queued：特殊文案，不展示 4 阶段
//
// M22 适配：TweenAnimationBuilder 首帧从 begin=0 开始，需 pump(500ms) 到达终值再断言。
//   不用 pumpAndSettle——preprocessing/recognizing/lookupNutrition 有 CircularProgressIndicator
//   无限动画，pumpAndSettle 会 timeout。pump(500ms) 只推进 1 帧，TweenAnimationBuilder
//   (400ms) 与 AnimatedContainer (300ms) 均到达终值，无限 spinner 不影响断言。
import 'package:eatwise/features/recognize/recognize_controller.dart';
import 'package:eatwise/features/recognize/recognize_progress_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 用 M3 主题包裹，提供 ColorScheme
  Widget wrap(Widget child) => MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFF6750A4)),
        home: Scaffold(body: Center(child: child)),
      );

  // M22：pump 500ms 让 TweenAnimationBuilder(400ms) 和 AnimatedContainer(300ms) 到达终值
  // 不用 pumpAndSettle——避免 CircularProgressIndicator 无限动画 timeout
  const settleDuration = Duration(milliseconds: 500);

  group('RecognizeProgressCard 4 阶段进度', () {
    testWidgets('pickingImage：第 1 阶段 active，进度 0/4', (tester) async {
      await tester.pumpWidget(wrap(const RecognizeProgressCard(
        currentState: RecognizeState.pickingImage,
      )));
      await tester.pump(settleDuration);
      // 第 1 阶段文案存在
      expect(find.text('选图中…'), findsOneWidget);
      // 第 2-4 阶段文案存在
      expect(find.text('压缩图中…'), findsOneWidget);
      expect(find.text('AI 推理中…'), findsOneWidget);
      expect(find.text('查库回填中…'), findsOneWidget);
      // 进度条 value = 0/4 = 0.0
      final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(progress.value, 0.0);
      // 第 1 阶段是当前（显示转圈）
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // 没有已完成的勾（pickingImage 是第一个，无已完成）
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('preprocessing：第 1 done + 第 2 active，进度 1/4', (tester) async {
      await tester.pumpWidget(wrap(const RecognizeProgressCard(
        currentState: RecognizeState.preprocessing,
      )));
      await tester.pump(settleDuration);
      final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(progress.value, 0.25);
      // 第 1 阶段已完成（显示勾）
      expect(find.byIcon(Icons.check), findsOneWidget);
      // 第 2 阶段当前（显示转圈）
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('recognizing：1-2 done + 第 3 active，进度 2/4', (tester) async {
      await tester.pumpWidget(wrap(const RecognizeProgressCard(
        currentState: RecognizeState.recognizing,
      )));
      await tester.pump(settleDuration);
      final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(progress.value, 0.5);
      expect(find.byIcon(Icons.check), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('lookupNutrition：1-3 done + 第 4 active，进度 3/4', (tester) async {
      await tester.pumpWidget(wrap(const RecognizeProgressCard(
        currentState: RecognizeState.lookupNutrition,
      )));
      await tester.pump(settleDuration);
      final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(progress.value, 0.75);
      expect(find.byIcon(Icons.check), findsNWidgets(3));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('done：4 阶段全 done，进度 4/4', (tester) async {
      await tester.pumpWidget(wrap(const RecognizeProgressCard(
        currentState: RecognizeState.done,
      )));
      await tester.pump(settleDuration);
      final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(progress.value, 1.0);
      expect(find.byIcon(Icons.check), findsNWidgets(4));
      // done 态无转圈
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('RecognizeProgressCard 特殊状态', () {
    testWidgets('error：显示"识别失败"特殊文案，不展示 4 阶段进度', (tester) async {
      await tester.pumpWidget(wrap(const RecognizeProgressCard(
        currentState: RecognizeState.error,
      )));
      expect(find.text('识别失败'), findsOneWidget);
      // 不展示 4 阶段文案
      expect(find.text('选图中…'), findsNothing);
      expect(find.text('AI 推理中…'), findsNothing);
    });

    testWidgets('queued：显示"已加入离线队列"特殊文案', (tester) async {
      await tester.pumpWidget(wrap(const RecognizeProgressCard(
        currentState: RecognizeState.queued,
      )));
      expect(find.textContaining('离线队列'), findsOneWidget);
      // 不展示 4 阶段文案
      expect(find.text('选图中…'), findsNothing);
    });

    testWidgets('idle：4 阶段全 pending，进度 0/4（不应出现，但兜底）', (tester) async {
      await tester.pumpWidget(wrap(const RecognizeProgressCard(
        currentState: RecognizeState.idle,
      )));
      await tester.pump(settleDuration);
      final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(progress.value, 0.0);
      // 无勾、无转圈（全 pending）
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('RecognizeProgressCard 视觉细节', () {
    testWidgets('当前阶段文案加粗（preprocessing 态）', (tester) async {
      await tester.pumpWidget(wrap(const RecognizeProgressCard(
        currentState: RecognizeState.preprocessing,
      )));
      await tester.pump(settleDuration);
      // 第 2 阶段"压缩图中…"是当前，应加粗
      final activeText = tester.widget<Text>(find.text('压缩图中…'));
      expect((activeText.style?.fontWeight ?? FontWeight.normal),
          FontWeight.bold,
          reason: '当前阶段文案应加粗');
      // 第 1 阶段"选图中…"已完成，应加粗（已完成也强调）
      final doneText = tester.widget<Text>(find.text('选图中…'));
      expect((doneText.style?.fontWeight ?? FontWeight.normal),
          FontWeight.bold,
          reason: '已完成阶段文案应加粗');
      // 第 3 阶段"AI 推理中…"未到，应默认字重
      final pendingText = tester.widget<Text>(find.text('AI 推理中…'));
      expect((pendingText.style?.fontWeight ?? FontWeight.normal),
          FontWeight.normal,
          reason: '未到阶段文案应默认字重');
    });

    testWidgets('已完成阶段显示勾图标，当前阶段显示转圈', (tester) async {
      await tester.pumpWidget(wrap(const RecognizeProgressCard(
        currentState: RecognizeState.recognizing,
      )));
      await tester.pump(settleDuration);
      // 第 1-2 阶段已完成（2 个勾）
      expect(find.byIcon(Icons.check), findsNWidgets(2));
      // 第 3 阶段当前（1 个转圈）
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // 第 4 阶段未到（无勾无转圈）
      // 总勾数 + 转圈数 = 3（已完成 2 + 当前 1）
    });
  });

  // M22 新增：动画测试
  group('RecognizeProgressCard 动画（M22）', () {
    testWidgets('进度条用 TweenAnimationBuilder 平滑插值', (tester) async {
      await tester.pumpWidget(wrap(const RecognizeProgressCard(
        currentState: RecognizeState.preprocessing,
      )));
      // 应存在 TweenAnimationBuilder 包裹 LinearProgressIndicator
      //（用 byWidgetPredicate 而非 byType——Dart 泛型不变，
      //  TweenAnimationBuilder<double> 不是 TweenAnimationBuilder<Object?>）
      expect(find.byWidgetPredicate((w) => w is TweenAnimationBuilder),
          findsWidgets);
      // pump 让动画到达终值
      await tester.pump(settleDuration);
      final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(progress.value, 0.25);
    });

    testWidgets('done 态显示成功反馈图标（M22 新增）', (tester) async {
      await tester.pumpWidget(wrap(const RecognizeProgressCard(
        currentState: RecognizeState.done,
      )));
      await tester.pump(settleDuration);
      // done 态除了 4 个阶段勾（Icons.check），还应有一个成功反馈图标（Icons.check_circle）
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('状态圆圈用 AnimatedContainer 颜色过渡', (tester) async {
      await tester.pumpWidget(wrap(const RecognizeProgressCard(
        currentState: RecognizeState.preprocessing,
      )));
      // 应存在 AnimatedContainer（状态圆圈颜色过渡）
      expect(find.byType(AnimatedContainer), findsWidgets);
    });
  });
}
