import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/legacy.dart'; // Riverpod 3.x：StateNotifier 移至 legacy.dart（主入口不再导出，仅用 legacy 导入）
import 'package:image_picker/image_picker.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/prompts.dart';
import '../../ai/vision_provider.dart';
import '../../core/config/secure_config_store.dart';
import 'circuit_breaker.dart';

/// 拍照识别状态
enum RecognizeState { idle, pickingImage, preprocessing, recognizing, lookupNutrition, done, error, queued }

class RecognizeUiState {
  final RecognizeState state;
  final String? errorMessage;
  final VisionRecognitionResult? recognitionResult;
  final NutritionResult? singleNutrition;
  final CompositeNutritionResult? compositeNutrition;
  final String? imagePath;
  final String mealType; // Sprint 2 T0：餐次（breakfast/lunch/dinner/snack），默认加餐
  // v1.2 一桌多菜：主菜之外的菜品查库结果（与 additionalDishes 一一对应）
  // 每项 (dish, singleNutrition, compositeNutrition) 对应一个 additionalDish 的查库回填
  final List<MultiDishItem> additionalItems;

  RecognizeUiState({
    this.state = RecognizeState.idle,
    this.errorMessage,
    this.recognitionResult,
    this.singleNutrition,
    this.compositeNutrition,
    this.imagePath,
    this.mealType = 'snack',
    this.additionalItems = const [],
  });

  RecognizeUiState copyWith({
    RecognizeState? state,
    String? errorMessage,
    bool clearError = false,
    VisionRecognitionResult? recognitionResult,
    NutritionResult? singleNutrition,
    CompositeNutritionResult? compositeNutrition,
    String? imagePath,
    String? mealType,
    List<MultiDishItem>? additionalItems,
  }) {
    return RecognizeUiState(
      state: state ?? this.state,
      // clearError=true 时显式清空（如重新拍照），否则保留旧错误信息
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      recognitionResult: recognitionResult ?? this.recognitionResult,
      singleNutrition: singleNutrition ?? this.singleNutrition,
      compositeNutrition: compositeNutrition ?? this.compositeNutrition,
      imagePath: imagePath ?? this.imagePath,
      mealType: mealType ?? this.mealType,
      additionalItems: additionalItems ?? this.additionalItems,
    );
  }
}

/// 一桌多菜时，单个菜品的查库结果（v1.2）
class MultiDishItem {
  final VisionRecognitionResult dish;
  final NutritionResult? singleNutrition;
  final CompositeNutritionResult? compositeNutrition;

  const MultiDishItem({
    required this.dish,
    this.singleNutrition,
    this.compositeNutrition,
  });
}

class RecognizeController extends StateNotifier<RecognizeUiState> {
  final VisionProvider _primaryProvider;
  final VisionProvider? _fallbackProvider;
  final NutritionLookup _nutritionLookup;
  // Sprint 2 T14：离线入队回调（page 注入，避免 controller 直接依赖 db）
  // 为 null 时走 Sprint 1 原逻辑（直接报错），向后兼容
  // T23：回调签名加第 4 个参数 promptVersion，透传真实版本
  final Future<void> Function(
          String imagePath, String mealType, String date, String promptVersion)?
      _onOfflineEnqueue;

  // T36：L3 转手动录入回调（page 注入，非 retryable 错误时跳 ManualEntryPage）
  // 为 null 时仅置 error 状态，向后兼容
  final void Function()? _onL3Fallback;

  // T37 断路器（可选，向后兼容 Sprint 3/5 测试）
  final CircuitBreaker? _circuitBreaker;

  // T43 月度识别计数（可选，向后兼容；识别成功后 +1，按月归档）
  final SecureConfigStore? _secureConfigStore;

  // T23：本地限流（每分钟最多 2 次，间隔 30s，防误触连点烧 token）
  DateTime? _lastRecognizeTime;
  static const _minInterval = Duration(seconds: 30);

  RecognizeController(
    this._primaryProvider,
    this._fallbackProvider,
    this._nutritionLookup, {
    Future<void> Function(
            String imagePath, String mealType, String date, String promptVersion)?
        onOfflineEnqueue,
    void Function()? onL3Fallback,
    CircuitBreaker? circuitBreaker,  // T37：可选命名参数（与 T36 onL3Fallback 模式一致）
    SecureConfigStore? secureConfigStore,  // T43：可选命名参数（月度计数）
  })  : _onOfflineEnqueue = onOfflineEnqueue,
        _onL3Fallback = onL3Fallback,
        _circuitBreaker = circuitBreaker,
        _secureConfigStore = secureConfigStore,
        super(RecognizeUiState());

