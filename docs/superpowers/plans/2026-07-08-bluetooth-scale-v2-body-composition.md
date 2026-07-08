# M27 v2 小米体脂秤2 + 体脂率 + BMR 自动升级 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 扩展 M27 蓝牙同步支持小米体脂秤2（XMTZC05HM，v2 协议），新增体脂率计算（openScale BIA 公式），并让 BMR 计算在有体脂率时自动升级用 Katch 公式（对精瘦人群更准）。

**Architecture:** 协议层新增 parseV2（保留 parseV1 双协议兼容）+ scanner 双 UUID 路由 + BodyFatCalculator 纯函数模块 + weight_log 表加 impedance/bodyFatPct 字段 + profile BMR 自动升级（有体脂率用 Katch，无则 Mifflin）+ tdee_calibrator 读 formula 分支 + UI 卡片/tooltip 展示体脂率。

**Tech Stack:** Flutter 3.44.4 / flutter_blue_plus 2.3.10 / drift 2.34 / Riverpod 3.3 / openScale MiScaleLib BIA 公式

---

## 文件结构

### 新增文件
- `lib/nutrition/body_fat_calculator.dart` — openScale BIA 体脂率公式（纯函数，可单测）
- `test/nutrition/body_fat_calculator_test.dart` — 3 openScale 夹具 + 边界测试
- `test/features/profile_save_formula_switch_test.dart` — formula 切换 + tdee 重置测试
- `test/nutrition/tdee_calibrator_formula_branch_test.dart` — formula 分支选 BMR 测试

### 修改文件
- `lib/data/bluetooth/mi_scale_parser.dart` — 新增 parseV2 + 模型扩展
- `lib/data/bluetooth/mi_scale_scanner.dart` — 双 UUID 路由 + isClosed 守卫 + onError 日志
- `lib/data/database/tables/weight_log_table.dart` — 加 impedance + bodyFatPct 字段
- `lib/data/database/database.dart` — schemaVersion 4→5 migration
- `lib/data/repositories/weight_log_repository.dart` — insert/update 支持新字段
- `lib/data/repositories/profile_repository.dart` — 新增 clearBodyFatPct() + update 支持 tdeeAdjustmentKcal 显式 0
- `lib/data/backup/json_exporter.dart` — 导出新字段
- `lib/data/backup/json_importer.dart` — 导入新字段（兼容旧备份）
- `lib/features/weight/weight_page.dart` — v2 捕获时机 + 系统定位 + 冷却 + UI + _save 同步
- `lib/features/profile/profile_page.dart` — BMR 自动升级 + formula 切换重置 + clearBodyFatPct
- `lib/nutrition/tdee_calibrator.dart` — 读 formula 分支选 BMR
- `test/mi_scale_parser_test.dart` — 新增 v2 测试（6 hex 样本）

---

## Task 1: BodyFatCalculator（TDD，无依赖，先做）

**Files:**
- Create: `lib/nutrition/body_fat_calculator.dart`
- Test: `test/nutrition/body_fat_calculator_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/nutrition/body_fat_calculator_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:eatwise/nutrition/body_fat_calculator.dart';

void main() {
  group('BodyFatCalculator.calcBodyFat', () {
    // openScale 官方夹具（双源验证，误差 <1e-5）
    test('openScale 夹具1：男 30 180cm 80kg 500Ω → 23.32%', () {
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: true, age: 30, heightCm: 180, weightKg: 80, impedance: 500,
      );
      expect(bf, isNotNull);
      expect(bf!, closeTo(23.32, 0.05));
    });

    test('openScale 夹具2：女 28 165cm 60kg 520Ω → 30.36%', () {
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: false, age: 28, heightCm: 165, weightKg: 60, impedance: 520,
      );
      expect(bf, isNotNull);
      expect(bf!, closeTo(30.36, 0.05));
    });

    test('openScale 夹具3：男 45 175cm 95kg 430Ω → 32.42%', () {
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: true, age: 45, heightCm: 175, weightKg: 95, impedance: 430,
      );
      expect(bf, isNotNull);
      expect(bf!, closeTo(32.42, 0.05));
    });

    // 边界测试
    test('impedance=null → 返回 null（提前下秤，BIA 未完成）', () {
      expect(
        BodyFatCalculator.calcBodyFat(
          isMale: true, age: 30, heightCm: 180, weightKg: 80, impedance: null,
        ),
        isNull,
      );
    });

    test('impedance=0 → 返回 null（无效值）', () {
      expect(
        BodyFatCalculator.calcBodyFat(
          isMale: true, age: 30, heightCm: 180, weightKg: 80, impedance: 0,
        ),
        isNull,
      );
    });

    test('impedance<0 → 返回 null（无效值）', () {
      expect(
        BodyFatCalculator.calcBodyFat(
          isMale: true, age: 30, heightCm: 180, weightKg: 80, impedance: -10,
        ),
        isNull,
      );
    });

    test('weightKg=0 → 返回 null（除零保护）', () {
      expect(
        BodyFatCalculator.calcBodyFat(
          isMale: true, age: 30, heightCm: 180, weightKg: 0, impedance: 500,
        ),
        isNull,
      );
    });

    test('体脂率超 75 → clamp 到 75', () {
      // 极端输入构造超范围值（极高 impedance + 极低体重）
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: true, age: 80, heightCm: 150, weightKg: 30, impedance: 2999,
      );
      expect(bf, isNotNull);
      expect(bf!, lessThanOrEqualTo(75.0));
    });

    test('体脂率低于 5 → clamp 到 5', () {
      // 极低 impedance + 高体重构造低体脂
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: true, age: 20, heightCm: 190, weightKg: 120, impedance: 1,
      );
      expect(bf, isNotNull);
      expect(bf!, greaterThanOrEqualTo(5.0));
    });

    // 性别 + 年龄 + 体重分支覆盖
    test('女性 >49 岁（lbmSub=7.25 分支）', () {
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: false, age: 55, heightCm: 160, weightKg: 55, impedance: 500,
      );
      expect(bf, isNotNull);
      expect(bf! > 0, true);
    });

    test('女性 weight>60 + height>160（coeff=0.9888 分支）', () {
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: false, age: 30, heightCm: 170, weightKg: 65, impedance: 500,
      );
      expect(bf, isNotNull);
    });

    test('女性 weight<50 + height>160（coeff=1.0506 分支）', () {
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: false, age: 30, heightCm: 170, weightKg: 45, impedance: 500,
      );
      expect(bf, isNotNull);
    });

    test('男性 weight<61（coeff=0.98 分支）', () {
      final bf = BodyFatCalculator.calcBodyFat(
        isMale: true, age: 30, heightCm: 170, weightKg: 55, impedance: 500,
      );
      expect(bf, isNotNull);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
export PATH=/tmp/flutter/bin:$PATH
flutter test test/nutrition/body_fat_calculator_test.dart
```

