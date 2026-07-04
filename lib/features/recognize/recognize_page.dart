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
import '../../data/repositories/pending_recognition_repository.dart';
import '../../data/seed/food_category_defaults.dart';
import '../manual_entry/manual_entry_page.dart';
import 'calibration_page.dart';
import 'multi_dish_page.dart';
import 'providers.dart';
import 'recognize_controller.dart';

class RecognizePage extends ConsumerStatefulWidget {
  const RecognizePage({super.key});

  @override
  ConsumerState<RecognizePage> createState() => _RecognizePageState();
}

class _RecognizePageState extends ConsumerState<RecognizePage> {
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
    return Scaffold(
      appBar: AppBar(title: const Text('拍照识别')),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Sprint 2 T0：餐次选择器（M3：DropdownButton → SegmentedButton）
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: MealTypeSelector(
                    value: _mealType,
                    onChanged: (v) => setState(() => _mealType = v),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isRecognizing
                      ? null
                      : () => _pickAndRecognize(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('拍照'),
                ),
                const SizedBox(height: 12),
                // 次要入口用 OutlinedButton 与主入口"拍照"形成主次层级（MD3 视觉层级）
                OutlinedButton.icon(
                  onPressed: _isRecognizing
                      ? null
                      : () => _pickAndRecognize(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text('从相册选择'),
                ),
              ],
            ),
          ),
          // 识别中遮罩：用 cs.scrim（MD3 spec 遮罩色）替代硬编码 Colors.black54
          if (_isRecognizing)
            Container(
              color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54),
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
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MultiDishPage(
                mainDish: state.recognitionResult!,
                mainSingle: state.singleNutrition,
                mainComposite: state.compositeNutrition,
                additionalItems: state.additionalItems,
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
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CalibrationPage(
              recognitionResult: state.recognitionResult!,
              singleNutrition: state.singleNutrition,
              compositeNutrition: state.compositeNutrition,
              foodItemRepo: foodItemRepo,
              suggestedServingG: suggestedServingG,
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

                    // 获取 foodItemId：单品用查库命中，复合菜创建 ai_recognized 记录
                    // 必须有有效 food_item_id（meal_log.food_item_id 是非空 FK，
                    // Task 2 已启用 PRAGMA foreign_keys = ON，id=0 会触发外键约束违规）
                    int foodItemId;
                    if (state.singleNutrition != null) {
                      final n = state.singleNutrition!;
                      if (n.foodItemId == 0) {
                        // v1.4：单品库未命中，AI 估算兜底 → 创建 ai_recognized food_item
                        // per100g 必须基于 AI 估算的 mid 份量反算（n.calories 对应 mid 份量），
                        // 不能用 servingG（用户校准后的份量），否则密度会随用户调整反向偏差
                        final mid = result.estimatedWeightGMid;
                        final per100 = mid > 0 ? 100.0 / mid : 0.0;
                        // v1.9：包装食品 OCR 优先路径——有包装营养表数据时按包装换算，
                        // 跳过品类校准（包装数据是精确值，不需要校准）
                        // 参考 prompts.dart v1.9 规则 10 + 示例 7（珍宝珠酸条）
                        // v1.10：包装换算后宏量全 0 但 cal>0（含糖饮料 AI 漏填宏量）→ 回退品类校准
                        //   避免含糖饮料碳水显示 0（computePackageNutritionPer100g 三层兜底仍 0 时）
                        final packagePer100 = result.hasPackageNutrition
                            ? result.computePackageNutritionPer100g(
                                // v1.9：哨兵分支 n.foodItemId==0 来自 _aiFallbackNutrition，
                                // n.proteinG 等于 r.estimatedProteinG ?? 0，三元死代码简化为直传
                                estimatedProteinG: result.estimatedProteinG,
                                estimatedFatG: result.estimatedFatG,
                                estimatedCarbsG: result.estimatedCarbsG,
                              )
                            : null;
                        // v1.10：判断包装换算宏量是否全 0（含糖饮料 AI 漏填宏量特征）
                        final packageMacrosAllZero = packagePer100 != null &&
                            packagePer100.$2 == 0 &&
                            packagePer100.$3 == 0 &&
                            packagePer100.$4 == 0;
                        final (caloriesPer100g, proteinPer100g, fatPer100g, carbsPer100g) =
                            (packagePer100 != null && !packageMacrosAllZero)
                                ? packagePer100
                                : (() {
                                    // 无包装数据 / 包装换算宏量全 0 → 走 AI 估算 + 品类校准路径
                                    // P0：品类默认值校准——AI 估算的 per100g 偏离品类默认值 2 倍以上
                                    // 用默认值替代（防 AI 离谱估算，如啤酒估成 200 kcal/100g 实际 43）
                                    final rawCalPer100 = n.calories * per100;
                                    return FoodCategoryDefaults.calibrate(
                                      aiCaloriesPer100g: rawCalPer100,
                                      aiProteinPer100g: n.proteinG * per100,
                                      aiFatPer100g: n.fatG * per100,
                                      aiCarbsPer100g: n.carbsG * per100,
                                      category: result.foodCategory,
                                    );
                                  })();
                        if (!result.hasPackageNutrition) {
                          // 仅 AI 估算路径打印校准日志（包装路径是精确值无需校准）
                          final rawCalPer100 = n.calories * per100;
                          if (caloriesPer100g != rawCalPer100) {
                            debugPrint(
                                '[FoodCategoryDefaults] ${result.dishName}(${result.foodCategory}) '
                                'AI per100g=$rawCalPer100 偏离品类默认值，校准为 $caloriesPer100g');
                          }
                        } else {
                          debugPrint(
                              '[PackageOCR] ${result.dishName} 使用包装营养表换算 per100g=$caloriesPer100g '
                              '(serving=${result.packageServingG}g/${result.packageServingKj}kJ/${result.packageServingKcal}kcal)');
                        }
                        foodItemId = await foodRepo.upsertAiRecognized(
                          name: result.dishName,
                          brand: result.brand,
                          caloriesPer100g: caloriesPer100g,
                          proteinPer100g: proteinPer100g,
                          fatPer100g: fatPer100g,
                          carbsPer100g: carbsPer100g,
                          confidence: result.confidence,
                        );
                      } else {
                        foodItemId = n.foodItemId;
                      }
                    } else if (state.compositeNutrition != null) {
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
                      return;
                    }

                    await mealRepo.insertMealLog(
                      date: todayYmd(),
                      mealType:
                          state.mealType, // Sprint 2 T0：从 controller state 读餐次
                      foodItemId: foodItemId,
                      actualServingG: servingG,
                      actualCalories: calories,
                      actualProteinG: protein,
                      actualFatG: fat,
                      actualCarbsG: carbs,
                      originalImagePath: controller.current.imagePath,
                      recognitionConfidence: result.confidence,
                      componentsSnapshotJson: componentsSnapshot,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '已记录：${calories.toStringAsFixed(0)} kcal',
                          ),
                        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.errorMessage ?? '已加入离线队列')),
        );
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
    final newDishName = await _promptNewDishName(displayName);
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
      nutrition = _nutritionFromFoodItem(
        candidates.first,
        result.estimatedWeightGMid,
      );
    } else {
      // 多候选 → 列表选择
      final selected = await _showFoodSelectionDialog(candidates);
      if (selected == null || !mounted) return;
      nutrition = _nutritionFromFoodItem(selected, result.estimatedWeightGMid);
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
                await mealRepo.insertMealLog(
                  date: todayYmd(),
                  mealType: mealType,
                  foodItemId: nutrition!.foodItemId,
                  actualServingG: servingG,
                  actualCalories: calories,
                  actualProteinG: protein,
                  actualFatG: fat,
                  actualCarbsG: carbs,
                  originalImagePath: imagePath,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已记录：${calories.toStringAsFixed(0)} kcal'),
                    ),
                  );
                }
              },
        ),
      ),
    );
  }

  /// 用 FoodItem + 份量构造 NutritionResult（候选列表选中后用）
  /// 建议 1：同步 lookupSingleItem 的可食部分系数（servingG 为 AI 整重，需乘 ediblePercent）
  NutritionResult _nutritionFromFoodItem(FoodItem food, double servingG) {
    final edibleFactor = (food.ediblePercent ?? 100).clamp(1, 100) / 100;
    final effectiveG = servingG * edibleFactor;
    return NutritionResult(
      foodItemId: food.id,
      calories: food.caloriesPer100g * effectiveG / 100,
      proteinG: food.proteinPer100g * effectiveG / 100,
      fatG: food.fatPer100g * effectiveG / 100,
      carbsG: food.carbsPer100g * effectiveG / 100,
      oilG: 0,
    );
  }

  /// 食物候选列表选择对话框（多候选时让用户选）
  Future<FoodItem?> _showFoodSelectionDialog(List<FoodItem> candidates) async {
    return showDialog<FoodItem>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择匹配的食物'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (ctx, i) {
              final f = candidates[i];
              return ListTile(
                title: Text(f.name),
                subtitle: Text(
                  '${f.caloriesPer100g.toStringAsFixed(0)} kcal/100g',
                ),
                onTap: () => Navigator.pop(ctx, f),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptNewDishName(String original) async {
    final ctrl = TextEditingController(text: original);
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('修改菜名'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: '菜名'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

}

enum _NotFoundAction { cancel, retry, manual }
