import 'dart:async';
import 'dart:io' show Platform;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/config/app_config.dart';
import '../../core/util/date_format.dart';
import '../../core/util/refresh_bus.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/bluetooth/mi_scale_parser.dart';
import '../../data/bluetooth/mi_scale_scanner.dart';
import '../../data/repositories/meal_log_repository.dart';
import '../../data/repositories/weight_log_repository.dart';
import '../../nutrition/body_fat_calculator.dart';
import '../../nutrition/tdee_calibrator.dart';
import '../profile/nutrition_calculator.dart';
import '../recognize/providers.dart' as recognize;

/// 体重记录页：录入体重 + fl_chart 折线趋势图
class WeightPage extends ConsumerStatefulWidget {
  const WeightPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  ConsumerState<WeightPage> createState() => WeightPageState();
}

/// 公开 State：RecordsTabPage 通过 `GlobalKey<WeightPageState>` 调用 refresh()
class WeightPageState extends ConsumerState<WeightPage>
    with WidgetsBindingObserver {
  final _weightCtrl = TextEditingController();
  List<WeightLog> _logs = [];
  List<MealLog> _meals = []; // 30 天 meal_log（双轴图热量用）
  Map<String, double> _dailyCalories = {}; // 日期 → 当日总热量
  bool _loading = true;
  bool _busy = false; // 防重入：记录期间禁用按钮，避免双击重复写库
  // M14：用户是否改过输入（PopScope 未保存确认用）
  // _loading 守卫防初始赋值（_load 后清空 _weightCtrl 不应误标 dirty）
  bool _dirty = false;
  // 体重校验错误（内联显示在主表单 TextField 下方，替代 toast）
  String? _weightError;

  // M27 蓝牙体重秤同步状态
  // _bleState：idle（未扫描）/ scanning（扫描中）/ captured（已捕获）/ error（错误）
  // _bleScanner：BLE 扫描 Service，懒初始化（首次开启蓝牙同步时创建）
  // _bleEnabled：用户是否已开启蓝牙同步（首次点击横幅后置 true，后续进入自动扫描）
  // _scanSub：measurementStream 订阅，dispose 时 cancel
  _BleState _bleState = _BleState.idle;
  MiScaleScanner? _bleScanner;
  bool _bleEnabled = false;
  StreamSubscription<MiScaleMeasurement>? _scanSub;
  // 扫描冷却：5 分钟内 ≤3 次 startScan（MIUI 熔断阈值）
  final List<DateTime> _scanTimestamps = [];

  // M27 v2：v2 协议阻抗捕获时机
  MiScaleMeasurement? _pendingStabilized; // v2 稳定但阻抗未完成时暂存
  double? _pendingBodyFat;                 // 捕获时算好的体脂率
  int? _pendingImpedance;                  // 捕获时的阻抗值

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // M27 生命周期监听
    // M14：监听输入变化标记 dirty（防初始赋值误标）
    _weightCtrl.addListener(_markDirty);
    _load();
  }

  /// M14：标记用户已修改输入（PopScope 弹放弃确认用）
  void _markDirty() {
    if (_loading) return;
    // 已 dirty 且无错误时不重复 setState（保留原优化）
    if (_dirty && _weightError == null) return;
    setState(() {
      _dirty = true;
      // 用户重新编辑体重时清掉旧错误提示
      _weightError = null;
    });
  }

  /// 公开刷新方法：切换到该页时由父容器调用
  void refresh() => _load();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanSub?.cancel();
    _bleScanner?.dispose();
    _weightCtrl.removeListener(_markDirty);
    _weightCtrl.dispose();
    super.dispose();
  }

  /// M27：App 生命周期切换时管理 BLE 扫描
  /// paused → stopScan（国产 ROM 后台扫描必被冻结）
  /// resumed → startScan（如已开启蓝牙同步）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _stopBleScan();
    } else if (state == AppLifecycleState.resumed && _bleEnabled) {
      _startBleScan();
    }
  }

  /// M27：用户点击"开启蓝牙同步"横幅 → 请求权限 + 启动扫描
  Future<void> _enableBleSync() async {
    // 1. 批量请求权限（国产 ROM 需要 location）
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    // 2. 永久拒绝 → 引导去设置
    final anyPermanentlyDenied =
        statuses.values.any((s) => s.isPermanentlyDenied);
    if (anyPermanentlyDenied) {
      if (!mounted) return;
      setState(() => _bleState = _BleState.error);
      showAppToast(context, '蓝牙权限被永久拒绝，请在设置中开启');
      await openAppSettings();
      return;
    }

    // 3. 普通拒绝 → 显示错误
    final allGranted = statuses.values.every((s) => s.isGranted);
    if (!allGranted) {
      if (!mounted) return;
      setState(() => _bleState = _BleState.error);
      showAppToast(context, '蓝牙权限不足，无法自动同步');
      return;
    }

    // 4. 权限 OK → 标记已开启
    if (!mounted) return;
    setState(() => _bleEnabled = true);

    // M27 v2：系统定位开关检查（华为系 HarmonyOS/EMUI 强依赖）
    final locationServiceStatus = await Permission.location.serviceStatus;
    if (locationServiceStatus != ServiceStatus.enabled) {
      if (!mounted) return;
      showAppToast(context, '请先开启系统定位开关（蓝牙扫描需要）');
      await openAppSettings();
      return;
    }

    await _startBleScan();
  }

  /// M27：启动 BLE 扫描
  Future<void> _startBleScan() async {
    // 扫描冷却：5分钟/3次（MIUI 熔断）+ 30秒/4次（AOSP 节流）
    final now = DateTime.now();
    _scanTimestamps.removeWhere((t) => now.difference(t).inMinutes >= 5);
    if (_scanTimestamps.length >= 3) {
      if (!mounted) return;
      showAppToast(context, '5分钟内扫描次数过多，请稍后再试');
      return;
    }
    // M27 v2：30秒短窗（AOSP 5次/30秒 节流保护）
    final recentCount =
        _scanTimestamps.where((t) => now.difference(t).inSeconds < 30).length;
    if (recentCount >= 4) {
      if (!mounted) return;
      showAppToast(context, '扫描过于频繁，请稍后再试');
      return;
    }
    _scanTimestamps.add(now);

    // 检查蓝牙适配器状态
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      // 蓝牙关闭 → Android 主动弹系统对话框（iOS 无此 API）
      if (Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {
          if (!mounted) return;
          setState(() => _bleState = _BleState.error);
          return;
        }
      } else {
        if (!mounted) return;
        setState(() => _bleState = _BleState.error);
        showAppToast(context, '请开启蓝牙');
        return;
      }
      // 等待适配器开启（最多 30 秒）
      try {
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .timeout(const Duration(seconds: 30))
            .first;
      } catch (_) {
        if (!mounted) return;
        setState(() => _bleState = _BleState.error);
        showAppToast(context, '蓝牙未开启，无法扫描');
        return;
      }
    }

    // 懒初始化扫描器
    _bleScanner ??= MiScaleScanner();

    // 订阅测量值流（取消旧订阅防重复）
    await _scanSub?.cancel();
    _scanSub = _bleScanner!.measurementStream.listen(_onMeasurement);

    if (!mounted) return;
    setState(() => _bleState = _BleState.scanning);

    try {
      await _bleScanner!.startScan(
        timeout: const Duration(seconds: 15),
      );
      // M27 v2 修复：startScan 在扫描开始时即返回，需显式等待扫描结束
      // 否则"未找到"toast 会立即误弹（扫描才刚开始）
      await FlutterBluePlus.isScanning.where((v) => v == false).first;
    } catch (e) {
      debugPrint('BLE 扫描启动失败: $e');
      if (mounted) {
        setState(() => _bleState = _BleState.error);
      }
    }

    // 扫描真正结束后如未捕获，检查 _pendingStabilized 兜底
    if (mounted && _bleState == _BleState.scanning) {
      if (_pendingStabilized != null) {
        // v2 超时未拿到 impedance，用 stabilized 帧兜底（只有 weight）
        _handleCapture(_pendingStabilized!);
        _pendingStabilized = null;
      } else {
        setState(() => _bleState = _BleState.idle);
        if (!mounted) return;
        showAppToast(context, '未找到体重秤，请确认秤已开机');
      }
    }
  }

  /// M27：停止 BLE 扫描
  ///
  /// 设 _bleState=idle，避免 startScan await 返回后 _bleState==scanning
  /// 误显示"未找到体重秤"toast（用户主动停止 / app 进后台 / 生命周期 paused）。
  /// _onMeasurement 捕获后不调此方法（避免覆盖 captured），直接调 _bleScanner.stopScan()。
  Future<void> _stopBleScan() async {
    if (mounted) setState(() => _bleState = _BleState.idle);
    await _bleScanner?.stopScan();
  }

  /// M27：收到有效测量值 → 预填输入框
  void _onMeasurement(MiScaleMeasurement m) {
    if (!mounted) return;

    // v1 协议（XMTZC04HM）：无阻抗，stabilized 即完整测量，直接捕获
    // v2 协议（XMTZC05HM）：优先等 measurementComplete（拿到 impedance），
    //   stabilized 但阻抗未完成时暂存，超时（15s）未拿到 impedance 则用此帧兜底
    if (m.protocolVersion == 1) {
      if (m.isStabilized) _handleCapture(m);
      return;
    }

    // v2：等 impedance 就绪
    final isV2WithImpedance = m.measurementComplete || m.impedance != null;
    if (!isV2WithImpedance && m.isStabilized) {
      // v2 稳定但阻抗未完成：暂存，继续扫描等 impedance
      // 超时（15s）未拿到 impedance 则用此帧兜底
      _pendingStabilized = m;
      return;
    }

    _handleCapture(m);
  }

  /// M27 v2：处理捕获（计算体脂率 + 预填 + 停止扫描）
  void _handleCapture(MiScaleMeasurement m) {
    // 计算体脂率（需 profile 的性别/年龄/身高，异步获取）
    _computeBodyFatAndCapture(m);
  }

  Future<void> _computeBodyFatAndCapture(MiScaleMeasurement m) async {
    double? bodyFat;
    if (m.impedance != null) {
      try {
        final profileRepo =
            await ref.read(recognize.profileRepoProvider.future);
        final profile = await profileRepo.get();
        final isMale = profile.gender == 'male';
        bodyFat = BodyFatCalculator.calcBodyFat(
          isMale: isMale,
          age: profile.age,
          heightCm: profile.heightCm,
          weightKg: m.weightKg,
          impedance: m.impedance!.toDouble(),
        );
      } catch (e) {
        debugPrint('体脂率计算失败: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _weightCtrl.text = m.weightKg.toStringAsFixed(1);
      _weightError = null;
      _bleState = _BleState.captured;
      _pendingBodyFat = bodyFat;
      _pendingImpedance = m.impedance;
      _dirty = true;
    });
    // 停止扫描（已捕获，省电）
    _bleScanner?.stopScan();

    // toast（impedance 无效只显示体重）
    final msg = bodyFat != null
        ? '已捕获 ${m.weightKg.toStringAsFixed(1)} kg，体脂 ${bodyFat.toStringAsFixed(1)}%'
        : '已捕获 ${m.weightKg.toStringAsFixed(1)} kg，请确认';
    showAppToast(context, msg);
  }

  Future<void> _load() async {
    try {
      final repo = await ref.read(recognize.weightLogRepoProvider.future);
      _logs = await repo.getRecent(days: 30);
      // 加载 30 天 meal_log 并按日聚合热量（双轴图用）
      final mealRepo = await ref.read(recognize.mealLogRepoProvider.future);
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
            // M27 蓝牙同步横幅 / 状态指示器
            if (_bleState == _BleState.idle && !_bleEnabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: const Text('开启蓝牙同步'),
                    subtitle: const Text('自动捕获小米体重秤数据'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _enableBleSync,
                  ),
                ),
              )
            else if (_bleState == _BleState.scanning)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: const Text('搜索体重秤…'),
                  subtitle: const Text('请上秤站立保持静止'),
                  trailing: TextButton(
                    onPressed: _stopBleScan,
                    child: const Text('停止'),
                  ),
                ),
              )
            else if (_bleState == _BleState.captured)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.bluetooth_connected,
                      color: Colors.green),
                  title: const Text('已捕获体重'),
                  trailing: TextButton(
                    onPressed: _startBleScan,
                    child: const Text('重新扫描'),
                  ),
                ),
              )
            else if (_bleState == _BleState.error)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(Icons.error_outline,
                      color: Theme.of(context).colorScheme.error),
                  title: const Text('蓝牙同步不可用'),
                  trailing: TextButton(
                    onPressed: _enableBleSync,
                    child: const Text('重试'),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
                    ],
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: '今日体重 (kg)',
                      errorText: _weightError,
                    ),
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
                    // M27 v2：有体脂率加到 tooltip
                    final bodyFatText = log.bodyFatPct != null
                        ? '\n体脂 ${log.bodyFatPct!.toStringAsFixed(1)}%'
                        : '';
                    // barIndex 0 = 热量，1 = 体重
                    final valueText = spot.barIndex == 0
                        ? '${_dailyCalories[log.date]?.round() ?? 0} kcal'
                        : '${log.weightKg.toStringAsFixed(1)} kg$bodyFatText';
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
      setState(() => _weightError = '体重需大于 0');
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = await ref.read(recognize.weightLogRepoProvider.future);
      final today = todayYmd();
      // 1. 写 weight_log（M27 v2：含 impedance + bodyFatPct）
      await repo.insert(
        date: today,
        weightKg: weight,
        impedance: _pendingImpedance?.toDouble(),
        bodyFatPercent: _pendingBodyFat,
      );

      // 2. 同步 profile（M27 v2：weightKg + bodyFatPct + formula 联动）
      // 让 dashboard 宏量目标（proteinGPerKg * weightKg）随最新体重变化。
      // formula 切换时 BMR 公式变了，旧 dailyCalorieTarget 失效，需重算
      // （参照 profile_page._save 的重算逻辑）；formula 未变时不重算 target
      // （日常体重波动通过 TDEE 校准 adjustmentKcal 微调）
      final profileRepo = await ref.read(recognize.profileRepoProvider.future);
      final oldProfile = await profileRepo.get();
      final oldFormula = oldProfile.formula;
      final hasBodyFat = _pendingBodyFat != null && _pendingBodyFat! > 0;
      final newFormula = hasBodyFat ? 'katch' : 'mifflin';
      final formulaChanged = oldFormula != newFormula;

      int? newDailyCalorieTarget;
      if (formulaChanged) {
        // formula 切换：BMR 公式变了（mifflin↔katch），重算 dailyCalorieTarget
        final genderEnum =
            oldProfile.gender == 'male' ? Gender.male : Gender.female;
        final goalEnum = oldProfile.goal == 'cut'
            ? Goal.cut
            : oldProfile.goal == 'bulk'
                ? Goal.bulk
                : Goal.maintain;
        final bmr = hasBodyFat
            ? NutritionCalculator.bmrKatch(
                weightKg: weight, bodyFatPct: _pendingBodyFat!)
            : NutritionCalculator.bmrMifflin(
                weightKg: weight,
                heightCm: oldProfile.heightCm,
                age: oldProfile.age,
                gender: genderEnum,
              );
        final tdee = NutritionCalculator.tdee(
            bmr: bmr, activityLevel: oldProfile.activityLevel);
        newDailyCalorieTarget = NutritionCalculator.dailyCalorieTarget(
          tdee: tdee,
          goal: goalEnum,
          tdeeAdjustmentKcal: 0, // formula 切换已重置
          goalRateKgPerWeek: oldProfile.goalRateKgPerWeek,
          gender: genderEnum,
          specialCondition: oldProfile.specialCondition,
        );
      }

      await profileRepo.update(
        weightKg: weight,
        bodyFatPct: _pendingBodyFat,
        formula: newFormula,
        // formula 切换时重置 tdeeAdjustmentKcal（防跨公式污染）+ 重算 dailyCalorieTarget
        tdeeAdjustmentKcal: formulaChanged ? 0 : null,
        dailyCalorieTarget: newDailyCalorieTarget,
      );
      // bodyFatPct 显式置空（用户清空体脂率时，update 的 null=不更新无法置空）
      if (_pendingBodyFat == null) {
        await profileRepo.clearBodyFatPct();
      }

      // 触发 TDEE 自适应校准（Sprint 3 T22）
      try {
        final config = await ref.read(appConfigProvider.future);
        if (config.tdeeAutoCalib) {
          // TdeeCalibrator 非 Repository，仍需 db 实例（db 走 databaseProvider 注入）
          final db = await ref.read(recognize.databaseProvider.future);
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
      // M27 v2：清理捕获暂存
      _pendingBodyFat = null;
      _pendingImpedance = null;
      _pendingStabilized = null;
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
      debugPrint('记录失败: $e');
      if (mounted) {
        showAppToast(context, '记录失败，请稍后重试。');
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
        // M27 v2：有体脂率加到 title
        title: Text(log.bodyFatPct != null
            ? '${log.weightKg.toStringAsFixed(1)} kg · 体脂 ${log.bodyFatPct!.toStringAsFixed(1)}%'
            : '${log.weightKg.toStringAsFixed(1)} kg',
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
        builder: (ctx) {
          // dialog 内部局部创建 formKey，避免 state 持久化问题
          final formKey = GlobalKey<FormState>();
          return StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              title: const Text('编辑体重'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: weightCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))
                      ],
                      decoration: const InputDecoration(labelText: '体重 (kg)'),
                      validator: (value) {
                        final v = double.tryParse(value?.trim() ?? '');
                        if (v == null || v <= 0 || v > 500) {
                          return '请输入 0-500 之间的数字';
                        }
                        return null;
                      },
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
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消')),
                FilledButton(
                  onPressed: () {
                    // 校验失败不关闭 dialog，TextFormField 显示 errorText
                    if (!(formKey.currentState?.validate() ?? false)) return;
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
          );
        },
      );
      // dialog 内已校验，调用方信任返回值；仅处理用户点取消（result == null）
      if (result == null) return;
      if (!mounted) return;
      // 仅在值或日期变化时写库（避免无意义 IO）
      if (result.weightKg == log.weightKg && result.date == log.date) return;
      setState(() => _busy = true);
      try {
        final repo = await ref.read(recognize.weightLogRepoProvider.future);
        await repo.update(
          id: log.id,
          weightKg: result.weightKg,
          date: result.date,
        );
        // 若改的是最新一条体重，同步 profile.weightKg（与 _save 一致逻辑）
        final isLatest = _logs.isEmpty || log.id == _logs.last.id;
        if (isLatest) {
          final profileRepo =
              await ref.read(recognize.profileRepoProvider.future);
          await profileRepo.update(weightKg: result.weightKg);
        }
        await _load();
        RefreshBus.instance.notify();
        if (mounted) {
          showAppToast(context, '已更新体重记录');
        }
      } catch (e) {
        debugPrint('保存失败: $e');
        if (mounted) {
          showAppToast(context, '保存失败，请稍后重试。');
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
      final repo = await ref.read(recognize.weightLogRepoProvider.future);
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
      debugPrint('删除失败: $e');
      if (mounted) {
        showAppToast(context, '删除失败，请稍后重试。');
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

/// M27 蓝牙扫描状态
enum _BleState {
  idle, // 未扫描（未授权 / 蓝牙关闭 / 首次进入未点击横幅）
  scanning, // 扫描中
  captured, // 已捕获稳定值
  error, // 错误（权限拒绝 / 蓝牙关闭）
}
