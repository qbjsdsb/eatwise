import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/legacy.dart'; // Riverpod 3.x：StateNotifier 移至 legacy.dart（主入口不再导出，仅用 legacy 导入）
import 'package:image_picker/image_picker.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/prompts.dart';
import '../../ai/vision_provider.dart';

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

  RecognizeUiState({
    this.state = RecognizeState.idle,
    this.errorMessage,
    this.recognitionResult,
    this.singleNutrition,
    this.compositeNutrition,
    this.imagePath,
    this.mealType = 'snack',
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
    );
  }
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
  })  : _onOfflineEnqueue = onOfflineEnqueue,
        _onL3Fallback = onL3Fallback,
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

    state = state.copyWith(
        state: RecognizeState.pickingImage, mealType: mealType, clearError: true);
    XFile? xFile;
    try {
      final picker = ImagePicker();
      xFile = await picker.pickImage(source: source, maxWidth: 1024, maxHeight: 1024);
      if (xFile == null) {
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
      _lastRecognizeTime = DateTime.now(); // T23 限流：记录本次识别时间
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
          _triggerL3Fallback();
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

      // 查库回填营养素
      state = state.copyWith(
        state: RecognizeState.lookupNutrition,
        recognitionResult: result,
        imagePath: xFile.path,
      );

      if (result.isSingleItem) {
        final nutrition = await _nutritionLookup.lookupSingleItem(
          dishName: result.dishName,
          servingG: result.estimatedWeightGMid,
        );
        state = state.copyWith(state: RecognizeState.done, singleNutrition: nutrition);
      } else {
        final nutrition = await _nutritionLookup.lookupCompositeDish(
          components: result.foodComponents,
          cookingMethod: result.cookingMethod,
        );
        state = state.copyWith(state: RecognizeState.done, compositeNutrition: nutrition);
      }
    } catch (e) {
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
  void _triggerL3Fallback() {
    if (_onL3Fallback != null) {
      state = state.copyWith(
        state: RecognizeState.error,
        errorMessage: '识别失败，已转手动录入',
      );
      _onL3Fallback();
    } else {
      state = state.copyWith(
        state: RecognizeState.error,
        errorMessage: '识别失败',
      );
    }
  }
}

