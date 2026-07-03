// test/core/secure_config_store_test.dart
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

  test('getQwenApiKey 返回存储的值', () async {
    when(
      () => mockStorage.read(key: 'qwen_api_key'),
    ).thenAnswer((_) async => 'sk-test');
    expect(await store.getQwenApiKey(), 'sk-test');
  });

  test('setQwenApiKey 空值时删除而非写入空串', () async {
    when(
      () => mockStorage.delete(key: 'qwen_api_key'),
    ).thenAnswer((_) async {});
    await store.setQwenApiKey('');
    verify(() => mockStorage.delete(key: 'qwen_api_key')).called(1);
    verifyNever(
      () => mockStorage.write(
        key: 'qwen_api_key',
        value: any(named: 'value'),
      ),
    );
  });

  test('getSentryEnabled 默认 false（未设置时）', () async {
    when(
      () => mockStorage.read(key: 'sentry_enabled'),
    ).thenAnswer((_) async => null);
    expect(await store.getSentryEnabled(), false);
  });

  test('getTdeeAutoCalib 默认 true（未设置时返回 true）', () async {
    when(
      () => mockStorage.read(key: 'tdee_auto_calib'),
    ).thenAnswer((_) async => null);
    expect(await store.getTdeeAutoCalib(), true);
  });

  test('setSentryEnabled(true) 写入 "1"', () async {
    when(
      () => mockStorage.write(key: 'sentry_enabled', value: '1'),
    ).thenAnswer((_) async {});
    await store.setSentryEnabled(true);
    verify(
      () => mockStorage.write(key: 'sentry_enabled', value: '1'),
    ).called(1);
  });
}
