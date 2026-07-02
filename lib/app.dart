import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/backup/backup_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/food_library/food_library_page.dart';
import 'features/insight/insight_page.dart';
import 'features/manual_entry/manual_entry_page.dart';
import 'features/me/me_page.dart';
import 'features/profile/profile_page.dart';
import 'features/records/records_tab_page.dart';
import 'features/recognize/recognize_page.dart';
import 'features/settings/settings_page.dart';
import 'features/weight/weight_page.dart';
import 'main_shell.dart';

/// 莫奈《睡莲》seedColor：青绿色调，宁静治愈，契合健康饮食语义
const _monetWaterLilySeed = Color(0xFF5B8C7B);

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

  /// M3 规范基线：卡片 12dp 圆角、FilledButton 20dp 圆角 + 内容宽度、
  /// 输入框统一 OutlineInputBorder、SnackBar floating、NavigationBar pill 指示器。
  /// 亮/暗共用组件主题，仅 ColorScheme 随 brightness 变化。
  static ThemeData _theme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _monetWaterLilySeed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.expressive,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // M3 Expressive：elevation 1 让卡片在 surface 上有轻微浮起层次，
      // 解决 elevation 0 时分组卡片与背景融合不可见的问题。
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(centerTitle: false),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      navigationBarTheme: NavigationBarThemeData(
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
          }
          return const TextStyle(fontSize: 12);
        }),
      ),
    );
  }

  static final _lightTheme = _theme(Brightness.light);
  static final _darkTheme = _theme(Brightness.dark);
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainShell(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/', builder: (c, s) => const DashboardPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/today', builder: (c, s) => const RecordsTabPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/insight', builder: (c, s) => const InsightPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/me', builder: (c, s) => const MePage()),
        ]),
      ],
    ),
    GoRoute(path: '/weight', builder: (c, s) => const WeightPage()),
    GoRoute(
        path: '/food_library', builder: (c, s) => const FoodLibraryPage()),
    GoRoute(path: '/profile', builder: (c, s) => const ProfilePage()),
    GoRoute(path: '/settings', builder: (c, s) => const SettingsPage()),
    GoRoute(path: '/backup', builder: (c, s) => const BackupPage()),
    GoRoute(
        path: '/manual_entry', builder: (c, s) => const ManualEntryPage()),
    GoRoute(path: '/recognize', builder: (c, s) => const RecognizePage()),
  ],
);
