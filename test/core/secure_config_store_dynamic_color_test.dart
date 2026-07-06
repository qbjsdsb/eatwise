// test/core/secure_config_store_dynamic_color_test.dart
// SecureConfigStore.getUseDynamicColor / setUseDynamicColor 读写单测
// 注意：flutter_secure_storage 在沙箱无平台通道，用 mocktail mock FlutterSecureStorage
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:eatwise/core/config/secure_config_store.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockSecureStorage mockStorage;
  late SecureConfigStore store;

  setUp(() {
    mockStorage = _MockSecureStorage();
    store = SecureConfigStore.forTesting(mockStorage);
  });

  group('getUseDynamicColor / setUseDynamicColor', () {
    test('默认 false（key 不存在时）', () async {
      when(() => mockStorage.read(key: 'use_dynamic_color'))
          .thenAnswer((_) async => null);
      expect(await store.getUseDynamicColor(), false);
    });

    test('set(true) 后 read 回 true', () async {
      when(() => mockStorage.write(key: 'use_dynamic_color', value: '1'))
          .thenAnswer((_) async {});
      when(() => mockStorage.read(key: 'use_dynamic_color'))
          .thenAnswer((_) async => '1');
      await store.setUseDynamicColor(true);
      expect(await store.getUseDynamicColor(), true);
    });

    test('set(false) 后 read 回 false', () async {
      when(() => mockStorage.write(key: 'use_dynamic_color', value: '1'))
          .thenAnswer((_) async {});
      when(() => mockStorage.write(key: 'use_dynamic_color', value: '0'))
          .thenAnswer((_) async {});
      when(() => mockStorage.read(key: 'use_dynamic_color'))
          .thenAnswer((_) async => '0');
      await store.setUseDynamicColor(true);
      await store.setUseDynamicColor(false);
      expect(await store.getUseDynamicColor(), false);
    });

    test('存储格式为 "1"/"0" 字符串', () async {
      when(() => mockStorage.write(key: 'use_dynamic_color', value: '1'))
          .thenAnswer((_) async {});
      when(() => mockStorage.write(key: 'use_dynamic_color', value: '0'))
          .thenAnswer((_) async {});
      await store.setUseDynamicColor(true);
      verify(() => mockStorage.write(key: 'use_dynamic_color', value: '1'))
          .called(1);
      await store.setUseDynamicColor(false);
      verify(() => mockStorage.write(key: 'use_dynamic_color', value: '0'))
          .called(1);
    });
  });

  group('getThemeSeed 回归测试', () {
    test('默认 0xFF6750A4', () async {
      when(() => mockStorage.read(key: 'theme_seed'))
          .thenAnswer((_) async => null);
      expect(await store.getThemeSeed(), 0xFF6750A4);
    });

    test('set 后 read 回', () async {
      const seed = 0xFF2E7D32;
      when(() => mockStorage.write(key: 'theme_seed', value: seed.toString()))
          .thenAnswer((_) async {});
      when(() => mockStorage.read(key: 'theme_seed'))
          .thenAnswer((_) async => seed.toString());
      await store.setThemeSeed(seed);
      expect(await store.getThemeSeed(), seed);
    });
  });
}
