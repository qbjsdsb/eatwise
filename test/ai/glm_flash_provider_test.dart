import 'dart:async';
import 'dart:io';

import 'package:eatwise/ai/glm_flash_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// H3 修复：_buildPrompt/_buildMonthlyPrompt 核心字段无 null 兜底
/// 调用方传不完整 data 时（如 daily_calories 缺失）应不崩溃
void main() {
  group('H3 _buildPrompt null 兜底', () {
    final provider = GlmFlashProvider(apiKey: 'fake', baseUrl: 'http://test');

    test('weekly data 缺 daily_calories 时不崩溃', () {
      final data = {
        'daily_weights': [70.0],
        'target_calories': 2000,
        'goal': 'maintain',
        // 故意漏掉 daily_calories
      };
      expect(() => provider.buildWeeklySummaryForTest(data), returnsNormally);
    });

    test('weekly data 缺 daily_weights 时不崩溃', () {
      final data = {
        'daily_calories': [2000.0],
        'target_calories': 2000,
        'goal': 'maintain',
        // 故意漏掉 daily_weights
      };
      expect(() => provider.buildWeeklySummaryForTest(data), returnsNormally);
    });

    test('weekly data 缺 target_calories 和 goal 时不崩溃', () {
      final data = {
        'daily_calories': [2000.0],
        'daily_weights': [70.0],
        // 故意漏掉 target_calories 和 goal
      };
      expect(() => provider.buildWeeklySummaryForTest(data), returnsNormally);
    });

    test('monthly data 缺 daily_calories 时不崩溃', () {
      final data = {
        'daily_weights': [70.0],
        'target_calories': 2000,
        // 故意漏掉 daily_calories 和 goal
      };
      expect(() => provider.buildMonthlySummaryForTest(data), returnsNormally);
    });

    test('weekly data 完整时正常构建（无回归）', () {
      final data = {
        'daily_calories': [1800.0, 2000.0, 2200.0],
        'daily_weights': [70.0, 70.1, 70.2],
        'target_calories': 2000,
        'goal': 'cut',
        'daily_protein': [80.0, 90.0, 100.0],
        'daily_fat': [60.0, 65.0, 70.0],
        'daily_carbs': [200.0, 210.0, 220.0],
        'protein_goal': 100.0,
        'fat_goal': 65.0,
        'carb_goal': 220.0,
        'recorded_days': 3,
        'total_days': 7,
        'coverage_rate': 0.43,
        'preference_foods': ['鸡胸肉', '米饭'],
      };
      final prompt = provider.buildWeeklySummaryForTest(data);
      expect(prompt, contains('减脂'));
      expect(prompt, contains('2000'));
    });
  });

  // 防御性兜底测试（M1 宏量数组长度不一致）放到 group 外，确保即使 H3 修复后仍可运行
  test('M1: 宏量数组长度不一致时不崩溃（取最小长度）', () {
    final provider = GlmFlashProvider(apiKey: 'fake', baseUrl: 'http://test');
    final data = {
      'daily_calories': [2000.0, 1800.0, 2200.0], // 3 天
      'daily_protein': [50.0, 60.0], // 只有 2 天（长度不一致）
      'daily_fat': [40.0, 30.0, 35.0], // 3 天
      'daily_carbs': [200.0, 180.0, 220.0], // 3 天
      'daily_weights': [70.0],
      'protein_goal': 80.0,
      'fat_goal': 60.0,
      'carb_goal': 250.0,
      'recorded_days': 3,
      'total_days': 7,
      'coverage_rate': 0.43,
      'preference_foods': ['鸡胸肉'],
    };
    // 应取最小长度 2，不抛 RangeError
    expect(() => provider.buildWeeklySummaryForTest(data), returnsNormally);
  });

  // 防 debugPrint 污染测试输出
  setUpAll(() {
    debugPrint = (String? message, {int? wrapWidth}) {};
  });

  // L2 修复：createChatCompletion 加默认 timeout 参数
  // 原方法无 timeout，调用方遗忘时网络抖动会卡死 UI。
  // 修复：加 Duration timeout = Duration(seconds: 30) 默认参数 + .timeout(timeout) 调用。
  group('L2 createChatCompletion timeout', () {
    test('L2: createChatCompletion 应用 timeout 参数，超时抛 TimeoutException', () async {
      // 启动一个"黑洞" TCP 服务器：接受连接但不响应，模拟 GLM API 卡死
      final server = await ServerSocket.bind('127.0.0.1', 0);
      server.listen((socket) {
        // 接受连接但不写入任何响应，模拟 API 卡死
      });

      final provider = GlmFlashProvider(
        apiKey: 'fake',
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      // 用 500ms 短 timeout，应在 ~500ms 内抛 TimeoutException
      // 若 timeout 参数未生效，请求会一直挂起（黑洞服务器不响应）
      await expectLater(
        provider.createChatCompletion(
          systemPrompt: 'test',
          userPrompt: 'test',
          timeout: const Duration(milliseconds: 500),
        ),
        throwsA(isA<TimeoutException>()),
      );

      await server.close();
      provider.close();
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('L2: createChatCompletion 不传 timeout 时使用默认值（签名兼容）', () {
      // 验证 timeout 是可选参数（有默认值），现有调用方不传 timeout 仍能编译
      final provider = GlmFlashProvider(apiKey: 'fake', baseUrl: 'http://test');
      // 不调用（无网络），仅验证方法签名支持不传 timeout
      // ignore: unnecessary_lambdas
      expect(
        () => provider.createChatCompletion(
          systemPrompt: 's',
          userPrompt: 'u',
        ),
        isA<Future<String> Function()>(),
      );
      provider.close();
    });
  });
}
