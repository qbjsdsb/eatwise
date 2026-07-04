// test/nutrition/food_profile_tagger_test.dart
//
// 食物画像标签器单元测试（v4 推荐算法核心组件）
// 覆盖：4 维度标签推断 + 中文展示文案 + 边界场景

import 'package:eatwise/nutrition/food_profile_tagger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FoodProfileTagger.tag 标签推断', () {
    group('taste 口味', () {
      test('甜味识别', () {
        expect(FoodProfileTagger.tag('巧克力蛋糕').taste, 'sweet');
        expect(FoodProfileTagger.tag('糖醋排骨').taste, 'sweet');
        expect(FoodProfileTagger.tag('蜜汁叉烧').taste, 'sweet');
        expect(FoodProfileTagger.tag('豆沙包').taste, 'sweet');
      });
      test('酸味识别', () {
        expect(FoodProfileTagger.tag('酸菜鱼').taste, 'sour');
        expect(FoodProfileTagger.tag('酸辣土豆丝').taste, 'sour'); // 酸辣归 sour
        expect(FoodProfileTagger.tag('柠檬鸡').taste, 'sour');
        expect(FoodProfileTagger.tag('醋溜白菜').taste, 'sour');
      });
      test('苦味识别', () {
        expect(FoodProfileTagger.tag('苦瓜炒蛋').taste, 'bitter');
        expect(FoodProfileTagger.tag('凉拌苦菜').taste, 'bitter');
      });
      test('辣味识别（含麻）', () {
        expect(FoodProfileTagger.tag('麻婆豆腐').taste, 'spicy');
        expect(FoodProfileTagger.tag('麻辣火锅').taste, 'spicy');
        expect(FoodProfileTagger.tag('辣椒炒肉').taste, 'spicy');
        expect(FoodProfileTagger.tag('川菜鱼香肉丝').taste, 'spicy');
        expect(FoodProfileTagger.tag('湘菜剁椒鱼头').taste, 'spicy');
      });
      test('咸味识别', () {
        expect(FoodProfileTagger.tag('咸鱼茄子煲').taste, 'salty');
        expect(FoodProfileTagger.tag('腊肉炒饭').taste, 'salty');
        expect(FoodProfileTagger.tag('香肠炒饭').taste, 'salty');
      });
      test('清淡识别', () {
        expect(FoodProfileTagger.tag('清蒸鲈鱼').taste, 'light');
        expect(FoodProfileTagger.tag('白灼虾').taste, 'light');
        expect(FoodProfileTagger.tag('皮蛋瘦肉粥').taste, 'light');
      });
      test('无匹配返回 null', () {
        expect(FoodProfileTagger.tag('米饭').taste, isNull);
        expect(FoodProfileTagger.tag('鸡胸肉').taste, isNull);
      });
    });

    group('style 风格', () {
      test('西式', () {
        expect(FoodProfileTagger.tag('牛排').style, 'western');
        expect(FoodProfileTagger.tag('芝士汉堡').style, 'western');
        expect(FoodProfileTagger.tag('番茄意面').style, 'western');
        expect(FoodProfileTagger.tag('凯撒沙拉').style, 'western');
      });
      test('日式', () {
        // 注："三文鱼寿司" 因 seafood 优先归 seafood，此处用不含海鲜的寿司验证 japanese
        expect(FoodProfileTagger.tag('金枪鱼寿司').style, 'japanese');
        expect(FoodProfileTagger.tag('天妇罗').style, 'japanese');
        expect(FoodProfileTagger.tag('日式拉面').style, 'japanese');
      });
      test('韩式', () {
        expect(FoodProfileTagger.tag('韩式烤肉').style, 'korean');
        expect(FoodProfileTagger.tag('石锅拌饭').style, 'korean');
        expect(FoodProfileTagger.tag('部队锅').style, 'korean');
      });
      test('海鲜（独立风格）', () {
        expect(FoodProfileTagger.tag('海鲜拼盘').style, 'seafood');
        expect(FoodProfileTagger.tag('蒜蓉扇贝').style, 'seafood');
        expect(FoodProfileTagger.tag('三文鱼刺身').style, 'seafood'); // seafood 优先于 japanese
      });
      test('快餐', () {
        expect(FoodProfileTagger.tag('麦当劳').style, 'fast_food');
        expect(FoodProfileTagger.tag('肯德基').style, 'fast_food');
        expect(FoodProfileTagger.tag('外卖盒饭').style, 'fast_food');
      });
      test('家常', () {
        expect(FoodProfileTagger.tag('家常豆腐').style, 'home');
        expect(FoodProfileTagger.tag('番茄炒饭').style, 'home'); // 含"炒饭"
      });
      test('无匹配返回 null', () {
        expect(FoodProfileTagger.tag('米饭').style, isNull);
        expect(FoodProfileTagger.tag('白菜').style, isNull);
      });
    });

    group('texture 材质/烹饪法', () {
      test('汤水', () {
        expect(FoodProfileTagger.tag('番茄蛋花汤').texture, 'soup');
        expect(FoodProfileTagger.tag('银耳羹').texture, 'soup');
        expect(FoodProfileTagger.tag('老火煲汤').texture, 'soup');
      });
      test('小炒', () {
        expect(FoodProfileTagger.tag('辣椒炒肉').texture, 'stir_fry');
        expect(FoodProfileTagger.tag('爆炒肥肠').texture, 'stir_fry');
      });
      test('清蒸', () {
        expect(FoodProfileTagger.tag('清蒸鲈鱼').texture, 'steamed');
      });
      test('炖煮', () {
        expect(FoodProfileTagger.tag('土豆炖牛肉').texture, 'boiled');
        expect(FoodProfileTagger.tag('卤鸡腿').texture, 'boiled');
      });
      test('烧烤', () {
        expect(FoodProfileTagger.tag('烤鸡翅').texture, 'grilled');
        expect(FoodProfileTagger.tag('叉烧肉').texture, 'grilled');
      });
      test('煎炸', () {
        expect(FoodProfileTagger.tag('炸薯条').texture, 'fried');
        expect(FoodProfileTagger.tag('生煎包').texture, 'fried');
        expect(FoodProfileTagger.tag('香煎三文鱼').texture, 'fried');
      });
      test('凉拌', () {
        expect(FoodProfileTagger.tag('凉拌黄瓜').texture, 'cold');
        expect(FoodProfileTagger.tag('冰镇西瓜').texture, 'cold');
      });
      test('无匹配返回 null', () {
        expect(FoodProfileTagger.tag('米饭').texture, isNull);
      });
    });

    group('priceTier 价格档', () {
      test('经济', () {
        expect(FoodProfileTagger.tag('米饭').priceTier, 'budget');
        expect(FoodProfileTagger.tag('馒头').priceTier, 'budget');
        expect(FoodProfileTagger.tag('肉包子').priceTier, 'budget');
        expect(FoodProfileTagger.tag('阳春面条').priceTier, 'budget'); // 含"面条"
      });
      test('精致', () {
        expect(FoodProfileTagger.tag('牛排').priceTier, 'premium');
        expect(FoodProfileTagger.tag('蒜蓉龙虾').priceTier, 'premium');
        expect(FoodProfileTagger.tag('海参炖鸡').priceTier, 'premium');
        expect(FoodProfileTagger.tag('鲍鱼捞饭').priceTier, 'premium');
      });
      test('精致 vs 经济冲突时，按 _matchFirst 顺序（budget 在前）', () {
        // "海参粥" 同时命中 "粥"(budget) 和 "海参"(premium)，
        // _priceTierKeywords 中 "粥" 在前，所以返回 budget（_matchFirst 行为）
        expect(FoodProfileTagger.tag('海参粥').priceTier, 'budget');
      });
      test('中等价位无标签（默认 null）', () {
        expect(FoodProfileTagger.tag('鸡胸肉').priceTier, isNull);
        expect(FoodProfileTagger.tag('番茄炒蛋').priceTier, isNull);
      });
    });

    test('多维度同时命中', () {
      // "清蒸鲈鱼" → taste=light + style=seafood + texture=steamed
      final tags = FoodProfileTagger.tag('清蒸鲈鱼');
      expect(tags.taste, 'light');
      expect(tags.style, 'seafood');
      expect(tags.texture, 'steamed');
      expect(tags.priceTier, isNull);
    });

    test('全部未命中返回空 Tags', () {
      final tags = FoodProfileTagger.tag('水');
      expect(tags.taste, isNull);
      expect(tags.style, isNull);
      expect(tags.texture, isNull);
      expect(tags.priceTier, isNull);
    });
  });

  group('FoodProfileTagger.*Label 中文文案', () {
    test('tasteLabel', () {
      expect(FoodProfileTagger.tasteLabel('sweet'), '甜');
      expect(FoodProfileTagger.tasteLabel('sour'), '酸');
      expect(FoodProfileTagger.tasteLabel('bitter'), '苦');
      expect(FoodProfileTagger.tasteLabel('spicy'), '辣');
      expect(FoodProfileTagger.tasteLabel('salty'), '咸');
      expect(FoodProfileTagger.tasteLabel('light'), '清淡');
      // 未知标签原样返回
      expect(FoodProfileTagger.tasteLabel('unknown'), 'unknown');
    });
    test('styleLabel', () {
      expect(FoodProfileTagger.styleLabel('western'), '西式');
      expect(FoodProfileTagger.styleLabel('japanese'), '日式');
      expect(FoodProfileTagger.styleLabel('seafood'), '海鲜');
      expect(FoodProfileTagger.styleLabel('fast_food'), '快餐');
    });
    test('textureLabel', () {
      expect(FoodProfileTagger.textureLabel('soup'), '汤水');
      expect(FoodProfileTagger.textureLabel('stir_fry'), '小炒');
      expect(FoodProfileTagger.textureLabel('steamed'), '清蒸');
      expect(FoodProfileTagger.textureLabel('fried'), '煎炸');
    });
    test('priceTierLabel', () {
      expect(FoodProfileTagger.priceTierLabel('budget'), '经济');
      expect(FoodProfileTagger.priceTierLabel('medium'), '适中');
      expect(FoodProfileTagger.priceTierLabel('premium'), '精致');
    });
  });
}
