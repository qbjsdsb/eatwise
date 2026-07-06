import 'package_nutrition_ocr_parser.dart';

/// 视觉大模型识别结果
class VisionRecognitionResult {
  final String dishName;
  final String brand; // v1.1：品牌名（可口可乐/乐事等，无品牌为空串）
  final double estimatedWeightGLow;
  final double estimatedWeightGMid;
  final double estimatedWeightGHigh;
  final List<FoodComponent> foodComponents;
  final String cookingMethod; // steam/boil/cold/toss/roast/stir-fry/pan-fry/deep-fry/braise
  final bool isSingleItem;
  final double confidence;
  final String promptVersion;
  // v1.2：一桌多菜批量识别时，主菜之外的其余菜品。
  // 单菜时为空数组；多菜时每个元素是独立的识别结果（additionalDishes 强制为空，不嵌套）。
  final List<VisionRecognitionResult> additionalDishes;
  // v1.3：同物多份（解决拍两罐可乐只识别一罐的问题）
  // quantity 数量（默认 1），unit 单位（罐/瓶/个/份...），perUnitG 单份克数
  // estimatedWeightGMid 应 = perUnitG * quantity（AI 总重量）
  final int quantity;
  final String unit;
  final double perUnitG;
  // v1.4：AI 整菜营养估算（按 mid 份量），用于库未命中时的兜底。
  // 旧 prompt(v1.0-v1.3) 返回无此字段 → null，走原有"未命中转手动"流程。
  final double? estimatedCalories;
  final double? estimatedProteinG;
  final double? estimatedFatG;
  final double? estimatedCarbsG;
  // v1.6：重量来源标记（批次 2 包装容量优先）
  // package_label=读取包装标注净含量（最准），ai_estimate=AI 视觉估算
  // 旧 prompt(v1.0-v1.5) 无此字段 → 默认 ai_estimate
  final String weightSource;
  // v1.7：食物类别（建议 3 密度表换算用）
  // water/carbonated/juice/milk/cream/oil/honey/sauce/alcohol/beer/wine/yogurt/soup/solid
  // 包装液体食品（weight_source=package_label）按此类别查密度表把 ml 换算成真实克数
  // 旧 prompt(v1.0-v1.6) 无此字段 → 默认 solid（不换算）
  final String foodCategory;
  // v1.9：CoT 推理过程（营养师诊断视角）
  // 描述怎么识别的、读了哪些包装信息、怎么换算的、隐藏热量如何估算
  // 旧 prompt(v1.0-v1.8) 无此字段 → null
  // 下游解析时忽略此字段，但用户能在反馈页看到推理过程（错了能精准纠正）
  final String? reasoning;
  // v1.9：包装营养表 OCR 路径（包装食品精确换算用）
  // 包装食品读营养成分表后按比例换算，避免凭印象估算
  // 6 个字段全部 null/空/0 表示无包装或读不到（走 ai_estimate 路径）
  // package_nutrition_table_ocr：营养成分表原文（含数字+单位），便于后端核对
  final String packageNutritionTableOcr;
  // package_serving_g：包装标称每份克数（如 10.5）
  // package_serving_kj：包装标称每份能量千焦（如 170）
  // package_serving_kcal：包装标称每份能量千卡（包装只标 kJ 时为 null 由后端换算）
  final double? packageServingG;
  final double? packageServingKj;
  final double? packageServingKcal;
  // v1.10：包装标称每份的蛋白/脂肪/碳水克数（AI 可选填，含糖饮料必标）
  // 优先级：包装字段 > OCR 正则提取 > AI 估算反算
  // 含糖饮料（菊花茶/冰红茶/可乐等）碳水必标，AI 漏填时后端从 OCR 原文兜底
  final double? packageServingProteinG;
  final double? packageServingFatG;
  final double? packageServingCarbsG;
  // package_total_g：整包装净含量克数（如 57.6）
  // package_servings_per_pack：每包装份数（如 8）
  final double? packageTotalG;
  final double? packageServingsPerPack;
  // v2 重构：物理约束警告（transient，不参与 JSON 序列化）
  // PostProcessor 调 validator 后设置，UI 在 reasoning 卡片下方显示警告横幅。
  // 默认空表示无警告（合法自洽结果）。
  final List<String> warnings;

