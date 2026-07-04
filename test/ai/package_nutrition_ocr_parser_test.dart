// 包装营养成分表 OCR 正则提取单元测试（v1.10 新增）
//
// 覆盖 PackageNutritionOcrParser.parse：
// 1. 中文格式：蛋白质/脂肪/碳水/碳水化合物 + 各种分隔符
// 2. 英文格式：protein/fat/carbs/carbohydrate
// 3. 整数 / 小数 / 0g（蛋白质/脂肪常为 0）
// 4. 空串 / 无可识别营养素
// 5. 菊花茶包装 OCR 实例（与 prompts.dart 示例 8b 一致）
import 'package:eatwise/ai/package_nutrition_ocr_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PackageNutritionOcrParser.parse - 中文格式', () {
    test('菊花茶包装 OCR：蛋白质0g 脂肪0g 碳水16g', () {
      // 与 prompts.dart 示例 8b 一致
      final r = PackageNutritionOcrParser.parse(
          '每份250ml 能量272kJ 蛋白质0g 脂肪0g 碳水16g');
      expect(r.proteinG, 0);
      expect(r.fatG, 0);
      expect(r.carbsG, 16);
      expect(r.isEmpty, isFalse);
    });

    test('完整中文格式：碳水化合物（全词）', () {
      final r = PackageNutritionOcrParser.parse(
          '每100g：能量180kJ 蛋白质0.5g 脂肪1.2g 碳水化合物10.6g');
      expect(r.proteinG, 0.5);
      expect(r.fatG, 1.2);
      expect(r.carbsG, 10.6);
    });

    test('中文 + 全角冒号分隔', () {
      final r = PackageNutritionOcrParser.parse(
          '蛋白质：1.5g 脂肪：2.0g 碳水化合物：15.3g');
      expect(r.proteinG, 1.5);
      expect(r.fatG, 2.0);
      expect(r.carbsG, 15.3);
    });

    test('中文 + 半角冒号分隔', () {
      final r = PackageNutritionOcrParser.parse(
          '蛋白质:1.5g 脂肪:2.0g 碳水:15.3g');
      expect(r.proteinG, 1.5);
      expect(r.fatG, 2.0);
      expect(r.carbsG, 15.3);
    });

    test('中文 + 顿号分隔', () {
      final r = PackageNutritionOcrParser.parse(
          '蛋白质、1.5g 脂肪、2.0g 碳水、15.3g');
      expect(r.proteinG, 1.5);
      expect(r.fatG, 2.0);
      expect(r.carbsG, 15.3);
    });

    test('中文 + 空格分隔（无冒号）', () {
      final r = PackageNutritionOcrParser.parse(
          '蛋白质 0g 脂肪 0g 碳水化合物 10.6g');
      expect(r.proteinG, 0);
      expect(r.fatG, 0);
      expect(r.carbsG, 10.6);
    });

    test('中文紧贴数值（无分隔符）', () {
      final r = PackageNutritionOcrParser.parse(
          '蛋白质0g 脂肪0g 碳水16g');
      expect(r.proteinG, 0);
      expect(r.fatG, 0);
      expect(r.carbsG, 16);
    });

    test('0g 必须能识别（含糖饮料蛋白/脂肪常为 0）', () {
      final r = PackageNutritionOcrParser.parse('蛋白质0g 脂肪0g 碳水0g');
      expect(r.proteinG, 0);
      expect(r.fatG, 0);
      expect(r.carbsG, 0);
      expect(r.isEmpty, isFalse); // 字段已提取到 0，不算空
    });

    test('小数支持（10.6g / 0.5g）', () {
      final r = PackageNutritionOcrParser.parse(
          '蛋白质0.5g 脂肪3.5g 碳水化合物10.6g');
      expect(r.proteinG, 0.5);
      expect(r.fatG, 3.5);
      expect(r.carbsG, 10.6);
    });
  });

  group('PackageNutritionOcrParser.parse - 英文格式', () {
    test('英文 + 空格分隔', () {
      final r = PackageNutritionOcrParser.parse(
          'protein 0g fat 0g carbs 16g');
      expect(r.proteinG, 0);
      expect(r.fatG, 0);
      expect(r.carbsG, 16);
    });

    test('英文 + 冒号分隔', () {
      final r = PackageNutritionOcrParser.parse(
          'protein: 1.5g fat: 2.0g carbohydrate: 15.3g');
      expect(r.proteinG, 1.5);
      expect(r.fatG, 2.0);
      expect(r.carbsG, 15.3);
    });

    test('大小写不敏感（Protein/FAT/Carbs）', () {
      final r = PackageNutritionOcrParser.parse(
          'Protein 0g FAT 0g Carbs 16g');
      expect(r.proteinG, 0);
      expect(r.fatG, 0);
      expect(r.carbsG, 16);
    });

    test('carbohydrate 全词', () {
      final r = PackageNutritionOcrParser.parse(
          'protein 0g fat 0g carbohydrate 16g');
      expect(r.proteinG, 0);
      expect(r.fatG, 0);
      expect(r.carbsG, 16);
    });
  });

  group('PackageNutritionOcrParser.parse - 缺失/异常', () {
    test('空串 → 全 null + isEmpty=true', () {
      final r = PackageNutritionOcrParser.parse('');
      expect(r.proteinG, isNull);
      expect(r.fatG, isNull);
      expect(r.carbsG, isNull);
      expect(r.isEmpty, isTrue);
    });

    test('无营养素原文（仅能量）→ 全 null', () {
      final r = PackageNutritionOcrParser.parse('每份250ml 能量272kJ');
      expect(r.proteinG, isNull);
      expect(r.fatG, isNull);
      expect(r.carbsG, isNull);
      expect(r.isEmpty, isTrue);
    });

    test('仅含蛋白质 → 仅 proteinG 非 null', () {
      final r = PackageNutritionOcrParser.parse('蛋白质 5g');
      expect(r.proteinG, 5);
      expect(r.fatG, isNull);
      expect(r.carbsG, isNull);
      expect(r.isEmpty, isFalse);
    });

    test('仅含脂肪 → 仅 fatG 非 null', () {
      final r = PackageNutritionOcrParser.parse('脂肪 5g');
      expect(r.proteinG, isNull);
      expect(r.fatG, 5);
      expect(r.carbsG, isNull);
    });

    test('仅含碳水 → 仅 carbsG 非 null', () {
      final r = PackageNutritionOcrParser.parse('碳水 5g');
      expect(r.proteinG, isNull);
      expect(r.fatG, isNull);
      expect(r.carbsG, 5);
    });

    test('负数不识别（防 OCR 误读）', () {
      // 正则只匹配 \d+，负号不匹配
      final r = PackageNutritionOcrParser.parse('蛋白质 -5g');
      expect(r.proteinG, isNull);
    });

    test('非数字不识别', () {
      final r = PackageNutritionOcrParser.parse('蛋白质 abc g');
      expect(r.proteinG, isNull);
    });

    test('无 g 单位不识别', () {
      // 营养成分表必须带 g 单位
      final r = PackageNutritionOcrParser.parse('蛋白质 5 脂肪 3');
      expect(r.proteinG, isNull);
      expect(r.fatG, isNull);
    });
  });

  group('PackageNutritionOcrParser.parse - 真实包装场景', () {
    test('菊花茶盒装饮料（与 prompts.dart 示例 8b 一致）', () {
      // 用户反馈"菊花茶碳水缺失"的根因场景
      final r = PackageNutritionOcrParser.parse(
          '每份250ml 能量272kJ 蛋白质0g 脂肪0g 碳水16g');
      expect(r.proteinG, 0);
      expect(r.fatG, 0);
      expect(r.carbsG, 16); // 关键：碳水必标，必须提取到 16
      expect(r.isEmpty, isFalse);
    });

    test('红牛功能饮料（碳水必标）', () {
      final r = PackageNutritionOcrParser.parse(
          '每100ml：能量188kJ 蛋白质0g 脂肪0g 碳水11g');
      expect(r.proteinG, 0);
      expect(r.fatG, 0);
      expect(r.carbsG, 11);
    });

    test('豆奶蛋白饮料', () {
      final r = PackageNutritionOcrParser.parse(
          '每份250ml：能量251kJ 蛋白质3g 脂肪1.5g 碳水5g');
      expect(r.proteinG, 3);
      expect(r.fatG, 1.5);
      expect(r.carbsG, 5);
    });

    test('混合中英文（部分蛋白用英文，碳水用中文）', () {
      final r = PackageNutritionOcrParser.parse(
          'protein 0g fat 0g 碳水化合物 16g');
      expect(r.proteinG, 0);
      expect(r.fatG, 0);
      expect(r.carbsG, 16);
    });

    test('每份/每100g 前缀不影响提取', () {
      final r = PackageNutritionOcrParser.parse(
          '营养成分表（每100g）：能量 180kJ，蛋白质 0.5g，脂肪 0g，碳水化合物 10.6g，钠 12mg');
      expect(r.proteinG, 0.5);
      expect(r.fatG, 0);
      expect(r.carbsG, 10.6);
    });
  });
}
