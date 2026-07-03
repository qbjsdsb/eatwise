import 'dart:io';

import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';

/// 图片清理：删除 N 天前原图，保留缩略图
/// 设计文档 9.4：默认保留近 30 天原图，更早的删除
class ImageCleanup {
  static const defaultRetentionDays = 30;

  /// 执行清理（后台任务 + App 启动时前台异步触发）
  /// 返回删除的文件数
  /// retentionDays <= 0 表示永久保留，直接返回 0 不清理
  static Future<int> run(EatWiseDatabase db, {int? retentionDays}) async {
    final days = retentionDays ?? defaultRetentionDays;
    if (days <= 0) return 0; // 永久保留，不清理
    final mealRepo = MealLogRepository(db);

    final candidates = await mealRepo.getOldImagePaths(days);
    var deletedCount = 0;

    for (final c in candidates) {
      try {
        final file = File(c.originalImagePath);
        if (await file.exists()) {
          await file.delete();
          deletedCount++;
        }
        // 无论文件是否存在，都清除 DB 引用（避免死链 404）
        await mealRepo.clearImagePath(c.id);
      } catch (_) {
        // 删除失败不阻塞，下次重试
      }
    }

    return deletedCount;
  }

  /// App 启动时若待清理项 > 50 则前台异步清理
  /// 设计文档 9.4：触发时机
  /// retentionDays <= 0 表示永久保留，不触发
  static Future<void> runIfBacklogLarge(
    EatWiseDatabase db, {
    int? retentionDays,
  }) async {
    final days = retentionDays ?? defaultRetentionDays;
    if (days <= 0) return; // 永久保留，不触发
    final mealRepo = MealLogRepository(db);
    final candidates = await mealRepo.getOldImagePaths(days);
    if (candidates.length > 50) {
      await run(db, retentionDays: days);
    }
  }
}
