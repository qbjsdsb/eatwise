# 小米体脂秤2（XMTZC05HM）v2 协议扩展 + 体脂率 + BMR 自动升级 设计

> 本设计是 M27 蓝牙体重秤同步的扩展：从只支持小米体重秤2（XMTZC04HM，v1 协议）扩展到同时支持小米体脂秤2（XMTZC05HM，v2 协议），并新增体脂率计算 + BMR 公式自动升级。

**版本**：v1.0
**日期**：2026-07-08
**前置**：M27 v1 已实现并发布（v0.31.0），本文档基于现有代码扩展

---

## 1. 背景与设备确认

### 1.1 设备型号澄清（极易混淆）

用户实际购买的是 **小米体脂秤2（Mi Body Composition Scale 2）**，型号 **XMTZC05HM**，2019 年发售，广播名 **MIBFS**。与 M27 v1 已支持的 **小米体重秤2（Mi Smart Scale 2，XMTZC04HM，广播名 MI_SCALE2）** 是**不同产品，协议不兼容**。

| 型号 | 产品名 | 广播名 | 类型 | 协议 |
|---|---|---|---|---|
| XMTZC04HM | Mi Smart Scale 2（体重秤2） | MI_SCALE2 | 纯体重 | v1（已实现） |
| XMTZC02HM | Mi Body Composition Scale（体脂秤1代） | MIBCS | 体脂 | v2 |
| **XMTZC05HM** | Mi Body Composition Scale 2（体脂秤2） | **MIBFS** | 体脂 | **v2** |

XMTZC05HM 与 XMTZC02HM 同协议（v2），仅硬件代次不同。证据：Theengs decoder "First (MIBCS) and second (MIBFS) version"；BeMacized Dart 实现匹配 `name == 'MIBFS'`；ble_monitor 两者共用 miscale parser。

### 1.2 v1 vs v2 协议对比

| 项目 | v1（XMTZC04HM） | v2（XMTZC05HM） |
|---|---|---|
| Service Data UUID | 0x181D（Weight Scale Service） | **0x181B**（Body Composition Service） |
| Payload 长度 | 10 字节 | **13 字节** |
| Control byte 数 | 1 个（byte0） | **2 个**（byte0 + byte1） |
| lbs 单位 bit | byte0 bit0 | byte0 bit0（同） |
| jin 单位 bit | byte0 bit4 | **byte1 bit6**（位置变了） |
| stabilized bit | byte0 bit5 | **byte1 bit5**（位置变了） |
| removed bit | byte0 bit7 | **byte1 bit7**（位置变了） |
| weight raw 位置 | byte 1-2（小端） | **byte 11-12**（小端） |
| 时间戳 | byte 3-9 | byte 2-8 |
| impedance | 无 | **byte 9-10**（小端，byte1 bit1=1 时有效） |
| measurementComplete | 无 | **byte1 bit1**（阻抗测量完成） |
| kg 换算 | raw/200 | raw/200（同） |
| lbs 换算 | raw/100×0.453592 | raw/100×0.453592（同） |
| jin 换算 | raw/100×0.5 | raw/100×0.5（同） |
| isEffective | stabilized && !removed | stabilized && !removed（同形，bit 位置不同） |
| 被动扫描可拿 | 体重 | 体重 + 阻抗（广播内含） |

### 1.3 v2 payload 布局（13 字节，小端）

| byte | 含义 | 说明 |
|---|---|---|
| 0 | control byte 0 | bit0=lbs(1)/kg(0)；实测取值 0x02(kg)/0x03(lbs) |
| 1 | control byte 1 | bit1=measurementComplete(阻抗就绪)；bit5=weightStabilized；bit6=catty(jin)；bit7=weightRemoved |
| 2-3 | year（小端 uint16） | 如 0x07E8=2024 |
| 4 | month | |
| 5 | day | |
| 6 | hour | |
| 7 | minute | |
| 8 | second | |
| 9-10 | impedance（小端 uint16，Ω） | 仅 byte1 bit1=1 时有效；范围 1-2999 |
| 11-12 | weight raw（小端 uint16） | kg=raw/200，jin=raw/100×0.5，lbs=raw/100×0.453592 |

### 1.4 v2 测量时序（BeMacized 状态机实证）

1. 上秤 → byte1 全 0（measuring，体重跳动）
2. 体重稳定 → byte1 bit5=1（stabilized，体重锁定，**阻抗仍在测**）
3. BIA 完成 → byte1 bit1=1（measurementComplete，**此刻 impedance 字段才有效**）
4. 下秤 → byte1 bit7=1（removed）

**关键**：weight 稳定（bit5=1）时 impedance 可能尚未完成（bit1=0）。若此时就判定有效并停止扫描，impedance 永远拿不到。

---

## 2. 架构

### 2.1 组件图

