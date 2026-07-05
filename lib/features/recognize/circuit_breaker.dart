// lib/features/recognize/circuit_breaker.dart
import 'package:flutter/foundation.dart';

/// 断路器状态
enum CircuitBreakerState { closed, open, halfOpen }

/// 视觉模型断路器（设计 3.2：连续 5 次失败 → 短路 60s）
///
/// 状态机：
/// - closed（正常）：记录失败次数，连续 5 次 retryable 失败 → open
/// - open（短路）：直接拒绝调用，60s 后 → halfOpen
/// - halfOpen（半开）：放行一次试探，成功 → closed，失败 → open（重置计时）
///
/// 持久化：失败计数 + open 截止时间存 secure_storage，跨 session + 后台回补感知
///
/// M16.2 修复（用户反馈"识别经常出错"）：
/// - 阈值 3→5：3 次过严，网络抖动易触发，5 次更宽容
/// - open 时长 30s→60s：给服务端更多恢复时间
/// - 429 限流不计入失败：限流是正常行为不是模型故障，不应累计触发断路器
class CircuitBreaker {
  static const _failureThreshold = 5;
  static const _openDuration = Duration(seconds: 60);

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
  })  : _write = write,
        _read = read,
        _delete = delete,
        _now = now ?? DateTime.now;

  /// 当前状态（读持久化数据判断）
  Future<CircuitBreakerState> get state async {
    final openUntilStr = await _read(_keyOpenUntil);
    if (openUntilStr != null) {
      final openUntilMs = int.tryParse(openUntilStr);
      if (openUntilMs == null) {
        // 存储损坏，清理并视为 closed
        await _delete(_keyOpenUntil);
        return CircuitBreakerState.closed;
      }
      final openUntil = DateTime.fromMillisecondsSinceEpoch(openUntilMs);
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
  ///
  /// [isRateLimit] 为 true 时（429 限流）不计入失败计数——限流是正常行为
  /// 不是模型故障，3 次 429 不应触发断路器（M16.2 修复）。
  Future<void> recordFailure({bool isRateLimit = false}) async {
    if (isRateLimit) {
      // 429 限流不累计失败计数，直接返回（等 Retry-After 后重试即可）
      return;
    }
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
