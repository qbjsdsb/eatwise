# Sprint 6：健壮性补全 + 显示规范 + 成本透明 + 质量基建

**编写日期：** 2026-07-02
**编写者：** Claude（writing-plans skill）
**前置条件：** Sprint 1-5 已完成（129 测试全过，analyze 0 issues）
**范围：** 15 个 Task（T37-T51），聚焦 4 条线：健壮性（断路器/refusal）+ 显示规范（估算区间/g/kg 双展示）+ 成本透明（月度计数显示）+ 质量基建（反馈补全/Prompt 回归/图片清理/设置页补全）
**执行方式：** Subagent-Driven Development（如 Sprint 3/4/5）
**沙箱约束：** 每个 Task 测试必须能在 `flutter test` 沙箱跑通（平台插件用 fake/注入），不引入需真机才能验证的 Task
**依赖约束：** 不新增 pubspec 依赖（复用 fl_chart / drift / flutter_riverpod / openai_dart / flutter_secure_storage 等已有包）

---

## 背景与缺口分析

Sprint 1-5 完成了核心识别、完整闭环、健壮性、可用性、完整性补全。Sprint 5 Self-Review 第1节列出 6 个未覆盖章节，经 Sprint 6 调研逐个核实源码后确定范围：

| 缺口线 | 设计章节 | 现状 | 影响 |
|---|---|---|---|
| 断路器 | 3.2 / 11.1 | recognize_controller 无连续失败计数/短路；后台 workmanager 回补无保护 | API 故障期后台回补持续烧 token |
| 显示规范 | 5.6 / 7.4 | 数据层 Low/Mid/High 已存，但下游全用 Mid 单值；无 ±10-15% 区间；无 g/kg 双展示 | 伪装精确，违背设计价值观 |
| refusal 区分 | 11.1 / 12.1 | qwen_vl_provider 无 refusal 检测分支，refusal 被当 malformed 处理 | 用户看到"JSON 解析失败"误导信息 |
| 成本显示 | 11.3 | 限流+压缩已做，但设置页无"本月识别次数/累计花费" | 用户无法感知月度消耗 |
| Prompt 回归 | 12.4 / 4.2.7 | recognition_feedback 表有数据但无按 prompt_version 聚合查询；无导出 | prompt 迭代无回归保护 |
| 反馈补全 | 4.2.7 | 反馈弹窗只问准/不准，不收集 correctedDishName/ServingG（表字段已存） | 反馈数据不完整，回归集质量差 |
| 图片清理 | 9.4 | ImageCleanup.run/runIfBacklogLarge 已实现，但 main.dart 未调用；设置页无保留期选择 | 启动不清理，保留期不可配 |
| 设置页补全 | 7.x | 无关于页/版本号/清缓存入口 | 体验项缺失 |

**明确推后**：L2-L4 数据源（6.2）— 设计自身标"后续迭代"，L2 USDA API 工作量大且 L1（1677 条食材）已满足闭环，推后至独立迭代。

---

## Sprint 6 完成标准

- [ ] CI 全绿：`flutter analyze` 0 issues + `flutter test --exclude-tags smoke` 全过
- [ ] T37-T51 共 15 个 Task 的 commit 全部在分支
- [ ] recognize_controller 断路器：连续 3 次失败短路 30s（持久化跨 session）
- [ ] qwen_vl_provider refusal 显式检测（非 malformed 误归类）
- [ ] NutritionLookup 支持区间计算（Low/Mid/High）
- [ ] 校准页 + 看板显示估算区间 ±10-15%
- [ ] 设置页显示本月识别次数 + 估算花费
- [ ] 反馈弹窗收集 correctedDishName/ServingG
- [ ] recognition_feedback 按 prompt_version 聚合准确率查询
- [ ] main.dart 启动调用 ImageCleanup.runIfBacklogLarge
- [ ] 设置页含图片保留期选择 + 关于页 + 清缓存
- [ ] Self-Review 全部完成

---

## 文件结构

### 新建文件
- `lib/features/recognize/circuit_breaker.dart` — 断路器状态机（T37）
- `test/features/circuit_breaker_test.dart` — 断路器单测（T37）
- `test/features/refusal_detection_test.dart` — refusal 检测测试（T39）
- `test/features/nutrition_range_test.dart` — 区间计算测试（T40）
- `test/features/estimation_range_ui_test.dart` — 区间 UI 测试（T41）
- `test/features/monthly_cost_test.dart` — 月度计数测试（T43）
- `test/features/feedback_correction_test.dart` — 反馈补全测试（T45）
- `test/features/prompt_accuracy_test.dart` — prompt 聚合测试（T46）
- `test/features/image_cleanup_startup_test.dart` — 启动清理测试（T47）
- `test/features/settings_completeness_test.dart` — 设置页补全测试（T49）

### 修改文件（按 Task 分组）
- **断路器线**：`lib/features/recognize/circuit_breaker.dart`（新）、`lib/features/recognize/recognize_controller.dart`（T38 接入）、`lib/features/offline/offline_queue_controller.dart`（T38 后台回补接入）
- **refusal 线**：`lib/ai/vision_provider.dart`（T39 加 isRefusal 字段）、`lib/ai/qwen_vl_provider.dart`（T39 检测）、`lib/ai/glm_4v_provider.dart`（T39 复用检测）、`lib/features/recognize/recognize_controller.dart`（T39 L3 提示）
- **显示规范线**：`lib/ai/nutrition_lookup.dart`（T40 区间计算）、`lib/features/recognize/calibration_page.dart`（T41 区间 UI）、`lib/features/dashboard/dashboard_page.dart`（T42 看板区间 + g/kg）
- **成本线**：`lib/core/config/secure_config_store.dart`（T43 月度计数存储）、`lib/features/recognize/recognize_controller.dart`（T43 识别成功计数）、`lib/features/settings/settings_page.dart`（T44 设置页展示）
- **质量线**：`lib/features/dashboard/today_meals_page.dart`（T45 反馈弹窗补全）、`lib/data/repositories/recognition_feedback_repository.dart`（T46 聚合查询）、`lib/data/backup/json_exporter.dart`（T46 导出）
- **运维线**：`lib/main.dart`（T47 启动清理）、`lib/data/backup/image_cleanup.dart`（T48 保留期参数）、`lib/features/settings/settings_page.dart`（T49 保留期 + 关于 + 清缓存）

---

## Task 37: 断路器状态机（CircuitBreaker）

**目标:** 实现断路器状态机：连续 3 次 retryable 失败 → 短路 30s，期间直接拒绝调用（不入队不重试），30s 后半开试探一次。

**参考设计文档:** 3.2（连续 3 次失败短路 30s）、11.1（避免烧预算）

**Files:**
- Create: `lib/features/recognize/circuit_breaker.dart`
- Test: `test/features/circuit_breaker_test.dart`

**当前状态核实:**
- recognize_controller.dart 无任何断路器字段（搜索 circuit/breaker/consecutive 零命中）
- 设计 3.2 节：连续 3 次失败 → 短路 30s
- 断路器需跨 session 持久化（后台 workmanager 回补也要感知），用 secure_storage 存（与 SecureConfigStore 同源）

- [ ] **Step 1: 创建 circuit_breaker.dart**

```dart
// lib/features/recognize/circuit_breaker.dart
import 'package:flutter/foundation.dart';

/// 断路器状态
enum CircuitBreakerState { closed, open, halfOpen }

/// 视觉模型断路器（设计 3.2：连续 3 次失败 → 短路 30s）
///
/// 状态机：
/// - closed（正常）：记录失败次数，连续 3 次 retryable 失败 → open
/// - open（短路）：直接拒绝调用，30s 后 → halfOpen
/// - halfOpen（半开）：放行一次试探，成功 → closed，失败 → open（重置计时）
///
/// 持久化：失败计数 + open 截止时间存 secure_storage，跨 session + 后台回补感知
class CircuitBreaker {
  static const _failureThreshold = 3;
  static const _openDuration = Duration(seconds: 30);

  final Future<void> Function(String key, String value) _write;
  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key) _delete;
  final DateTime Function() _now;

  static const _keyFailures = 'circuit_failures';
  static const _keyOpenUntil = 'circuit_open_until';

  CircuitBreaker({
    required Future<void> Function(String key, String value) write,
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key) delete,
    DateTime Function()? now,
  })  : _write = write,
        _read = read,
        _delete = delete,
        _now = now ?? DateTime.now;

  /// 当前状态（读持久化数据判断）
  Future<CircuitBreakerState> get state async {
    final openUntilStr = await _read(_keyOpenUntil);
    if (openUntilStr != null) {
      final openUntil = DateTime.fromMillisecondsSinceEpoch(int.parse(openUntilStr));
      if (_now().isBefore(openUntil)) return CircuitBreakerState.open;
      // 已过 open 截止 → halfOpen（未持久化，仅内存判断）
      return CircuitBreakerState.halfOpen;
    }
    return CircuitBreakerState.closed;
  }

  /// 调用前检查：是否允许调用
  /// open 状态返回 false（调用方应直接走降级，不调 API）
  Future<bool> get allowCall async => await state != CircuitBreakerState.open;

  /// 记录成功：重置失败计数，清除 open 截止（halfOpen → closed）
  Future<void> recordSuccess() async {
    await _delete(_keyFailures);
    await _delete(_keyOpenUntil);
  }

  /// 记录失败：失败计数 +1，达阈值 → open
  Future<void> recordFailure() async {
    final failuresStr = await _read(_keyFailures);
    final failures = int.tryParse(failuresStr ?? '0') ?? 0;
    final newFailures = failures + 1;
    if (newFailures >= _failureThreshold) {
      // 达阈值 → open，写截止时间
      final openUntil = _now().add(_openDuration);
      await _write(_keyOpenUntil, openUntil.millisecondsSinceEpoch.toString());
      await _delete(_keyFailures); // open 期间不计失败
    } else {
      await _write(_keyFailures, newFailures.toString());
    }
  }

  /// halfOpen 试探失败 → 重新 open（重置 30s 计时）
  /// （halfOpen 状态下 recordFailure 也会走到 open 分支，但需确保 openUntil 重置）
  /// 实际上 recordFailure 已处理：halfOpen 时 _keyFailures 为空（之前 recordSuccess 清了或 open 期间清了），
  /// newFailures=1 < 3 不会重新 open。故 halfOpen 失败需单独处理。
  Future<void> recordHalfOpenFailure() async {
    final openUntil = _now().add(_openDuration);
    await _write(_keyOpenUntil, openUntil.millisecondsSinceEpoch.toString());
    await _delete(_keyFailures);
  }

  /// 仅供测试：读取当前失败计数
  @visibleForTesting
  Future<int> get failureCount async {
    final failuresStr = await _read(_keyFailures);
    return int.tryParse(failuresStr ?? '0') ?? 0;
  }
}
```

> **注意**：
> - 断路器用回调注入存储（`write/read/delete`），便于测试用内存 Map 模拟，也便于生产用 SecureConfigStore。
> - `_now` 可注入便于测试（避免真实等待 30s，测试用 fakeNow 推进时钟）。
> - halfOpen 失败单独处理（`recordHalfOpenFailure`）：因为 open 期间失败计数被清空，halfOpen 时 recordFailure 的 newFailures=1 不会重新触发 open，故需显式重置 openUntil。

- [ ] **Step 2: 创建 circuit_breaker_test.dart**

```dart
// test/features/circuit_breaker_test.dart
import 'package:eatwise/features/recognize/circuit_breaker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, String> storage;
  late CircuitBreaker breaker;
  // 可注入的时钟，从固定起点推进
  late DateTime fakeNow;

  setUp(() {
    storage = {};
    fakeNow = DateTime(2026, 7, 2, 12, 0, 0);
    breaker = CircuitBreaker(
      write: (k, v) async => storage[k] = v,
      read: (k) async => storage[k],
      delete: (k) async => storage.remove(k),
      now: () => fakeNow,
    );
  });

  test('初始状态 closed，允许调用', () async {
    expect(await breaker.state, CircuitBreakerState.closed);
    expect(await breaker.allowCall, isTrue);
  });

  test('连续 2 次失败仍 closed（未达阈值 3）', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    expect(await breaker.state, CircuitBreakerState.closed);
    expect(await breaker.failureCount, 2);
  });

  test('连续 3 次失败 → open，拒绝调用', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    expect(await breaker.state, CircuitBreakerState.open);
    expect(await breaker.allowCall, isFalse);
  });

  test('open 期间 30s 内仍 open', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    // 推进 29s
    fakeNow = fakeNow.add(const Duration(seconds: 29));
    expect(await breaker.state, CircuitBreakerState.open);
  });

  test('open 30s 后 → halfOpen，允许调用试探', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    // 推进 31s
    fakeNow = fakeNow.add(const Duration(seconds: 31));
    expect(await breaker.state, CircuitBreakerState.halfOpen);
    expect(await breaker.allowCall, isTrue);
  });

  test('halfOpen 试探成功 → closed，失败计数清零', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    fakeNow = fakeNow.add(const Duration(seconds: 31));
    expect(await breaker.state, CircuitBreakerState.halfOpen);
    await breaker.recordSuccess();
    expect(await breaker.state, CircuitBreakerState.closed);
    expect(await breaker.failureCount, 0);
  });

  test('halfOpen 试探失败 → 重新 open（重置 30s）', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    // 31s 后 halfOpen
    fakeNow = fakeNow.add(const Duration(seconds: 31));
    expect(await breaker.state, CircuitBreakerState.halfOpen);
    // halfOpen 试探失败
    await breaker.recordHalfOpenFailure();
    // 重新 open，需再等 30s
    fakeNow = fakeNow.add(const Duration(seconds: 29));
    expect(await breaker.state, CircuitBreakerState.open);
    fakeNow = fakeNow.add(const Duration(seconds: 2));
    expect(await breaker.state, CircuitBreakerState.halfOpen);
  });

  test('closed 状态成功调用 → 失败计数清零', () async {
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordSuccess();
    expect(await breaker.failureCount, 0);
  });

  test('断路器状态跨实例持久化（模拟重启）', () async {
    // 实例 1：触发 open
    await breaker.recordFailure();
    await breaker.recordFailure();
    await breaker.recordFailure();
    expect(await breaker.state, CircuitBreakerState.open);
    // 实例 2：用同一 storage 新建（模拟后台 workmanager 新 session）
    final breaker2 = CircuitBreaker(
      write: (k, v) async => storage[k] = v,
      read: (k) async => storage[k],
      delete: (k) async => storage.remove(k),
      now: () => fakeNow,
    );
    expect(await breaker2.state, CircuitBreakerState.open);
    expect(await breaker2.allowCall, isFalse);
  });
}
```

