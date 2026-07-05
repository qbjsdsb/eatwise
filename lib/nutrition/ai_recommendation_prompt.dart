// lib/nutrition/ai_recommendation_prompt.dart
//
// AI 个性化推荐 prompt 构建器（v5 渐进增强）
//
// 把用户画像 + 当日剩余额度 + 历史饮食 + 满意度反馈聚合成结构化 prompt，
// 喂给 GLM-4-Flash 让其生成 5 道个性化推荐（JSON 输出）。
//
// 设计原则：
// - 纯函数（输入数据 → 输出字符串），无副作用，易测
// - 不调 IO，所有数据由调用方传入
// - prompt 用中文（与项目风格一致 + GLM 中文表现更好）
// - 严格约束 JSON 输出格式，避免解析失败

import 'package:eatwise/data/database/database.dart';

import 'recommendation_service.dart';

/// AI 推荐请求所需的全部上下文（调用方聚合后传入）
class AiRecommendationContext {
  final Profile profile;
  final DailyRemaining remaining;
  final String mealType; // breakfast/lunch/dinner/snack
  final List<MealLog> recentMeals; // 近 14 天 meal_log
  final Map<int, FoodItem> foodMap; // foodItemId → FoodItem
  final Set<String> recentFoodNames; // 近 3 天吃过的食物名（避免重复推荐）
  final List<FeedbackRecord> feedbacks; // 历史满意度反馈

  const AiRecommendationContext({
    required this.profile,
    required this.remaining,
    required this.mealType,
    required this.recentMeals,
    required this.foodMap,
    required this.recentFoodNames,
    required this.feedbacks,
  });
}

/// 满意度反馈记录（用于 prompt 注入，让 AI 学习用户偏好）
class FeedbackRecord {
  final String foodName;
  final int rating; // 1=不喜欢 / 2=一般 / 3=喜欢
  final DateTime createdAt;

  const FeedbackRecord({
    required this.foodName,
    required this.rating,
    required this.createdAt,
  });
}

/// AI 推荐结果项（JSON 解析后的结构）
class AiRecommendation {
  final String name;
  final String reason;
  final double estimatedCalories;
  final double estimatedProtein;

  const AiRecommendation({
    required this.name,
    required this.reason,
    required this.estimatedCalories,
    required this.estimatedProtein,
  });

  @override
  String toString() =>
      'AiRecommendation($name, $reason, ${estimatedCalories}kcal, ${estimatedProtein}g)';
}

/// prompt 构建器（纯函数）
class AiRecommendationPrompt {
  AiRecommendationPrompt._(); // 禁止实例化

  /// System prompt：营养师人设 + 输出格式约束
  static const systemPrompt = '你是一位资深营养师，擅长根据用户画像和饮食习惯做个性化推荐。'
      '请根据用户信息推荐 5 道适合当前餐次的菜肴，严格遵循以下要求：\n'
      '1. 推荐必须符合用户的健康状况（糖尿病/高血压/肾病等）和饮食偏好（素食/乳糖不耐等）\n'
      '2. 优先填补当日营养缺口（如蛋白质不足则推高蛋白食物）\n'
      '3. 禁止与近 7 天吃过的食物重复（硬约束，不可违反）\n'
      '4. 参考用户历史饮食偏好（常吃/少碰的口味和食材）\n'
      '5. 参考用户对历史推荐的满意度反馈（喜欢/一般/不喜欢）\n'
      '6. 每道菜给出 ≤30 字的个性化推荐理由（说明为什么适合该用户）\n'
      '7. 估算每道菜一份的热量和蛋白质（基于常见中式份量）\n'
      '8. 5 道菜至少覆盖 3 个食材类别（肉类/水产/蔬菜/豆制品/蛋类/主食/水果），'
      '避免集中推荐同一类别（如不要 5 道都是鸡肉或都是沙拉）\n'
      '9. 烹饪方式尽量多样化（炒/蒸/煮/凉拌/烤搭配，不要 5 道都是同一做法）\n\n'
      '严格按以下 JSON 格式输出（不要 markdown 代码块，不要解释文字）：\n'
      '{"recommendations":[{"name":"菜名","reason":"推荐理由","estimatedCalories":350,"estimatedProtein":25}]}';

