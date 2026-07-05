import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/vision_provider.dart';
import '../../core/config/secure_config_store.dart';
import '../../core/util/recognition_post_processor.dart';
import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/pending_recognition_repository.dart';
import '../../data/seed/food_category_defaults.dart';
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
  // M11：月度识别计数（可选，与 recognize_controller 模式一致）
  // 后台回补成功时 +1，设置页"本月识别次数"与实际 token 消耗对齐
  final SecureConfigStore? _secureConfigStore;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _wasOffline = true;
  bool _processing = false;

  OfflineQueueController({
    required EatWiseDatabase db,
    required VisionProvider visionProvider,
    VisionProvider? fallbackProvider,
    required NutritionLookup nutritionLookup,
    CircuitBreaker? circuitBreaker, // T37：可选命名参数（与 recognize_controller 模式一致）
    SecureConfigStore? secureConfigStore, // M11：可选命名参数（月度计数）
  })  : _db = db,
        _visionProvider = visionProvider,
        _fallbackProvider = fallbackProvider,
        _nutritionLookup = nutritionLookup,
        _circuitBreaker = circuitBreaker,
        _secureConfigStore = secureConfigStore;

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

          // 调视觉模型（60s 超时，避免单条卡死整队列）
          // M16.2：30→60s，与 qwen_vl_provider.dart 一致，复杂图识别需要时间
          // 主失败 → fallback（与 recognize_controller.dart 主备降级一致）
          VisionRecognitionResult result;
          try {
            result = await _visionProvider
                .recognize(imageBase64)
                .timeout(const Duration(seconds: 60));
          } catch (e) {
            if (_fallbackProvider == null) rethrow;
            result = await _fallbackProvider
                .recognize(imageBase64)
                .timeout(const Duration(seconds: 60));
          }

          // T37 断路器：视觉调用成功记录成功（halfOpen → closed）
          // best-effort：断路器持久化失败不影响主流程（与 recognize_controller 一致）
          if (_circuitBreaker != null) {
            try {
              await _circuitBreaker.recordSuccess();
            } catch (_) {}
          }

          // 第二波：后处理（密度换算 + 校验修正），与前台 recognize_controller 一致
          // 修复第一波盲区：离线回补原直接用原始 result，包装液体未换算 ml→g、
          // 营养素不自洽未修正、组分份量不自洽未缩放，导致前后台行为分叉。
          result = RecognitionPostProcessor.process(result);

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
              brand: result.brand,
            );
            if (nutrition == null) {
              // v1.4：单品库未命中，用 AI 整菜估算兜底（与前台 recognize_controller 对齐）
              // 若 AI 无估算（旧 prompt）：不创建 0 卡 food_item（会污染未来查库），不写 meal_log，
              // 标记 failed 让用户后续手动处理，避免静默丢失餐次
              final cal = result.estimatedCalories;
              if (cal == null) {
                // M16.2：permanent: true → false（让用户可改菜名重试）
                // 原 permanent: true 让记录永久 failed 无法恢复，但此场景可通过
                // recognize_page 改菜名重试解决，不应永久放弃
                await pendingRepo.markFailed(
                    p.id, 'AI 无估算且库未命中，需手动录入或改菜名重试');
                continue;
              }
              // v1.9：包装食品 OCR 优先路径——有包装营养表数据时按包装换算，
              // 跳过品类校准（包装数据是精确值，不需要校准）
              // 与 recognize_page 哨兵分支 / multi_dish_page resolveSingleFoodItemId 一致
              // 参考 prompts.dart v1.9 规则 10 + 示例 7（珍宝珠酸条）
              // v1.10：包装换算后宏量全 0 但 cal>0（含糖饮料 AI 漏填宏量）→ 回退品类校准，
              //   避免含糖饮料碳水显示 0（computePackageNutritionPer100g 三层兜底仍 0 时）
              final mid = result.estimatedWeightGMid;
              final per100 = mid > 0 ? 100.0 / mid : 0.0;
              final packagePer100 = result.hasPackageNutrition
                  ? result.computePackageNutritionPer100g(
                      estimatedProteinG: result.estimatedProteinG,
                      estimatedFatG: result.estimatedFatG,
                      estimatedCarbsG: result.estimatedCarbsG,
                    )
                  : null;
              // v1.10：判断包装换算宏量是否全 0（含糖饮料 AI 漏填宏量特征）
              final packageMacrosAllZero = packagePer100 != null &&
                  packagePer100.$2 == 0 &&
                  packagePer100.$3 == 0 &&
                  packagePer100.$4 == 0;
              final (caloriesPer100g, proteinPer100g, fatPer100g, carbsPer100g) =
                  (packagePer100 != null && !packageMacrosAllZero)
                      ? packagePer100
                      : (() {
                          // 无包装数据 / 包装换算宏量全 0 → 走 AI 估算 + 品类校准路径
                          // P0：品类默认值校准——AI 估算的 per100g 偏离品类默认值 2 倍以上
                          // 用默认值替代（防 AI 离谱估算，如啤酒估成 200 kcal/100g 实际 43）
                          return FoodCategoryDefaults.calibrate(
                            aiCaloriesPer100g: cal * per100,
                            aiProteinPer100g:
                                (result.estimatedProteinG ?? 0) * per100,
                            aiFatPer100g: (result.estimatedFatG ?? 0) * per100,
                            aiCarbsPer100g:
                                (result.estimatedCarbsG ?? 0) * per100,
                            category: result.foodCategory,
                          );
                        })();
              final foodItemRepo = FoodItemRepository(_db);
              foodItemId = await foodItemRepo.upsertAiRecognized(
                name: result.dishName,
                brand: result.brand,
                caloriesPer100g: caloriesPer100g,
                proteinPer100g: proteinPer100g,
                fatPer100g: fatPer100g,
                carbsPer100g: carbsPer100g,
                confidence: result.confidence,
              );
              // v1.9：有包装数据时 actualCalories 用包装换算整菜热量
              // （与 recognize_controller._aiFallbackNutrition 一致，达到豆包级精度）
              // 无包装数据时用 AI 估算整菜值
              // v1.10：包装换算宏量全 0 时也走 AI 估算整菜值（与 per100g 路径一致，
              //   per100g 已回退品类校准，actualCalories 不再用包装换算避免两者脱节）
              // 蛋白/脂肪/碳水：actual* 用 AI 估算原值
              //   （proteinPer100g × mid / 100 = estimatedProteinG，数学等价）
              if (packagePer100 != null && !packageMacrosAllZero && mid > 0) {
                actualCalories = caloriesPer100g * mid / 100;
              } else {
                actualCalories = cal;
              }
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
              // v1.9：包装食品 OCR 优先路径——若复合菜恰好是预包装速冻食品等
              // （如速冻水饺被识别为 composite 但有包装营养表），优先用包装数据换算
              // 复合菜不做品类校准（无 meaningful food category），AI 估算路径直接用原值
              // v1.10：包装换算后宏量全 0 但 cal>0（含糖饮料 AI 漏填宏量）→ 回退 AI 估算，
              //   避免复合菜路径宏量显示 0（与单品路径 / 前台哨兵分支一致）
              final mid = result.estimatedWeightGMid;
              final per100 = mid > 0 ? 100.0 / mid : 0.0;
              final packagePer100 = result.hasPackageNutrition
                  ? result.computePackageNutritionPer100g(
                      estimatedProteinG: result.estimatedProteinG,
                      estimatedFatG: result.estimatedFatG,
                      estimatedCarbsG: result.estimatedCarbsG,
                    )
                  : null;
              // v1.10：判断包装换算宏量是否全 0（含糖饮料 AI 漏填宏量特征）
              final packageMacrosAllZero = packagePer100 != null &&
                  packagePer100.$2 == 0 &&
                  packagePer100.$3 == 0 &&
                  packagePer100.$4 == 0;
              final (caloriesPer100g, proteinPer100g, fatPer100g, carbsPer100g) =
                  (packagePer100 != null && !packageMacrosAllZero)
                      ? packagePer100
                      : (() {
                          // 无包装数据 / 包装换算宏量全 0 → 走原 AI 估算路径（复合菜不做品类校准）
                          return (
                            result.estimatedCalories! * per100,
                            (result.estimatedProteinG ?? 0) * per100,
                            (result.estimatedFatG ?? 0) * per100,
                            (result.estimatedCarbsG ?? 0) * per100,
                          );
                        })();
              final foodItemRepo = FoodItemRepository(_db);
              foodItemId = await foodItemRepo.upsertAiRecognized(
                name: result.dishName,
                brand: result.brand,
                caloriesPer100g: caloriesPer100g,
                proteinPer100g: proteinPer100g,
                fatPer100g: fatPer100g,
                carbsPer100g: carbsPer100g,
                confidence: result.confidence,
              );
              // v1.9：有包装数据时 actualCalories 用包装换算整菜热量（与单品路径一致）
              // 无包装数据时用 AI 估算整菜值
              // v1.10：包装换算宏量全 0 时也走 AI 估算整菜值（与 per100g 路径一致，
              //   per100g 已回退 AI 估算，actualCalories 不再用包装换算避免两者脱节）
              if (packagePer100 != null && !packageMacrosAllZero && mid > 0) {
                actualCalories = caloriesPer100g * mid / 100;
              } else {
                actualCalories = result.estimatedCalories!;
              }
              actualProteinG = result.estimatedProteinG ?? 0;
              actualFatG = result.estimatedFatG ?? 0;
              actualCarbsG = result.estimatedCarbsG ?? 0;
            } else if (composite.componentHits.isEmpty) {
              // 复合菜组分全 miss 且 AI 无估算（旧 prompt）：不写近 0 卡 meal_log，
              // 标记 failed 让用户手动处理（与前台 recognize_controller 行为一致）
              // M16.2：permanent: true → false（让用户可改菜名重试，与单品路径一致）
              await pendingRepo.markFailed(
                  p.id, '复合菜组分全 miss 且 AI 无估算，需手动录入或改菜名重试');
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
              // v1.9：复合菜有包装营养表数据时（预包装速冻食品等），按包装换算
              // per100g + actualCalories 都用包装换算值，跳过组分累加
              // 无包装数据 → 走原组分累加路径（per100g=0，actualCalories=composite.calories）
              // v1.10：包装换算后宏量全 0 但 cal>0（含糖饮料 AI 漏填宏量）→ 回退组分累加，
              //   避免复合菜路径宏量显示 0（与单品路径 / 前台哨兵分支一致）
              actualServingG = result.foodComponents
                  .fold<double>(0, (s, c) => s + c.estimatedG);
              final packagePer100 = result.hasPackageNutrition
                  ? result.computePackageNutritionPer100g(
                      estimatedProteinG: result.estimatedProteinG,
                      estimatedFatG: result.estimatedFatG,
                      estimatedCarbsG: result.estimatedCarbsG,
                    )
                  : null;
              // v1.10：判断包装换算宏量是否全 0（含糖饮料 AI 漏填宏量特征）
              final packageMacrosAllZero = packagePer100 != null &&
                  packagePer100.$2 == 0 &&
                  packagePer100.$3 == 0 &&
                  packagePer100.$4 == 0;
              if (packagePer100 != null && !packageMacrosAllZero) {
                // 有包装：per100g 存包装换算值（未来查库按密度算更准），
                // actualCalories 按 actualServingG 换算（与份量一致）
                foodItemId = await foodItemRepo.upsertAiRecognized(
                  name: result.dishName,
                  brand: result.brand,
                  caloriesPer100g: packagePer100.$1,
                  proteinPer100g: packagePer100.$2,
                  fatPer100g: packagePer100.$3,
                  carbsPer100g: packagePer100.$4,
                  confidence: result.confidence,
                  componentsJson: componentsJson,
                );
                actualCalories = packagePer100.$1 * actualServingG / 100;
                actualProteinG = packagePer100.$2 * actualServingG / 100;
                actualFatG = packagePer100.$3 * actualServingG / 100;
                actualCarbsG = packagePer100.$4 * actualServingG / 100;
              } else {
                // 无包装 / 包装换算宏量全 0 → 组分累加（原逻辑）
                foodItemId = await foodItemRepo.upsertAiRecognized(
                  name: result.dishName,
                  brand: result.brand,
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
              }
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

          // M11：后台回补成功计入月度识别次数（与前台 recognize_controller 一致）
          // 事务成功后才计数（事务失败会被 catch 块 markFailed，不应计数）
          // best-effort：计数失败不覆盖回补主流程（与 recognize_controller 模式一致）
          if (_secureConfigStore != null) {
            try {
              final now = DateTime.now();
              await _secureConfigStore.incrementMonthlyCount(now.year, now.month);
            } catch (e) {
              debugPrint('M11 incrementMonthlyCount 失败（不影响回补）：$e');
            }
          }
        } catch (e) {
          // T37 断路器：retryable 视觉调用失败记录（halfOpen 失败 → 重新 open）
          // M16.2：429 限流不计入失败计数（isRateLimit=true），与 recognize_controller 一致
          // best-effort：断路器操作本身异常不可逃逸 catch 块
          if (_circuitBreaker != null &&
              e is VisionRecognitionException &&
              e.retryable) {
            try {
              final breakerState = await _circuitBreaker.state;
              if (breakerState == CircuitBreakerState.halfOpen) {
                await _circuitBreaker.recordHalfOpenFailure();
              } else {
                final isRateLimit = e.reason.contains('限流 429');
                await _circuitBreaker.recordFailure(isRateLimit: isRateLimit);
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
  final store = SecureConfigStore(); // M11：注入月度计数 store
  final controller = OfflineQueueController(
    db: db,
    visionProvider: qwen,
    fallbackProvider: glm4v,
    nutritionLookup: lookup,
    circuitBreaker: breaker, // T37：后台回补接入断路器
    secureConfigStore: store, // M11：后台回补计入月度识别次数
  );
  // Provider 销毁时停止 connectivity 订阅，避免 StreamSubscription 泄漏
  ref.onDispose(controller.stop);
  return controller;
});