```
┌─────────────────────────────────────────────────────────────┐
│                    weight_page.dart                          │
│  ┌──────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │ BLE UI (4态)  │  │ 捕获预填+toast   │  │ _save() 同步  │  │
│  │ idle/scan/   │  │ weight+bodyFat   │  │ weight_log +  │  │
│  │ captured/err │  │                  │  │ profile       │  │
│  └──────┬───────┘  └────────┬─────────┘  └───────┬───────┘  │
└─────────┼───────────────────┼─────────────────────┼──────────┘
          │                   │                     │
          ▼                   ▼                     ▼
┌─────────────────┐  ┌─────────────────┐  ┌──────────────────┐
│ MiScaleScanner  │  │ BodyFatCalculator│  │ WeightLogRepo    │
│ (BLE 被动扫描)  │  │ (openScale BIA) │  │ + ProfileRepo    │
│ 双UUID路由      │  │                 │  │                  │
└────────┬────────┘  └─────────────────┘  └──────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ MiScaleParser               │
│ parseV1 (0x181D/10B) ← 保留 │
│ parseV2 (0x181B/13B) ← 新增 │
└─────────────────────────────┘
```

### 2.2 数据流

```
BLE 扫描 → parseV2 → MiScaleMeasurement(weightKg, impedance, measurementComplete)
  → BodyFatCalculator.calcBodyFat(profile.gender/age/height + weight + impedance)
  → 预填 _weightCtrl + 暂存 _pendingBodyFat + _pendingImpedance
  → 用户点"记录"
  → _save():
      1. 写 weight_log(weightKg, impedance, bodyFatPct)
      2. 更新 profile(weightKg, bodyFatPct, formula)
         - 有 bodyFatPct → formula='katch'
         - 无 bodyFatPct → formula='mifflin'
         - formula 切换 → 重置 tdeeAdjustmentKcal=0 + toast 提示
      3. RefreshBus.notify() → dashboard 宏量目标用新 profile 重算（Katch BMR 生效）
```

### 2.3 状态机（weight_page BLE 同步）

```
idle ──开启同步──► scanning ──捕获(weight stabilized)──► captured
  ▲                  │                                         │
  │                  ├──超时15s/未找到──► idle (toast)         │
  │                  ├──用户停止──► idle                        │
  │                  ├──app后台──► idle (stopScan)              │
  │                  ├──权限拒绝──► error                       │
  │                  └──蓝牙关闭──► error                       │
  │                                                            │
  └────────────────────用户点"记录"写库────────────────────────┘
                      (captured → idle)
```

---

## 3. 协议层改造

### 3.1 MiScaleParser（mi_scale_parser.dart）

**保留 parseV1**（v1 兼容），**新增 parseV2**：

```dart
class MiScaleParser {
  MiScaleParser._();

  /// v1: 小米体重秤2（XMTZC04HM），UUID 0x181D，10 字节
  static MiScaleMeasurement? parseV1(List<int> payload) { /* 现有代码不动 */ }

  /// v2: 小米体脂秤2（XMTZC05HM）/ 体脂秤1代（XMTZC02HM），UUID 0x181B，13 字节
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
      payload[0], payload[1],           // control bytes
      payload[9], payload[10],          // impedance
      payload[11], payload[12],         // weight raw
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
```

### 3.2 MiScaleMeasurement 模型扩展

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

### 3.3 MiScaleScanner（mi_scale_scanner.dart）双 UUID 路由

```dart
class MiScaleScanner {
  static final Guid _v1Uuid = Guid('181D'); // 体重秤2 XMTZC04HM
  static final Guid _v2Uuid = Guid('181B'); // 体脂秤2 XMTZC05HM / 体脂秤1代 XMTZC02HM

  void _handleScanResults(ScanResult r) {
    final sd = r.serviceData;
    MiScaleMeasurement? m;

    // 双 UUID 路由
    final v1Payload = sd[_v1Uuid];
    final v2Payload = sd[_v2Uuid];
    if (v1Payload != null && v1Payload.length == 10) {
      m = MiScaleParser.parseV1(v1Payload);
    } else if (v2Payload != null && v2Payload.length == 13) {
      m = MiScaleParser.parseV2(v2Payload);
    }
    if (m == null) return;

    // isClosed 守卫（防 dispose 竞态崩溃）
    if (_controller.isClosed) return;

    // packetId 去重
    if (_lastPacketId == m.packetId) return;
    _lastPacketId = m.packetId;

    _controller.add(m);
  }
}
```

### 3.4 startScan 时序修复（P0 严重 bug）

**问题**：flutter_blue_plus 的 `await startScan(timeout:)` 在扫描**开始**时即返回，不是结束时。当前代码 await 后立即判断"未找到"会误弹 toast。

**修复**：

