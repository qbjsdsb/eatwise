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

  static const _titles = ['今日明细', '体重', '食物库'];

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
              onSelectionChanged: (v) => setState(() => _index = v.first),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          TodayMealsPage(embedded: true),
          WeightPage(embedded: true),
          FoodLibraryPage(embedded: true),
        ],
      ),
    );
  }
}
