import 'package:eatwise/ai/off_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  group('OffProvider 解析逻辑', () {
    late OffProvider provider;
    setUp(() {
      provider = OffProvider(isOnline: () async => true);
    });

    test('完整产品（energy-kcal_100g）→ 解析成功', () {
      final r = provider.parseProductForTest({
        'product_name': 'Coca Cola',
        'brands': 'Coca-Cola',
        'nutriments': {
          'energy-kcal_100g': 42,
          'proteins_100g': 0,
          'fat_100g': 0,
          'carbohydrates_100g': 10.6,
        },
        'serving_size': '330 ml',
      });
      expect(r, isNotNull);
      expect(r!.name, 'Coca Cola');
      expect(r.brand, 'Coca-Cola');
      expect(r.caloriesPer100g, 42);
      expect(r.proteinPer100g, 0);
      expect(r.fatPer100g, 0);
      expect(r.carbsPer100g, 10.6);
      // P1-2: 330 ml 按密度 1.0 兜底为 330g（饮料不再按 100g 算 5 倍偏差）
      expect(r.defaultServingG, 330);
    });

    test('完整产品（energy_100g kJ）→ 转 kcal 成功', () {
      final r = provider.parseProductForTest({
        'product_name': 'Sprite',
        'nutriments': {
          'energy_100g': 176, // kJ
          'proteins_100g': 0,
          'fat_100g': 0,
          'carbohydrates_100g': 10.5,
        },
      });
      expect(r, isNotNull);
      // 176 / 4.184 ≈ 42.07
      expect(r!.caloriesPer100g, closeTo(42.07, 0.1));
    });

    test('kcal 字段优先于 kJ 字段', () {
      final r = provider.parseProductForTest({
        'product_name': 'Test',
        'nutriments': {
          'energy-kcal_100g': 50,
          'energy_100g': 1000, // 应被忽略
          'proteins_100g': 1,
          'fat_100g': 1,
          'carbohydrates_100g': 10,
        },
      });
      expect(r!.caloriesPer100g, 50);
    });

    test('缺蛋白质 → 返回 null', () {
      final r = provider.parseProductForTest({
        'product_name': 'Incomplete',
        'nutriments': {
          'energy-kcal_100g': 100,
          'fat_100g': 1,
          'carbohydrates_100g': 10,
        },
      });
      expect(r, isNull);
    });

    test('能量超 3000 → 返回 null（防异常值）', () {
      final r = provider.parseProductForTest({
        'product_name': 'Bad',
        'nutriments': {
          'energy-kcal_100g': 5000,
          'proteins_100g': 1,
          'fat_100g': 1,
          'carbohydrates_100g': 10,
        },
      });
      expect(r, isNull);
    });

    test('蛋白质超 100 → 返回 null（防异常值）', () {
      final r = provider.parseProductForTest({
        'product_name': 'Bad',
        'nutriments': {
          'energy-kcal_100g': 100,
          'proteins_100g': 150,
          'fat_100g': 1,
          'carbohydrates_100g': 10,
        },
      });
      expect(r, isNull);
    });

    test('能量为负 → 返回 null', () {
      final r = provider.parseProductForTest({
        'product_name': 'Bad',
        'nutriments': {
          'energy-kcal_100g': -10,
          'proteins_100g': 1,
          'fat_100g': 1,
          'carbohydrates_100g': 10,
        },
      });
      expect(r, isNull);
    });

    test('无 product_name → 返回 null', () {
      final r = provider.parseProductForTest({
        'nutriments': {
          'energy-kcal_100g': 42,
          'proteins_100g': 0,
          'fat_100g': 0,
          'carbohydrates_100g': 10,
        },
      });
      expect(r, isNull);
    });

    test('product_name 为空字符串 → 返回 null', () {
      final r = provider.parseProductForTest({
        'product_name': '   ',
        'nutriments': {
          'energy-kcal_100g': 42,
          'proteins_100g': 0,
          'fat_100g': 0,
          'carbohydrates_100g': 10,
        },
      });
      expect(r, isNull);
    });

    test('serving_size "100 g" → defaultServingG=100', () {
      final r = provider.parseProductForTest({
        'product_name': 'X',
        'nutriments': {
          'energy-kcal_100g': 42,
          'proteins_100g': 0,
          'fat_100g': 0,
          'carbohydrates_100g': 10,
        },
        'serving_size': '100 g',
      });
      expect(r!.defaultServingG, 100);
    });

    test('serving_size "50.5 g" → defaultServingG=50.5', () {
      final r = provider.parseProductForTest({
        'product_name': 'X',
        'nutriments': {
          'energy-kcal_100g': 42,
          'proteins_100g': 0,
          'fat_100g': 0,
          'carbohydrates_100g': 10,
        },
        'serving_size': '50.5 g',
      });
      expect(r!.defaultServingG, 50.5);
    });

    // P1-2: serving_size 支持 ml 单位（饮料按密度 1.0 兜底为 g）
    test('serving_size "330 ml" → defaultServingG=330（ml 按密度 1.0 兜底）', () {
      final r = provider.parseProductForTest({
        'product_name': 'Coca Cola',
        'nutriments': {
          'energy-kcal_100g': 42,
          'proteins_100g': 0,
          'fat_100g': 0,
          'carbohydrates_100g': 10.6,
        },
        'serving_size': '330 ml',
      });
      expect(r!.defaultServingG, 330);
    });

    test('serving_size "30 g" → defaultServingG=30（g 行为不变）', () {
      final r = provider.parseProductForTest({
        'product_name': 'X',
        'nutriments': {
          'energy-kcal_100g': 42,
          'proteins_100g': 0,
          'fat_100g': 0,
          'carbohydrates_100g': 10,
        },
        'serving_size': '30 g',
      });
      expect(r!.defaultServingG, 30);
    });

    test('serving_size 无单位（如 "1 个"）→ 回退 defaultServingG=100', () {
      final r = provider.parseProductForTest({
        'product_name': 'X',
        'nutriments': {
          'energy-kcal_100g': 42,
          'proteins_100g': 0,
          'fat_100g': 0,
          'carbohydrates_100g': 10,
        },
        'serving_size': '1 个',
      });
      expect(r!.defaultServingG, 100);
    });

    test('无 nutriments 字段 → 返回 null（不崩）', () {
      final r = provider.parseProductForTest({
        'product_name': 'X',
      });
      expect(r, isNull);
    });

    test('营养素为字符串数字 → 正确解析', () {
      final r = provider.parseProductForTest({
        'product_name': 'X',
        'nutriments': {
          'energy-kcal_100g': '42',
          'proteins_100g': '0.5',
          'fat_100g': '0',
          'carbohydrates_100g': '10.6',
        },
      });
      expect(r, isNotNull);
      expect(r!.caloriesPer100g, 42);
      expect(r.proteinPer100g, 0.5);
    });
  });

  group('OffProvider lookup 网络路径', () {
    setUp(() {
      // P1-1: _searchOff 现调用 PackageInfo.fromPlatform()，沙箱需 mock
      PackageInfo.setMockInitialValues(
        appName: '慢慢吃',
        packageName: 'com.example.eatwise',
        version: '0.18.2',
        buildNumber: '21',
        buildSignature: '',
        installerStore: null,
      );
    });

    test('离线 → 返回 null，不发起请求', () async {
      var requestMade = false;
      final client = MockClient((_) async {
        requestMade = true;
        return http.Response('{}', 200);
      });
      final provider = OffProvider(
        client: client,
        isOnline: () async => false,
      );
      final r = await provider.lookup('可口可乐');
      expect(r, isNull);
      expect(requestMade, isFalse);
    });

    test('空菜名 → 返回 null，不发起请求', () async {
      var requestMade = false;
      final client = MockClient((_) async {
        requestMade = true;
        return http.Response('{}', 200);
      });
      final provider = OffProvider(
        client: client,
        isOnline: () async => true,
      );
      final r = await provider.lookup('   ');
      expect(r, isNull);
      expect(requestMade, isFalse);
    });

    test('count=0 → 返回 null', () async {
      final client = MockClient((_) async {
        return http.Response('{"count":0,"products":[]}', 200);
      });
      final provider = OffProvider(
        client: client,
        isOnline: () async => true,
      );
      final r = await provider.lookup('不存在的食物xyz');
      expect(r, isNull);
    });

    test('命中产品 → 返回 OffResult', () async {
      final client = MockClient((request) async {
        expect(request.url.path, contains('/cgi/search.pl'));
        expect(request.url.queryParameters['search_terms'], '可乐');
        return http.Response(
          '{"count":1,"products":[{"product_name":"Cola","brands":"Coca-Cola",'
          '"nutriments":{"energy-kcal_100g":42,"proteins_100g":0,'
          '"fat_100g":0,"carbohydrates_100g":10.6}}]}',
          200,
        );
      });
      final provider = OffProvider(
        client: client,
        isOnline: () async => true,
      );
      final r = await provider.lookup('可乐');
      expect(r, isNotNull);
      expect(r!.name, 'Cola');
      expect(r.caloriesPer100g, 42);
    });

    test('第一个产品缺数据 → 取第二个', () async {
      final client = MockClient((_) async {
        return http.Response(
          '{"count":2,"products":['
          '{"product_name":"Bad","nutriments":{"energy-kcal_100g":5000}},'
          '{"product_name":"Good","nutriments":{"energy-kcal_100g":42,'
          '"proteins_100g":0,"fat_100g":0,"carbohydrates_100g":10.6}}'
          ']}',
          200,
        );
      });
      final provider = OffProvider(
        client: client,
        isOnline: () async => true,
      );
      final r = await provider.lookup('test');
      expect(r, isNotNull);
      expect(r!.name, 'Good');
    });

    test('HTTP 500 → 返回 null（不抛异常）', () async {
      final client = MockClient((_) async {
        return http.Response('Server Error', 500);
      });
      final provider = OffProvider(
        client: client,
        isOnline: () async => true,
      );
      final r = await provider.lookup('test');
      expect(r, isNull);
    });

    test('响应非 JSON → 返回 null（不抛异常）', () async {
      final client = MockClient((_) async {
        return http.Response('not json', 200);
      });
      final provider = OffProvider(
        client: client,
        isOnline: () async => true,
      );
      final r = await provider.lookup('test');
      expect(r, isNull);
    });

    test('所有产品都缺数据 → 返回 null', () async {
      final client = MockClient((_) async {
        return http.Response(
          '{"count":2,"products":['
          '{"product_name":"A","nutriments":{}},'
          '{"product_name":"B","nutriments":{"energy-kcal_100g":42}}'
          ']}',
          200,
        );
      });
      final provider = OffProvider(
        client: client,
        isOnline: () async => true,
      );
      final r = await provider.lookup('test');
      expect(r, isNull);
    });
  });

  // P1-1: OFF User-Agent 必须含实际版本号（动态读取 PackageInfo），
  // 不能硬编码 0.4.0（与 pubspec 0.18.2 脱节）。
  // 沙箱无平台通道，用 PackageInfo.setMockInitialValues 注入内存 mock。
  group('P1-1 OFF User-Agent 动态版本号', () {
    setUp(() {
      // mock 平台返回的 PackageInfo（模拟 pubspec.yaml 的 0.18.2+21）
      PackageInfo.setMockInitialValues(
        appName: '慢慢吃',
        packageName: 'com.example.eatwise',
        version: '0.18.2',
        buildNumber: '21',
        buildSignature: '',
        installerStore: null,
      );
    });

    test('User-Agent 含实际版本号 0.18.2（非硬编码 0.4.0）', () async {
      String? capturedUA;
      final client = MockClient((request) async {
        // http 包 Request.headers 键会被规范化为小写
        capturedUA = request.headers['user-agent'];
        return http.Response('{"count":0,"products":[]}', 200);
      });
      final provider = OffProvider(
        client: client,
        isOnline: () async => true,
      );
      await provider.lookup('可乐');
      expect(capturedUA, isNotNull, reason: '应发起请求并携带 User-Agent');
      expect(capturedUA, contains('0.18.2'),
          reason: 'User-Agent 应含实际版本号');
      expect(capturedUA, isNot(contains('0.4.0')),
          reason: 'User-Agent 不应含旧硬编码版本号');
    });

    test('User-Agent 格式：EatWise/{version} (Android; food-matching) contact@eatwise.app',
        () async {
      String? capturedUA;
      final client = MockClient((request) async {
        capturedUA = request.headers['user-agent'];
        return http.Response('{"count":0,"products":[]}', 200);
      });
      final provider = OffProvider(
        client: client,
        isOnline: () async => true,
      );
      await provider.lookup('可乐');
      expect(capturedUA, startsWith('EatWise/0.18.2 '));
      expect(capturedUA, contains('food-matching'));
      expect(capturedUA, contains('contact@eatwise.app'));
    });

    test('pubspec bump 后 User-Agent 自动同步（验证动态读取）', () async {
      // 模拟发版后版本号变化
      PackageInfo.setMockInitialValues(
        appName: '慢慢吃',
        packageName: 'com.example.eatwise',
        version: '0.19.0',
        buildNumber: '22',
        buildSignature: '',
        installerStore: null,
      );
      String? capturedUA;
      final client = MockClient((request) async {
        capturedUA = request.headers['user-agent'];
        return http.Response('{"count":0,"products":[]}', 200);
      });
      final provider = OffProvider(
        client: client,
        isOnline: () async => true,
      );
      await provider.lookup('可乐');
      expect(capturedUA, contains('0.19.0'),
          reason: 'pubspec bump 后 User-Agent 应自动同步，无需改代码');
    });
  });
}