预期：FAIL，报错 `Target of URI doesn't exist: 'package:eatwise/nutrition/body_fat_calculator.dart'`。

- [ ] **Step 3: 创建 BodyFatCalculator 实现**

创建 `lib/nutrition/body_fat_calculator.dart`：

```dart
/// 小米体脂秤体脂率计算（openScale MiScaleLib 逆向公式）
///
/// 基于 openScale MiScaleLib.kt + prototux MIBCS 逆向工程，
/// 双源交叉验证（openScale Kotlin + miscale Python 逐字节一致），
/// 3 个回归夹具验证（误差 <1e-5）。
///
/// 公式输入：性别 + 年龄 + 身高 + 体重 + 阻抗（Ω）
/// 公式输出：体脂率百分比（如 23.32 表示 23.32%）
class BodyFatCalculator {
  BodyFatCalculator._();

  /// 计算体脂率百分比。
  ///
  /// [isMale] true=男 false=女
  /// [age] 年龄（岁）
  /// [heightCm] 身高（cm）
  /// [weightKg] 体重（kg）
  /// [impedance] 阻抗（Ω，1-2999），null 或 <=0 表示未测/无效（提前下秤）
  ///
  /// 返回体脂率百分比（5-75），impedance 无效时返回 null。
  static double? calcBodyFat({
    required bool isMale,
    required int age,
    required double heightCm,
    required double weightKg,
    required double? impedance,
  }) {
    // 边界：impedance 无效（提前下秤/未测）→ 返回 null
    if (impedance == null || impedance <= 0) return null;
    if (weightKg <= 0 || heightCm <= 0) return null;

    // 第一步：LBM 系数
    // lbmCoeff = 0.0009058×h² + 0.32×w + 12.226 − 0.0068×imp − 0.0542×age
    double lbmCoeff = (heightCm * 9.058 / 100.0) * (heightCm / 100.0);
    lbmCoeff += weightKg * 0.32 + 12.226;
    lbmCoeff -= impedance * 0.0068;
    lbmCoeff -= age * 0.0542;

    // 第二步：lbmSub（性别 + 年龄扣除常数）
    double lbmSub;
    if (!isMale && age <= 49) {
      lbmSub = 9.25;
    } else if (!isMale && age > 49) {
      lbmSub = 7.25;
    } else {
      lbmSub = 0.8;
    }

    // 第三步：coeff（性别 + 体重 + 身高校正）
    double coeff = 1.0;
    if (isMale && weightKg < 61.0) {
      coeff = 0.98;
    } else if (!isMale && weightKg > 60.0) {
      coeff = 0.96;
      if (heightCm > 160.0) coeff *= 1.03;
    } else if (!isMale && weightKg < 50.0) {
      coeff = 1.02;
      if (heightCm > 160.0) coeff *= 1.03;
    }

    // 第四步：体脂率
    // bodyFat% = (1 − ((lbmCoeff − lbmSub) × coeff) / weight) × 100
    double bodyFat =
        (1.0 - (((lbmCoeff - lbmSub) * coeff) / weightKg)) * 100.0;

    // 第五步：clamp（openScale >63→75 哨兵 + miscale [5,75] 上下限）
    if (bodyFat > 63.0) bodyFat = 75.0;
    if (bodyFat < 5.0) bodyFat = 5.0;
    if (bodyFat > 75.0) bodyFat = 75.0;
    return bodyFat;
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/nutrition/body_fat_calculator_test.dart
```

预期：14 个测试全 PASS。

- [ ] **Step 5: flutter analyze 验证**

```bash
flutter analyze 2>&1 | tail -3
```

预期：No issues found.

- [ ] **Step 6: 提交**

```bash
git add lib/nutrition/body_fat_calculator.dart test/nutrition/body_fat_calculator_test.dart
git commit -m "feat(M27v2): 新增 BodyFatCalculator 体脂率公式（openScale BIA 逆向）"
```

---

## Task 2: MiScaleParser 新增 parseV2（TDD）

**Files:**
- Modify: `lib/data/bluetooth/mi_scale_parser.dart`
- Test: `test/mi_scale_parser_test.dart`

- [ ] **Step 1: 在测试文件追加 v2 失败测试**

在 `test/mi_scale_parser_test.dart` 末尾的 `main()` 函数内追加：

```dart
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
      final p2 = [0x02, 0x22, 0xE8, 0x07, 0x03, 0x0F, 0x08, 0x20, 0x06, 0xE0, 0x01, 0x5C, 0x35]; // 时间+阻抗低字节不同？不，阻抗相同
      final m1 = MiScaleParser.parseV2(p1);
      final m2 = MiScaleParser.parseV2(p2);
      expect(m1, isNotNull);
      expect(m2, isNotNull);
      // packetId 取 bytes[0-1]+bytes[9-12]，时间戳 bytes[2-8] 不影响
      expect(m1!.packetId, m2!.packetId);
    });
  });
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/mi_scale_parser_test.dart
```

预期：v2 group 的测试 FAIL（parseV2 方法不存在）。

- [ ] **Step 3: 扩展 MiScaleMeasurement 模型 + 新增 parseV2**

