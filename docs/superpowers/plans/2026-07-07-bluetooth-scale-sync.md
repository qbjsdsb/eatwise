# M27 蓝牙体重秤同步 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户进入体重页时，App 通过 BLE 被动扫描小米体重秤 2（XMTZC04HM）的广播，自动捕获稳定体重值并预填输入框，用户确认后写入 WeightLogs。

**Architecture:** 纯被动 BLE 扫描（不建立 GATT 连接）→ Dart 层软过滤 serviceData UUID 0x181D → bitmask 解析 v1 协议（学 ble_monitor）→ 预填 _weightCtrl → 复用现有 _save() 写库。零改动数据层。

**Tech Stack:** Flutter 3.44.4 / flutter_blue_plus 2.3.10 / permission_handler 12.0.3 / Android minSdk 31

---

## 文件结构

### 新增文件

- `lib/data/bluetooth/mi_scale_parser.dart` — 纯 Dart 协议解析器（可单测，零依赖）
- `lib/data/bluetooth/mi_scale_scanner.dart` — BLE 扫描 Service（封装 flutter_blue_plus）
- `test/mi_scale_parser_test.dart` — 7 个 hex 样本单测

### 修改文件

- `pubspec.yaml` — 新增 2 个依赖
- `android/app/src/main/AndroidManifest.xml` — 新增 4 个权限声明
- `lib/features/weight/weight_page.dart` — 接入蓝牙扫描 + 预填输入框

---

## Task 1: 添加依赖

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 在 pubspec.yaml dependencies 区添加两个依赖**

读取 `pubspec.yaml` 找到 `dependencies:` 区块，在合适位置添加：

```yaml
  flutter_blue_plus: ^2.3.10
  permission_handler: ^12.0.3
```

- [ ] **Step 2: 运行 pub get**

```bash
export PATH=/tmp/flutter/bin:$PATH
flutter pub get
```

预期：依赖解析成功，pubspec.lock 更新。

- [ ] **Step 3: 验证依赖入库**

```bash
git diff pubspec.yaml pubspec.lock | head -50
```

预期：pubspec.yaml 新增 2 行，pubspec.lock 新增 flutter_blue_plus + permission_handler 及其传递依赖。

- [ ] **Step 4: 提交**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat(bl): 添加 flutter_blue_plus + permission_handler 依赖

M27 蓝牙体重秤同步首步：引入 BLE 扫描库。
flutter_blue_plus 2.3.10（零依赖纯 Dart + 薄原生通道）
permission_handler 12.0.3（权限请求）"
```

---

## Task 2: AndroidManifest 权限声明

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: 读取当前 AndroidManifest.xml**

读取 `android/app/src/main/AndroidManifest.xml`，找到 `<manifest>` 标签内、`<application>` 标签之前的位置。

- [ ] **Step 2: 在 <application> 标签之前添加权限声明**

```xml
    <!-- M27 蓝牙体重秤同步：BLE 被动扫描权限 -->
    <!-- BLUETOOTH_SCAN：Android 12+ 扫描 BLE 广播必需 -->
    <!-- 不加 neverForLocation：国产 ROM（MIUI/HarmonyOS/ColorOS）需要 ACCESS_FINE_LOCATION 才能扫描 -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
    <!-- BLUETOOTH_CONNECT：跟随 flutter_blue_plus 官方 example，未来扩展 GATT 不用改 -->
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <!-- ACCESS_FINE_LOCATION：MIUI/HarmonyOS 强依赖，minSdk=31 也不可省 -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <!-- 声明需要 BLE 硬件，required=false 不阻止无蓝牙设备安装 -->
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />
```

- [ ] **Step 3: 验证 manifest 合法**

```bash
export PATH=/tmp/flutter/bin:$PATH
flutter analyze
```

预期：No issues。

- [ ] **Step 4: 提交**

```bash
git add android/app/src/main/AndroidManifest.xml
git commit -m "feat(bl): AndroidManifest 声明 BLE 扫描权限

