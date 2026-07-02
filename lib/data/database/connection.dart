import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _dbName = 'eatwise.db';

/// 打开数据库连接（明文版，移除 sqlite3mc 加密避免 native 库兼容问题）
///
/// 历史：曾用 sqlite3mc 加密，但 build hooks 在 CI release 模式下
/// 可能未正确编译 native 库导致运行时崩溃。个人自用 app 加密是过度设计，
/// 临时移除以排除 native 库问题，恢复稳定后可再评估。
Future<QueryExecutor> openEncryptedConnection() async {
  final dir = await getApplicationDocumentsDirectory();
  final dbFile = File(p.join(dir.path, _dbName));

  return NativeDatabase.createInBackground(dbFile);
}
