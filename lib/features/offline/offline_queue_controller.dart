import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/vision_provider.dart';
import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/pending_recognition_repository.dart';
import '../recognize/providers.dart' as recognize;

/// 离线队列前台触发控制器
/// 监听 connectivity_plus 网络恢复事件，自动回补 pending 识别（重试上限 3 次）
///
/// 设计：VisionProvider 通过构造注入（便于测试用 Fake），生产环境传 QwenVlProvider
class OfflineQueueController {
  final EatWiseDatabase _db;
  final VisionProvider _visionProvider;
  final NutritionLookup _nutritionLookup;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _wasOffline = true;
  bool _processing = false;

  OfflineQueueController({
    required EatWiseDatabase db,
    required VisionProvider visionProvider,
    required NutritionLookup nutritionLookup,
  })  : _db = db,
        _visionProvider = visionProvider,
        _nutritionLookup = nutritionLookup;

  /// 启动监听（App 启动时调用）
  Future<void> start() async {
    // 取初始状态
    final initial = await Connectivity().checkConnectivity();
    _wasOffline = initial.every((r) => r == ConnectivityResult.none);

    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (_wasOffline && isOnline) {
        // 网络恢复 → 触发回补
        processPending();
      }
      _wasOffline = !isOnline;
    });

    // 启动时若已在线也尝试一次（处理上次崩溃残留）
    if (!_wasOffline) {
      await processPending();
    }
  }

  /// 停止监听
  void stop() => _sub?.cancel();

  /// 处理所有 pending 记录
  /// 公开方法：测试可手动触发（沙箱无法模拟真实网络切换）
  Future<void> processPending() async {
    if (_processing) return; // 防重入
    _processing = true;
    try {
      final pendingRepo = PendingRecognitionRepository(_db);
      final pending = await pendingRepo.listPending();
      if (pending.isEmpty) return;

      final mealRepo = MealLogRepository(_db);

      for (final p in pending) {
        try {
          // 读图片 base64
          final imageFile = File(p.imagePath);
          if (!imageFile.existsSync()) {
            // 图片缺失是不可恢复错误，直接标记 failed（不重试）
            await pendingRepo.markFailed(p.id, '图片文件不存在', permanent: true);
            continue;
          }
          final imageBase64 = base64Encode(await imageFile.readAsBytes());

          // 调视觉模型
          final result = await _visionProvider.recognize(imageBase64);

          // 查库回填营养素
          final nutrition = await _nutritionLookup.lookupSingleItem(
            dishName: result.dishName,
            servingG: result.estimatedWeightGMid,
          );

          if (nutrition == null) {
            // 查库未命中 → upsertAiRecognized 后再标记 done
            final foodItemRepo = FoodItemRepository(_db);
            final foodId = await foodItemRepo.upsertAiRecognized(
              name: result.dishName,
              caloriesPer100g: 0,
              proteinPer100g: 0,
              fatPer100g: 0,
              carbsPer100g: 0,
              confidence: result.confidence,
            );
            await pendingRepo.markDone(p.id, foodId);
            continue;
          }

          // 写 meal_log
          await mealRepo.insertMealLog(
            date: p.date,
            mealType: p.mealType,
            foodItemId: nutrition.foodItemId,
            actualServingG: result.estimatedWeightGMid,
            actualCalories: nutrition.calories,
            actualProteinG: nutrition.proteinG,
            actualFatG: nutrition.fatG,
            actualCarbsG: nutrition.carbsG,
            originalImagePath: p.imagePath,
            recognitionConfidence: result.confidence,
          );
          await pendingRepo.markDone(p.id, nutrition.foodItemId);
        } catch (e) {
          await pendingRepo.markFailed(p.id, e.toString());
        }
      }
    } finally {
      _processing = false;
    }
  }
}

/// Riverpod Provider：OfflineQueueController 单例
/// App 启动时通过 ref.read(offlineQueueControllerProvider).start() 启动监听
final offlineQueueControllerProvider =
    FutureProvider<OfflineQueueController>((ref) async {
  final db = await ref.read(recognize.databaseProvider.future);
  final qwen = ref.read(recognize.qwenVlProviderProvider);
  final lookup = await ref.read(recognize.nutritionLookupProvider.future);
  return OfflineQueueController(
    db: db,
    visionProvider: qwen,
    nutritionLookup: lookup,
  );
});
