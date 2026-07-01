import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/dashboard/dashboard_page.dart';
import 'features/dashboard/today_meals_page.dart';
import 'features/food_library/food_library_page.dart';
import 'features/insight/insight_page.dart';
import 'features/manual_entry/manual_entry_page.dart';
import 'features/profile/profile_page.dart';
import 'features/weight/weight_page.dart';

class EatWiseApp extends StatelessWidget {
  const EatWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'EatWise',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const DashboardPage(),
    ),
    GoRoute(
      path: '/today',
      builder: (context, state) => const TodayMealsPage(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfilePage(),
    ),
    GoRoute(
      path: '/food_library',
      builder: (context, state) => const FoodLibraryPage(),
    ),
    GoRoute(
      path: '/manual_entry',
      builder: (context, state) => const ManualEntryPage(),
    ),
    GoRoute(
      path: '/weight',
      builder: (context, state) => const WeightPage(),
    ),
    GoRoute(
      path: '/insight',
      builder: (context, state) => const InsightPage(),
    ),
  ],
);