BLUETOOTH_SCAN + BLUETOOTH_CONNECT + ACCESS_FINE_LOCATION
不加 neverForLocation（国产 ROM 适配）+ uses-feature required=false"
```

---

## Task 3: MiScaleParser 协议解析器（TDD）

**Files:**
- Create: `lib/data/bluetooth/mi_scale_parser.dart`
- Create: `test/mi_scale_parser_test.dart`

- [ ] **Step 1: 先写失败的单测**

创建 `test/mi_scale_parser_test.dart`：

```dart
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

    test('样本 2：0x22 kg stabilized not removed 100.8 kg', () {
      final payload = [0x22, 0xB0, 0x4E, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00];
      final m = MiScaleParser.parseV1(payload);
      expect(m, isNotNull);
      expect(m!.weightKg, closeTo(100.8, 0.01));
      expect(m.unit, 'kg');
      expect(m.isStabilized, true);
      expect(m.weightRemoved, false);
      expect(m.isEffective, true);
    });

    test('样本 3：0xA2 kg stabilized removed（下秤包，isEffective=false）', () {
      final payload = [0xA2, 0xB0, 0x4E, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00];
      final m = MiScaleParser.parseV1(payload);
      expect(m, isNotNull);
      expect(m!.weightKg, closeTo(100.8, 0.01));
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
```

- [ ] **Step 2: 运行测试确认失败**

```bash
export PATH=/tmp/flutter/bin:$PATH
flutter test test/mi_scale_parser_test.dart
```

预期：FAIL，报错 `Target of URI doesn't exist: 'package:eatwise/data/bluetooth/mi_scale_parser.dart'`。

- [ ] **Step 3: 创建解析器实现**

创建 `lib/data/bluetooth/mi_scale_parser.dart`：

```dart
/// M27 小米体重秤 v1 协议解析器
///
/// 纯 Dart 实现，零依赖，可单测。解析 XMTZC01HM / XMTZC04HM 的 BLE 广播 payload。
///
/// 协议（学 ble_monitor，不学 ESPHome v1）：
/// - UUID: 0x181D（Weight Scale Service）
/// - Payload: 10 字节
/// - byte 0: control byte（bitmask 判定，不用枚举）
///   - bit0: 单位 = lbs
///   - bit4: 单位 = jin（斤）
///   - bit5: stabilized（稳定）
///   - bit7: weight_removed（已下秤）
/// - byte 1-2: weight raw（little-endian uint16）
/// - byte 3-9: timestamp（year LE 2B + month/day/hour/min/sec 各 1B，本实现不解析）
///
/// 单位换算（raw → kg）：
/// - kg: raw / 200.0
/// - jin: raw / 100.0 * 0.5（1 斤 = 0.5 kg，不用 ESPHome 的 0.6 bug）
/// - lbs: raw / 100.0 * 0.453592
///
/// 有效性判定（学 ble_monitor）：
/// - isEffective = isStabilized && !weightRemoved
/// - !stabilized → 抖动阶段，丢弃
/// - stabilized && removed → 下秤包，不落库
class MiScaleParser {
  MiScaleParser._();

  /// 解析 v1 协议 payload（10 字节）
  ///
  /// 返回 null 表示 payload 不合法（长度错误）。
  static MiScaleMeasurement? parseV1(List<int> payload) {
    if (payload.length != 10) return null;

    final controlByte = payload[0];
    final raw = payload[1] | (payload[2] << 8);

    // bitmask 判定单位（学 ble_monitor，不学 ESPHome 枚举）
    // 优先级：先 lbs（bit0），再 jin（bit4），都不是则 kg
    final isLbs = (controlByte & (1 << 0)) != 0;
    final isJin = (controlByte & (1 << 4)) != 0;

    double weightKg;
    String unit;
    if (isLbs) {
      weightKg = raw / 100.0 * 0.453592;
      unit = 'lbs';
    } else if (isJin) {
      weightKg = raw / 100.0 * 0.5;
      unit = 'jin';
    } else {
      weightKg = raw / 200.0;
      unit = 'kg';
    }

    final isStabilized = (controlByte & (1 << 5)) != 0;
    final weightRemoved = (controlByte & (1 << 7)) != 0;

    // packet_id = payload hex（用于去重，学 ble_monitor）
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

/// 小米体重秤 v1 解析结果
class MiScaleMeasurement {
  /// 体重（已换算为 kg）
  final double weightKg;

  /// 原始单位（'kg' / 'jin' / 'lbs'）
  final String unit;

  /// 是否稳定（bit5）
  final bool isStabilized;

  /// 是否已下秤（bit7）
  final bool weightRemoved;

  /// payload hex，用于去重
  final String packetId;

  const MiScaleMeasurement({
    required this.weightKg,
    required this.unit,
    required this.isStabilized,
    required this.weightRemoved,
    required this.packetId,
  });

  /// 有效测量值：stabilized && !removed（学 ble_monitor）
  /// !stabilized → 抖动阶段，丢弃
  /// stabilized && removed → 下秤包，不落库
  bool get isEffective => isStabilized && !weightRemoved;
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
export PATH=/tmp/flutter/bin:$PATH
flutter test test/mi_scale_parser_test.dart
```

预期：所有测试 PASS（10 个测试）。

- [ ] **Step 5: 运行 flutter analyze**

```bash
flutter analyze
```

预期：No issues。

- [ ] **Step 6: 提交**

```bash
git add lib/data/bluetooth/mi_scale_parser.dart test/mi_scale_parser_test.dart
git commit -m "feat(bl): MiScaleParser v1 协议解析器 + 10 个单测

学 ble_monitor bitmask 判定（不学 ESPHome 枚举）：
- 0x62 真实样本证明 bitmask 必要（ESPHome 枚举漏掉）
- 斤系数用 0.5（不用 ESPHome 的 0.6 bug）
- isEffective = stabilized && !removed 双重保护"
```

---

## Task 4: MiScaleScanner BLE 扫描 Service

**Files:**
- Create: `lib/data/bluetooth/mi_scale_scanner.dart`

- [ ] **Step 1: 创建扫描器实现**

创建 `lib/data/bluetooth/mi_scale_scanner.dart`：

```dart
import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'mi_scale_parser.dart';

/// M27 小米体重秤 BLE 扫描 Service
///
/// 封装 flutter_blue_plus 的被动扫描逻辑：
/// - 无过滤扫描（不用 withServices 硬过滤，避免漏扫）
/// - Dart 层软过滤 serviceData[0x181D] && length==10
/// - AndroidScanMode.lowLatency（防抓到非稳定值，OpenMQTTGateway 社区案例）
/// - timeout 15 秒自动停止
/// - onScanResults.listen（带 onError，唯一会发 error 的流）
///
/// 生命周期由调用方（weight_page）管理：
/// - startScan() 启动扫描
/// - stopScan() 停止扫描
/// - measurementStream 推送有效测量值（isEffective=true）
class MiScaleScanner {
  StreamSubscription<List<ScanResult>>? _scanSub;
  final StreamController<MiScaleMeasurement> _controller =
      StreamController<MiScaleMeasurement>.broadcast();
  String? _lastPacketId; // packet_id 去重

  /// 权重秤 Service UUID（v1 协议）
  static final Guid _weightScaleUuid = Guid('181D');

  /// 有效测量值流（stabilized && !removed）
  /// 调用方 listen 此流，收到值后预填输入框
  Stream<MiScaleMeasurement> get measurementStream => _controller.stream;

  /// 当前是否在扫描
  bool get isScanning => FlutterBluePlus.isScanningNow;

  /// 启动扫描
  ///
  /// 前置条件：已获得 BLUETOOTH_SCAN + BLUETOOTH_CONNECT + ACCESS_FINE_LOCATION 权限，
  /// 且蓝牙适配器已开启（adapterState == on）。
  /// 调用方负责权限请求和适配器状态检查。
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    // 重置去重状态（新一次扫描允许重复包）
    _lastPacketId = null;

    // 先取消旧订阅（防重复监听）
    await _scanSub?.cancel();
    _scanSub = null;

    // 订阅实时扫描结果（onScanResults 不重发历史，必须带 onError）
    _scanSub = FlutterBluePlus.onScanResults.listen(
      _handleScanResults,
      onError: (Object e) {
        // scanResults/onScanResults 是唯一会发 error 的流
        // 错误通常无害（如短暂权限撤销），不中断扫描
      },
    );

    // 启动扫描：无过滤 + lowLatency + timeout
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidScanMode: AndroidScanMode.lowLatency,
    );
  }

  /// 停止扫描
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
  }

  /// 释放资源（调用方 dispose 时调）
  Future<void> dispose() async {
    await stopScan();
    await _controller.close();
  }

  void _handleScanResults(List<ScanResult> results) {
    for (final r in results) {
      final sd = r.advertisementData.serviceData;
      final payload = sd[_weightScaleUuid];
      // 软过滤：UUID 0x181D 且长度 10（v1 协议）
      if (payload == null || payload.length != 10) continue;

      final m = MiScaleParser.parseV1(payload);
      if (m == null) continue;

      // 有效性过滤：stabilized && !removed
      if (!m.isEffective) continue;

      // packet_id 去重（学 ble_monitor）
      if (m.packetId == _lastPacketId) continue;
      _lastPacketId = m.packetId;

      // 推送给调用方
      _controller.add(m);
    }
  }
}
```

- [ ] **Step 2: 运行 flutter analyze**

```bash
export PATH=/tmp/flutter/bin:$PATH
flutter analyze
```

预期：No issues。

- [ ] **Step 3: 提交**

```bash
git add lib/data/bluetooth/mi_scale_scanner.dart
git commit -m "feat(bl): MiScaleScanner BLE 扫描 Service

封装 flutter_blue_plus 被动扫描：
- 无过滤扫描 + Dart 软过滤 serviceData[0x181D]
- AndroidScanMode.lowLatency 防抓到非稳定值
- onScanResults + onError（唯一会发 error 的流）
- packet_id 去重 + isEffective 过滤"
```

---

## Task 5: weight_page 接入蓝牙扫描

**Files:**
- Modify: `lib/features/weight/weight_page.dart`

- [ ] **Step 1: 添加 import 和 WidgetsBindingObserver**

在 `lib/features/weight/weight_page.dart` 顶部 import 区添加：

```dart
import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/bluetooth/mi_scale_scanner.dart';
import '../../data/bluetooth/mi_scale_parser.dart';
```

（注意：`dart:async` 和 `package:flutter/services.dart` 已有的 import 保留，新增的按字母序插入）

将 `WeightPageState` 类声明改为 mixin WidgetsBindingObserver：

```dart
class WeightPageState extends ConsumerState<WeightPage>
    with WidgetsBindingObserver {
```

- [ ] **Step 2: 添加蓝牙状态字段**

在 `WeightPageState` 的 `String? _weightError;` 之后添加：

```dart
  // M27 蓝牙体重秤同步状态
  // _bleState：idle（未扫描）/ scanning（扫描中）/ captured（已捕获）/ error（错误）
  // _bleScanner：BLE 扫描 Service，懒初始化（首次开启蓝牙同步时创建）
  // _bleEnabled：用户是否已开启蓝牙同步（首次点击横幅后置 true，后续进入自动扫描）
  // _scanSub：measurementStream 订阅，dispose 时 cancel
  _BleState _bleState = _BleState.idle;
  MiScaleScanner? _bleScanner;
  bool _bleEnabled = false;
  StreamSubscription<MiScaleMeasurement>? _scanSub;
  // 扫描冷却：5 分钟内 ≤3 次 startScan（MIUI 熔断阈值）
  final List<DateTime> _scanTimestamps = [];
```

在文件底部（`_WeightEditResult` 类之后）添加枚举：

```dart

/// M27 蓝牙扫描状态
enum _BleState {
  idle, // 未扫描（未授权 / 蓝牙关闭 / 首次进入未点击横幅）
  scanning, // 扫描中
  captured, // 已捕获稳定值
  error, // 错误（权限拒绝 / 蓝牙关闭）
}
```

- [ ] **Step 3: initState 添加 WidgetsBindingObserver**

将 `initState` 改为：

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // M27 生命周期监听
    _weightCtrl.addListener(_markDirty);
    _load();
  }
```

- [ ] **Step 4: dispose 添加 BLE 资源清理**

将 `dispose` 改为：

```dart
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanSub?.cancel();
    _bleScanner?.dispose();
    _weightCtrl.removeListener(_markDirty);
    _weightCtrl.dispose();
    super.dispose();
  }
