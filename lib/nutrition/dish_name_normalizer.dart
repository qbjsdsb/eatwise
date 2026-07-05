// lib/nutrition/dish_name_normalizer.dart
//
// 菜名归一化纯函数（M19 AI 推荐去重配套）
//
// 让"鸡胸肉(去皮)"和"鸡胸肉"、"某品牌炒鸡胸肉200g"和"鸡胸肉"在去重时被视为同一道菜。
// 消除用户感知的"实质重复"（括号注释/份量/品牌/烹饪方式前缀差异）。
//
// 归一化规则（按顺序应用，每步后空则回退上一步结果）：
// 1. 去括号及内容（中英文括号）
// 2. 去份量后缀（数字 + g/G/克）
// 3. 去品牌前缀（含"品牌"/"牌"关键字时，去"X品牌"/"X牌"前缀）
// 4. 去烹饪方式前缀（词典：炒/凉拌/清蒸/红烧/煎/炸/烤/焖/炖/煮/卤/腌/拌/蒸）
//
// 不变量：
// - 纯函数，无副作用，无 IO
// - 输入空字符串 → 返回空字符串
// - 任何步骤归一化为空 → 返回该步骤前的值（避免归一化为空）
// - 不覆盖食材重叠模糊匹配（"鸡胸肉沙拉" vs "烤鸡胸沙拉" 视为不同，需食材维度去重）

/// 菜名归一化（M19 AI 推荐去重用）
///
/// 入参 [name] 原始菜名（如"某品牌炒鸡胸肉(去皮)200g"）
/// 返回归一化后的菜名（如"鸡胸肉"）
String normalizeDishName(String name) {
  if (name.isEmpty) return '';

  var result = name.trim();
  if (result.isEmpty) return '';

  // 1. 去括号及内容（中英文括号）
  final afterBracket = _stripParentheses(result);
  if (afterBracket.isNotEmpty) result = afterBracket;

  // 2. 去份量后缀（数字 + g/G/克，可能带空格）
  final afterWeight = _stripWeightSuffix(result);
  if (afterWeight.isNotEmpty) result = afterWeight;

  // 3. 去品牌前缀（含"品牌"/"牌"关键字时，去"X品牌"/"X牌"前缀）
  final afterBrand = _stripBrandPrefix(result);
  if (afterBrand.isNotEmpty) result = afterBrand;

  // 4. 去烹饪方式前缀
  final afterCooking = _stripCookingPrefix(result);
  if (afterCooking.isNotEmpty) result = afterCooking;

  return result;
}

/// 去括号及内容（支持中英文括号，支持多个括号）
String _stripParentheses(String s) {
  // 中英文括号都去掉（含内容）
  // 用正则：\(.*?\) /（.*?） 非贪婪匹配
  return s
      .replaceAll(RegExp(r'\([^)]*\)'), '')
      .replaceAll(RegExp(r'（[^）]*）'), '')
      .trim();
}

/// 去份量后缀（数字 + g/G/克，可能带空格）
String _stripWeightSuffix(String s) {
  // 匹配末尾的 "200g" / "200G" / "200克" / " 200 克" 等
  return s.replaceAll(RegExp(r'\s*\d+\s*[gG克]\s*$'), '').trim();
}

/// 去品牌前缀（含"品牌"/"牌"关键字时，去"X品牌"/"X牌"前缀）
String _stripBrandPrefix(String s) {
  // "某品牌鸡胸肉" → "鸡胸肉"
  // "泰森牌鸡胸肉" → "鸡胸肉"
  // 仅当含"品牌"或"牌"关键字时，去掉到该关键字为止的前缀
  final brandIdx = s.indexOf('品牌');
  if (brandIdx >= 0) {
    return s.substring(brandIdx + 2).trim();
  }
  final paiIdx = s.indexOf('牌');
  if (paiIdx >= 0) {
    return s.substring(paiIdx + 1).trim();
  }
  return s;
}

/// 烹饪方式词典（前缀匹配）
const _cookingPrefixes = <String>[
  '凉拌', // 2 字优先匹配
  '清蒸',
  '红烧',
  '爆炒',
  '干煸',
  '炒',
  '煎',
  '炸',
  '烤',
  '焖',
  '炖',
  '煮',
  '卤',
  '腌',
  '拌',
  '蒸',
];

/// 去烹饪方式前缀（词典匹配，仅当剩余部分非空时才去）
String _stripCookingPrefix(String s) {
  for (final prefix in _cookingPrefixes) {
    if (s.startsWith(prefix)) {
      final rest = s.substring(prefix.length).trim();
      // 仅当去掉后剩余非空才去前缀（避免"凉拌"→""）
      if (rest.isNotEmpty) return rest;
    }
  }
  return s;
}
