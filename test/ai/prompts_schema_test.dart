// prompts.dart schema 一致性单元测试（v1.10 新增）
//
// 验证 systemPrompt 中所有示例 JSON：
// 1. Prompts.version == 'v1.10'
// 2. 每个示例 JSON 可被 jsonDecode 解析
// 3. 每个示例含 v1.10 新增的 3 个字段（package_serving_protein_g/fat_g/carbs_g）
// 4. food_category 字段值在支持的品类枚举内
// 5. 示例数量符合预期（防漏示例）
import 'dart:convert';

import 'package:eatwise/ai/prompts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 从 systemPrompt 中提取所有示例 JSON
  /// 示例格式：每行一个完整 JSON，以 {"reasoning" 开头
  List<Map<String, dynamic>> extractExamples(String prompt) {
    final examples = <Map<String, dynamic>>[];
    // 多行模式，匹配以 {"reasoning" 开头的整行 JSON
    final regex = RegExp(r'^\{"reasoning".*\}$', multiLine: true);
    for (final match in regex.allMatches(prompt)) {
      final jsonStr = match.group(0)!;
      try {
        final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
        examples.add(parsed);
      } catch (e) {
        // 解析失败会在测试中暴露
        examples.add(<String, dynamic>{'__parse_error__': e.toString()});
      }
    }
    return examples;
  }

  /// v1.10 支持的 food_category 枚举
  const supportedCategories = {
    'water', 'carbonated', 'juice', 'milk', 'cream', 'oil', 'honey', 'sauce',
    'alcohol', 'beer', 'wine', 'yogurt', 'soup', 'tea', 'protein_drink',
    'energy_drink', 'solid',
  };

  group('prompts schema 一致性', () {
    test('Prompts.version == v1.10', () {
      expect(Prompts.version, 'v1.10');
    });

    test('systemPrompt 非空', () {
      expect(Prompts.systemPrompt, isNotEmpty);
    });

    test('systemPrompt 含 v1.10 新字段定义', () {
      // schema 中应明确声明 3 个新字段
      expect(Prompts.systemPrompt, contains('package_serving_protein_g'));
      expect(Prompts.systemPrompt, contains('package_serving_fat_g'));
      expect(Prompts.systemPrompt, contains('package_serving_carbs_g'));
    });

    test('systemPrompt 含 v1.10 新品类枚举', () {
      expect(Prompts.systemPrompt, contains('tea'));
      expect(Prompts.systemPrompt, contains('protein_drink'));
      expect(Prompts.systemPrompt, contains('energy_drink'));
    });

    test('示例数量 >= 9（防漏示例）', () {
      final examples = extractExamples(Prompts.systemPrompt);
      expect(examples.length, greaterThanOrEqualTo(9),
          reason: '应至少有示例 1-8 + 8b 共 9 个，实际 ${examples.length}');
    });
  });

  group('每个示例 JSON schema 验证', () {
    final examples = extractExamples(Prompts.systemPrompt);

    // 验证每个示例的字段一致性
    for (var i = 0; i < examples.length; i++) {
      final example = examples[i];
      final label = '示例 ${i + 1}';

      test('$label 可被 jsonDecode 解析', () {
        expect(example.containsKey('__parse_error__'), isFalse,
            reason: example['__parse_error__']?.toString() ?? '解析失败');
      });

      test('$label 含必填字段 dish_name', () {
        expect(example.containsKey('dish_name'), isTrue);
      });

      test('$label 含 v1.10 新字段 package_serving_protein_g', () {
        expect(example.containsKey('package_serving_protein_g'), isTrue,
            reason: 'v1.10 BUG-3 修复：所有示例必须含此字段保持 schema 一致');
      });

      test('$label 含 v1.10 新字段 package_serving_fat_g', () {
        expect(example.containsKey('package_serving_fat_g'), isTrue);
      });

      test('$label 含 v1.10 新字段 package_serving_carbs_g', () {
        expect(example.containsKey('package_serving_carbs_g'), isTrue);
      });

      test('$label food_category 值在支持枚举内', () {
        final category = example['food_category'] as String?;
        expect(category, isNotNull);
        expect(supportedCategories, contains(category),
            reason: 'food_category=$category 不在支持枚举内');
      });

      test('$label 含 additional_dishes 字段（即使空数组）', () {
        expect(example.containsKey('additional_dishes'), isTrue);
      });

      test('$label 含 reasoning 字段（v1.9 必填）', () {
        expect(example.containsKey('reasoning'), isTrue);
        expect((example['reasoning'] as String?)?.isNotEmpty, isTrue,
            reason: 'reasoning 不能为空字符串');
      });
    }
  });

  group('示例 8b 菊花茶关键字段验证', () {
    test('示例 8b 是含糖茶饮（food_category=tea）', () {
      final examples = extractExamples(Prompts.systemPrompt);
      // 示例 8b 是最后一个（第 9 个）
      final example8b = examples.last;
      expect(example8b['food_category'], 'tea');
    });

    test('示例 8b 含 package_serving_carbs_g > 0（含糖饮料碳水必标）', () {
      final examples = extractExamples(Prompts.systemPrompt);
      final example8b = examples.last;
      final carbs = example8b['package_serving_carbs_g'];
      expect(carbs, isNotNull);
      expect((carbs as num).toDouble(), greaterThan(0),
          reason: '含糖饮料碳水必标，不应为 0');
    });
  });
}