  /// User prompt：聚合用户画像 + 剩余额度 + 历史 + 反馈
  static String buildUserPrompt(AiRecommendationContext ctx) {
    final buf = StringBuffer();
    buf.writeln('## 用户画像');
    buf.writeln(_profileSection(ctx.profile));
    buf.writeln();
    buf.writeln('## 当日营养额度');
    buf.writeln(_remainingSection(ctx.remaining, ctx.mealType));
    buf.writeln();
    buf.writeln('## 近 14 天饮食习惯');
    buf.writeln(_historySection(ctx.recentMeals, ctx.foodMap));
    buf.writeln();
    buf.writeln('## 近 7 天已吃食物（禁止重复推荐）');
    buf.writeln(ctx.recentFoodNames.isEmpty
        ? '（无记录）'
        : ctx.recentFoodNames.take(20).join('、'));
    buf.writeln();
    buf.writeln('## 历史推荐反馈');
    buf.writeln(_feedbackSection(ctx.feedbacks));
    buf.writeln();
    buf.writeln('## 任务');
    final mealLabel = _mealTypeLabel(ctx.mealType);
    buf.writeln('请为该用户推荐 5 道适合$mealLabel的菜肴，输出 JSON。');
    return buf.toString();
  }

  static String _profileSection(Profile p) {
    final genderLabel = p.gender == 'male' ? '男' : '女';
    final goalLabel = _goalLabel(p.goal);
    final activityLabel = _activityLabel(p.activityLevel);
    final parts = <String>[
      '性别：$genderLabel',
      '年龄：${p.age} 岁',
      '身高：${p.heightCm.toStringAsFixed(0)} cm',
      '体重：${p.weightKg.toStringAsFixed(0)} kg',
    ];
    if (p.bodyFatPct != null) {
      parts.add('体脂率：${p.bodyFatPct!.toStringAsFixed(1)}%');
    }
    parts.add('活动量：$activityLabel');
    parts.add('目标：$goalLabel');
    final sc = p.specialCondition ?? 'none';
    if (sc != 'none') parts.add('特殊状况：${_specialConditionLabel(sc)}');
    final hc = p.healthCondition ?? 'none';
    if (hc != 'none') parts.add('健康状况：${_healthConditionLabel(hc)}');
    final dp = p.dietPreference ?? 'none';
    if (dp != 'none') parts.add('饮食偏好：${_dietPreferenceLabel(dp)}');
    parts.add('每日热量目标：${p.dailyCalorieTarget} kcal');
    return parts.join('；');
  }

  static String _remainingSection(DailyRemaining r, String mealType) {
    final mealLabel = _mealTypeLabel(mealType);
    return '当前餐次：$mealLabel；'
        '今日已摄入 ${r.consumedCalories.toStringAsFixed(0)}/${r.targetCalories} kcal；'
        '剩余 ${r.remainingCalories.toStringAsFixed(0)} kcal；'
        '蛋白质 ${r.consumedProtein.toStringAsFixed(0)}/${r.proteinGoal.toStringAsFixed(0)} g'
        '（剩余 ${r.remainingProtein.toStringAsFixed(0)} g）；'
        '脂肪剩余 ${r.remainingFat.toStringAsFixed(0)} g；'
        '碳水剩余 ${r.remainingCarbs.toStringAsFixed(0)} g';
  }

  /// 历史饮食：聚合近 14 天 meal_log，按食物频次降序取 top 20
  /// M19：加优先级声明（去重约束优先于频次偏好）+ 反向偏好（少吃的食材类别）
  static String _historySection(List<MealLog> meals, Map<int, FoodItem> foodMap) {
    if (meals.isEmpty) return '（无历史记录）';
    // 按食物名聚合频次
    final freq = <String, int>{};
    for (final m in meals) {
      final food = foodMap[m.foodItemId];
      if (food == null) continue;
      freq[food.name] = (freq[food.name] ?? 0) + 1;
    }
    if (freq.isEmpty) return '（无历史记录）';
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(20).map((e) => '${e.key}(${e.value}次)').join('、');
    // M19 多样性反向偏好：统计常吃食物的食材类别分布，提示 AI 推荐少吃的类别
    final rareCategories = _inferRareCategories(freq.keys);
    return '常吃食物（按频次）：$top\n'
        '（注：高频仅反映偏好，去重约束优先于频次偏好，不可推荐近 7 天已吃过的食物）\n'
        '用户近期少吃的食材类别：$rareCategories（推荐时优先考虑这些类别以增加多样性）';
  }

