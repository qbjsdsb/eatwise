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
}
