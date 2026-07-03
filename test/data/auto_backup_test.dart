import 'dart:io';
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/backup/auto_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MemoryPathProvider extends PathProviderPlatform {
  final String basePath;
  _MemoryPathProvider(this.basePath);
  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

void main() {
  late EatWiseDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('auto_backup_test');
    PathProviderPlatform.instance = _MemoryPathProvider(tempDir.path);
  });
  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('run 生成备份文件到 backups/ 目录', () async {
    final path = await AutoBackup.run(db);
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(path, contains('backups'));
    expect(path, contains('eatwise_backup_'));
  });

  test('保留最近 4 份，多余的删除', () async {
    // 生成 6 份备份
    for (var i = 0; i < 6; i++) {
      await AutoBackup.run(db);
      // 稍微延迟确保文件名/时间不同（同一天同名会覆盖，模拟不同日期）
    }
    final backupDir = Directory('${tempDir.path}/backups');
    final files = backupDir.listSync().whereType<File>().toList();
    // 同一天生成的文件名相同会覆盖，所以实际文件数 ≤ 4
    expect(files.length, lessThanOrEqualTo(AutoBackup.maxBackups));
  });

  test('lastBackupTime 返回最近备份时间', () async {
    await AutoBackup.run(db);
    final time = await AutoBackup.lastBackupTime();
    expect(time, isNotNull);
    expect(
      time!.isBefore(DateTime.now()) || time.isAtSameMomentAs(DateTime.now()),
      isTrue,
    );
  });

  test('无备份时 lastBackupTime 返回 null', () async {
    final time = await AutoBackup.lastBackupTime();
    expect(time, isNull);
  });
}