```

- [ ] **Step 5: 添加 didChangeAppLifecycleState**

在 `dispose` 方法之后添加：

```dart

  /// M27：App 生命周期切换时管理 BLE 扫描
  /// paused → stopScan（国产 ROM 后台扫描必被冻结）
  /// resumed → startScan（如已开启蓝牙同步）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _stopBleScan();
    } else if (state == AppLifecycleState.resumed && _bleEnabled) {
      _startBleScan();
    }
  }
```

- [ ] **Step 6: 添加 _enableBleSync 方法**

在 `didChangeAppLifecycleState` 之后添加：

```dart

  /// M27：用户点击"开启蓝牙同步"横幅 → 请求权限 + 启动扫描
  Future<void> _enableBleSync() async {
    // 1. 批量请求权限（国产 ROM 需要 location）
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    // 2. 永久拒绝 → 引导去设置
    final anyPermanentlyDenied = statuses.values
        .any((s) => s.isPermanentlyDenied);
    if (anyPermanentlyDenied) {
      if (!mounted) return;
      setState(() => _bleState = _BleState.error);
      showAppToast(context, '蓝牙权限被永久拒绝，请在设置中开启');
      await openAppSettings();
      return;
    }

    // 3. 普通拒绝 → 显示错误
    final allGranted = statuses.values.every((s) => s.isGranted);
    if (!allGranted) {
      if (!mounted) return;
      setState(() => _bleState = _BleState.error);
      showAppToast(context, '蓝牙权限不足，无法自动同步');
      return;
    }

    // 4. 权限 OK → 标记已开启 + 启动扫描
    setState(() => _bleEnabled = true);
    await _startBleScan();
  }

  /// M27：启动 BLE 扫描
  Future<void> _startBleScan() async {
    // 扫描冷却：5 分钟内 ≤3 次（MIUI 熔断阈值）
    final now = DateTime.now();
    _scanTimestamps.removeWhere(
        (t) => now.difference(t).inMinutes >= 5);
    if (_scanTimestamps.length >= 3) {
      if (!mounted) return;
      showAppToast(context, '扫描过于频繁，请稍后再试');
      return;
    }
    _scanTimestamps.add(now);

    // 检查蓝牙适配器状态
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      // 蓝牙关闭 → Android 主动弹系统对话框
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        // 用户拒绝开启蓝牙
        if (!mounted) return;
        setState(() => _bleState = _BleState.error);
        return;
      }
      // 等待适配器开启（最多 30 秒）
      try {
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .timeout(const Duration(seconds: 30))
            .first;
      } catch (_) {
        if (!mounted) return;
        setState(() => _bleState = _BleState.error);
        showAppToast(context, '蓝牙未开启，无法扫描');
        return;
      }
    }

    // 懒初始化扫描器
    _bleScanner ??= MiScaleScanner();

    // 订阅测量值流（取消旧订阅防重复）
    await _scanSub?.cancel();
    _scanSub = _bleScanner!.measurementStream.listen(_onMeasurement);

    if (!mounted) return;
    setState(() => _bleState = _BleState.scanning);

    try {
      await _bleScanner!.startScan(
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      debugPrint('BLE 扫描启动失败: $e');
      if (mounted) {
        setState(() => _bleState = _BleState.error);
      }
    }

    // 扫描超时后如未捕获，回到 idle
    if (mounted && _bleState == _BleState.scanning) {
      setState(() => _bleState = _BleState.idle);
      if (!mounted) return;
      showAppToast(context, '未找到体重秤，请确认秤已开机');
    }
  }

  /// M27：停止 BLE 扫描
  Future<void> _stopBleScan() async {
    await _bleScanner?.stopScan();
  }

  /// M27：收到有效测量值 → 预填输入框
  void _onMeasurement(MiScaleMeasurement m) {
    if (!mounted) return;
    setState(() {
      _weightCtrl.text = m.weightKg.toStringAsFixed(1);
      _weightError = null;
      _bleState = _BleState.captured;
      // 预填视为用户输入，标记 dirty（PopScope 未保存确认）
      _dirty = true;
    });
    // 停止扫描（已捕获，省电）
    _stopBleScan();
    showAppToast(context, '已捕获 ${m.weightKg.toStringAsFixed(1)} kg，请确认');
  }
