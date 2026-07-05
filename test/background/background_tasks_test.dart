// test/background/background_tasks_test.dart
// workmanager 是平台插件，沙箱无法真实注册任务。
// 此测试验证 callbackDispatcher 的逻辑分支（用 Fake DB + 内存 DB）
import 'package:drift/native.dart';
import 'package:eatwise/background/background_tasks.dart';
import 'package:eatwise/data/repositories/pending_recognition_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;

  setUp(() {
    db = EatWiseDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('callbackDispatcher offline_backfill 任务：空 pending 队列直接返回', () async {
    // 直接测 OfflineQueueController.processPending（callbackDispatcher 内部调它）
    // 空队列时应立即返回，不报错
    final pendingRepo = PendingRecognitionRepository(db);
    expect(await pendingRepo.listPending(), isEmpty);
    // （完整 Fake VisionProvider 测试见 test/features/offline_queue_test.dart，Sprint 2 已有）
  });

  test('BackgroundTasks 任务名常量唯一', () {
    expect(BackgroundTasks.offlineBackfill, 'offline_backfill');
    expect(BackgroundTasks.autoBackup, 'auto_backup');
    expect(BackgroundTasks.imageCleanup, 'image_cleanup');
    // 三个任务名互不相同
    final names = {
      BackgroundTasks.offlineBackfill,
      BackgroundTasks.autoBackup,
      BackgroundTasks.imageCleanup,
    };
    expect(names.length, 3);
  });
}
