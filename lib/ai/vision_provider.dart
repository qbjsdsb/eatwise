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
  });

  /// 是否多菜（additionalDishes 非空）
  bool get isMultiDish => additionalDishes.isNotEmpty;

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
    // 递归但只一层：子菜的 additionalDishes 强制为空（fromJson 传空 json 自然为空）
    final additional = ((json['additional_dishes'] as List?) ?? const [])
        .map((e) => VisionRecognitionResult.fromJson(
              e as Map<String, dynamic>,
              promptVersion,
            ))
        .toList();
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
