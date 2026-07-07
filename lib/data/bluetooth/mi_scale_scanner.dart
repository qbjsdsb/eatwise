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
