import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  bool _loading = true;
  bool _busy = false; // 防重入：保存期间禁用按钮，避免双击重复写库

  @override
  void initState() {
    super.initState();
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
    } catch (e) {
      // DB 异常时不卡死 loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('档案加载失败：$e')),
        );
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
    return Scaffold(
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
                      onSelected: (v) =>
                          setState(() => _gender = v ?? 'male'),
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
                  onSelected: (v) =>
                      setState(() => _activity = v ?? 1.375),
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(value: 1.2, label: '久坐'),
                    DropdownMenuEntry(value: 1.375, label: '轻度活动'),
                    DropdownMenuEntry(value: 1.55, label: '中度活动'),
                    DropdownMenuEntry(value: 1.725, label: '高强度活动'),
                    DropdownMenuEntry(value: 1.9, label: '极度活动'),
                  ],
                ),
              ),
            ),
            SectionTitle('目标'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    DropdownMenu<String>(
                      initialSelection: _goal,
                      expandedInsets: EdgeInsets.zero,
                      label: const Text('目标'),
                      onSelected: (v) =>
                          setState(() => _goal = v ?? 'maintain'),
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
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存并重算目标'),
            ),
          ],
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
      );
      // 宏量目标密度（g/kg）：硬编码同 NutritionCalculator.macros 内部值
      // 减脂/维持时 carbGPerKg=null（碳水填剩余，dashboard 读取时按剩余热量反算）
      final proteinGPerKg =
          goalEnum == Goal.cut ? 2.4 : goalEnum == Goal.bulk ? 1.8 : 1.4;
      final fatGPerKg =
          goalEnum == Goal.cut ? 0.9 : goalEnum == Goal.bulk ? 1.0 : 0.9;
      final double? carbGPerKg = goalEnum == Goal.bulk ? 5.0 : null;

      // 风险警告：goalRate 超阈值时弹窗，用户确认后继续保存
      if (goalRate > 0) {
        final warning = NutritionCalculator.validateGoalRate(
          goalRateKgPerWeek: goalRate,
          weightKg: weight,
          goal: goalEnum,
        );
        if (warning != null) {
          if (!mounted) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('⚠ 风险警告'),
              content: Text(warning),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('重新填写'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('我知道风险，继续'),
                ),
              ],
            ),
          );
          if (confirmed != true) return; // 用户取消
        }
      }

      await repo.update(
        heightCm: height,
        weightKg: weight,
        bodyFatPct: bodyFat,
        age: age,
        gender: _gender, // String 写库
        activityLevel: _activity,
        goal: _goal, // String 写库
        goalRateKgPerWeek: goalRate, // 新增：保存目标速率
        formula: 'mifflin',
        dailyCalorieTarget: target, // 联动重算后的目标热量
        proteinGPerKg: proteinGPerKg,
        fatGPerKg: fatGPerKg,
        carbGPerKg: carbGPerKg,
        // 不传 tdeeAdjustmentKcal：保留 DB 存储值，不被 goalRate 重算覆盖
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存，每日目标 $target kcal')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
