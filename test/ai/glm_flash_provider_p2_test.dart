import 'package:eatwise/ai/glm_flash_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 问题2 增强 prompt 测试：验证新字段（餐次分布/streak/超额/达成天数/体重变化/特殊人群/周环比）
/// 能正确写入 AI prompt，且 'none'/null 兜底不写入噪音。
void main() {
  final provider = GlmFlashProvider(apiKey: 'fake', baseUrl: 'http://test');

  group('问题2 _appendEnhancedInsights', () {
    test('餐次分布写入 prompt（含占比）', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2000.0],
        'target_calories': 2000,
        'meal_type_calories': {
          'breakfast': 400.0,
          'lunch': 800.0,
          'dinner': 600.0,
          'snack': 200.0,
        },
      });
      // 总热量 2000，早 20%/午 40%/晚 30%/加餐 10%
      expect(prompt, contains('餐次分布'));
      expect(prompt, contains('早餐 400kcal(20%)'));
      expect(prompt, contains('午餐 800kcal(40%)'));
      expect(prompt, contains('晚餐 600kcal(30%)'));
      expect(prompt, contains('加餐 200kcal(10%)'));
    });

    test('streak > 0 写入 prompt', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2000.0],
        'streak': 5,
      });
      expect(prompt, contains('已连续记录 5 天'));
    });

    test('streak = 0 不写入 prompt（避免噪音）', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2000.0],
        'streak': 0,
      });
      expect(prompt, isNot(contains('已连续记录')));
    });

    test('平均超额 > 0 写入"超"目标', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2200.0],
        'avg_excess': 200.0,
      });
      expect(prompt, contains('平均每天超目标 200 kcal'));
    });

    test('平均超额 < 0 写入"缺"目标', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [1800.0],
        'avg_excess': -200.0,
      });
      expect(prompt, contains('平均每天缺目标 200 kcal'));
    });

    test('平均超额 abs < 1 不写入 prompt（视为达标）', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2000.0],
        'avg_excess': 0.5,
      });
      expect(prompt, isNot(contains('平均每天')));
    });

    test('目标达成天数写入 prompt', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2000.0],
        'goal_hit_days': 4,
        'total_days': 7,
      });
      expect(prompt, contains('目标达成 4/7 天'));
    });

    test('体重变化（减重）写入 prompt', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2000.0],
        'weight_diff': -0.7,
      });
      expect(prompt, contains('体重减 0.7 kg'));
    });

    test('体重变化（增重）写入 prompt', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2000.0],
        'weight_diff': 0.5,
      });
      expect(prompt, contains('体重增 0.5 kg'));
    });

    test('体重变化=0 写入"持平"', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2000.0],
        'weight_diff': 0.0,
      });
      expect(prompt, contains('体重持平 0.0 kg'));
    });

    test('特殊人群画像（三字段都非 none）写入 prompt', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2000.0],
        'special_condition': 'pregnancy',
        'diet_preference': 'vegetarian',
        'health_condition': 'diabetes',
      });
      expect(prompt, contains('用户特征：孕期、蛋奶素、糖尿病'));
    });

    test('特殊人群字段为 none 不写入 prompt', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2000.0],
        'special_condition': 'none',
        'diet_preference': 'none',
        'health_condition': 'none',
      });
      expect(prompt, isNot(contains('用户特征')));
    });

    test('特殊人群字段为 null 不崩溃且不写入', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2000.0],
        // 三字段都不传
      });
      expect(prompt, isNot(contains('用户特征')));
    });

    test('特殊人群部分字段非 none 只写入非 none 的', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2000.0],
        'special_condition': 'none',
        'diet_preference': 'vegan',
        'health_condition': 'none',
      });
      expect(prompt, contains('用户特征：纯素'));
    });

    test('未知特殊人群 code 原样输出（不崩溃）', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2000.0],
        'special_condition': 'unknown_condition',
      });
      expect(prompt, contains('unknown_condition'));
    });
  });

  group('问题2 _appendWeeklyBreakdown（仅月报）', () {
    test('周环比写入月报 prompt', () {
      final prompt = provider.buildMonthlySummaryForTest({
        'daily_calories': [2000.0],
        'weekly_breakdown': [
          {'weekStart': '2026-06-07', 'weekEnd': '2026-06-13', 'avgCal': 1950.0},
          {'weekStart': '2026-06-14', 'weekEnd': '2026-06-20', 'avgCal': 2100.0},
        ],
      });
      expect(prompt, contains('周环比'));
      expect(prompt, contains('第1周(2026-06-07~2026-06-13 日均 1950kcal)'));
      expect(prompt, contains('第2周(2026-06-14~2026-06-20 日均 2100kcal)'));
    });

    test('周环比空列表不写入 prompt', () {
      final prompt = provider.buildMonthlySummaryForTest({
        'daily_calories': [2000.0],
        'weekly_breakdown': [],
      });
      // 月报固定结尾含"包含周环比分析"，但 _appendWeeklyBreakdown 写的是"周环比："
      expect(prompt, isNot(contains('周环比：')));
    });

    test('周环比字段缺失不崩溃', () {
      final prompt = provider.buildMonthlySummaryForTest({
        'daily_calories': [2000.0],
        // 不传 weekly_breakdown
      });
      expect(prompt, isNot(contains('周环比：')));
    });

    test('周报不写周环比（仅月报有）', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2000.0],
        'weekly_breakdown': [
          {'weekStart': '2026-06-07', 'weekEnd': '2026-06-13', 'avgCal': 1950.0},
        ],
      });
      // 周报不应包含"周环比："（即使传了 weekly_breakdown）
      expect(prompt, isNot(contains('周环比：')));
    });
  });

  group('问题2 全字段组合（端到端）', () {
    test('周报全字段组合正常构建', () {
      final prompt = provider.buildWeeklySummaryForTest({
        'daily_calories': [2200.0, 1800.0, 2000.0],
        'daily_weights': [70.5, 70.3, 70.2],
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
        'meal_type_calories': {
          'breakfast': 600.0,
          'lunch': 1200.0,
          'dinner': 900.0,
          'snack': 300.0,
        },
        'streak': 3,
        'avg_excess': 100.0,
        'goal_hit_days': 2,
        'weight_diff': -0.3,
        'special_condition': 'none',
        'diet_preference': 'none',
        'health_condition': 'none',
      });
      // 验证关键内容都在
      expect(prompt, contains('减脂'));
      expect(prompt, contains('餐次分布'));
      expect(prompt, contains('已连续记录 3 天'));
      expect(prompt, contains('平均每天超目标 100 kcal'));
      expect(prompt, contains('目标达成 2/7 天'));
      expect(prompt, contains('体重减 0.3 kg'));
      // none 字段不写入
      expect(prompt, isNot(contains('用户特征')));
    });

    test('月报全字段组合含周环比', () {
      final prompt = provider.buildMonthlySummaryForTest({
        'daily_calories': List.filled(30, 2000.0),
        'daily_weights': [70.0],
        'target_calories': 2000,
        'goal': 'bulk',
        'daily_protein': List.filled(30, 100.0),
        'daily_fat': List.filled(30, 65.0),
        'daily_carbs': List.filled(30, 220.0),
        'protein_goal': 100.0,
        'fat_goal': 65.0,
        'carb_goal': 220.0,
        'recorded_days': 30,
        'total_days': 30,
        'coverage_rate': 1.0,
        'preference_foods': ['鸡蛋', '燕麦'],
        'meal_type_calories': {
          'breakfast': 500.0,
          'lunch': 700.0,
          'dinner': 600.0,
          'snack': 200.0,
        },
        'streak': 30,
        'avg_excess': 0.0,
        'goal_hit_days': 30,
        'weight_diff': 1.5,
        'weekly_breakdown': [
          {'weekStart': '2026-06-07', 'weekEnd': '2026-06-13', 'avgCal': 1950.0},
          {'weekStart': '2026-06-14', 'weekEnd': '2026-06-20', 'avgCal': 2050.0},
        ],
        'special_condition': 'elderly',
        'diet_preference': 'none',
        'health_condition': 'hypertension',
      });
      expect(prompt, contains('增肌'));
      expect(prompt, contains('餐次分布'));
      expect(prompt, contains('已连续记录 30 天'));
      // avg_excess=0 不写入
      expect(prompt, isNot(contains('平均每天')));
      expect(prompt, contains('目标达成 30/30 天'));
      expect(prompt, contains('体重增 1.5 kg'));
      expect(prompt, contains('周环比'));
      expect(prompt, contains('用户特征：老年、高血压'));
    });
  });

  // 防 debugPrint 污染测试输出
  setUpAll(() {
    debugPrint = (String? message, {int? wrapWidth}) {};
  });
}