读取 `lib/data/bluetooth/mi_scale_parser.dart`，在现有 `MiScaleMeasurement` class 加 2 个字段，并新增 `parseV2` 静态方法。

**修改 MiScaleMeasurement**（加 impedance + measurementComplete 字段）：

```dart
class MiScaleMeasurement {
  final double weightKg;
  final String unit;
  final bool isStabilized;
  final bool weightRemoved;
  final String packetId;
  final int? impedance;           // 新增：v1 恒 null
  final bool measurementComplete; // 新增：v1 恒 false

  const MiScaleMeasurement({
    required this.weightKg,
    required this.unit,
    required this.isStabilized,
    required this.weightRemoved,
    required this.packetId,
    this.impedance,
    this.measurementComplete = false,
  });

  bool get isEffective => isStabilized && !weightRemoved;
}
```

**新增 parseV2 静态方法**（在 parseV1 之后）：

```dart
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
      payload[0], payload[1],          // control bytes
      payload[9], payload[10],         // impedance
      payload[11], payload[12],        // weight raw
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
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/mi_scale_parser_test.dart
```

预期：v1 + v2 全部测试 PASS（v1 9 个 + v2 8 个 = 17 个）。

- [ ] **Step 5: flutter analyze**

```bash
flutter analyze 2>&1 | tail -3
```

预期：No issues found.

- [ ] **Step 6: 提交**

```bash
git add lib/data/bluetooth/mi_scale_parser.dart test/mi_scale_parser_test.dart
git commit -m "feat(M27v2): MiScaleParser 新增 parseV2（XMTZC05HM 13字节 v2 协议）"
```

---

## Task 3: MiScaleScanner 双 UUID 路由 + 修复

**Files:**
- Modify: `lib/data/bluetooth/mi_scale_scanner.dart`

- [ ] **Step 1: 修改 scanner 支持双 UUID 路由 + isClosed 守卫 + onError 日志**

读取 `lib/data/bluetooth/mi_scale_scanner.dart`，修改以下部分：

**1. 替换 UUID 常量（L26-27）**：

```dart
  // 修复前
  static final Guid _weightScaleUuid = Guid('181D');

  // 修复后
  /// v1 权重秤 Service UUID（XMTZC04HM 体重秤2）
  static final Guid _v1Uuid = Guid('181D');
  /// v2 体成分 Service UUID（XMTZC05HM 体脂秤2 / XMTZC02HM 体脂秤1代）
  static final Guid _v2Uuid = Guid('181B');
```

**2. 替换 _handleScanResults（L78-98）**：

```dart
  void _handleScanResults(List<ScanResult> results) {
    for (final r in results) {
      final sd = r.advertisementData.serviceData;

      // 双 UUID 路由：v1(0x181D/10B) 或 v2(0x181B/13B)
      MiScaleMeasurement? m;
      final v1Payload = sd[_v1Uuid];
      final v2Payload = sd[_v2Uuid];
      if (v1Payload != null && v1Payload.length == 10) {
        m = MiScaleParser.parseV1(v1Payload);
      } else if (v2Payload != null && v2Payload.length == 13) {
        m = MiScaleParser.parseV2(v2Payload);
      }
      if (m == null) continue;

      // 有效性过滤：stabilized && !removed
      if (!m.isEffective) continue;

      // packet_id 去重（学 ble_monitor）
      if (m.packetId == _lastPacketId) continue;
      _lastPacketId = m.packetId;

      // isClosed 守卫（防 dispose 竞态崩溃）
      if (_controller.isClosed) return;

      // 推送给调用方
      _controller.add(m);
    }
  }
```

**3. 修改 onError（L52-55）加日志**：

```dart
      onError: (Object e) {
        // scanResults/onScanResults 是唯一会发 error 的流
        // 医疗场景不留静默，记录日志便于排查
        debugPrint('MiScaleScanner onScanResults error: $e');
      },
```

**4. 加 import**（文件顶部）：

```dart
import 'package:flutter/foundation.dart'; // debugPrint
```

- [ ] **Step 2: flutter analyze**

```bash
flutter analyze 2>&1 | tail -3
```

预期：No issues found.

- [ ] **Step 3: 跑现有 parser 测试确认无回归**

```bash
flutter test test/mi_scale_parser_test.dart
```

预期：17 个测试全 PASS（无回归）。

- [ ] **Step 4: 提交**

```bash
git add lib/data/bluetooth/mi_scale_scanner.dart
git commit -m "fix(M27v2): scanner 双 UUID 路由 + isClosed 守卫 + onError 日志"
```

---

## Task 4: 数据层扩展（weight_log 加字段 + migration + repository + backup）

**Files:**
- Modify: `lib/data/database/tables/weight_log_table.dart`
- Modify: `lib/data/database/database.dart`
- Modify: `lib/data/repositories/weight_log_repository.dart`
- Modify: `lib/data/backup/json_exporter.dart`
- Modify: `lib/data/backup/json_importer.dart`

- [ ] **Step 1: weight_log_table.dart 加 2 字段**

读取 `lib/data/database/tables/weight_log_table.dart`，修改为：

```dart
import 'package:drift/drift.dart';

/// 体重记录表
class WeightLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()(); // 'YYYY-MM-DD' 本地时区自然日
  RealColumn get weightKg => real()();
  // M27 v2：蓝牙体脂秤2 扩展字段（nullable，向后兼容 v1 秤无此数据）
  RealColumn get impedance => real().nullable()();    // 原始阻抗值 Ω
  RealColumn get bodyFatPct => real().nullable()();   // 体脂率 %
}
```

- [ ] **Step 2: database.dart schemaVersion 4→5 + migration**

读取 `lib/data/database/database.dart`。

**修改 schemaVersion（L36）**：

```dart
  @override
  int get schemaVersion => 5;
```

**在 onUpgrade 末尾（L68 之后）加 v5 migration**：

```dart
          // v4 → v5：M27 v2 —— weight_log 表加 impedance + bodyFatPct 字段
          // 蓝牙体脂秤2（XMTZC05HM）扩展，nullable 向后兼容
          if (from < 5) {
            await m.addColumn(weightLogs, weightLogs.impedance);
            await m.addColumn(weightLogs, weightLogs.bodyFatPct);
          }
```

