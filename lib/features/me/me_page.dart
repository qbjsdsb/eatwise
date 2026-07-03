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
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48),
                          const SizedBox(height: 16),
                          const Text('数据加载失败'),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: _refresh,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final p = snap.data!;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Card(
                    color: cs.primaryContainer,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _pushAndRefresh(const ProfilePage()),
                      child: Padding(
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
                                    style: TextStyle(
                                      color: cs.onPrimaryContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_genderLabel(p.gender)} · ${_goalLabel(p.goal)} · ${_activityLabel(p.activityLevel)}',
                                    style: TextStyle(
                                      color: cs.onPrimaryContainer,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '每日目标 ${p.dailyCalorieTarget} kcal',
                                    style: TextStyle(
                                      color: cs.onPrimaryContainer,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              _sectionTitle('数据'),
              _groupCard([
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
              _sectionTitle('偏好'),
              _groupCard([
                _listItem(
                  Icons.settings_rounded,
                  '设置',
                  () => _pushAndRefresh(const SettingsPage()),
                ),
              ]),
              _sectionTitle('关于'),
              _groupCard([
                _listItem(
                  Icons.info_outline_rounded,
                  '关于 EatWise',
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

  Widget _sectionTitle(String text) => SectionTitle(text);

  Widget _groupCard(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Column(children: _withDividers(children)),
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> items) {
    if (items.length <= 1) return items;
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i < items.length - 1) {
        result.add(Divider(
          height: 1,
          indent: 56,
          color: Theme.of(context).dividerColor,
        ));
      }
    }
    return result;
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
      applicationVersion: '0.10.0',
      applicationLegalese: '拍照识别食物热量 + 营养记录 + AI 汇总建议',
    );
  }

  Future<void> _showPrivacy() async {
    final text = await rootBundle.loadString('assets/privacy_policy.md');
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('隐私政策'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: Text(text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