```dart
// 修复前（错误）
await _bleScanner!.startScan(timeout: const Duration(seconds: 15));
if (mounted && _bleState == _BleState.scanning) {
  setState(() => _bleState = _BleState.idle);
  showAppToast(context, '未找到体重秤，请确认秤已开机'); // 立即误弹
}

// 修复后（正确）
await _bleScanner!.startScan(timeout: const Duration(seconds: 15));
// 等待扫描真正结束（startScan 在扫描开始时即返回，需显式等待结束）
await FlutterBluePlus.isScanning.where((v) => v == false).first;
if (mounted && _bleState == _BleState.scanning) {
  setState(() => _bleState = _BleState.idle);
  showAppToast(context, '未找到体重秤，请确认秤已开机');
}
```

**注意**：`_onMeasurement` 中调 `stopScan()` 会提前结束扫描，此时 isScanning 变 false，await 返回，但 _bleState 已是 captured 不会误判 idle ✓

---

## 4. 数据层改造

### 4.1 weight_log 表加字段（schemaVersion 4→5）

```dart
// weight_log_table.dart
class WeightLogTable extends Table {
  IntColumn get id => integer()();
  TextColumn get date => text()(); // YYYY-MM-DD
  RealColumn get weightKg => real()();
  // 新增字段（M27 v2 扩展）
  RealColumn get impedance => real().nullable()();    // 原始阻抗值 Ω
  RealColumn get bodyFatPct => real().nullable()();   // 体脂率 %
  
  @override
  Set<Column> get primaryKey => {id};
}
```

### 4.2 database.dart migration v4→v5

```dart
@override
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (m) => m.createAll(),
  onUpgrade: (m, from, to) async {
    if (from < 2) { /* ... 现有 ... */ }
    if (from < 3) { /* ... 现有 ... */ }
    if (from < 4) { /* ... 现有 ... */ }
    if (from < 5) {
      // M27 v2：weight_log 加 impedance + bodyFatPct
      await m.addColumn(weightLogTable, weightLogTable.impedance);
      await m.addColumn(weightLogTable, weightLogTable.bodyFatPct);
    }
  },
);
```

### 4.3 WeightLogRepository 扩展

```dart
class WeightLogRepository {
  // insert 支持新字段
  Future<int> insert(String date, double weightKg, {
    double? impedance,
    double? bodyFatPercent,
  }) async {
    return into(weightLogTable).insert(WeightLogCompanion(
      date: Value(date),
      weightKg: Value(weightKg),
      impedance: impedance == null ? const Value.absent() : Value(impedance),
      bodyFatPct: bodyFatPercent == null ? const Value.absent() : Value(bodyFatPercent),
    ));
  }

  // update 支持新字段
  Future<bool> update(int id, {
    double? weightKg,
    double? impedance,
    double? bodyFatPercent,
  }) async { /* ... */ }
}
```

### 4.4 backup 导入导出

```dart
// json_exporter.dart
// WeightLog JSON 加 impedance + bodyFatPct
'impedance': log.impedance,
'bodyFatPct': log.bodyFatPct,

// json_importer.dart
// 读 impedance + bodyFatPct（兼容旧备份无此字段）
impedance: (json['impedance'] as num?)?.toDouble(),
bodyFatPct: (json['bodyFatPct'] as num?)?.toDouble(),
```

---

## 5. 业务层：BodyFatCalculator

### 5.1 公式（openScale MiScaleLib 逆向，双源交叉验证）

基于 openScale `MiScaleLib.kt`（Kotlin）+ miscale PyPI 包（prototux 原始 Python 逆向），两者逐字节一致，3 个回归夹具验证（误差 <1e-5）。

**第一步：LBM 系数**
```
lbmCoeff = 0.0009058 × height² + 0.32 × weight + 12.226 − 0.0068 × impedance − 0.0542 × age
```

**第二步：lbmSub（性别 + 年龄扣除常数）**
- 男性（任意年龄）：0.8
- 女性，年龄 ≤ 49：9.25
- 女性，年龄 > 49：7.25

**第三步：coeff（性别 + 体重 + 身高校正）**
- 男性，weight < 61：0.98
- 男性，weight ≥ 61：1.0
- 女性，weight > 60：0.96（height > 160 则 ×1.03 = 0.9888）
- 女性，weight < 50：1.02（height > 160 则 ×1.03 = 1.0506）
- 女性，50 ≤ weight ≤ 60：1.0

**第四步：体脂率**
```
bodyFat% = (1 − ((lbmCoeff − lbmSub) × coeff) / weight) × 100
```

**第五步：clamp**
- bodyFat > 63 → 75（openScale 哨兵值）
- bodyFat < 5 → 5（miscale 下限）
- bodyFat > 75 → 75（miscale 上限）

### 5.2 Dart 实现