```

- [ ] **Step 7: 在 build 方法的 ListView children 顶部添加蓝牙 UI**

找到 `build` 方法中 `body: ListView(` 之后的 `children: [`，在 `Row(` （体重输入行）之前添加：

```dart
            // M27 蓝牙同步横幅 / 状态指示器
            if (_bleState == _BleState.idle && !_bleEnabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: const Text('开启蓝牙同步'),
                    subtitle: const Text('自动捕获小米体重秤数据'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _enableBleSync,
                  ),
                ),
              )
            else if (_bleState == _BleState.scanning)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: const Text('搜索体重秤...'),
                  subtitle: const Text('请上秤站立保持静止'),
                  trailing: TextButton(
                    onPressed: _stopBleScan,
                    child: const Text('停止'),
                  ),
                ),
              )
            else if (_bleState == _BleState.captured)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.bluetooth_connected,
                      color: Colors.green),
                  title: const Text('已捕获体重'),
                  trailing: TextButton(
                    onPressed: _startBleScan,
                    child: const Text('重新扫描'),
                  ),
                ),
              )
            else if (_bleState == _BleState.error)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(Icons.error_outline,
                      color: Theme.of(context).colorScheme.error),
                  title: const Text('蓝牙同步不可用'),
                  trailing: TextButton(
                    onPressed: _enableBleSync,
                    child: const Text('重试'),
                  ),
                ),
              ),
