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

  test('同一天多次记录各存一条（DB 层）', () async {
    // insert 层各存一条（保留历史，编辑/删除用）
    await repo.insert(date: '2026-07-02', weightKg: 70.0);
    await repo.insert(date: '2026-07-02', weightKg: 70.2);

    // 直接查 DB 验证两条都存了（不经过 getRange 去重）
    final all = await db.select(db.weightLogs).get();
    expect(all.length, 2, reason: 'DB 层应保留所有记录');
  });

  test('L5: getRange 同日多条去重保留最新（与 getRangeForTdee 一致）', () async {
    // 同日插入两条，第二条是更新后的值
    await repo.insert(date: '2026-07-02', weightKg: 70.0);
    await repo.insert(date: '2026-07-02', weightKg: 71.5);

    final logs = await repo.getRange('2026-07-02', '2026-07-02');
    expect(logs.length, 1, reason: 'L5: 同日多条应去重，折线图只显示一个点');
    expect(logs.first.weightKg, 71.5,
        reason: 'L5: 保留最新（后插入的 id 大，是用户最新值）');
  });

  test('L5: getRange 跨日多条只对同日去重，不同日各保留', () async {
    await repo.insert(date: '2026-07-01', weightKg: 70.0);
    await repo.insert(date: '2026-07-01', weightKg: 70.5); // 覆盖 07-01
    await repo.insert(date: '2026-07-02', weightKg: 71.0);

    final logs = await repo.getRange('2026-07-01', '2026-07-02');
    expect(logs.length, 2, reason: '不同日应各保留一条');
    expect(logs[0].date, '2026-07-01');
    expect(logs[0].weightKg, 70.5, reason: '07-01 取最新');
    expect(logs[1].date, '2026-07-02');
    expect(logs[1].weightKg, 71.0);
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

  // ===== 编辑/删除能力测试（P0 第一批：全 editable）=====

  group('getById 单条查询', () {
    test('存在 id 返回 WeightLog', () async {
      final id = await repo.insert(date: '2026-07-02', weightKg: 70.5);
      final log = await repo.getById(id);
      expect(log, isNotNull);
      expect(log!.id, id);
      expect(log.weightKg, 70.5);
      expect(log.date, '2026-07-02');
    });

    test('不存在的 id 返回 null', () async {
      final log = await repo.getById(99999);
      expect(log, isNull);
    });
  });

  group('update 部分更新', () {
    test('只改 weightKg，date 保持原值', () async {
      final id = await repo.insert(date: '2026-07-02', weightKg: 70.0);
      await repo.update(id: id, weightKg: 71.5);

      final log = await repo.getById(id);
      expect(log, isNotNull);
      expect(log!.weightKg, 71.5);
      expect(log.date, '2026-07-02'); // date 未传，保留原值
    });

    test('只改 date，weightKg 保持原值', () async {
      final id = await repo.insert(date: '2026-07-02', weightKg: 70.0);
      await repo.update(id: id, date: '2026-07-05');

      final log = await repo.getById(id);
      expect(log, isNotNull);
      expect(log!.weightKg, 70.0); // weightKg 未传，保留原值
      expect(log.date, '2026-07-05');
    });

    test('同时改 weightKg 和 date', () async {
      final id = await repo.insert(date: '2026-07-02', weightKg: 70.0);
      await repo.update(id: id, weightKg: 71.2, date: '2026-07-05');

      final log = await repo.getById(id);
      expect(log, isNotNull);
      expect(log!.weightKg, 71.2);
      expect(log.date, '2026-07-05');
    });

    test('不传任何字段（null null）→ 不修改记录', () async {
      final id = await repo.insert(date: '2026-07-02', weightKg: 70.0);
      await repo.update(id: id);

      final log = await repo.getById(id);
      expect(log, isNotNull);
      expect(log!.weightKg, 70.0);
      expect(log.date, '2026-07-02');
    });

    test('更新不存在的 id 不报错（drift 无操作）', () async {
      // drift update where 不命中行时不报错，无副作用
      await repo.update(id: 99999, weightKg: 70.0);
      // 验证全表无新增
      final all = await repo.getRange('2020-01-01', '2099-12-31');
      expect(all, isEmpty);
    });
  });

  group('delete 删除', () {
    test('删除存在的记录', () async {
      final id = await repo.insert(date: '2026-07-02', weightKg: 70.0);
      await repo.delete(id);

      final log = await repo.getById(id);
      expect(log, isNull);
    });

    test('删除后其他记录不受影响', () async {
      final id1 = await repo.insert(date: '2026-07-01', weightKg: 70.0);
      final id2 = await repo.insert(date: '2026-07-02', weightKg: 71.0);
      await repo.delete(id1);

      expect(await repo.getById(id1), isNull);
      expect(await repo.getById(id2), isNotNull);
    });

    test('删除不存在的 id 不报错', () async {
      await repo.delete(99999);
      // 验证全表无变化
      final all = await repo.getRange('2020-01-01', '2099-12-31');
      expect(all, isEmpty);
    });
  });
}