```dart
// lib/nutrition/body_fat_calculator.dart
class BodyFatCalculator {
  BodyFatCalculator._();

  /// 计算体脂率百分比。impedance 无效返回 null。
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
    double lbmCoeff = (heightCm * 9.058 / 100.0) * (heightCm / 100.0);
    lbmCoeff += weightKg * 0.32 + 12.226;
    lbmCoeff -= impedance * 0.0068;
    lbmCoeff -= age * 0.0542;

    // 第二步：lbmSub
    double lbmSub;
    if (!isMale && age <= 49) {
      lbmSub = 9.25;
    } else if (!isMale && age > 49) {
      lbmSub = 7.25;
    } else {
      lbmSub = 0.8;
    }

    // 第三步：coeff
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
    double bodyFat = (1.0 - (((lbmCoeff - lbmSub) * coeff) / weightKg)) * 100.0;

    // 第五步：clamp
    if (bodyFat > 63.0) bodyFat = 75.0;
    if (bodyFat < 5.0) bodyFat = 5.0;
    if (bodyFat > 75.0) bodyFat = 75.0;
    return bodyFat;
  }
}
```

### 5.3 真实样本验证（openScale 官方夹具）

| 样本 | 性别 | 年龄 | 身高 | 体重 | 阻抗 | 期望体脂率 | 实算 |
|---|---|---|---|---|---|---|---|
| 1 | 男 | 30 | 180 | 80 | 500 | 23.32% | 23.3151% ✓ |
| 2 | 女 | 28 | 165 | 60 | 520 | 30.36% | 30.3620% ✓ |
| 3 | 男 | 45 | 175 | 95 | 430 | 32.42% | 32.4178% ✓ |

---

## 6. 业务层：BMR 自动升级

### 6.1 核心改动：首次让 profile.formula 字段产生语义

**现状**：`profile.formula` 是"只写不读"死字段，`bmrKatch()` 从未被调用，profile_page L528 始终硬编码 'mifflin'。

**改动**：有 bodyFatPct 时自动用 Katch，无则 Mifflin，formula 字段同步写入实际使用的公式。

### 6.2 profile_page._save() 改动

```dart
// 修复前（L455-461）
// 重算目标（MVP：始终用 mifflin...）
final bmr = NutritionCalculator.bmrMifflin(
  weightKg: weight, heightCm: height, age: age, gender: genderEnum,
);

// 修复后
// 有体脂率 → Katch-McArdle（基于瘦体重，对精瘦人群更准）；
// 无 → Mifflin-St Jeor（向后兼容）。
final hasBodyFat = bodyFat != null && bodyFat > 0;
final bmr = hasBodyFat
    ? NutritionCalculator.bmrKatch(weightKg: weight, bodyFatPct: bodyFat!)
    : NutritionCalculator.bmrMifflin(
        weightKg: weight, heightCm: height, age: age, gender: genderEnum);
final formula = hasBodyFat ? 'katch' : 'mifflin';
```

```dart
// 修复前（L528）
formula: 'mifflin',

// 修复后
formula: formula,
```

### 6.3 P0 修复：formula 切换时重置 tdeeAdjustmentKcal

**问题**：老用户 mifflin 时期累积的 `tdeeAdjustmentKcal` 是补偿 mifflin 系统性偏差的。切 katch 后 katch 已修正偏差，旧补偿值会"双重修正"导致目标过激。

**修复**：profile_page._save() 中检测 formula 是否切换，切换则重置：

```dart
// 读取旧 formula（需在 update 前读）
final oldProfile = await _profileRepo.get();
final oldFormula = oldProfile?.formula ?? 'mifflin';
final formulaChanged = oldFormula != formula;

// update profile
await _profileRepo.update(
  // ... 其他字段 ...
  formula: formula,
  bodyFatPct: bodyFat,
  // formula 切换时重置 tdeeAdjustmentKcal（防跨公式污染）
  tdeeAdjustmentKcal: formulaChanged ? 0.0 : null, // null=不更新
);

// formula 切换时 toast 提示
if (formulaChanged) {
  showAppToast(context, '已切换到 ${formula == 'katch' ? 'Katch' : 'Mifflin'} 公式，'
      'TDEE 校准累积值已重置，将在下次记录体重后重新校准');
}
```

### 6.4 P1 修复：bodyFatPct 显式置空

**问题**：ProfileRepository.update 的 `bodyFatPct: null` 被映射为 `Value.absent()`（不更新），用户清空体脂率输入框后 DB 仍保留旧值，formula 不会回退 mifflin。

**修复**：新增 `ProfileRepository.clearBodyFatPct()` 方法：

```dart
// profile_repository.dart
class ProfileRepository {
  // ... 现有方法 ...

  /// 显式置空 bodyFatPct（M27 v2：用户清空体脂率时调用）
  /// 因 update() 的 null=不更新设计无法置空，需专门方法。
  Future<void> clearBodyFatPct() async {
    await _db.managers.profileRecords.update(
      (row) => row(bodyFatPct: const Value(null)),
    );
    // 或用 customStatement: UPDATE profiles SET body_fat_pct = NULL
  }
}
```

