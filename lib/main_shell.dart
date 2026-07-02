import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/util/refresh_bus.dart';

/// 主壳层：底部导航 + 居中 FAB（拍照）
/// 4 tab（今日/记录/洞察/我的）+ FAB 短按直接进拍照页
///
/// StatefulWidget：FAB 拍照流程返回后通过 RefreshBus 通知当前 tab 刷新数据。
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    return Scaffold(
      body: navigationShell,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onFabTap(context),
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.camera_alt_rounded),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '记录',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: '洞察',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outlined),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }

  /// FAB 短按：进拍照页，返回后通知当前 tab 刷新数据
  Future<void> _onFabTap(BuildContext context) async {
    await context.push('/recognize');
    // 拍照记录流程结束返回后，通知当前可见 tab 重新加载数据
    if (!mounted) return;
    RefreshBus.instance.notify();
  }
}
