import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/backup/backup_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/dashboard/today_meals_page.dart';
import 'features/food_library/food_library_page.dart';
import 'features/insight/insight_page.dart';
import 'features/manual_entry/manual_entry_page.dart';
import 'features/profile/profile_page.dart';
import 'features/settings/settings_page.dart';
import 'features/weight/weight_page.dart';

class EatWiseApp extends StatelessWidget {
  const EatWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'EatWise',
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }

  // M3 亮色主题
  static final _lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.green,
      brightness: Brightness.light,
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
    ),
  );

  // M3 暗色主题
  static final _darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.green,
      brightness: Brightness.dark,
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
    ),
  );
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
    GoRoute(
      path: '/backup',
      builder: (context, state) => const BackupPage(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
  ],
);
