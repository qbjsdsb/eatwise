import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../ai/nutrition_lookup.dart';
import '../../ai/vision_provider.dart';
import '../../core/config/app_config.dart';
import '../../core/util/date_format.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/repositories/food_item_repository.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/pending_recognition_repository.dart';
import '../manual_entry/manual_entry_page.dart';
import 'calibration_page.dart';
import 'calibrated_nutrition_calculator.dart';
import 'dish_name_editor.dart';
import 'multi_dish_page.dart';
import 'providers.dart';
import 'recognize_controller.dart';

class RecognizePage extends ConsumerStatefulWidget {
  const RecognizePage({super.key});

  @override
  ConsumerState<RecognizePage> createState() => _RecognizePageState();

  /// 校准页 onConfirm 回调核心逻辑：写 food_item + meal_log。
  ///
  /// 抽成静态方法便于单测（M16.6 Task 3）：验证 AI 兜底哨兵路径（foodItemId=0）
  /// 下 meal_log.actualCalories 与 food_item.caloriesPer100g 数据一致。
  ///
  /// M16.8 Task 4：查库命中分支（singleNutrition.foodItemId > 0）+ 传入
  /// [aiFallbackNutrition] 时，走 CalibratedNutritionCalculator 差异检测——
  /// AI 与库 per100g 偏差 > 50% 用 AI 反算 per100g 写库 + 用 AI 值记 meal_log
  /// （修复 reasoning 与记录脱节）；偏差 ≤ 50% 用库值不更新库。未传
  /// [aiFallbackNutrition] 时保持原行为（用 onConfirm 传入值，已基于 DB per100g）。
  ///
  /// 返回 actualCalories（用于 toast 显示）；返回 null 表示无营养数据未记录。
  @visibleForTesting
  static Future<double?> writeCalibratedMealLog({
    required FoodItemRepository foodRepo,
    required MealLogRepository mealRepo,
    required VisionRecognitionResult result,
    required NutritionResult? singleNutrition,
    required CompositeNutritionResult? compositeNutrition,
    required String mealType,
    required double servingG,
    required double calories,
    required double protein,
    required double fat,
    required double carbs,
    String? componentsSnapshot,
    String? imagePath,
    NutritionResult? aiFallbackNutrition,
  }) async {
    // 获取 foodItemId：单品用查库命中，复合菜创建 ai_recognized 记录
    // 必须有有效 food_item_id（meal_log.food_item_id 是非空 FK，
    // Task 2 已启用 PRAGMA foreign_keys = ON，id=0 会触发外键约束违规）
    int foodItemId;
    // M16.6：actualXxx 默认用 onConfirm 传入值（查库命中 / 复合菜路径已基于 DB per100g，无脱节）；
    // AI 兜底哨兵路径（foodItemId=0）下用 CalibratedNutritionCalculator 重算，
    // 保证 meal_log.actualCalories 与 food_item.caloriesPer100g 同源
    double actualCalories = calories;
    double actualProteinG = protein;
    double actualFatG = fat;
    double actualCarbsG = carbs;
    if (singleNutrition != null) {
      final n = singleNutrition;
      if (n.foodItemId == 0) {
        // v1.4：单品库未命中，AI 估算兜底 → 创建 ai_recognized food_item
        // M16.6 Task 3：用 CalibratedNutritionCalculator 统一计算 per100g + actualXxx，
        // 保证 meal_log.actualCalories 与 food_item.caloriesPer100g 数据一致
        // （之前 meal_log 直接用 onConfirm 传入的未校准 calories，与 food_item 脱节）
        // per100g 基于 mid 反算（硬约束 #4），actualXxx = per100g * servingG / 100
        // CalibratedNutritionCalculator 内部已处理包装 OCR 优先级 + 品类校准，
        // 与 offline_queue_controller 三路径行为一致
        final calibrated = CalibratedNutritionCalculator.compute(
          recognitionResult: result,
          aiFallback: n,
          servingG: servingG,
        );
        // 校准日志（包装路径是精确值无需校准，仅 AI 估算路径打印）
        if (!result.hasPackageNutrition) {
          final mid = result.estimatedWeightGMid;
          final rawCalPer100 = mid > 0 ? n.calories * 100.0 / mid : 0.0;
          if (calibrated.caloriesPer100g != rawCalPer100) {
            debugPrint(
                '[FoodCategoryDefaults] ${result.dishName}(${result.foodCategory}) '
                'AI per100g=$rawCalPer100 偏离品类默认值，校准为 ${calibrated.caloriesPer100g}');
          }
        } else {
          debugPrint(
              '[PackageOCR] ${result.dishName} 使用包装营养表换算 per100g=${calibrated.caloriesPer100g} '
              '(serving=${result.packageServingG}g/${result.packageServingKj}kJ/${result.packageServingKcal}kcal)');
        }
        foodItemId = await foodRepo.upsertAiRecognized(
          name: result.dishName,
          brand: result.brand,
          caloriesPer100g: calibrated.caloriesPer100g,
          proteinPer100g: calibrated.proteinPer100g,
          fatPer100g: calibrated.fatPer100g,
          carbsPer100g: calibrated.carbsPer100g,
          confidence: result.confidence,
        );
        // M16.6：actualXxx 用校准后 per100g * servingG / 100（与 food_item 同源）
        actualCalories = calibrated.actualCalories;
        actualProteinG = calibrated.actualProteinG;
        actualFatG = calibrated.actualFatG;
        actualCarbsG = calibrated.actualCarbsG;
      } else {
        foodItemId = n.foodItemId;
        // M16.8 Task 4：查库命中 + 有 AI 兜底估算 → 差异检测决定信任 AI 还是库
        // 偏差 > 50% 用 AI 反算 per100g 写库 + 用 AI 值记 meal_log
        // （修复 reasoning 显示 AI 估算但记录用库值致脱节）
        // 偏差 ≤ 50% 用库值（actualXxx 保持 onConfirm 传入值，已基于 DB per100g）
        // 未传 aiFallbackNutrition 时保持原行为（向后兼容）
        if (aiFallbackNutrition != null) {
          final calibrated = CalibratedNutritionCalculator.compute(
            recognitionResult: result,
            aiFallback: aiFallbackNutrition,
            servingG: servingG,
            lookupHitNutrition: n,
          );
          actualCalories = calibrated.actualCalories;
          actualProteinG = calibrated.actualProteinG;
          actualFatG = calibrated.actualFatG;
          actualCarbsG = calibrated.actualCarbsG;
          // 偏差大时用 AI 反算 per100g 纠正脏库
          if (calibrated.shouldUpdateFoodItem) {
            await foodRepo.updatePer100g(
              foodItemId: calibrated.foodItemId,
              caloriesPer100g: calibrated.caloriesPer100g,
              proteinPer100g: calibrated.proteinPer100g,
              fatPer100g: calibrated.fatPer100g,
              carbsPer100g: calibrated.carbsPer100g,
            );
          }
        }
      }
    } else if (compositeNutrition != null) {
      // 复合菜：存入 food_item（source=ai_recognized，components_json 存组分快照）
      // v1.9：复合菜有包装营养表数据时（预包装速冻食品等），
      // per100g 用包装换算值（替代 0），actualCalories 在 CalibrationPage 按包装换算
      final packagePer100 = result.hasPackageNutrition
          ? result.computePackageNutritionPer100g(
              estimatedProteinG: result.estimatedProteinG,
              estimatedFatG: result.estimatedFatG,
              estimatedCarbsG: result.estimatedCarbsG,
            )
          : null;
      foodItemId = await foodRepo.upsertAiRecognized(
        name: result.dishName,
        brand: result.brand,
        caloriesPer100g: packagePer100?.$1 ?? 0,
        proteinPer100g: packagePer100?.$2 ?? 0,
        fatPer100g: packagePer100?.$3 ?? 0,
        carbsPer100g: packagePer100?.$4 ?? 0,
        confidence: result.confidence,
        componentsJson: componentsSnapshot,
      );
    } else {
      // 无营养数据（查库未命中），不记录
      return null;
    }

    await mealRepo.insertMealLog(
      date: todayYmd(),
      mealType: mealType,
      foodItemId: foodItemId,
      actualServingG: servingG,
      actualCalories: actualCalories,
      actualProteinG: actualProteinG,
      actualFatG: actualFatG,
      actualCarbsG: actualCarbsG,
      originalImagePath: imagePath,
      recognitionConfidence: result.confidence,
      componentsSnapshotJson: componentsSnapshot,
    );
    return actualCalories;
  }
}