- [ ] **Step 3: 重新生成 drift 代码**

```bash
export PATH=/tmp/flutter/bin:$PATH
dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -5
```

预期：build success，`database.g.dart` 重新生成含新字段。

- [ ] **Step 4: WeightLogRepository insert/update 支持新字段**

读取 `lib/data/repositories/weight_log_repository.dart`，修改 insert 和 update 方法：

```dart
  /// 插入体重记录（同一天多次记录各存一条，UI 取最新）
  /// M27 v2：支持 impedance + bodyFatPercent（蓝牙体脂秤2，nullable）
  Future<int> insert({
    required String date,
    required double weightKg,
    double? impedance,
    double? bodyFatPercent,
  }) {
    return _db.into(_db.weightLogs).insert(WeightLogsCompanion.insert(
          date: date,
          weightKg: weightKg,
          impedance: impedance == null ? const Value.absent() : Value(impedance),
          bodyFatPct: bodyFatPercent == null
              ? const Value.absent()
              : Value(bodyFatPercent),
        ));
  }
```

```dart
  /// 部分更新体重记录
  /// M27 v2：支持 impedance + bodyFatPercent
  Future<void> update({
    required int id,
    double? weightKg,
    String? date,
    double? impedance,
    double? bodyFatPercent,
  }) async {
    await (_db.weightLogs.update()..where((w) => w.id.equals(id))).write(
      WeightLogsCompanion(
        weightKg: weightKg == null ? const Value.absent() : Value(weightKg),
        date: date == null ? const Value.absent() : Value(date),
        impedance:
            impedance == null ? const Value.absent() : Value(impedance),
        bodyFatPct: bodyFatPercent == null
            ? const Value.absent()
            : Value(bodyFatPercent),
      ),
    );
  }
```

- [ ] **Step 5: json_exporter.dart 导出新字段**

读取 `lib/data/backup/json_exporter.dart`，找到 WeightLog 序列化处，加 impedance + bodyFatPct：

```dart
    // M27 v2：导出 impedance + bodyFatPct（蓝牙体脂秤2 扩展字段）
    'impedance': log.impedance,
    'bodyFatPct': log.bodyFatPct,
```

- [ ] **Step 6: json_importer.dart 导入新字段（兼容旧备份）**

读取 `lib/data/backup/json_importer.dart`，找到 WeightLog 反序列化处，加：

```dart
      // M27 v2：读 impedance + bodyFatPct（兼容旧备份无此字段）
      impedance: (json['impedance'] as num?)?.toDouble(),
      bodyFatPct: (json['bodyFatPct'] as num?)?.toDouble(),
```

- [ ] **Step 7: flutter analyze + 跑现有测试确认无回归**

```bash
flutter analyze 2>&1 | tail -3
flutter test 2>&1 | tail -3
```

预期：analyze No issues；test 全 PASS（0 回归）。

- [ ] **Step 8: 提交**

```bash
git add lib/data/database/tables/weight_log_table.dart lib/data/database/database.dart lib/data/database/database.g.dart lib/data/repositories/weight_log_repository.dart lib/data/backup/json_exporter.dart lib/data/backup/json_importer.dart
git commit -m "feat(M27v2): weight_log 表加 impedance+bodyFatPct 字段（schemaVersion v5）"
```

---

## Task 5: ProfileRepository 支持 clearBodyFatPct + tdeeAdjustmentKcal 显式 0

**Files:**
- Modify: `lib/data/repositories/profile_repository.dart`

- [ ] **Step 1: 新增 clearBodyFatPct() 方法**

读取 `lib/data/repositories/profile_repository.dart`，在 update 方法之后新增：

```dart
  /// 显式置空 bodyFatPct（M27 v2：用户清空体脂率时调用）
  ///
  /// 因 update() 的 null=不更新（Value.absent）设计无法置空 nullable 字段，
  /// 需专门方法。用户清空体脂率 → formula 应回退 mifflin。
  /// 见 update() 的 M7 已知限制注释。
  Future<void> clearBodyFatPct() async {
    await (_db.profiles.update()..where((p) => p.id.equals(1)))
        .write(const ProfilesCompanion(bodyFatPct: Value(null)));
  }
```

- [ ] **Step 2: flutter analyze**

```bash
flutter analyze 2>&1 | tail -3
```

预期：No issues found.

- [ ] **Step 3: 提交**

```bash
git add lib/data/repositories/profile_repository.dart
git commit -m "feat(M27v2): ProfileRepository 新增 clearBodyFatPct()（支持显式置空体脂率）"
```

---

## Task 6: BMR 自动升级（profile_page + tdee_calibrator）

**Files:**
- Modify: `lib/features/profile/profile_page.dart`
- Modify: `lib/nutrition/tdee_calibrator.dart`
- Create: `test/features/profile_save_formula_switch_test.dart`
- Create: `test/nutrition/tdee_calibrator_formula_branch_test.dart`

- [ ] **Step 1: 写 formula 切换失败测试**

