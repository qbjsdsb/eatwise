import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/theme_controller.dart';
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

class EatWiseApp extends ConsumerWidget {
  const EatWiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 主题种子色来自 Riverpod（设置页点选色板时实时换肤）
    final seed = Color(ref.watch(themeSeedProvider));
    return MaterialApp.router(
      title: '慢慢吃',
      theme: _theme(ColorScheme.fromSeed(
        seedColor: seed,
        dynamicSchemeVariant: DynamicSchemeVariant.expressive,
      )),
      darkTheme: _theme(ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        dynamicSchemeVariant: DynamicSchemeVariant.expressive,
      )),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }

  /// M3 规范基线：卡片 12dp 圆角、FilledButton 20dp 圆角 + 内容宽度、
  /// 输入框统一 OutlineInputBorder、SnackBar floating、NavigationBar pill 指示器。
  /// 亮/暗共用组件主题，仅 ColorScheme 随 brightness 变化。
  static ThemeData _theme(ColorScheme colorScheme) {
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
