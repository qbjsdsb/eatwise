import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/widgets/m3_widgets.dart';
import '../../data/backup/json_exporter.dart';
import '../../data/backup/json_importer.dart';
import '../recognize/providers.dart' as recognize;

/// 数据备份页：导出 JSON 到文档目录 + 从 JSON 文本导入
/// （MVP 版：不加 file_picker / share_plus 依赖，导入用粘贴 JSON）
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false; // 导出/导入进行中：禁用按钮 + 显示遮罩

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('数据备份')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _export(),
                icon: const Icon(Icons.upload),
                label: const Text('导出为 JSON'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : () => _import(),
                icon: const Icon(Icons.download),
                label: const Text('从 JSON 导入'),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: Icon(Icons.info_outline_rounded,
                            color: cs.onSurfaceVariant, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '说明：导出生成 JSON 文件到 App 文档目录；导入粘贴 JSON 文本后还原。'
                          '导入会清空当前数据后批量写入，请谨慎操作。',
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // 进行中遮罩：防重复点击 + 给用户反馈
          if (_busy)
            Container(
              color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('处理中…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final db = await ref.read(recognize.databaseProvider.future);
      final exporter = JsonExporter(db);
      final jsonStr = await exporter.exportAsString();
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final fileName =
          'eatwise_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.json';
      final file = await File('${dir.path}/$fileName').writeAsString(jsonStr);
      if (!mounted) return;
      showAppToast(context, '已导出到 ${file.path}',
          duration: const Duration(seconds: 4));
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '导出失败：$e',
          duration: const Duration(seconds: 4));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final ctrl = TextEditingController();
    String? jsonStr;
    try {
      jsonStr = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入 JSON'),
          content: TextField(
            controller: ctrl,
            maxLines: 12,
            // JSON 文本：禁用自动纠错与建议，避免破坏 JSON 结构
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: '粘贴之前导出的 JSON 文本…',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('导入'),
            ),
          ],
        ),
      );
    } finally {
      // showDialog 返回时弹窗退出动画仍在进行（~200ms），立即 dispose 会让
      // TextField 在动画期间引用已释放的 controller（"used after being disposed"）。
      // 延迟到退出动画结束后再 dispose。
      Future.delayed(const Duration(milliseconds: 300), ctrl.dispose);
    }
    if (jsonStr == null || jsonStr.trim().isEmpty) return;
    if (!mounted) return;

    // 查询离线队列 pending 数：导入会 DELETE FROM pending_recognitions，
    // 破坏性操作需在确认弹窗中告知用户具体条数（M24 Task A5 知情同意）
    final pendingRepo =
        await ref.read(recognize.pendingRecognitionRepoProvider.future);
    final pendingCount = await pendingRepo.countPending();
    if (!mounted) return;

    // 二次确认：导入会先清空当前所有数据（DELETE FROM 8 张表，含 pending_recognitions），
    // 破坏性操作需用户明确知情同意。pending>0 时额外提示离线队列将被清空
    final pendingHint = pendingCount > 0
        ? '\n\n⚠️ 离线队列中 $pendingCount 条待识别记录将被清空'
        : '';
    final confirmed = await confirmAction(
      context,
      title: '确认导入',
      content: '导入将清空当前所有数据（档案、食物库、餐次记录、体重、汇总、反馈），此操作不可撤销。$pendingHint\n\n确定继续？',
      confirmLabel: '确定导入',
      icon: Icons.warning_amber_rounded,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      // JsonImporter 不是 Repository，直接用 databaseProvider 拿 db 实例
      final db = await ref.read(recognize.databaseProvider.future);
      final importer = JsonImporter(db);
      final stats = await importer.importFromString(jsonStr);
      if (!mounted) return;
      showAppToast(
          context,
          '导入成功：${stats.profiles}档案 + ${stats.foodItems}食物 + ${stats.mealLogs}餐次 + ${stats.weightLogs}体重 + ${stats.insights}汇总 + ${stats.feedbacks}反馈${stats.imageCheckResult.totalMissing > 0 ? '\n注意：${stats.imageCheckResult.totalMissing} 张图片未迁移（原图未保留）' : ''}',
          duration: const Duration(seconds: 4));
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '导入失败：$e',
          duration: const Duration(seconds: 4));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