创建 `test/features/profile_save_formula_switch_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:eatwise/features/profile/nutrition_calculator.dart';

void main() {
  // 此测试验证 BMR 公式选择逻辑（不测 UI，测计算分支）
  group('BMR 公式选择逻辑', () {
    test('有体脂率 → 用 Katch', () {
      final bmrKatch = NutritionCalculator.bmrKatch(
        weightKg: 70, bodyFatPct: 15,
      );
      final bmrMifflin = NutritionCalculator.bmrMifflin(
        weightKg: 70, heightCm: 175, age: 30, gender: Gender.male,
      );
      // Katch 对精瘦人群 BMR 更高
      expect(bmrKatch, greaterThan(bmrMifflin));
      // Katch: 370 + 21.6×70×(1-0.15) = 370 + 1285.2 = 1655.2
      expect(bmrKatch, closeTo(1655.2, 1.0));
    });

    test('无体脂率 → 用 Mifflin', () {
      final bmr = NutritionCalculator.bmrMifflin(
        weightKg: 70, heightCm: 175, age: 30, gender: Gender.male,
      );
      // Mifflin: 10×70 + 6.25×175 - 5×30 + 5 = 1617.5
      expect(bmr, closeTo(1617.5, 1.0));
    });

    test('体脂率=0 → 走 Mifflin（hasBodyFat=false 判定）', () {
      // bodyFat=0 时 hasBodyFat = 0 > 0 = false，走 mifflin
      // 防止 Katch 对 0% 体脂率算出过高 BMR
      final hasBodyFat = (0.0 > 0);
      expect(hasBodyFat, false);
    });

    test('formula 切换 mifflin→katch 应重置 tdeeAdjustmentKcal', () {
      // 验证切换逻辑：oldFormula != newFormula → 重置
      const oldFormula = 'mifflin';
      const newFormula = 'katch';
      final formulaChanged = oldFormula != newFormula;
      expect(formulaChanged, true);
      // 重置后 tdeeAdjustmentKcal 应为 0
      const resetValue = formulaChanged ? 0 : null;
      expect(resetValue, 0);
    });

    test('formula 未变 mifflin→mifflin 不重置 tdeeAdjustmentKcal', () {
      const oldFormula = 'mifflin';
      const newFormula = 'mifflin';
      final formulaChanged = oldFormula != newFormula;
      expect(formulaChanged, false);
    });
  });
}
```

- [ ] **Step 2: 写 tdee_calibrator formula 分支失败测试**

创建 `test/nutrition/tdee_calibrator_formula_branch_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:eatwise/features/profile/nutrition_calculator.dart';

void main() {
  group('TDEE calibrator BMR 分支选择', () {
    test('formula=katch + bodyFatPct!=null → 用 Katch BMR', () {
      // 模拟 tdee_calibrator 的分支逻辑
      const formula = 'katch';
      const bodyFatPct = 15.0;
      final bmr = (formula == 'katch' && bodyFatPct > 0)
          ? NutritionCalculator.bmrKatch(weightKg: 70, bodyFatPct: bodyFatPct)
          : NutritionCalculator.bmrMifflin(
              weightKg: 70, heightCm: 175, age: 30, gender: Gender.male);
      expect(bmr, closeTo(1655.2, 1.0)); // Katch 值
    });

    test('formula=mifflin → 用 Mifflin BMR（老用户回归）', () {
      const formula = 'mifflin';
      const bodyFatPct = 15.0; // 即使有体脂率，formula=mifflin 仍用 mifflin
      final bmr = (formula == 'katch' && bodyFatPct > 0)
          ? NutritionCalculator.bmrKatch(weightKg: 70, bodyFatPct: bodyFatPct)
          : NutritionCalculator.bmrMifflin(
              weightKg: 70, heightCm: 175, age: 30, gender: Gender.male);
      expect(bmr, closeTo(1617.5, 1.0)); // Mifflin 值
    });

    test('formula=katch 但 bodyFatPct=null → 兜底 Mifflin（防御性）', () {
      const formula = 'katch';
      const double? bodyFatPct = null;
      final bmr = (formula == 'katch' && bodyFatPct != null && bodyFatPct > 0)
          ? NutritionCalculator.bmrKatch(weightKg: 70, bodyFatPct: bodyFatPct!)
          : NutritionCalculator.bmrMifflin(
              weightKg: 70, heightCm: 175, age: 30, gender: Gender.male);
      expect(bmr, closeTo(1617.5, 1.0)); // 兜底 Mifflin
    });
  });
}
```

- [ ] **Step 3: 运行测试确认部分失败**

```bash
flutter test test/features/profile_save_formula_switch_test.dart test/nutrition/tdee_calibrator_formula_branch_test.dart
```

预期：部分 PASS（纯计算逻辑已对），但确认测试可运行。

- [ ] **Step 4: 修改 profile_page.dart BMR 自动升级**

读取 `lib/features/profile/profile_page.dart`。

**修改 L455-461（BMR 计算）**：

```dart
      // 修复前
      // 重算目标（MVP：始终用 mifflin，有体脂率时也用 mifflin 除非用户显式选 katch——Sprint 2 简化）
      final bmr = NutritionCalculator.bmrMifflin(
        weightKg: weight,
        heightCm: height,
        age: age,
        gender: genderEnum,
      );

      // 修复后
      // M27 v2：有体脂率 → Katch-McArdle（基于瘦体重，对精瘦人群更准）；
      // 无 → Mifflin-St Jeor（向后兼容）。formula 字段同步写入实际使用的公式。
      final hasBodyFat = bodyFat != null && bodyFat > 0;
      final bmr = hasBodyFat
          ? NutritionCalculator.bmrKatch(weightKg: weight, bodyFatPct: bodyFat!)
          : NutritionCalculator.bmrMifflin(
              weightKg: weight,
              heightCm: height,
              age: age,
              gender: genderEnum,
            );
      final formula = hasBodyFat ? 'katch' : 'mifflin';
```

**修改 L519-529（update 调用）**：

在 `await repo.update(` 之前读取旧 formula，并在 update 调用中改 formula + 条件重置 tdeeAdjustmentKcal：

```dart
      // M27 v2：读取旧 formula 检测是否切换（切换需重置 tdeeAdjustmentKcal）
      final oldFormula = existing.formula;
      final formulaChanged = oldFormula != formula;

      await repo.update(
        heightCm: height,
        weightKg: weight,
        bodyFatPct: bodyFat,
        age: age,
        gender: _gender,
        activityLevel: _activity,
        goal: _goal,
        goalRateKgPerWeek: goalRate,
        formula: formula, // 修复：用实际公式而非硬编码 'mifflin'
        dailyCalorieTarget: target,
        // M27 v2：formula 切换时重置 tdeeAdjustmentKcal（防跨公式污染）
        tdeeAdjustmentKcal: formulaChanged ? 0 : existing.tdeeAdjustmentKcal,
        // ... 其他字段保持不变 ...
      );

      // M27 v2：bodyFatPct 显式置空（用户清空体脂率时）
      if (bodyFat == null) {
        await repo.clearBodyFatPct();
      }

      // M27 v2：formula 切换提示
      if (formulaChanged && mounted) {
        showAppToast(
          context,
          '已切换到 ${formula == 'katch' ? 'Katch' : 'Mifflin'} 公式，'
          'TDEE 校准累积值已重置，将在下次记录体重后重新校准',
        );
      }
```