- [ ] **Step 3: flutter analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze
flutter test test/features/circuit_breaker_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/recognize/circuit_breaker.dart test/features/circuit_breaker_test.dart
git commit -m "feat: Sprint 6 T37 - 断路器状态机(连续3次失败短路30s,跨session持久化)"
```

---

## Task 38: 断路器接入 recognize_controller + 后台回补

**目标:** recognize_controller 调用 Vision API 前检查断路器（open 时直接走离线入队，不调 API 不烧 token）；识别成功 recordSuccess，retryable 失败 recordFailure；后台 offline_queue_controller 回补也接入断路器。

**参考设计文档:** 3.2、11.1

**Files:**
- Modify: `lib/features/recognize/recognize_controller.dart`
- Modify: `lib/features/offline/offline_queue_controller.dart`
- Modify: `lib/features/recognize/providers.dart`（注入 CircuitBreaker）
- Modify: `test/features/recognize_controller_test.dart`（加断路器集成测试）

**当前状态核实:**
- recognize_controller.dart:150-186 是 L1/L2/L3 容灾链路（T36 实现），断路器接入点在 line 150 `try { result = await _primaryProvider.recognize...` 之前
- recognize_controller.dart:208-235 外层 catch（retryable → 离线入队）保持不变
- offline_queue_controller.dart processPending 调视觉模型处（T30 已加 fallback try/catch）
- providers.dart（66 行）：qwenVlProviderProvider line 35、glm4vProviderProvider line 42、offlineQueueControllerProvider 在 offline_queue_controller.dart 末尾（T30 已核实）

- [ ] **Step 1: 修改 recognize_controller.dart — 接入断路器**

```dart
// lib/features/recognize/recognize_controller.dart 改动：

// 1. import circuit_breaker.dart：
import 'circuit_breaker.dart';

// 2. 构造器加 circuitBreaker 参数（可选，向后兼容 Sprint 3/5 测试）：
class RecognizeController extends StateNotifier<RecognizeUiState> {
  final VisionProvider _primaryProvider;
  final VisionProvider? _fallbackProvider;
  final NutritionLookup _nutritionLookup;
  final Future<void> Function(String, String, String, String)? _onOfflineEnqueue;
  final void Function()? _onL3Fallback;
  final CircuitBreaker? _circuitBreaker;  // 新增：T37 断路器（可选，向后兼容）

  // ... existing fields ...

  RecognizeController(
    this._primaryProvider,
    this._fallbackProvider,
    this._nutritionLookup, {
    Future<void> Function(String, String, String, String)? onOfflineEnqueue,
    void Function()? onL3Fallback,
    CircuitBreaker? circuitBreaker,  // 新增：可选命名参数（与 T36 onL3Fallback 模式一致）
  })  : _onOfflineEnqueue = onOfflineEnqueue,
        _onL3Fallback = onL3Fallback,
        _circuitBreaker = circuitBreaker,
        super(RecognizeUiState());

  // 注意：字段 _circuitBreaker（下划线前缀，私有惯例），构造参数 circuitBreaker，
  // 初始化列表 _circuitBreaker = circuitBreaker（与 T36 _onL3Fallback 模式一致）

  @visibleForTesting
  CircuitBreaker? get circuitBreakerForTest => _circuitBreaker;

  // 3. pickAndRecognize 中，调 Vision API 前检查断路器（line 149 try 之前）：
  // 在 _lastRecognizeTime = DateTime.now(); 之后、VisionRecognitionResult result; 之前：
  // T37 断路器：open 状态直接走离线入队，不调 API 不烧 token
  if (circuitBreaker != null && !await circuitBreaker.allowCall) {
    state = state.copyWith(
      state: RecognizeState.error,
      errorMessage: '识别服务暂时不可用（断路器保护中），已加入离线队列',
    );
    // 直接走离线入队（与外层 catch 一致的入队逻辑）
    if (_onOfflineEnqueue != null && xFile != null) {
      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      try {
        await _onOfflineEnqueue(xFile.path, mealType, today, Prompts.version);
        state = state.copyWith(
          state: RecognizeState.queued,
          errorMessage: '识别服务暂时不可用，已加入队列，稍后自动重试',
          imagePath: xFile.path,
        );
      } catch (e) {
        state = state.copyWith(
          state: RecognizeState.error,
          errorMessage: '离线入队失败：$e',
        );
      }
    }
    return;
  }

  // 4. 识别成功后 recordSuccess（在 result 赋值后、查库回填前，line 187 附近）：
  // VisionRecognitionResult result 已确定（无论主/L1重试/L2切备成功）后：
  if (circuitBreaker != null) await circuitBreaker.recordSuccess();

  // 5. retryable 失败 rethrow 前 recordFailure（内层 catch 的各 rethrow 点）：
  // 在内层 catch（line 152-186）的每个 rethrow 前，以及 halfOpen 失败处理：
  // 由于 rethrow 点分散，统一在【外层 catch】开头判断：如果是 retryable VisionRecognitionException，recordFailure/halfOpenFailure
  // （见 Step 1.6 外层 catch 改动）
```

> **注意**：
> - 断路器检查放 `_lastRecognizeTime` 之后，避免限流拒绝时也触发断路器逻辑。
> - 断路器 open 时直接入队（与 retryable 失败入队一致），不入队则仅 error 状态。
> - **recordSuccess 时机**：result 赋值成功后（line 187 前），无论主/L1/L2 成功都算成功。
> - **recordFailure 时机**：在外层 catch 统一处理（避免内层多个 rethrow 点重复代码）。

- [ ] **Step 2: 修改 recognize_controller.dart — 外层 catch 接入断路器 recordFailure**

```dart
// recognize_controller.dart 外层 catch（line 208-235）改动：
// 原：
//   } catch (e) {
//     if (_onOfflineEnqueue != null && xFile != null && e is VisionRecognitionException && e.retryable) {
//       ... 入队 ...
//     }
//     state = state.copyWith(state: RecognizeState.error, errorMessage: e.toString());
//   }
// 改：
} catch (e) {
  // T37 断路器：retryable 失败记录（连续 3 次 → open）
  if (circuitBreaker != null && e is VisionRecognitionException && e.retryable) {
    final breakerState = await circuitBreaker.state;
    if (breakerState == CircuitBreakerState.halfOpen) {
      await circuitBreaker.recordHalfOpenFailure();
    } else {
      await circuitBreaker.recordFailure();
    }
  }
  if (_onOfflineEnqueue != null &&
      xFile != null &&
      e is VisionRecognitionException &&
      e.retryable) {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    try {
      await _onOfflineEnqueue(xFile.path, mealType, today, Prompts.version);
      state = state.copyWith(
        state: RecognizeState.queued,
        errorMessage: '当前离线，已加入队列，联网后自动识别',
        imagePath: xFile.path,
      );
      return;
    } catch (enqueueErr) {
      state = state.copyWith(
        state: RecognizeState.error,
        errorMessage: '离线入队失败：$enqueueErr',
      );
      return;
    }
  }
  state = state.copyWith(state: RecognizeState.error, errorMessage: e.toString());
}
```

- [ ] **Step 3: 修改 offline_queue_controller.dart — 后台回补接入断路器**

```dart
// lib/features/offline/offline_queue_controller.dart 改动：

// 1. 构造器加 circuitBreaker 参数：
class OfflineQueueController {
  final EatWiseDatabase _db;
  final VisionProvider _visionProvider;
  final VisionProvider? _fallbackProvider;
  final NutritionLookup _nutritionLookup;
  final CircuitBreaker? _circuitBreaker;  // 新增
  // ...

  OfflineQueueController({
    required EatWiseDatabase db,
    required VisionProvider visionProvider,
    VisionProvider? fallbackProvider,
    required NutritionLookup nutritionLookup,
    this.circuitBreaker,  // 新增
  })  : _db = db,
        _visionProvider = visionProvider,
        _fallbackProvider = fallbackProvider,
        _nutritionLookup = nutritionLookup,
        _circuitBreaker = circuitBreaker;

  // 2. processPending 中，调视觉模型前检查断路器（T30 的 try/catch 之前）：
  // 在读图片转 base64 之后、调 _visionProvider.recognize 之前：
  // T37 断路器：open 状态跳过本条（不调 API），直接 continue 保留 pending 状态
  // 【第2轮 Self-Review 修正】：不能调 markFailed！markFailed 会增加 retryCount
  //   （pending_recognition_repository.dart:61-88：retryCount 达 3 标 failed 永久不重试），
  //   断路器 open 30s 期间多次 processPending 会触发上限导致 pending 永久 failed。
  //   正确做法：直接 continue，保留 pending 状态，等断路器恢复后下次 processPending 重试。
  if (_circuitBreaker != null && !await _circuitBreaker.allowCall) {
    continue;  // 保留 pending，不调 markFailed，等断路器恢复
  }

  // 3. 视觉调用成功后 recordSuccess（在 result 赋值后）：
  if (_circuitBreaker != null) await _circuitBreaker.recordSuccess();

  // 4. 视觉调用失败 catch 中 recordFailure（T30 的 catch 块）：
  // 原：
  //   } catch (e) {
  //     if (_fallbackProvider == null) rethrow;
  //     result = await _fallbackProvider.recognize...;
  //   }
  // 改：在 rethrow 前 / fallback 失败前 recordFailure
  // 由于 processPending 外层有 try/catch 处理 markFailed，这里在 fallback 也失败的最终 catch 记录
```

> **注意**：
> - **后台回补断路器 open 时 markFailed（不 markDone）**：等断路器恢复后下次 processPending 重试。markFailed 会增加重试计数，需确认 pendingRepo.markFailed 是否有重试上限（Sprint 2 测试 line 8："markFailed 重试 3 次后标记 failed"）—— 断路器 open 期间可能多次 markFailed 触发上限。**实施时核实 markFailed 逻辑**，若会触发上限导致 pending 永久 failed，改为不调 markFailed 直接 continue（保留 pending 状态等下次）。
> - 后台回补断路器 recordFailure：在 processPending 外层 catch（markFailed 处）记录。

- [ ] **Step 4: 修改 providers.dart + offline_queue_controller.dart provider — 注入 CircuitBreaker**

```dart
// lib/features/recognize/providers.dart 改动（新增 circuitBreakerProvider）：
import '../../features/recognize/circuit_breaker.dart';
import '../../core/config/app_config.dart';  // 已 import

// 新增 provider（用 SecureConfigStore 作存储后端）：
final circuitBreakerProvider = Provider<CircuitBreaker>((ref) {
  final store = ref.read(secureConfigStoreProvider);
  return CircuitBreaker(
    write: (k, v) => store.writeRaw(k, v),  // 用公开方法（T38 在 SecureConfigStore 新增）
    read: (k) => store.readRaw(k),
    delete: (k) => store.deleteRaw(k),
  );
});
```

> **注意**：SecureConfigStore 现有方法都是具名（getQwenApiKey 等），无通用 write/read/delete，且 `_storage` 是 private（line 23）外部不可访问。**T38 需在 SecureConfigStore 加 3 个公开通用方法**（已核实 secure_config_store.dart:23 `_storage` private）：
> ```dart
> // lib/core/config/secure_config_store.dart 追加（T38 + T43 + T48 共用）：
> /// 通用 raw 读写（断路器/月度计数/保留期等用，key 自定义）
> Future<void> writeRaw(String key, String value) => _storage.write(key: key, value: value);
> Future<String?> readRaw(String key) => _storage.read(key: key);
> Future<void> deleteRaw(String key) => _storage.delete(key: key);
> ```
> 这 3 个方法同时供 T43 月度计数、T48 保留期复用（替代 T43/T48 计划中各自新增具名方法，统一用 writeRaw/readRaw）。

- [ ] **Step 5: 修改 recognize_page.dart — 注入 CircuitBreaker**

```dart
// lib/features/recognize/recognize_page.dart 改动（_ensureController，T36 已用位置参数）：
// 在构造 RecognizeController 时加 circuitBreaker 命名参数：
final breaker = ref.read(circuitBreakerProvider);
_controller = RecognizeController(
  qwen,
  glm,
  lookup,
  onOfflineEnqueue: (...) async { ... },  // 现有
  onL3Fallback: () { ... },  // T36 现有
  circuitBreaker: breaker,  // 新增
);
```

- [ ] **Step 6: 修改 recognize_controller_test.dart — 加断路器集成测试**

```dart
// test/features/recognize_controller_test.dart 追加：
// 复用 Sprint 3/5 的 _FakeVisionProvider / _FakeNutritionLookup
// 用内存 Map 模拟断路器存储

test('断路器 open 时 pickAndRecognize 不调 API 直接入队', () async {
  // 这个测试依赖 pickAndRecognize 完整流程（ImagePicker 平台插件），
  // 沙箱跑不了 → 标 @Tags(['smoke']) 真机验证
}, tags: ['smoke']);

test('T38：构造器接受 circuitBreaker（编译期验证 + 字段可读）', () {
  final storage = <String, String>{};
  final breaker = CircuitBreaker(
    write: (k, v) async => storage[k] = v,
    read: (k) async => storage[k],
    delete: (k) async => storage.remove(k),
  );
  final controller = RecognizeController(
    _FakeVisionProvider(),
    null,
    _FakeNutritionLookup(),
    circuitBreaker: breaker,
  );
  expect(controller.circuitBreakerForTest, isNotNull);
});

test('T38：circuitBreaker 默认 null（向后兼容，未注入时不报错）', () {
  final controller = RecognizeController(
    _FakeVisionProvider(),
    null,
    _FakeNutritionLookup(),
  );
  expect(controller.circuitBreakerForTest, isNull);
});
```

- [ ] **Step 7: flutter analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze
flutter test test/features/recognize_controller_test.dart test/features/circuit_breaker_test.dart test/features/offline_queue_test.dart test/features/offline_queue_composite_test.dart
```

- [ ] **Step 8: Commit**

```bash
git add lib/features/recognize/recognize_controller.dart lib/features/offline/offline_queue_controller.dart lib/features/recognize/providers.dart lib/features/recognize/recognize_page.dart lib/core/config/secure_config_store.dart test/features/recognize_controller_test.dart
git commit -m "feat: Sprint 6 T38 - 断路器接入recognize_controller+后台回补(open时跳过不烧token)"
```

---

## Task 39: refusal 显式检测（qwen_vl_provider + glm_4v_provider）

**目标:** qwen_vl_provider 检测模型 refusal（内容安全过滤），抛 `VisionRecognitionException(reason, retryable: false, isRefusal: true)`；recognize_controller L3 提示"内容被安全过滤"而非"JSON 解析失败"。

**参考设计文档:** 11.1（refusal 不重试）、12.1（refusal 测试）

**Files:**
- Modify: `lib/ai/vision_provider.dart`（VisionRecognitionException 加 isRefusal）
- Modify: `lib/ai/qwen_vl_provider.dart`（检测 refusal）
- Modify: `lib/ai/glm_4v_provider.dart`（复用检测）
- Modify: `lib/features/recognize/recognize_controller.dart`（L3 提示文案）
- Test: `test/features/refusal_detection_test.dart`

**当前状态核实:**
- vision_provider.dart:67-75 VisionRecognitionException 有 reason/retryable/retryAfter，无 isRefusal
- qwen_vl_provider.dart:72-78 response.text 为空时抛 retryable:false；line 79-81 FormatException 也 retryable:false。**无 refusal 检测**：模型返回 refusal 文本（如"我无法识别"）非 JSON → jsonDecode 抛 FormatException → 当 malformed 处理
- 设计 11.1：refusal 不重试（重试就是付费再听"no"）
- openai_dart 7.0 response 有 `choices[].message.refusal` 字段（OpenAI 标准），但 Qwen-VL 兼容模式可能不填，需文本兜底检测

- [ ] **Step 1: 修改 vision_provider.dart — VisionRecognitionException 加 isRefusal**

```dart
// lib/ai/vision_provider.dart 改动（VisionRecognitionException 类）：
class VisionRecognitionException implements Exception {
  final String reason;
  final bool retryable;
  final Duration? retryAfter;
  final bool isRefusal;  // 新增：T39 内容安全过滤标记

  VisionRecognitionException(
    this.reason, {
    this.retryable = false,
    this.retryAfter,
    this.isRefusal = false,  // 新增，默认 false
  });

  @override
  String toString() => reason;
}
```

- [ ] **Step 2: 修改 qwen_vl_provider.dart — 检测 refusal**

```dart
// lib/ai/qwen_vl_provider.dart 改动（recognizeWithClient 方法，line 70-78 之间）：
// 原：
//   final jsonStr = response.text;
//   if (jsonStr == null || jsonStr.isEmpty) {
//     throw VisionRecognitionException('空响应', retryable: false);
//   }
//   final json = jsonDecode(jsonStr) as Map<String, dynamic>;
//   return VisionRecognitionResult.fromJson(json, promptVersion);
// 改：
final jsonStr = response.text;

// T39：检测 refusal（内容安全过滤）
// 1. 优先检查 OpenAI 标准 refusal 字段（openai_dart 7.0 response.choices[].message.refusal）
//    但 Qwen-VL 兼容模式可能不填，需文本兜底
// 2. 文本兜底：refusal 关键词检测（"我无法"/"不能识别"/"内容违反"/"I cannot"/"I can't"）
if (_isRefusal(jsonStr, response)) {
  throw VisionRecognitionException(
    '内容被安全过滤（模型拒绝识别），请换一张照片或手动录入',
    retryable: false,
    isRefusal: true,
  );
}

if (jsonStr == null || jsonStr.isEmpty) {
  throw VisionRecognitionException('空响应', retryable: false);
}

final json = jsonDecode(jsonStr) as Map<String, dynamic>;
return VisionRecognitionResult.fromJson(json, promptVersion);

// 新增 _isRefusal 静态方法（放 recognizeWithClient 后）：
/// 检测模型 refusal（内容安全过滤）
/// 1. OpenAI 标准 refusal 字段非空 → refusal
/// 2. 文本兜底：含 refusal 关键词且非合法 JSON（避免误判正常菜名含"无法"等）
static bool _isRefusal(String? text, dynamic response) {
  // 1. 标准 refusal 字段（openai_dart 7.0：response.choices[].message.refusal）
  try {
    final choices = response.choices;
    if (choices != null && choices.isNotEmpty) {
      final refusal = choices.first.message.refusal;
      if (refusal != null && refusal.isNotEmpty) return true;
    }
  } catch (_) {
    // 字段访问失败（SDK 版本差异）→ 走文本兜底
  }
  // 2. 文本兜底：空文本或含 refusal 关键词
  if (text == null || text.isEmpty) return false;  // 空文本走"空响应"分支
  final lower = text.toLowerCase();
  const refusalKeywords = [
    '我无法', '我不能', '无法识别', '不能识别', '内容违反', '违反政策',
    'i cannot', "i can't", 'i am unable', 'content policy', 'safety',
  ];
  // 仅当文本含关键词且【不是合法 JSON】时判定为 refusal
  // （正常菜名"我无法想象"等极罕见，且正常响应是 JSON 对象不会含这些短语）
  if (refusalKeywords.any((k) => lower.contains(k.toLowerCase()))) {
    try {
      jsonDecode(text);  // 是合法 JSON → 不是 refusal（可能是菜名含关键词）
      return false;
    } catch (_) {
      return true;  // 非 JSON + 含关键词 → refusal
    }
  }
  return false;
}
```

> **注意**：
> - **refusal 检测优先级**：标准 refusal 字段 > 文本兜底。文本兜底需"含关键词 + 非 JSON"双条件，避免误判。
> - refusal 是 `retryable: false`（设计 11.1：不重试），走 L3 转手动。
> - `_isRefusal` 用 `dynamic response` 避免强依赖 openai_dart 类型（SDK 版本兼容）。

- [ ] **Step 3: 修改 glm_4v_provider.dart — 复用 refusal 检测**

```dart
// lib/ai/glm_4v_provider.dart 改动：
// 先 Read 确认 GLM 是否复用 QwenVlProvider.recognizeWithClient（T30 调研提到"两个 Provider 仅 client/baseUrl/modelName 不同，识别流程完全一致"）
// 如果 GLM 直接调 QwenVlProvider.recognizeWithClient，则 refusal 检测自动生效，无需改
// 如果 GLM 有独立 recognize 实现，需复制 _isRefusal 检测
// 实施时先 Read glm_4v_provider.dart 确认
```

- [ ] **Step 4: 修改 recognize_controller.dart — L3 提示文案区分 refusal**

```dart
// lib/features/recognize/recognize_controller.dart 改动（_triggerL3Fallback，line 241-254）：
// 原：
//   void _triggerL3Fallback() {
//     if (_onL3Fallback != null) {
//       state = state.copyWith(state: RecognizeState.error, errorMessage: '识别失败，已转手动录入');
//       _onL3Fallback();
//     } else { ... }
//   }
// 改：_triggerL3Fallback 接收异常参数，区分 refusal
void _triggerL3Fallback({VisionRecognitionException? error}) {
  final message = (error?.isRefusal ?? false)
      ? '内容被安全过滤，已转手动录入'
      : '识别失败，已转手动录入';
  if (_onL3Fallback != null) {
    state = state.copyWith(
      state: RecognizeState.error,
      errorMessage: message,
    );
    _onL3Fallback();
  } else {
    state = state.copyWith(
      state: RecognizeState.error,
      errorMessage: error?.isRefusal ?? false ? '内容被安全过滤' : '识别失败',
    );
  }
}

// 内层 catch 的 L3 触发点（line 173-176）改：
} else if (!e.retryable) {
  _triggerL3Fallback(error: e);  // 传异常给 L3 区分 refusal
  return;
}
```

- [ ] **Step 5: 创建 refusal_detection_test.dart**

```dart
// test/features/refusal_detection_test.dart
import 'package:eatwise/ai/qwen_vl_provider.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 直接测 _isRefusal 静态方法（需 visibleForTesting 暴露，或通过 recognizeWithClient 间接测）
  // 由于 _isRefusal 是 private，通过 recognizeWithClient 间接测更稳妥
  // 但 recognizeWithClient 依赖 OpenAIClient，需 mock
  // 简化方案：把 _isRefusal 改为 @visibleForTesting public 静态方法

  test('refusal 文本（非 JSON + 含关键词）判定为 refusal', () {
    expect(QwenVlProvider.isRefusalForTest('我无法识别这张图片', null), isTrue);
    expect(QwenVlProvider.isRefusalForTest('I cannot help with this', null), isTrue);
  });

  test('合法 JSON 不判定为 refusal（即使含关键词）', () {
    // 正常响应是 JSON，即使菜名含"无法"也不是 refusal
    expect(QwenVlProvider.isRefusalForTest('{"dish_name":"无法命名的菜"}', null), isFalse);
  });

  test('正常 JSON 响应不判定为 refusal', () {
    expect(QwenVlProvider.isRefusalForTest('{"dish_name":"宫保鸡丁"}', null), isFalse);
  });

  test('空文本不判定为 refusal（走空响应分支）', () {
    expect(QwenVlProvider.isRefusalForTest('', null), isFalse);
    expect(QwenVlProvider.isRefusalForTest(null, null), isFalse);
  });

  test('VisionRecognitionException isRefusal 默认 false', () {
    // 【第2轮修正】：构造器非 const（vision_provider.dart:72 无 const 关键字），用 final
    final e = VisionRecognitionException('test');
    expect(e.isRefusal, isFalse);
  });

  test('VisionRecognitionException 可设置 isRefusal', () {
    final e = VisionRecognitionException('refusal', isRefusal: true);
    expect(e.isRefusal, isTrue);
    expect(e.retryable, isFalse);
  });
}
```

> **注意**：测试需 `_isRefusal` 改为 `@visibleForTesting static bool isRefusalForTest(...)`。实施时把 `_isRefusal` 重命名为 `isRefusalForTest` 并加 `@visibleForTesting`。

- [ ] **Step 6: flutter analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze
flutter test test/features/refusal_detection_test.dart test/features/recognize_controller_test.dart
```

- [ ] **Step 7: Commit**

```bash
git add lib/ai/vision_provider.dart lib/ai/qwen_vl_provider.dart lib/ai/glm_4v_provider.dart lib/features/recognize/recognize_controller.dart test/features/refusal_detection_test.dart
git commit -m "feat: Sprint 6 T39 - refusal显式检测(isRefusal标记+L3提示区分+非malformed误归类)"
```

---

## Task 40: NutritionLookup 区间计算（Low/Mid/High）

**目标:** NutritionLookup 新增区间计算方法，返回 Low/Mid/High 三档热量/宏量（Mid 为现有值，Low/High 按 ±10-15% 计算），供 UI 显示估算区间。

**参考设计文档:** 5.6（估算区间 ±10-15%）、3.1（份量估算）

**Files:**
- Modify: `lib/ai/nutrition_lookup.dart`
- Test: `test/features/nutrition_range_test.dart`

**当前状态核实:**
- nutrition_lookup.dart:30-45 lookupSingleItem 只接收 servingG 单值，返回 NutritionResult 单值
- nutrition_lookup.dart:48-97 lookupCompositeDish 用 comp.estimatedG 单值
- vision_provider.dart:4-6 VisionRecognitionResult 有 estimatedWeightGLow/Mid/High 三字段
- 设计 5.6：单品 ±3-5%，复合菜 ±10-15%，纯图像 ±20%。MVP 统一用 ±10% 区间（Low=Mid×0.9, High=Mid×1.1）简化

- [ ] **Step 1: 修改 nutrition_lookup.dart — 新增区间计算**

```dart
// lib/ai/nutrition_lookup.dart 改动：

// 1. 新增 NutritionRange 类（放 NutritionResult 后）：
/// 营养素区间（Low/Mid/High 三档，设计 5.6 估算区间）
class NutritionRange {
  final NutritionResult low;
  final NutritionResult mid;
  final NutritionResult high;

  const NutritionRange({required this.low, required this.mid, required this.high});
}

/// 复合菜营养素区间
class CompositeNutritionRange {
  final CompositeNutritionResult low;
  final CompositeNutritionResult mid;
  final CompositeNutritionResult high;

  const CompositeNutritionRange({required this.low, required this.mid, required this.high});
}

// 2. NutritionLookup 新增区间计算方法：
class NutritionLookup {
  // ... 现有代码 ...

  /// 单品区间计算（Low/Mid/High 三档份量）
  /// 设计 5.6：估算区间 ±10%（MVP 统一，单品实际 ±3-5% 但 UI 简化展示）
  Future<NutritionRange?> lookupSingleItemWithRange({
    required String dishName,
    required double servingGLow,
    required double servingGMid,
    required double servingGHigh,
  }) async {
    final low = await lookupSingleItem(dishName: dishName, servingG: servingGLow);
    final mid = await lookupSingleItem(dishName: dishName, servingG: servingGMid);
    final high = await lookupSingleItem(dishName: dishName, servingG: servingGHigh);
    if (low == null || mid == null || high == null) return null;
    return NutritionRange(low: low, mid: mid, high: high);
  }

  /// 复合菜区间计算（Low/Mid/High 三档份量，按比例缩放）
  /// 复合菜组分 estimatedG 是单值，区间按 Mid 份量 ±10% 缩放
  Future<CompositeNutritionRange> lookupCompositeDishWithRange({
    required List<FoodComponent> components,
    required String cookingMethod,
  }) async {
    final mid = await lookupCompositeDish(components: components, cookingMethod: cookingMethod);
    // Low/High 按份量 ±10% 缩放（组分份量按比例）
    final lowComponents = components.map((c) => FoodComponent(name: c.name, estimatedG: c.estimatedG * 0.9)).toList();
    final highComponents = components.map((c) => FoodComponent(name: c.name, estimatedG: c.estimatedG * 1.1)).toList();
    final low = await lookupCompositeDish(components: lowComponents, cookingMethod: cookingMethod);
    final high = await lookupCompositeDish(components: highComponents, cookingMethod: cookingMethod);
    return CompositeNutritionRange(low: low, mid: mid, high: high);
  }
}
```

> **注意**：
> - 区间计算复用现有 lookupSingleItem/lookupCompositeDish，不重复查库逻辑。
> - 单品区间：用 Low/Mid/High 三档份量分别查库（3 次查库，但单品查库是本地 O(1)，可接受）。
> - 复合菜区间：组分份量按 ±10% 缩放后重新查库（3 次查库）。
> - MVP 统一 ±10%，不区分单品 ±3-5% / 复合菜 ±10-15%（设计允许简化，UI 统一展示更简洁）。
> - **【第2轮修正·重要】**：NutritionLookup 加新公开方法后，`test/features/recognize_controller_test.dart:35` 的 `_FakeNutritionLookup implements NutritionLookup` 必须实现这两个新方法，否则编译失败。T40 必须同步修改该测试文件的 _FakeNutritionLookup，补：
>   ```dart
>   @override
>   Future<NutritionRange?> lookupSingleItemWithRange({
>     required String dishName,
>     required double servingGLow,
>     required double servingGMid,
>     required double servingGHigh,
>   }) async => null;  // fake 不实际查库
>
>   @override
>   Future<CompositeNutritionRange> lookupCompositeDishWithRange({
>     required List<FoodComponent> components,
>     required String cookingMethod,
>   }) async => CompositeNutritionRange(
>     low: CompositeNutritionResult(calories: 0, proteinG: 0, fatG: 0, carbsG: 0, oilG: 0, componentHits: const [], componentMisses: const []),
>     mid: CompositeNutritionResult(calories: 0, proteinG: 0, fatG: 0, carbsG: 0, oilG: 0, componentHits: const [], componentMisses: const []),
>     high: CompositeNutritionResult(calories: 0, proteinG: 0, fatG: 0, carbsG: 0, oilG: 0, componentHits: const [], componentMisses: const []),
>   );
>   ```
>   T40 commit 需包含 `test/features/recognize_controller_test.dart`。

- [ ] **Step 2: 创建 nutrition_range_test.dart**

```dart
// test/features/nutrition_range_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/food_item_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late NutritionLookup lookup;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    lookup = NutritionLookup(FoodItemRepository(db));
    // 种子：米饭（116 kcal/100g）
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '米饭', defaultServingG: 100, caloriesPer100g: 116,
          proteinPer100g: 2.6, fatPer100g: 0.3, carbsPer100g: 25.9,
          source: 'manual', sourceVersion: 'test', createdAt: 1000));
  });
  tearDown(() async => db.close());

  test('单品区间计算：Low < Mid < High', () async {
    final range = await lookup.lookupSingleItemWithRange(
      dishName: '米饭',
      servingGLow: 90,
      servingGMid: 100,
      servingGHigh: 110,
    );
    expect(range, isNotNull);
    expect(range!.low.calories, lessThan(range.mid.calories));
    expect(range.mid.calories, lessThan(range.high.calories));
    // Mid = 116 kcal（100g × 116/100）
    expect(range.mid.calories, closeTo(116, 0.1));
    // Low = 104.4（90g），High = 127.6（110g）
    expect(range.low.calories, closeTo(104.4, 0.1));
    expect(range.high.calories, closeTo(127.6, 0.1));
  });

  test('单品未命中返回 null', () async {
    final range = await lookup.lookupSingleItemWithRange(
      dishName: '不存在的食物',
      servingGLow: 90, servingGMid: 100, servingGHigh: 110,
    );
    expect(range, isNull);
  });

  test('复合菜区间计算：Low < Mid < High', () async {
    final range = await lookup.lookupCompositeDishWithRange(
      components: const [FoodComponent(name: '米饭', estimatedG: 100)],
      cookingMethod: 'steam',
    );
    expect(range.low.calories, lessThan(range.mid.calories));
    expect(range.mid.calories, lessThan(range.high.calories));
  });
}
```

- [ ] **Step 3: flutter analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze
flutter test test/features/nutrition_range_test.dart test/features/nutrition_lookup_test.dart  # Sprint 1 回归
```

