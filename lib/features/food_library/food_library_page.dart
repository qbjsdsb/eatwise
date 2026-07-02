import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';
import '../../data/repositories/food_item_repository.dart';
import '../recognize/providers.dart' as recognize;
import 'food_edit_page.dart';

/// 食物库页（列表 + 搜索 + 复用/编辑）
/// pickForReuse=true: 从手动录入页跳来选食物复用，pop 返回选中 FoodItem
/// pickForReuse=false: 普通浏览，点击进编辑页
class FoodLibraryPage extends ConsumerStatefulWidget {
  const FoodLibraryPage({super.key, this.pickForReuse = false});
  final bool pickForReuse;

  @override
  ConsumerState<FoodLibraryPage> createState() => _FoodLibraryPageState();
}

class _FoodLibraryPageState extends ConsumerState<FoodLibraryPage> {
  final _searchCtrl = TextEditingController();
  List<FoodItem> _frequent = [];
  List<FoodItem> _searchResults = [];
  bool _searching = false;
  // 搜索防抖 + 竞态保护：debounce 计时器 + 请求序列号
  Timer? _debounce;
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadFrequent();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFrequent() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = FoodItemRepository(db);
    _frequent = await repo.listFrequent();
    if (mounted) setState(() {});
  }

  /// 防抖搜索：300ms 内连续输入只发最后一次查询；
  /// 序列号校验：丢弃乱序到达的旧结果，避免覆盖新结果
  void _search(String keyword) {
    _debounce?.cancel();
    if (keyword.isEmpty) {
      setState(() {
        _searching = false;
        _searchResults = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _doSearch(keyword));
  }

  Future<void> _doSearch(String keyword) async {
    final seq = ++_searchSeq;
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = FoodItemRepository(db);
    final results = await repo.searchByName(keyword);
    // 序列号校验：若期间用户又输入了新关键词，丢弃本次结果
    if (seq != _searchSeq || !mounted) return;
    setState(() {
      _searchResults = results;
      _searching = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _searching ? _searchResults : _frequent;
    return Scaffold(
      appBar: AppBar(title: const Text('食物库')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: '搜索食物',
              leading: const Icon(Icons.search),
              onChanged: _search,
            ),
          ),
          if (!_searching && _frequent.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('常吃',
                      style: TextStyle(fontWeight: FontWeight.bold))),
            ),
          if (!_searching && _frequent.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                  child: Text('暂无常用食物，去拍照识别或手动录入后会出现在这里',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant))),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final f = list[i];
                return ListTile(
                  title: Text(f.name),
                  subtitle: Text(
                      '${f.caloriesPer100g.toStringAsFixed(0)} kcal/100g · ${_sourceLabel(f.source)}'),
                  onTap: () async {
                    if (widget.pickForReuse) {
                      Navigator.of(context).pop(f); // 返回选中的 FoodItem 给手动录入页
                    } else {
                      await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => FoodEditPage(foodItem: f)));
                      // 编辑返回后刷新列表（营养素/份量可能已修改）
                      if (mounted) _loadFrequent();
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'china_fct':
        return '中国成分表';
      case 'usda':
        return 'USDA';
      case 'manual':
        return '手动';
      case 'ai_recognized':
        return 'AI 入库';
      default:
        return source;
    }
  }
}
