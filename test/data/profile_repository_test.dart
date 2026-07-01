import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late ProfileRepository repo;

  setUp(() {
    db = EatWiseDatabase(NativeDatabase.memory());
    repo = ProfileRepository(db);
  });

  tearDown(() async => db.close());

  test('get 读取默认 profile（database.dart onCreate 初始化的行）', () async {
    // 触发数据库创建（beforeOpen 钩子初始化 profile 行）
    await db.customSelect('SELECT 1').get();

    final p = await repo.get();
    expect(p.id, 1);
    expect(p.heightCm, 170);
    expect(p.weightKg, 70);
    expect(p.age, 30);
    expect(p.gender, 'male');
    expect(p.activityLevel, 1.375);
    expect(p.goal, 'maintain');
    expect(p.dailyCalorieTarget, 2000);
  });

  test('update 部分字段：只传 heightCm + weightKg，其余保持不变', () async {
    await db.customSelect('SELECT 1').get();
    await repo.update(heightCm: 180, weightKg: 75);

    final p = await repo.get();
    expect(p.heightCm, 180);
    expect(p.weightKg, 75);
    // 未传的字段保持原值
    expect(p.age, 30);
    expect(p.gender, 'male');
    expect(p.dailyCalorieTarget, 2000);
  });

  test('update 全字段：dailyCalorieTarget + 宏量目标写入', () async {
    await db.customSelect('SELECT 1').get();
    await repo.update(
      heightCm: 175,
      weightKg: 80,
      age: 25,
      gender: 'female',
      activityLevel: 1.55,
      goal: 'cut',
      formula: 'mifflin',
      dailyCalorieTarget: 1800,
      proteinGPerKg: 2.4,
      fatGPerKg: 0.9,
      carbGPerKg: null, // 减脂：碳水填剩余
    );

    final p = await repo.get();
    expect(p.heightCm, 175);
    expect(p.weightKg, 80);
    expect(p.age, 25);
    expect(p.gender, 'female');
    expect(p.activityLevel, 1.55);
    expect(p.goal, 'cut');
    expect(p.dailyCalorieTarget, 1800);
    expect(p.proteinGPerKg, 2.4);
    expect(p.fatGPerKg, 0.9);
    expect(p.carbGPerKg, isNull);
  });
}
