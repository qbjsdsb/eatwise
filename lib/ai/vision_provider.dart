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
  // package_total_g：整包装净含量克数（如 57.6）
  // package_servings_per_pack：每包装份数（如 8）
  final double? packageTotalG;
  final double? packageServingsPerPack;

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
    this.packageTotalG,
    this.packageServingsPerPack,
  });

  /// 是否多菜（additionalDishes 非空）
  bool get isMultiDish => additionalDishes.isNotEmpty;

  /// 是否多份（quantity > 1）
  bool get isMultiQuantity => quantity > 1;

  /// v1.9：是否有包装营养表数据（用于 LLM-first 优先路径判断）
  /// 任一 package_serving_* 字段非空非 0 即视为有包装数据
  bool get hasPackageNutrition =>
      (packageServingG != null && packageServingG! > 0) ||
      (packageServingKj != null && packageServingKj! > 0) ||
      (packageServingKcal != null && packageServingKcal! > 0);

  /// 复制并覆盖部分字段
  /// - dishName：改菜名重试后透传新菜名给校准页
  /// - estimatedCalories：营养素自洽校验失败时用修正值覆盖（批次 1）
  /// - foodComponents：组分份量交叉验证失败时用缩放后组分覆盖（建议 7）
  /// - perUnitG/estimatedWeightG*/foodCategory：建议 3 密度换算后覆盖
  /// - reasoning：v1.9 CoT 推理过程透传（避免 PostProcessor 重建时丢失）
  VisionRecognitionResult copyWith({
    String? dishName,
    double? estimatedCalories,
    List<FoodComponent>? foodComponents,
    double? perUnitG,
    double? estimatedWeightGLow,
    double? estimatedWeightGMid,
    double? estimatedWeightGHigh,
    String? foodCategory,
    String? reasoning,
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
      additionalDishes: additionalDishes,
      quantity: quantity,
      unit: unit,
      perUnitG: perUnitG ?? this.perUnitG,
      estimatedCalories: estimatedCalories ?? this.estimatedCalories,
      estimatedProteinG: estimatedProteinG,
      estimatedFatG: estimatedFatG,
      estimatedCarbsG: estimatedCarbsG,
      weightSource: weightSource,
      foodCategory: foodCategory ?? this.foodCategory,
      reasoning: reasoning ?? this.reasoning,
      packageNutritionTableOcr: packageNutritionTableOcr,
      packageServingG: packageServingG,
      packageServingKj: packageServingKj,
      packageServingKcal: packageServingKcal,
      packageTotalG: packageTotalG,
      packageServingsPerPack: packageServingsPerPack,
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
      cookingMethod: json['cooking_method'] as String,
      isSingleItem: json['is_single_item'] as bool,
      confidence: (json['confidence'] as num).toDouble(),
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