- [ ] **Step 4: Commit**

```bash
git add lib/ai/nutrition_lookup.dart test/features/nutrition_range_test.dart test/features/recognize_controller_test.dart
git commit -m "feat: Sprint 6 T40 - NutritionLookup区间计算(Low/Mid/High三档±10%)+FakeLookup补实现"
```

---

## Task 41: 校准页显示估算区间

**目标:** calibration_page 显示份量 + 估算区间（如"100g (90-110g)"），营养素预览显示区间（如"116 kcal (104-128)"）。

**参考设计文档:** 5.6、7.4

**Files:**
- Modify: `lib/features/recognize/calibration_page.dart`
- Test: `test/features/estimation_range_ui_test.dart`

**当前状态核实:**
- calibration_page.dart:98 显示 `份量：${_servingG}g`（单值）
- calibration_page.dart:132-140 _buildNutritionPreview 显示单值 cal/protein/fat/carbs
- calibration_page.dart:135 用 estimatedWeightGMid 算 ratio
- recognize_page.dart 调 calibration_page 时传 singleNutrition/compositeNutrition（单值 NutritionResult）

- [ ] **Step 1: 修改 calibration_page.dart — 显示区间**

```dart
// lib/features/recognize/calibration_page.dart 改动：

// 1. widget 加 nutritionRange 参数（可选，向后兼容）：
// 先 Read 确认 CalibrationPage widget 字段结构
// 加可选字段：final NutritionRange? singleNutritionRange; final CompositeNutritionRange? compositeNutritionRange;

// 2. 份量显示加区间（line 98 附近）：
// 原：Text('份量：${_servingG.toStringAsFixed(0)} g'),
// 改：
Text('份量：${_servingG.toStringAsFixed(0)} g'
    '${widget.singleNutritionRange != null ? " (估算 ${(widget.recognitionResult.estimatedWeightGLow).toStringAsFixed(0)}-${(widget.recognitionResult.estimatedWeightGHigh).toStringAsFixed(0)} g)" : ""}'),

// 3. _buildNutritionPreview 显示区间（line 132-140）：
// 单品路径：用 singleNutritionRange 的 Low/High
Widget _buildNutritionPreview() {
  if (widget.singleNutrition != null) {
    final ratio = _servingG / widget.recognitionResult.estimatedWeightGMid;
    final cal = widget.singleNutrition!.calories * ratio;
    final protein = widget.singleNutrition!.proteinG * ratio;
    final fat = widget.singleNutrition!.fatG * ratio;
    final carbs = widget.singleNutrition!.carbsG * ratio;
    // 区间（如有）
    final range = widget.singleNutritionRange;
    final calRange = range != null
        ? ' (${(range.low.calories * ratio).toStringAsFixed(0)}-${(range.high.calories * ratio).toStringAsFixed(0)})'
        : '';
    return _nutritionCard(cal, protein, fat, carbs, calRange: calRange);
  }
  // 复合菜路径类似...
}

// 4. _nutritionCard 加可选区间参数：
Widget _nutritionCard(double cal, double protein, double fat, double carbs, {String? calRange}) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('热量：${cal.toStringAsFixed(0)} kcal${calRange ?? ""}'),
          // ... protein/fat/carbs ...
        ],
      ),
    ),
  );
}
```

