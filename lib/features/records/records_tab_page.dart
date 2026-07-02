import 'package:flutter/material.dart';

import '../dashboard/today_meals_page.dart';
import '../food_library/food_library_page.dart';
import '../weight/weight_page.dart';

/// 记录 tab 容器页：SegmentedButton 切换 今日明细 / 体重 / 食物库
/// 用 IndexedStack 保留 3 子视图状态
class RecordsTabPage extends StatefulWidget {
  const RecordsTabPage({super.key});
  @override
  State<RecordsTabPage> createState() => _RecordsTabPageState();
}

class _RecordsTabPageState extends State<RecordsTabPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: const Text('记录')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('今日明细')),
                  ButtonSegment(value: 1, label: Text('体重')),
                  ButtonSegment(value: 2, label: Text('食物库')),
                ],
                selected: {_index},
                onSelectionChanged: (v) => setState(() => _index = v.first),
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: true,
            child: IndexedStack(
              index: _index,
              children: const [
                TodayMealsPage(),
                WeightPage(),
                FoodLibraryPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