注意：保留 L519-529 之间原有的 proteinGPerKg/fatGPerKg/carbGPerKg/specialCondition 等字段，只改 formula 和 tdeeAdjustmentKcal 两行。需读取完整 update 调用块确保不遗漏字段。

- [ ] **Step 5: 修改 tdee_calibrator.dart 读 formula 分支**

读取 `lib/nutrition/tdee_calibrator.dart`，修改 L142-147：

```dart
      // 修复前
      final bmr = NutritionCalculator.bmrMifflin(
        weightKg: profile.weightKg,
        heightCm: profile.heightCm,
        age: profile.age,
        gender: genderEnum,
      );

      // 修复后
      // M27 v2：读 profile.formula 分支选 BMR（有体脂率用 Katch，否则 Mifflin）
      final bmr = (profile.formula == 'katch' &&
              profile.bodyFatPct != null &&
              profile.bodyFatPct! > 0)
          ? NutritionCalculator.bmrKatch(
              weightKg: profile.weightKg, bodyFatPct: profile.bodyFatPct!)
          : NutritionCalculator.bmrMifflin(
              weightKg: profile.weightKg,
              heightCm: profile.heightCm,
              age: profile.age,
              gender: genderEnum,
            );
```

- [ ] **Step 6: 运行新测试 + 全量回归**

```bash
flutter test test/features/profile_save_formula_switch_test.dart test/nutrition/tdee_calibrator_formula_branch_test.dart
flutter test 2>&1 | tail -3
```

预期：新测试 PASS；全量 0 回归。

- [ ] **Step 7: flutter analyze**

```bash
flutter analyze 2>&1 | tail -3
```

预期：No issues found.

- [ ] **Step 8: 提交**

```bash
git add lib/features/profile/profile_page.dart lib/nutrition/tdee_calibrator.dart test/features/profile_save_formula_switch_test.dart test/nutrition/tdee_calibrator_formula_branch_test.dart
git commit -m "feat(M27v2): BMR 自动升级（有体脂率用 Katch）+ formula 切换重置 tdeeAdjustmentKcal"
```

---

## Task 7: weight_page 接入 v2（捕获时机 + 修复 + UI + _save 同步）

**Files:**
- Modify: `lib/features/weight/weight_page.dart`

- [ ] **Step 1: 修复 startScan 时序 bug（P0）**

读取 `lib/features/weight/weight_page.dart` L184-200。

**修改 _startBleScan 的扫描等待逻辑**：

```dart
    try {
      await _bleScanner!.startScan(
        timeout: const Duration(seconds: 15),
      );
      // M27 v2 修复：startScan 在扫描开始时即返回，需显式等待扫描结束
      // 否则"未找到"toast 会立即误弹（扫描才刚开始）
      await FlutterBluePlus.isScanning.where((v) => v == false).first;
    } catch (e) {
      debugPrint('BLE 扫描启动失败: $e');
      if (mounted) {
        setState(() => _bleState = _BleState.error);
      }
    }

    // 扫描真正结束后如未捕获，回到 idle
    if (mounted && _bleState == _BleState.scanning) {
      setState(() => _bleState = _BleState.idle);
      if (!mounted) return;
      showAppToast(context, '未找到体重秤，请确认秤已开机');
    }
```

- [ ] **Step 2: 新增系统定位开关检查**

在 `_enableBleSync` 方法（L103-135）的权限请求之后、`_startBleScan` 调用之前，加系统定位检查：

```dart
    // 4. 权限 OK → 标记已开启
    if (!mounted) return;
    setState(() => _bleEnabled = true);

    // M27 v2：系统定位开关检查（华为系 HarmonyOS/EMUI 强依赖）
    final locationServiceStatus = await Permission.location.serviceStatus;
    if (!locationServiceStatus.isGranted) {
      if (!mounted) return;
      showAppToast(context, '请先开启系统定位开关（蓝牙扫描需要）');
      await openAppSettings();
      return;
    }

    await _startBleScan();
```

- [ ] **Step 3: 新增 30秒短窗冷却**

修改 `_startBleScan` 的冷却逻辑（L139-147）：

```dart
    // 扫描冷却：5分钟/3次（MIUI 熔断）+ 30秒/4次（AOSP 节流）
    final now = DateTime.now();
    _scanTimestamps.removeWhere((t) => now.difference(t).inMinutes >= 5);
    if (_scanTimestamps.length >= 3) {
      if (!mounted) return;
      showAppToast(context, '5分钟内扫描次数过多，请稍后再试');
      return;
    }
    // M27 v2：30秒短窗（AOSP 5次/30秒 节流保护）
    final recentCount =
        _scanTimestamps.where((t) => now.difference(t).inSeconds < 30).length;
    if (recentCount >= 4) {
      if (!mounted) return;
      showAppToast(context, '扫描过于频繁，请稍后再试');
      return;
    }
    _scanTimestamps.add(now);
```

- [ ] **Step 4: turnOn 限 Android**

修改 L152-153：

```dart
      // 蓝牙关闭 → Android 主动弹系统对话框（iOS 无此 API）
      if (Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {
          if (!mounted) return;
          setState(() => _bleState = _BleState.error);
          return;
        }
      } else {
        if (!mounted) return;
        setState(() => _bleState = _BleState.error);
        showAppToast(context, '请开启蓝牙');
        return;
      }
```

文件顶部加 import：

```dart
import 'dart:io' show Platform;
```

- [ ] **Step 5: v2 impedance 捕获时机 + 暂存**

新增状态字段（在 class 顶部 _bleState 等字段附近）：