  /// 当前状态（供外部一次性读取，避免直接访问 StateNotifier 的 protected state）
  RecognizeUiState get current => state;

  @visibleForTesting
  DateTime? get lastRecognizeTimeForTest => _lastRecognizeTime;

  @visibleForTesting
  Future<void> Function(String, String, String, String)? get onOfflineEnqueueForTest =>
      _onOfflineEnqueue;

  @visibleForTesting
  void Function()? get onL3FallbackForTest => _onL3Fallback;

  @visibleForTesting
  CircuitBreaker? get circuitBreakerForTest => _circuitBreaker;

  @visibleForTesting
  SecureConfigStore? get secureConfigStoreForTest => _secureConfigStore;

  /// 更新 state.imagePath 为持久化路径（避免 image_picker 临时缓存被系统清理后图片丢失）
  /// 由 recognize_page 在识别成功后调用：把临时路径复制到 app 私有目录，再回写 state
  void updateImagePath(String persistentPath) {
    state = state.copyWith(imagePath: persistentPath);
  }

  /// 拍照入口
  /// Sprint 2 T0：新增 mealType 参数（breakfast/lunch/dinner/snack）
  /// Sprint 2 T14：网络异常时若有 onOfflineEnqueue 则入队，否则报错
  Future<void> pickAndRecognize(ImageSource source,
      {required String mealType}) async {
    // T23 限流：距上次识别不足 30s 则拒绝（防误触连点烧 token）
    final now = DateTime.now();
    if (_lastRecognizeTime != null &&
        now.difference(_lastRecognizeTime!) < _minInterval) {
      final remain = _minInterval - now.difference(_lastRecognizeTime!);
      state = state.copyWith(
        state: RecognizeState.error,
        errorMessage: '操作太快，请等待 ${remain.inSeconds} 秒后再试',
      );
      return;
    }
    // 立即记录时间戳，防竞态：避免连点两次都通过检查（检查与原 L185 set 之间有多个 await）
    _lastRecognizeTime = now;

    state = state.copyWith(
        state: RecognizeState.pickingImage, mealType: mealType, clearError: true);
    XFile? xFile;
    try {
      final picker = ImagePicker();
      xFile = await picker.pickImage(source: source, maxWidth: 1024, maxHeight: 1024);
      if (xFile == null) {
        // 用户取消选图：重置限流时间戳，不惩罚取消行为
        _lastRecognizeTime = null;
        state = state.copyWith(state: RecognizeState.idle);
        return;
      }

      // 预处理：压缩 + 默认剥离 EXIF + 方向校正
      state = state.copyWith(state: RecognizeState.preprocessing);
      final compressedBytes = await FlutterImageCompress.compressWithFile(
        xFile.path,
        minWidth: 1024,
        minHeight: 1024,
        quality: 85,
        // keepExif 默认 false，EXIF 默认剥离
        // autoCorrectionAngle 默认 true，方向校正
      );
      if (compressedBytes == null) {
        state = state.copyWith(state: RecognizeState.error, errorMessage: '图片压缩失败');
        return;
      }

      final imageBase64 = base64Encode(compressedBytes);

      // 调 Vision API（L1 重试 + L2 切备 + L3 转手动 容灾链路）
      state = state.copyWith(state: RecognizeState.recognizing);
      // T37 断路器：open 状态直接走离线入队，不调 API 不烧 token
      if (_circuitBreaker != null && !await _circuitBreaker.allowCall) {
        state = state.copyWith(
          state: RecognizeState.error,
          errorMessage: '识别服务暂时不可用（断路器保护中），已加入离线队列',
        );
        // 直接走离线入队（与外层 catch 一致的入队逻辑）
        // xFile 经上文 if (xFile == null) return 已保证非空，无需重复判空
        if (_onOfflineEnqueue != null) {
          final now = DateTime.now();
          final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
          try {
            await _onOfflineEnqueue(xFile.path, mealType, today, Prompts.version);
            state = state.copyWith(
              state: RecognizeState.queued,
              errorMessage: '识别服务暂时不可用，已加入队列，稍后自动重试',
              imagePath: xFile.path,
            );
          } catch (e) {
            state = state.copyWith(
              state: RecognizeState.error,
              errorMessage: '离线入队失败：$e',
            );
          }
        }
        return;
      }
      VisionRecognitionResult result;
      try {
        result = await _primaryProvider.recognize(imageBase64);
      } on VisionRecognitionException catch (e) {
        // 🚨 T36 关键设计（第2轮 Self-Review 修正）：
        // - retryable 错误（网络/超时/5xx/429 重试失败）必须 rethrow 走【外层 catch 离线入队】
        //   （保留 Sprint 2 T14 P0 离线拍照入队功能）
        // - 只有非 retryable（malformed JSON / 401 / 403）才 L3 转手动
        // - 不能让 L3 吞掉 retryable 错误（否则离线拍照队列会被杀死）
        if (e.retryAfter != null && e.retryAfter!.inSeconds <= 60) {
          // 429：等待 Retry-After 后 L1 重试一次（上限 60s 避免卡死 UI）
          await Future.delayed(e.retryAfter!);
          try {
            result = await _primaryProvider.recognize(imageBase64);
            // L1 重试成功
          } catch (_) {
            // L1 重试失败 → L2 切备（无备则 rethrow 走外层离线入队）
            if (_fallbackProvider == null) rethrow;
            try {
              result = await _fallbackProvider.recognize(imageBase64);
            } catch (_) {
              rethrow; // L2 失败 → 外层离线入队（429 稍后恢复，入队重试合理）
            }
          }
        } else if (!e.retryable) {
          // 非 retryable（malformed JSON / 401 / 403）→ L3 转手动（重试或入队都无法解决）
          _triggerL3Fallback(error: e);
          return;
        } else {
          // retryable 非 429（网络/超时/5xx）→ L2 切备，失败 rethrow 走外层离线入队
          if (_fallbackProvider == null) rethrow;
          try {
            result = await _fallbackProvider.recognize(imageBase64);
          } catch (_) {
            rethrow; // L2 失败 → 外层离线入队（保留 Sprint 2 T14）
          }
        }
      }

      // T37 断路器：识别成功（无论主/L1重试/L2切备）记录成功（halfOpen → closed）
      // best-effort：断路器持久化失败不应覆盖成功识别结果
      if (_circuitBreaker != null) {
        try {
          await _circuitBreaker.recordSuccess();
        } catch (_) {
          // best-effort：持久化失败不影响识别结果展示
        }
      }

      // 查库回填营养素
      state = state.copyWith(
        state: RecognizeState.lookupNutrition,
        recognitionResult: result,
        imagePath: xFile.path,
      );

      // 主菜查库回填
      NutritionResult? mainSingle;
      CompositeNutritionResult? mainComposite;
      if (result.isSingleItem) {
        mainSingle = await _nutritionLookup.lookupSingleItem(
          dishName: result.dishName,
          servingG: result.estimatedWeightGMid,
        );
        // v1.4：库未命中时用 AI 整菜估算兜底；旧 prompt 无估算则保持 null 走弹窗
        mainSingle = mainSingle ?? _aiFallbackNutrition(result);
      } else {
        mainComposite = await _nutritionLookup.lookupCompositeDish(
          components: result.foodComponents,
          cookingMethod: result.cookingMethod,
        );
        // v1.4：复合菜组分全 miss 时用 AI 整菜估算兜底（转走单品路径）
        // lookupCompositeDish 永不返回 null，但 componentHits 为空表示无有效营养数据，
        // 若不兜底会显示 0 kcal 误导用户
        if (mainComposite.componentHits.isEmpty) {
          final fallback = _aiFallbackNutrition(result);
          if (fallback != null) {
            mainSingle = fallback;
            mainComposite = null;
          }
        }
      }

      // v1.2 一桌多菜：对每个 additionalDish 也查库回填
      // 单菜时 additionalDishes 为空，循环跳过，行为同原逻辑
      final additionalItems = <MultiDishItem>[];
      for (final dish in result.additionalDishes) {
        if (dish.isSingleItem) {
          var n = await _nutritionLookup.lookupSingleItem(
            dishName: dish.dishName,
            servingG: dish.estimatedWeightGMid,
          );
          // v1.4：附加菜库未命中也用 AI 兜底
          n = n ?? _aiFallbackNutrition(dish);
          additionalItems.add(MultiDishItem(dish: dish, singleNutrition: n));
        } else {
          final n = await _nutritionLookup.lookupCompositeDish(
            components: dish.foodComponents,
            cookingMethod: dish.cookingMethod,
          );
          // v1.4：附加菜复合菜组分全 miss 也转 AI 兜底（走单品路径）
          if (n.componentHits.isEmpty) {
            final fallback = _aiFallbackNutrition(dish);
            if (fallback != null) {
              additionalItems.add(MultiDishItem(dish: dish, singleNutrition: fallback));
              continue;
            }
          }
          additionalItems.add(MultiDishItem(dish: dish, compositeNutrition: n));
        }
      }

      // T43：识别成功 + 查库回填完成，月度计数 +1（state=done 之前；离线入队/L3 转手动不计数）
      // best-effort：计数失败不覆盖识别结果
      if (_secureConfigStore != null) {
        try {
          final now = DateTime.now();
          await _secureConfigStore.incrementMonthlyCount(now.year, now.month);
        } catch (_) {
          // best-effort：月度计数失败不影响识别结果
        }
      }
      state = state.copyWith(
        state: RecognizeState.done,
        singleNutrition: mainSingle,
        compositeNutrition: mainComposite,
        additionalItems: additionalItems,
      );
    } catch (e) {
      // T37 断路器：retryable 失败记录（连续 3 次 → open）
      // best-effort：断路器操作本身异常不可逃逸 catch 块（否则吞掉原始错误，用户看到的是断路器异常）
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
      // Sprint 2 T14：网络类异常 + 配置了离线回调 → 入队
      if (_onOfflineEnqueue != null &&
          xFile != null &&
          e is VisionRecognitionException &&
          e.retryable) {
        final now = DateTime.now();
        final today =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        try {
          await _onOfflineEnqueue(xFile.path, mealType, today, Prompts.version);
          state = state.copyWith(
            state: RecognizeState.queued,
            errorMessage: '当前离线，已加入队列，联网后自动识别',
            imagePath: xFile.path,
          );
          return;
        } catch (enqueueErr) {
          // 入队失败 → 回退到 error 状态
          state = state.copyWith(
            state: RecognizeState.error,
            errorMessage: '离线入队失败：$enqueueErr',
          );
          return;
        }
      }
      state = state.copyWith(state: RecognizeState.error, errorMessage: e.toString());
    }
  }

