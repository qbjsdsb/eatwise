// lib/features/recognize/circuit_breaker.dart
import 'package:flutter/foundation.dart';

/// 断路器状态
enum CircuitBreakerState { closed, open, halfOpen }

/// 视觉模型断路器（设计 3.2：连续 3 次失败 → 短路 30s）
///
/// 状态机：
/// - closed（正常）：记录失败次数，连续 3 次 retryable 失败 → open
/// - open（短路）：直接拒绝调用，30s 后 → halfOpen
/// - halfOpen（半开）：放行一次试探，成功 → closed，失败 → open（重置计时）
///
/// 持久化：失败计数 + open 截止时间存 secure_storage，跨 session + 后台回补感知
class CircuitBreaker {
  static const _failureThreshold = 3;
  static const _openDuration = Duration(seconds: 30);

  final Future<void> Function(String key, String value) _write;
  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key) _delete;
  final DateTime Function() _now;

  static const _keyFailures = 'circuit_failures';
  static const _keyOpenUntil = 'circuit_open_until';

  CircuitBreaker({
    required Future<void> Function(String key, String value) write,
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key) delete,
    DateTime Function()? now,
  }) : _write = write,
       _read = read,
       _delete = delete,
       _now = now ?? DateTime.now;

  /// 当前状态（读持久化数据判断）
  Future<CircuitBreakerState> get state async {
    final openUntilStr = await _read(_keyOpenUntil);
    if (openUntilStr != null) {
      final openUntil = DateTime.fromMillisecondsSinceEpoch(
        int.parse(openUntilStr),
      );
      if (_now().isBefore(openUntil)) return CircuitBreakerState.open;
      // 已过 open 截止 → halfOpen（未持久化，仅内存判断）
      return CircuitBreakerState.halfOpen;
    }
    return CircuitBreakerState.closed;
  }

  /// 调用前检查：是否允许调用
  /// open 状态返回 false（调用方应直接走降级，不调 API）
  Future<bool> get allowCall async => await state != CircuitBreakerState.open;

  /// 记录成功：重置失败计数，清除 open 截止（halfOpen → closed）
  Future<void> recordSuccess() async {
    await _delete(_keyFailures);
    await _delete(_keyOpenUntil);
  }

  /// 记录失败：失败计数 +1，达阈值 → open
  Future<void> recordFailure() async {
    final failuresStr = await _read(_keyFailures);
    final failures = int.tryParse(failuresStr ?? '0') ?? 0;
    final newFailures = failures + 1;
    if (newFailures >= _failureThreshold) {
      // 达阈值 → open，写截止时间
      final openUntil = _now().add(_openDuration);
      await _write(_keyOpenUntil, openUntil.millisecondsSinceEpoch.toString());
      await _delete(_keyFailures); // open 期间不计失败
    } else {
      await _write(_keyFailures, newFailures.toString());
    }
  }

  /// halfOpen 试探失败 → 重新 open（重置 30s 计时）
  /// （halfOpen 状态下 recordFailure 也会走到 open 分支，但需确保 openUntil 重置）
  /// 实际上 recordFailure 已处理：halfOpen 时 _keyFailures 为空（之前 recordSuccess 清了或 open 期间清了），
  /// newFailures=1 < 3 不会重新 open。故 halfOpen 失败需单独处理。
  Future<void> recordHalfOpenFailure() async {
    final openUntil = _now().add(_openDuration);
    await _write(_keyOpenUntil, openUntil.millisecondsSinceEpoch.toString());
    await _delete(_keyFailures);
  }

  /// 仅供测试：读取当前失败计数
  @visibleForTesting
  Future<int> get failureCount async {
    final failuresStr = await _read(_keyFailures);
    return int.tryParse(failuresStr ?? '0') ?? 0;
  }
}