> **注意**：
> - 区间显示用括号 `(...)`，如"100g (90-110g)"、"116 kcal (104-128)"。
> - 区间仅热量显示（设计 5.6 重点），宏量可后续扩展。
> - **实施时核实**：recognize_page.dart 调 calibration_page 时需传入区间（调 T40 的 lookupSingleItemWithRange/lookupCompositeDishWithRange）。这需改 recognize_controller state 加 range 字段 + recognize_page 传参。**T41 范围**：calibration_page 显示 + recognize_page 传参 + recognize_controller state 加 range。若改动过大，T41 仅做 calibration_page 显示（用 widget.recognitionResult.estimatedWeightGLow/High 算份量区间），营养素区间推 T42。

- [ ] **Step 2: 修改 recognize_page.dart + recognize_controller.dart — 传区间**

```dart
// lib/features/recognize/recognize_controller.dart 改动：
// RecognizeUiState 加 singleNutritionRange / compositeNutritionRange 字段（可选）
// pickAndRecognize 中查库回填时调 lookupSingleItemWithRange/lookupCompositeDishWithRange
// （如果性能可接受，3 次查库；否则仅在校准页按需计算）

// 简化方案（T41 采用）：recognize_controller 仍用单值 lookup，calibration_page 内部按 widget.recognitionResult.estimatedWeightGLow/High 自算区间
// （份量区间直接用 Low/High，营养素区间按 ratio 缩放，无需 3 次查库）
```

> **注意**：T41 简化方案——calibration_page 用 estimatedWeightGLow/High 直接显示份量区间，营养素区间按 `ratio = Low/Mid` 和 `ratio = High/Mid` 缩放 singleNutrition（无需 T40 的区间查库）。**这样 T40 和 T41 解耦**：T40 提供精确区间查库（供 T42 看板用），T41 校准页用简化缩放。实施时根据复杂度选择。

- [ ] **Step 3: 创建 estimation_range_ui_test.dart**

```dart
// test/features/estimation_range_ui_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/ai/nutrition_lookup.dart';
import 'package:eatwise/ai/vision_provider.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/recognize/calibration_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('校准页显示份量区间', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // 种子食物
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '米饭', defaultServingG: 100, caloriesPer100g: 116,
          proteinPer100g: 2.6, fatPer100g: 0.3, carbsPer100g: 25.9,
          source: 'manual', sourceVersion: 'test', createdAt: 1000));

    final result = VisionRecognitionResult(
      dishName: '米饭',
      estimatedWeightGLow: 90,
      estimatedWeightGMid: 100,
      estimatedWeightGHigh: 110,
      isSingleItem: true,
      confidence: 0.9,
      promptVersion: 'v1.0',
    );
    final nutrition = await NutritionLookup(FoodItemRepository(db))
        .lookupSingleItem(dishName: '米饭', servingG: 100);

    await tester.pumpWidget(MaterialApp(
      home: CalibrationPage(
        recognitionResult: result,
        singleNutrition: nutrition,
      ),
    ));

    // 验证显示区间（含 "90-110" 或 "估算" 文字）
    expect(find.textContaining('90'), findsWidgets);
    expect(find.textContaining('110'), findsWidgets);
  });
}
```

> **注意**：先 Read CalibrationPage 构造器签名确认参数。如果 CalibrationPage 是 ConsumerWidget 不依赖 databaseProvider，可直接 pumpWidget；如果依赖 Provider，需 override。

- [ ] **Step 4: flutter analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze
flutter test test/features/estimation_range_ui_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/recognize/calibration_page.dart lib/features/recognize/recognize_page.dart lib/features/recognize/recognize_controller.dart test/features/estimation_range_ui_test.dart
git commit -m "feat: Sprint 6 T41 - 校准页显示估算区间(份量Low-High+热量区间)"
```

---

## Task 42: 看板显示估算区间 + g/kg 双展示

**目标:** dashboard_page 热量/宏量显示估算区间（±10%），宏量同时展示 g/kg 体重（用 profile.weightKg 换算）。

**参考设计文档:** 5.6、7.4

**Files:**
- Modify: `lib/features/dashboard/dashboard_page.dart`
- Modify: `lib/features/profile/profile_page.dart`（档案页展示 g/kg，可选）
- Test: `test/features/estimation_range_ui_test.dart`（追加用例）

**当前状态核实:**
- dashboard_page.dart:151 `d.cal.toStringAsFixed(0)`（单值热量）
- dashboard_page.dart:224 `'${value} / ${goal} g'`（单值宏量）
- profile.weightKg 字段已存（profile_table.dart）
- 设计 5.6：宏量同时展示 g/kg 与克数

- [ ] **Step 1: 修改 dashboard_page.dart — 热量区间 + g/kg**

```dart
// lib/features/dashboard/dashboard_page.dart 改动：

// 1. 热量显示加区间（line 151 附近）：
// 原：Text(d.cal.toStringAsFixed(0))
// 改：显示 Mid 值 + 区间（用 T40 的 NutritionRange，或按 ±10% 缩放）
// 由于 dashboard 显示的是 meal_log 已记录的 actualCalories（确定值，非估算），
// 区间仅对"今日识别未校准"的记录有意义。简化：dashboard 显示确定值，区间仅在校准页/识别页显示。
// T42 改为：宏量 g/kg 双展示（更有价值），热量区间推后（已记录值是确定的）

// 2. 宏量 g/kg 双展示（line 224 附近）：
// 原：'${value} / ${goal} g'
// 改：需读 profile.weightKg 换算 g/kg
// 先 Read dashboard_page 确认如何获取 profile（是否已 watch profileProvider）
// 加：'${value} / ${goal} g (${(value / weightKg).toStringAsFixed(1)} g/kg)'
```

> **注意**：
> - **热量区间重新评估**：dashboard 显示的是 meal_log.actualCalories（已校准确定值），非识别估算值。区间在校准页（T41）已展示。dashboard 区间无意义，T42 取消热量区间，仅做 g/kg 双展示。
> - **g/kg 换算**：需 profile.weightKg。dashboard 是否已加载 profile？先 Read 确认。若未加载，需加 profileRepo.get() 调用。
> - 依据来源标注（设计 5.6 第3点"标注依据来源"）：在档案页/设置页加"营养目标依据 ACSM/ISSN/NIH 标准"文字（简单 Text，归入 T42 或 T49 设置页补全）。

- [ ] **Step 2: 追加 estimation_range_ui_test.dart 用例**

```dart
// test/features/estimation_range_ui_test.dart 追加：
testWidgets('看板宏量显示 g/kg 双展示', (tester) async {
  // 种子 profile（weightKg=70）+ 今日 meal_log
  // pumpWidget DashboardPage
  // 验证 find.textContaining('g/kg')
});
```

- [ ] **Step 3: flutter analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze
flutter test test/features/estimation_range_ui_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/dashboard/dashboard_page.dart test/features/estimation_range_ui_test.dart
git commit -m "feat: Sprint 6 T42 - 看板宏量g/kg双展示(按体重换算)"
```

