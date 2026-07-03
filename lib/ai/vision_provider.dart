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
  });

  /// 是否多菜（additionalDishes 非空）
  bool get isMultiDish => additionalDishes.isNotEmpty;

  /// 是否多份（quantity > 1）
  bool get isMultiQuantity => quantity > 1;

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