```

- [ ] **Step 8: 运行 flutter analyze**

```bash
export PATH=/tmp/flutter/bin:$PATH
flutter analyze
```

预期：No issues。如有 import 未使用或类型错误，修复后重跑。

- [ ] **Step 9: 提交**

```bash
git add lib/features/weight/weight_page.dart
git commit -m "feat(bl): weight_page 接入蓝牙体重秤同步

- WidgetsBindingObserver 生命周期管理（paused stopScan / resumed startScan）
- 首次进入显示"开启蓝牙同步"横幅，点击请求权限
- 扫描中显示 CircularProgressIndicator + "搜索体重秤..."
- 捕获稳定值预填 _weightCtrl + toast 提示
- 5 分钟 ≤3 次扫描冷却（MIUI 熔断阈值）
- 蓝牙关闭 turnOn() 弹系统对话框
- 复用现有 _save() 写库路径，零改动数据层"
```

---

## Task 6: 全量验证

**Files:**
- 无修改，仅验证

- [ ] **Step 1: flutter analyze**

```bash
export PATH=/tmp/flutter/bin:$PATH
flutter analyze
```

预期：No issues。

- [ ] **Step 2: flutter test（全量）**

```bash
flutter test
```

预期：所有测试 PASS。基线 v0.30.1 是 1134 passed / 3 skipped。本次新增 10 个 parser 单测，预期 1144 passed / 3 skipped。

- [ ] **Step 3: 验证 6+1 硬约束**

```bash
# 1. build.gradle.kts isMinifyEnabled = false + isShrinkResources = false
grep -A2 "release" android/app/build.gradle.kts | grep -E "isMinify|isShrink"
# 预期：isMinifyEnabled = false / isShrinkResources = false

