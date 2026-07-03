import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/insight_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// InsightRepository 测试（去重 + regenerate + 编辑）
/// 不依赖真实 GLM-4-Flash 网络，用固定字符串模拟 LLM 返回
void main() {
  late EatWiseDatabase db;
  late InsightRepository repo;

  setUp(() {
    db = EatWiseDatabase(NativeDatabase.memory());
    repo = InsightRepository(db);
  });

  tearDown(() async => db.close());

  test('find 不存在返回 null', () async {
    final result = await repo.find('weekly', '2026-06-30', '2026-07-06');
    expect(result, isNull);
  });

  test('insert + find 命中', () async {
    await repo.insert(
      periodType: 'weekly',
      periodStart: '2026-06-30',
      periodEnd: '2026-07-06',
      summaryText: '本周热量偏高，建议减少外卖。',
    );
    final found = await repo.find('weekly', '2026-06-30', '2026-07-06');
    expect(found, isNotNull);
    expect(found!.summaryText, contains('热量偏高'));
    expect(found.isEdited, 0); // 默认未编辑
  });

  test('regenerate 同周期删旧插新（去重）', () async {
    await repo.insert(
      periodType: 'weekly',
      periodStart: '2026-06-30',
      periodEnd: '2026-07-06',
      summaryText: '旧汇总',
    );
    // 重新生成
    await repo.regenerate(
      periodType: 'weekly',
      periodStart: '2026-06-30',
      periodEnd: '2026-07-06',
      summaryText: '新汇总',
    );
    // 应只剩 1 条
    final all = await db.insightSummaries.select().get();
    expect(all.length, 1);
    expect(all.first.summaryText, '新汇总');
  });

  test('updateText 标记 isEdited=1', () async {
    final id = await repo.insert(
      periodType: 'weekly',
      periodStart: '2026-06-30',
      periodEnd: '2026-07-06',
      summaryText: '原汇总',
    );
    await repo.updateText(id, '用户改写的汇总');
    final found = await repo.find('weekly', '2026-06-30', '2026-07-06');
    expect(found!.summaryText, '用户改写的汇总');
    expect(found.isEdited, 1); // 编辑后标记
  });

  test('不同周期独立存储（weekly 不与 monthly 串）', () async {
    await repo.insert(
      periodType: 'weekly',
      periodStart: '2026-06-30',
      periodEnd: '2026-07-06',
      summaryText: '周报',
    );
    await repo.insert(
      periodType: 'monthly',
      periodStart: '2026-06-01',
      periodEnd: '2026-06-30',
      summaryText: '月报',
    );
    final weekly = await repo.find('weekly', '2026-06-30', '2026-07-06');
    final monthly = await repo.find('monthly', '2026-06-01', '2026-06-30');
    expect(weekly!.summaryText, '周报');
    expect(monthly!.summaryText, '月报');
  });
}
