import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/refresh_bus.dart';
import '../../core/widgets/m3_widgets.dart';
import '../../data/repositories/profile_repository.dart';
import 'nutrition_calculator.dart';
import '../recognize/providers.dart' as recognize;

/// 个人档案录入页
/// 录入身高/体重/年龄/性别/活动量/目标/体脂率（可选）
/// 保存时调 NutritionCalculator 重算 dailyCalorieTarget + 宏量目标，写 profile 表
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});
  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _bodyFatCtrl = TextEditingController();
  final _goalRateCtrl = TextEditingController(); // 目标速率 kg/周（减脂/增肌时显示）
  String _gender = 'male';
  double _activity = 1.375;
  String _goal = 'maintain';
  // 特殊人群适配（v2 新增，默认 'none' 向后兼容）
  String _specialCondition = 'none';
  String _dietPreference = 'none';
  String _healthCondition = 'none';
  bool _loading = true;
  bool _busy = false; // 防重入：保存期间禁用按钮，避免双击重复写库
  bool _dirty = false; // 用户是否改过任意字段（PopScope 未保存确认用）

  /// 标记 dirty。加载期间（_loading=true）跳过，避免初始赋值触发误标记。
  void _markDirty() {
    if (_loading || _dirty) return;
    setState(() => _dirty = true);
  }

  @override
  void initState() {
    super.initState();
    // controller 监听在 _loadProfile 之前注册；_markDirty 用 _loading 守门
    // 确保初始赋值不触发 dirty（仅用户后续编辑才标记）
    _heightCtrl.addListener(_markDirty);
    _weightCtrl.addListener(_markDirty);
    _ageCtrl.addListener(_markDirty);
    _bodyFatCtrl.addListener(_markDirty);
    _goalRateCtrl.addListener(_markDirty);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final db = await ref.read(recognize.databaseProvider.future);
      final repo = ProfileRepository(db);
      final p = await repo.get();
      _heightCtrl.text = p.heightCm.toString();
      _weightCtrl.text = p.weightKg.toString();
      _ageCtrl.text = p.age.toString();
      _bodyFatCtrl.text = p.bodyFatPct?.toString() ?? '';
      _goalRateCtrl.text =
          p.goalRateKgPerWeek > 0 ? p.goalRateKgPerWeek.toString() : '';
      _gender = p.gender;
      _activity = p.activityLevel;
      _goal = p.goal;
      // 特殊人群字段：null（旧数据升级）视为 'none'
      _specialCondition = p.specialCondition ?? 'none';
      _dietPreference = p.dietPreference ?? 'none';
      _healthCondition = p.healthCondition ?? 'none';
    } catch (e) {
      // DB 异常时不卡死 loading
      if (mounted) {
        showAppToast(context, '档案加载失败：$e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _ageCtrl.dispose();
    _bodyFatCtrl.dispose();
    _goalRateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmDiscardChanges(context) && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
      appBar: AppBar(title: const Text('个人档案')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionTitle('基本信息'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _heightCtrl,
                      decoration: const InputDecoration(labelText: '身高 (cm)'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return '必填';
                        if (double.tryParse(v) == null) return '请输入有效数字';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _weightCtrl,
                      decoration: const InputDecoration(labelText: '体重 (kg)'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return '必填';
                        if (double.tryParse(v) == null) return '请输入有效数字';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _ageCtrl,
                      decoration: const InputDecoration(labelText: '年龄'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return '必填';
                        if (int.tryParse(v) == null) return '请输入有效整数';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownMenu<String>(
                      initialSelection: _gender,
                      expandedInsets: EdgeInsets.zero,
                      label: const Text('性别'),
                      onSelected: (v) {
                        setState(() => _gender = v ?? 'male');
                        _markDirty();
                      },
                      dropdownMenuEntries: const [
                        DropdownMenuEntry(value: 'male', label: '男'),
                        DropdownMenuEntry(value: 'female', label: '女'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bodyFatCtrl,
                      decoration: const InputDecoration(
                          labelText: '体脂率 % (可选，填了可用 Katch 公式)'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return null; // 可选字段
                        if (double.tryParse(v) == null) return '请输入有效数字';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            SectionTitle('活动量'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownMenu<double>(
                  initialSelection: _activity,
                  expandedInsets: EdgeInsets.zero,
                  label: const Text('活动量'),
                  onSelected: (v) {
                    setState(() => _activity = v ?? 1.375);
                    _markDirty();
                  },
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(
                        value: 1.2,
                        label: '久坐（桌案工作，<5000 步/天）'),
                    DropdownMenuEntry(
                        value: 1.375,
                        label: '轻度（每周 1-3 次锻炼或 7000+ 步）'),
                    DropdownMenuEntry(
                        value: 1.55,
                        label: '中度（每周 4-5 次锻炼或体力工作）'),
                    DropdownMenuEntry(
                        value: 1.725,
                        label: '高强度（每日训练或重体力工作）'),
                    DropdownMenuEntry(
                        value: 1.9,
                        label: '极度（每日双训或职业运动员）'),
                  ],
                ),
              ),
            ),
            // 活动量说明（避免用户高估，参考 CalEye：多数办公族+健身习惯是"轻度"而非"中度"）
            // padding 16 对齐 Card 边缘；labelSmall 替代硬编码 fontSize: 11，跟随系统字号缩放
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '提示：多数有健身习惯的办公族属"轻度"而非"中度"，高估会多算 200-400 kcal/天',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            SectionTitle('目标'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    DropdownMenu<String>(
                      key: const Key('goal_dropdown'),
                      initialSelection: _goal,
                      expandedInsets: EdgeInsets.zero,
                      label: const Text('目标'),
                      onSelected: (v) {
                        setState(() => _goal = v ?? 'maintain');
                        _markDirty();
                      },
                      dropdownMenuEntries: const [
                        DropdownMenuEntry(value: 'cut', label: '减脂'),
                        DropdownMenuEntry(value: 'bulk', label: '增肌'),
                        DropdownMenuEntry(value: 'maintain', label: '维持'),
                      ],
                    ),
                    if (_goal == 'cut' || _goal == 'bulk') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _goalRateCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '目标速率（kg/周）',
                          hintText: '减脂建议 0.3-0.7，增肌建议 0.18-0.45',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 特殊状况段：适配不同人群（孕期/哺乳/老年/青少年/糖尿病/肾病/素食等）
            // 影响 TDEE 加成 + 宏量分配 + 风险提示，null/'none' 时不调整（向后兼容）
            SectionTitle('特殊状况（可选）'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    DropdownMenu<String>(
                      initialSelection: _specialCondition,
                      expandedInsets: EdgeInsets.zero,
                      label: const Text('生理状态'),
                      onSelected: (v) {
                        setState(() => _specialCondition = v ?? 'none');
                        _markDirty();
                      },
                      dropdownMenuEntries: const [
                        DropdownMenuEntry(value: 'none', label: '无'),
                        DropdownMenuEntry(
                            value: 'pregnancy', label: '孕期（+340 kcal/天）'),
                        DropdownMenuEntry(
                            value: 'lactation', label: '哺乳期（+500 kcal/天）'),
                        DropdownMenuEntry(
                            value: 'elderly', label: '老年（≥65，蛋白 1.2g/kg）'),
                        DropdownMenuEntry(
                            value: 'teenager', label: '青少年（生长需求）'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownMenu<String>(
                      initialSelection: _healthCondition,
                      expandedInsets: EdgeInsets.zero,
                      label: const Text('健康状况'),
                      onSelected: (v) {
                        setState(() => _healthCondition = v ?? 'none');
                        _markDirty();
                      },
                      dropdownMenuEntries: const [
                        DropdownMenuEntry(value: 'none', label: '无'),
                        DropdownMenuEntry(
                            value: 'diabetes',
                            label: '糖尿病（碳水 ≤45%）'),
                        DropdownMenuEntry(
                            value: 'hypertension', label: '高血压（限钠提示）'),
                        DropdownMenuEntry(
                            value: 'kidney_issues',
                            label: '肾病（蛋白 ≤0.8g/kg）'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownMenu<String>(
                      initialSelection: _dietPreference,
                      expandedInsets: EdgeInsets.zero,
                      label: const Text('饮食偏好'),
                      onSelected: (v) {
                        setState(() => _dietPreference = v ?? 'none');
                        _markDirty();
                      },
                      dropdownMenuEntries: const [
                        DropdownMenuEntry(value: 'none', label: '无'),
                        DropdownMenuEntry(value: 'vegetarian', label: '蛋奶素'),
                        DropdownMenuEntry(value: 'vegan', label: '纯素'),
                        DropdownMenuEntry(
                            value: 'lactose_intolerant', label: '乳糖不耐'),
                        DropdownMenuEntry(value: 'gluten_free', label: '无麸质'),
                      ],
                    ),
                    // 健康风险提示（选了特殊状况时显示）
                    if (_specialCondition != 'none' ||
                        _healthCondition != 'none' ||
                        _dietPreference != 'none') ...[
                      const SizedBox(height: 12),
                      _buildSpecialConditionHint(),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
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
                  : const Text('保存并重算目标'),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Future<void> _save() async {
    if (_busy) return; // 防重入
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final db = await ref.read(recognize.databaseProvider.future);
      final repo = ProfileRepository(db);

      // 读取现有 profile，保留 tdeeAdjustmentKcal（校准累积值，不应被 goalRate 重算覆盖）
      final existing = await repo.get();

      final height = double.parse(_heightCtrl.text);
      final weight = double.parse(_weightCtrl.text);
      final age = int.parse(_ageCtrl.text);
      final bodyFat =
          _bodyFatCtrl.text.isEmpty ? null : double.parse(_bodyFatCtrl.text);
      final goalRate = double.tryParse(_goalRateCtrl.text) ?? 0;
      // 枚举转换：String → Gender/Goal
      final genderEnum =
          _gender == 'male' ? Gender.male : Gender.female;
      final goalEnum = _goal == 'cut'
          ? Goal.cut
          : _goal == 'bulk'
              ? Goal.bulk
              : Goal.maintain;

      // 重算目标（MVP：始终用 mifflin，有体脂率时也用 mifflin 除非用户显式选 katch——Sprint 2 简化）
      final bmr = NutritionCalculator.bmrMifflin(
        weightKg: weight,
        heightCm: height,
        age: age,
        gender: genderEnum,
      );
      final tdee = NutritionCalculator.tdee(bmr: bmr, activityLevel: _activity);
      final target = NutritionCalculator.dailyCalorieTarget(
        tdee: tdee,
        goal: goalEnum,
        tdeeAdjustmentKcal: existing.tdeeAdjustmentKcal, // Sprint 7：传真实校准累积值，不再硬编码 0
        goalRateKgPerWeek: goalRate, // 联动重算：goalRate 影响每日目标热量
        gender: genderEnum,
        specialCondition: _specialCondition, // v2：特殊人群能量加成（孕期+340/哺乳+500）
      );
      // 宏量目标密度（g/kg）：用 NutritionCalculator.macros 统一计算
      // （含特殊人群调整：老年/青少年/肾病/糖尿病等覆盖 goal 默认值）
      final macros = NutritionCalculator.macros(
        dailyCalorieTarget: target,
        weightKg: weight,
        goal: goalEnum,
        specialCondition: _specialCondition,
        healthCondition: _healthCondition,
      );
      final proteinGPerKg = macros.proteinGPerKg;
      final fatGPerKg = macros.fatGPerKg;
      // 减脂/维持时 carbGPerKg=null（碳水填剩余，dashboard 读取时按剩余热量反算）
      // 增肌时仍传 5.0（macros 内部已处理，此处取 goalEnum 判断是否主动设碳水）
      final double? carbGPerKg = goalEnum == Goal.bulk ? 5.0 : null;

      // 风险警告：goalRate 超阈值 或 孕期/哺乳期选了减脂 → 弹窗
      // 孕期/哺乳期不应减脂（影响胎儿/婴儿发育），选 cut 时强制警告
      final warnings = <String>[];
      if (goalRate > 0) {
        final w = NutritionCalculator.validateGoalRate(
          goalRateKgPerWeek: goalRate,
          weightKg: weight,
          goal: goalEnum,
        );
        if (w != null) warnings.add(w);
      }
      if ((_specialCondition == 'pregnancy' || _specialCondition == 'lactation') &&
          goalEnum == Goal.cut) {
        warnings.add('孕期/哺乳期不建议减脂，可能影响胎儿/婴儿发育。'
            '建议目标改为"维持"，已自动加能量（孕期 +340 / 哺乳 +500 kcal/天）。');
      }
      if (_healthCondition == 'kidney_issues' && goalEnum == Goal.cut) {
        warnings.add('肾病人群减脂期蛋白已自动限制到 0.8g/kg（KDOQI 推荐），'
            '可能影响饱腹感与肌肉保留，请遵医嘱。');
      }
      if (warnings.isNotEmpty) {
        if (!mounted) return;
        final confirmed = await confirmAction(
          context,
          title: '风险警告',
          content: warnings.join('\n\n'),
          cancelLabel: '重新填写',
          confirmLabel: '我知道风险，继续',
          icon: Icons.warning_amber_rounded,
        );
        if (confirmed != true) return; // 用户取消
      }

      await repo.update(
        heightCm: height,
        weightKg: weight,
        bodyFatPct: bodyFat,
        age: age,
        gender: _gender, // String 写库
        activityLevel: _activity,
        goal: _goal, // String 写库
        goalRateKgPerWeek: goalRate,
        formula: 'mifflin',
        dailyCalorieTarget: target,
        proteinGPerKg: proteinGPerKg,
        fatGPerKg: fatGPerKg,
        carbGPerKg: carbGPerKg,
        specialCondition: _specialCondition, // v2：写特殊人群字段
        dietPreference: _dietPreference,
        healthCondition: _healthCondition,
        // 不传 tdeeAdjustmentKcal：保留 DB 存储值，不被 goalRate 重算覆盖
      );

      if (mounted) {
        // SnackBar 显示目标 + 特殊人群调整说明（若有）
        final specialAdj = NutritionCalculator.specialConditionCalorieAdjustment(
            _specialCondition == 'none' ? null : _specialCondition);
        final suffix = specialAdj > 0
            ? '（含特殊加成 +$specialAdj kcal）'
            : '';
        showAppToast(context, '已保存，每日目标 $target kcal$suffix');
        _dirty = false; // 清 dirty 让 PopScope 放行 programmatic pop
        Navigator.of(context).pop();
        // 通知 dashboard/records/insight 等监听 RefreshBus 的页面刷新
        RefreshBus.instance.notify();
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '保存失败：$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 特殊状况风险提示卡片：根据当前选择显示对应的医学建议
  /// 内容来源：IOM（孕期/哺乳）、ISSN（老年）、ADA（糖尿病）、KDOQI（肾病）
  Widget _buildSpecialConditionHint() {
    final cs = Theme.of(context).colorScheme;
    final hints = <String>[];
    switch (_specialCondition) {
      case 'pregnancy':
        hints.add('孕期每日能量 +340 kcal（IOM，2nd-3rd trimester），'
            '叶酸/铁/钙需求增加，不建议减脂。');
        break;
      case 'lactation':
        hints.add('哺乳期每日能量 +500 kcal（IOM），蛋白质需求升至 1.1g/kg，'
            '注意补钙与水分。');
        break;
      case 'elderly':
        hints.add('老年人蛋白提高到 1.2g/kg 防肌少症（ISSN），'
            '注意维生素 D/B12 与钙补充。');
        break;
      case 'teenager':
        hints.add('青少年生长需求高，不应过度限制热量，'
            '蛋白 1.4g/kg + 充足碳水，避免节食。');
        break;
    }
    switch (_healthCondition) {
      case 'diabetes':
        hints.add('糖尿病碳水占比 ≤45%（ADA），选低 GI 食物，'
            '避免精制糖，规律监测血糖。');
        break;
      case 'hypertension':
        hints.add('高血压限钠 < 2300mg/天（约 6g 盐），'
            '增加钾摄入（蔬果），DASH 饮食模式。');
        break;
      case 'kidney_issues':
        hints.add('肾病蛋白 ≤0.8g/kg（KDOQI 3-5 期），'
            '限磷限钾，避免高蛋白饮食加重肾负担。');
        break;
    }
    switch (_dietPreference) {
      case 'vegan':
        hints.add('纯素需补 B12、铁、锌、Omega-3（亚麻籽/藻油），'
            '蛋白组合豆类+谷物获完整氨基酸。');
        break;
      case 'vegetarian':
        hints.add('蛋奶素注意铁吸收（搭配维 C），蛋白可通过蛋奶补足。');
        break;
      case 'lactose_intolerant':
        hints.add('乳糖不耐选无乳糖奶或植物奶，注意钙与维 D 补充。');
        break;
      case 'gluten_free':
        hints.add('无麸质饮食注意 B 族维生素与膳食纤维摄入（糙米/藜麦替代）。');
        break;
    }
    if (hints.isEmpty) return const SizedBox.shrink();
    // 用 Card(color: tertiaryContainer) 替代手写 Container，与 settings 分组卡片同构
    final textTheme = Theme.of(context).textTheme;
    return Card(
      color: cs.tertiaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline,
                size: 18, color: cs.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hints.join('\n\n'),
                style: textTheme.bodySmall
                    ?.copyWith(color: cs.onTertiaryContainer, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