  const VisionRecognitionResult({
    required this.dishName,
    required this.estimatedWeightGLow,
    required this.estimatedWeightGMid,
    required this.estimatedWeightGHigh,
    required this.foodComponents,
    required this.cookingMethod,
    required this.isSingleItem,
    required this.confidence,
    required this.promptVersion,
    this.brand = '',
    this.additionalDishes = const [],
    this.quantity = 1,
    this.unit = '份',
    this.perUnitG = 0,
    this.estimatedCalories,
    this.estimatedProteinG,
    this.estimatedFatG,
    this.estimatedCarbsG,
    this.weightSource = 'ai_estimate',
    this.foodCategory = 'solid',
    this.reasoning,
    this.packageNutritionTableOcr = '',
    this.packageServingG,
    this.packageServingKj,
    this.packageServingKcal,
    this.packageServingProteinG,
    this.packageServingFatG,
    this.packageServingCarbsG,
    this.packageTotalG,
    this.packageServingsPerPack,
    this.warnings = const [],
  });

  /// 是否多菜（additionalDishes 非空）
  bool get isMultiDish => additionalDishes.isNotEmpty;

  /// 是否多份（quantity > 1）
  bool get isMultiQuantity => quantity > 1;

  /// v1.9：是否有包装营养表数据（用于 LLM-first 优先路径判断）
  /// M5 修复：与 computePackageNutritionPer100g 前置条件一致——
  /// 需同时满足 packageServingG>0（per100g 换算分母）和 kj/kcal>0（能量来源），
  /// 否则调用方误以为有包装数据但 computePackageNutritionPer100g 返回 null 致换算失败
  bool get hasPackageNutrition =>
      (packageServingG != null && packageServingG! > 0) &&
      ((packageServingKj != null && packageServingKj! > 0) ||
          (packageServingKcal != null && packageServingKcal! > 0));

