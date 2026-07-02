// lib/background/background_dispatcher.dart
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../core/config/app_config.dart';
import '../core/config/secure_config_store.dart';
import '../data/backup/auto_backup.dart';
import '../data/backup/image_cleanup.dart';
import '../data/database/connection.dart';
import '../data/database/database.dart';
import '../data/repositories/food_item_repository.dart';
import '../ai/nutrition_lookup.dart';
import '../ai/qwen_vl_provider.dart';
import '../features/offline/offline_queue_controller.dart';
import 'background_tasks.dart';

/// workmanager callbackDispatcher
/// 必须是 top-level 函数 + @pragma('vm:entry-point')，在独立 isolate 运行
///
/// 注意：此 isolate 无法访问 main isolate 的 ProviderContainer，
/// 需重新初始化 DB + AppConfig + VisionProvider
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('后台任务执行: $task');
    try {
      // 重新初始化依赖（独立 isolate）
      final executor = await openEncryptedConnection();
      final db = EatWiseDatabase(executor);

      switch (task) {
        case BackgroundTasks.offlineBackfill:
          await _runOfflineBackfill(db);
          break;
        case BackgroundTasks.autoBackup:
          await AutoBackup.run(db);
          break;
        case BackgroundTasks.imageCleanup:
          // T48：用配置的保留期（0=永久保留，跳过清理）
          final retentionDays = await SecureConfigStore().getImageRetentionDays();
          if (retentionDays > 0) {
            await ImageCleanup.run(db, retentionDays: retentionDays);
          }
          break;
        default:
          debugPrint('未知后台任务: $task');
      }

      await db.close();
      return true;
    } catch (e, st) {
      debugPrint('后台任务失败: $e\n$st');
      // 返回 false 让 WorkManager 重试（按指数退避）
      return false;
    }
  });
}

/// 离线队列回补（复用 OfflineQueueController 逻辑）
Future<void> _runOfflineBackfill(EatWiseDatabase db) async {
  // 后台 isolate 读 secure_storage 获取 API key
  final store = SecureConfigStore();
  final config = AppConfig(store);
  await config.load();

  if (config.qwenApiKey.isEmpty) {
    debugPrint('后台回补跳过：未配置 Qwen API key');
    return;
  }

  final visionProvider = QwenVlProvider(
    apiKey: config.qwenApiKey,
    baseUrl: config.qwenBaseUrl.isNotEmpty
        ? config.qwenBaseUrl
        : 'https://dashscope.aliyuncs.com/compatible-mode/v1',
  );
  final foodRepo = FoodItemRepository(db);
  final lookup = NutritionLookup(foodRepo);

  final controller = OfflineQueueController(
    db: db,
    visionProvider: visionProvider,
    nutritionLookup: lookup,
  );
  // 后台回补只调 processPending 一次（不启动 connectivity 监听）
  await controller.processPending();
}