```dart
  // M27 v2：v2 协议阻抗捕获时机
  MiScaleMeasurement? _pendingStabilized; // v2 稳定但阻抗未完成时暂存
  double? _pendingBodyFat;                 // 捕获时算好的体脂率
  int? _pendingImpedance;                  // 捕获时的阻抗值
```

修改 `_onMeasurement` 方法（L214-227）支持 v2 impedance 捕获时机：

```dart
  /// M27：收到有效测量值 → 预填输入框
  void _onMeasurement(MiScaleMeasurement m) {
    if (!mounted) return;

    // M27 v2：v2 协议优先等 measurementComplete（拿到 impedance）
    // v1 协议 measurementComplete 恒 false，直接用 stabilized
    final isV2WithImpedance = m.measurementComplete || m.impedance != null;
    if (!isV2WithImpedance && m.isStabilized) {
      // v2 稳定但阻抗未完成：暂存，继续扫描等 impedance
      // 超时（15s）未拿到 impedance 则用此帧兜底
      _pendingStabilized = m;
      return;
    }

    _handleCapture(m);
  }

  /// M27 v2：处理捕获（计算体脂率 + 预填 + 停止扫描）
  void _handleCapture(MiScaleMeasurement m) {
    // 计算体脂率（需 profile 的性别/年龄/身高，异步获取）
    _computeBodyFatAndCapture(m);
  }

  Future<void> _computeBodyFatAndCapture(MiScaleMeasurement m) async {
    double? bodyFat;
    if (m.impedance != null) {
      try {
        final profileRepo =
            await ref.read(recognize.profileRepoProvider.future);
        final profile = await profileRepo.get();
        final isMale = profile.gender == 'male';
        bodyFat = BodyFatCalculator.calcBodyFat(
          isMale: isMale,
          age: profile.age,
          heightCm: profile.heightCm,
          weightKg: m.weightKg,
          impedance: m.impedance!.toDouble(),
        );
      } catch (e) {
        debugPrint('体脂率计算失败: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _weightCtrl.text = m.weightKg.toStringAsFixed(1);
      _weightError = null;
      _bleState = _BleState.captured;
      _pendingBodyFat = bodyFat;
      _pendingImpedance = m.impedance;
      _dirty = true;
    });
    // 停止扫描（已捕获，省电）
    _bleScanner?.stopScan();

    // toast（impedance 无效只显示体重）
    final msg = bodyFat != null
        ? '已捕获 ${m.weightKg.toStringAsFixed(1)} kg，体脂 ${bodyFat.toStringAsFixed(1)}%'
        : '已捕获 ${m.weightKg.toStringAsFixed(1)} kg，请确认';
    showAppToast(context, msg);
  }
```

修改扫描超时逻辑（_startBleScan 末尾"未找到"toast 处），加 _pendingStabilized 兜底：

```dart
    // 扫描真正结束后如未捕获，检查 _pendingStabilized 兜底
    if (mounted && _bleState == _BleState.scanning) {
      if (_pendingStabilized != null) {
        // v2 超时未拿到 impedance，用 stabilized 帧兜底（只有 weight）
        _handleCapture(_pendingStabilized!);
        _pendingStabilized = null;
      } else {
        setState(() => _bleState = _BleState.idle);
        if (!mounted) return;
        showAppToast(context, '未找到体重秤，请确认秤已开机');
      }
    }
```

加 import（文件顶部）：

```dart
import '../../nutrition/body_fat_calculator.dart';
```

- [ ] **Step 6: 记录卡片 + tooltip 显示体脂率**

找到 `_buildWeightTile` 方法，修改 subtitle 显示体脂率：

```dart
  Widget _buildWeightTile(WeightLog log) {
    // M27 v2：有体脂率显示"体重 · 体脂X%"
    final subtitle = log.bodyFatPct != null
        ? '${log.weightKg.toStringAsFixed(1)} kg · 体脂 ${log.bodyFatPct!.toStringAsFixed(1)}%'
        : '${log.weightKg.toStringAsFixed(1)} kg';
    // ... 其余 ListTile 逻辑用 subtitle ...
  }
```

注意：需读取 _buildWeightTile 完整实现，保留原有日期/编辑/删除逻辑，只改 subtitle 文本。

找到图表 tooltip 的 `getTooltipItems`（约 L296-314），加体脂率显示：

```dart
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    final idx = spot.spotIndex;
                    final log = _logs[idx];
                    // M27 v2：有体脂率加到 tooltip
                    final bodyFatText = log.bodyFatPct != null
                        ? '\n体脂 ${log.bodyFatPct!.toStringAsFixed(1)}%'
                        : '';
                    final valueText = spot.barIndex == 0
                        ? '${_dailyCalories[log.date]?.round() ?? 0} kcal'
                        : '${log.weightKg.toStringAsFixed(1)} kg$bodyFatText';
                    return LineTooltipItem(
                      '${log.date}\n$valueText',
                      TextStyle(
                        color: cs.onInverseSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    );
                  }).toList();
                },
```

- [ ] **Step 7: _save() 同步 profile bodyFatPct + formula**

找到 `_save` 方法（约 L613+），修改写库逻辑。需读取完整 _save 方法。

在 `await weightRepo.insert(...)` 处加 impedance + bodyFatPercent：

```dart
    // 1. 写 weight_log（M27 v2：含 impedance + bodyFatPct）
    await weightRepo.insert(
      formatYmd(DateTime.now()),
      weight,
      impedance: _pendingImpedance?.toDouble(),
      bodyFatPercent: _pendingBodyFat,
    );
```

注意：现有 insert 签名是 `insert({required String date, required double weightKg})`，Task 4 已改为支持命名参数 `insert({required date, required weightKg, impedance, bodyFatPercent})`。但当前 weight_page 调用可能是 `insert(date, weight)` 位置参数。需确认调用方式与 Task 4 改后的签名一致（命名参数）。

在 `await profileRepo.update(...)` 处加 bodyFatPct + formula + tdeeAdjustmentKcal 重置：

