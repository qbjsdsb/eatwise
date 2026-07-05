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

  test('连续 4 次失败仍 closed（未达阈值 5）', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    expect(await breaker.state, CircuitBreakerState.closed);
    expect(await breaker.failureCount, 4);
  });

  test('连续 5 次失败 → open，拒绝调用', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    expect(await breaker.state, CircuitBreakerState.open);
    expect(await breaker.allowCall, isFalse);
  });

  test('open 期间 60s 内仍 open', () async {
    for (var i = 0; i < 5; i++) {
      await breaker.recordFailure();
    }
    // 推进 59s
    fakeNow = fakeNow.add(const Duration(seconds: 59));
    expect(await breaker.state, CircuitBreakerState.open);
  });

  test('open 60s 后 → halfOpen，允许调用试探', () async {
    for (var i = 0; i < 5; i++) {
      await breaker.recordFailure();
    }
    // 推进 61s
    fakeNow = fakeNow.add(const Duration(seconds: 61));
    expect(await breaker.state, CircuitBreakerState.halfOpen);
    expect(await breaker.allowCall, isTrue);
  });

  test('halfOpen 试探成功 → closed，失败计数清零', () async {
    for (var i = 0; i < 5; i++) {
      await breaker.recordFailure();
    }
    fakeNow = fakeNow.add(const Duration(seconds: 61));
    expect(await breaker.state, CircuitBreakerState.halfOpen);
    await breaker.recordSuccess();
    expect(await breaker.state, CircuitBreakerState.closed);
    expect(await breaker.failureCount, 0);
  });

  test('halfOpen 试探失败 → 重新 open（重置 60s）', () async {
    for (var i = 0; i < 5; i++) {
      await breaker.recordFailure();
    }
    // 61s 后 halfOpen
    fakeNow = fakeNow.add(const Duration(seconds: 61));
    expect(await breaker.state, CircuitBreakerState.halfOpen);
    // halfOpen 试探失败
    await breaker.recordHalfOpenFailure();
    // 重新 open，需再等 60s
    fakeNow = fakeNow.add(const Duration(seconds: 59));
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
    for (var i = 0; i < 5; i++) {
      await breaker.recordFailure();
    }
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

  // M16.2 新增：429 限流不计入失败计数
  group('M16.2: 429 限流不计入断路器失败', () {
    test('4 次普通失败 + 多次 429 仍 closed（429 不累计）', () async {
      // 4 次普通失败（阈值 5，未触发）
      await breaker.recordFailure();
      await breaker.recordFailure();
      await breaker.recordFailure();
      await breaker.recordFailure();
      expect(await breaker.failureCount, 4);
      expect(await breaker.state, CircuitBreakerState.closed);

      // 多次 429 限流（不应累计失败计数）
      await breaker.recordFailure(isRateLimit: true);
      await breaker.recordFailure(isRateLimit: true);
      await breaker.recordFailure(isRateLimit: true);
      await breaker.recordFailure(isRateLimit: true);
      await breaker.recordFailure(isRateLimit: true);

      // 失败计数仍为 4（429 不累计）
      expect(await breaker.failureCount, 4);
      expect(await breaker.state, CircuitBreakerState.closed);
      expect(await breaker.allowCall, isTrue);
    });

    test('5 次 429 限流不触发 open（限流是正常行为不是模型故障）', () async {
      // 5 次 429（原阈值 5 会触发 open，但 429 不应触发）
      for (var i = 0; i < 5; i++) {
        await breaker.recordFailure(isRateLimit: true);
      }
      expect(await breaker.failureCount, 0);
      expect(await breaker.state, CircuitBreakerState.closed);
      expect(await breaker.allowCall, isTrue);
    });

    test('4 次普通失败 + 1 次 429 后再 1 次普通失败 → open（429 不影响计数）', () async {
      // 4 次普通失败
      for (var i = 0; i < 4; i++) {
        await breaker.recordFailure();
      }
      expect(await breaker.failureCount, 4);

      // 1 次 429（不累计）
      await breaker.recordFailure(isRateLimit: true);
      expect(await breaker.failureCount, 4);
      expect(await breaker.state, CircuitBreakerState.closed);

      // 再 1 次普通失败（第 5 次，触发 open）
      await breaker.recordFailure();
      expect(await breaker.state, CircuitBreakerState.open);
    });
  });
}