profile_page 清空体脂率时调用：

```dart
// profile_page._save()
if (bodyFat == null) {
  await _profileRepo.clearBodyFatPct();
}
```

### 6.5 tdee_calibrator.dart 改动

```dart
// 修复前（L142）
final bmr = NutritionCalculator.bmrMifflin(
  weightKg: profile.weightKg,
  heightCm: profile.heightCm,
  age: age,
  gender: genderEnum,
);

// 修复后：读 profile.formula 分支
final bmr = (profile.formula == 'katch' && profile.bodyFatPct != null && profile.bodyFatPct! > 0)
    ? NutritionCalculator.bmrKatch(weightKg: profile.weightKg, bodyFatPct: profile.bodyFatPct!)
    : NutritionCalculator.bmrMifflin(
        weightKg: profile.weightKg,
        heightCm: profile.heightCm,
        age: age,
        gender: genderEnum,
      );
```

**老用户安全**：老用户 formula='mifflin'，即使有 bodyFatPct 也走 mifflin 分支，行为不变。只有用户主动保存档案（触发 formula='katch' 写入）才切换。

---

## 7. UI 层改造（weight_page.dart）

### 7.1 v2 impedance 捕获时机

**问题**：v2 协议 weight 稳定（bit5=1）时 impedance 可能尚未完成（bit1=0）。若此时就判定有效并停止扫描，impedance 永远拿不到。

**策略**：优先等 measurementComplete（拿到完整 weight+impedance），超时未完成才用 stabilized 兜底。

```dart
void _onMeasurement(MiScaleMeasurement m) {
  if (!m.isEffective) return; // 非有效包（未稳定/已下秤）忽略

  // v2：优先等 measurementComplete（拿到 impedance）
  // v1：measurementComplete 恒 false，直接用 stabilized
  if (m.measurementComplete || m.impedance != null || !_isV2Scale) {
    // 完整捕获（v2 阻抗完成，或 v1 稳定）
    _handleCapture(m);
  } else if (m.isStabilized) {
    // v2 稳定但阻抗未完成：暂存 weight，继续扫描等 impedance
    // 如果扫描超时（15s）还没拿到 impedance，用此 stabilized 帧兜底
    _pendingStabilized = m;
  }
}

void _onScanTimeout() {
  // 扫描超时：若有 _pendingStabilized，用它兜底（只有 weight 没 impedance）
  if (_pendingStabilized != null) {
    _handleCapture(_pendingStabilized!);
  } else {
    // 真的没找到
    showAppToast(context, '未找到体重秤，请确认秤已开机');
  }
}
```

### 7.2 国产 ROM 系统定位开关检查

```dart
Future<void> _enableBleSync() async {
  // ... 现有权限请求 ...

  // 新增：系统定位开关检查（华为系强依赖）
  final locationServiceEnabled = await Permission.location.serviceStatus;
  if (!locationServiceEnabled.isGranted) {
    if (mounted) {
      showAppToast(context, '请先开启系统定位开关（蓝牙扫描需要）');
      await openAppSettings(); // 跳转系统设置
    }
    return;
  }

  // ... 继续扫描 ...
}
```

### 7.3 30秒短窗冷却（防 AOSP 节流）

```dart
// 修复前：只防 5分钟/3次（MIUI）
final now = DateTime.now();
_scanTimestamps.removeWhere((t) => now.difference(t).inMinutes >= 5);
if (_scanTimestamps.length >= 3) {
  showAppToast(context, '扫描过于频繁，请稍后再试');
  return;
}

// 修复后：5分钟/3次 + 30秒/4次 双窗口
final now = DateTime.now();
_scanTimestamps.removeWhere((t) => now.difference(t).inMinutes >= 5);
if (_scanTimestamps.length >= 3) {
  showAppToast(context, '5分钟内扫描次数过多，请稍后再试');
  return;
}
// 新增 30秒窗口（AOSP 5次/30秒 节流）
final recentCount = _scanTimestamps.where((t) => now.difference(t).inSeconds < 30).length;
if (recentCount >= 4) {
  showAppToast(context, '扫描过于频繁，请稍后再试');
  return;
}
_scanTimestamps.add(now);
```

### 7.4 turnOn 限 Android

```dart
// 修复前
await FlutterBluePlus.turnOn();

// 修复后
if (Platform.isAndroid) {
  await FlutterBluePlus.turnOn();
}
```

### 7.5 捕获 toast + 卡片 + tooltip

