import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 图片质量预检工具
///
/// 模糊检测：用拉普拉斯算子方差（Variance of Laplacian）判断图片清晰度。
/// 原理：拉普拉斯算子对边缘敏感，清晰图边缘锐利→方差大，模糊图边缘平滑→方差小。
///
/// M16.2 修复（用户反馈"相册内识别经常出错"）：
/// - 阈值 50→25：原阈值对低纹理食物（米饭/粥/汤面/蒸蛋）误判清晰图为模糊
///   经三层降采样（image_picker resize 1024 → compress quality 85 → checker copyResize 256）
///   后方差显著降低，50 过严。25 仍能拒识真模糊图（手抖/失焦），但放行低纹理食物
/// - copyResize 256→512：提高方差计算精度，减少降采样损失，让阈值判断更准
class ImageQualityChecker {
  /// 低于此方差判定为模糊
  /// M16.2：50→25（原阈值对低纹理食物误判，三层降采样后方差偏低）
  static const double _blurThreshold = 25.0;

  /// 检查图片是否模糊
  /// [bytes] 图片字节数据
  /// 返回 true 表示模糊，建议重拍
  static Future<bool> isBlurry(Uint8List bytes) async {
    try {
      // 解码（image 包同步耗时，包 isolate 调用避免卡 UI）
      final decoded = await Future(() => img.decodeImage(bytes));
      if (decoded == null) return false; // 解码失败不阻断（交后续流程处理）

      // 缩小到 512x512 加速计算（模糊检测不需要高分辨率）
      // M16.2：256→512，提高方差计算精度，减少降采样损失
      final small = img.copyResize(decoded, width: 512);

      // 转灰度
      final gray = img.grayscale(small);

      // 算拉普拉斯方差
      final variance = _laplacianVariance(gray);
      return variance < _blurThreshold;
    } catch (_) {
      // 预检失败不阻断识别流程（降级为不预检）
      return false;
    }
  }

  /// 从文件路径检查模糊
  static Future<bool> isBlurryFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return await isBlurry(bytes);
    } catch (_) {
      return false;
    }
  }

  /// 计算拉普拉斯算子方差
  /// 拉普拉斯卷积核：[[0,1,0],[1,-4,1],[0,1,0]]
  static double _laplacianVariance(img.Image gray) {
    final w = gray.width;
    final h = gray.height;
    if (w < 3 || h < 3) return 1000; // 太小不判模糊

    final laplacianValues = <double>[];
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final center = img.getLuminance(gray.getPixel(x, y));
        final up = img.getLuminance(gray.getPixel(x, y - 1));
        final down = img.getLuminance(gray.getPixel(x, y + 1));
        final left = img.getLuminance(gray.getPixel(x - 1, y));
        final right = img.getLuminance(gray.getPixel(x + 1, y));
        final lap = up + down + left + right - 4 * center;
        laplacianValues.add(lap.toDouble());
      }
    }

    if (laplacianValues.isEmpty) return 1000;

    // 算方差
    final mean = laplacianValues.reduce((a, b) => a + b) / laplacianValues.length;
    var sumSq = 0.0;
    for (final v in laplacianValues) {
      sumSq += (v - mean) * (v - mean);
    }
    return sumSq / laplacianValues.length;
  }
}
