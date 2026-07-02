// test/features/monthly_cost_test.dart
// T43 月度识别计数存储测试
//
// 注意：flutter_secure_storage 在沙箱无平台通道，用 setMockInitialValues
// 注入内存平台实现（flutter_secure_storage 10.3.1 自带 TestFlutterSecureStoragePlatform）。
import 'package:eatwise/core/config/secure_config_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SecureConfigStore store;

  setUp(() {
    // 沙箱无平台通道，注入内存 mock 平台实现（计划预案：实施时核实）
    FlutterSecureStorage.setMockInitialValues({});
    store = SecureConfigStore();
  });

  test('月度计数初始为 0', () async {
    final count = await store.getMonthlyCount(2026, 7);
    expect(count, 0);
  });

  test('increment 后计数 +1', () async {
    await store.incrementMonthlyCount(2026, 7);
    expect(await store.getMonthlyCount(2026, 7), 1);
    await store.incrementMonthlyCount(2026, 7);
    expect(await store.getMonthlyCount(2026, 7), 2);
  });

  test('不同月份独立计数', () async {
    await store.incrementMonthlyCount(2026, 7);
    await store.incrementMonthlyCount(2026, 7);
    await store.incrementMonthlyCount(2026, 6);
    expect(await store.getMonthlyCount(2026, 7), 2);
    expect(await store.getMonthlyCount(2026, 6), 1);
  });
}
