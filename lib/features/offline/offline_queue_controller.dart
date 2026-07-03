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
    // fire-and-forget：不 await，避免 pending 多时阻塞 app 启动序列数分钟
    if (!_wasOffline) {
      processPending().catchError((_) {});
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
            break; // 断路器 open：跳过本批所有 pending，等恢复后下次 processPending 重试
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
          // best-effort：断路器持久化失败不影响主流程（与 recognize_controller 一致）
          if (_circuitBreaker != null) {
            try {
              await _circuitBreaker.recordSuccess();
            } catch (_) {}
          }

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
              // v1.4：单品库未命中，用 AI 整菜估算兜底（与前台 recognize_controller 对齐）
              // 若 AI 无估算（旧 prompt）：不创建 0 卡 food_item（会污染未来查库），不写 meal_log，
              // 标记 failed 让用户后续手动处理，避免静默丢失餐次
              final cal = result.estimatedCalories;
              if (cal == null) {
                await pendingRepo.markFailed(
                    p.id, 'AI 无估算且库未命中，需手动录入', permanent: true);
                continue;
              }
              // AI 兜底：per100g 基于 mid 份量反算（与 recognize_page 哨兵处理一致）
              final mid = result.estimatedWeightGMid;
              final per100 = mid > 0 ? 100.0 / mid : 0.0;
              final foodItemRepo = FoodItemRepository(_db);
              foodItemId = await foodItemRepo.upsertAiRecognized(
                name: result.dishName,
                caloriesPer100g: cal * per100,
                proteinPer100g: (result.estimatedProteinG ?? 0) * per100,
                fatPer100g: (result.estimatedFatG ?? 0) * per100,
                carbsPer100g: (result.estimatedCarbsG ?? 0) * per100,
                confidence: result.confidence,
              );
              actualCalories = cal;
              actualProteinG = result.estimatedProteinG ?? 0;
              actualFatG = result.estimatedFatG ?? 0;
              actualCarbsG = result.estimatedCarbsG ?? 0;
            } else {
              foodItemId = nutrition.foodItemId;
              actualCalories = nutrition.calories;
              actualProteinG = nutrition.proteinG;
              actualFatG = nutrition.fatG;
              actualCarbsG = nutrition.carbsG;
            }
          } else {
            // 复合菜 → lookupCompositeDish（组分累加 + 烹饪用油）
            final composite = await _nutritionLookup.lookupCompositeDish(
              components: result.foodComponents,
              cookingMethod: result.cookingMethod,
            );
            if (composite.componentHits.isEmpty &&
                result.estimatedCalories != null) {
              // v1.4：复合菜组分全 miss 时用 AI 整菜估算兜底（与前台对齐）
              final mid = result.estimatedWeightGMid;
              final per100 = mid > 0 ? 100.0 / mid : 0.0;
              final foodItemRepo = FoodItemRepository(_db);
              foodItemId = await foodItemRepo.upsertAiRecognized(
                name: result.dishName,
                caloriesPer100g: result.estimatedCalories! * per100,
                proteinPer100g: (result.estimatedProteinG ?? 0) * per100,
                fatPer100g: (result.estimatedFatG ?? 0) * per100,
                carbsPer100g: (result.estimatedCarbsG ?? 0) * per100,
                confidence: result.confidence,
              );
              actualCalories = result.estimatedCalories!;
              actualProteinG = result.estimatedProteinG ?? 0;
              actualFatG = result.estimatedFatG ?? 0;
              actualCarbsG = result.estimatedCarbsG ?? 0;
            } else if (composite.componentHits.isEmpty) {
              // 复合菜组分全 miss 且 AI 无估算（旧 prompt）：不写近 0 卡 meal_log，
              // 标记 failed 让用户手动处理（与前台 recognize_controller 行为一致）
              await pendingRepo.markFailed(
                  p.id, '复合菜组分全 miss 且 AI 无估算，需手动录入',
                  permanent: true);
              continue;
            } else {
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
          }

          // 写 meal_log + 标记 done（事务包裹：原子化，防 insertMealLog 成功但 markDone
          // 失败导致下次重试产生重复 meal_log 记录）
          await _db.transaction(() async {
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
          });
        } catch (e) {
          // T37 断路器：retryable 视觉调用失败记录（halfOpen 失败 → 重新 open）
          // best-effort：断路器操作本身异常不可逃逸 catch 块
          if (_circuitBreaker != null &&
              e is VisionRecognitionException &&
              e.retryable) {
            try {
              final breakerState = await _circuitBreaker.state;
              if (breakerState == CircuitBreakerState.halfOpen) {
                await _circuitBreaker.recordHalfOpenFailure();
              } else {
                await _circuitBreaker.recordFailure();
              }
            } catch (_) {
              // best-effort：断路器持久化失败不逃逸
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
