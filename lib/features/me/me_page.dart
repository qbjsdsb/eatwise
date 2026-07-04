import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/m3_widgets.dart';
import '../../data/database/database.dart';
import '../../data/repositories/profile_repository.dart';
import '../backup/backup_page.dart';
import '../profile/profile_page.dart';
import '../recognize/providers.dart' as recognize;
import '../settings/settings_page.dart';
import '../weight/weight_page.dart';

/// 我的页：用户卡片（tap 进档案）+ 数据/偏好/关于三组列表
class MePage extends ConsumerStatefulWidget {
  const MePage({super.key});
  @override
  ConsumerState<MePage> createState() => _MePageState();
}

class _MePageState extends ConsumerState<MePage> {
  Future<Profile>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadProfile();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _future = _loadProfile());
  }

  Future<Profile> _loadProfile() async {
    final db = await ref.read(recognize.databaseProvider.future);
    return ProfileRepository(db).get();
  }

  /// 跳转子页，返回后刷新用户卡片
  Future<void> _pushAndRefresh(Widget page) async {
    await Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => page));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: const Text('我的')),
          SliverToBoxAdapter(
            child: FutureBuilder<Profile>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  // SliverToBoxAdapter 给的是 bounded 宽度 + unbounded 高度，
                  // ErrorState/LoadingState 内部 Center 会 expand，需 SizedBox 提供高度约束
                  return SizedBox(height: 240, child: ErrorState(onRetry: _refresh));
                }
                if (!snap.hasData) {
                  return const SizedBox(height: 240, child: LoadingState());
                }
                final p = snap.data!;
                final textTheme = Theme.of(context).textTheme;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: HeroCard(
                    onTap: () => _pushAndRefresh(const ProfilePage()),
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: cs.onPrimaryContainer.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.person_rounded,
                              color: cs.onPrimaryContainer),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${p.heightCm.toStringAsFixed(0)}cm · ${p.weightKg.toStringAsFixed(1)}kg · ${p.age}岁',
                                style: textTheme.titleMedium?.copyWith(
                                  color: cs.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_genderLabel(p.gender)} · ${_goalLabel(p.goal)} · ${_activityLabel(p.activityLevel)}',
                                style: textTheme.bodySmall
                                    ?.copyWith(color: cs.onPrimaryContainer),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '每日目标 ${p.dailyCalorieTarget} kcal',
                                style: textTheme.bodySmall
                                    ?.copyWith(color: cs.onPrimaryContainer),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              SectionTitle('数据'),
              GroupCard(dividerIndent: 56, children: [
                _listItem(
                  Icons.monitor_weight_rounded,
                  '体重记录',
                  () => _pushAndRefresh(const WeightPage()),
                ),
                _listItem(
                  Icons.cloud_upload_rounded,
                  '数据备份',
                  () => _pushAndRefresh(const BackupPage()),
                ),
              ]),
              SectionTitle('偏好'),
              GroupCard(dividerIndent: 56, children: [
                _listItem(
                  Icons.settings_rounded,
                  '设置',
                  () => _pushAndRefresh(const SettingsPage()),
                ),
              ]),
              SectionTitle('关于'),
              GroupCard(dividerIndent: 56, children: [
                _listItem(
                  Icons.info_outline_rounded,
                  '关于慢慢吃',
                  () => _showAbout(context),
                ),
                _listItem(
                  Icons.privacy_tip_outlined,
                  '隐私政策',
                  () => _showPrivacy(),
                ),
              ]),
              const SizedBox(height: 32),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _listItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: LeadingIconContainer(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  String _genderLabel(String g) => g == 'male' ? '男' : '女';
  String _goalLabel(String g) =>
      {'cut': '减脂', 'bulk': '增肌', 'maintain': '维持'}[g] ?? '维持';
  String _activityLabel(double a) => {
        1.2: '久坐',
        1.375: '轻度活动',
        1.55: '中度活动',
        1.725: '高强度活动',
        1.9: '极度活动',
      }[a] ??
      '轻度活动';

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: '慢慢吃',
      applicationVersion: '0.16.0',
      applicationLegalese: '拍照识别食物热量 + 营养记录 + AI 汇总建议',
    );
  }

  Future<void> _showPrivacy() async {
    final text = await rootBundle.loadString('assets/privacy_policy.md');
    if (!mounted) return;
    // 注意：dialog push 到 root Navigator（showDialog 默认 useRootNavigator:true），
    // 关闭按钮必须用 dialog 自己的 ctx 来 pop；若用外层页面 context，
    // Navigator.of(context) 会找到 tab 的嵌套 Navigator，把 MePage 本身 pop 掉 → 黑屏。
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('隐私政策'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: Text(text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