class _RecognizePageState extends ConsumerState<RecognizePage>
    with DishNameEditor<RecognizePage> {
  RecognizeController? _controller;
  String _mealType = 'snack'; // Sprint 2 T0：餐次选择，默认加餐
  bool _isRecognizing = false; // 识别中遮罩：防重复点击 + 给用户反馈
  // 最近一次选图来源（camera/gallery），用于错误态 SnackBar 的"重试"入口；
  // null 表示尚未触发过识别（不应出现错误态，重试按钮也不会显示）
  ImageSource? _lastSource;

  @override
  void dispose() {
    _controller?.dispose(); // 释放 StateNotifier
    super.dispose();
  }

  Future<RecognizeController> _ensureController() async {
    if (_controller != null) return _controller!;
    final qwen = ref.read(qwenVlProviderProvider);
    final glm = ref.read(glm4vProviderProvider);
    final lookup = await ref.read(nutritionLookupProvider.future);
    final db = await ref.read(databaseProvider.future);
    final breaker = ref.read(circuitBreakerProvider); // T37：注入断路器
    final store = ref.read(secureConfigStoreProvider); // T43：月度计数
    // Sprint 2 T14：注入离线入队回调（网络异常时入 pending_recognition 队列）
    _controller = RecognizeController(
      qwen,
      glm,
      lookup,
      onOfflineEnqueue: (imagePath, mealType, date, promptVersion) async {
        // 把图片从临时缓存目录复制到持久目录，避免系统清缓存后回补时图片丢失
        final persistentPath = await _persistImage(imagePath);
        final repo = PendingRecognitionRepository(db);
        await repo.enqueue(
          imagePath: persistentPath,
          mealType: mealType,
          date: date,
          promptVersion: promptVersion,
        );
      },
      onL3Fallback: () {
        // T36：非 retryable 错误（malformed/401/403）→ 跳手动录入页
        if (!mounted) return;
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ManualEntryPage()));
      },
      circuitBreaker: breaker, // T37：断路器（open 时不调 API 直接入队）
      secureConfigStore: store, // T43：识别成功月度计数
    );
    return _controller!;
  }

  /// 把图片从临时缓存目录复制到 app 私有持久目录
  /// （image_picker 相机照片存在 getTemporaryDirectory，系统可能清理）
  /// 返回持久路径；若源文件不存在或复制失败，回退返回原路径（避免阻塞入队）
  Future<String> _persistImage(String tempPath) async {
    try {
      final src = File(tempPath);
      if (!await src.exists()) return tempPath;
      final dir = await getApplicationDocumentsDirectory();
      final persistDir = Directory('${dir.path}/pending_images');
      if (!await persistDir.exists()) {
        await persistDir.create(recursive: true);
      }
      final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final destPath = '${persistDir.path}/$fileName';
      await src.copy(destPath);
      return destPath;
    } catch (e) {
      // 复制失败回退原路径（回补时若文件不存在会 markFailed，至少入队不阻塞）
      return tempPath;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('拍照识别')),
      body: Stack(
        children: [
          // 整体布局：上半 hero 引导区（图标+标题+副标题）+ 下半操作区（餐次+两个大按钮）
          // 解决原 Column 在屏幕中央导致上下大面空白的问题
          SafeArea(
            child: Column(
              children: [
                // Hero 引导区：撑满上半空间，居中大图标 + 引导文案
                Expanded(
                  flex: 5,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: ExcludeSemantics(
                            child: Icon(
                              Icons.restaurant_menu_rounded,
                              size: 48,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text('拍照识别食物', style: tt.headlineSmall),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'AI 自动识别菜品 + 估算营养，也可选相册图片',
                            textAlign: TextAlign.center,
                            style: tt.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 操作区：餐次选择 + 拍照按钮 + 相册按钮
                Flexible(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MealTypeSelector(
                          value: _mealType,
                          onChanged: (v) => setState(() => _mealType = v),
                        ),
                        const SizedBox(height: 20),
                        // 主入口：拍照（大按钮，full width，强视觉权重）
                        FilledButton.icon(
                          onPressed: _isRecognizing
                              ? null
                              : () => _pickAndRecognize(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_rounded),
                          label: const Text('拍照识别'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 次入口：相册（OutlinedButton 与主入口形成主次层级）
                        OutlinedButton.icon(
                          onPressed: _isRecognizing
                              ? null
                              : () => _pickAndRecognize(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_rounded),
                          label: const Text('从相册选择'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 识别中遮罩：用 cs.scrim（MD3 spec 遮罩色）替代硬编码 Colors.black54
          if (_isRecognizing)
            Container(
              color: cs.scrim.withValues(alpha: 0.54),
              child: Center(
                child: Card(
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('识别中…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAndRecognize(ImageSource source) async {
    if (_isRecognizing) return; // 防重入
    _lastSource = source; // 记录来源供错误态重试
    setState(() => _isRecognizing = true);
    try {
      final controller = await _ensureController();
      await controller.pickAndRecognize(source, mealType: _mealType);

      // 监听状态变化跳转校准页
      final state = controller.current;
      if (state.state == RecognizeState.done &&
          state.recognitionResult != null) {
        if (!mounted) return;
        // 持久化原图：image_picker 临时缓存会被系统清理，复制到 app 私有目录避免 broken image
        // （与离线入队 _persistImage 一致，回写 state.imagePath 让后续 meal_log 引用持久路径）
        if (state.imagePath != null) {
          final persistent = await _persistImage(state.imagePath!);
          controller.updateImagePath(persistent);
        }
        // v1.2 一桌多菜：additionalItems 非空 → 跳多菜列表页（每菜可校准+合并记录）
        if (state.additionalItems.isNotEmpty) {
          if (!mounted) return;
          // M16.8：为主菜 + 每个附加菜计算 AI 兜底估算，传给 MultiDishPage
          // 查库命中时用于差异检测（偏差 > 50% 用 AI 反算 per100g 写库 + 用 AI 值记 meal_log）
          final mainAiFallback =
              controller.aiFallbackNutrition(state.recognitionResult!);
          final additionalItemsWithFallback = state.additionalItems
              .map((item) => MultiDishItem(
                    dish: item.dish,
                    singleNutrition: item.singleNutrition,
                    compositeNutrition: item.compositeNutrition,
                    aiFallback: controller.aiFallbackNutrition(item.dish),
                  ))
              .toList();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MultiDishPage(
                mainDish: state.recognitionResult!,
                mainSingle: state.singleNutrition,
                mainComposite: state.compositeNutrition,
                mainAiFallback: mainAiFallback,
                additionalItems: additionalItemsWithFallback,
                mealType: state.mealType,
                imagePath: controller.current.imagePath,
              ),
            ),
          );
          return;
        }
        // Sprint 4 T29：单品 + 复合菜均未命中 → 弹窗（改菜名重试 / 转手动录入）
        // v1.4：复合菜组分全 miss 且 AI 兜底返回 null（旧 prompt）时 componentHits 为空，也算未命中
        if (state.singleNutrition == null &&
            (state.compositeNutrition == null ||
                state.compositeNutrition!.componentHits.isEmpty)) {
          await _showNotFoundDialog(
            state.recognitionResult!,
            mealType: state.mealType,
            imagePath: controller.current.imagePath,
            // M16.8：传 AI 兜底估算，改菜名重试命中后走差异检测（与主路径一致）
            aiFallbackNutrition:
                controller.aiFallbackNutrition(state.recognitionResult!),
          );
          return;
        }
        final foodItemRepo = await ref.read(foodItemRepoProvider.future);
        if (!mounted) return;
        // 智能份量校准：单品路径查历史中位数作滑块初值（B 功能）
        // v1.3：多份场景跳过（CalibrationPage 会用 AI mid，查了也浪费 DB 调用）
        // v1.4：AI 兜底（foodItemId=0 哨兵）跳过，库里还没有这条食物
        double? suggestedServingG;
        if (state.singleNutrition != null &&
            state.singleNutrition!.foodItemId > 0 &&
            !state.recognitionResult!.isMultiQuantity) {
          final mealRepo = await ref.read(mealLogRepoProvider.future);
          suggestedServingG = await mealRepo.getMedianServing(
            state.singleNutrition!.foodItemId,
          );
        }
        if (!mounted) return;
        // 改菜名支持：注入 NutritionLookup 供 calibration_page 调用（5 级模糊兜底 + OFF 云查）
        final nutritionLookup = await ref.read(nutritionLookupProvider.future);
        if (!mounted) return;
        // M16.8：计算 AI 兜底估算，传给 CalibrationPage 让查库命中分支预览走差异检测
        final mainAiFallback =
            controller.aiFallbackNutrition(state.recognitionResult!);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CalibrationPage(
              recognitionResult: state.recognitionResult!,
              singleNutrition: state.singleNutrition,
              compositeNutrition: state.compositeNutrition,
              foodItemRepo: foodItemRepo,
              suggestedServingG: suggestedServingG,
              nutritionLookup: nutritionLookup,
              aiFallbackNutrition: mainAiFallback,
              onConfirm:
                  (
                    servingG,
                    calories,
                    protein,
                    fat,
                    carbs, {
                    componentsSnapshot,
                  }) async {
                    final mealRepo = await ref.read(mealLogRepoProvider.future);
                    final foodRepo = await ref.read(
                      foodItemRepoProvider.future,
                    );
                    final result = state.recognitionResult!;
                    final actualCalories = await RecognizePage.writeCalibratedMealLog(
                      foodRepo: foodRepo,
                      mealRepo: mealRepo,
                      result: result,
                      singleNutrition: state.singleNutrition,
                      aiFallbackNutrition: mainAiFallback,
                      compositeNutrition: state.compositeNutrition,
                      mealType:
                          state.mealType, // Sprint 2 T0：从 controller state 读餐次
                      servingG: servingG,
                      calories: calories,
                      protein: protein,
                      fat: fat,
                      carbs: carbs,
                      componentsSnapshot: componentsSnapshot,
                      imagePath: controller.current.imagePath,
                    );
                    if (mounted && actualCalories != null) {
                      showAppToast(
                        context,
                        '已记录：${actualCalories.toStringAsFixed(0)} kcal',
                      );
                    }
                  },
            ),
          ),
        );
      } else if (state.state == RecognizeState.error) {
        if (!mounted) return;
        final msg = state.errorMessage ?? '未知错误';
        // 判断是否可重试：
        // - 操作太快（限流 30s，立即重试只会再触发限流，需用户等待）
        // - 已转手动录入（L3 已导航到 ManualEntryPage，重试无意义）
        // - 安全过滤（内容被 AI 拒识，重试同图结果不变）
        // 上述三类不显示重试按钮；其余错误（压缩失败/模糊图/API 异常/入队失败等）可重试
        final source = _lastSource;
        final canRetry = source != null &&
            !msg.contains('操作太快') &&
            !msg.contains('已转手动录入') &&
            !msg.contains('安全过滤');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('识别失败：$msg'),
            duration: const Duration(seconds: 6),
            action: canRetry
                ? SnackBarAction(
                    label: '重试',
                    onPressed: () {
                      if (!mounted) return;
                      _pickAndRecognize(source);
                    },
                  )
                : null,
          ),
        );
      } else if (state.state == RecognizeState.queued) {
        // Sprint 2 T14：离线已入队提示
        if (!mounted) return;
        showAppToast(context, state.errorMessage ?? '已加入离线队列');
      }
    } finally {
      if (mounted) setState(() => _isRecognizing = false);
    }
  }

  Future<void> _showNotFoundDialog(
    VisionRecognitionResult result, {
    required String mealType,
    String? imagePath,
    String? currentName,
    NutritionResult? aiFallbackNutrition,
  }) async {
    if (!mounted) return;
    // currentName：用户改菜名重试后透传，让弹窗显示用户最新输入而非原始识别名
    final displayName = currentName ?? result.dishName;
    final action = await showDialog<_NotFoundAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未找到营养数据'),
        content: Text(
          '识别菜名「$displayName」在食物库中未命中。'
          '可修改菜名重试，或转手动录入。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _NotFoundAction.cancel),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _NotFoundAction.manual),
            child: const Text('转手动录入'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _NotFoundAction.retry),
            child: const Text('改菜名重试'),
          ),
        ],
      ),
    );
    if (action == null || action == _NotFoundAction.cancel) return;
    if (!mounted) return;

    if (action == _NotFoundAction.manual) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ManualEntryPage(
            initialName: displayName,
            modelDishName: result.dishName, // 自动学习：原始识别名存为 alias，下次同名自动命中
          ),
        ),
      );
      return;
    }

    // 改菜名重试：模糊搜库 + 候选列表选择 + 5 级模糊兜底
    final newDishName = await promptNewDishName(displayName);
    if (newDishName == null || newDishName.isEmpty || !mounted) return;

    final foodRepo = await ref.read(foodItemRepoProvider.future);
    if (!mounted) return;
    final candidates = await foodRepo.searchByName(newDishName, limit: 30);
    if (!mounted) return;

    NutritionResult? nutrition;
    if (candidates.isEmpty) {
      // searchByName 无结果 → 5 级模糊匹配兜底
      final lookup = await ref.read(nutritionLookupProvider.future);
      nutrition = await lookup.lookupSingleItem(
        dishName: newDishName,
        servingG: result.estimatedWeightGMid,
      );
    } else if (candidates.length == 1) {
      // 唯一候选 → 直接用
      nutrition = nutritionFromFoodItem(
        candidates.first,
        result.estimatedWeightGMid,
      );
    } else {
      // 多候选 → 列表选择
      final selected = await showFoodSelectionDialog(candidates);
      if (selected == null || !mounted) return;
      nutrition = nutritionFromFoodItem(selected, result.estimatedWeightGMid);
    }

    if (nutrition == null) {
      // 仍未命中 → 递归再弹窗，透传用户最新输入的菜名（currentName）
      // 不再先弹 SnackBar（会被紧随的 Dialog 遮挡，用户看不到）
      if (!mounted) return;
      await _showNotFoundDialog(
        result,
        mealType: mealType,
        imagePath: imagePath,
        currentName: newDishName,
        aiFallbackNutrition: aiFallbackNutrition,
      );
      return;
    }
    // 命中 → 跳校准页（用新菜名的查库结果）
    if (!mounted) return;
    final foodItemRepo = await ref.read(foodItemRepoProvider.future);
    if (!mounted) return;
    // 智能份量校准：查历史中位数作滑块初值（B 功能）
    // v1.3：多份场景跳过（CalibrationPage 会用 AI mid）
    final mealRepoForSuggest = await ref.read(mealLogRepoProvider.future);
    final suggestedServingG = result.isMultiQuantity
        ? null
        : await mealRepoForSuggest.getMedianServing(nutrition.foodItemId);
    if (!mounted) return;
    // 若用户改了菜名，用新菜名构造 result（校准页标题显示用户输入的菜名，非原始识别名）
    final resultForCalibration = newDishName != result.dishName
        ? result.copyWith(dishName: newDishName)
        : result;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalibrationPage(
          recognitionResult: resultForCalibration,
          singleNutrition: nutrition,
          foodItemRepo: foodItemRepo,
          suggestedServingG: suggestedServingG,
          // M16.8：传 AI 兜底估算，让查库命中分支预览走差异检测（与记录同源）
          aiFallbackNutrition: aiFallbackNutrition,
          onConfirm:
              (
                servingG,
                calories,
                protein,
                fat,
                carbs, {
                componentsSnapshot,
              }) async {
                final mealRepo = await ref.read(mealLogRepoProvider.future);
                final foodRepo = await ref.read(
                  foodItemRepoProvider.future,
                );
                // M16.8：改调 writeCalibratedMealLog 统一写库路径，
                // 补齐 recognitionConfidence + componentsSnapshotJson 字段
                // （原直接调 insertMealLog 缺这两字段，致 meal_log 记录不完整）
                final actualCalories = await RecognizePage.writeCalibratedMealLog(
                  foodRepo: foodRepo,
                  mealRepo: mealRepo,
                  result: resultForCalibration,
                  singleNutrition: nutrition,
                  aiFallbackNutrition: aiFallbackNutrition,
                  compositeNutrition: null,
                  mealType: mealType,
                  servingG: servingG,
                  calories: calories,
                  protein: protein,
                  fat: fat,
                  carbs: carbs,
                  componentsSnapshot: componentsSnapshot,
                  imagePath: imagePath,
                );
                if (mounted && actualCalories != null) {
                  showAppToast(
                    context,
                    '已记录：${actualCalories.toStringAsFixed(0)} kcal',
                  );
                }
              },
        ),
      ),
    );
  }

}

enum _NotFoundAction { cancel, retry, manual }
