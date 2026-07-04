import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        // tonalSpot：secondary/tertiary 紧跟 primary 色相，切色后整体跟随
        // （expressive 会对 secondary 做色相旋转致大面积绿色，与"切色"预期不符）
        dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
      )),
      darkTheme: _theme(ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
      )),
      themeMode: ThemeMode.system,
      routerConfig: _router,
      // 启用 edge-to-edge（Android 15+ 强制，14- 推荐）：
      // 状态栏/导航栏透明，内容延伸到系统栏后方，避免 NavigationBar 被手势条遮挡。
      // 配合 AppBarTheme.systemOverlayStyle 控制状态栏图标颜色随主题变化。
      builder: (context, child) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        return child!;
      },
    );
  }

  /// M3 Expressive 规范基线：
  /// - Card 16dp 圆角（普通）/ HeroCard 28dp（焦点卡片，组件层显式覆盖）
  /// - FilledButton 20dp 圆角 + 48dp 触摸目标
  /// - 输入框统一 OutlineInputBorder
  /// - SnackBar floating
  /// - NavigationBar pill 指示器 + labelMedium 字号
  /// - ProgressIndicator 圆角 + onSurfaceVariant 加载色（M3 Expressive 推荐）
  /// - FAB 16dp 圆角（M3 Expressive）+ elevation 3
  /// - SegmentedButton selected 用 primaryContainer
  /// - DropdownMenu 默认占满宽度（expandedInsets: zero）
  /// 亮/暗共用组件主题，仅 ColorScheme 随 brightness 变化。
  static ThemeData _theme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // M3 Expressive：elevation 1 让卡片在 surface 上有轻微浮起层次，
      // 解决 elevation 0 时分组卡片与背景融合不可见的问题。
      // surfaceTintColor 显式声明让 elevation>0 时表面带 primary 色调渐变（M3 tonal elevation）。
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 1,
        surfaceTintColor: colorScheme.surfaceTint,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      // TextButton 触摸目标 ≥48dp（WCAG 2.5.5）：默认 36dp 不达标，
      // 全局提升避免每个 TextButton 单独设 minimumSize
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
      ),
      // OutlinedButton 同样提升到 48dp，与 FilledButton/TextButton 一致
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        // 滚动时下方 elevation（M3 推荐 3dp）
        scrolledUnderElevation: 3,
        // 透明 surfaceTintColor 避免 AppBar 变色（保持 surface 一致）
        surfaceTintColor: Colors.transparent,
        // 状态栏图标颜色跟随主题亮度（亮色主题用 dark 图标，暗色用 light）
        systemOverlayStyle: colorScheme.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
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
      // ProgressIndicator 统一圆角 + 加载色（M3 Expressive 推荐柔和的 onSurfaceVariant）
      // 注意：linearBorderRadius 是 Flutter 3.27+ 属性，当前 SDK 不支持，
      // dashboard 两处 LinearProgressIndicator 仍用 ClipRRect 包裹实现圆角
      progressIndicatorTheme: ProgressIndicatorThemeData(
        circularTrackColor: colorScheme.surfaceContainerHighest,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        linearMinHeight: 4,
        // 加载色用 onSurfaceVariant（M3 Expressive 推荐，比 primary 更柔和）
        color: colorScheme.onSurfaceVariant,
      ),
      // FAB 主题：统一 main_shell FAB 圆角 16dp + elevation 3
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 3,
      ),
      // SegmentedButton 主题：selected 段用 primaryContainer 配色（M3 Expressive 推荐）
      // 注意：ButtonStyle 用 backgroundColor/foregroundColor + WidgetStateProperty.resolveWith
      // （selectedBackgroundColor/selectedForegroundColor 是 Flutter 3.22+ 属性，当前 SDK 不支持）
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.primaryContainer;
            }
            return colorScheme.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onPrimaryContainer;
            }
            return colorScheme.onSurfaceVariant;
          }),
          // 触摸目标 48dp
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
        ),
      ),
      // 注意：DropdownMenuThemeData 无 expandedInsets 属性（expandedInsets 是 DropdownMenu 自身属性）
      // 各页面 DropdownMenu 仍需显式传 expandedInsets: EdgeInsets.zero
      // ListTile 主题：统一 selected/icon 配色 + trailing chevron 默认色
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        selectedColor: colorScheme.primary,
      ),
      // Divider 主题：统一颜色与高度
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorShape: const StadiumBorder(),
        // 显式 backgroundColor 避免 Flutter 版本默认值不确定
        backgroundColor: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        height: 80,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          // M3 推荐 NavigationBar 用 labelMedium
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600);
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