```dart
// 捕获 toast（impedance 无效只显示体重）
void _handleCapture(MiScaleMeasurement m) {
  final bodyFat = _pendingBodyFat; // 由 BodyFatCalculator 算出
  final msg = bodyFat != null
      ? '已捕获 ${m.weightKg.toStringAsFixed(1)} kg，体脂 ${bodyFat.toStringAsFixed(1)}%'
      : '已捕获 ${m.weightKg.toStringAsFixed(1)} kg';
  showAppToast(context, msg);
  // ... 预填 _weightCtrl ...
}

// 记录卡片（无体脂只显示体重）
Widget _buildWeightTile(WeightLog log) {
  final subtitle = log.bodyFatPct != null
      ? '${log.weightKg.toStringAsFixed(1)} kg · 体脂 ${log.bodyFatPct!.toStringAsFixed(1)}%'
      : '${log.weightKg.toStringAsFixed(1)} kg';
  // ...
}

// 图表 tooltip（有体脂才显示）
getTooltipItems: (touchedSpots) {
  return touchedSpots.map((spot) {
    final idx = spot.spotIndex;
    final log = _logs[idx];
    final bodyFatText = log.bodyFatPct != null
        ? '\n体脂 ${log.bodyFatPct!.toStringAsFixed(1)}%'
        : '';
    final valueText = spot.barIndex == 0
        ? '${_dailyCalories[log.date]?.round() ?? 0} kcal'
        : '${log.weightKg.toStringAsFixed(1)} kg$bodyFatText';
    return LineTooltipItem('${log.date}\n$valueText', /* ... */);
  }).toList();
},
```

### 7.6 _save() 同步逻辑

```dart
Future<void> _save() async {
  // ... 现有 weightKg 校验 ...

  setState(() => _busy = true);
  try {
    final weightRepo = await ref.read(recognize.weightLogRepoProvider.future);
    final profileRepo = await ref.read(recognize.profileRepoProvider.future);

    // 1. 写 weight_log（含 impedance + bodyFatPct）
    await weightRepo.insert(
      formatYmd(DateTime.now()),
      weight,
      impedance: _pendingImpedance,
      bodyFatPercent: _pendingBodyFat,
    );

    // 2. 更新 profile（weightKg + bodyFatPct + formula）
    final oldProfile = await profileRepo.get();
    final oldFormula = oldProfile?.formula ?? 'mifflin';
    final hasBodyFat = _pendingBodyFat != null && _pendingBodyFat! > 0;
    final newFormula = hasBodyFat ? 'katch' : 'mifflin';
    final formulaChanged = oldFormula != newFormula;

    await profileRepo.update(
      weightKg: weight,
      bodyFatPct: _pendingBodyFat, // null 时 clearBodyFatPct
      formula: newFormula,
      // formula 切换时重置 tdeeAdjustmentKcal
      tdeeAdjustmentKcal: formulaChanged ? 0.0 : null,
    );
    if (_pendingBodyFat == null) {
      await profileRepo.clearBodyFatPct();
    }

    // 3. 重算 dailyCalorieTarget（用新 formula）
    // ... 现有 _recomputeTarget 逻辑，但用 newFormula 选 BMR ...

    // 4. formula 切换提示
    if (formulaChanged && mounted) {
      showAppToast(context, '已切换到 ${newFormula == 'katch' ? 'Katch' : 'Mifflin'} 公式，'
          'TDEE 校准累积值已重置');
    }

    // 5. RefreshBus 通知
    RefreshBus.instance.notify();

    // ... 清理 _pending* + _dirty ...
  } catch (e) {
    // ... 错误处理 ...
  } finally {
    if (mounted) setState(() => _busy = false);
  }
}
```

---

## 8. 错误处理

| 场景 | 处理 |
|---|---|
| 权限拒绝（普通） | toast "请授予蓝牙权限" + 引导到设置 |
| 权限拒绝（永久） | dialog "需要蓝牙权限才能同步体重，去设置开启？" → openAppSettings |
| 蓝牙关闭 | toast "请开启蓝牙" + (Android) turnOn() |
| 系统定位关闭（华为系） | toast "请开启系统定位开关" + openAppSettings |
| 扫描超时（15s 未找到） | toast "未找到体重秤，请确认秤已开机" |
| 扫描冷却（5分钟/3次 或 30秒/4次） | toast "扫描过于频繁，请稍后再试" |
| impedance 无效（提前下秤） | 体脂率 null，只存体重，toast 只显示体重 |
| 体脂率超范围 | clamp [5, 75]% |
| formula 切换 | 重置 tdeeAdjustmentKcal=0 + toast 提示 |
| bodyFatPct 清空 | clearBodyFatPct() + formula 回退 mifflin |
| app 后台 | stopScan + 回 idle（不误弹"未找到"） |
| app 前台恢复 | 自动重新扫描（若之前在 scanning） |

---

## 9. 权限

