// test/features/network_available_provider_test.dart
// networkAvailableProvider 行为测试（Bug 2 修复验证）
//
// 验证：
// - 冷启动校正：connectivity_plus 6.x Android 冷启动 NetworkCallback 未首次回调时
//   checkConnectivity() 误报 [none]，provider 内部 delay 500ms 重查一次
// - autoDispose：invalidate 后重新 read 会重新查询（避免冷启动 false 永久缓存）
//
// MethodChannel mock：connectivity_plus 6.x 用 'dev.fluttercommunity.plus/connectivity'
// 通道，方法名 'check'，返回 List<String>（'wifi'/'mobile'/'none' 等）
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;

void main() {
  // 初始化 binding：TestDefaultBinaryMessengerBinding.instance 需要先初始化
  // 才能调用 setMockMethodCallHandler
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('冷启动校正：首次 [none] → delay 500ms 重查 [wifi] → 最终 true', () async {
    var callCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'check') {
        callCount++;
        // 模拟冷启动：首次 NetworkCallback 未回调误报 [none]，第二次正常 [wifi]
        if (callCount == 1) return ['none'];
        return ['wifi'];
      }
      return null;
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final online =
        await container.read(recognize.networkAvailableProvider.future);
    expect(online, true, reason: '冷启动校正后应返回 true（重查到 [wifi]）');
    expect(callCount, 2, reason: '首次 [none] 应触发重查，共调用 check 2 次');
  });

  test('真离线：两次都 [none] → false', () async {
    var callCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'check') {
        callCount++;
        return ['none'];
      }
      return null;
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final online =
        await container.read(recognize.networkAvailableProvider.future);
    expect(online, false, reason: '两次 [none] 应返回 false（真离线）');
    expect(callCount, 2, reason: '首次 [none] 触发重查仍 [none]，共调用 check 2 次');
  });

  test('在线：首次 [wifi] → true（不触发重查）', () async {
    var callCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'check') {
        callCount++;
        return ['wifi'];
      }
      return null;
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final online =
        await container.read(recognize.networkAvailableProvider.future);
    expect(online, true, reason: '首次 [wifi] 应返回 true');
    expect(callCount, 1, reason: '首次 [wifi] 无需重查，只调用 check 1 次');
  });

  test('autoDispose：invalidate 后重新 read 会重新查询', () async {
    var callCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'check') {
        callCount++;
        return ['wifi'];
      }
      return null;
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // 第一次 read
    await container.read(recognize.networkAvailableProvider.future);
    expect(callCount, 1);

    // autoDispose + invalidate 强制销毁并重新创建 provider
    // 验证重新 read 会重新查询（避免冷启动 false 永久缓存）
    container.invalidate(recognize.networkAvailableProvider);
    await container.read(recognize.networkAvailableProvider.future);
    expect(callCount, 2, reason: 'invalidate 后重新 read 应重新查询 check');
  });
}
