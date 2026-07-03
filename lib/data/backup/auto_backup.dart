import 'dart:io';

import 'package:eatwise/data/backup/json_exporter.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:path_provider/path_provider.dart';

/// 自动备份：每周导出 JSON 到 backups/ 目录，保留最近 4 份
/// 设计文档 9.5
class AutoBackup {
  static const maxBackups = 4;

  /// 执行自动备份（后台任务调用）
  /// 返回备份文件路径，失败返回 null
  static Future<String?> run(EatWiseDatabase db) async {
    try {
      final exporter = JsonExporter(db);
      final jsonStr = await exporter.exportAsString();

      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${dir.path}/backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final now = DateTime.now();
      final fileName =
          'eatwise_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';
      final file = File('${backupDir.path}/$fileName');
      await file.writeAsString(jsonStr);

      // 清理旧备份（保留最近 maxBackups 份）
      await _pruneOldBackups(backupDir);

      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 清理旧备份，保留最近 maxBackups 份
  static Future<void> _pruneOldBackups(Directory backupDir) async {
    final files = await backupDir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    if (files.length <= maxBackups) return;

    // 按修改时间降序排序，删除多余的
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    for (var i = maxBackups; i < files.length; i++) {
      try {
        await files[i].delete();
      } catch (_) {}
    }
  }

  /// 查询上次自动备份时间（设置页显示用）
  /// 超过 14 天未备份则看板提示
  static Future<DateTime?> lastBackupTime() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${dir.path}/backups');
      if (!backupDir.existsSync()) return null;
      final files = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      if (files.isEmpty) return null;
      files.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
      return files.first.statSync().modified;
    } catch (_) {
      return null;
    }
  }
}
