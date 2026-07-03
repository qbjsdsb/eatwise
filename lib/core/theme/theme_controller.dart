// lib/core/theme/theme_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 主题种子色控制器（ARGB int）。
/// 默认莫奈《睡莲》青绿 #5B8C7B。
/// main.dart 启动时从 secure_storage 读出后调用 set()；
/// 设置页点选色板时调用 set() 并持久化，App 实时重建换肤。
class ThemeNotifier extends Notifier<int> {
  @override
  int build() => 0xFF5B8C7B; // 莫奈《睡莲》青绿

  /// 设置主题种子色。非法值（0/负数/alpha=0 全透明）忽略，
  /// 避免 Color(argb) 得到透明/异常色导致 UI 不可见。
  void set(int argb) {
    if (argb <= 0 || (argb >> 24) == 0) return; // ARGB 高 8 位 alpha 必须非 0
    state = argb;
  }
}

final themeSeedProvider = NotifierProvider<ThemeNotifier, int>(
  ThemeNotifier.new,
);

/// 预设主题色板：莫奈画作取色 + Material 经典色。
/// 每项为 (ARGB int, 名称)。
const kThemePresets = <(int, String)>[
  (0xFF5B8C7B, '睡莲青绿'), // 莫奈《睡莲》
  (0xFFE08B3C, '日出橙'), // 莫奈《日出·印象》
  (0xFF6B5B95, '鸢尾紫'), // 莫奈《鸢尾花》
  (0xFFD32F2F, '番茄红'),
  (0xFFE91E63, '粉红'),
  (0xFF7B1FA2, '深紫'),
  (0xFF303F9F, '靛蓝'),
  (0xFF1976D2, '海蓝'),
  (0xFF0097A7, '青'),
  (0xFF388E3C, '草绿'),
  (0xFFF57C00, '琥珀'),
  (0xFF5D4037, '棕'),
];
