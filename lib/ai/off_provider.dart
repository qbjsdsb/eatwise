import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Open Food Facts 云查结果（per 100g 营养素，已转 kcal）
class OffResult {
  final String name;
  final String brand;
  final double caloriesPer100g; // kcal（OFF 的 energy-kcal_100g 或 kJ/4.184）
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;
  final double defaultServingG;

  const OffResult({
    required this.name,
    required this.brand,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
    required this.defaultServingG,
  });
}

/// Open Food Facts 云查 provider
///
/// 作用：本地食物库 miss 时的兜底数据源（百万级品牌食品 + 条码数据库）。
/// 隐私：只传菜名文本，不传图片、不传用户身份。
/// 离线降级：[isOnline] 返回 false 时直接返回 null，不发起请求。
/// 健壮性：任何异常（超时/解析失败/网络错误）都返回 null，绝不阻塞主流程。
///
/// 命中后由 [NutritionLookup] 落库（source='off'），下次直接查库命中，避免重复云查。
class OffProvider {
  final http.Client _client;
  final Future<bool> Function() _isOnline;

  static const _timeout = Duration(seconds: 10);
  static const _baseUrl = 'https://world.openfoodfacts.org';

  /// [client] 可选（测试注入 MockClient）；[isOnline] 必填（生产传 connectivity 检查）
  OffProvider({http.Client? client, required Future<bool> Function() isOnline})
      : _client = client ?? http.Client(),
        _isOnline = isOnline;

  /// 云查 OFF。离线/超时/无命中/解析失败均返回 null。
  ///
  /// P2-1 brand 组合查询：[brand] 非空时先查 "brand+name"（如"雪花 啤酒"），
  /// OFF 有品牌产品名，命中率提升。未命中再回退查 name。
  Future<OffResult?> lookup(String dishName, {String brand = ''}) async {
    if (dishName.trim().isEmpty) return null;
    try {
      if (!await _isOnline()) return null;

      // P2-1：brand 非空时先查组合（brand+name），提升品牌包装食品命中率
      final cleanBrand = brand.trim();
      if (cleanBrand.isNotEmpty) {
        final combined = '$cleanBrand $dishName';
        final hit = await _searchOff(combined);
        if (hit != null) return hit;
      }
      // 回退查 name（brand miss 或 brand 为空）
      return await _searchOff(dishName);
    } catch (_) {
      // 任何异常都不阻塞：返回 null，调用方走手动录入
      return null;
    }
  }

  /// OFF 搜索内部实现（单次查询）
  Future<OffResult?> _searchOff(String terms) async {
    final url = Uri.parse('$_baseUrl/cgi/search.pl').replace(
      queryParameters: {
        'search_terms': terms,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': '5',
      },
    );
    // OFF 要求 User-Agent 标识应用（否则可能被限流）
    // P1-1: 版本号从 PackageInfo 动态读取（替代硬编码 0.4.0，pubspec bump 后自动同步）
    final info = await PackageInfo.fromPlatform();
    final ua =
        'EatWise/${info.version} (Android; food-matching) contact@eatwise.app';
    final resp = await _client
        .get(url, headers: {'User-Agent': ua})
        .timeout(_timeout);
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final count = json['count'] as int? ?? 0;
    if (count == 0) return null;
    final products = json['products'] as List? ?? const [];
    // 遍历前 5 个结果，取第一个营养素齐全且合理的
    for (final p in products) {
      if (p is! Map<String, dynamic>) continue;
      final result = _parseProduct(p);
      if (result != null) return result;
    }
    return null;
  }

  /// 解析单个产品。4 项营养素必须齐全且在合理区间，否则跳过。
  @visibleForTesting
  OffResult? parseProductForTest(Map<String, dynamic> p) => _parseProduct(p);

  OffResult? _parseProduct(Map<String, dynamic> p) {
    final nutriments = p['nutriments'] as Map<String, dynamic>? ?? const {};

    // 能量：优先 energy-kcal_100g，否则 energy_100g(kJ)/4.184
    double? energy = _parseDouble(nutriments, 'energy-kcal_100g');
    if (energy == null) {
      final kj = _parseDouble(nutriments, 'energy_100g');
      if (kj != null) energy = kj / 4.184;
    }
    final protein = _parseDouble(nutriments, 'proteins_100g');
    final fat = _parseDouble(nutriments, 'fat_100g');
    final carbs = _parseDouble(nutriments, 'carbohydrates_100g');
    if (energy == null || protein == null || fat == null || carbs == null) {
      return null;
    }
    // 合理性校验（防异常值污染本地库）
    if (energy < 0 || energy > 3000) return null;
    if (protein < 0 || protein > 100) return null;
    if (fat < 0 || fat > 100) return null;
    if (carbs < 0 || carbs > 100) return null;

    final name = (p['product_name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null; // 无名的产品不可用
    final brand = (p['brands'] as String?)?.trim() ?? '';

    // serving_size 解析（如 "330 ml" / "100 g"），默认 100g
    // P1-2: 扩展支持 ml 单位，饮料按密度 1.0 兜底为 g（避免按 100g 算的 5 倍偏差）
    double defaultServingG = 100;
    final serving = (p['serving_size'] as String?)?.trim();
    if (serving != null && serving.isNotEmpty) {
      final m = RegExp(r'(\d+(?:\.\d+)?)\s*(g|ml)', caseSensitive: false)
          .firstMatch(serving);
      if (m != null) {
        final v = double.tryParse(m.group(1)!);
        // ml 按密度 1.0 兜底为 g（饮料密度≈1），g 直接用数值
        if (v != null && v > 0 && v < 5000) defaultServingG = v;
      }
    }

    return OffResult(
      name: name,
      brand: brand,
      caloriesPer100g: energy,
      proteinPer100g: protein,
      fatPer100g: fat,
      carbsPer100g: carbs,
      defaultServingG: defaultServingG,
    );
  }

  double? _parseDouble(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