# 2. minSdk = 31
grep "minSdk" android/app/build.gradle.kts
# 预期：minSdk = 31

# 3. abiFilters = arm64-v8a（v0.30.1 新增）
grep "abiFilters" android/app/build.gradle.kts
# 预期：abiFilters += "arm64-v8a"
```

预期：6+1 硬约束全部满足。

- [ ] **Step 4: 验证 APK 可构建**

```bash
flutter build apk --release --target-platform android-arm64
```

预期：构建成功，APK 体积约 42-43 MB（增量 <500KB）。

- [ ] **Step 5: 提交验证记录（如有改动）**

```bash
git status
# 如无改动则跳过 commit
```

---

## Task 7: bump 版本 + 更新 HANDOFF

**Files:**
- Modify: `pubspec.yaml`
- Modify: `CHANGELOG.md`（如存在）
- Modify: `HANDOFF.md`

- [ ] **Step 1: bump pubspec.yaml 版本**

将 `pubspec.yaml` 的 `version: 0.30.1+42` 改为 `version: 0.31.0+43`。

- [ ] **Step 2: 更新 HANDOFF.md**

读取 `HANDOFF.md`，在"当前状态"区更新：

```markdown
## 当前状态

**版本**：v0.31.0+43（M27 蓝牙体重秤同步）

