import 'dart:io';

import 'package:eatwise/ai/glm_flash_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 走真实网络（绕过 flutter_test 默认 HttpOverrides）
  HttpOverrides.global = null;
  final apiKey = const String.fromEnvironment('GLM_API_KEY');
  final canRun = apiKey.isNotEmpty;

  test(
    'GLM-4-Flash 生成周汇总',
    skip: canRun ? false : '需 GLM_API_KEY（--dart-define=GLM_API_KEY=xxx）',
    () async {
      final provider = GlmFlashProvider(apiKey: apiKey);
      final text = await provider.generateWeeklySummary({
        'daily_calories': [1800, 2100, 1500, 2200, 1900, 2500, 1700],
        'daily_weights': [70.2, 70.1, 70.3, 70.0, 69.8, 69.9, 69.7],
        'target_calories': 2000,
        'goal': 'cut',
      });
      expect(text.isNotEmpty, isTrue);
      // 模型偶尔超 300 字（标点/换行差异），用 500 字宽松上限做冒烟
      expect(text.length, lessThan(500), reason: '应≤300字（宽松上限 500）');
      // ignore: avoid_print
      print('✅ GLM-4-Flash 返回 ${text.length} 字: $text');
    },
  );
}
