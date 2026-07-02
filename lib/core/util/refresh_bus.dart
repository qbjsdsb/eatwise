import 'package:flutter/foundation.dart';

/// 轻量刷新总线：跨 widget 通知"数据可能已变更，请刷新"。
///
/// 当前用于：FAB 拍照记录流程返回后，通知当前可见的 tab 页（首页/记录/洞察）
/// 重新加载数据，避免用户看到旧数据以为没记上。
///
/// 各 tab 页在 initState 中 `RefreshBus.instance.addListener(_refresh)`，
/// dispose 中 `removeListener`，收到通知即调用自身刷新方法。
class RefreshBus extends ChangeNotifier {
  RefreshBus._();
  static final RefreshBus instance = RefreshBus._();

  /// 通知所有监听者刷新
  void notify() => notifyListeners();
}
