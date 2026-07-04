import 'package:flutter/foundation.dart';
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
  /// weeklyData 格式（v1.11 增强）：
  /// {
  ///   'daily_calories': [1800, 2100, 1500, 2200, 1900, 2500, 1700],
  ///   'daily_weights': [70.2, 70.1, 70.3, 70.0, 69.8, 69.9, 69.7],
  ///   'target_calories': 2000,
  ///   'goal': 'cut',
  ///   'daily_protein': [80, 95, 70, 110, 85, 120, 75],   // 每日蛋白 g
  ///   'daily_fat': [60, 70, 50, 75, 65, 80, 55],          // 每日脂肪 g
  ///   'daily_carbs': [200, 230, 180, 250, 210, 280, 190], // 每日碳水 g
  ///   'protein_goal': 98.0,  'fat_goal': 63.0,  'carb_goal': 250.0,
  ///   'recorded_days': 7,  'total_days': 7,  'coverage_rate': 1.0,
  ///   'preference_foods': ['米饭', '鸡蛋', '鸡胸肉', '西兰花', '牛奶'],
  /// }
  Future<String> generateWeeklySummary(Map<String, dynamic> weeklyData) async {
    final prompt = _buildPrompt(weeklyData);
    final res = await _client.chat.completions
        .create(
          ChatCompletionCreateRequest(
            model: 'glm-4-flash',
            messages: [
              ChatMessage.system(
                '你是营养师助手。根据用户一周的饮食热量、体重、宏量营养素、饮食偏好数据，'
                '给出不超过300字的具体中文建议，包含：1）热量摄入评估 2）宏量营养素达成率分析 '
                '3）体重趋势分析 4）下周可执行建议（结合饮食偏好）。直接给建议，不要寒暄。',
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

  /// 构造周报 user prompt（v1.11 增强：宏量达成率 + 偏好 + 覆盖率）
  ///
  /// H3 修复：核心字段加 null 兜底，避免调用方传不完整 data 时崩溃。
  /// 与 _appendMacroAndPreference 的兜底风格一致。
  String _buildPrompt(Map<String, dynamic> data) {
    final calories = data['daily_calories'] as List? ?? const [];
    final weights = data['daily_weights'] as List? ?? const [];
    final target = data['target_calories'] ?? 2000;
    final goal = data['goal'] ?? 'maintain';
    final goalLabel = goal == 'cut' ? '减脂' : goal == 'bulk' ? '增肌' : '维持';

    final buf = StringBuffer('本周目标：$goalLabel，每日热量目标 $target kcal。');
    buf.write('每日摄入热量：$calories kcal。');
    buf.write('每日体重：$weights kg。');
    _appendMacroAndPreference(buf, data, '本周');
    buf.write('请给出本周总结和下周建议，结合宏量达成率分析饮食结构是否合理。');
    return buf.toString();
  }

  /// @visibleForTesting：暴露 _buildPrompt 供测试验证 null 兜底（H3）
  @visibleForTesting
  String buildWeeklySummaryForTest(Map<String, dynamic> data) =>
      _buildPrompt(data);

  /// 根据一月饮食 + 体重数据生成 ≤400 字中文建议
  ///
  /// monthlyData 格式（v1.11 增强，字段与 weeklyData 一致，仅日数 28~31）：
  /// 见 [generateWeeklySummary] 的 weeklyData 注释。
  Future<String> generateMonthlySummary(Map<String, dynamic> monthlyData) async {
    final prompt = _buildMonthlyPrompt(monthlyData);
    final res = await _client.chat.completions
        .create(
          ChatCompletionCreateRequest(
            model: 'glm-4-flash',
            messages: [
              ChatMessage.system(
                '你是营养师助手。根据用户一个月的饮食热量、体重、宏量营养素、饮食偏好数据，'
                '给出不超过400字的具体中文建议，包含：1）月度热量摄入评估 + 周环比趋势 '
                '2）宏量营养素达成率分析 3）体重变化分析 4）下月可执行建议（结合饮食偏好）。'
                '直接给建议，不要寒暄。',
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

  /// 构造月报 user prompt（v1.11 增强：宏量达成率 + 偏好 + 覆盖率 + 周环比）
  ///
  /// H3 修复：核心字段加 null 兜底（与 _buildPrompt 一致）
  String _buildMonthlyPrompt(Map<String, dynamic> data) {
    final calories = data['daily_calories'] as List? ?? const [];
    final weights = data['daily_weights'] as List? ?? const [];
    final target = data['target_calories'] ?? 2000;
    final goal = data['goal'] ?? 'maintain';
    final goalLabel = goal == 'cut' ? '减脂' : goal == 'bulk' ? '增肌' : '维持';

    final buf = StringBuffer('本月目标：$goalLabel，每日热量目标 $target kcal。');
    buf.write('每日摄入热量：$calories kcal。');
    buf.write('每日体重：$weights kg。');
    _appendMacroAndPreference(buf, data, '本月');
    buf.write('请给出本月总结和下月建议，包含周环比分析，结合宏量达成率分析饮食结构。');
    return buf.toString();
  }

  /// @visibleForTesting：暴露 _buildMonthlyPrompt 供测试验证 null 兜底（H3）
  @visibleForTesting
  String buildMonthlySummaryForTest(Map<String, dynamic> data) =>
      _buildMonthlyPrompt(data);

  /// 追加宏量达成率 + 覆盖率 + 偏好画像到 prompt（周/月共用）
  ///
  /// v1.11 新增：让 AI 能看到三宏实际摄入 vs 目标、数据完整度、常吃食物，
  /// 从而给出更智能的建议（如"蛋白不足，常吃米饭可搭配鸡蛋"）。
  ///
  /// 宏量均值只统计有记录的天数（calories > 0），避免 0 填充日拉低均值。
  void _appendMacroAndPreference(
      StringBuffer buf, Map<String, dynamic> data, String periodLabel) {
    // 宏量达成率（蛋白/脂肪/碳水 实际均值 vs 目标）
    final protein = data['daily_protein'] as List?;
    final fat = data['daily_fat'] as List?;
    final carbs = data['daily_carbs'] as List?;
    final calories = data['daily_calories'] as List?;
    final proteinGoal = data['protein_goal'];
    final fatGoal = data['fat_goal'];
    final carbGoal = data['carb_goal'];
    if (protein != null && fat != null && carbs != null && calories != null) {
      // M1 修复：取四数组最小长度作为循环上界，避免长度不一致时 RangeError
      // 当前调用方长度一致，但防御性加固防未来扩展崩溃
      final minLen = [protein, fat, carbs, calories]
          .map((l) => l.length)
          .reduce((a, b) => a < b ? a : b);
      // 只统计有记录的天数（热量>0），避免 0 填充日拉低均值
      double sumP = 0, sumF = 0, sumC = 0;
      var n = 0;
      for (var i = 0; i < minLen; i++) {
        final cal = (calories[i] as num).toDouble();
        if (cal <= 0) continue;
        n++;
        sumP += (protein[i] as num).toDouble();
        sumF += (fat[i] as num).toDouble();
        sumC += (carbs[i] as num).toDouble();
      }
      if (n > 0) {
        final avgP = sumP / n;
        final avgF = sumF / n;
        final avgC = sumC / n;
        buf.write('$periodLabel 记录日均值：蛋白 ${avgP.toStringAsFixed(1)}g'
            '（目标 ${proteinGoal?.toStringAsFixed(0)}g）、'
            '脂肪 ${avgF.toStringAsFixed(1)}g'
            '（目标 ${fatGoal?.toStringAsFixed(0)}g）、'
            '碳水 ${avgC.toStringAsFixed(1)}g'
            '（目标 ${carbGoal?.toStringAsFixed(0)}g）。');
      }
    }

    // 覆盖率（让 AI 知道数据完整度，覆盖率低时建议用户多记录）
    final recordedDays = data['recorded_days'];
    final totalDays = data['total_days'];
    final coverageRate = data['coverage_rate'];
    if (recordedDays != null && totalDays != null && coverageRate != null) {
      buf.write('记录覆盖 $recordedDays/$totalDays 天'
          '（${(coverageRate * 100).round()}%）。');
    }

    // 饮食偏好画像（高频食物 top 5）
    final prefs = data['preference_foods'] as List?;
    if (prefs != null && prefs.isNotEmpty) {
      buf.write('常吃食物：${prefs.join('、')}。');
    }
  }

  /// 通用聊天补全（v5 AI 推荐用）
  ///
  /// 调用方传入 [systemPrompt] 和 [userPrompt]，返回模型文本响应。
  /// 不在此处做 timeout（调用方按场景控制，AI 推荐用 30s）。
  Future<String> createChatCompletion({
    required String systemPrompt,
    required String userPrompt,
    String model = 'glm-4-flash',
    int maxCompletionTokens = 1000,
    double temperature = 0.7,
  }) async {
    final res = await _client.chat.completions.create(
      ChatCompletionCreateRequest(
        model: model,
        messages: [
          ChatMessage.system(systemPrompt),
          ChatMessage.user(UserMessageContent.text(userPrompt)),
        ],
        maxCompletionTokens: maxCompletionTokens,
        temperature: temperature,
      ),
    );
    return res.text ?? '';
  }

  /// 关闭底层 HTTP 客户端，释放连接资源
  /// 调用方用完 provider 后应调 close() 避免 OpenAIClient 连接泄漏
  void close() {
    _client.close();
  }
}