已有（M27 v1 已声明，无需改）：
- BLUETOOTH_SCAN
- BLUETOOTH_CONNECT
- ACCESS_FINE_LOCATION
- uses-feature bluetooth_le required=false

国产 ROM 适配：
- 不加 neverForLocation（MIUI/HarmonyOS/ColorOS 强依赖 ACCESS_FINE_LOCATION）
- 运行时检查系统定位开关（华为系强依赖）

---

## 10. 依赖

已有（M27 v1 已添加，无需改）：
- flutter_blue_plus: ^2.3.10
- permission_handler: ^12.0.3

---

## 11. 文件结构

### 新增文件
- `lib/nutrition/body_fat_calculator.dart` — openScale BIA 体脂率公式
- `test/nutrition/body_fat_calculator_test.dart` — 3 夹具 + 边界测试
- `test/features/profile_save_formula_switch_test.dart` — formula 切换 + tdee 重置
- `test/nutrition/tdee_calibrator_formula_branch_test.dart` — formula 分支选 BMR

### 修改文件
- `lib/data/bluetooth/mi_scale_parser.dart` — 新增 parseV2 + 模型扩展
- `lib/data/bluetooth/mi_scale_scanner.dart` — 双 UUID 路由 + isClosed 守卫 + onError 日志
- `lib/data/database/tables/weight_log_table.dart` — 加 impedance + bodyFatPct 字段
- `lib/data/database/database.dart` — schemaVersion 4→5 migration
- `lib/data/repositories/weight_log_repository.dart` — insert/update 支持新字段
- `lib/data/repositories/profile_repository.dart` — 新增 clearBodyFatPct()
- `lib/data/backup/json_exporter.dart` — 导出新字段
- `lib/data/backup/json_importer.dart` — 导入新字段（兼容旧备份）
- `lib/features/weight/weight_page.dart` — v2 捕获时机 + 系统定位 + 冷却 + UI + _save 同步
- `lib/features/profile/profile_page.dart` — BMR 自动升级 + formula 切换重置 + clearBodyFatPct
- `lib/nutrition/tdee_calibrator.dart` — 读 formula 分支选 BMR
- `test/mi_scale_parser_test.dart` — 新增 v2 测试
- `test/data/weight_log_repository_test.dart` — 新字段测试（如已存在则追加）

---

## 12. 测试

### 12.1 MiScaleParser v2 TDD（6 hex 样本）

| 样本 | control | 场景 | 预期 |
|---|---|---|---|
| A | 02 A6 | kg stabilized removed complete（下秤包，isEffective=false，impedance=442） | weight=70.70, imp=442, isEffective=false |
| B | 02 20 | kg stabilized 未下秤 阻抗未完成（isEffective=true，impedance=null） | weight=72.50, imp=null, isEffective=true |
| C | 02 22 | kg stabilized+complete 未下秤（理想帧，isEffective=true，impedance=480） | weight=68.30, imp=480, isEffective=true |
| D | 03 20 | lbs stabilized（验单位换算） | weight=72.5747, isEffective=true |
| E | 02 00 | kg 未稳定（抖动，isEffective=false） | weight=70.0, isEffective=false |
| F | 02 60 | jin stabilized（验 byte1 bit6 catty） | weight=72.50, unit='jin', isEffective=true |

### 12.2 BodyFatCalculator TDD（3 openScale 夹具 + 边界）

| 测试 | 输入 | 期望 |
|---|---|---|
| openScale 夹具1 | 男 30 180cm 80kg 500Ω | 23.32% |
| openScale 夹具2 | 女 28 165cm 60kg 520Ω | 30.36% |
| openScale 夹具3 | 男 45 175cm 95kg 430Ω | 32.42% |
| impedance=null | 任何 | null |
| impedance=0 | 任何 | null |
| bodyFat 超范围 | 极端输入 | clamp [5,75] |

### 12.3 BMR 升级测试

| 测试 | 场景 | 期望 |
|---|---|---|
| 有 bodyFatPct 保存 | profile_page 填体脂率 | formula='katch', BMR 用 Katch |
| 无 bodyFatPct 保存 | profile_page 不填体脂率 | formula='mifflin', BMR 用 Mifflin |
| formula 切换 | mifflin→katch | tdeeAdjustmentKcal 重置为 0 |
| formula 未变 | mifflin→mifflin | tdeeAdjustmentKcal 保留 |
| 清空 bodyFatPct | 用户删除体脂率 | bodyFatPct=null, formula='mifflin' |
| tdee_calibrator katch 分支 | formula='katch'+bodyFatPct | 用 bmrKatch 重算 |
| tdee_calibrator mifflin 分支 | formula='mifflin' | 用 bmrMifflin（回归） |

### 12.4 回归保护

- 全量 flutter test：0 回归
- flutter analyze：No issues
- 6+1 硬约束全部满足

---