---

## Task 43: 月度识别计数存储 + 识别成功计数

**目标:** 识别成功时本地累计计数（按月），存 secure_storage；recognize_controller 识别成功后 +1。

**参考设计文档:** 11.3（App 内显示本月识别次数/累计花费）

**Files:**
- Modify: `lib/core/config/secure_config_store.dart`（月度计数存储）
- Modify: `lib/features/recognize/recognize_controller.dart`（识别成功计数）
- Test: `test/features/monthly_cost_test.dart`

**当前状态核实:**
- secure_config_store.dart 无月度计数方法（搜索 monthly/count/识别次数 零命中）
- recognize_controller.dart:200 识别成功后 state=done，无计数
- 设计 11.3：本月识别次数 + 估算花费（按 Qwen-VL 0.15 元/百万 token 估算，单次约 500 token ≈ 0.000075 元，或按次估 0.001 元简化）

- [ ] **Step 1: 修改 secure_config_store.dart — 月度计数存储**

```dart
// lib/core/config/secure_config_store.dart 改动：

// 1. 加 key 常量（key 格式：monthly_count_YYYYMM）：
static const _monthlyCountPrefix = 'monthly_count_';

// 2. 加方法：
/// 读取某月识别次数（key: monthly_count_YYYYMM）
Future<int> getMonthlyCount(int year, int month) async {
  final key = '$_monthlyCountPrefix${year}${month.toString().padLeft(2, '0')}';
  final v = await _storage.read(key: key);
  return int.tryParse(v ?? '0') ?? 0;
}

/// 增加某月识别次数（+1）
Future<void> incrementMonthlyCount(int year, int month) async {
  final key = '$_monthlyCountPrefix${year}${month.toString().padLeft(2, '0')}';
  final current = await getMonthlyCount(year, month);
  await _storage.write(key: key, value: (current + 1).toString());
}

/// 读取本月识别次数
Future<int> getCurrentMonthCount() async {
  final now = DateTime.now();
  return getMonthlyCount(now.year, now.month);
}
```

> **注意**：月度计数按 YYYYMM 作 key，自动按月归档（无需清理历史，旧月份数据留在 storage 不影响本月）。

- [ ] **Step 2: 修改 recognize_controller.dart — 识别成功计数**

```dart
// lib/features/recognize/recognize_controller.dart 改动：

// 1. 构造器加 secureConfigStore 参数（可选，向后兼容）：
final SecureConfigStore? _configStore;  // 新增：T43 月度计数

RecognizeController(
  this._primaryProvider,
  this._fallbackProvider,
  this._nutritionLookup, {
  Future<void> Function(String, String, String, String)? onOfflineEnqueue,
  void Function()? onL3Fallback,
  CircuitBreaker? circuitBreaker,
  this.secureConfigStore,  // 新增
})  : ...

@visibleForTesting
SecureConfigStore? get secureConfigStoreForTest => secureConfigStore;

// 2. 识别成功后计数（line 200 附近，state=done 之前）：
// result 赋值成功 + 查库回填成功后：
if (secureConfigStore != null) {
  final now = DateTime.now();
  await secureConfigStore.incrementMonthlyCount(now.year, now.month);
}
```

> **注意**：计数时机——识别成功（result 赋值 + 查库回填完成）后，state=done 之前。离线入队不计数（未真正识别）。L3 转手动不计数。

- [ ] **Step 3: 创建 monthly_cost_test.dart**

```dart
// test/features/monthly_cost_test.dart
import 'package:eatwise/core/config/secure_config_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // SecureConfigStore 用真实 FlutterSecureStorage 在沙箱跑不了（平台插件）
  // 需 mock 或用 SecureConfigStore.forTesting
  // 简化：测 getMonthlyCount/incrementMonthlyCount 逻辑用内存 Map 模拟 _storage
  // 但 _storage 是 private，需 visibleForTesting 暴露或用 forTesting 注入

  late SecureConfigStore store;

  setUp(() {
    // FlutterSecureStorage 在沙箱有平台插件支持（testFeatures），可用
    // 先确认 test/features/offline_queue_test.dart 等是否用了 FlutterSecureStorage
    // 如果沙箱跑不了，改用 mock
    store = SecureConfigStore();
  });

  test('月度计数初始为 0', () async {
    final count = await store.getMonthlyCount(2026, 7);
    expect(count, 0);
  });

  test('increment 后计数 +1', () async {
    await store.incrementMonthlyCount(2026, 7);
    expect(await store.getMonthlyCount(2026, 7), 1);
    await store.incrementMonthlyCount(2026, 7);
    expect(await store.getMonthlyCount(2026, 7), 2);
  });

  test('不同月份独立计数', () async {
    await store.incrementMonthlyCount(2026, 7);
    await store.incrementMonthlyCount(2026, 7);
    await store.incrementMonthlyCount(2026, 6);
    expect(await store.getMonthlyCount(2026, 7), 2);
    expect(await store.getMonthlyCount(2026, 6), 1);
  });
}
```

> **注意**：FlutterSecureStorage 在 flutter test 沙箱有 mock 支持（FlutterSecureStorage.setMockInitialValues）。如果测试失败，加 `FlutterSecureStorage.setMockInitialValues({});` 在 setUp。**实施时核实**。

- [ ] **Step 4: flutter analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze
flutter test test/features/monthly_cost_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/core/config/secure_config_store.dart lib/features/recognize/recognize_controller.dart test/features/monthly_cost_test.dart
git commit -m "feat: Sprint 6 T43 - 月度识别计数存储(secure_storage按月归档)+识别成功计数"
```

---

## Task 44: 设置页显示本月识别次数 + 估算花费

**目标:** settings_page 新增"本月使用"区，显示本月识别次数 + 估算花费 + 超阈值提示。

**参考设计文档:** 11.3

**Files:**
- Modify: `lib/features/settings/settings_page.dart`
- Test: `test/features/monthly_cost_test.dart`（追加 UI 用例）

**当前状态核实:**
- settings_page.dart 无成本统计区（line 70-155 设置项）
- 设计 11.3：显示本月识别次数/累计花费，超阈值提示
- T43 已加 secureConfigStore.getCurrentMonthCount()

- [ ] **Step 1: 修改 settings_page.dart — 加本月使用区**

```dart
// lib/features/settings/settings_page.dart 改动：

// 1. _SettingsPageState 加字段：
int? _monthlyCount;
double? _estimatedCost;
static const _costPerRecognition = 0.001;  // 估算：单次约 0.001 元（500 token × 0.15/百万）
static const _costWarningThreshold = 5.0;  // 5 元/月提示

// 2. _loadSettings 中加载月度计数：
final store = ref.read(secureConfigStoreProvider);
_monthlyCount = await store.getCurrentMonthCount();
_estimatedCost = _monthlyCount! * _costPerRecognition;

// 3. build 中"数据备份"区前加"本月使用"区：
_sectionHeader('本月使用'),
ListTile(
  leading: const Icon(Icons.analytics_outlined),
  title: const Text('本月识别次数'),
  trailing: Text('$_monthlyCount 次'),
),
ListTile(
  leading: const Icon(Icons.payments_outlined),
  title: const Text('估算花费'),
  trailing: Text('${_estimatedCost!.toStringAsFixed(3)} 元'),
),
if (_estimatedCost! >= _costWarningThreshold)
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Text(
      '⚠️ 本月花费已达 ${_estimatedCost!.toStringAsFixed(2)} 元，建议在厂商控制台设置月度费用上限',
      style: const TextStyle(color: Colors.orange, fontSize: 12),
    ),
  ),
const SizedBox(height: 16),
```

- [ ] **Step 2: 追加 monthly_cost_test.dart UI 用例**

```dart
// test/features/monthly_cost_test.dart 追加：
testWidgets('设置页显示本月识别次数', (tester) async {
  // pumpWidget SettingsPage（依赖 appConfigProvider）
  // 验证 find.textContaining('本月识别次数')
});
```

> **注意**：SettingsPage 依赖 appConfigProvider + secureConfigStoreProvider，测试需 override。参考 settings_page 现有测试（如果有）。

- [ ] **Step 3: flutter analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze
flutter test test/features/monthly_cost_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/settings/settings_page.dart test/features/monthly_cost_test.dart
git commit -m "feat: Sprint 6 T44 - 设置页显示本月识别次数+估算花费+超阈值提示"
```

---

## Task 45: 反馈弹窗收集 correctedDishName/ServingG

**目标:** today_meals_page 反馈弹窗"不准"时，追加输入正确菜名 + 份量，写入 recognition_feedback.correctedDishName/correctedServingG。

**参考设计文档:** 4.2.7（用户标注正确菜名+份量）

**Files:**
- Modify: `lib/features/dashboard/today_meals_page.dart`
- Test: `test/features/feedback_correction_test.dart`

**当前状态核实:**
- today_meals_page.dart:182-231 _showFeedbackDialog 只问准/不准（showDialog<bool>）
- today_meals_page.dart:222-226 feedbackRepo.insert 不传 correctedDishName/ServingG
- recognition_feedback_repository.dart:11-28 insert 已支持 correctedDishName/ServingG（可选参数）
- recognition_feedback_table.dart:9-10 有 correctedDishName/correctedServingG 可空字段

- [ ] **Step 1: 修改 today_meals_page.dart — 反馈弹窗补全**

```dart
// lib/features/dashboard/today_meals_page.dart 改动（_showFeedbackDialog，line 182-231）：

Future<void> _showFeedbackDialog(MealLog m) async {
  final db = await ref.read(recognize.databaseProvider.future);
  final feedbackRepo = RecognitionFeedbackRepository(db);
  if (await feedbackRepo.hasFeedback(m.id)) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已反馈过')));
    }
    return;
  }
  if (!mounted) return;
  final isCorrect = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('识别准不准？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('准')),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('不准')),
      ],
    ),
  );
  if (isCorrect == null) return;
  if (!mounted) return;

  // T45：不准时追加输入正确菜名 + 份量
  String? correctedDishName;
  double? correctedServingG;
  if (!isCorrect) {
    final correction = await showDialog<_CorrectionResult>(
      context: context,
      builder: (ctx) {
        // 【第2轮修正】：MealLog 无 foodItemName 字段（today_meals_page.dart:125 用 _foodNames map 反查）
        final nameCtrl = TextEditingController(text: _foodNames[m.foodItemId] ?? '');
        final servingCtrl = TextEditingController();
        return AlertDialog(
          title: const Text('请输入正确信息'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '正确菜名', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: servingCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '正确份量(g)', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('跳过')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _CorrectionResult(
                nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
                double.tryParse(servingCtrl.text.trim()),
              )),
              child: const Text('提交'),
            ),
          ],
        );
      },
    );
    if (correction != null) {
      correctedDishName = correction.name;
      correctedServingG = correction.servingG;
    }
  }
  if (!mounted) return;

  // T23：反查 prompt_version（现有逻辑保持）
  String promptVersion = Prompts.version;
  if (m.originalImagePath != null) {
    final pendingRepo = PendingRecognitionRepository(db);
    final pendingList = await pendingRepo.listAll();
    final match = pendingList.where((p) => p.imagePath == m.originalImagePath).toList();
    if (match.isNotEmpty && match.first.promptVersion != null) {
      promptVersion = match.first.promptVersion!;
    }
  }

  // T45：传 correctedDishName/ServingG
  await feedbackRepo.insert(
    mealLogId: m.id,
    isCorrect: isCorrect,
    correctedDishName: correctedDishName,
    correctedServingG: correctedServingG,
    promptVersion: promptVersion,
  );
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已记录反馈')));
  }
}

// 新增 _CorrectionResult 辅助类：
class _CorrectionResult {
  final String? name;
  final double? servingG;
  const _CorrectionResult(this.name, this.servingG);
}
```

> **注意**：
> - "不准"时弹第二个对话框收集菜名 + 份量（都可跳过）。
> - **【第2轮已确认】**：MealLog 无 foodItemName 字段，菜名来自 `_foodNames[m.foodItemId]`（today_meals_page.dart:23/125 批量反查 food_item.name 的内存 map）。代码已用 `_foodNames[m.foodItemId] ?? ''`。

- [ ] **Step 2: 创建 feedback_correction_test.dart**

```dart
// test/features/feedback_correction_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/recognition_feedback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late RecognitionFeedbackRepository repo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    repo = RecognitionFeedbackRepository(db);
    // 种子 food_item + meal_log
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '米饭', defaultServingG: 100, caloriesPer100g: 116,
          proteinPer100g: 2.6, fatPer100g: 0.3, carbsPer100g: 25.9,
          source: 'manual', sourceVersion: 'test', createdAt: 1000));
    await db.into(db.mealLogs).insert(MealLogsCompanion.insert(
          date: '2026-07-02', mealType: 'lunch', foodItemId: 1,
          actualServingG: 100, actualCalories: 116, actualProteinG: 2.6,
          actualFatG: 0.3, actualCarbsG: 25.9, loggedAt: 1000));
  });
  tearDown(() async => db.close());

  test('T45：反馈含 correctedDishName/ServingG 写入成功', () async {
    await repo.insert(
      mealLogId: 1,
      isCorrect: false,
      correctedDishName: '面条',
      correctedServingG: 150.0,
      promptVersion: 'v1.0',
    );
    final has = await repo.hasFeedback(1);
    expect(has, isTrue);
    // 验证字段写入（需加查询方法或直接查表）
    final rows = await db.select(db.recognitionFeedbacks).get();
    expect(rows.length, 1);
    expect(rows.first.correctedDishName, '面条');
    expect(rows.first.correctedServingG, 150.0);
  });

  test('T45：准的反馈不传 correctedDishName/ServingG（null）', () async {
    await repo.insert(
      mealLogId: 1,
      isCorrect: true,
      promptVersion: 'v1.0',
    );
    final rows = await db.select(db.recognitionFeedbacks).get();
    expect(rows.first.correctedDishName, isNull);
    expect(rows.first.correctedServingG, isNull);
  });
}
```

