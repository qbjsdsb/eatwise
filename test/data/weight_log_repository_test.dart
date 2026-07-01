import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/weight_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late WeightLogRepository repo;

  setUp(() {
    db = EatWiseDatabase(NativeDatabase.memory());
    repo = WeightLogRepository(db);
  });

  tearDown(() async => db.close());

  test('insert + getRange 按日期升序', () async {
    // 故意乱序插入，验证 orderBy 生效
    await repo.insert(date: '2026-07-03', weightKg: 70.1);
    await repo.insert(date: '2026-07-01', weightKg: 70.5);
    await repo.insert(date: '2026-07-02', weightKg: 70.3);

    final logs = await repo.getRange('2026-07-01', '2026-07-03');
    expect(logs.length, 3);
    expect(logs[0].date, '2026-07-01');
    expect(logs[0].weightKg, 70.5);
    expect(logs[1].date, '2026-07-02');
    expect(logs[2].date, '2026-07-03');
  });

  test('getRange 区间端点包含', () async {
    await repo.insert(date: '2026-07-01', weightKg: 70.0);
    await repo.insert(date: '2026-07-05', weightKg: 70.5);
    await repo.insert(date: '2026-07-10', weightKg: 71.0);

    // 07-01 与 07-05 应在区间内，07-10 应被排除
    final logs = await repo.getRange('2026-07-01', '2026-07-05');
    expect(logs.length, 2);
    expect(logs.first.date, '2026-07-01');
    expect(logs.last.date, '2026-07-05');
  });

  test('同一天多次记录各存一条', () async {
    await repo.insert(date: '2026-07-02', weightKg: 70.0);
    await repo.insert(date: '2026-07-02', weightKg: 70.2);

    final logs = await repo.getRange('2026-07-02', '2026-07-02');
    expect(logs.length, 2);
  });

  test('getRecent 返回最近 N 天', () async {
    // 插入 35 天前 + 今天的数据
    final now = DateTime.now();
    final old = now.subtract(const Duration(days: 35));
    final oldDate =
        '${old.year}-${old.month.toString().padLeft(2, '0')}-${old.day.toString().padLeft(2, '0')}';
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    await repo.insert(date: oldDate, weightKg: 72.0);
    await repo.insert(date: today, weightKg: 70.0);

    // 默认 30 天，应只返回今天的
    final logs = await repo.getRecent(days: 30);
    expect(logs.length, 1);
    expect(logs.first.date, today);
    expect(logs.first.weightKg, 70.0);
  });
}
