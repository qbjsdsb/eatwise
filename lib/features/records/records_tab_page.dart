import 'package:flutter/material.dart';

import '../../core/util/refresh_bus.dart';
import '../dashboard/today_meals_page.dart';
import '../food_library/food_library_page.dart';
import '../weight/weight_page.dart';

/// 记录 tab 容器页：SegmentedButton 切换 今日明细 / 体重 / 食物库
/// 用 IndexedStack 保留 3 子视图状态，切换时刷新对应页数据
class RecordsTabPage extends StatefulWidget {
  const RecordsTabPage({super.key});
  @override
  State<RecordsTabPage> createState() => _RecordsTabPageState();
}

class _RecordsTabPageState extends State<RecordsTabPage> {
  int _index = 0;

  static const _titles = ['今日明细', '体重', '食物库'];

  // GlobalKey 用于切换时调用子页 refresh（今日明细/体重数据随记录变化）
  final _todayMealsKey = GlobalKey<TodayMealsPageState>();
  final _weightKey = GlobalKey<WeightPageState>();

  @override
  void initState() {
    super.initState();
    // 监听刷新总线：拍照记录返回后刷新当前可见子页数据
    RefreshBus.instance.addListener(_onRefreshBus);
  }

  @override
  void dispose() {
    RefreshBus.instance.removeListener(_onRefreshBus);
    super.dispose();
  }

  /// 收到刷新通知：刷新当前可见的子页（IndexedStack 中非当前页用户看不到，暂不刷）
  void _onRefreshBus() {
    if (!mounted) return;
    if (_index == 0) {
      _todayMealsKey.currentState?.refresh();
    } else if (_index == 1) {
      _weightKey.currentState?.refresh();
    }
    // FoodLibraryPage 无公开 refresh（编辑返回时自行 _loadFrequent）
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('今日明细')),
                ButtonSegment(value: 1, label: Text('体重')),
                ButtonSegment(value: 2, label: Text('食物库')),
              ],
              selected: {_index},
              onSelectionChanged: (v) {
                setState(() => _index = v.first);
                // 切换到对应页时刷新数据（拍照记录后切回可见最新）
                if (_index == 0) {
                  _todayMealsKey.currentState?.refresh();
                } else if (_index == 1) {
                  _weightKey.currentState?.refresh();
                }
              },
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          TodayMealsPage(embedded: true, key: _todayMealsKey),
          WeightPage(embedded: true, key: _weightKey),
          const FoodLibraryPage(embedded: true),
        ],
      ),
    );
  }
}
