import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/backup/json_exporter.dart';
import '../../data/backup/json_importer.dart';
import '../recognize/providers.dart' as recognize;

/// 数据备份页：导出 JSON 到文档目录 + 从 JSON 文本导入
/// （MVP 版：不加 file_picker / share_plus 依赖，导入用粘贴 JSON）
class BackupPage extends ConsumerWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据备份')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: () => _export(context, ref),
            icon: const Icon(Icons.upload),
            label: const Text('导出为 JSON'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _import(context, ref),
            icon: const Icon(Icons.download),
            label: const Text('从 JSON 导入'),
          ),
          const SizedBox(height: 24),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '说明：导出生成 JSON 文件到 App 文档目录；导入粘贴 JSON 文本后还原。'
                '导入会清空当前数据后批量写入，请谨慎操作。',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final db = await ref.read(recognize.databaseProvider.future);
      final exporter = JsonExporter(db);
      final jsonStr = await exporter.exportAsString();
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final fileName =
          'eatwise_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.json';
      final file = await File('${dir.path}/$fileName').writeAsString(jsonStr);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已导出到 ${file.path}'),
            duration: const Duration(seconds: 5)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('导出失败：$e'),
            duration: const Duration(seconds: 5)),
      );
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
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
            decoration: const InputDecoration(
              hintText: '粘贴之前导出的 JSON 文本',
              border: OutlineInputBorder(),
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
      ctrl.dispose();
    }
    if (jsonStr == null || jsonStr.trim().isEmpty) return;

    final db = await ref.read(recognize.databaseProvider.future);
    final importer = JsonImporter(db);
    try {
      final stats = await importer.importFromString(jsonStr);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '导入成功：${stats.profiles}档案 + ${stats.foodItems}食物 + ${stats.mealLogs}餐次 + ${stats.weightLogs}体重 + ${stats.insights}汇总 + ${stats.feedbacks}反馈'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e'), duration: const Duration(seconds: 5)),
      );
    }
  }
}