  /// T36：L3 转手动录入触发器
  /// 非 retryable 错误（malformed JSON / 401 / 403）调用：重试或入队都无法解决，
  /// 引导用户转手动录入。onL3Fallback 为 null 时仅置 error 状态（向后兼容）。
  /// T39：error 携带 isRefusal 标记时，提示文案区分"内容被安全过滤"。
  void _triggerL3Fallback({VisionRecognitionException? error}) {
    final isRefusal = error?.isRefusal ?? false;
    if (_onL3Fallback != null) {
      state = state.copyWith(
        state: RecognizeState.error,
        errorMessage: isRefusal ? '内容被安全过滤，已转手动录入' : '识别失败，已转手动录入',
      );
      _onL3Fallback();
    } else {
      state = state.copyWith(
        state: RecognizeState.error,
        errorMessage: isRefusal ? '内容被安全过滤' : '识别失败',
      );
    }
  }

  /// v1.4：库未命中时的 AI 整菜估算兜底（prompt v1.4 提供 estimated_calories 等字段）。
  /// 返回 null 表示无 AI 估算（旧 prompt 兼容），调用方保持 null 走未命中弹窗。
  /// foodItemId=0 为哨兵，recognize_page 写库前用 upsertAiRecognized 创建 food_item 替换为真实 id。
  NutritionResult? _aiFallbackNutrition(VisionRecognitionResult r) {
    final cal = r.estimatedCalories;
    if (cal == null) return null;
    return NutritionResult(
      foodItemId: 0,
      calories: cal,
      proteinG: r.estimatedProteinG ?? 0,
      fatG: r.estimatedFatG ?? 0,
      carbsG: r.estimatedCarbsG ?? 0,
      oilG: 0,
      source: NutritionSource.aiEstimate,
    );
  }
}

