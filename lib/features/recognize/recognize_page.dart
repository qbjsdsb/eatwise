import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai/vision_provider.dart';
import '../../data/repositories/pending_recognition_repository.dart';
import '../manual_entry/manual_entry_page.dart';
import 'calibration_page.dart';
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
    // Sprint 2 T14：注入离线入队回调（网络异常时入 pending_recognition 队列）
    _controller = RecognizeController(
      qwen,
      glm,
      lookup,
      onOfflineEnqueue: (imagePath, mealType, date, promptVersion) async {
        final repo = PendingRecognitionRepository(db);
        await repo.enqueue(
          imagePath: imagePath,
          mealType: mealType,
          date: date,
          promptVersion: promptVersion,
        );
      },
      onL3Fallback: () {
        // T36：非 retryable 错误（malformed/401/403）→ 跳手动录入页
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const ManualEntryPage(),
        ));
      },
    );
    return _controller!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('拍照识别')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Sprint 2 T0：餐次选择器
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: DropdownButton<String>(
                value: _mealType,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'breakfast', child: Text('早餐')),
                  DropdownMenuItem(value: 'lunch', child: Text('午餐')),
                  DropdownMenuItem(value: 'dinner', child: Text('晚餐')),
                  DropdownMenuItem(value: 'snack', child: Text('加餐')),
                ],
                onChanged: (v) => setState(() => _mealType = v ?? _mealType),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _pickAndRecognize(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('拍照'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _pickAndRecognize(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('从相册选择'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndRecognize(ImageSource source) async {
    final controller = await _ensureController();
    await controller.pickAndRecognize(source, mealType: _mealType);

    // 监听状态变化跳转校准页
    final state = controller.current;
    if (state.state == RecognizeState.done && state.recognitionResult != null) {
      if (!mounted) return;
      // Sprint 4 T29：单品 + 复合菜均未命中 → 弹窗（改菜名重试 / 转手动录入）
      if (state.singleNutrition == null && state.compositeNutrition == null) {
        await _showNotFoundDialog(
          state.recognitionResult!,
          mealType: state.mealType,
          imagePath: state.imagePath,
        );
        return;
      }
      final foodItemRepo = await ref.read(foodItemRepoProvider.future);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CalibrationPage(
          recognitionResult: state.recognitionResult!,
          singleNutrition: state.singleNutrition,
          compositeNutrition: state.compositeNutrition,
          foodItemRepo: foodItemRepo,
          onConfirm: (servingG, calories, protein, fat, carbs, {componentsSnapshot}) async {
            final mealRepo = await ref.read(mealLogRepoProvider.future);
            final foodRepo = await ref.read(foodItemRepoProvider.future);
            final result = state.recognitionResult!;

            // 获取 foodItemId：单品用查库命中，复合菜创建 ai_recognized 记录
            // 必须有有效 food_item_id（meal_log.food_item_id 是非空 FK，
            // Task 2 已启用 PRAGMA foreign_keys = ON，id=0 会触发外键约束违规）
            int foodItemId;
            if (state.singleNutrition != null) {
              foodItemId = state.singleNutrition!.foodItemId;
            } else if (state.compositeNutrition != null) {
              // 复合菜：存入 food_item（source=ai_recognized，components_json 存组分快照）
              foodItemId = await foodRepo.upsertAiRecognized(
                name: result.dishName,
                caloriesPer100g: 0, // 复合菜热量不按 100g 密度存储，实际值在 meal_log
                proteinPer100g: 0,
                fatPer100g: 0,
                carbsPer100g: 0,
                confidence: result.confidence,
                componentsJson: componentsSnapshot,
              );
            } else {
              // 无营养数据（查库未命中），不记录
              return;
            }

            await mealRepo.insertMealLog(
              date: _todayLocalDate(),
              mealType: state.mealType, // Sprint 2 T0：从 controller state 读餐次
              foodItemId: foodItemId,
              actualServingG: servingG,
              actualCalories: calories,
              actualProteinG: protein,
              actualFatG: fat,
              actualCarbsG: carbs,
              originalImagePath: state.imagePath,
              recognitionConfidence: result.confidence,
              componentsSnapshotJson: componentsSnapshot,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已记录：${calories.toStringAsFixed(0)} kcal')),
              );
            }
          },
        ),
      ));
    } else if (state.state == RecognizeState.error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('识别失败：${state.errorMessage}')),
      );
    } else if (state.state == RecognizeState.queued) {
      // Sprint 2 T14：离线已入队提示
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.errorMessage ?? '已加入离线队列')),
      );
    }
  }

  Future<void> _showNotFoundDialog(
    VisionRecognitionResult result, {
    required String mealType,
    String? imagePath,
  }) async {
    if (!mounted) return;
    final action = await showDialog<_NotFoundAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未找到营养数据'),
        content: Text('识别菜名「${result.dishName}」在食物库中未命中。'
            '可修改菜名重试，或转手动录入。'),
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
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ManualEntryPage(initialName: result.dishName),
      ));
      return;
    }

    // 改菜名重试
    final newDishName = await _promptNewDishName(result.dishName);
    if (newDishName == null || newDishName.isEmpty || !mounted) return;

    // 重新查库
    final lookup = await ref.read(nutritionLookupProvider.future);
    final nutrition = await lookup.lookupSingleItem(
      dishName: newDishName,
      servingG: result.estimatedWeightGMid,
    );
    if (nutrition == null) {
      // 仍未命中 → 再次弹窗引导（递归，透传 mealType/imagePath）
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('修改后的菜名仍未命中，请转手动录入')),
      );
      await _showNotFoundDialog(
        result,
        mealType: mealType,
        imagePath: imagePath,
      );
      return;
    }
    // 命中 → 跳校准页（用新菜名的查库结果）
    if (!mounted) return;
    final foodItemRepo = await ref.read(foodItemRepoProvider.future);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CalibrationPage(
        recognitionResult: result,
        singleNutrition: nutrition,
        foodItemRepo: foodItemRepo,
        onConfirm: (servingG, calories, protein, fat, carbs, {componentsSnapshot}) async {
          final mealRepo = await ref.read(mealLogRepoProvider.future);
          await mealRepo.insertMealLog(
            date: _todayLocalDate(),
            mealType: mealType,
            foodItemId: nutrition.foodItemId,
            actualServingG: servingG,
            actualCalories: calories,
            actualProteinG: protein,
            actualFatG: fat,
            actualCarbsG: carbs,
            originalImagePath: imagePath,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已记录：${calories.toStringAsFixed(0)} kcal')),
            );
          }
        },
      ),
    ));
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
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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

  String _todayLocalDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

enum _NotFoundAction { cancel, retry, manual }