  /// v1.9/v1.10：基于包装营养成分表换算 per100g 营养值
  ///
  /// 调用前必须先检查 [hasPackageNutrition] 为 true。
  ///
  /// 换算规则（与 prompts.dart v1.9 规则 10 / v1.10 修正一致）：
  /// - 单份 kcal：优先 packageServingKcal；为 0/null 时用 packageServingKj ÷ 4.184
  /// - per100g kcal = 单份 kcal × 100 ÷ packageServingG
  /// - 蛋白/脂肪/碳水 per100g 三层优先级（v1.10 修复碳水缺失问题）：
  ///   1. 包装字段 packageServingProteinG/FatG/CarbsG（AI 显式填，最可靠）
  ///   2. OCR 正则提取（AI 漏填包装字段时从 packageNutritionTableOcr 兜底）
  ///   3. AI 估算 estimatedProteinG/FatG/CarbsG 反算（最弱，AI 可能漏填致 0）
  ///
  /// 返回 (calories, protein, fat, carbs) per100g。
  /// 无法换算（packageServingG 为 0 或所有 serving_* 为 0）时返回 null，调用方走 AI 估算路径。
  (double, double, double, double)? computePackageNutritionPer100g({
    double? estimatedProteinG,
    double? estimatedFatG,
    double? estimatedCarbsG,
  }) {
    final servingG = packageServingG ?? 0;
    if (servingG <= 0) return null;

    // 单份 kcal：优先 kcal 字段，为 0 时用 kJ ÷ 4.184
    double servingKcal = packageServingKcal ?? 0;
    if (servingKcal <= 0) {
      final kj = packageServingKj ?? 0;
      if (kj <= 0) return null;
      servingKcal = kj / 4.184;
    }

    final per100Calories = servingKcal * 100 / servingG;

    // v1.10：宏量营养素 per100g 三层优先级
    // 第 1 层：包装字段（AI 显式填 package_serving_protein_g 等，最可靠）
    // 第 2 层：OCR 正则提取（AI 漏填包装字段时从 package_nutrition_table_ocr 兜底）
    // 第 3 层：AI 估算反算（最弱，AI 可能漏填致 0，但比无值好）
    // 不再用"包装通常不标碳水"的错误假设（含糖饮料碳水必标）
    final ocrParsed = PackageNutritionOcrParser.parse(packageNutritionTableOcr);

    // 蛋白质 per100g
    final double per100Protein;
    if (packageServingProteinG != null && packageServingProteinG! >= 0) {
      per100Protein = packageServingProteinG! * 100 / servingG;
    } else if (ocrParsed.proteinG != null) {
      per100Protein = ocrParsed.proteinG! * 100 / servingG;
    } else {
      final mid = estimatedWeightGMid;
      final per100Ratio = mid > 0 ? 100.0 / mid : 0.0;
      per100Protein = (estimatedProteinG ?? 0) * per100Ratio;
    }

    // 脂肪 per100g
    final double per100Fat;
    if (packageServingFatG != null && packageServingFatG! >= 0) {
      per100Fat = packageServingFatG! * 100 / servingG;
    } else if (ocrParsed.fatG != null) {
      per100Fat = ocrParsed.fatG! * 100 / servingG;
    } else {
      final mid = estimatedWeightGMid;
      final per100Ratio = mid > 0 ? 100.0 / mid : 0.0;
      per100Fat = (estimatedFatG ?? 0) * per100Ratio;
    }

    // 碳水 per100g（v1.10 关键修复：含糖饮料碳水必标，不再默认 0）
    final double per100Carbs;
    if (packageServingCarbsG != null && packageServingCarbsG! >= 0) {
      per100Carbs = packageServingCarbsG! * 100 / servingG;
    } else if (ocrParsed.carbsG != null) {
      per100Carbs = ocrParsed.carbsG! * 100 / servingG;
    } else {
      final mid = estimatedWeightGMid;
      final per100Ratio = mid > 0 ? 100.0 / mid : 0.0;
      per100Carbs = (estimatedCarbsG ?? 0) * per100Ratio;
    }

    return (per100Calories, per100Protein, per100Fat, per100Carbs);
  }

  /// 复制并覆盖部分字段
  /// - dishName：改菜名重试后透传新菜名给校准页
  /// - estimatedCalories：营养素自洽校验失败时用修正值覆盖（批次 1）
  /// - estimatedProteinG/FatG/CarbsG：v1.10 宏量反推修正覆盖
  /// - foodComponents：组分份量交叉验证失败时用缩放后组分覆盖（建议 7）
  /// - perUnitG/estimatedWeightG*/foodCategory：建议 3 密度换算后覆盖
  /// - reasoning：v1.9 CoT 推理过程透传（避免 PostProcessor 重建时丢失）
  VisionRecognitionResult copyWith({
    String? dishName,
    double? estimatedCalories,
    double? estimatedProteinG,
    double? estimatedFatG,
    double? estimatedCarbsG,
    List<FoodComponent>? foodComponents,
    double? perUnitG,
    double? estimatedWeightGLow,
    double? estimatedWeightGMid,
    double? estimatedWeightGHigh,
    String? foodCategory,
    String? reasoning,
    // M6 修复：补全 v1.9/v1.10 新增 9 个 package_* 字段，允许调用方修改
    String? packageNutritionTableOcr,
    double? packageServingG,
    double? packageServingKj,
    double? packageServingKcal,
    double? packageServingProteinG,
    double? packageServingFatG,
    double? packageServingCarbsG,
    double? packageTotalG,
    double? packageServingsPerPack,
    // v2 重构：warnings 透传（PostProcessor → UI）
    List<String>? warnings,
    // additionalDishes 透传（密度换算/校验后重建）
    List<VisionRecognitionResult>? additionalDishes,
  }) {
    return VisionRecognitionResult(
      dishName: dishName ?? this.dishName,
      brand: brand,
      estimatedWeightGLow: estimatedWeightGLow ?? this.estimatedWeightGLow,
      estimatedWeightGMid: estimatedWeightGMid ?? this.estimatedWeightGMid,
      estimatedWeightGHigh: estimatedWeightGHigh ?? this.estimatedWeightGHigh,
      foodComponents: foodComponents ?? this.foodComponents,
      cookingMethod: cookingMethod,
      isSingleItem: isSingleItem,
      confidence: confidence,
      promptVersion: promptVersion,
      additionalDishes: additionalDishes ?? this.additionalDishes,
      quantity: quantity,
      unit: unit,
      perUnitG: perUnitG ?? this.perUnitG,
      estimatedCalories: estimatedCalories ?? this.estimatedCalories,
      estimatedProteinG: estimatedProteinG ?? this.estimatedProteinG,
      estimatedFatG: estimatedFatG ?? this.estimatedFatG,
      estimatedCarbsG: estimatedCarbsG ?? this.estimatedCarbsG,
      weightSource: weightSource,
      foodCategory: foodCategory ?? this.foodCategory,
      reasoning: reasoning ?? this.reasoning,
      packageNutritionTableOcr: packageNutritionTableOcr ?? this.packageNutritionTableOcr,
      packageServingG: packageServingG ?? this.packageServingG,
      packageServingKj: packageServingKj ?? this.packageServingKj,
      packageServingKcal: packageServingKcal ?? this.packageServingKcal,
      packageServingProteinG: packageServingProteinG ?? this.packageServingProteinG,
      packageServingFatG: packageServingFatG ?? this.packageServingFatG,
      packageServingCarbsG: packageServingCarbsG ?? this.packageServingCarbsG,
      packageTotalG: packageTotalG ?? this.packageTotalG,
      packageServingsPerPack: packageServingsPerPack ?? this.packageServingsPerPack,
      warnings: warnings ?? this.warnings,
    );
  }

