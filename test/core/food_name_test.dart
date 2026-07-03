// food_name 工具单元测试
import 'package:eatwise/core/util/food_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('placeholderFoodName', () {
    test('返回 "食物 #id" 格式', () {
      expect(placeholderFoodName(42), '食物 #42');
      expect(placeholderFoodName(0), '食物 #0');
      expect(placeholderFoodName(-1), '食物 #-1');
      expect(placeholderFoodName(999999), '食物 #999999');
    });
  });

  group('isPlaceholderFoodName', () {
    test('识别占位名', () {
      expect(isPlaceholderFoodName('食物 #42'), true);
      expect(isPlaceholderFoodName('食物 #0'), true);
      expect(isPlaceholderFoodName('食物 #-1'), true);
    });

    test('非占位名返回 false', () {
      expect(isPlaceholderFoodName('番茄炒蛋'), false);
      expect(isPlaceholderFoodName(''), false);
      expect(isPlaceholderFoodName('食物'), false); // 缺 # 与 id
      expect(isPlaceholderFoodName('#42'), false); // 缺 "食物 " 前缀
      expect(isPlaceholderFoodName('食物番茄'), false); // 缺 #
    });

    test('前缀匹配（"食物 #42abc" 也算占位名）', () {
      // startsWith 语义：只要以 "食物 #" 开头即认为是占位名
      expect(isPlaceholderFoodName('食物 #42 abc'), true);
    });
  });

  group('往返一致性', () {
    test('placeholderFoodName 生成的总能被 isPlaceholderFoodName 识别', () {
      for (final id in [0, 1, 42, 999, -1, 999999]) {
        expect(isPlaceholderFoodName(placeholderFoodName(id)), true);
      }
    });
  });
}