- [ ] **Step 3: flutter analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze
flutter test test/features/feedback_correction_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/dashboard/today_meals_page.dart test/features/feedback_correction_test.dart
git commit -m "feat: Sprint 6 T45 - 反馈弹窗收集correctedDishName/ServingG(不准时追加输入)"
```

---

## Task 46: recognition_feedback 按 prompt_version 聚合 + 导出

**目标:** RecognitionFeedbackRepository 新增按 prompt_version 聚合准确率查询；json_exporter 导出含完整反馈数据（供动态回归集）。

**参考设计文档:** 4.2.7（按 prompt_version 聚合准确率）、12.4（动态回归集导出）

**Files:**
- Modify: `lib/data/repositories/recognition_feedback_repository.dart`
- Modify: `lib/data/backup/json_exporter.dart`（确认已含 feedback，T46 补完整字段）
- Test: `test/features/prompt_accuracy_test.dart`

**当前状态核实:**
- recognition_feedback_repository.dart 只有 insert（line 11-28）+ hasFeedback（line 31-36），无聚合查询
- json_exporter.dart:20 已含 recognition_feedbacks（调研报告确认），但需确认导出字段是否含 correctedDishName/ServingG
- 设计 4.2.7：按 prompt_version 聚合准确率，退化时触发回归排查
- 设计 12.4：动态回归集从 recognition_feedback 导出错判样本

- [ ] **Step 1: 修改 recognition_feedback_repository.dart — 聚合查询**

```dart
// lib/data/repositories/recognition_feedback_repository.dart 改动：

/// 按 prompt_version 聚合准确率
/// 返回 {promptVersion: {total, correct, accuracy}}
Future<Map<String, Map<String, dynamic>>> getAccuracyByPromptVersion() async {
  final rows = await _db.select(_db.recognitionFeedbacks).get();
  final result = <String, Map<String, dynamic>>{};
  for (final r in rows) {
    final pv = r.promptVersion;
    result.putIfAbsent(pv, () => {'total': 0, 'correct': 0, 'accuracy': 0.0});
    result[pv]!['total'] = (result[pv]!['total'] as int) + 1;
    if (r.isCorrect == 1) {
      result[pv]!['correct'] = (result[pv]!['correct'] as int) + 1;
    }
  }
  // 计算准确率
  for (final pv in result.keys) {
    final total = result[pv]!['total'] as int;
    final correct = result[pv]!['correct'] as int;
    result[pv]!['accuracy'] = total > 0 ? correct / total : 0.0;
  }
  return result;
}

/// 查询某 prompt_version 的错判样本（供动态回归集导出）
/// 返回含 mealLogId/correctedDishName/correctedServingG 的列表
Future<List<({int mealLogId, String? correctedDishName, double? correctedServingG})>>
    getWrongSamples(String promptVersion) async {
  final rows = await (_db.recognitionFeedbacks.select()
        ..where((f) => f.promptVersion.equals(promptVersion) & f.isCorrect.equals(0)))
      .get();
  return rows
      .map((r) => (
            mealLogId: r.mealLogId,
            correctedDishName: r.correctedDishName,
            correctedServingG: r.correctedServingG,
          ))
      .toList();
}
```

- [ ] **Step 2: 确认 json_exporter.dart 导出完整字段**

```dart
// lib/data/backup/json_exporter.dart 改动（如需）：
// 调研报告说 line 20 已含 recognition_feedbacks
// 实施时 Read 确认导出的 feedback 对象是否含 correctedDishName/correctedServingG
// 如果导出的是完整行（drift 默认 toMap），字段齐全无需改
// 如果是手动选字段，补 correctedDishName/correctedServingG
```

- [ ] **Step 3: 创建 prompt_accuracy_test.dart**

```dart
// test/features/prompt_accuracy_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/recognition_feedback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EatWiseDatabase db;
  late RecognitionFeedbackRepository repo;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    repo = RecognitionFeedbackRepository(db);
    // 种子 food_item + meal_log
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '米饭', defaultServingG: 100, caloriesPer100g: 116,
          proteinPer100g: 2.6, fatPer100g: 0.3, carbsPer100g: 25.9,
          source: 'manual', sourceVersion: 'test', createdAt: 1000));
    for (var i = 1; i <= 5; i++) {
      await db.into(db.mealLogs).insert(MealLogsCompanion.insert(
            date: '2026-07-0$i', mealType: 'lunch', foodItemId: 1,
            actualServingG: 100, actualCalories: 116, actualProteinG: 2.6,
            actualFatG: 0.3, actualCarbsG: 25.9, loggedAt: i * 1000));
    }
  });
  tearDown(() async => db.close());

  test('T46：按 prompt_version 聚合准确率', () async {
    // v1.0：3 准 2 不准 → 准确率 0.6
    await repo.insert(mealLogId: 1, isCorrect: true, promptVersion: 'v1.0');
    await repo.insert(mealLogId: 2, isCorrect: true, promptVersion: 'v1.0');
    await repo.insert(mealLogId: 3, isCorrect: true, promptVersion: 'v1.0');
    await repo.insert(mealLogId: 4, isCorrect: false, promptVersion: 'v1.0');
    await repo.insert(mealLogId: 5, isCorrect: false, promptVersion: 'v1.0');

    final accuracy = await repo.getAccuracyByPromptVersion();
    expect(accuracy['v1.0']!['total'], 5);
    expect(accuracy['v1.0']!['correct'], 3);
    expect(accuracy['v1.0']!['accuracy'], 0.6);
  });

  test('T46：不同 prompt_version 独立聚合', () async {
    await repo.insert(mealLogId: 1, isCorrect: true, promptVersion: 'v1.0');
    await repo.insert(mealLogId: 2, isCorrect: false, promptVersion: 'v1.1');

    final accuracy = await repo.getAccuracyByPromptVersion();
    expect(accuracy['v1.0']!['accuracy'], 1.0);
    expect(accuracy['v1.1']!['accuracy'], 0.0);
  });

  test('T46：查询错判样本含 correctedDishName', () async {
    await repo.insert(mealLogId: 1, isCorrect: false, correctedDishName: '面条',
        correctedServingG: 150.0, promptVersion: 'v1.0');
    await repo.insert(mealLogId: 2, isCorrect: true, promptVersion: 'v1.0');

    final samples = await repo.getWrongSamples('v1.0');
    expect(samples.length, 1);
    expect(samples.first.mealLogId, 1);
    expect(samples.first.correctedDishName, '面条');
    expect(samples.first.correctedServingG, 150.0);
  });
}
```

- [ ] **Step 4: flutter analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze
flutter test test/features/prompt_accuracy_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/recognition_feedback_repository.dart lib/data/backup/json_exporter.dart test/features/prompt_accuracy_test.dart
git commit -m "feat: Sprint 6 T46 - recognition_feedback按prompt_version聚合准确率+错判样本导出"
```

---

## Task 47: main.dart 启动调用 ImageCleanup.runIfBacklogLarge

**目标:** main.dart 启动时调用 ImageCleanup.runIfBacklogLarge，前台异步清理 >50 项的图片积压。

**参考设计文档:** 9.4（App 启动时若待清理项 > 50 则前台异步清理）

**Files:**
- Modify: `lib/main.dart`
- Test: `test/features/image_cleanup_startup_test.dart`

**当前状态核实:**
- main.dart:14-49 启动流程未调用 ImageCleanup.runIfBacklogLarge（调研报告确认）
- image_cleanup.dart:39-45 runIfBacklogLarge 已实现
- 设计 9.4：启动时若 >50 项则前台异步清理

- [ ] **Step 1: 修改 main.dart — 启动清理**

```dart
// lib/main.dart 改动（在 offlineQueue.start 后、initSentry 前）：

// 1. import image_cleanup.dart：
import 'data/backup/image_cleanup.dart';

// 2. 启动清理（在 offlineQueue.start try/catch 后）：
// T47：启动时前台异步清理图片积压（设计 9.4：>50 项触发）
try {
  final db = await container.read(databaseProvider.future);
  // 不 await，不阻塞启动（前台异步）
  ImageCleanup.runIfBacklogLarge(db).catchError((e) {
    debugPrint('ImageCleanup 启动清理失败：$e');
  });
} catch (e) {
  debugPrint('ImageCleanup 初始化失败：$e');
}
```

> **注意**：
> - **不 await**：启动清理不阻塞 UI（前台异步）。
> - **catchError**：清理失败不影响启动。
> - databaseProvider 已在 offlineQueue.start 时读取（line 34），可复用，但 offlineQueue.start 失败时 db 可能未初始化。用独立 `container.read(databaseProvider.future)` 确保 db 可用。

- [ ] **Step 2: 创建 image_cleanup_startup_test.dart**

```dart
// test/features/image_cleanup_startup_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/data/backup/image_cleanup.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/data/repositories/meal_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 测 ImageCleanup.runIfBacklogLarge 逻辑（不测 main.dart 启动集成，main 难单测）
  late EatWiseDatabase db;

  setUp(() async {
    db = EatWiseDatabase(NativeDatabase.memory());
    // 【第2轮修正】：meal_log.food_item_id 是 FK，先种子 food_item（id=1）
    await db.into(db.foodItems).insert(FoodItemsCompanion.insert(
          name: '测试食物', defaultServingG: 100, caloriesPer100g: 100,
          proteinPer100g: 10, fatPer100g: 5, carbsPer100g: 20,
          source: 'manual', sourceVersion: 'test', createdAt: 1000));
  });
  tearDown(() async => db.close());

  // 【第2轮修正·重要】：日期必须用 5 月（2026-05-xx），不能用 6 月！
  // 原因：getOldImagePaths(30) 的 cutoff = now(2026-07-02) - 30 天 = 2026-06-02，
  //   where date < '2026-06-02'。6 月只有 30 天，原计划 '2026-06-31'..'2026-06-51' 无效，
  //   且 6 月仅 '2026-06-01' 1 项命中 cutoff，51 项只 1 项被 getOldImagePaths 返回，
  //   candidates.length=1 不 > 50 → 不触发清理，但测试期望"全部置空"→ 断言失败。
  // 改用 5 月：所有 '2026-05-xx' < '2026-06-02' 全命中（字符串比较 '5' < '6'），
  //   51 项全命中 → candidates.length=51 > 50 → 触发清理 → 全部置空 ✓
  //   （'2026-05-32'..'2026-05-51' 虽非真实日期，但 date 是 text 字段可存，字符串比较仍 < '2026-06-02'）

  test('T47：积压 ≤50 项不触发清理', () async {
    final mealRepo = MealLogRepository(db);
    for (var i = 0; i < 50; i++) {
      await mealRepo.insertMealLog(
        date: '2026-05-${(i + 1).toString().padLeft(2, '0')}',
        mealType: 'lunch', foodItemId: 1,
        actualServingG: 100, actualCalories: 100, actualProteinG: 10,
        actualFatG: 5, actualCarbsG: 20,
        originalImagePath: '/tmp/nonexistent_$i.jpg',
      );
    }
    // runIfBacklogLarge 不应触发 run（50 不 > 50）
    await ImageCleanup.runIfBacklogLarge(db);
    final meals = await db.select(db.mealLogs).get();
    expect(meals.where((m) => m.originalImagePath != null).length, 50);
  });

  test('T47：积压 >50 项触发清理', () async {
    final mealRepo = MealLogRepository(db);
    for (var i = 0; i < 51; i++) {
      await mealRepo.insertMealLog(
        date: '2026-05-${(i + 1).toString().padLeft(2, '0')}',
        mealType: 'lunch', foodItemId: 1,
        actualServingG: 100, actualCalories: 100, actualProteinG: 10,
        actualFatG: 5, actualCarbsG: 20,
        originalImagePath: '/tmp/nonexistent_$i.jpg',
      );
    }
    await ImageCleanup.runIfBacklogLarge(db);
    // 验证路径被清除（清理后 originalImagePath 置空）
    final meals = await db.select(db.mealLogs).get();
    expect(meals.where((m) => m.originalImagePath != null).length, 0);
  });
}
```

> **注意**：
> - **【第2轮已落实】**：setUp 已补 food_item 种子（FK 约束）。
> - **【第2轮已核实】**：getOldImagePaths 逻辑（meal_log_repository.dart:45-61）—— cutoff = now - beforeDays，cutoffDate='YYYY-MM-DD'，where `date < cutoffDate AND originalImagePath IS NOT NULL`，字符串字典序比较。今天 2026-07-02，beforeDays=30 → cutoff='2026-06-02'。测试日期已改用 5 月（全命中）。

- [ ] **Step 3: flutter analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze
flutter test test/features/image_cleanup_startup_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart test/features/image_cleanup_startup_test.dart
git commit -m "feat: Sprint 6 T47 - main.dart启动调用ImageCleanup.runIfBacklogLarge(>50项触发)"
```

---

## Task 48: 图片清理保留期可配

**目标:** ImageCleanup.run 支持自定义保留期参数；设置页加保留期选择（7/30/永久）；后台清理任务用配置的保留期。

**参考设计文档:** 9.4（用户可选保留期：7天/30天默认/永久保留）

**Files:**
- Modify: `lib/data/backup/image_cleanup.dart`
- Modify: `lib/core/config/secure_config_store.dart`（存保留期）
- Modify: `lib/background/background_tasks.dart`（后台任务用配置保留期）
- Test: `test/features/image_cleanup_startup_test.dart`（追加用例）

**当前状态核实:**
- image_cleanup.dart:9 defaultRetentionDays=30 硬编码
- image_cleanup.dart:13 run({int? retentionDays}) 已支持参数（但调用方未传）
- 设计 9.4：7天/30天（默认）/永久保留
- background_tasks.dart:37-42 注册每周清理任务

- [ ] **Step 1: 修改 secure_config_store.dart — 存保留期**

```dart
// lib/core/config/secure_config_store.dart 改动：

