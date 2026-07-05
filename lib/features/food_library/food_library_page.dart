import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/food_name.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/repositories/food_item_repository.dart';
import '../recognize/providers.dart' as recognize;
import 'food_edit_page.dart';

/// 食物库页（列表 + 搜索 + 复用/编辑）
/// pickForReuse=true: 从手动录入页跳来选食物复用，pop 返回选中 FoodItem
/// pickForReuse=false: 普通浏览，点击进编辑页
class FoodLibraryPage extends ConsumerStatefulWidget {
  const FoodLibraryPage({super.key, this.pickForReuse = false, this.embedded = false});
  final bool pickForReuse;
  final bool embedded;

  @override
  ConsumerState<FoodLibraryPage> createState() => _FoodLibraryPageState();
}

class _FoodLibraryPageState extends ConsumerState<FoodLibraryPage> {
  final _searchCtrl = TextEditingController();
  List<FoodItem> _frequent = [];
  List<FoodItem> _searchResults = [];
  bool _searching = false; // 是否处于搜索模式（输入框非空）
  bool _searchLoading = false; // 搜索查询进行中（debounce + 异步查询期间）
  bool _initialLoading = true; // 首屏常吃列表加载中（避免数据未到时误显"暂无常用食物"）
  bool _loadError = false; // 加载失败标志：与"暂无常用食物"空态严格区分（避免误导用户）
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
    try {
      final repo = await ref.read(recognize.foodItemRepoProvider.future);
      _frequent = await repo.listFrequent();
      _loadError = false; // 加载成功：清错误标志（重试成功后兜底）
      if (mounted) setState(() {});
    } catch (_) {
      // DB 异常：置 _loadError 标志让 build 显 ErrorState + 重试按钮
      // （不静默显"暂无常用食物"空态误导用户，与 profile_page _loadError 同构）
      _loadError = true;
    } finally {
      if (mounted) setState(() => _initialLoading = false);
    }
  }

  /// 防抖搜索：300ms 内连续输入只发最后一次查询；
  /// 序列号校验：丢弃乱序到达的旧结果，避免覆盖新结果。
  /// 输入非空立即进入搜索模式并显示 loading（debounce + 查询期间），
  /// 查询返回后 loading 关闭；输入清空回到常吃列表。
  void _search(String keyword) {
    _debounce?.cancel();
    if (keyword.isEmpty) {
      setState(() {
        _searching = false;
        _searchLoading = false;
        _searchResults = [];
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchLoading = true;
    });
    _debounce = Timer(const Duration(milliseconds: 300), () => _doSearch(keyword));
  }

  Future<void> _doSearch(String keyword) async {
    final seq = ++_searchSeq;
    try {
      final repo = await ref.read(recognize.foodItemRepoProvider.future);
      final results = await repo.searchByName(keyword);
      // 序列号校验：若期间用户又输入了新关键词，丢弃本次结果
      if (seq != _searchSeq || !mounted) return;
      setState(() {
        _searchResults = results;
        _searchLoading = false;
      });
    } catch (_) {
      // 查询异常：关闭 loading，清空结果，避免 UI 永久卡转圈；
      // 同时弹 toast 提示用户搜索失败可重试（避免静默吞错显示"未找到相关食物"误导）
      if (seq != _searchSeq || !mounted) return;
      setState(() {
        _searchResults = [];
        _searchLoading = false;
      });
      showAppToast(context, '搜索失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 加载失败：显 ErrorState + 重试按钮（不显空态"暂无常用食物"误导用户）
    // 与 profile_page.dart 的 _loadError + ErrorState 模式同构
    if (_loadError) {
      return Scaffold(
        body: ErrorState(
          message: '常用食物加载失败',
          onRetry: () {
            setState(() {
              _loadError = false;
              _initialLoading = true;
            });
            // 失败可能源于 databaseProvider 缓存的错误（如 DB 打开失败），
            // invalidate 后下次 read 会重新执行 create 函数，让重试真正生效
            // M24 Task B1：同时 invalidate foodItemRepoProvider（它缓存了 error 态，
            // 仅 invalidate databaseProvider 不会立即刷新 foodItemRepoProvider 的缓存）
            ref.invalidate(recognize.databaseProvider);
            ref.invalidate(recognize.foodItemRepoProvider);
            _loadFrequent();
          },
        ),
      );
    }
    final list = _searching ? _searchResults : _frequent;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('食物库')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: '搜索食物…',
              leading: const Icon(Icons.search),
              onChanged: _search,
            ),
          ),
          if (!_searching && _frequent.isNotEmpty) SectionTitle('常吃'),
          if (!_searching && _frequent.isEmpty)
            // 首屏加载中显示转圈，避免数据未到时误显"暂无常用食物"
            // LoadingState 内部 Center 在 Column unbounded 高度下会报错，用 SizedBox 约束高度
            _initialLoading
                ? const SizedBox(height: 200, child: LoadingState())
                : const EmptyState(
                    icon: Icons.restaurant_menu,
                    title: '暂无常用食物',
                    subtitle: '去拍照识别或手动录入后会出现在这里',
                  ),
          Expanded(
            child: _searching && _searchLoading
                ? const LoadingState()
                : _searching && _searchResults.isEmpty
                    ? _emptySearchHint(cs)
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final f = list[i];
                          return ListTile(
                            leading: const LeadingIconContainer(
                                Icons.restaurant_rounded),
                            title: Text(
                              f.name.trim().isEmpty ? '未命名食物' : f.name,
                            ),
                            subtitle: Text(
                                '${f.caloriesPer100g.toStringAsFixed(0)} kcal/100 g · ${foodSourceLabel(f.source)}',
                                style: TextStyle(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ])),
                            // 可跳转编辑页，加 chevron 提示（与 me/settings/dashboard 全局约定一致）
                            trailing: const ExcludeSemantics(
                                child: Icon(Icons.chevron_right)),
                            onTap: () async {
                              if (widget.pickForReuse) {
                                Navigator.of(context).pop(f);
                              } else {
                                await Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            FoodEditPage(foodItem: f)));
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

  /// 搜索无结果占位：套 Card 包裹 + 固定高度，与 insight/weight 图表空态统一。
  Widget _emptySearchHint(ColorScheme cs) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      height: 120,
      child: Card(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                  child: Icon(Icons.search_off_rounded,
                      size: 40, color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text('未找到相关食物',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
