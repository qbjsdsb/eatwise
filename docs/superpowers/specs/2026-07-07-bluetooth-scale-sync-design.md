# M27 蓝牙体重秤同步 — 设计文档

## 1. 背景

用户拥有一台多年前生产的小米体重秤 2（型号 XMTZC04HM）。需求：用户进入体重页时，App 自动通过 BLE 扫描捕获秤的广播，预填体重到输入框，用户确认后写入 WeightLogs。不建立 GATT 连接，纯被动扫描。

## 2. 设备与协议

### 2.1 设备

- 型号：XMTZC04HM（Mi Smart Scale 2，纯体重秤，无体脂）
- 协议版本：v1（与 XMTZC01HM 完全一致）
- Service Data UUID：`0x181D`（Weight Scale Service）
- Payload 长度：10 字节

### 2.2 v1 Payload 字节布局

| 字节 | 字段 | 说明 |
|------|------|------|
| 0 | control byte | bit0=lbs, bit4=jin, bit5=stabilized, bit7=weight_removed |
| 1-2 | weight raw | little-endian uint16 |
| 3-4 | year | little-endian uint16 |
| 5-9 | month/day/hour/minute/second | 各 1 字节 |

### 2.3 control byte bitmask 判定（学 ble_monitor，不学 ESPHome 枚举）

| bit | 含义 |
|-----|------|
| 0 | 单位 = lbs |
| 4 | 单位 = jin（斤） |
| 5 | stabilized（稳定） |
| 7 | weight_removed（已下秤） |

判定优先级：先 lbs（bit0），再 jin（bit4），都不是则 kg。

**真实样本 0x62（openScale wiki）证明 bitmask 必要**：0x62 = 0110 0010，bit6=1（未知），bit5=1（stabilized），ESPHome 枚举匹配漏掉这个包，bitmask 正确解析为 94.30 kg。

### 2.4 单位换算

| 单位 | 公式（raw → kg） | 依据 |
|------|------------------|------|
| kg | `raw / 200.0` | ble_monitor + openScale wiki |
| jin | `raw / 100.0 * 0.5` | 1 斤 = 0.5 kg（不用 ESPHome 的 0.6 bug） |
| lbs | `raw / 100.0 * 0.453592` | 1 lb = 0.453592 kg |

### 2.5 stabilized / weight_removed 处理（学 ble_monitor）

- `!stabilized` → 抖动阶段，丢弃
- `stabilized && !removed` → 有效稳定值，更新 lastStableWeight + 预填输入框
- `stabilized && removed` → 下秤包，ble_monitor 不设置 weight 字段，我也忽略

**不做会话制**：ble_monitor 源码确认无 session 概念，只用 packet_id 去重。简化设计，收到 stabilized 包即预填输入框，用户手动点"记录"按钮确认。

## 3. 架构

### 3.1 组件

```
weight_page (前台可见)
  ├─ WidgetsBindingObserver (生命周期)
  ├─ 首次进入：显示"开启蓝牙同步"横幅
  ├─ 用户点击横幅 → 批量请求 [bluetoothScan, bluetoothConnect, location]
  │  ├─ 永久拒绝 → openAppSettings()
  │  └─ 授权 → 检查 adapterState
  ├─ adapterState == off → FlutterBluePlus.turnOn()
  ├─ adapterState == on → startScan
  │
  ├─ App paused → stopScan / resumed → startScan
  ├─ 页面 dispose → stopScan + cancel subscription
  │
  ↓ MiScaleScanner (lib/data/bluetooth/mi_scale_scanner.dart)
  ├─ 无过滤扫描（不用 withServices 硬过滤）
  ├─ timeout 15 秒自动停止
  ├─ AndroidScanMode.lowLatency（防抓到非稳定值）
  ├─ onScanResults.listen（带 onError）
  │
  ↓ Dart 层软过滤
  ├─ serviceData[Guid("181D")] != null && length == 10
  │
  ↓ MiScaleParser.parseV1(payload) (lib/data/bluetooth/mi_scale_parser.dart)
  ├─ bitmask 判定单位
  ├─ 单位换算转 kg
  ├─ bit5=stabilized, bit7=weight_removed 双重保护
  ├─ packet_id = payload hex（去重）
  │
  ↓ 处理逻辑
  ├─ !stabilized → 丢弃
  ├─ stabilized && !removed → 
  │  ├─ packet_id 去重（相同包不重复处理）
  │  ├─ 更新 lastStableWeight
  │  └─ 预填 _weightCtrl.text + toast "已捕获 XX.X kg，请确认"
  ├─ stabilized && removed → 忽略
  │
  ↓ 用户点"记录"按钮
  └─ 复用现有 _save() → WeightLogs.insert + profileRepo.update + RefreshBus
```

### 3.2 数据流