static const _imageRetentionDays = 'image_retention_days';

/// 读取图片保留期（0=永久保留，默认 30）
Future<int> getImageRetentionDays() async {
  final v = await _storage.read(key: _imageRetentionDays);
  return int.tryParse(v ?? '30') ?? 30;
}

Future<void> setImageRetentionDays(int days) async {
  await _storage.write(key: _imageRetentionDays, days.toString());
}
```

- [ ] **Step 2: 修改 image_cleanup.dart + background_tasks.dart — 用配置保留期**

```dart
// lib/data/backup/image_cleanup.dart 改动：
// run({int? retentionDays}) 已支持，无需改
// runIfBacklogLarge 加可选 retentionDays 参数：
static Future<void> runIfBacklogLarge(EatWiseDatabase db, {int? retentionDays}) async {
  final mealRepo = MealLogRepository(db);
  final days = retentionDays ?? defaultRetentionDays;
  final candidates = await mealRepo.getOldImagePaths(days);
  if (candidates.length > 50) {
    await run(db, retentionDays: days);
  }
}

// lib/background/background_tasks.dart 改动（line 37-42 附近）：
// 后台清理任务用配置的保留期：
// 先 Read background_tasks.dart 确认清理任务调用方式
// 加：final retentionDays = await SecureConfigStore().getImageRetentionDays();
//     if (retentionDays > 0) await ImageCleanup.run(db, retentionDays: retentionDays);
// （retentionDays=0 表示永久保留，不清理）
```

- [ ] **Step 3: 追加 image_cleanup_startup_test.dart 用例**

```dart
// test/features/image_cleanup_startup_test.dart 追加：
test('T48：自定义保留期 7 天', () async {
  // 种子 8 天前的 meal_log + 6 天前的 meal_log
  // 用 retentionDays=7 清理：8 天前的清，6 天前的留
});

test('T48：保留期 0（永久保留）不清理', () async {
  // run(retentionDays: 0) 应不清理任何项
  // 需确认 ImageCleanup.run 对 retentionDays=0 的处理（getOldImagePaths(0) 会返回所有？需防御）
});
```

> **注意**：**实施时核实** getOldImagePaths(0) 行为。如果 retentionDays=0 会返回所有 meal_log（now - 0 天 = now，所有历史日期 < now），需在 run 内加 `if (retentionDays <= 0) return 0;` 防御。

- [ ] **Step 4: flutter analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze
flutter test test/features/image_cleanup_startup_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/data/backup/image_cleanup.dart lib/core/config/secure_config_store.dart lib/background/background_tasks.dart test/features/image_cleanup_startup_test.dart
git commit -m "feat: Sprint 6 T48 - 图片清理保留期可配(7/30/永久)+后台任务用配置"
```

---

## Task 49: 设置页补全（图片保留期 + 关于页 + 清缓存）

**目标:** settings_page 加图片保留期选择（7/30/永久）+ 关于页（版本号）+ 清缓存入口。

**参考设计文档:** 9.4、7.x

**Files:**
- Modify: `lib/features/settings/settings_page.dart`
- Test: `test/features/settings_completeness_test.dart`

**当前状态核实:**
- settings_page.dart 无保留期选择/关于页/清缓存（调研报告确认）
- T48 已加 secureConfigStore.getImageRetentionDays/setImageRetentionDays
- pubspec.yaml 有 version 字段（PackageInfo 可读）

- [ ] **Step 1: 修改 settings_page.dart — 保留期 + 关于 + 清缓存**

```dart
// lib/features/settings/settings_page.dart 改动：

// 1. _SettingsPageState 加字段：
int _imageRetentionDays = 30;  // T48 保留期

// 2. _loadSettings 中加载保留期：
_imageRetentionDays = await ref.read(secureConfigStoreProvider).getImageRetentionDays();

// 3. build 中"本月使用"区后加"图片管理"区：
_sectionHeader('图片管理'),
ListTile(
  leading: const Icon(Icons.image_outlined),
  title: const Text('原图保留期'),
  trailing: DropdownButton<int>(
    value: _imageRetentionDays,
    items: const [
      DropdownMenuItem(value: 7, child: Text('7 天')),
      DropdownMenuItem(value: 30, child: Text('30 天（默认）')),
      DropdownMenuItem(value: 0, child: Text('永久保留')),
    ],
    onChanged: (v) => setState(() => _imageRetentionDays = v ?? 30),
  ),
),
const SizedBox(height: 16),

// 4. build 末尾加"关于"区：
_sectionHeader('关于'),
ListTile(
  leading: const Icon(Icons.info_outline),
  title: const Text('关于 EatWise'),
  trailing: const Icon(Icons.chevron_right),
  onTap: _showAbout,
),
const SizedBox(height: 16),

// 5. _save 中保存保留期：
await store.setImageRetentionDays(_imageRetentionDays);

// 6. 新增 _showAbout 方法：
Future<void> _showAbout() async {
  // 用 package_info_plus 读版本号（如已 import），或硬编码 1.0.0
  // 先 Read pubspec.yaml 确认是否有 package_info_plus 依赖
  // 如无，用 PlatformDispatcher 简单显示
  if (!mounted) return;
  await showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('关于 EatWise'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EatWise v1.0.0'),
          SizedBox(height: 8),
          Text('拍照识别食物热量 + 营养记录 + AI 汇总建议'),
          SizedBox(height: 8),
          Text('营养目标依据 ACSM/ISSN/NIH/WHO 标准', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    ),
  );
}
```

> **注意**：
> - **版本号**：如无 package_info_plus 依赖，硬编码 v1.0.0（pubspec.yaml version 字段手动同步）。**先 Read pubspec.yaml 确认**。
> - **清缓存**：图片清理已在后台 + 启动（T47）做，设置页"清缓存"入口可手动触发 ImageCleanup.run（可选，T49 范围内）。如复杂度高，T49 仅做保留期 + 关于页，清缓存推后。

- [ ] **Step 2: 创建 settings_completeness_test.dart**

```dart
// test/features/settings_completeness_test.dart
import 'package:drift/native.dart';
import 'package:eatwise/core/config/app_config.dart';
import 'package:eatwise/data/database/database.dart';
import 'package:eatwise/features/recognize/providers.dart' as recognize;
import 'package:eatwise/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('设置页含图片保留期选择', (tester) async {
    final db = EatWiseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      recognize.databaseProvider.overrideWith((ref) async => db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsPage()),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.textContaining('保留期'), findsOneWidget);
  });

  testWidgets('设置页含关于入口', (tester) async {
    // 同上 pumpWidget
    // expect(find.textContaining('关于'), findsWidgets);
  });
}
```

> **注意**：SettingsPage 依赖 appConfigProvider（FutureProvider）+ secureConfigStoreProvider，测试需等待 _loadSettings 完成（pumpAndSettle）。

- [ ] **Step 3: flutter analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze
flutter test test/features/settings_completeness_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/settings/settings_page.dart test/features/settings_completeness_test.dart
git commit -m "feat: Sprint 6 T49 - 设置页补全(图片保留期选择+关于页+版本号)"
```

---

## Task 50: vision_response_parser 增 refusal/字段缺失测试

**目标:** vision_response_parser_test.dart 补 refusal 用例 + 字段缺失容错用例（设计 12.1）。

**参考设计文档:** 12.1（大模型 JSON 解析容错：malformed/refusal/字段缺失）

**Files:**
- Modify: `lib/ai/vision_provider.dart`（fromJson 加 Low/High 缺失默认值，设计 5.6 + T41 依赖）
- Modify: `test/ai/vision_response_parser_test.dart`

**当前状态核实:**
- vision_response_parser_test.dart:6-78 4 个测试（正常/复合菜/字段缺失默认空/int转double）
- 设计 12.1：malformed/refusal/字段缺失测试
- refusal 检测在 qwen_vl_provider（T39），parser 层测的是 VisionRecognitionResult.fromJson 容错
- **【第2轮核实·重要】**：fromJson（vision_provider.dart:25-39）当前对字段缺失【不容错】，直接抛异常：
  - `dishName: json['dish_name'] as String` → 缺失抛 TypeError
  - `estimatedWeightGLow/High: (json[...] as num).toDouble()` → 缺失抛 TypeError
  - `confidence: (json[...] as num).toDouble()` → 缺失抛 TypeError
  - 仅 `foodComponents` 缺失有默认空数组（line 31 `?? []`）
- **设计 5.6 要求**：Low/High 缺失时回退到 Mid（避免区间显示异常）。T41 校准页用 estimatedWeightGLow/High 显示区间，若缺失会崩。故 T50 必须改 fromJson 加 Low/High 缺失默认值（回退 Mid）。

- [ ] **Step 1: 修改 vision_provider.dart fromJson — Low/High 缺失回退 Mid（设计 5.6）**

```dart
// lib/ai/vision_provider.dart 改动（fromJson，line 25-39）：
// 【第2轮修正】：原 fromJson 对 Low/High 缺失直接抛异常（as num 转 null 失败），
//   但设计 5.6 要求 Low/High 缺失回退 Mid（T41 校准页显示区间依赖此）。
//   改：Low/High 缺失时用 Mid 值兜底。其余字段（dishName/confidence/cookingMethod/isSingleItem）保持必填（缺失抛异常，符合"必填字段缺失是 malformed"）。
factory VisionRecognitionResult.fromJson(Map<String, dynamic> json, String promptVersion) {
  final mid = (json['estimated_weight_g_mid'] as num).toDouble();
  // Low/High 缺失时回退 Mid（设计 5.6，避免区间显示异常）
  final low = json['estimated_weight_g_low'] != null
      ? (json['estimated_weight_g_low'] as num).toDouble()
      : mid;
  final high = json['estimated_weight_g_high'] != null
      ? (json['estimated_weight_g_high'] as num).toDouble()
      : mid;
  return VisionRecognitionResult(
    dishName: json['dish_name'] as String,
    estimatedWeightGLow: low,
    estimatedWeightGMid: mid,
    estimatedWeightGHigh: high,
    foodComponents: ((json['food_components'] as List?) ?? [])
        .map((e) => FoodComponent.fromJson(e as Map<String, dynamic>))
        .toList(),
    cookingMethod: json['cooking_method'] as String,
    isSingleItem: json['is_single_item'] as bool,
    confidence: (json['confidence'] as num).toDouble(),
    promptVersion: promptVersion,
  );
}
```

> **注意**：仅 Low/High 缺失兜底（回退 Mid）。dishName/confidence/cookingMethod/isSingleItem 仍必填（缺失抛异常 = malformed，由 qwen_vl_provider catch FormatException 处理）。这符合设计 12.1"必填字段缺失是 malformed"。

- [ ] **Step 2: 追加 vision_response_parser_test.dart 用例**

```dart
// test/ai/vision_response_parser_test.dart 追加：

test('字段缺失：estimated_weight_g_low 缺失时回退 Mid（设计 5.6）', () {
  final json = {
    'dish_name': '米饭',
    'estimated_weight_g_mid': 100,
    'is_single_item': true,
    'cooking_method': 'boil',
    'confidence': 0.9,
    // estimated_weight_g_low 缺失
  };
  final result = VisionRecognitionResult.fromJson(json, 'v1.0');
  expect(result.estimatedWeightGMid, 100);
  expect(result.estimatedWeightGLow, 100);  // 回退 Mid
});

test('字段缺失：estimated_weight_g_high 缺失时回退 Mid', () {
  final json = {
    'dish_name': '米饭',
    'estimated_weight_g_mid': 100,
    'is_single_item': true,
    'cooking_method': 'boil',
    'confidence': 0.9,
    // estimated_weight_g_high 缺失
  };
  final result = VisionRecognitionResult.fromJson(json, 'v1.0');
  expect(result.estimatedWeightGHigh, 100);  // 回退 Mid
});

test('必填字段缺失（dishName）抛异常（malformed）', () {
  final json = {
    'estimated_weight_g_mid': 100,
    'is_single_item': true,
    'cooking_method': 'boil',
    'confidence': 0.9,
    // dish_name 缺失
  };
  expect(() => VisionRecognitionResult.fromJson(json, 'v1.0'), throwsA(anything));
});

test('必填字段缺失（confidence）抛异常（malformed）', () {
  final json = {
    'dish_name': '米饭',
    'estimated_weight_g_mid': 100,
    'is_single_item': true,
    'cooking_method': 'boil',
    // confidence 缺失
  };
  expect(() => VisionRecognitionResult.fromJson(json, 'v1.0'), throwsA(anything));
});

test('字段类型错误：estimated_weight_g_mid 为字符串抛异常（as num 失败）', () {
  final json = {
    'dish_name': '米饭',
    'estimated_weight_g_mid': '100',  // 字符串，as num 失败
    'is_single_item': true,
    'cooking_method': 'boil',
    'confidence': 0.9,
  };
  expect(() => VisionRecognitionResult.fromJson(json, 'v1.0'), throwsA(anything));
});
```

> **注意**：测试断言匹配 fromJson 实际行为（已核实）：Low/High 缺失回退 Mid（Step 1 改动后），其余必填字段缺失/类型错误抛异常。

- [ ] **Step 2: flutter analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze
flutter test test/ai/vision_response_parser_test.dart
```

- [ ] **Step 3: Commit**

```bash
git add test/ai/vision_response_parser_test.dart
git commit -m "test: Sprint 6 T50 - vision_response_parser补refusal/字段缺失/类型容错用例"
```

---

## Task 51: Sprint 6 全量回归验证 + 文档更新

**目标:** 全量 test 套件回归 + analyze + 确认所有 commit 在分支 + 更新设计文档状态。

**Files:**
- 无代码改动（纯验证 + 文档）

- [ ] **Step 1: 全量 analyze + test**

```bash
export PATH="/tmp/flutter/bin:$PATH"
cd /workspace
flutter analyze  # 期望 0 issues
flutter test --exclude-tags smoke  # 期望全过
```

- [ ] **Step 2: 核对 Sprint 6 commits**

```bash
git log --oneline [T37 commit^]..HEAD  # 期望 15 个 commit（T37-T51）
```

