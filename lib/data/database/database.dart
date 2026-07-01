import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'database.g.dart';

/// 冒烟测试最小表（验证 drift 代码生成）
class TestItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
}

@DriftDatabase(tables: [TestItems])
class EatWiseDatabase extends _$EatWiseDatabase {
  EatWiseDatabase() : super(_openConnection());

  static QueryExecutor _openConnection() => NativeDatabase.memory();
}
