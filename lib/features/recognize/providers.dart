import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/glm_4v_provider.dart';
import '../../ai/nutrition_lookup.dart';
import '../../ai/qwen_vl_provider.dart';
import '../../core/config/app_config.dart';
import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
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
  return QwenVlProvider(
    apiKey: ref.watch(qwenApiKeyProvider),
    baseUrl: ref.watch(qwenBaseUrlProvider),
  );
});

final glm4vProviderProvider = Provider<Glm4vProvider?>((ref) {
  final key = ref.watch(glmApiKeyProvider);
  final url = ref.watch(glmBaseUrlProvider);
  if (key.isEmpty || url.isEmpty) return null;
  return Glm4vProvider(apiKey: key, baseUrl: url);
});

final foodItemRepoProvider = FutureProvider<FoodItemRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return FoodItemRepository(db);
});

final mealLogRepoProvider = FutureProvider<MealLogRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return MealLogRepository(db);
});

final nutritionLookupProvider = FutureProvider<NutritionLookup>((ref) async {
  final repo = await ref.watch(foodItemRepoProvider.future);
  return NutritionLookup(repo);
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
/// 生产：调 connectivity_plus 检查网络
/// 测试：overrideWith 返回 false 模拟离线
final networkAvailableProvider = FutureProvider<bool>((ref) async {
  final results = await Connectivity().checkConnectivity();
  return results.any((r) => r != ConnectivityResult.none);
});
