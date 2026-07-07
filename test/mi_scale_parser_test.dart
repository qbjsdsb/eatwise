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
}
