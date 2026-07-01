import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/glm_4v_provider.dart';
import '../../ai/nutrition_lookup.dart';
import '../../ai/qwen_vl_provider.dart';
import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/meal_log_repository.dart';

// export database.dart：让用 `import 'providers.dart' as recognize;` 的页面
// 能访问 recognize.databaseProvider（databaseProvider 在 database.dart 中定义）
// 不加此 export，T8-T14 各页面用 `recognize.databaseProvider` 会编译失败
// （Dart 的 import as 不会传递被 import 文件的 import 符号）
export '../../data/database/database.dart';

/// API key（Sprint 3 改从 secure_storage 读，Sprint 1 用 --dart-define 注入）
final qwenApiKeyProvider = Provider<String>(
  (ref) => const String.fromEnvironment('QWEN_API_KEY', defaultValue: ''),
);
final qwenBaseUrlProvider = Provider<String>(
  (ref) => const String.fromEnvironment('QWEN_BASE_URL', defaultValue: ''),
);
final glmApiKeyProvider = Provider<String>(
  (ref) => const String.fromEnvironment('GLM_API_KEY', defaultValue: ''),
);
final glmBaseUrlProvider = Provider<String>(
  (ref) => const String.fromEnvironment('GLM_BASE_URL', defaultValue: ''),
);

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

// RecognizeController 不用 Provider 管理（依赖 FutureProvider 异步初始化，
// 与 StateNotifierProvider 同步初始化存在时序冲突）
// 在 RecognizePage 中用 ref.read 按需创建实例，见 recognize_page.dart