  factory VisionRecognitionResult.fromJson(Map<String, dynamic> json, String promptVersion) {
    final mid = (json['estimated_weight_g_mid'] as num).toDouble();
    // Low/High 缺失时回退 Mid（设计 5.6，避免区间显示异常）
    final low = json['estimated_weight_g_low'] != null
        ? (json['estimated_weight_g_low'] as num).toDouble()
        : mid;
    final high = json['estimated_weight_g_high'] != null
        ? (json['estimated_weight_g_high'] as num).toDouble()
        : mid;
    // v1.2：解析 additional_dishes（单菜/旧响应无此字段 → 空数组）
    // 完全递归解析（模型若违反 prompt 返回多层嵌套也会解析），但 controller 只处理第一层，
    // 深层 additionalDishes 会被静默丢弃（prompt 规则要求子菜 additional_dishes 为空）
    final additional = ((json['additional_dishes'] as List?) ?? const [])
        .map((e) => VisionRecognitionResult.fromJson(
              e as Map<String, dynamic>,
              promptVersion,
            ))
        .toList();
    // v1.3：解析 quantity/per_unit_g/unit（旧响应无此字段 → 默认值，向后兼容）
    // quantity 清洗到 [1,20]：防 0/负致 mid/0=Infinity 或 NaN 崩溃，防 >20 步进器难用
    final quantityRaw = (json['quantity'] as num?)?.toInt() ?? 1;
    final quantity = quantityRaw < 1 ? 1 : (quantityRaw > 20 ? 20 : quantityRaw);
    var perUnitG = (json['per_unit_g'] as num?)?.toDouble() ??
        (quantity > 0 ? mid / quantity : 0); // 旧响应无 per_unit_g 时反推
    // NaN/Infinity/负数兜底（mid/0 在 Dart 产生 Infinity/NaN，会致 Slider value 崩溃）
    if (perUnitG.isNaN || perUnitG.isInfinite || perUnitG < 0) perUnitG = 0;
    final unitStr = (json['unit'] as String?) ?? '';
    final unit = unitStr.isNotEmpty ? unitStr : '份';
    return VisionRecognitionResult(
      dishName: json['dish_name'] as String,
      // brand 可选（v1.1+），旧模型/v1.0 响应无此字段 → 空串
      brand: (json['brand'] as String?) ?? '',
      estimatedWeightGLow: low,
      estimatedWeightGMid: mid,
      estimatedWeightGHigh: high,
      foodComponents: ((json['food_components'] as List?) ?? [])
          .map((e) => FoodComponent.fromJson(e as Map<String, dynamic>))
          .toList(),
      cookingMethod: (json['cooking_method'] as String?) ?? 'raw',
      isSingleItem: (json['is_single_item'] as bool?) ?? true,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      promptVersion: promptVersion,
      additionalDishes: additional,
      quantity: quantity,
      unit: unit,
      perUnitG: perUnitG,
      // v1.4 营养字段缺失时为 null（旧 prompt 兼容）
      estimatedCalories: (json['estimated_calories'] as num?)?.toDouble(),
      estimatedProteinG: (json['estimated_protein_g'] as num?)?.toDouble(),
      estimatedFatG: (json['estimated_fat_g'] as num?)?.toDouble(),
      estimatedCarbsG: (json['estimated_carbs_g'] as num?)?.toDouble(),
      // v1.6 weight_source 缺失时默认 ai_estimate（旧 prompt 兼容）
      // 非法值兜底为 ai_estimate，避免下游 switch/if 链漏分支
      weightSource: (json['weight_source'] as String?) == 'package_label'
          ? 'package_label'
          : 'ai_estimate',
      // v1.7 food_category 缺失时默认 solid（旧 prompt 兼容，不换算密度）
      // 非法值兜底为 solid
      foodCategory: (json['food_category'] as String?)?.isNotEmpty == true
          ? json['food_category'] as String
          : 'solid',
      // v1.9 reasoning 缺失时为 null（旧 prompt 兼容）
      // 模型未遵循 prompt 不写 reasoning 也会变 null，下游忽略
      reasoning: (json['reasoning'] as String?)?.isNotEmpty == true
          ? json['reasoning'] as String
          : null,
      // v1.9 包装营养表 OCR 路径，缺失时为空串/null（旧 prompt 兼容）
      packageNutritionTableOcr:
          (json['package_nutrition_table_ocr'] as String?) ?? '',
      packageServingG: (json['package_serving_g'] as num?)?.toDouble(),
      packageServingKj: (json['package_serving_kj'] as num?)?.toDouble(),
      packageServingKcal: (json['package_serving_kcal'] as num?)?.toDouble(),
      // v1.10：包装每份宏量营养素（AI 可选填，含糖饮料必填）
      packageServingProteinG:
          (json['package_serving_protein_g'] as num?)?.toDouble(),
      packageServingFatG:
          (json['package_serving_fat_g'] as num?)?.toDouble(),
      packageServingCarbsG:
          (json['package_serving_carbs_g'] as num?)?.toDouble(),
      packageTotalG: (json['package_total_g'] as num?)?.toDouble(),
      packageServingsPerPack:
          (json['package_servings_per_pack'] as num?)?.toDouble(),
    );
  }
}

class FoodComponent {
  final String name;
  final double estimatedG;

  const FoodComponent({required this.name, required this.estimatedG});

  factory FoodComponent.fromJson(Map<String, dynamic> json) {
    return FoodComponent(
      name: json['name'] as String,
      estimatedG: (json['estimated_g'] as num).toDouble(),
    );
  }
}

/// 视觉大模型抽象接口
abstract class VisionProvider {
  String get name;
  String get promptVersion;

  /// 识别图片，返回结构化结果
  /// [imageBase64] base64 编码的 JPEG 图片
  Future<VisionRecognitionResult> recognize(String imageBase64);
}

/// 识别异常
class VisionRecognitionException implements Exception {
  final String reason;
  final bool retryable; // malformed=false(带错误信息重发), timeout=true, rate_limit=true
  final Duration? retryAfter; // 429 的 Retry-After 等待时长
  final bool isRefusal; // T39 内容安全过滤标记

  VisionRecognitionException(
    this.reason, {
    this.retryable = false,
    this.retryAfter,
    this.isRefusal = false,
  });

  @override
  String toString() => 'VisionRecognitionException: $reason';
}
