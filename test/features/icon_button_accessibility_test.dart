// test/features/icon_button_accessibility_test.dart
// 可访问性测试：IconButton 缺 tooltip + 触控目标 <48dp（Web Interface Guidelines P1）
//
// 覆盖：
// 1. multi_dish_page 步进器 ± 按钮有 tooltip（aria-label 等价物）
// 2. calibration_page 步进器 ± 按钮有 tooltip
// 3. multi_dish_page 改菜名 IconButton 触控目标 ≥48dp（Material 3 标准）
// 4. settings 主题色块触控目标 ≥48dp
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/core/config/app_config.dart';
import 'package:eatwise/core/config/secure_config_store.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:eatwise/features/recognize/calibration_page.dart';
import 'package:eatwise/features/recognize/multi_dish_page.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:eatwise/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// path_provider 内存 mock（SettingsPage._loadSettings 调 AutoBackup.lastBackupTime
// 需要 getApplicationDocumentsDirectory，沙箱无平台通道会挂起）
class _MemoryPathProvider extends PathProviderPlatform {
  final String basePath;
  _MemoryPathProvider(this.basePath);
  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

void main() {
  // ===== multi_dish_page 测试 =====
  group('multi_dish_page 可访问性', () {
    late EatWiseDatabase db;

    setUp(() async {
      db = EatWiseDatabase(NativeDatabase.memory());
      // 预置库数据：番茄（主菜查库命中，perUnitG > 0 显示步进器）
      await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
            name: '番茄',
            defaultServingG: 100,
            caloriesPer100g: 18,
            proteinPer100g: 0.9,
            fatPer100g: 0.2,
            carbsPer100g: 3.9,
            source: 'china_fct',
            sourceVersion: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
    });

    tearDown(() async => db.close());

    // 主菜 VisionRecognitionResult（番茄，单品，perUnitG=100 > 0 显示步进器）
    const mainDish = VisionRecognitionResult(
      dishName: '番茄',
      estimatedWeightGLow: 80,
      estimatedWeightGMid: 100,
      estimatedWeightGHigh: 120,
      foodComponents: [],
      cookingMethod: 'raw',
      isSingleItem: true,
      confidence: 0.95,
      promptVersion: 'v1.0',
      perUnitG: 100, // > 0 才显示数量步进器
      unit: '个',
    );

    // 主菜查库命中的营养结果（番茄 100g）
    final mainSingle = NutritionResult(
      foodItemId: 1, // 番茄 id（setUp 第一条 insert）
      calories: 18, // 18 * 100/100
      proteinG: 0.9,
      fatG: 0.2,
      carbsG: 3.9,
      oilG: 0,
    );

    testWidgets('步进器 ± 按钮有 tooltip（减少数量/增加数量）', (tester) async {
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: MultiDishPage(
          mainDish: mainDish,
          mainSingle: mainSingle,
          additionalItems: [],
          mealType: 'lunch',
        )),
      ));
      await tester.pumpAndSettle();

      expect(find.byTooltip('减少数量'), findsOneWidget,
          reason: '步进器减号 IconButton 应有 tooltip');
      expect(find.byTooltip('增加数量'), findsOneWidget,
          reason: '步进器加号 IconButton 应有 tooltip');
    });

    testWidgets('改菜名 IconButton 触控目标 ≥48dp（Material 3 标准）',
        (tester) async {
      final container = ProviderContainer(overrides: [
        recognize.databaseProvider.overrideWith((ref) async => db),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: MultiDishPage(
          mainDish: mainDish,
          mainSingle: mainSingle,
          additionalItems: [],
          mealType: 'lunch',
        )),
      ));
      await tester.pumpAndSettle();

      // 改菜名按钮已有 tooltip（'改菜名'），用它定位
      final renameBtn = find.byTooltip('改菜名');
      expect(renameBtn, findsOneWidget, reason: '改菜名按钮应已存在 tooltip');
      // 测量实际渲染尺寸（触控目标 = 渲染尺寸）
      final size = tester.getSize(renameBtn);
      expect(size.width, greaterThanOrEqualTo(48.0),
          reason: '触控目标宽度应 ≥48dp (Material 3 标准)');
      expect(size.height, greaterThanOrEqualTo(48.0),
          reason: '触控目标高度应 ≥48dp (Material 3 标准)');
    });
  });

  // ===== calibration_page 测试 =====
  group('calibration_page 可访问性', () {
    late EatWiseDatabase db;
    late FoodItemRepository foodRepo;

    setUp(() async {
      db = EatWiseDatabase(NativeDatabase.memory());
      foodRepo = FoodItemRepository(db);
    });

    tearDown(() async => db.close());

    testWidgets('步进器 ± 按钮有 tooltip（减少数量/增加数量）', (tester) async {
      // perUnitG > 0 才显示步进器
      final recognition = VisionRecognitionResult(
        dishName: '可乐',
        estimatedWeightGLow: 250,
        estimatedWeightGMid: 300,
        estimatedWeightGHigh: 350,
        foodComponents: const [],
        cookingMethod: '',
        isSingleItem: true,
        confidence: 0.9,
        promptVersion: 'v1.10',
        perUnitG: 330, // 一罐 330g
        unit: '罐',
      );
      final single = NutritionResult(
        foodItemId: 1,
        calories: 129,
        proteinG: 0,
        fatG: 0,
        carbsG: 31.5,
        oilG: 0,
      );

      await tester.pumpWidget(MaterialApp(
        home: CalibrationPage(
          recognitionResult: recognition,
          singleNutrition: single,
          foodItemRepo: foodRepo,
          suggestedServingG: 330,
          onConfirm: (_, __, ___, ____, _____, {componentsSnapshot}) async {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byTooltip('减少数量'), findsOneWidget,
          reason: '步进器减号 IconButton 应有 tooltip');
      expect(find.byTooltip('增加数量'), findsOneWidget,
          reason: '步进器加号 IconButton 应有 tooltip');
    });
  });

  // ===== settings_page 测试 =====
  group('settings_page 可访问性', () {
    late SecureConfigStore store;

    setUp(() {
      // 沙箱无平台通道，注入内存 mock 平台实现
      FlutterSecureStorage.setMockInitialValues({});
      store = SecureConfigStore();
    });

    testWidgets('主题色块触控目标 ≥48dp（Material 3 标准）', (tester) async {
      PathProviderPlatform.instance =
          _MemoryPathProvider('/tmp/icon_button_a11y_test');
      // 放大视口：SettingsPage 的 ListView 懒加载，主题色板位于列表后段，
      // 默认 800×600 视口无法完整显示，需加高视口让所有子项被 build。
      await tester.binding.setSurfaceSize(const Size(800, 2400));

      final container = ProviderContainer(overrides: [
        secureConfigStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      // runAsync 让 _loadSettings 中的真实异步（secure_storage 读、目录检查）
      // 在真实事件循环中完成；pumpAndSettle 会等所有 frame 稳定。
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 找到第一个主题色块（睡莲青绿），其 Tooltip message = 主题名
      final colorDot = find.byTooltip('睡莲青绿');
      expect(colorDot, findsOneWidget, reason: '主题色块应已存在 tooltip');
      // 测量实际渲染尺寸（触控目标 = 渲染尺寸）
      final size = tester.getSize(colorDot);
      expect(size.width, greaterThanOrEqualTo(48.0),
          reason: '主题色块触控目标宽度应 ≥48dp (Material 3 标准)');
      expect(size.height, greaterThanOrEqualTo(48.0),
          reason: '主题色块触控目标高度应 ≥48dp (Material 3 标准)');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
