import 'dart:convert';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/legacy.dart'; // Riverpod 3.x：StateNotifier 移至 legacy.dart（主入口不再导出，仅用 legacy 导入）
import 'package:image_picker/image_picker.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/vision_provider.dart';

/// 拍照识别状态
enum RecognizeState { idle, pickingImage, preprocessing, recognizing, lookupNutrition, done, error }

class RecognizeUiState {
  final RecognizeState state;
  final String? errorMessage;
  final VisionRecognitionResult? recognitionResult;
  final NutritionResult? singleNutrition;
  final CompositeNutritionResult? compositeNutrition;
  final String? imagePath;

  RecognizeUiState({
    this.state = RecognizeState.idle,
    this.errorMessage,
    this.recognitionResult,
    this.singleNutrition,
    this.compositeNutrition,
    this.imagePath,
  });

  RecognizeUiState copyWith({
    RecognizeState? state,
    String? errorMessage,
    VisionRecognitionResult? recognitionResult,
    NutritionResult? singleNutrition,
    CompositeNutritionResult? compositeNutrition,
    String? imagePath,
  }) {
    return RecognizeUiState(
      state: state ?? this.state,
      errorMessage: errorMessage,
      recognitionResult: recognitionResult ?? this.recognitionResult,
      singleNutrition: singleNutrition ?? this.singleNutrition,
      compositeNutrition: compositeNutrition ?? this.compositeNutrition,
      imagePath: imagePath ?? this.imagePath,
    );
  }
}

class RecognizeController extends StateNotifier<RecognizeUiState> {
  final VisionProvider _primaryProvider;
  final VisionProvider? _fallbackProvider;
  final NutritionLookup _nutritionLookup;

  RecognizeController(
    this._primaryProvider,
    this._fallbackProvider,
    this._nutritionLookup,
  ) : super(RecognizeUiState());

  /// 当前状态（供外部一次性读取，避免直接访问 StateNotifier 的 protected state）
  RecognizeUiState get current => state;

  /// 拍照入口
  Future<void> pickAndRecognize(ImageSource source) async {
    state = state.copyWith(state: RecognizeState.pickingImage);
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(source: source, maxWidth: 1024, maxHeight: 1024);
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
      state = state.copyWith(state: RecognizeState.error, errorMessage: e.toString());
    }
  }
}
