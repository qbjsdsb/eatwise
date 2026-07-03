import 'package:drift/drift.dart';
import 'package:eatwise/data/database/database.dart';

/// 离线识别队列 Repository
/// 离线拍照时入队，联网后由 OfflineQueueController 触发回补识别
class PendingRecognitionRepository {
  final EatWiseDatabase _db;
  PendingRecognitionRepository(this._db);

  /// 入队（离线拍照时调用）
  Future<int> enqueue({
    required String imagePath,
    required String mealType,
    required String date,
    String promptVersion = 'v1.0',
  }) {
    return _db.into(_db.pendingRecognitions).insert(
          PendingRecognitionsCompanion.insert(
            imagePath: imagePath,
            mealType: mealType,
            date: date,
            status: 'pending',
            promptVersion: Value(promptVersion),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  /// 查询所有 pending 记录（按创建时间升序，FIFO）
  Future<List<PendingRecognition>> listPending() {
    return (_db.pendingRecognitions.select()
          ..where((p) => p.status.equals('pending'))
          ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]))
        .get();
  }

  /// 查询全部记录（含 done/failed/pending，按创建时间降序）
  /// 反馈反查用：通过 imagePath 匹配 meal_log.original_image_path 找到对应 prompt_version
  Future<List<PendingRecognition>> listAll() {
    return (_db.pendingRecognitions.select()
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
        .get();
  }

  /// 按 imagePath 精准查询单条记录（反查 prompt_version 用，替代 listAll 全表扫）
  Future<PendingRecognition?> getByImagePath(String imagePath) {
    return (_db.pendingRecognitions.select()
          ..where((p) => p.imagePath.equals(imagePath))
          ..limit(1))
        .getSingleOrNull();
  }

  /// 标记成功
  Future<void> markDone(int id, int resultFoodItemId) async {
    await (_db.pendingRecognitions.update()..where((p) => p.id.equals(id)))
        .write(
      PendingRecognitionsCompanion(
        status: const Value('done'),
        resultFoodItemId: Value(resultFoodItemId),
        processedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 标记失败 + 重试计数 +1
  /// 重试 3 次后（retryCount 达到 3）标记 failed，不再重试
  ///
  /// [permanent] 为 true 时直接标记 failed（图片缺失等不可恢复错误），不增加重试计数
  Future<void> markFailed(int id, String errorMessage,
      {bool permanent = false}) async {
    if (permanent) {
      await (_db.pendingRecognitions.update()..where((p) => p.id.equals(id)))
          .write(
        PendingRecognitionsCompanion(
          status: const Value('failed'),
          errorMessage: Value(errorMessage),
          processedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      return;
    }
    // 包事务：read-then-write 原子化，防"立即重试"与后台 workmanager 并发时
    // 两者都读到 retryCount=2 都写 +1（本应一方写 failed），导致计数丢失 + 本应
    // failed 的任务继续重试浪费 API 配额
    await _db.transaction(() async {
      final current = await (_db.pendingRecognitions.select()
            ..where((p) => p.id.equals(id)))
          .getSingleOrNull();
      if (current == null) return; // 记录已被删除（并发场景），无需标记失败
      await (_db.pendingRecognitions.update()..where((p) => p.id.equals(id)))
          .write(
        PendingRecognitionsCompanion(
          // retryCount 当前为 0/1/2 时下次还重试；当前为 2 时（即将变 3）标记 failed
          status: current.retryCount >= 2
              ? const Value('failed')
              : const Value('pending'),
          retryCount: Value(current.retryCount + 1),
          errorMessage: Value(errorMessage),
        ),
      );
    });
  }

  /// 统计 pending 数量（UI 角标用）
  Future<int> countPending() async {
    final result = await (_db.pendingRecognitions.select()
          ..where((p) => p.status.equals('pending')))
        .get();
    return result.length;
  }
}
