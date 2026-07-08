import 'package:flutter_test/flutter_test.dart';
import 'package:eatwise/data/bluetooth/mi_scale_parser.dart';

/// M27 小米体重秤 v1 协议解析器单测
///
/// 样本来源：
/// - 样本 1（0x62）：openScale wiki 真实抓包，bit6=1，ESPHome 枚举漏掉，bitmask 正确
/// - 样本 2-7：基于 ESPHome 源码常量 + ble_monitor bitmask 逻辑构造
///
/// 协议：UUID 0x181D，10 字节 payload
/// byte 0: control byte（bit0=lbs, bit4=jin, bit5=stabilized, bit7=removed）
/// byte 1-2: weight raw（little-endian uint16）
/// byte 3-9: timestamp（year LE 2B + month/day/hour/min/sec 各 1B）
void main() {
  group('MiScaleParser.parseV1', () {
    test('样本 1（真实 openScale）：0x62 kg stabilized 94.3 kg', () {
      final payload = [0x62, 0xAC, 0x49, 0xE0, 0x07, 0x0C, 0x14, 0x0D, 0x1C, 0x04];
      final m = MiScaleParser.parseV1(payload);
      expect(m, isNotNull);
      expect(m!.weightKg, closeTo(94.3, 0.01));
      expect(m.unit, 'kg');
      expect(m.isStabilized, true);
      expect(m.weightRemoved, false);
      expect(m.isEffective, true); // stabilized && !removed
    });

    test('样本 2：0x22 kg stabilized not removed 100.72 kg', () {
      final payload = [0x22, 0xB0, 0x4E, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00];
      final m = MiScaleParser.parseV1(payload);
      expect(m, isNotNull);
      // raw = 0xB0 | (0x4E << 8) = 176 | 19968 = 20144, /200 = 100.72
      expect(m!.weightKg, closeTo(100.72, 0.01));
      expect(m.unit, 'kg');
      expect(m.isStabilized, true);
      expect(m.weightRemoved, false);
      expect(m.isEffective, true);
    });

    test('样本 3：0xA2 kg stabilized removed（下秤包，isEffective=false）', () {
      final payload = [0xA2, 0xB0, 0x4E, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00];
      final m = MiScaleParser.parseV1(payload);
      expect(m, isNotNull);
      expect(m!.weightKg, closeTo(100.72, 0.01));
      expect(m.unit, 'kg');
      expect(m.isStabilized, true);
      expect(m.weightRemoved, true);
      expect(m.isEffective, false); // removed=true → 不落库
    });

    test('样本 4：0x12 jin not stabilized（抖动，isEffective=false）', () {
      final payload = [0x12, 0x58, 0x4E, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00];
      final m = MiScaleParser.parseV1(payload);
      expect(m, isNotNull);
      // jin: raw=20056, /100=200.56 斤, *0.5=100.28 kg
      expect(m!.weightKg, closeTo(100.28, 0.01));
      expect(m.unit, 'jin');
      expect(m.isStabilized, false);
      expect(m.weightRemoved, false);
      expect(m.isEffective, false); // !stabilized → 不落库
    });

    test('样本 5：0xB2 jin stabilized removed（下秤包，isEffective=false）', () {
      final payload = [0xB2, 0x58, 0x4E, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00];
      final m = MiScaleParser.parseV1(payload);
      expect(m, isNotNull);
      expect(m!.weightKg, closeTo(100.28, 0.01));
      expect(m.unit, 'jin');
      expect(m.isStabilized, true);
      expect(m.weightRemoved, true);
      expect(m.isEffective, false);
    });

    test('样本 6：0x03 lbs not stabilized（抖动，isEffective=false）', () {
      final payload = [0x03, 0xD0, 0x15, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00];
      final m = MiScaleParser.parseV1(payload);
      expect(m, isNotNull);
      // lbs: raw=5584, /100=55.84 lbs, *0.453592=25.33 kg
      expect(m!.weightKg, closeTo(25.33, 0.01));
      expect(m.unit, 'lbs');
      expect(m.isStabilized, false);
      expect(m.weightRemoved, false);
      expect(m.isEffective, false);
    });

    test('样本 7：0xB3 lbs stabilized removed（下秤包，isEffective=false）', () {
      final payload = [0xB3, 0xD0, 0x15, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00];
      final m = MiScaleParser.parseV1(payload);
      expect(m, isNotNull);
      expect(m!.weightKg, closeTo(25.33, 0.01));
      expect(m.unit, 'lbs');
      expect(m.isStabilized, true);
      expect(m.weightRemoved, true);
      expect(m.isEffective, false);
    });

    test('长度错误返回 null', () {
      expect(MiScaleParser.parseV1([0x22, 0xAC, 0x49]), isNull);
      expect(MiScaleParser.parseV1([]), isNull);
    });

    test('packetId 去重：相同 payload 产生相同 packetId', () {
      final p = [0x22, 0xB0, 0x4E, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00];
      final m1 = MiScaleParser.parseV1(p);
      final m2 = MiScaleParser.parseV1(p);
      expect(m1, isNotNull);
      expect(m2, isNotNull);
      expect(m1!.packetId, m2!.packetId);
      expect(m1.packetId, '22b04ee80707080a1e00');
    });
  });

  group('MiScaleParser.parseV2', () {
    test('样本 A（真实抓包）：0xA6 kg stabilized removed complete（下秤包，isEffective=false）', () {
      // c0=0x02(kg) c1=0xA6=10100110 → bit1=1(complete) bit5=1(stabilized) bit7=1(removed)
      final payload = [0x02, 0xA6, 0xE6, 0x07, 0x02, 0x0B, 0x11, 0x22, 0x07, 0xBA, 0x01, 0x3C, 0x37];
      final m = MiScaleParser.parseV2(payload);
      expect(m, isNotNull);
      expect(m!.weightKg, closeTo(70.70, 0.01));
      expect(m.unit, 'kg');
      expect(m.isStabilized, true);
      expect(m.weightRemoved, true);
      expect(m.measurementComplete, true);
      expect(m.impedance, 442); // 0x01BA = 442
      expect(m.isEffective, false); // removed=true
    });

    test('样本 B：0x20 kg stabilized 未下秤 阻抗未完成（isEffective=true，impedance=null）', () {
      // c1=0x20=00100000 → bit5=1(stabilized)，bit1=0(无阻抗)
      final payload = [0x02, 0x20, 0xE8, 0x07, 0x03, 0x0F, 0x08, 0x1E, 0x00, 0x00, 0x00, 0xA4, 0x38];
      final m = MiScaleParser.parseV2(payload);
      expect(m, isNotNull);
      expect(m!.weightKg, closeTo(72.50, 0.01));
      expect(m.unit, 'kg');
      expect(m.isStabilized, true);
      expect(m.weightRemoved, false);
      expect(m.measurementComplete, false);
      expect(m.impedance, isNull);
      expect(m.isEffective, true);
    });

    test('样本 C：0x22 kg stabilized+complete 未下秤（理想帧，isEffective=true，impedance=480）', () {
      // c1=0x22=00100010 → bit1=1(complete) bit5=1(stabilized)
      final payload = [0x02, 0x22, 0xE8, 0x07, 0x03, 0x0F, 0x08, 0x1F, 0x05, 0xE0, 0x01, 0x5C, 0x35];
      final m = MiScaleParser.parseV2(payload);
      expect(m, isNotNull);
      expect(m!.weightKg, closeTo(68.30, 0.01));
      expect(m.unit, 'kg');
      expect(m.isStabilized, true);
      expect(m.weightRemoved, false);
      expect(m.measurementComplete, true);
      expect(m.impedance, 480); // 0x01E0 = 480
      expect(m.isEffective, true);
    });

    test('样本 D：0x20 lbs stabilized（验单位换算）', () {
      // c0=0x03(lbs) c1=0x20(stabilized)
      final payload = [0x03, 0x20, 0xE8, 0x07, 0x03, 0x0F, 0x08, 0x1E, 0x00, 0x00, 0x00, 0x80, 0x3E];
      final m = MiScaleParser.parseV2(payload);
      expect(m, isNotNull);
      expect(m!.weightKg, closeTo(72.5747, 0.01));
      expect(m.unit, 'lbs');
      expect(m.isStabilized, true);
      expect(m.isEffective, true);
    });

    test('样本 E：0x00 kg 未稳定（抖动，isEffective=false）', () {
      // c1=0x00 → stabilized=0
      final payload = [0x02, 0x00, 0xE8, 0x07, 0x03, 0x0F, 0x08, 0x1E, 0x00, 0x00, 0x00, 0xB0, 0x36];
      final m = MiScaleParser.parseV2(payload);
      expect(m, isNotNull);
      expect(m!.weightKg, closeTo(70.0, 0.01));
      expect(m.unit, 'kg');
      expect(m.isStabilized, false);
      expect(m.isEffective, false);
    });

    test('样本 F：0x60 jin stabilized（验 byte1 bit6 catty）', () {
      // c1=0x60=01100000 → bit5=1(stabilized) bit6=1(catty)
      final payload = [0x02, 0x60, 0xE8, 0x07, 0x03, 0x0F, 0x08, 0x1E, 0x00, 0x00, 0x00, 0xA4, 0x38];
      final m = MiScaleParser.parseV2(payload);
      expect(m, isNotNull);
      expect(m!.weightKg, closeTo(72.50, 0.01));
      expect(m.unit, 'jin');
      expect(m.isStabilized, true);
      expect(m.isEffective, true);
    });

    test('v2 长度错误返回 null', () {
      expect(MiScaleParser.parseV2([0x02, 0x20, 0xE8]), isNull);
      expect(MiScaleParser.parseV2([]), isNull);
    });

    test('v2 packetId 去重：剔除时间戳字节，相同控制+阻抗+体重产生相同 packetId', () {
      // 同一测量值，不同时间戳（bytes 2-8 不同）
      final p1 = [0x02, 0x22, 0xE8, 0x07, 0x03, 0x0F, 0x08, 0x1F, 0x05, 0xE0, 0x01, 0x5C, 0x35];
      final p2 = [0x02, 0x22, 0xE8, 0x07, 0x04, 0x10, 0x09, 0x20, 0x06, 0xE0, 0x01, 0x5C, 0x35];
      final m1 = MiScaleParser.parseV2(p1);
      final m2 = MiScaleParser.parseV2(p2);
      expect(m1, isNotNull);
      expect(m2, isNotNull);
      // packetId 取 bytes[0-1]+bytes[9-12]，时间戳 bytes[2-8] 不影响
      expect(m1!.packetId, m2!.packetId);
    });
  });
}