```dart
    // 2. 更新 profile（M27 v2：weightKg + bodyFatPct + formula 联动）
    final oldProfile = await profileRepo.get();
    final oldFormula = oldProfile.formula;
    final hasBodyFat = _pendingBodyFat != null && _pendingBodyFat! > 0;
    final newFormula = hasBodyFat ? 'katch' : 'mifflin';
    final formulaChanged = oldFormula != newFormula;

    await profileRepo.update(
      weightKg: weight,
      bodyFatPct: _pendingBodyFat,
      formula: newFormula,
      // formula 切换时重置 tdeeAdjustmentKcal（防跨公式污染）
      tdeeAdjustmentKcal: formulaChanged ? 0 : null,
      // ... 保留原有其他字段 ...
    );
    // bodyFatPct 显式置空（用户清空体脂率时）
    if (_pendingBodyFat == null) {
      await profileRepo.clearBodyFatPct();
    }
```

在 _save 末尾清理 _pending* 字段：

```dart
    // M27 v2：清理捕获暂存
    _pendingBodyFat = null;
    _pendingImpedance = null;
    _pendingStabilized = null;
```

- [ ] **Step 8: flutter analyze**

```bash
flutter analyze 2>&1 | tail -3
```

预期：No issues found.

- [ ] **Step 9: 全量测试回归**

```bash
flutter test 2>&1 | tail -3
```

预期：全 PASS，0 回归。

- [ ] **Step 10: 提交**

```bash
git add lib/features/weight/weight_page.dart
git commit -m "feat(M27v2): weight_page 接入 v2（impedance 捕获时机 + startScan 时序修复 + 系统定位 + 30s 冷却 + 体脂率 UI + _save 同步 profile）"
```

---

## Task 8: 全量验证 + 版本 bump + HANDOFF

**Files:**
- Modify: `pubspec.yaml`
- Modify: `CHANGELOG.md`
- Modify: `HANDOFF.md`

- [ ] **Step 1: 全量验证**

```bash
export PATH=/tmp/flutter/bin:$PATH
flutter analyze 2>&1 | tail -3
flutter test 2>&1 | tail -5
```

预期：analyze No issues；test 全 PASS（含新增 BodyFatCalculator 14 + v2 parser 8 + formula switch 5 + tdee branch 3 = 30 个新测试），0 回归。

- [ ] **Step 2: 6+1 硬约束核查**

逐一确认：
1. `android/app/build.gradle.kts` isMinifyEnabled=false + isShrinkResources=false ✓（未触碰）
2. meal_log.food_item_id 非空外键 ✓（未触碰）
3. AI 三路径 ✓（未触碰）
4. per100g 反算 ✓（未触碰）
5. SecureConfigStore ✓（未触碰）
6. initSentryAndRunApp ✓（未触碰）
7. minSdk=31 ✓（未触碰）

- [ ] **Step 3: bump 版本**

修改 `pubspec.yaml`：

```yaml
version: 0.32.0+45
```

- [ ] **Step 4: 更新 CHANGELOG.md**

在 CHANGELOG.md 顶部新增：

```markdown
## [v0.32.0] - 2026-07-08

### M27 v2 小米体脂秤2 + 体脂率 + BMR 自动升级

#### 新增
- 支持小米体脂秤2（XMTZC05HM）v2 协议（0x181B/13字节，保留 v1 兼容）
- 体脂率自动计算（openScale MiScaleLib 逆向 BIA 公式，双源验证）
- BMR 自动升级：有体脂率用 Katch-McArdle（对精瘦人群更准），无则 Mifflin
- 体重记录卡片 + 图表 tooltip 显示体脂率

#### 修复
- startScan 时序 bug（flutter_blue_plus startScan 开始时返回非结束时，"未找到"toast 误弹）
- 国产 ROM 系统定位开关检查（华为系 HarmonyOS/EMUI 静默无结果）
- AOSP 30秒/5次 扫描节流保护（新增 30秒短窗冷却）
- scanner _controller isClosed 守卫（防 dispose 竞态崩溃）
- v2 impedance 捕获时机（优先等 measurementComplete，超时 stabilized 兜底）
- formula 切换时重置 tdeeAdjustmentKcal（防跨公式污染）
- bodyFatPct 显式置空支持（clearBodyFatPct 方法）

#### 数据层
- weight_log 表加 impedance + bodyFatPct 字段（schemaVersion v4→v5）
- backup 导入导出支持新字段（兼容旧备份）
```

- [ ] **Step 5: 更新 HANDOFF.md**

读取 HANDOFF.md，更新"当前状态"段：

```markdown
## 2. 当前状态

**版本**：v0.32.0+45（M27 v2 已实现待发版）
**HEAD**：待 push 的最后 commit

### M27 v2 已完成
- BodyFatCalculator（openScale BIA 公式，14 测试）
- MiScaleParser parseV2（XMTZC05HM 13字节，8 测试）
- MiScaleScanner 双 UUID 路由 + isClosed 守卫
- weight_log 加 impedance + bodyFatPct（schemaVersion v5）
- ProfileRepository clearBodyFatPct
- BMR 自动升级（有体脂率用 Katch）+ formula 切换重置 tdeeAdjustmentKcal
- tdee_calibrator 读 formula 分支
- weight_page v2 捕获时机 + startScan 时序修复 + 系统定位 + 30s 冷却 + 体脂率 UI
- 全量测试 0 回归

### 待发版
- push（不打 tag 不发 release，等用户指令）
```

- [ ] **Step 6: 提交**

```bash
git add pubspec.yaml CHANGELOG.md HANDOFF.md
git commit -m "chore(M27v2): bump v0.32.0+45 + HANDOFF/CHANGELOG"
```

---

## Task 9: push（不打 tag 不发 release）

- [ ] **Step 1: 确认 git 状态**

```bash
git status
git log --oneline -10
```

预期：clean，9 个新 commit（Task 1-8）。

- [ ] **Step 2: push**

```bash
git push origin trae/agent-wX1X6Q
```

预期：push 成功。

- [ ] **Step 3: 最终确认**

```bash
git log --oneline -10
```

确认所有 commit 已 push。
