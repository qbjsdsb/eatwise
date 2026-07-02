// lib/background/background_tasks.dart
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

/// 后台任务名常量（callbackDispatcher 中 switch 用）
class BackgroundTasks {
  /// 离线队列回补（网络恢复时触发）
  static const offlineBackfill = 'offline_backfill';
  /// 自动备份（每周日凌晨）
  static const autoBackup = 'auto_backup';
  /// 图片清理（每周一次，清理配置保留期前原图，T48）
  static const imageCleanup = 'image_cleanup';

  /// 注册所有周期任务（App 启动时调用）
  /// 使用 existingWorkPolicy.update：重复注册时更新而非取消（避免重启 App 重置调度）
  static Future<void> registerAll() async {
    // 离线回补：每 15 分钟尝试一次（系统最小周期，实际由系统决定）
    // Constraints: 需联网（离线时跳过）
    await Workmanager().registerPeriodicTask(
      'eatwise_offline_backfill',
      offlineBackfill,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );

    // 自动备份：每周一次（系统可能延迟，不保证精确）
    await Workmanager().registerPeriodicTask(
      'eatwise_auto_backup',
      autoBackup,
      frequency: const Duration(days: 7),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );

    // 图片清理：每周一次
    await Workmanager().registerPeriodicTask(
      'eatwise_image_cleanup',
      imageCleanup,
      frequency: const Duration(days: 7),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );

    debugPrint('workmanager 周期任务已注册');
  }
}
