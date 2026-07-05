import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/util/date_format.dart';
import '../../core/util/refresh_bus.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/database/database.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/weight_log_repository.dart';
import '../../nutrition/tdee_calibrator.dart';
import '../recognize/providers.dart' as recognize;

/// 体重记录页：录入体重 + fl_chart 折线趋势图
class WeightPage extends ConsumerStatefulWidget {
  const WeightPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  ConsumerState<WeightPage> createState() => WeightPageState();
}

/// 公开 State：RecordsTabPage 通过 `GlobalKey<WeightPageState>` 调用 refresh()
class WeightPageState extends ConsumerState<WeightPage> {
  final _weightCtrl = TextEditingController();
  List<WeightLog> _logs = [];
  List<MealLog> _meals = []; // 30 天 meal_log（双轴图热量用）
  Map<String, double> _dailyCalories = {}; // 日期 → 当日总热量
  bool _loading = true;
  bool _busy = false; // 防重入：记录期间禁用按钮，避免双击重复写库
  // M14：用户是否改过输入（PopScope 未保存确认用）
  // _loading 守卫防初始赋值（_load 后清空 _weightCtrl 不应误标 dirty）
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    // M14：监听输入变化标记 dirty（防初始赋值误标）
    _weightCtrl.addListener(_markDirty);
    _load();
  }

  /// M14：标记用户已修改输入（PopScope 弹放弃确认用）
  void _markDirty() {
    if (_loading) return;
    if (_dirty) return; // 已是 dirty 不重复 setState
    setState(() => _dirty = true);
  }

  /// 公开刷新方法：切换到该页时由父容器调用
  void refresh() => _load();

  @override
  void dispose() {
    _weightCtrl.removeListener(_markDirty);
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final db = await ref.read(recognize.databaseProvider.future);
      final repo = WeightLogRepository(db);
      _logs = await repo.getRecent(days: 30);
      // 加载 30 天 meal_log 并按日聚合热量（双轴图用）
      final mealRepo = MealLogRepository(db);
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 30));
      final startStr = formatYmd(startDate);
      final endStr = formatYmd(now);
      _meals = await mealRepo.getRange(startStr, endStr);
      _dailyCalories = {};
      for (final m in _meals) {
        _dailyCalories[m.date] =
            (_dailyCalories[m.date] ?? 0) + m.actualCalories;
      }
    } catch (e) {
      // DB 异常时不卡死 loading，用空数据渲染（用户至少能看到空图表）
      _logs = [];
      _meals = [];
      _dailyCalories = {};
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: widget.embedded ? null : AppBar(title: const Text('体重记录')),
        body: const LoadingState(),
      );
    }
    // M14：PopScope 未保存确认（与 manual_entry_page/calibration_page 风格一致）
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmDiscardChanges(context) && context.mounted) {
          _dirty = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: widget.embedded ? null : AppBar(title: const Text('体重记录')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: '今日体重 (kg)'),
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary),
                        )
                      : const Text('记录'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_logs.length >= 2)
              SizedBox(height: 250, child: _buildChart())
            else
              const EmptyChartHint('至少记录 2 次才能显示趋势图'),
            const SizedBox(height: 16),
            for (final log in _logs.reversed)
              _buildWeightTile(log),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    if (_logs.length < 2) {
      return const Center(child: Text('至少记录 2 次才能显示趋势图'));
    }

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // 双轴技巧：fl_chart 0.70 不原生支持双 Y 轴。热量用真实值（左轴），
    // 体重按比例映射到热量轴范围；rightTitles 用 getTitlesWidget 反向映射
    // 显示体重刻度（社区常用双轴方案）。
    final weightSpots = <FlSpot>[];
    for (var i = 0; i < _logs.length; i++) {
      weightSpots.add(FlSpot(i.toDouble(), _logs[i].weightKg));
    }
    final weights = _logs.map((l) => l.weightKg).toList();
    final minW = weights.reduce((a, b) => a < b ? a : b);
    final maxW = weights.reduce((a, b) => a > b ? a : b);
    final wPadding = (maxW - minW) * 0.1 + 0.5;

    // 热量数据（主轴/左轴）：按体重记录日期对齐
    final calSpots = <FlSpot>[];
    for (var i = 0; i < _logs.length; i++) {
      final cal = _dailyCalories[_logs[i].date] ?? 0;
      calSpots.add(FlSpot(i.toDouble(), cal));
    }
    final cals = calSpots.map((s) => s.y).toList();
    final maxCal = cals.reduce((a, b) => a > b ? a : b);
    final calPadding = maxCal * 0.1 + 50;
    final calRange = maxCal + calPadding;
    final wMin = minW - wPadding;
    final wMax = maxW + wPadding;

    // Y 轴刻度间隔：热量轴 1/4 取整（刻度整齐不重叠，左右轴共用同一组刻度）
    final yInterval = (calRange / 4).clamp(1.0, double.infinity).toDouble();
    // 体重映射到热量轴范围后的 spots
    final weightMappedSpots = weightSpots
        .map((s) => FlSpot(s.x, (s.y - wMin) / (wMax - wMin) * calRange))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 图例：说明哪条线是热量、哪条线是体重
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LegendDot(color: cs.tertiary, label: '热量 (kcal)'),
              const SizedBox(width: 16),
              LegendDot(color: cs.primary, label: '体重 (kg)'),
            ],
          ),
        ),
        Expanded(
          child: LineChart(LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false, // 只留水平网格，去掉垂直线减少噪音
              horizontalInterval: yInterval,
              getDrawingHorizontalLine: (v) => FlLine(
                color: cs.outlineVariant.withValues(alpha: 0.4),
                strokeWidth: 1,
                dashArray: [3, 3],
              ),
            ),
            borderData: FlBorderData(
              show: true,
              // 只留左 + 下边框（现代图表风格）
              border: Border(
                left: BorderSide(color: cs.outlineVariant),
                bottom: BorderSide(color: cs.outlineVariant),
                top: BorderSide.none,
                right: BorderSide.none,
              ),
            ),
            minX: 0,
            maxX: (_logs.length - 1).toDouble(),
            minY: 0,
            maxY: calRange,
            titlesData: FlTitlesData(
              bottomTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                axisNameWidget: Text('kcal',
                    style: textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  interval: yInterval, // 固定间隔防重叠
                  getTitlesWidget: (value, meta) {
                    // 0 不显示（避免和 X 轴标签挤）
                    if (value == 0) return const SizedBox.shrink();
                    return Text('${value.round()}',
                        style: textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ]));
                  },
                ),
              ),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(
                axisNameWidget: Text('kg',
                    style: textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  // 双轴：右 Y 轴显示体重刻度。interval 用热量轴单位
                  //（getTitlesWidget 收到的 value 是热量轴值，按比例反推体重）
                  interval: yInterval,
                  getTitlesWidget: (value, meta) {
                    // value 是热量轴（左 Y 轴）值，反向映射回体重轴值
                    final ratio = value / calRange;
                    final w = wMin + (wMax - wMin) * ratio;
                    return Text(w.toStringAsFixed(1),
                        style: textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ]));
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              // 触摸节点显示具体值 + 高亮指示线
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    final idx = spot.spotIndex;
                    final log = _logs[idx];
                    // barIndex 0 = 热量，1 = 体重
                    final valueText = spot.barIndex == 0
                        ? '${_dailyCalories[log.date]?.round() ?? 0} kcal'
                        : '${log.weightKg.toStringAsFixed(1)} kg';
                    return LineTooltipItem(
                      '${log.date}\n$valueText',
                      TextStyle(
                        color: cs.onInverseSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    );
                  }).toList();
                },
              ),
              getTouchedSpotIndicator: (barData, spotIndexes) {
                return spotIndexes.map((index) {
                  return TouchedSpotIndicatorData(
                    FlLine(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                      strokeWidth: 1,
                      dashArray: [3, 3],
                    ),
                    FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: cs.surface,
                        strokeWidth: 2,
                        strokeColor: bar.color ?? cs.primary,
                      ),
                    ),
                  );
                }).toList();
              },
            ),
            lineBarsData: [
              // 热量（左轴，主）
              LineChartBarData(
                spots: calSpots,
                isCurved: true,
                curveSmoothness: 0.35,
                color: cs.tertiary,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                    radius: 3,
                    color: cs.tertiary,
                    strokeWidth: 1.5,
                    strokeColor: cs.surface,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      cs.tertiary.withValues(alpha: 0.18),
                      cs.tertiary.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
              // 体重（映射到主轴范围）
              LineChartBarData(
                spots: weightMappedSpots,
                isCurved: true,
                curveSmoothness: 0.35,
                color: cs.primary,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                    radius: 3,
                    color: cs.primary,
                    strokeWidth: 1.5,
                    strokeColor: cs.surface,
                  ),
                ),
              ),
            ],
          )),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_busy) return; // 防重入
    if (_weightCtrl.text.isEmpty) return;
    final weight = double.tryParse(_weightCtrl.text);
    if (weight == null || weight <= 0) {
      if (!mounted) return;
      showAppToast(context, '请输入有效的体重数字');
      return;
    }
    setState(() => _busy = true);
    try {
      final db = await ref.read(recognize.databaseProvider.future);
      final repo = WeightLogRepository(db);
      final today = todayYmd();
      await repo.insert(date: today, weightKg: weight);

      // 同步 profile.weightKg：让 dashboard 宏量目标（proteinGPerKg * weightKg）
      // 随最新体重变化。原代码只写 weight_logs 表，profile.weightKg 不变，
      // 导致即使主页刷新，宏量目标仍用旧体重算。
      // 注意：不重算 dailyCalorieTarget（BMR 重算只在用户主动编辑档案时做，
      // 日常体重波动通过 TDEE 校准 adjustmentKcal 微调）
      await ProfileRepository(db).update(weightKg: weight);

      // 触发 TDEE 自适应校准（Sprint 3 T22）
      try {
        final config = await ref.read(appConfigProvider.future);
        if (config.tdeeAutoCalib) {
          final calibrator = TdeeCalibrator(db);
          final result = await calibrator.runAndApply(enabled: true);
          if (result.adjustmentKcal != 0 && mounted) {
            showAppToast(context, 'TDEE 已调整：${result.reason}');
          }
        }
      } catch (_) {
        // 校准失败不影响体重记录主流程
      }

      _weightCtrl.clear();
      await _load();
      // 通知 dashboard/records/insight 等监听 RefreshBus 的页面刷新
      // 修复：原代码只刷新本页（_load），主页宏量目标/目标热量不更新
      RefreshBus.instance.notify();
      if (mounted) {
        // M14：保存成功后清 dirty 标志，避免 _weightCtrl.clear() 触发 listener 误标
        _dirty = false;
        showAppToast(context, '已记录体重');
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '记录失败：$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 体重记录卡片：Dismissible 滑删 + onTap 编辑
  /// 用户输错体重后必须能改/删，否则折线图被污染
  Widget _buildWeightTile(WeightLog log) {
    final cs = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('weight-${log.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: cs.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: ExcludeSemantics(
            child: Icon(Icons.delete, color: cs.onErrorContainer)),
      ),
      // 滑删确认：避免误删（体重记录通常较少，二次确认成本可接受）
      confirmDismiss: (_) => confirmAction(
        context,
        title: '删除体重记录？',
        content: '${log.weightKg.toStringAsFixed(1)} kg · ${log.date}',
        confirmLabel: '删除',
        destructive: true,
      ),
      onDismissed: (_) => _deleteWeight(log),
      child: ListTile(
        leading: const LeadingIconContainer(Icons.monitor_weight_outlined),
        title: Text('${log.weightKg.toStringAsFixed(1)} kg',
            style: TextStyle(
                fontFeatures: const [FontFeature.tabularFigures()])),
        subtitle: Text(log.date),
        trailing: const ExcludeSemantics(child: Icon(Icons.chevron_right)),
        onTap: () => _showEditWeightDialog(log),
      ),
    );
  }

  /// 编辑体重记录 dialog：改体重值 + 改日期
  Future<void> _showEditWeightDialog(WeightLog log) async {
    if (_busy) return;
    final weightCtrl =
        TextEditingController(text: log.weightKg.toStringAsFixed(1));
    // 解析原日期为 DateTime（DatePicker 初始值）
    DateTime selectedDate;
    try {
      final parts = log.date.split('-').map(int.parse).toList();
      selectedDate = DateTime(parts[0], parts[1], parts[2]);
    } catch (_) {
      selectedDate = DateTime.now();
    }
    try {
      final result = await showDialog<_WeightEditResult>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('编辑体重'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: weightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '体重 (kg)'),
                ),
                const SizedBox(height: 12),
                // 日期选择器：点击行触发 DatePicker
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      const ExcludeSemantics(
                          child: Icon(Icons.calendar_today_outlined)),
                  title: Text(formatYmd(selectedDate)),
                  trailing:
                      const ExcludeSemantics(child: Icon(Icons.chevron_right)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  final w = double.tryParse(weightCtrl.text.trim());
                  Navigator.pop(
                    ctx,
                    _WeightEditResult(
                      weightKg: w,
                      date: formatYmd(selectedDate),
                    ),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      );
      if (result == null || result.weightKg == null || result.weightKg! <= 0) {
        return;
      }
      if (!mounted) return;
      // 仅在值或日期变化时写库（避免无意义 IO）
      if (result.weightKg == log.weightKg && result.date == log.date) return;
      setState(() => _busy = true);
      try {
        final db = await ref.read(recognize.databaseProvider.future);
        final repo = WeightLogRepository(db);
        await repo.update(
          id: log.id,
          weightKg: result.weightKg,
          date: result.date,
        );
        // 若改的是最新一条体重，同步 profile.weightKg（与 _save 一致逻辑）
        final isLatest = _logs.isEmpty || log.id == _logs.last.id;
        if (isLatest) {
          await ProfileRepository(db).update(weightKg: result.weightKg);
        }
        await _load();
        RefreshBus.instance.notify();
        if (mounted) {
          showAppToast(context, '已更新体重记录');
        }
      } catch (e) {
        if (mounted) {
          showAppToast(context, '保存失败：$e');
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } finally {
      weightCtrl.dispose();
    }
  }

  /// 删除体重记录：先 DB 删除，再刷新本页 + 通知 dashboard
  /// 注：不做 Undo SnackBar——已用 confirmDismiss 二次确认，再 Undo 流程冗余
  Future<void> _deleteWeight(WeightLog log) async {
    try {
      final db = await ref.read(recognize.databaseProvider.future);
      final repo = WeightLogRepository(db);
      await repo.delete(log.id);
      // 若删的是最新一条体重，profile.weightKg 不自动回退
      // （用户删最新记录的场景是"输错"，profile 维持旧值是合理的，
      // 后续再录新体重会自动同步）
      await _load();
      RefreshBus.instance.notify();
      if (mounted) {
        showAppToast(context, '已删除体重记录');
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '删除失败：$e');
        await _load(); // 失败回滚 UI
      }
    }
  }
}

/// 编辑体重 dialog 返回结果
class _WeightEditResult {
  final double? weightKg;
  final String date;
  const _WeightEditResult({this.weightKg, required this.date});
}
