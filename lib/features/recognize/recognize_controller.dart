import 'dart:convert';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/legacy.dart'; // Riverpod 3.x：StateNotifier 移至 legacy.dart（主入口不再导出，仅用 legacy 导入）
import 'package:image_picker/image_picker.dart';

import '../../ai/nutrition_lookup.dart';
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
  final Future<void> Function(String imagePath, String mealType, String date)?
      _onOfflineEnqueue;

  RecognizeController(
    this._primaryProvider,
    this._fallbackProvider,
    this._nutritionLookup, {
    Future<void> Function(String imagePath, String mealType, String date)?
        onOfflineEnqueue,
  })  : _onOfflineEnqueue = onOfflineEnqueue,
        super(RecognizeUiState());

  /// 当前状态（供外部一次性读取，避免直接访问 StateNotifier 的 protected state）
  RecognizeUiState get current => state;

  /// 拍照入口
  /// Sprint 2 T0：新增 mealType 参数（breakfast/lunch/dinner/snack）
  /// Sprint 2 T14：网络异常时若有 onOfflineEnqueue 则入队，否则报错
  Future<void> pickAndRecognize(ImageSource source,
      {required String mealType}) async {
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

      // 调 Vision API（主→备降级）
      state = state.copyWith(state: RecognizeState.recognizing);
      VisionRecognitionResult result;
      try {
        result = await _primaryProvider.recognize(imageBase64);
      } catch (e) {
        if (_fallbackProvider == null) rethrow;
        // 主失败，转备
        result = await _fallbackProvider.recognize(imageBase64);
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
          await _onOfflineEnqueue(xFile.path, mealType, today);
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
}

