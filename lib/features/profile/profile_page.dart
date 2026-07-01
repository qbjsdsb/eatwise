import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  String _gender = 'male';
  double _activity = 1.375;
  String _goal = 'maintain';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = ProfileRepository(db);
    final p = await repo.get();
    _heightCtrl.text = p.heightCm.toString();
    _weightCtrl.text = p.weightKg.toString();
    _ageCtrl.text = p.age.toString();
    _bodyFatCtrl.text = p.bodyFatPct?.toString() ?? '';
    _gender = p.gender;
    _activity = p.activityLevel;
    _goal = p.goal;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _ageCtrl.dispose();
    _bodyFatCtrl.dispose();
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
            TextFormField(
              controller: _heightCtrl,
              decoration: const InputDecoration(labelText: '身高 (cm)'),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || v.isEmpty ? '必填' : null,
            ),
            TextFormField(
              controller: _weightCtrl,
              decoration: const InputDecoration(labelText: '体重 (kg)'),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || v.isEmpty ? '必填' : null,
            ),
            TextFormField(
              controller: _ageCtrl,
              decoration: const InputDecoration(labelText: '年龄'),
              keyboardType: TextInputType.number,
              validator: (v) => v == null || v.isEmpty ? '必填' : null,
            ),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(labelText: '性别'),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('男')),
                DropdownMenuItem(value: 'female', child: Text('女')),
              ],
              onChanged: (v) => setState(() => _gender = v!),
            ),
            TextFormField(
              controller: _bodyFatCtrl,
              decoration:
                  const InputDecoration(labelText: '体脂率 % (可选，填了可用 Katch 公式)'),
              keyboardType: TextInputType.number,
            ),
            DropdownButtonFormField<double>(
              initialValue: _activity,
              decoration: const InputDecoration(labelText: '活动量'),
              items: const [
                DropdownMenuItem(value: 1.2, child: Text('久坐')),
                DropdownMenuItem(value: 1.375, child: Text('轻度活动')),
                DropdownMenuItem(value: 1.55, child: Text('中度活动')),
                DropdownMenuItem(value: 1.725, child: Text('高强度活动')),
                DropdownMenuItem(value: 1.9, child: Text('极度活动')),
              ],
              onChanged: (v) => setState(() => _activity = v!),
            ),
            DropdownButtonFormField<String>(
              initialValue: _goal,
              decoration: const InputDecoration(labelText: '目标'),
              items: const [
                DropdownMenuItem(value: 'cut', child: Text('减脂')),
                DropdownMenuItem(value: 'bulk', child: Text('增肌')),
                DropdownMenuItem(value: 'maintain', child: Text('维持')),
              ],
              onChanged: (v) => setState(() => _goal = v!),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Text('保存并重算目标'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final db = await ref.read(recognize.databaseProvider.future);
    final repo = ProfileRepository(db);

    final height = double.parse(_heightCtrl.text);
    final weight = double.parse(_weightCtrl.text);
    final age = int.parse(_ageCtrl.text);
    final bodyFat =
        _bodyFatCtrl.text.isEmpty ? null : double.parse(_bodyFatCtrl.text);
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
      tdeeAdjustmentKcal: 0,
      gender: genderEnum,
    );
    // 宏量目标密度（g/kg）：硬编码同 NutritionCalculator.macros 内部值
    // 减脂/维持时 carbGPerKg=null（碳水填剩余，dashboard 读取时按剩余热量反算）
    final proteinGPerKg =
        goalEnum == Goal.cut ? 2.4 : goalEnum == Goal.bulk ? 1.8 : 1.4;
    final fatGPerKg =
        goalEnum == Goal.cut ? 0.9 : goalEnum == Goal.bulk ? 1.0 : 0.9;
    final double? carbGPerKg = goalEnum == Goal.bulk ? 5.0 : null;

    await repo.update(
      heightCm: height,
      weightKg: weight,
      bodyFatPct: bodyFat,
      age: age,
      gender: _gender, // String 写库
      activityLevel: _activity,
      goal: _goal, // String 写库
      formula: 'mifflin',
      dailyCalorieTarget: target,
      proteinGPerKg: proteinGPerKg,
      fatGPerKg: fatGPerKg,
      carbGPerKg: carbGPerKg,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存，每日目标 $target kcal')),
      );
      Navigator.of(context).pop();
    }
  }
}
