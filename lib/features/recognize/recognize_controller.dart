import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/legacy.dart'; // Riverpod 3.x：StateNotifier 移至 legacy.dart（主入口不再导出，仅用 legacy 导入）
import 'package:image_picker/image_picker.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/prompts.dart';
import '../../ai/vision_provider.dart';
import '../../ai/food_density.dart';
import '../../core/config/secure_config_store.dart';
import '../../core/util/image_quality_checker.dart';
import '../../core/util/recognition_validator.dart';
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

      // 图片预检：模糊图直接拒识（避免垃圾输入导致必错识别，浪费 token）
      // 阈值 50，低于判定模糊，提示用户重拍
      final isBlurry = await ImageQualityChecker.isBlurry(compressedBytes);
      if (isBlurry) {
        state = state.copyWith(
          state: RecognizeState.error,
          errorMessage: '图片较模糊，请擦净镜头后重拍',
        );
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

      // 批次 1：识别结果校验（字段合理性 + 营养素自洽性）
      // - 字段严重不合理（dishName 空 / confidence 越界 / weight 非正 / 区间倒置）→ 重试 1 次
      // - 营养素不自洽（4p+9f+4c ≠ cal，误差>10%）→ 用宏量营养素反推修正 calories
      // - 校验失败原因 best-effort 上报 Sentry（不阻塞识别）
      result = await _validateAndMaybeRetry(imageBase64, result);

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

  /// 建议 3：包装液体食品按密度换算 ml→g
  ///
  /// prompt v1.6 让 AI 读取包装净含量填 per_unit_g，但液体 ml 数值 ≠ g 数值：
  ///   - 食用油 1ml≈0.92g → 100ml 按 100g 算低估 8%
  ///   - 蜂蜜 1ml≈1.42g → 100ml 按 100g 算低估 42%
  ///   - 烈酒 1ml≈0.79g → 100ml 按 100g 算高估 21%
  ///
  /// 换算条件：weight_source=package_label（包装标签）+ food_category 是液体类别
  /// 换算后重算 perUnitG + estimatedWeightG*（按 quantity * realPerUnitG）
  /// 区间按 ±3% 估算（包装标注误差）
  ///
  /// 水基饮料（carbonated/water/soup 密度=1.0）换算后无变化，直接返回不重建
  VisionRecognitionResult _applyDensityConversion(VisionRecognitionResult original) {
    // 主菜换算
    final convertedMain = _convertDensityForDish(original);

    // 附加菜换算
    if (original.additionalDishes.isEmpty) return convertedMain;
    final convertedAdditional =
        original.additionalDishes.map(_convertDensityForDish).toList();

    // 主菜无变化 + 附加菜无变化 → 直接返回（避免无谓重建）
    // _convertDensityForDish 不换算时返回原引用，用 identical 比较即可
    if (identical(convertedMain, original) &&
        _listIdentical(convertedAdditional, original.additionalDishes)) {
      return original;
    }

    // 重建带换算后的附加菜
    return VisionRecognitionResult(
      dishName: convertedMain.dishName,
      brand: convertedMain.brand,
      estimatedWeightGLow: convertedMain.estimatedWeightGLow,
      estimatedWeightGMid: convertedMain.estimatedWeightGMid,
      estimatedWeightGHigh: convertedMain.estimatedWeightGHigh,
      foodComponents: convertedMain.foodComponents,
      cookingMethod: convertedMain.cookingMethod,
      isSingleItem: convertedMain.isSingleItem,
      confidence: convertedMain.confidence,
      promptVersion: convertedMain.promptVersion,
      additionalDishes: convertedAdditional,
      quantity: convertedMain.quantity,
      unit: convertedMain.unit,
      perUnitG: convertedMain.perUnitG,
      estimatedCalories: convertedMain.estimatedCalories,
      estimatedProteinG: convertedMain.estimatedProteinG,
      estimatedFatG: convertedMain.estimatedFatG,
      estimatedCarbsG: convertedMain.estimatedCarbsG,
      weightSource: convertedMain.weightSource,
      foodCategory: convertedMain.foodCategory,
    );
  }

  /// 单个 dish 的密度换算（仅包装液体）
  VisionRecognitionResult _convertDensityForDish(VisionRecognitionResult r) {
    // 仅对包装标签 + 液体类别换算
    if (r.weightSource != 'package_label') return r;
    if (!isLiquidCategory(r.foodCategory)) return r;
    final density = densityOf(r.foodCategory);
    // 密度=1.0（水基饮料）无需换算
    if (density == 1.0) return r;
    // perUnitG 为 0 或负数不换算（防除零/异常）
    if (r.perUnitG <= 0) return r;

    final realPerUnitG = r.perUnitG * density;
    final realMid = realPerUnitG * r.quantity;
    // 区间按 ±3% 估算（包装标注误差）
    final realLow = realMid * 0.97;
    final realHigh = realMid * 1.03;

    debugPrint('[DensityConversion] ${r.dishName}(${r.foodCategory}) '
        'perUnitG: ${r.perUnitG}→${realPerUnitG.toStringAsFixed(1)}, '
        'mid: ${r.estimatedWeightGMid}→${realMid.toStringAsFixed(1)} '
        '(density=$density)');

    return r.copyWith(
      perUnitG: realPerUnitG,
      estimatedWeightGLow: realLow,
      estimatedWeightGMid: realMid,
      estimatedWeightGHigh: realHigh,
    );
  }

  /// 判断两个列表的元素是否引用相同（避免无谓重建）
  bool _listIdentical(List<VisionRecognitionResult> a, List<VisionRecognitionResult> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// 批次 1：校验识别结果，必要时重试 + 修正
  ///
  /// 三层处理：
  /// 1. 字段严重不合理（dishName 空 / confidence 越界 / weight 非正 / 区间倒置）
  ///    → 重试 1 次（best-effort：重试异常用原结果，不阻塞用户）
  /// 2. 营养素不自洽（|4p+9f+4c - cal|/cal > 10%）
  ///    → 用宏量营养素反推修正 calories（重试赌运气不稳定，修正更可靠）
  /// 3. additionalDishes 逐个校验修正（不单独重试，重试成本高且会整体重返）
  ///
  /// 校验失败原因 debugPrint（best-effort，不引入 Sentry 依赖避免循环）。
  Future<VisionRecognitionResult> _validateAndMaybeRetry(
    String imageBase64,
    VisionRecognitionResult original,
  ) async {
    // 建议 3：包装液体食品按密度换算 ml→g（在校验和查库前执行，确保后续用真实克数）
    // prompt v1.6 让 AI 读包装净含量填 per_unit_g，但液体的 ml 数值 ≠ g 数值
    // 如 100ml 油 AI 填 per_unit_g=100（实为 ml），真实 92g，需按密度 0.92 换算
    var result = _applyDensityConversion(original);

    // 主菜校验
    final mainValidation = RecognitionValidator.validate(result);
    if (mainValidation.reasons.isNotEmpty) {
      debugPrint('[RecognitionValidator] 主菜校验: ${mainValidation.reasons}');
    }

    // 字段严重不合理 → 重试 1 次（best-effort）
    if (mainValidation.needsRetry) {
      try {
        final retryResult = await _primaryProvider.recognize(imageBase64);
        final retryValidation = RecognitionValidator.validate(retryResult);
        if (retryValidation.reasons.isNotEmpty) {
          debugPrint('[RecognitionValidator] 重试后校验: ${retryValidation.reasons}');
        }
        // 重试结果有效则采用（即使重试后仍有营养素不自洽，下面会修正）
        if (!retryValidation.needsRetry) {
          result = retryResult;
          // 用重试结果的校验做后续修正
          if (retryValidation.correctedCalories != null) {
            result = result.copyWith(
                estimatedCalories: retryValidation.correctedCalories);
          }
          // 建议 7：组分份量交叉验证修正
          if (retryValidation.correctedComponents != null) {
            result =
                result.copyWith(foodComponents: retryValidation.correctedComponents);
          }
          // additionalDishes 修正
          result = _correctAdditionalDishes(result);
          return result;
        }
        // 重试后仍 needsRetry → 用原结果继续（修正 calories 后返回，不阻塞用户）
      } catch (e) {
        debugPrint('[RecognitionValidator] 重试异常，用原结果: $e');
        // 重试异常用原结果继续
      }
    }

    // 主菜 calories 修正（原结果或重试后仍 needsRetry 的结果）
    if (mainValidation.correctedCalories != null) {
      result = result.copyWith(
          estimatedCalories: mainValidation.correctedCalories);
    }

    // 建议 7：主菜组分份量交叉验证修正
    if (mainValidation.correctedComponents != null) {
      result =
          result.copyWith(foodComponents: mainValidation.correctedComponents);
    }

    // additionalDishes 修正
    result = _correctAdditionalDishes(result);
    return result;
  }

  /// 批次 1 + 建议 7：校验并修正 additionalDishes（calories + 组分份量，不重试）
  VisionRecognitionResult _correctAdditionalDishes(
      VisionRecognitionResult result) {
    if (result.additionalDishes.isEmpty) return result;
    final corrected = <VisionRecognitionResult>[];
    var changed = false;
    for (final dish in result.additionalDishes) {
      final v = RecognitionValidator.validate(dish);
      if (v.reasons.isNotEmpty) {
        debugPrint('[RecognitionValidator] 附加菜「${dish.dishName}」校验: ${v.reasons}');
      }
      var modified = dish;
      var dishChanged = false;
      if (v.correctedCalories != null) {
        modified = modified.copyWith(estimatedCalories: v.correctedCalories);
        dishChanged = true;
      }
      // 建议 7：组分份量交叉验证修正
      if (v.correctedComponents != null) {
        modified = modified.copyWith(foodComponents: v.correctedComponents);
        dishChanged = true;
      }
      if (dishChanged) changed = true;
      corrected.add(modified);
    }
    if (!changed) return result;
    // 重建 result 带修正后的 additionalDishes
    return VisionRecognitionResult(
      dishName: result.dishName,
      brand: result.brand,
      estimatedWeightGLow: result.estimatedWeightGLow,
      estimatedWeightGMid: result.estimatedWeightGMid,
      estimatedWeightGHigh: result.estimatedWeightGHigh,
      foodComponents: result.foodComponents,
      cookingMethod: result.cookingMethod,
      isSingleItem: result.isSingleItem,
      confidence: result.confidence,
      promptVersion: result.promptVersion,
      additionalDishes: corrected,
      quantity: result.quantity,
      unit: result.unit,
      perUnitG: result.perUnitG,
      estimatedCalories: result.estimatedCalories,
      estimatedProteinG: result.estimatedProteinG,
      estimatedFatG: result.estimatedFatG,
      estimatedCarbsG: result.estimatedCarbsG,
      weightSource: result.weightSource,
      foodCategory: result.foodCategory,
    );
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

