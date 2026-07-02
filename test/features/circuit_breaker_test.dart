// test/features/circuit_breaker_test.dart
import 'package:eatwise/features/recognize/circuit_breaker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, String> storage;
  late CircuitBreaker breaker;
  // 可注入的时钟，从固定起点推进
  late DateTime fakeNow;

  setUp(() {
    storage = {};
    fakeNow = DateTime(2026, 7, 2, 12, 0, 0);
    breaker = CircuitBreaker(
      write: (k, v) async => storage[k] = v,
      read: (k) async => storage[k],
      delete: (k) async => storage.remove(k),
      now: () => fakeNow,
    );
  });

  test('初始状态 closed，允许调用', () async {
    expect(await breaker.state, CircuitBreakerState.closed);
    expect(await breaker.allowCall, isTrue);
  });

  test('连续 2 次失败仍 closed（未达阈值 3）', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    expect(await breaker.state, CircuitBreakerState.closed);
    expect(await breaker.failureCount, 2);
  });

  test('连续 3 次失败 → open，拒绝调用', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    expect(await breaker.state, CircuitBreakerState.open);
    expect(await breaker.allowCall, isFalse);
  });

  test('open 期间 30s 内仍 open', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    // 推进 29s
    fakeNow = fakeNow.add(const Duration(seconds: 29));
    expect(await breaker.state, CircuitBreakerState.open);
  });

  test('open 30s 后 → halfOpen，允许调用试探', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    // 推进 31s
    fakeNow = fakeNow.add(const Duration(seconds: 31));
    expect(await breaker.state, CircuitBreakerState.halfOpen);
    expect(await breaker.allowCall, isTrue);
  });

  test('halfOpen 试探成功 → closed，失败计数清零', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    fakeNow = fakeNow.add(const Duration(seconds: 31));
    expect(await breaker.state, CircuitBreakerState.halfOpen);
    await breaker.recordSuccess();
    expect(await breaker.state, CircuitBreakerState.closed);
    expect(await breaker.failureCount, 0);
  });

  test('halfOpen 试探失败 → 重新 open（重置 30s）', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    // 31s 后 halfOpen
    fakeNow = fakeNow.add(const Duration(seconds: 31));
    expect(await breaker.state, CircuitBreakerState.halfOpen);
    // halfOpen 试探失败
    await breaker.recordHalfOpenFailure();
    // 重新 open，需再等 30s
    fakeNow = fakeNow.add(const Duration(seconds: 29));
    expect(await breaker.state, CircuitBreakerState.open);
    fakeNow = fakeNow.add(const Duration(seconds: 2));
    expect(await breaker.state, CircuitBreakerState.halfOpen);
  });

  test('closed 状态成功调用 → 失败计数清零', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordSuccess();
    expect(await breaker.failureCount, 0);
  });

  test('断路器状态跨实例持久化（模拟重启）', () async {
    // 实例 1：触发 open
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    expect(await breaker.state, CircuitBreakerState.open);
    // 实例 2：用同一 storage 新建（模拟后台 workmanager 新 session）
    final breaker2 = CircuitBreaker(
      write: (k, v) async => storage[k] = v,
      read: (k) async => storage[k],
      delete: (k) async => storage.remove(k),
      now: () => fakeNow,
    );
    expect(await breaker2.state, CircuitBreakerState.open);
    expect(await breaker2.allowCall, isFalse);
  });
}