```
用户进 weight_page
  → 首次：显示"开启蓝牙同步"横幅
  → 用户点击 → 请求权限（首次弹系统对话框）
  → 权限 OK → 检查蓝牙状态
  → 蓝牙关闭 → turnOn() 弹系统对话框
  → 蓝牙开启 → startScan（AppBar 显示"搜索体重秤..."）
  → 用户上秤
  → 秤广播（抖动阶段，!stabilized）→ 丢弃
  → 秤广播（稳定阶段，stabilized && !removed）→ 解析 + 去重 + 预填
  → toast "已捕获 65.3 kg，请确认"
  → 停止扫描 + AppBar 显示"重新扫描"按钮
  → 用户点"记录"按钮
  → 复用 _save() → WeightLogs.insert + profileRepo.update + RefreshBus
```

### 3.3 状态

- `idle`：未扫描（未授权 / 蓝牙关闭 / 首次进入未点击横幅）
- `scanning`：扫描中（AppBar 旋转图标 + "搜索体重秤..."）
- `captured`：已捕获（输入框预填 + "重新扫描"按钮）
- `error`：错误（蓝牙关闭 / 权限拒绝，显示引导）

## 4. 错误处理

| 场景 | 处理 |
|------|------|
| 权限拒绝 | 状态 → error，AppBar 显示"蓝牙权限不足"，input 仍可用 |
| 权限永久拒绝 | openAppSettings() 引导去设置，状态 → error |
| 蓝牙关闭 | turnOn() 弹系统对话框，input 仍可用 |
| 15 秒无稳定值 | 停止扫描 + toast"未找到体重秤，请确认秤已开机"，状态 → idle，input 仍可用 |
| 抓到非稳定值 | 丢弃，继续扫描 |
| 页面退出 | stopScan + cancel subscription，无内存泄漏 |
| 重复包 | packet_id 去重，不重复预填 |
| App 切后台 | stopScan，切回前台 startScan（5 分钟≤3 次冷却） |
| 扫描频率超限 | 5 分钟内 ≤3 次 startScan + timeout 自动停止 |

## 5. 权限

### 5.1 AndroidManifest.xml 新增

```xml
<uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<!-- 不加 neverForLocation：国产 ROM（MIUI/HarmonyOS/ColorOS）需要 ACCESS_FINE_LOCATION 才能扫描 -->
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<!-- 不加 maxSdkVersion：MIUI/HarmonyOS 强依赖，minSdk=31 也不可省 -->
```

### 5.2 运行时权限请求

- 批量请求：`[Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request()`
- 永久拒绝：`openAppSettings()`
- 顺序：请求权限 → 检查 adapterState → turnOn（如关闭）→ startScan

## 6. 依赖

### 6.1 pubspec.yaml 新增

```yaml
dependencies:
  flutter_blue_plus: ^2.3.10
  permission_handler: ^12.0.3
```

> `^` 是最低版本约束，pubspec.lock 会锁定具体版本（项目已入库 pubspec.lock，CI 可复现）。

### 6.2 APK 体积影响

- flutter_blue_plus：零依赖（纯 Dart + 薄原生通道）
- permission_handler：基于 AndroidX Permission 库的薄封装
- 预期增量：< 500KB（42MB → ~42.5MB）

## 7. 文件结构

### 7.1 新增文件

```
lib/data/bluetooth/
  mi_scale_parser.dart       # 纯 Dart 解析器（可单测）
  mi_scale_scanner.dart      # BLE 扫描 Service

test/
  mi_scale_parser_test.dart  # 7 个 hex 样本单测
```

### 7.2 修改文件

```
lib/features/weight/weight_page.dart
  - initState：加 WidgetsBindingObserver
  - build：加扫描状态指示器 + 首次横幅
  - 新增 _startScan / _stopScan / _handleScanResult 方法
  - dispose：cancel subscription + removeObserver

android/app/src/main/AndroidManifest.xml
  - 新增 4 个权限声明

pubspec.yaml
  - 新增 2 个依赖
```

## 8. 测试

### 8.1 单测样本（基于真实数据 + ble_monitor 验证）

```dart
// 样本 1（真实，openScale wiki）：0x62 bit6=1，ESPHome 漏掉，bitmask 正确
[0x62, 0xAC, 0x49, 0xE0, 0x07, 0x0C, 0x14, 0x0D, 0x1C, 0x04]
// raw=18860, kg, stabilized=true, removed=false → 94.3 kg

// 样本 2：kg stabilized not removed（有效）
[0x22, 0xB0, 0x4E, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00]
// raw=20160, kg, stabilized=true, removed=false → 100.8 kg

// 样本 3：kg stabilized removed（下秤包，忽略）
[0xA2, 0xB0, 0x4E, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00]
// raw=20160, kg, stabilized=true, removed=true → 忽略

// 样本 4：jin not stabilized（抖动，丢弃）
[0x12, 0x58, 0x4E, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00]
// raw=20056, jin, stabilized=false → 丢弃

// 样本 5：jin stabilized removed（下秤包，忽略）
[0xB2, 0x58, 0x4E, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00]
// raw=20056, jin, stabilized=true, removed=true → 忽略

// 样本 6：lbs not stabilized（抖动，丢弃）
[0x03, 0xD0, 0x15, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00]
// raw=5584, lbs, stabilized=false → 丢弃

// 样本 7：lbs stabilized removed（下秤包，忽略）
[0xB3, 0xD0, 0x15, 0xE8, 0x07, 0x07, 0x08, 0x0A, 0x1E, 0x00]
// raw=5584, lbs, stabilized=true, removed=true → 忽略
```

