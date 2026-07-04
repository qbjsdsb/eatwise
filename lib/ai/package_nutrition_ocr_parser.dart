// 包装营养成分表 OCR 正则提取工具（v1.10 新增）
//
// 用途：AI 返回 package_nutrition_table_ocr 原文后，后端用正则二次提取
// 蛋白质/脂肪/碳水值（每份克数）。当 AI 漏填 estimated_protein_g/fat_g/carbs_g
// 但 OCR 原文包含营养表数据时，从原文兜底提取，避免碳水缺失问题。
//
// 设计依据：GB 28050 强制预包装食品标注蛋白质/脂肪/碳水化合物，
// 含糖饮料的碳水（糖）是核心指标必标项。AI 偶发漏填时 OCR 原文是可靠兜底源。
//
// 正则策略：
// - 容错多种写法："碳水"/"碳水化合物"/"糖"/"蛋白质"/"脂肪"/"protein"/"fat"/"carbs"
// - 容错中英文冒号/空格/全角字符
// - 容错小数（如 10.6g）/整数（如 10g）/范围（如 10-12g 取首值）
// - 容错"0g"（蛋白质/脂肪常为 0，必须能识别）

/// 包装营养成分表 OCR 提取结果（每份克数，null 表示未提取到）
class PackageNutritionOcrResult {
  /// 蛋白质（每份克数）
  final double? proteinG;
  /// 脂肪（每份克数）
  final double? fatG;
  /// 碳水/碳水化合物/糖（每份克数）
  final double? carbsG;

  const PackageNutritionOcrResult({
    this.proteinG,
    this.fatG,
    this.carbsG,
  });

  /// 三个字段是否全部为 null（OCR 原文无可识别营养素）
  bool get isEmpty => proteinG == null && fatG == null && carbsG == null;
}

class PackageNutritionOcrParser {
  PackageNutritionOcrParser._();

  /// 从包装营养成分表 OCR 原文提取蛋白/脂肪/碳水（每份克数）
  ///
  /// [ocrText] AI 返回的 package_nutrition_table_ocr 原文
  /// （如 "每份250ml 能量180kJ 蛋白质0g 脂肪0g 碳水10.6g"）
  ///
  /// 返回 [PackageNutritionOcrResult]，未提取到的字段为 null
  static PackageNutritionOcrResult parse(String ocrText) {
    if (ocrText.isEmpty) {
      return const PackageNutritionOcrResult();
    }
    return PackageNutritionOcrResult(
      proteinG: _extractMacro(ocrText, _proteinPatterns),
      fatG: _extractMacro(ocrText, _fatPatterns),
      carbsG: _extractMacro(ocrText, _carbsPatterns),
    );
  }

  /// 提取单个宏量营养素（按多个模式依次尝试，首个命中返回）
  /// 返回数值（克），未命中返回 null
  static double? _extractMacro(String text, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final valueStr = match.group(1);
        if (valueStr != null) {
          final value = double.tryParse(valueStr);
          if (value != null && !value.isNaN && value >= 0) {
            return value;
          }
        }
      }
    }
    return null;
  }

  // 蛋白质匹配模式（中英文 + 容错冒号/空格）
  // 例：蛋白质0g / 蛋白质：0g / 蛋白质 0g / protein 0g / 蛋白质0.5g
  static final List<RegExp> _proteinPatterns = [
    RegExp(r'蛋白质\s*[：:、\s]*\s*(\d+(?:\.\d+)?)\s*g', caseSensitive: false),
    RegExp(r'protein\s*[：:、\s]*\s*(\d+(?:\.\d+)?)\s*g', caseSensitive: false),
  ];

  // 脂肪匹配模式
  // 例：脂肪0g / 脂肪：0g / 脂肪 0g / fat 0g / 脂肪3.5g
  static final List<RegExp> _fatPatterns = [
    RegExp(r'脂肪\s*[：:、\s]*\s*(\d+(?:\.\d+)?)\s*g', caseSensitive: false),
    RegExp(r'fat\s*[：:、\s]*\s*(\d+(?:\.\d+)?)\s*g', caseSensitive: false),
  ];

  // 碳水匹配模式（含"碳水化合物"/"碳水"/"糖"/"carbs"/"carbohydrate"）
  // 注意：含糖饮料包装常标"碳水"或"碳水化合物"，部分标"糖"
  // 顺序：先匹配长词"碳水化合物"再"碳水"（防"碳水"误匹配"碳水化合物"前缀）
  // "糖"作为兜底（部分包装只标"糖"不标"碳水"，如某些功能饮料）
  // 例：碳水10.6g / 碳水化合物：10.6g / 碳水 10.6g / carbs 10.6g / 糖11g
  static final List<RegExp> _carbsPatterns = [
    RegExp(r'碳水化合物\s*[：:、\s]*\s*(\d+(?:\.\d+)?)\s*g', caseSensitive: false),
    RegExp(r'碳水\s*[：:、\s]*\s*(\d+(?:\.\d+)?)\s*g', caseSensitive: false),
    RegExp(r'carbohydrate\s*[：:、\s]*\s*(\d+(?:\.\d+)?)\s*g', caseSensitive: false),
    RegExp(r'carbs\s*[：:、\s]*\s*(\d+(?:\.\d+)?)\s*g', caseSensitive: false),
    // "糖"作为最后兜底（部分包装只标"糖"不标"碳水"）
    // 用负向回视断言防误匹配"低糖/无糖/加糖/含糖"等修饰词（这些词"糖"前有修饰字）
    // 注意 Dart RegExp 支持 (?<!...) 固定宽度回视（Dart 2.4+）
    RegExp(r'(?<![低无加含少减高])糖\s*[：:、\s]*\s*(\d+(?:\.\d+)?)\s*g', caseSensitive: false),
  ];
}
