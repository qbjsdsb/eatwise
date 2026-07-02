import 'package:eatwise/ai/off_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
      // 330 ml 不含 g，默认 100
      expect(r.defaultServingG, 100);
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
}
