import 'package:flutter/foundation.dart';

/// Mi Scale v1（XMTZC04HM / Mi Smart Scale 2）协议解析器
///
/// 协议参考（来自调研）：
/// - ble_monitor custom_components/miscale/parser.py（bitmask 判定，正确实现）
/// - openScale 源码 + wiki（hex 样本）
/// - 不采用 ESPHome 实现的枚举匹配（漏 0x62 等包）与 0.6 斤系数（应为 0.5）
///
/// Payload 布局（10 字节）：
/// - byte 0：control byte
///   - bit0 = 1 → lbs
///   - bit4 = 1 → jin（斤）
///   - bit5 = 1 → weight stabilized（稳定）
///   - bit7 = 1 → weight removed（下秤包，应丢弃）
/// - byte 1-2：weight raw（little-endian uint16）
/// - byte 3-9：timestamp（year/month/day/h/m/s），解析不需要
class MiScaleParser {
  MiScaleParser._();

  /// 解析 v1 payload，长度不为 10 返回 null
  static MiScaleMeasurement? parseV1(List<int> payload) {
    if (payload.length != 10) return null;

    final controlByte = payload[0];
    // little-endian uint16
    final raw = payload[1] | (payload[2] << 8);

    // 单位判定（bitmask，不用枚举匹配）
    final isLbs = (controlByte & (1 << 0)) != 0;
    final isJin = (controlByte & (1 << 4)) != 0;

    double weightKg;
    String unit;
    if (isLbs) {
      // lbs → kg
      weightKg = raw / 100.0 * 0.453592;
      unit = 'lbs';
    } else if (isJin) {
      // 斤 → kg（1 斤 = 0.5 kg，ESPHome 0.6 系数是 bug）
      weightKg = raw / 100.0 * 0.5;
      unit = 'jin';
    } else {
      // kg
      weightKg = raw / 200.0;
      unit = 'kg';
    }

    final isStabilized = (controlByte & (1 << 5)) != 0;
    final weightRemoved = (controlByte & (1 << 7)) != 0;

    // packet_id：payload hex 字符串作为去重 key
    final packetId = payload
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return MiScaleMeasurement(
      weightKg: weightKg,
      unit: unit,
      isStabilized: isStabilized,
      weightRemoved: weightRemoved,
      packetId: packetId,
    );
  }
}

/// 一次测量结果
@immutable
class MiScaleMeasurement {
  /// 统一换算到 kg
  final double weightKg;

  /// 原始单位：'kg' / 'jin' / 'lbs'
  final String unit;

  /// 是否稳定（bit5）
  final bool isStabilized;

  /// 是否为下秤包（bit7，应丢弃）
  final bool weightRemoved;

  /// 去重 key（payload hex）
  final String packetId;

  const MiScaleMeasurement({
    required this.weightKg,
    required this.unit,
    required this.isStabilized,
    required this.weightRemoved,
    required this.packetId,
  });

  /// 是否为有效测量：稳定 && 未下秤（学 ble_monitor 双重保护）
  bool get isEffective => isStabilized && !weightRemoved;
}
