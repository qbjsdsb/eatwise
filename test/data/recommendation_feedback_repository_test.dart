// test/data/recommendation_feedback_repository_test.dart
//
// 推荐满意度反馈存储单元测试
//
// 覆盖：
// - insertFeedback + rating 范围校验
// - getRecent 按时间倒序 + limit
// - clearAll
// - 餐次/日期字段持久化

import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/recommendation_feedback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late RecommendationFeedbackRepository repo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory(), seedOnCreate: false);
    repo = RecommendationFeedbackRepository(db);
  });

  tearDown(() async => db.close());

  group('insertFeedback', () {
    test('rating 1-3 范围内合法', () async {
      await repo.insertFeedback(foodName: '麻婆豆腐', rating: 3, mealType: 'lunch', recommendDate: '2026-07-04');
      await repo.insertFeedback(foodName: '白粥', rating: 2, mealType: 'breakfast', recommendDate: '2026-07-04');
      await repo.insertFeedback(foodName: '生鱼片', rating: 1, mealType: 'dinner', recommendDate: '2026-07-04');
      final all = await repo.getRecent(limit: 10);
      expect(all.length, 3);
    });

    test('rating=0 → 抛 ArgumentError', () async {
      expect(
        () => repo.insertFeedback(foodName: 'test', rating: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rating=4 → 抛 ArgumentError', () async {
      expect(
        () => repo.insertFeedback(foodName: 'test', rating: 4),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rating=-1 → 抛 ArgumentError', () async {
      expect(
        () => repo.insertFeedback(foodName: 'test', rating: -1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('mealType/recommendDate 可选（不传 → null）', () async {
      await repo.insertFeedback(foodName: '测试', rating: 3);
      final all = await repo.getRecent(limit: 10);
      expect(all.length, 1);
      expect(all.first.mealType, isNull);
      expect(all.first.recommendDate, isNull);
    });
  });

  group('getRecent', () {
    test('按时间倒序（最新在前）', () async {
      await repo.insertFeedback(foodName: '第一', rating: 3);
      await Future.delayed(const Duration(milliseconds: 10));
      await repo.insertFeedback(foodName: '第二', rating: 3);
      await Future.delayed(const Duration(milliseconds: 10));
      await repo.insertFeedback(foodName: '第三', rating: 3);
      final all = await repo.getRecent(limit: 10);
      expect(all.length, 3);
      expect(all[0].foodName, '第三');
      expect(all[1].foodName, '第二');
      expect(all[2].foodName, '第一');
    });

    test('limit 截断', () async {
      for (var i = 0; i < 5; i++) {
        await repo.insertFeedback(foodName: '食物$i', rating: 3);
        await Future.delayed(const Duration(milliseconds: 5));
      }
      final top3 = await repo.getRecent(limit: 3);
      expect(top3.length, 3);
      // 最新的 3 条（食物4/3/2）
      expect(top3[0].foodName, '食物4');
      expect(top3[2].foodName, '食物2');
    });

    test('空表 → 返回空列表', () async {
      final all = await repo.getRecent(limit: 10);
      expect(all, isEmpty);
    });
  });

  group('clearAll', () {
    test('清除所有反馈', () async {
      await repo.insertFeedback(foodName: 'test1', rating: 3);
      await repo.insertFeedback(foodName: 'test2', rating: 1);
      expect(await repo.clearAll(), 2);
      final all = await repo.getRecent(limit: 10);
      expect(all, isEmpty);
    });

    test('空表 clearAll → 返回 0', () async {
      expect(await repo.clearAll(), 0);
    });
  });

  group('字段持久化', () {
    test('foodName/rating/mealType/recommendDate/createdAt 全字段', () async {
      await repo.insertFeedback(
        foodName: '宫保鸡丁',
        rating: 3,
        mealType: 'lunch',
        recommendDate: '2026-07-04',
      );
      final all = await repo.getRecent(limit: 10);
      expect(all.length, 1);
      final f = all.first;
      expect(f.foodName, '宫保鸡丁');
      expect(f.rating, 3);
      expect(f.mealType, 'lunch');
      expect(f.recommendDate, '2026-07-04');
      expect(f.createdAt, greaterThan(0));
    });
  });
}