### 8.2 测试覆盖

- `mi_scale_parser_test.dart`：7 个样本 + 边界值（空 payload / 长度错误 / 未知 control byte）
- 集成测试：weight_page 进入时权限流程（手动验证）

## 9. 不做（YAGNI）

- ❌ 后台自动监听（国产 ROM 不可靠，App 必须前台）
- ❌ GATT 连接拉历史记录（只需实时广播）
- ❌ 体脂计算（Mi Scale 2 不测体脂）
- ❌ 多秤管理（个人自用单秤）
- ❌ iOS 适配（项目 Android only）
- ❌ 会话制（ble_monitor 无 session 概念，packet_id 去重足够）
- ❌ 等待 weight_removed 才落库（简化，用户手动确认）
- ❌ 时间戳解析（用手机本地时间，秤时间可能未同步）
- ❌ 多用户按体重区间分发（个人自用单用户）
- ❌ 电量广播处理（无电量广播）
- ❌ ForegroundService（前台被动扫描不需要）

## 10. 12 个已知陷阱规避清单

| # | 陷阱 | 规避 |
|---|------|------|
| 1 | ESPHome 0.6 斤系数 | 用 0.5（ble_monitor 验证） |
| 2 | v1 不检查 stabilized | bitmask + 双重保护 |
| 3 | 枚举判定 control byte | bitmask（0x62 样本证明） |
| 4 | withServices 硬过滤漏扫 | 无过滤 + Dart 软过滤 |
| 5 | neverForLocation 与国产 ROM 冲突 | 不加 neverForLocation + 声明 ACCESS_FINE_LOCATION |
| 6 | scanResults 重发历史 | 用 onScanResults |
| 7 | onScanResults 不带 onError | 必须带 onError |
| 8 | adapterState 重复监听 | dispose cancel subscription |
| 9 | 扫描间隔太长抓到非稳定值 | AndroidScanMode.lowLatency |
| 10 | 扫描频率超限 | 5分钟≤3次 + timeout |
| 11 | 权限请求顺序错 | 批量请求 + 永久拒绝引导设置 |
| 12 | ble_monitor 重启丢弃第一个包 | 我的实现不丢弃 |

## 11. 对硬约束的影响

- build.gradle.kts：`isMinifyEnabled=false` 不变 ✓（蓝牙库不依赖反射）
- meal_log：完全不碰 ✓（体重进 WeightLogs）
- minSdk=31：不变 ✓（简化蓝牙权限模型）
- 6+1 硬约束全部满足 ✓

## 12. 版本

- 当前：0.30.1+42
- 目标：0.31.0+43（minor bump，新功能）

## 13. 调研来源

### 协议层

- ble_monitor miscale.py 完整源码：https://github.com/custom-components/ble_monitor/blob/master/custom_components/ble_monitor/ble_parser/miscale.py
- ESPHome xiaomi_miscale.cpp 源码：https://github.com/esphome/esphome/blob/dev/esphome/components/xiaomi_miscale/xiaomi_miscale.cpp
- openScale wiki：https://github.com/mist/openScale/wiki/Xiaomi-Bluetooth-Mi-Scale
- ble_monitor 8.1.0 release notes：https://github.com/custom-components/ble_monitor/releases/tag/8.1.0
- ble_monitor issue #874（多次上报）：https://github.com/custom-components/ble_monitor/issues/874
- HA 社区 #9972：https://community.home-assistant.io/t/integrating-xiaomi-mi-scale/9972
- OpenMQTTGateway 社区 XMTZC04HM：https://community.openmqttgateway.com/t/unable-to-obtain-mi-scale-weight-in-realtime/1162

### flutter_blue_plus API

- pub.dev：https://pub.dev/packages/flutter_blue_plus
- GitHub README：https://github.com/chipweinberger/flutter_blue_plus
- example AndroidManifest.xml：https://github.com/chipweinberger/flutter_blue_plus/blob/master/packages/flutter_blue_plus/example/android/app/src/main/AndroidManifest.xml
- permission_handler：https://pub.dev/packages/permission_handler
- Android 官方蓝牙权限：https://developer.android.com/develop/connectivity/bluetooth/bt-permissions

### 国产 ROM 适配

- CSDN ask 9313401（华为/小米扫描失败实测）：https://ask.csdn.net/questions/9313401
- devsflow BLE Android 12+ 指南：https://neuro.devsflow.ca/blog/ble-scanning-android-12-permissions.html
