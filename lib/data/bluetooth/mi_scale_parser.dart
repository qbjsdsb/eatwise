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

  /// v2: 小米体脂秤2（XMTZC05HM）/ 体脂秤1代（XMTZC02HM）
  /// UUID 0x181B（Body Composition Service），13 字节 payload
  ///
  /// 与 v1 的关键差异：
  /// - payload 13 字节（v1=10）
  /// - 2 个 control byte（v1=1 个）
  /// - jin flag 在 byte1 bit6（v1 在 byte0 bit4）
  /// - stabilized 在 byte1 bit5（v1 在 byte0 bit5）
  /// - removed 在 byte1 bit7（v1 在 byte0 bit7）
  /// - weight raw 在 byte[11-12]（v1 在 byte[1-2]）
  /// - 新增 impedance 在 byte[9-10]（byte1 bit1=1 时有效）
  /// - 新增 measurementComplete（byte1 bit1，阻抗测量完成）
  static MiScaleMeasurement? parseV2(List<int> payload) {
    if (payload.length != 13) return null;

    final c0 = payload[0];
    final c1 = payload[1];
    final raw = payload[11] | (payload[12] << 8); // 小端

    // 单位判定（注意 jin 位置从 v1 的 byte0 bit4 变成 v2 的 byte1 bit6）
    final isLbs = (c0 & (1 << 0)) != 0;
    final isJin = (c1 & (1 << 6)) != 0;

    double weightKg;
    String unit;
    if (isJin) {
      weightKg = raw / 100.0 * 0.5;
      unit = 'jin';
    } else if (isLbs) {
      weightKg = raw / 100.0 * 0.453592;
      unit = 'lbs';
    } else {
      weightKg = raw / 200.0;
      unit = 'kg';
    }

    final isStabilized = (c1 & (1 << 5)) != 0;
    final weightRemoved = (c1 & (1 << 7)) != 0;
    final measurementComplete = (c1 & (1 << 1)) != 0; // 阻抗测量完成

    // impedance 仅 measurementComplete 时有效
    int? impedance;
    if (measurementComplete) {
      final imp = payload[9] | (payload[10] << 8);
      if (imp > 0 && imp < 3000) impedance = imp; // ESPHome 有效范围
    }

    // packetId 去重剔除时间戳字节（bytes 2-8），避免每秒包被当新包
    final packetId = [
      payload[0], payload[1], // control bytes
      payload[9], payload[10], // impedance
      payload[11], payload[12], // weight raw
    ].map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return MiScaleMeasurement(
      weightKg: weightKg,
      unit: unit,
      isStabilized: isStabilized,
      weightRemoved: weightRemoved,
      packetId: packetId,
      impedance: impedance,
      measurementComplete: measurementComplete,
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

  /// 阻抗值（Ω，1-2999），仅 v2 协议且 measurementComplete 时有效；v1 恒 null
  final int? impedance;

  /// 阻抗测量是否完成（v2 byte1 bit1）；v1 恒 false
  final bool measurementComplete;

  const MiScaleMeasurement({
    required this.weightKg,
    required this.unit,
    required this.isStabilized,
    required this.weightRemoved,
    required this.packetId,
    this.impedance,
    this.measurementComplete = false,
  });

  /// 是否为有效测量：稳定 && 未下秤（学 ble_monitor 双重保护）
  bool get isEffective => isStabilized && !weightRemoved;
}
