import 'package:openai_dart/openai_dart.dart';

/// GLM-4-Flash 汇总建议生成器（智谱免费文本模型，OpenAI 兼容）
class GlmFlashProvider {
  final OpenAIClient _client;

  /// apiKey: 智谱 API key
  /// baseUrl: 默认 https://open.bigmodel.cn/api/paas/v4
  GlmFlashProvider({
    required String apiKey,
    String baseUrl = 'https://open.bigmodel.cn/api/paas/v4',
  }) : _client = OpenAIClient(
          config: OpenAIConfig(
            authProvider: ApiKeyProvider(apiKey),
            baseUrl: baseUrl,
          ),
        );

  /// 根据一周饮食 + 体重数据生成 ≤300 字中文建议
  ///
  /// weeklyData 格式：
  /// {
  ///   'daily_calories': [1800, 2100, 1500, 2200, 1900, 2500, 1700],
  ///   'daily_weights': [70.2, 70.1, 70.3, 70.0, 69.8, 69.9, 69.7],
  ///   'target_calories': 2000,
  ///   'goal': 'cut',
  /// }
  Future<String> generateWeeklySummary(Map<String, dynamic> weeklyData) async {
    final prompt = _buildPrompt(weeklyData);
    final res = await _client.chat.completions
        .create(
          ChatCompletionCreateRequest(
            model: 'glm-4-flash',
            messages: [
              ChatMessage.system(
                '你是营养师助手。根据用户一周的饮食热量和体重数据，给出不超过300字的具体中文建议，'
                '包含：1）热量摄入评估 2）体重趋势分析 3）下周可执行建议。直接给建议，不要寒暄。',
              ),
              // openai_dart 7.0: UserMessageContent.text(...) 工厂构造器
              ChatMessage.user(UserMessageContent.text(prompt)),
            ],
            maxCompletionTokens: 500,
            temperature: 0.7,
          ),
        )
        .timeout(const Duration(seconds: 30));
    // openai_dart 7.0: res.text 是 String? 便捷访问器
    return res.text ?? '（无内容返回）';
  }

  String _buildPrompt(Map<String, dynamic> data) {
    final calories = data['daily_calories'] as List;
    final weights = data['daily_weights'] as List;
    final target = data['target_calories'];
    final goal = data['goal'];
    final goalLabel = goal == 'cut' ? '减脂' : goal == 'bulk' ? '增肌' : '维持';
    return '本周目标：$goalLabel，每日热量目标 $target kcal。'
        '每日摄入热量：$calories kcal。'
        '每日体重：$weights kg。'
        '请给出本周总结和下周建议。';
  }

  /// 根据一月饮食 + 体重数据生成 ≤400 字中文建议
  ///
  /// monthlyData 格式：
  /// {
  ///   'daily_calories': [1800, 2100, ...], // 28~31 元素
  ///   'daily_weights': [70.2, 70.1, ...],
  ///   'target_calories': 2000,
  ///   'goal': 'cut',
  /// }
  Future<String> generateMonthlySummary(Map<String, dynamic> monthlyData) async {
    final prompt = _buildMonthlyPrompt(monthlyData);
    final res = await _client.chat.completions
        .create(
          ChatCompletionCreateRequest(
            model: 'glm-4-flash',
            messages: [
              ChatMessage.system(
                '你是营养师助手。根据用户一个月的饮食热量和体重数据，给出不超过400字的具体中文建议，'
                '包含：1）月度热量摄入评估 + 周环比趋势 2）体重变化分析 3）下月可执行建议。直接给建议，不要寒暄。',
              ),
              ChatMessage.user(UserMessageContent.text(prompt)),
            ],
            maxCompletionTokens: 600,
            temperature: 0.7,
          ),
        )
        .timeout(const Duration(seconds: 30));
    return res.text ?? '（无内容返回）';
  }

  String _buildMonthlyPrompt(Map<String, dynamic> data) {
    final calories = data['daily_calories'] as List;
    final weights = data['daily_weights'] as List;
    final target = data['target_calories'];
    final goal = data['goal'];
    final goalLabel = goal == 'cut' ? '减脂' : goal == 'bulk' ? '增肌' : '维持';
    return '本月目标：$goalLabel，每日热量目标 $target kcal。'
        '每日摄入热量：$calories kcal。'
        '每日体重：$weights kg。'
        '请给出本月总结和下月建议，包含周环比分析。';
  }
}
