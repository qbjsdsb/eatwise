import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

const _dbName = 'eatwise.db';
const _keyStorageKey = 'eatwise_db_key';

/// 获取或生成数据库加密密钥（32 字节密码学安全随机）
Future<String> _getOrCreatePassphrase() async {
  const storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );
  final existing = await storage.read(key: _keyStorageKey);
  if (existing != null) return existing;

  // 生成 32 字节密码学安全随机密钥（256 bits，匹配 AES-256）
  // Random.secure() 底层调用 OS 级 CSPRNG（iOS: SecRandomCopyBytes / Android: SecureRandom）
  final random = Random.secure();
  final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
  final passphrase = keyBytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  await storage.write(key: _keyStorageKey, value: passphrase);
  return passphrase;
}

/// debug 模式校验 sqlite3mc 已链接（防止 build hooks 失效静默退回明文）
bool _debugCheckHasCipher(Database database) {
  return database.select('PRAGMA cipher;').isNotEmpty;
}

/// 打开加密数据库连接
Future<QueryExecutor> openEncryptedConnection() async {
  final dir = await getApplicationDocumentsDirectory();
  final dbFile = File(p.join(dir.path, _dbName));
  final passphrase = await _getOrCreatePassphrase();

  return NativeDatabase.createInBackground(
    dbFile,
    setup: (rawDb) {
      assert(_debugCheckHasCipher(rawDb));
      rawDb.execute("PRAGMA key = '$passphrase';");
    },
  );
}
