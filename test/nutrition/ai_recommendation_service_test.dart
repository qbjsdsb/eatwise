// test/nutrition/ai_recommendation_service_test.dart
//
// AI 推荐服务单元测试
//
// 覆盖：
// - JSON 解析：标准格式 / markdown 包裹 / 含解释文字 / 缺字段 / 类型错误 / 空响应
// - 缓存：命中 / forceRefresh / 当日 key 隔离
// - 降级：AI 异常静默返回空 + 不缓存失败结果

import 'package:drift/native.dart';
import 'package:eatwise/ai/glm_flash_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:eatwise/data/repositories/recommendation_feedback_repository.dart';
import 'package:eatwise/nutrition/ai_recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late FoodItemRepository foodRepo;
  late MealLogRepository mealRepo;
  late ProfileRepository profileRepo;
  late RecommendationFeedbackRepository feedbackRepo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory(), seedOnCreate: false);
    foodRepo = FoodItemRepository(db);
    mealRepo = MealLogRepository(db);
    profileRepo = ProfileRepository(db);
    feedbackRepo = RecommendationFeedbackRepository(db);
    // 每个测试前清缓存（静态缓存跨测试会污染）
    AiRecommendationService.clearCache();
  });

  tearDown(() async => db.close());

  group('parseRecommendations JSON 解析', () {
    test('标准 JSON 格式正确解析', () {
      const raw = '{"recommendations":['
          '{"name":"鸡胸肉沙拉","reason":"高蛋白低脂适合减脂","estimatedCalories":350,"estimatedProtein":35},'
          '{"name":"番茄炒蛋","reason":"家常菜蛋白质补充","estimatedCalories":200,"estimatedProtein":12}'
          ']}';
      final list = AiRecommendationService.parseRecommendations(raw);
      expect(list.length, 2);
      expect(list[0].name, '鸡胸肉沙拉');
      expect(list[0].reason, '高蛋白低脂适合减脂');
      expect(list[0].estimatedCalories, 350);
      expect(list[0].estimatedProtein, 35);
      expect(list[1].name, '番茄炒蛋');
    });

    test('markdown 代码块包裹的 JSON 正确解析', () {
      const raw = '```json\n'
          '{"recommendations":[{"name":"白粥","reason":"易消化","estimatedCalories":150,"estimatedProtein":3}]}\n'
          '```';
      final list = AiRecommendationService.parseRecommendations(raw);
      expect(list.length, 1);
      expect(list[0].name, '白粥');
    });

    test('JSON 前后含解释文字正确解析', () {
      const raw = '好的，根据您的画像推荐如下：\n'
          '{"recommendations":[{"name":"糙米饭","reason":"高纤维","estimatedCalories":180,"estimatedProtein":4}]}\n'
          '希望对您有帮助。';
      final list = AiRecommendationService.parseRecommendations(raw);
      expect(list.length, 1);
      expect(list[0].name, '糙米饭');
    });

    test('空字符串 → 返回空列表', () {
      expect(AiRecommendationService.parseRecommendations(''), isEmpty);
    });

    test('无 JSON 对象 → 抛 FormatException', () {
      expect(() => AiRecommendationService.parseRecommendations('纯文字无JSON'),
          throwsA(isA<FormatException>()));
    });

    test('JSON 缺 recommendations 字段 → 抛 FormatException', () {
      const raw = '{"items":[]}';
      expect(() => AiRecommendationService.parseRecommendations(raw),
          throwsA(isA<FormatException>()));
    });

    test('recommendations 不是 List → 抛 FormatException', () {
      const raw = '{"recommendations":"not a list"}';
      expect(() => AiRecommendationService.parseRecommendations(raw),
          throwsA(isA<FormatException>()));
    });

    test('单项缺 name → 跳过该项', () {
      const raw = '{"recommendations":['
          '{"reason":"无name","estimatedCalories":100,"estimatedProtein":5},'
          '{"name":"有效项","reason":"有效理由","estimatedCalories":200,"estimatedProtein":10}'
          ']}';
      final list = AiRecommendationService.parseRecommendations(raw);
      expect(list.length, 1);
      expect(list[0].name, '有效项');
    });

    test('单项 name 空字符串 → 跳过该项', () {
      const raw = '{"recommendations":['
          '{"name":"","reason":"空name","estimatedCalories":100,"estimatedProtein":5}'
          ']}';
      expect(AiRecommendationService.parseRecommendations(raw), isEmpty);
    });

    test('单项缺 reason → 跳过该项', () {
      const raw = '{"recommendations":['
          '{"name":"无理由","estimatedCalories":100,"estimatedProtein":5}'
          ']}';
      expect(AiRecommendationService.parseRecommendations(raw), isEmpty);
    });

    test('estimatedCalories 是字符串 → 正确转换', () {
      const raw = '{"recommendations":['
          '{"name":"测试","reason":"理由","estimatedCalories":"350","estimatedProtein":"25"}'
          ']}';
      final list = AiRecommendationService.parseRecommendations(raw);
      expect(list.length, 1);
      expect(list[0].estimatedCalories, 350);
      expect(list[0].estimatedProtein, 25);
    });

    test('estimatedCalories 是非法字符串 → 转 0', () {
      const raw = '{"recommendations":['
          '{"name":"测试","reason":"理由","estimatedCalories":"abc","estimatedProtein":null}'
          ']}';
      final list = AiRecommendationService.parseRecommendations(raw);
      expect(list.length, 1);
      expect(list[0].estimatedCalories, 0);
      expect(list[0].estimatedProtein, 0);
    });

    test('JSON 格式错误（malformed）→ 抛 FormatException（service 层兜底）', () {
      const raw = '{"recommendations":[{"name":"test"';
      expect(() => AiRecommendationService.parseRecommendations(raw),
          throwsA(isA<FormatException>()));
    });

    test('name/reason 含前后空格 → trim', () {
      const raw = '{"recommendations":['
          '{"name":"  鸡胸肉  ","reason":"  高蛋白  ","estimatedCalories":100,"estimatedProtein":5}'
          ']}';
      final list = AiRecommendationService.parseRecommendations(raw);
      expect(list[0].name, '鸡胸肉');
      expect(list[0].reason, '高蛋白');
    });
  });

  group('recommend 缓存', () {
    // 用有效 JSON 才能缓存（解析失败不缓存）
    const validJson = '{"recommendations":['
        '{"name":"鸡胸肉沙拉","reason":"高蛋白","estimatedCalories":350,"estimatedProtein":35}'
        ']}';

    test('命中缓存 → fromCache=true', () async {
      final service = AiRecommendationService(
        _FakeGlmProvider(validJson),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      // 第一次调用：实际调 AI
      final r1 = await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
      );
      expect(r1.fromCache, false);
      expect(r1.recommendations, isNotEmpty);
      // 第二次调用：命中缓存
      final r2 = await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
      );
      expect(r2.fromCache, true);
    });

    test('forceRefresh=true → 跳过缓存强制刷新', () async {
      final service = AiRecommendationService(
        _FakeGlmProvider(validJson),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      // 第一次：填充缓存
      await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
      );
      // forceRefresh：不应命中缓存
      final r = await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
        forceRefresh: true,
      );
      expect(r.fromCache, false);
    });

    test('不同 mealType → 缓存隔离', () async {
      final service = AiRecommendationService(
        _FakeGlmProvider(validJson),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      // lunch 填充缓存
      await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
      );
      // dinner 不应命中 lunch 的缓存
      final r = await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'dinner'),
      );
      expect(r.fromCache, false);
    });

    test('不同 date → 缓存隔离', () async {
      final service = AiRecommendationService(
        _FakeGlmProvider(validJson),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
      );
      final r = await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-05', mealType: 'lunch'),
      );
      expect(r.fromCache, false);
    });

    test('解析失败不缓存（下次允许重试）', () async {
      // '{}' 无 recommendations → 解析抛 FormatException
      final service = AiRecommendationService(
        _FakeGlmProvider('{}'),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      // 第一次：失败返回空
      final r1 = await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
      );
      expect(r1.recommendations, isEmpty);
      expect(r1.fromCache, false);
      // 第二次：不命中缓存（fromCache=false，会再次尝试）
      final r2 = await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
      );
      expect(r2.fromCache, false);
    });
  });

  group('recommend 降级', () {
    test('AI 抛异常 → 静默返回空列表（v4 兜底）', () async {
      final service = AiRecommendationService(
        _ThrowingGlmProvider(),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      final r = await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
      );
      expect(r.recommendations, isEmpty);
      expect(r.fromCache, false);
    });

    test('AI 超时 → 静默返回空列表', () async {
      final service = AiRecommendationService(
        _SlowGlmProvider(), // 永不返回
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      // service.recommend 内部有 30s timeout，测试用 forceRefresh 跳过缓存
      // 为避免测试卡 30s，直接测 _fetchFromAi 的兜底逻辑：
      // service.recommend 会 catch 所有异常返回空，故直接调
      final r = await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
        forceRefresh: true,
      ).timeout(const Duration(seconds: 35));
      expect(r.recommendations, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('AI 失败不缓存结果（下次允许重试）', () async {
      final service = AiRecommendationService(
        _ThrowingGlmProvider(),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      // 第一次：失败返回空
      await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
      );
      // 第二次：不命中缓存（fromCache=false，且会再次尝试调 AI）
      final r = await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
      );
      expect(r.fromCache, false);
    });
  });

  group('L1 _friendlyError 5xx/403 错误文案', () {
    test('L1: 403 Forbidden → 权限不足文案', () async {
      final service = AiRecommendationService(
        _ThrowingGlmProviderWithMessage('403 Forbidden'),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      final r = await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
        forceRefresh: true,
      );
      expect(r.error, contains('权限不足'),
          reason: '403 应映射为"权限不足"文案');
    });

    test('L1: 500 Internal Server Error → 服务暂时不可用文案', () async {
      final service = AiRecommendationService(
        _ThrowingGlmProviderWithMessage('500 Internal Server Error'),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      final r = await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
        forceRefresh: true,
      );
      expect(r.error, contains('服务暂时不可用'),
          reason: '5xx 应映射为"服务暂时不可用"文案');
    });

    test('L1: 503 Service Unavailable → 服务暂时不可用文案', () async {
      final service = AiRecommendationService(
        _ThrowingGlmProviderWithMessage('Exception: 503 Service Unavailable'),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      final r = await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
        forceRefresh: true,
      );
      expect(r.error, contains('服务暂时不可用'),
          reason: '503 应映射为"服务暂时不可用"文案');
    });

    test('L1: 已有 401 文案保持不变（回归测试）', () async {
      final service = AiRecommendationService(
        _ThrowingGlmProviderWithMessage('401 Unauthorized'),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      final r = await service.recommend(
        const AiRecommendationRequest(todayDate: '2026-07-04', mealType: 'lunch'),
        forceRefresh: true,
      );
      expect(r.error, contains('API Key 无效'),
          reason: '401 应保持原有"API Key 无效"文案');
    });
  });

  group('M19 后处理去重', () {
    // 用今天日期预置 meal_log，与 service 内部 DateTime.now() 一致
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    test('AI 返回含 recentFoodNames 精确重名 → 被过滤', () async {
      // 预置：今天吃了鸡胸肉
      final chickenId = await foodRepo.insertManual(
        name: '鸡胸肉',
        caloriesPer100g: 167,
        proteinPer100g: 19,
        fatPer100g: 9,
        carbsPer100g: 0,
      );
      await mealRepo.insertMealLog(
        date: today,
        mealType: 'lunch',
        foodItemId: chickenId,
        actualServingG: 100,
        actualCalories: 167,
        actualProteinG: 19,
        actualFatG: 9,
        actualCarbsG: 0,
      );
      // mock AI 返回鸡胸肉 + 牛肉
      const json = '{"recommendations":['
          '{"name":"鸡胸肉","reason":"高蛋白","estimatedCalories":167,"estimatedProtein":19},'
          '{"name":"牛肉","reason":"补铁","estimatedCalories":250,"estimatedProtein":26}'
          ']}';
      final service = AiRecommendationService(
        _FakeGlmProvider(json),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      final r = await service.recommend(
        AiRecommendationRequest(todayDate: today, mealType: 'lunch'),
      );
      expect(r.recommendations.where((rec) => rec.name == '鸡胸肉'), isEmpty,
          reason: '鸡胸肉是今天吃过的，应被去重过滤');
      expect(r.recommendations.any((rec) => rec.name == '牛肉'), true,
          reason: '牛肉未吃过，应保留');
    });

    test('AI 返回含 recentFoodNames 归一化重名 → 被过滤', () async {
      // 预置：今天吃了"鸡胸肉"（无前缀）
      final chickenId = await foodRepo.insertManual(
        name: '鸡胸肉',
        caloriesPer100g: 167,
        proteinPer100g: 19,
        fatPer100g: 9,
        carbsPer100g: 0,
      );
      await mealRepo.insertMealLog(
        date: today,
        mealType: 'lunch',
        foodItemId: chickenId,
        actualServingG: 100,
        actualCalories: 167,
        actualProteinG: 19,
        actualFatG: 9,
        actualCarbsG: 0,
      );
      // mock AI 返回"炒鸡胸肉"（归一化后="鸡胸肉"，应被过滤）+ 牛肉
      const json = '{"recommendations":['
          '{"name":"炒鸡胸肉","reason":"高蛋白","estimatedCalories":200,"estimatedProtein":19},'
          '{"name":"牛肉","reason":"补铁","estimatedCalories":250,"estimatedProtein":26}'
          ']}';
      final service = AiRecommendationService(
        _FakeGlmProvider(json),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      final r = await service.recommend(
        AiRecommendationRequest(todayDate: today, mealType: 'lunch'),
      );
      expect(r.recommendations.where((rec) => rec.name == '炒鸡胸肉'), isEmpty,
          reason: '炒鸡胸肉归一化后=鸡胸肉（今天吃过），应被过滤');
      expect(r.recommendations.any((rec) => rec.name == '牛肉'), true,
          reason: '牛肉未吃过，应保留');
    });

    test('AI 返回内部重复（同一菜名两次）→ 只留一个', () async {
      // 不预置 meal_log（recentFoodNames 为空）
      const json = '{"recommendations":['
          '{"name":"牛肉","reason":"补铁","estimatedCalories":250,"estimatedProtein":26},'
          '{"name":"牛肉","reason":"补铁2","estimatedCalories":260,"estimatedProtein":27}'
          ']}';
      final service = AiRecommendationService(
        _FakeGlmProvider(json),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      final r = await service.recommend(
        AiRecommendationRequest(todayDate: today, mealType: 'lunch'),
      );
      expect(r.recommendations.length, 1,
          reason: 'AI 返回内部重复（牛肉×2）应只留一个');
      expect(r.recommendations.first.name, '牛肉');
    });

    test('AI 返回全部命中 recentFoodNames → 返回空列表', () async {
      // 预置：今天吃了鸡胸肉 + 牛肉
      final chickenId = await foodRepo.insertManual(
        name: '鸡胸肉',
        caloriesPer100g: 167,
        proteinPer100g: 19,
        fatPer100g: 9,
        carbsPer100g: 0,
      );
      final beefId = await foodRepo.insertManual(
        name: '牛肉',
        caloriesPer100g: 250,
        proteinPer100g: 26,
        fatPer100g: 15,
        carbsPer100g: 0,
      );
      await mealRepo.insertMealLog(
        date: today,
        mealType: 'lunch',
        foodItemId: chickenId,
        actualServingG: 100,
        actualCalories: 167,
        actualProteinG: 19,
        actualFatG: 9,
        actualCarbsG: 0,
      );
      await mealRepo.insertMealLog(
        date: today,
        mealType: 'lunch',
        foodItemId: beefId,
        actualServingG: 100,
        actualCalories: 250,
        actualProteinG: 26,
        actualFatG: 15,
        actualCarbsG: 0,
      );
      // mock AI 返回鸡胸肉 + 牛肉（全部命中）
      const json = '{"recommendations":['
          '{"name":"鸡胸肉","reason":"高蛋白","estimatedCalories":167,"estimatedProtein":19},'
          '{"name":"牛肉","reason":"补铁","estimatedCalories":250,"estimatedProtein":26}'
          ']}';
      final service = AiRecommendationService(
        _FakeGlmProvider(json),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      final r = await service.recommend(
        AiRecommendationRequest(todayDate: today, mealType: 'lunch'),
      );
      // 全部命中 → 返回空（注意：空结果不缓存，error 非 null）
      expect(r.recommendations, isEmpty,
          reason: 'AI 返回全部命中近 7 天已吃，应返回空列表');
    });

    test('AI 返回 5 道菜，2 道命中 → 返回 3 道', () async {
      // 预置：今天吃了鸡胸肉 + 牛肉
      final chickenId = await foodRepo.insertManual(
        name: '鸡胸肉',
        caloriesPer100g: 167,
        proteinPer100g: 19,
        fatPer100g: 9,
        carbsPer100g: 0,
      );
      final beefId = await foodRepo.insertManual(
        name: '牛肉',
        caloriesPer100g: 250,
        proteinPer100g: 26,
        fatPer100g: 15,
        carbsPer100g: 0,
      );
      await mealRepo.insertMealLog(
        date: today,
        mealType: 'lunch',
        foodItemId: chickenId,
        actualServingG: 100,
        actualCalories: 167,
        actualProteinG: 19,
        actualFatG: 9,
        actualCarbsG: 0,
      );
      await mealRepo.insertMealLog(
        date: today,
        mealType: 'lunch',
        foodItemId: beefId,
        actualServingG: 100,
        actualCalories: 250,
        actualProteinG: 26,
        actualFatG: 15,
        actualCarbsG: 0,
      );
      // mock AI 返回 5 道，含鸡胸肉+牛肉+3其他
      const json = '{"recommendations":['
          '{"name":"鸡胸肉","reason":"1","estimatedCalories":167,"estimatedProtein":19},'
          '{"name":"牛肉","reason":"2","estimatedCalories":250,"estimatedProtein":26},'
          '{"name":"鲈鱼","reason":"3","estimatedCalories":200,"estimatedProtein":20},'
          '{"name":"豆腐","reason":"4","estimatedCalories":150,"estimatedProtein":12},'
          '{"name":"菠菜","reason":"5","estimatedCalories":40,"estimatedProtein":3}'
          ']}';
      final service = AiRecommendationService(
        _FakeGlmProvider(json),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      final r = await service.recommend(
        AiRecommendationRequest(todayDate: today, mealType: 'lunch'),
      );
      expect(r.recommendations.length, 3,
          reason: '5 道中 2 道命中近 7 天已吃，应返回 3 道');
      expect(r.recommendations.map((rec) => rec.name).toList(),
          ['鲈鱼', '豆腐', '菠菜'],
          reason: '应保留未吃过的 3 道，顺序与 AI 返回一致');
    });

    test('recentFoodNames 为空 → 不过滤', () async {
      // 不预置 meal_log（recentFoodNames 为空）
      const json = '{"recommendations":['
          '{"name":"鸡胸肉","reason":"1","estimatedCalories":167,"estimatedProtein":19},'
          '{"name":"牛肉","reason":"2","estimatedCalories":250,"estimatedProtein":26},'
          '{"name":"鲈鱼","reason":"3","estimatedCalories":200,"estimatedProtein":20}'
          ']}';
      final service = AiRecommendationService(
        _FakeGlmProvider(json),
        profileRepo,
        mealRepo,
        foodRepo,
        feedbackRepo,
      );
      final r = await service.recommend(
        AiRecommendationRequest(todayDate: today, mealType: 'lunch'),
      );
      expect(r.recommendations.length, 3,
          reason: 'recentFoodNames 为空时不应过滤，应返回全部 3 道');
    });
  });
}

/// 假 GlmFlashProvider：返回固定响应（不实际调 API）
class _FakeGlmProvider extends GlmFlashProvider {
  final String _response;
  _FakeGlmProvider(this._response) : super(apiKey: 'fake', baseUrl: 'http://fake');

  @override
  Future<String> createChatCompletion({
    required String systemPrompt,
    required String userPrompt,
    String model = 'glm-4-flash',
    int maxCompletionTokens = 1000,
    double temperature = 0.7,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return _response;
  }
}

/// 抛异常的 GlmFlashProvider（模拟 AI 调用失败）
class _ThrowingGlmProvider extends GlmFlashProvider {
  _ThrowingGlmProvider() : super(apiKey: 'fake', baseUrl: 'http://fake');

  @override
  Future<String> createChatCompletion({
    required String systemPrompt,
    required String userPrompt,
    String model = 'glm-4-flash',
    int maxCompletionTokens = 1000,
    double temperature = 0.7,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    throw Exception('AI 服务不可用');
  }
}

/// 抛带特定 message 异常的 GlmFlashProvider（L1 测试用，模拟 5xx/403 等）
class _ThrowingGlmProviderWithMessage extends GlmFlashProvider {
  final String _message;
  _ThrowingGlmProviderWithMessage(this._message)
      : super(apiKey: 'fake', baseUrl: 'http://fake');

  @override
  Future<String> createChatCompletion({
    required String systemPrompt,
    required String userPrompt,
    String model = 'glm-4-flash',
    int maxCompletionTokens = 1000,
    double temperature = 0.7,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    throw Exception(_message);
  }
}

/// 慢 GlmFlashProvider（模拟超时，永不返回）
class _SlowGlmProvider extends GlmFlashProvider {
  _SlowGlmProvider() : super(apiKey: 'fake', baseUrl: 'http://fake');

  @override
  Future<String> createChatCompletion({
    required String systemPrompt,
    required String userPrompt,
    String model = 'glm-4-flash',
    int maxCompletionTokens = 1000,
    double temperature = 0.7,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await Future.delayed(const Duration(minutes: 1));
    return '';
  }
}