**最近改动**：
- M27 蓝牙体重秤同步：接入 flutter_blue_plus + permission_handler，weight_page 自动扫描小米体重秤 2（XMTZC04HM）广播，捕获稳定体重值预填输入框
- 协议解析学 ble_monitor（bitmask 判定 + 双重保护 + packet_id 去重），不学 ESPHome v1（枚举 + 0.6 斤系数 bug + 不检查 stabilized）
- 新增 lib/data/bluetooth/mi_scale_parser.dart + mi_scale_scanner.dart
- 6+1 硬约束全部满足，1144 passed / 3 skipped / 0 回归
```

- [ ] **Step 3: 提交**

```bash
git add pubspec.yaml HANDOFF.md
git commit -m "chore: bump v0.31.0+43 + HANDOFF 更新

M27 蓝牙体重秤同步完成"
```

---

## Task 8: push（不打 tag 不发 release）

- [ ] **Step 1: push 到远程**

```bash
git push origin trae/agent-wX1X6Q
```

预期：push 成功。

- [ ] **Step 2: 确认 git status clean**

```bash
git status
```

预期：nothing to commit, working tree clean。

---

## 自检清单

### Spec 覆盖

- ✅ Section 2 设备与协议 → Task 3 parser 实现 + 单测
- ✅ Section 3.1 架构 → Task 4 scanner + Task 5 weight_page 接入
- ✅ Section 4 错误处理 → Task 5 _enableBleSync / _startBleScan 错误分支
- ✅ Section 5 权限 → Task 2 AndroidManifest + Task 5 运行时请求
- ✅ Section 6 依赖 → Task 1 pubspec
- ✅ Section 7 文件结构 → Task 3/4 新增 + Task 5 修改
- ✅ Section 8 测试 → Task 3 单测 + Task 6 全量验证
- ✅ Section 10 陷阱规避 → Task 3/4/5 代码实现
- ✅ Section 11 硬约束 → Task 6 验证
- ✅ Section 12 版本 → Task 7 bump

### 类型一致性

- `MiScaleMeasurement` 类：Task 3 定义，Task 4 scanner 引用，Task 5 weight_page 引用 — 一致
- `MiScaleScanner` 类：Task 4 定义 `startScan`/`stopScan`/`dispose`/`measurementStream`，Task 5 调用 — 一致
- `MiScaleParser.parseV1` 静态方法：Task 3 定义，Task 4 scanner 调用 — 一致
- `_BleState` 枚举：Task 5 定义 idle/scanning/captured/error，build 方法 4 个分支引用 — 一致
