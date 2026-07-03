import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/theme_controller.dart';
import 'features/backup/backup_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/dashboard/today_meals_page.dart';
import 'features/food_library/food_library_page.dart';
import 'features/insight/insight_page.dart';
import 'features/manual_entry/manual_entry_page.dart';
import 'features/profile/profile_page.dart';
import 'features/settings/settings_page.dart';
import 'features/weight/weight_page.dart';

class EatWiseApp extends ConsumerWidget {
  const EatWiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = Color(ref.watch(themeSeedProvider));
    final lightCs = ColorScheme.fromSeed(seedColor: seed);
    final darkCs = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return MaterialApp.router(
      title: '慢慢吃',
      theme: _theme(lightCs),
      darkTheme: _theme(darkCs),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }

  /// 全局主题基线：M3 规范统一卡片/输入框/按钮圆角，避免散落硬编码。
  static ThemeData _theme(ColorScheme cs) => ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    // 卡片：12dp 圆角 + elevation 1，分组卡片在 surface 上有轻微浮起
    cardTheme: const CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      elevation: 1,
    ),
    // 输入框：统一 OutlineInputBorder，消除下划线/描边混用
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(),
    ),
    // FilledButton：20dp 圆角（M3 expressive）
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
    ),
  );
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const DashboardPage()),
    GoRoute(
      path: '/today',
      builder: (context, state) => const TodayMealsPage(),
    ),
    GoRoute(path: '/profile', builder: (context, state) => const ProfilePage()),
    GoRoute(
      path: '/food_library',
      builder: (context, state) => const FoodLibraryPage(),
    ),
    GoRoute(
      path: '/manual_entry',
      builder: (context, state) => const ManualEntryPage(),
    ),
    GoRoute(path: '/weight', builder: (context, state) => const WeightPage()),
    GoRoute(path: '/insight', builder: (context, state) => const InsightPage()),
    GoRoute(path: '/backup', builder: (context, state) => const BackupPage()),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
  ],
);
