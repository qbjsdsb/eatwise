import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/glm_4v_provider.dart';
import '../../ai/nutrition_lookup.dart';
import '../../ai/off_provider.dart';
import '../../ai/qwen_vl_provider.dart';
import '../../core/config/app_config.dart';
import '../../core/config/app_version_provider.dart';
import '../../core/update/apk_downloader.dart';
import '../../core/update/github_release_client.dart';
import '../../core/update/update_service.dart';
import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/insight_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/pending_recognition_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/recommendation_feedback_repository.dart';
import '../../data/repositories/recognition_feedback_repository.dart';
import '../../data/repositories/weight_log_repository.dart';
import 'circuit_breaker.dart';

// export database.dart：让用 `import 'providers.dart' as recognize;` 的页面
// 能访问 recognize.databaseProvider（databaseProvider 在 database.dart 中定义）
// 不加此 export，T8-T14 各页面用 `recognize.databaseProvider` 会编译失败
// （Dart 的 import as 不会传递被 import 文件的 import 符号）
export '../../data/database/database.dart';

/// API key（Sprint 3 改从 secure_storage 读，Sprint 1 用 --dart-define 注入）
final qwenApiKeyProvider = Provider<String>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.maybeWhen(data: (c) => c.qwenApiKey, orElse: () => '');
});
final qwenBaseUrlProvider = Provider<String>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.maybeWhen(data: (c) => c.qwenBaseUrl, orElse: () => '');
});
final glmApiKeyProvider = Provider<String>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.maybeWhen(data: (c) => c.glmApiKey, orElse: () => '');
});
final glmBaseUrlProvider = Provider<String>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.maybeWhen(data: (c) => c.glmBaseUrl, orElse: () => '');
});

final qwenVlProviderProvider = Provider<QwenVlProvider>((ref) {
  final url = ref.watch(qwenBaseUrlProvider);
  return QwenVlProvider(
    apiKey: ref.watch(qwenApiKeyProvider),
    // 留空用默认（与后台 background_dispatcher.dart 一致，兑现设置页 hintText 承诺）
    baseUrl: url.isEmpty
        ? 'https://dashscope.aliyuncs.com/compatible-mode/v1'
        : url,
  );
});

final glm4vProviderProvider = Provider<Glm4vProvider?>((ref) {
  final key = ref.watch(glmApiKeyProvider);
  final url = ref.watch(glmBaseUrlProvider);
  if (key.isEmpty) return null;
  // 留空用默认（与后台一致，避免 url 空导致无备援）
  final baseUrl = url.isEmpty
      ? 'https://open.bigmodel.cn/api/paas/v4'
      : url;
  return Glm4vProvider(apiKey: key, baseUrl: baseUrl);
});

final foodItemRepoProvider = FutureProvider<FoodItemRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return FoodItemRepository(db);
});

final mealLogRepoProvider = FutureProvider<MealLogRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return MealLogRepository(db);
});

// M24 Task B1：补齐缺失的 Repository Provider，feature 层不再直接 new Repo(db)
// 模式与 foodItemRepoProvider / mealLogRepoProvider 一致：FutureProvider 包裹，
// feature 层用 `ref.read(recognize.xxxRepoProvider.future)` 拿实例
final profileRepoProvider = FutureProvider<ProfileRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return ProfileRepository(db);
});

final weightLogRepoProvider = FutureProvider<WeightLogRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return WeightLogRepository(db);
});

final pendingRecognitionRepoProvider =
    FutureProvider<PendingRecognitionRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return PendingRecognitionRepository(db);
});

final recommendationFeedbackRepoProvider =
    FutureProvider<RecommendationFeedbackRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return RecommendationFeedbackRepository(db);
});

final recognitionFeedbackRepoProvider =
    FutureProvider<RecognitionFeedbackRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return RecognitionFeedbackRepository(db);
});

// M24 Task B1：InsightRepository Provider（insight_page AI 周报页用）
final insightRepoProvider = FutureProvider<InsightRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return InsightRepository(db);
});

final nutritionLookupProvider = FutureProvider<NutritionLookup>((ref) async {
  final repo = await ref.watch(foodItemRepoProvider.future);
  // OFF 云查兜底：闭包实时读 networkAvailableProvider（离线时跳过，省电省流量）
  // 测试可用 override networkAvailableProvider 返回 false 模拟离线
  Future<bool> isOnline() async =>
      await ref.read(networkAvailableProvider.future);
  return NutritionLookup(repo, offProvider: OffProvider(isOnline: isOnline));
});

// T37 断路器 Provider（用 SecureConfigStore 作存储后端，跨 session + 后台回补感知）
final circuitBreakerProvider = Provider<CircuitBreaker>((ref) {
  final store = ref.read(secureConfigStoreProvider);
  return CircuitBreaker(
    write: (k, v) => store.writeRaw(k, v),
    read: (k) => store.readRaw(k),
    delete: (k) => store.deleteRaw(k),
  );
});

// RecognizeController 不用 Provider 管理（依赖 FutureProvider 异步初始化，
// 与 StateNotifierProvider 同步初始化存在时序冲突）
// 在 RecognizePage 中用 ref.read 按需创建实例，见 recognize_page.dart

/// 网络可用性 Provider（AI 汇总离线守卫用，Sprint 7 T54）
///
/// 生产：调 connectivity_plus 检查网络
/// 测试：overrideWith 返回 false 模拟离线
///
/// autoDispose（Bug 2 修复）：避免冷启动误报 false 永久缓存。
/// connectivity_plus 6.x 在 Android 冷启动时 ConnectivityManager 的
/// NetworkCallback 尚未首次回调，checkConnectivity() 误报 [none] 即使设备有网。
/// 非 autoDispose 的 FutureProvider 首次结果会永久缓存，导致 dashboard AI 推荐
/// "刚打开软件就加载失败"，且重试按钮也无效（ref.read 不刷新）。
/// autoDispose 保证页面重建/重新进入时重新查询。
///
/// 冷启动校正：首次返回 [none] 时 delay 500ms 重查一次，
/// 避免 NetworkCallback 未首次回调的窗口期误报。
final networkAvailableProvider = FutureProvider.autoDispose<bool>((ref) async {
  final connectivity = Connectivity();
  var results = await connectivity.checkConnectivity();
  // 冷启动校正：connectivity_plus 6.x Android 冷启动 NetworkCallback
  // 尚未首次回调时 checkConnectivity() 误报 [none]，delay 500ms 重查
  if (results.every((r) => r == ConnectivityResult.none)) {
    await Future.delayed(const Duration(milliseconds: 500));
    results = await connectivity.checkConnectivity();
  }
  return results.any((r) => r != ConnectivityResult.none);
});

// === M16 应用内更新 providers ===

/// GitHubReleaseClient 单例（http.Client 内部复用连接池）
final gitHubReleaseClientProvider = Provider<GitHubReleaseClient>((ref) {
  return GitHubReleaseClient();
});

/// ApkDownloader 单例
final apkDownloaderProvider = Provider<ApkDownloader>((ref) {
  return ApkDownloader();
});

/// UpdateService 实例（异步：需先读 appVersionShortProvider 拿当前版本号）
/// UI 用 `ref.read(updateServiceProvider.future)` 拿实例后调 checkForUpdate / downloadApk
final updateServiceProvider = FutureProvider<UpdateService>((ref) async {
  final version = await ref.read(appVersionShortProvider.future);
  final releaseClient = ref.read(gitHubReleaseClientProvider);
  final downloader = ref.read(apkDownloaderProvider);
  return UpdateService(
    releaseClient: releaseClient,
    downloader: downloader,
    currentVersion: version,
  );
});
