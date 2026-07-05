// lib/features/dashboard/dashboard_data.dart
// Dashboard 数据模型（从 dashboard_page.dart 拆出，M24 B5）
//
// 单独文件存放避免主文件与 section widget 子文件之间循环 import。
// dashboard_page.dart 与各 section widget 都 import 此文件取 DashboardData 类型。
import '../../../data/repositories/meal_log_repository.dart';

/// Dashboard 页面聚合数据（_loadData 一次性查库后填充，传给各 section widget 渲染）
class DashboardData {
  final double cal;
  final double protein;
  final double fat;
  final double carbs;
  final int target;
  final double proteinGoal;
  final double fatGoal;
  final double carbGoal;
  final double weightKg;
  final List<MealLog> meals;
  final Map<int, String> foodNames;

  DashboardData({
    required this.cal,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.target,
    required this.proteinGoal,
    required this.fatGoal,
    required this.carbGoal,
    required this.weightKg,
    required this.meals,
    required this.foodNames,
  });
}