## 13. YAGNI 清单（明确不做）

- ❌ GATT 连接读历史记录（被动扫描已够）
- ❌ 完整身体成分（肌肉/水分/骨量/内脏脂肪/BMR 秤端值）—— 用户当前只需体脂率
- ❌ 多用户支持（按体重接近度匹配 profile）
- ❌ 独立体脂率趋势图（卡片+tooltip 已够）
- ❌ 数据 migration 处理 formula（formula 字段已存在，只改值不改结构）
- ❌ v1 移除（保留双协议兼容）

---

## 14. 陷阱规避

| # | 陷阱 | 规避 |
|---|---|---|
| 1 | v2 jin flag 位置变了（byte0 bit4 → byte1 bit6） | parseV2 用 byte1 bit6，不复用 v1 判定 |
| 2 | v2 packetId 含时间戳导致每秒包被当新包 | packetId 取 bytes[0-1]+bytes[9-12]，剔除 bytes[2-8] |
| 3 | v2 impedance 捕获时机（weight 稳定 ≠ impedance 完成） | 优先等 measurementComplete，超时用 stabilized 兜底 |
| 4 | startScan 时序 bug（开始时返回非结束时） | await isScanning.where(false).first 等待真正结束 |
| 5 | 国产 ROM 系统定位开关（华为系静默无结果） | Permission.location.serviceStatus 检查 + 引导 |
| 6 | AOSP 30秒/5次 节流 | 30秒/4次 短窗冷却 + 5分钟/3次 长窗冷却 |
| 7 | scanner _controller.add 未防 isClosed（dispose 竞态崩溃） | if (_controller.isClosed) return; 守卫 |
| 8 | tdeeAdjustmentKcal 跨公式污染（双重修正） | formula 切换时重置为 0 |
| 9 | bodyFatPct 无法显式置空（null=不更新） | 新增 clearBodyFatPct() 方法 |
| 10 | tdee_calibrator 硬编码 mifflin（体脂率白填） | 读 profile.formula 分支选 BMR |
| 11 | turnOn 在 iOS 无效 | if (Platform.isAndroid) 限定 |
| 12 | onError 静默（医疗场景应留日志） | debugPrint 记录 |

---

## 15. 硬约束影响

6+1 硬约束全部满足，本次改动不触碰：
1. ✅ build.gradle.kts isMinifyEnabled=false + isShrinkResources=false
2. ✅ meal_log.food_item_id 非空外键
3. ✅ AI 三路径（recognize_page / multi_dish_page / offline_queue_controller）
4. ✅ per100g 反算基于 estimatedWeightGMid
5. ✅ SecureConfigStore 无 instance 静态属性
6. ✅ initSentryAndRunApp 命名参数
7. ✅ minSdk=31

---

## 16. 版本

- 版本号：v0.32.0+45
- CHANGELOG：M27 v2 小米体脂秤2 支持 + 体脂率 + BMR 自动升级

---

## 17. 调研来源

### 协议（4 源交叉验证）
- ble_monitor miscale parser: https://github.com/custom-components/ble_monitor/blob/master/custom_components/ble_monitor/ble_parser/miscale.py
- ESPHome xiaomi_miscale: https://github.com/esphome/esphome/blob/dev/esphome/components/xiaomi_miscale/xiaomi_miscale.cpp
- BeMacized/xiaomi_scale（Dart，同技术栈）: https://github.com/BeMacized/xiaomi_scale
- smartscale_reader（Dart/Flutter，同技术栈）: https://pub.dev/packages/smartscale_reader
- blescalesync.dev: https://blescalesync.dev/body-composition

### 体脂率公式（双源验证）
- openScale MiScaleLib.kt: https://github.com/oliexdev/openScale/blob/master/android_app/app/src/main/java/com/health/openscale/core/bluetooth/libs/MiScaleLib.kt
- openScale MiScaleLibTest.kt（3 夹具）: https://github.com/oliexdev/openScale/blob/master/android_app/app/src/test/java/com/health/openscale/core/bluetooth/libs/MiScaleLibTest.kt
- miscale PyPI（prototux 原始 Python）: https://pypi.org/project/miscale/

### flutter_blue_plus 最佳实践
- flutter_blue_plus README: https://pub.dev/packages/flutter_blue_plus
- flutter_blue_plus_harmony changelog（确认 startScan 时序）: https://pub.dev/packages/flutter_blue_plus_harmony/changelog
- flutter_blue_plus_ohos（扫描范式代码）: https://pub.dev/packages/flutter_blue_plus_ohos

### 国产 ROM 适配
- 华为/小米 BLE 扫描失效: https://ask.csdn.net/questions/9313401
- Silicon Labs Android BLE 节流: https://docs.silabs.com/btmesh/10.0.0/bluetooth-mesh-for-android-and-ios-adk/04-resources
