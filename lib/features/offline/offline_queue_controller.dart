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
import '../recognize/circuit_breaker.dart';
import '../recognize/providers.dart' as recognize;

/// 离线队列前台触发控制器
/// 监听 connectivity_plus 网络恢复事件，自动回补 pending 识别（重试上限 3 次）
///
/// 设计：VisionProvider 通过构造注入（便于测试用 Fake），生产环境传 QwenVlProvider
class OfflineQueueController {
  final EatWiseDatabase _db;
  final VisionProvider _visionProvider;
  final VisionProvider? _fallbackProvider;
  final NutritionLookup _nutritionLookup;
  final CircuitBreaker? _circuitBreaker; // T37：后台回补断路器（可选）
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _wasOffline = true;
  bool _processing = false;

  OfflineQueueController({
    required EatWiseDatabase db,
    required VisionProvider visionProvider,
    VisionProvider? fallbackProvider,
    required NutritionLookup nutritionLookup,
    CircuitBreaker? circuitBreaker, // T37：可选命名参数（与 recognize_controller 模式一致）
  })  : _db = db,
        _visionProvider = visionProvider,
        _fallbackProvider = fallbackProvider,
        _nutritionLookup = nutritionLookup,
        _circuitBreaker = circuitBreaker;

  /// 启动监听（App 启动时调用）
  Future<void> start() async {
    // 取初始状态
    final initial = await Connectivity().checkConnectivity();
    _wasOffline = initial.every((r) => r == ConnectivityResult.none);

    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (_wasOffline && isOnline) {
        // 网络恢复 → 触发回补（fire-and-forget，内部已 catch）
        processPending().catchError((_) {});
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
          // 读图片 base64（异步 exists 避免阻塞 UI）
          final imageFile = File(p.imagePath);
          if (!await imageFile.exists()) {
            // 图片缺失是不可恢复错误，直接标记 failed（不重试）
            await pendingRepo.markFailed(p.id, '图片文件不存在', permanent: true);
            continue;
          }
          final imageBase64 = base64Encode(await imageFile.readAsBytes());

          // T37 断路器：open 状态跳过本条（不调 API），直接 continue 保留 pending 状态
          // 【第2轮 Self-Review 修正】：不能调 markFailed！markFailed 会增加 retryCount
          //   （pending_recognition_repository.dart：retryCount 达 3 标 failed 永久不重试），
          //   断路器 open 30s 期间多次 processPending 会触发上限导致 pending 永久 failed。
          //   正确做法：直接 continue，保留 pending 状态，等断路器恢复后下次 processPending 重试。
          if (_circuitBreaker != null && !await _circuitBreaker.allowCall) {
            continue; // 保留 pending，不调 markFailed，等断路器恢复
          }

          // 调视觉模型（30s 超时，避免单条卡死整队列）
          // 主失败 → fallback（与 recognize_controller.dart 主备降级一致）
          VisionRecognitionResult result;
          try {
            result = await _visionProvider
                .recognize(imageBase64)
                .timeout(const Duration(seconds: 30));
          } catch (e) {
            if (_fallbackProvider == null) rethrow;
            result = await _fallbackProvider
                .recognize(imageBase64)
                .timeout(const Duration(seconds: 30));
          }

          // T37 断路器：视觉调用成功记录成功（halfOpen → closed）
          if (_circuitBreaker != null) await _circuitBreaker.recordSuccess();

          // 查库回填营养素：区分单品 / 复合菜
          // （修复 bug：原无条件 lookupSingleItem 导致复合菜 nutrition==null 静默丢弃）
          int foodItemId;
          double actualCalories, actualProteinG, actualFatG, actualCarbsG;
          double actualServingG = result.estimatedWeightGMid;
          String? componentsJson;

          if (result.isSingleItem) {
            final nutrition = await _nutritionLookup.lookupSingleItem(
              dishName: result.dishName,
              servingG: result.estimatedWeightGMid,
            );
            if (nutrition == null) {
              // 单品未命中 → upsert 0 卡 + markDone（保留原逻辑：单品无营养数据无法记录热量）
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
            foodItemId = nutrition.foodItemId;
            actualCalories = nutrition.calories;
            actualProteinG = nutrition.proteinG;
            actualFatG = nutrition.fatG;
            actualCarbsG = nutrition.carbsG;
          } else {
            // 复合菜 → lookupCompositeDish（组分累加 + 烹饪用油）
            final composite = await _nutritionLookup.lookupCompositeDish(
              components: result.foodComponents,
              cookingMethod: result.cookingMethod,
            );
            // 复合菜 upsert ai_recognized（存组分快照，热量在 meal_log）
            final foodItemRepo = FoodItemRepository(_db);
            componentsJson = jsonEncode({
              'components': result.foodComponents
                  .map((c) => {'name': c.name, 'estimated_g': c.estimatedG})
                  .toList(),
              'oil_g': composite.oilG,
            });
            foodItemId = await foodItemRepo.upsertAiRecognized(
              name: result.dishName,
              caloriesPer100g: 0, // 复合菜热量不按 100g 密度存储
              proteinPer100g: 0,
              fatPer100g: 0,
              carbsPer100g: 0,
              confidence: result.confidence,
              componentsJson: componentsJson,
            );
            actualCalories = composite.calories;
            actualProteinG = composite.proteinG;
            actualFatG = composite.fatG;
            actualCarbsG = composite.carbsG;
            actualServingG = result.foodComponents
                .fold<double>(0, (s, c) => s + c.estimatedG);
          }

          // 写 meal_log（复合菜不再静默丢弃）
          await mealRepo.insertMealLog(
            date: p.date,
            mealType: p.mealType,
            foodItemId: foodItemId,
            actualServingG: actualServingG,
            actualCalories: actualCalories,
            actualProteinG: actualProteinG,
            actualFatG: actualFatG,
            actualCarbsG: actualCarbsG,
            originalImagePath: p.imagePath,
            recognitionConfidence: result.confidence,
            componentsSnapshotJson: componentsJson,
          );
          await pendingRepo.markDone(p.id, foodItemId);
        } catch (e) {
          // T37 断路器：retryable 视觉调用失败记录（halfOpen 失败 → 重新 open）
          if (_circuitBreaker != null &&
              e is VisionRecognitionException &&
              e.retryable) {
            final breakerState = await _circuitBreaker.state;
            if (breakerState == CircuitBreakerState.halfOpen) {
              await _circuitBreaker.recordHalfOpenFailure();
            } else {
              await _circuitBreaker.recordFailure();
            }
          }
          await pendingRepo.markFailed(p.id, e.toString());
        }
      }
    } catch (_) {
      // listPending / DB 异常：吞掉避免未观察异常，下次网络恢复重试
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
  final glm4v = ref.read(recognize.glm4vProviderProvider);
  final lookup = await ref.read(recognize.nutritionLookupProvider.future);
  final breaker = ref.read(recognize.circuitBreakerProvider); // T37：注入断路器
  final controller = OfflineQueueController(
    db: db,
    visionProvider: qwen,
    fallbackProvider: glm4v,
    nutritionLookup: lookup,
    circuitBreaker: breaker, // T37：后台回补接入断路器
  );
  // Provider 销毁时停止 connectivity 订阅，避免 StreamSubscription 泄漏
  ref.onDispose(controller.stop);
  return controller;
});
