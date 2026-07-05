// test/nutrition/dish_name_normalizer_test.dart
//
// 菜名归一化纯函数测试（M19 TDD Round 1）
//
// 覆盖 4 类归一化规则 + 边界场景：
// 1. 去括号及内容
// 2. 去份量后缀
// 3. 去品牌前缀
// 4. 去烹饪方式前缀
// 5. 组合场景
// 6. 边界：空字符串 / 纯修饰词 / 无修饰词

import 'package:eatwise/nutrition/dish_name_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeDishName 菜名归一化 (M19)', () {
    group('去括号及内容', () {
      test('简单括号注释', () {
        expect(normalizeDishName('鸡胸肉(去皮)'), '鸡胸肉');
      });
      test('中文括号', () {
        expect(normalizeDishName('鸡胸肉（去皮）'), '鸡胸肉');
      });
      test('括号在中间', () {
        expect(normalizeDishName('鸡胸肉(去皮)沙拉'), '鸡胸肉沙拉');
      });
    });

    group('去份量后缀', () {
      test('数字+g 后缀', () {
        expect(normalizeDishName('鸡胸肉200g'), '鸡胸肉');
      });
      test('数字+G 大写', () {
        expect(normalizeDishName('鸡胸肉200G'), '鸡胸肉');
      });
      test('数字+克 中文', () {
        expect(normalizeDishName('鸡胸肉200克'), '鸡胸肉');
      });
      test('带空格的份量', () {
        expect(normalizeDishName('鸡胸肉 200 克'), '鸡胸肉');
      });
    });

    group('去品牌前缀', () {
      test('某品牌前缀', () {
        expect(normalizeDishName('某品牌鸡胸肉'), '鸡胸肉');
      });
      test('XX牌前缀', () {
        expect(normalizeDishName('泰森牌鸡胸肉'), '鸡胸肉');
      });
    });

    group('去烹饪方式前缀', () {
      test('炒前缀', () {
        expect(normalizeDishName('炒番茄蛋'), '番茄蛋');
      });
      test('凉拌前缀', () {
        expect(normalizeDishName('凉拌黄瓜'), '黄瓜');
      });
      test('清蒸前缀', () {
        expect(normalizeDishName('清蒸鲈鱼'), '鲈鱼');
      });
      test('红烧前缀', () {
        expect(normalizeDishName('红烧排骨'), '排骨');
      });
    });

    group('组合场景', () {
      test('品牌+烹饪方式+括号+份量', () {
        expect(normalizeDishName('某品牌炒鸡胸肉(去皮)200g'), '鸡胸肉');
      });
      test('烹饪方式+括号', () {
        expect(normalizeDishName('炒鸡蛋(全蛋)'), '鸡蛋');
      });
    });

    group('边界场景', () {
      test('空字符串返回空字符串', () {
        expect(normalizeDishName(''), '');
      });
      test('纯烹饪方式返回原值（避免归一化为空）', () {
        // "凉拌" 去掉后为空，应返回原值
        expect(normalizeDishName('凉拌'), '凉拌');
      });
      test('无修饰词返回原值', () {
        expect(normalizeDishName('鸡胸肉'), '鸡胸肉');
      });
      test('只有括号内容返回原值', () {
        // "(去皮)" 去掉后为空，应返回原值
        expect(normalizeDishName('(去皮)'), '(去皮)');
      });
    });
  });
}