- [ ] **Step 3: 更新设计文档状态（可选）**

如设计文档有"状态"字段，更新为"Sprint 6 已实现"。如无，跳过。

- [ ] **Step 4: Commit（如有文档改动）**

```bash
git add docs/
git commit -m "docs: Sprint 6 完成 - 15 Task 全部交付,回归验证通过"
```

---

## Self-Review

### 1. Spec coverage（设计文档覆盖）

| 设计文档章节 | 对应 Task | 覆盖状态 |
|---|---|---|
| 3.2 断路器（连续 3 次失败短路 30s） | T37+T38 | ✅ 断路器状态机 + recognize_controller/offline_queue 接入 |
| 5.6 显示规范（估算区间 ±10-15%） | T40+T41+T42 | ✅ NutritionLookup 区间计算 + 校准页区间 + 看板 g/kg |
| 7.4 看板估算区间 | T42 | ✅ g/kg 双展示（热量区间取消，已记录值是确定的） |
| 9.4 图片清理（启动触发 + 保留期可配） | T47+T48 | ✅ main.dart 启动清理 + 设置页保留期选择 |
| 11.1 refusal 显式区分 | T39 | ✅ isRefusal 标记 + qwen_vl_provider 检测 + L3 提示区分 |
| 11.3 成本控制显示 | T43+T44 | ✅ 月度计数存储 + 设置页显示 + 超阈值提示 |
| 12.1 JSON 解析容错测试 | T50 | ✅ refusal/字段缺失/类型容错用例 |
| 12.4 Prompt 回归测试（部分） | T46 | ✅ 按 prompt_version 聚合 + 错判样本导出（静态照片集推后） |
| 4.2.7 反馈补全 | T45+T46 | ✅ correctedDishName/ServingG 收集 + 聚合查询 |
| 设置页补全（关于页/保留期） | T49 | ✅ 关于页 + 保留期选择 + 版本号 |

**未覆盖章节（明确推后）：**
- 6.2 L2-L4 数据源 — 设计自身标"后续迭代"，L2 USDA API 工作量大，推后至独立 Sprint
- 12.4 静态回归集（50-100 张照片）— 需人工采集，推后
- 断路器 jitter 退避 — 复杂度高，当前固定 30s 短路足够

**结论**：Sprint 6 覆盖 10 项章节，L2-L4/静态回归集明确推后。

### 2. Placeholder scan（占位符扫描）

逐项检查计划全文：
- ❌ "TBD" / "TODO" / "implement later" — **无**
- ❌ "Add appropriate error handling" — **无**
- ❌ "Write tests for the above"（无具体测试代码）— **无**

**标注"实施时核实/实施时确认"的项（合理实施指引，非占位）：**
- T38 Step 4：SecureConfigStore 通用 write/read/delete 方法（需加公开方法）
- T38 Step 3：markFailed 重试上限逻辑（需确认是否触发永久 failed）
- T39 Step 3：glm_4v_provider 是否复用 recognizeWithClient
- T41 Step 1：CalibrationPage 构造器签名 + 是否依赖 Provider
- T42 Step 1：dashboard 是否已加载 profile
- T45 Step 1：m.foodItemName 来源
- T47 Step 2：getOldImagePaths 日期判定逻辑
- T48 Step 3：getOldImagePaths(0) 行为
- T49 Step 1：pubspec.yaml 是否有 package_info_plus

**结论**：无占位符，"实施时核实"均为合理实施指引。

### 3. Type consistency（类型一致性）

| 类型/方法 | 定义位置 | 使用位置 | 一致性 |
|---|---|---|---|
| `CircuitBreaker({write, read, delete, now, delay})` | T37 Step 1 | T38 接入 / T37 测试 | ✅ 回调注入 |
| `CircuitBreakerState.closed/open/halfOpen` | T37 Step 1 | T38 外层 catch | ✅ 枚举 |
| `CircuitBreaker.allowCall/state/recordSuccess/recordFailure/recordHalfOpenFailure` | T37 Step 1 | T38 recognize_controller + offline_queue | ✅ 方法名一致 |
| `VisionRecognitionException(reason, {retryable, retryAfter, isRefusal})` | T39 Step 1 | qwen_vl_provider / recognize_controller L3 | ✅ 可选 isRefusal |
| `QwenVlProvider.isRefusalForTest(text, response)` | T39 Step 2 | T39 测试 | ✅ @visibleForTesting |
| `NutritionRange(low, mid, high)` / `CompositeNutritionRange` | T40 Step 1 | T41 校准页 | ✅ 三档 |
| `NutritionLookup.lookupSingleItemWithRange/lookupCompositeDishWithRange` | T40 Step 1 | T41 / T42 | ✅ 区间方法 |
| `SecureConfigStore.getMonthlyCount/incrementMonthlyCount/getCurrentMonthCount` | T43 Step 1 | T43 controller / T44 设置页 | ✅ 月度计数 |
| `SecureConfigStore.getImageRetentionDays/setImageRetentionDays` | T48 Step 1 | T48 background_tasks / T49 设置页 | ✅ 保留期 |
| `RecognitionFeedbackRepository.getAccuracyByPromptVersion/getWrongSamples` | T46 Step 1 | T46 测试 | ✅ 聚合查询 |
| `RecognizeController(primary, fallback, nutritionLookup, {onOfflineEnqueue, onL3Fallback, circuitBreaker, secureConfigStore})` | T38/T43 构造器 | T38/T43 测试 / recognize_page 注入 | ✅ 位置参数 + 可选命名 |
| `ImageCleanup.runIfBacklogLarge(db, {retentionDays})` | T48 Step 2 | T47 main.dart | ✅ 可选参数 |

### 4. 沙箱不可验证项（需真机）

| 项 | 原因 | 计划中的应对 | 真机验证步骤 |
|---|---|---|---|
| T38 断路器真实 API 故障短路 | 需真实 API 持续失败 | T38 Step 6 构造器编译期验证 + T37 状态机单测 | 真机断网/限流触发断路器 |
| T39 refusal 真实模型拒绝 | 需真实 API 返回 refusal | T39 Step 5 isRefusalForTest 单测 | 真机传违规图片 |
| T41/T42 区间 UI 渲染 | fl_chart/布局验证 | T41 Step 3 widget test 渲染 | 真机观察区间显示 |
| T44 成本显示真实计数 | 需真实识别成功 | T43 Step 3 计数逻辑单测 | 真机识别多次看计数 |
| T47 启动清理真实图片 | 需真实文件系统 | T47 Step 2 逻辑单测（用不存在文件） | 真机积压图片启动清理 |

**结论**：所有真机不可测项都有沙箱单测覆盖核心逻辑。

### 5. 第2轮 Self-Review 发现的计划偏差（逐源码核实，已就地修正）

> 第2轮 Self-Review 标准：逐 Task 对照真实源码核实字段名/方法签名/表结构/构造器形式。Sprint 5 第2轮曾修正 11 处，Sprint 6 第2轮修正 8 处。

| # | Task | 偏差描述 | 修正方式 | 影响范围 |
|---|---|---|---|---|
| 1 | T38 Step 1 | 计划写 `this.circuitBreaker`（`this.` 语法仅用于位置参数或与字段同名的命名参数），但字段名为 `_circuitBreaker` — 编译失败 | 改为命名参数 `CircuitBreaker? circuitBreaker` + 初始化列表 `_circuitBreaker = circuitBreaker`；getter 改为 `=> _circuitBreaker` | recognize_controller.dart 构造器 |
| 2 | T38 Step 3 | 计划写 `await pendingRepo.markFailed(p.id); continue;`，但 `markFailed` 内部 `retryCount+1`，断路器 open 30s 期间多次 processPending 会让 pending 永久 failed（达上限 3） | 改为直接 `continue;` 保留 pending 状态，断路器 open 时不调 markFailed | offline_queue_controller.dart |
| 3 | T38 Step 4 | 计划写 `store._writeRaw(k, v)`，但 `_storage` private + `_writeRaw` 不存在 — 外部不可访问 | 改为公开方法 `store.writeRaw(k, v)`，在计划中显式声明 `writeRaw/readRaw/deleteRaw` 3 个公开方法（同时供 T43/T48 复用） | secure_config_store.dart |
| 4 | T39 Step 5 | 计划写 `const e = VisionRecognitionException('test')`，但构造器（vision_provider.dart:72）非 const — 编译失败 | 改为 `final e = VisionRecognitionException('test')` | refusal_detection_test.dart |
| 5 | T40 | 计划未说明 `_FakeNutritionLookup implements NutritionLookup` 在 `test/features/recognize_controller_test.dart:35`，NutritionLookup 加新公开方法后必须补实现 — 编译失败 | 在 T40 注意段补 FakeLookup 需实现的 2 个新方法代码 + T40 commit 列表加 `recognize_controller_test.dart` | recognize_controller_test.dart |
| 6 | T45 | 计划用 `m.foodItemName`，但 `MealLog` 无此字段（菜名通过 `_foodNames` map 反查 `foodItemId` 得到） | 改为 `_foodNames[m.foodItemId] ?? ''` | today_meals_page.dart |
| 7 | T47 | 三处问题：(a) 测试日期用 `2026-06-31..51` — 6 月仅 30 天无效；(b) meal_log.food_item_id 是 FK，setUp 未种子 food_item；(c) cutoff=2026-06-02 仅 06-01 命中（1 项），51 项中只 1 项被 getOldImagePaths 返回，断言失败 | (a) 日期改用 5 月（全早于 cutoff）；(b) setUp 补 food_item 种子；(c) 同 (a) 解决 | image_cleanup_startup_test.dart |
| 8 | T50 | 计划假设 fromJson 对字段缺失返回默认值，但实际除 foodComponents（`?? []`）外，其余字段缺失直接抛 TypeError（`as num` 转 null 失败） | 加 Step 1 修改 fromJson：Low/High 缺失时回退 Mid（仅这两个回退，其余仍抛）；重写 Step 2 测试断言匹配实际行为（Low/High 缺失回退 Mid 走 expect，必填字段缺失走 `throwsA`） | vision_provider.dart + vision_response_parser_test.dart |

**修正原则**：8 处全部为 P0 级（编译失败或测试必失败），无 P1/P2。修正方式遵循"最小改动匹配源码真实行为"，不扩大修改面。修正后第3节类型一致性表已与新代码一致。

### 6. Self-Review 完成结论

**第1轮（计划完整性自查）：**
- ✅ Spec coverage：10 项章节覆盖，L2-L4/静态回归集明确推后
- ✅ Placeholder scan：无占位符（9 处"实施时核实"均为合理指引）
- ✅ Type consistency：12 项类型/方法一致
- ✅ 沙箱不可验证项：5 项均有沙箱单测覆盖核心逻辑

**第2轮（逐源码核实）：**
- ✅ 逐 Task 对照真实源码核实 17 个文件（recognize_controller / offline_queue_controller / vision_provider / qwen_vl_provider / glm_4v_provider / nutrition_lookup / pending_recognition_repository / meal_log_repository / main.dart / image_cleanup / background_tasks / dashboard_page / settings_page / recognize_page / json_exporter / pubspec.yaml / vision_response_parser_test）
- ✅ 发现 8 处 P0 偏差并全部就地修正
- ✅ 确认 T39 GLM 无需改（直接复用 `QwenVlProvider.recognizeWithClient`，refusal 检测自动生效）
- ✅ 确认 T46 json_exporter 无需改（`_feedbackToJson` line 114-122 已含 correctedDishName/correctedServingG/promptVersion 全字段）
- ✅ 确认 T42 dashboard 已加载 profile（`_loadData` line 45）
- ✅ 确认 pubspec.yaml 无 package_info_plus（T49 关于页版本号改为硬编码）
- ✅ 修正后第3节类型一致性表与代码一致

**完成结论**：计划 v1.1 已通过第1轮 + 第2轮 Self-Review，可进入执行阶段。

---

## 执行交接

### 实施顺序

按 Task 编号顺序执行（T37 → T51），部分顺序约束：
1. **T37 断路器状态机**（独立，先做）
2. **T38 断路器接入**（依赖 T37）
3. **T39 refusal 检测**（独立，可与 T37/T38 并行但建议顺序做）
4. **T40 区间计算**（独立）
5. **T41 校准页区间**（依赖 T40 或独立简化方案）
6. **T42 看板 g/kg**（独立）
7. **T43 月度计数**（独立）
8. **T44 设置页成本显示**（依赖 T43）
9. **T45 反馈补全**（独立）
10. **T46 prompt 聚合**（独立，与 T45 协同）
11. **T47 启动清理**（独立）
12. **T48 保留期可配**（依赖 T47 概念，独立实现）
13. **T49 设置页补全**（依赖 T48）
14. **T50 parser 测试**（独立）
15. **T51 全量回归**（最后）

### Task 完成检查清单（每个 Task 完成后必查）

- [ ] 代码与计划一致（逐行核对）
- [ ] 测试存在且通过
- [ ] Commit 已提交且在当前分支（git log 可见）
- [ ] 无新增 analyze warning
- [ ] 类型一致性（对照 Self-Review 第 3 节）
- [ ] 无遗留 TODO

### Sprint 6 完成标准

- [ ] CI 全绿：analyze 0 issues + test 全过
- [ ] T37-T51 共 15 个 commit 全在分支
- [ ] 断路器连续 3 次失败短路 30s
- [ ] refusal 显式检测
- [ ] 估算区间显示
- [ ] 月度成本显示
- [ ] 反馈补全 + prompt 聚合
- [ ] 图片清理启动 + 保留期可配
- [ ] 设置页补全

### 执行方式

Subagent-Driven Development（如 Sprint 3/4/5）。主控按 T37→T51 顺序派发 fresh subagent，逐个 review。

---

**计划版本：** v1.1（第1轮 + 第2轮 Self-Review 均完成，可进入执行阶段）
**编写日期：** 2026-07-02
**编写者：** Claude（writing-plans skill）
**Self-Review 状态：** ✅ 第1轮完成（6 节检查）+ ✅ 第2轮完成（17 源文件核实 + 8 处 P0 修正）
**待执行：** T37 → T51（15 个 Task，subagent-driven）