  /// 根据常吃食物名推断用户少吃的食材类别（M19 多样性反向偏好用）
  ///
  /// 食材类别词典（简易关键词匹配）：
  /// - 肉类：鸡/猪/牛/羊/鸭
  /// - 水产：鱼/虾/蟹/贝
  /// - 蔬菜：菜/瓜/茄/菇/菠菜/白菜/西兰花
  /// - 豆制品：豆腐/豆干/豆浆/豆皮
  /// - 蛋类：蛋
  /// - 主食：饭/面/粥/粉/包/饼
  /// - 水果：苹果/香蕉/橙/葡萄/西瓜
  ///
  /// 返回：常吃食物中未出现的类别（最多 3 个），用顿号分隔
  /// 若常吃食物覆盖全部类别，返回"（无明显缺口）"
  ///
  /// 关键词匹配是模糊的（如"鸡蛋"含"鸡"会被归到肉类），但对"用户少吃哪类"的
  /// 粗粒度提示足够。不依赖 FoodProfileTagger，避免新增依赖。
  static String _inferRareCategories(Iterable<String> foodNames) {
    const categoryKeywords = <String, List<String>>{
      '肉类': ['鸡', '猪', '牛', '羊', '鸭'],
      '水产': ['鱼', '虾', '蟹', '贝'],
      '蔬菜': ['菜', '瓜', '茄', '菇', '菠菜', '白菜', '西兰花'],
      '豆制品': ['豆腐', '豆干', '豆浆', '豆皮'],
      '蛋类': ['蛋'],
      '主食': ['饭', '面', '粥', '粉', '包', '饼'],
      '水果': ['苹果', '香蕉', '橙', '葡萄', '西瓜'],
    };
    final present = <String>{};
    for (final name in foodNames) {
      for (final entry in categoryKeywords.entries) {
        for (final kw in entry.value) {
          if (name.contains(kw)) {
            present.add(entry.key);
            break;
          }
        }
      }
    }
    final rare = categoryKeywords.keys
        .where((c) => !present.contains(c))
        .take(3)
        .toList();
    return rare.isEmpty ? '（无明显缺口）' : rare.join('、');
  }

  static String _feedbackSection(List<FeedbackRecord> feedbacks) {
    if (feedbacks.isEmpty) return '（暂无反馈）';
    // 仅取近 30 条，按时间倒序
    final sorted = List<FeedbackRecord>.from(feedbacks)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final lines = sorted.take(30).map((f) {
      final label = f.rating == 3 ? '喜欢' : f.rating == 2 ? '一般' : '不喜欢';
      return '${f.foodName}：$label';
    }).join('、');
    return lines;
  }

  static String _mealTypeLabel(String mt) {
    switch (mt) {
      case 'breakfast':
        return '早餐';
      case 'lunch':
        return '午餐';
      case 'dinner':
        return '晚餐';
      case 'snack':
        return '加餐';
      default:
        return '一餐';
    }
  }

  static String _goalLabel(String g) {
    switch (g) {
      case 'cut':
        return '减脂';
      case 'bulk':
        return '增肌';
      case 'maintain':
        return '维持';
      default:
        return '维持';
    }
  }

  static String _activityLabel(double level) {
    if (level <= 1.2) return '久坐';
    if (level <= 1.375) return '轻度活动';
    if (level <= 1.55) return '中度活动';
    if (level <= 1.725) return '高度活动';
    return '极度活动';
  }

  static String _specialConditionLabel(String sc) {
    switch (sc) {
      case 'pregnancy':
        return '孕期';
      case 'lactation':
        return '哺乳期';
      case 'elderly':
        return '老年';
      case 'teenager':
        return '青少年';
      default:
        return '无';
    }
  }

  static String _healthConditionLabel(String hc) {
    switch (hc) {
      case 'diabetes':
        return '糖尿病';
      case 'hypertension':
        return '高血压';
      case 'kidney_issues':
        return '肾病';
      default:
        return '无';
    }
  }

  static String _dietPreferenceLabel(String dp) {
    switch (dp) {
      case 'vegetarian':
        return '蛋奶素';
      case 'vegan':
        return '纯素';
      case 'lactose_intolerant':
        return '乳糖不耐';
      case 'gluten_free':
        return '无麸质';
      default:
        return '无';
    }
  }
}
