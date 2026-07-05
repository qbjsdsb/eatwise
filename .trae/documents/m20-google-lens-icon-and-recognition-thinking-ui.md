# M20 Google Lens 风图标 + 识别思考流程 UI（v0.20.0）

## 摘要

用户反馈"图标还是太难看，希望像谷歌公司会做的样子，精致一点"+"拍照识别等候界面很单调，希望把 AI 思考流程放出来，也很美观"。

Phase 1 探索确认：
- **图标**：M17 同心圆环+中心圆点+紫橙渐变，已有 icon_assets_test.dart 测试。用户反馈仍"太难看"。
- **等候界面**：极简——只有 Card + CircularProgressIndicator + "识别中…" 文本。**底层 `RecognizeController` 已定义 6 个细粒度状态（pickingImage/preprocessing/recognizing/lookupNutrition/done/error/queued）但 UI 完全没读取**，是核心改造点。

本次改进采用**双线并行**：
1. **图标**：用 Seedream AI 生成 4 张 Google Lens 风参考图 → 用户挑选 → 手工实现 vector drawable XML（圆角取景框 + 食物轮廓 + 扫描线 + 紫橙渐变）
2. **等候界面**：4 阶段逐步打勾 + 顶部进度条（选图→压缩→AI 推理→查库回填），监听 `RecognizeController.state` 实时切换

TDD 严格循环（Red-Green-Refactor）。

## 当前状态分析

### 图标现状（M17）
| 元素 | 现状 |
|------|------|
| 前景 | 同心圆环（带顶部 8dp 缺口）+ 中心圆点（直径 16dp），纯白 |
| 背景 | 紫→橙 135° 对角线渐变（#6750A4 → #FF6E40） |
| 文件 | `ic_launcher_foreground.xml` + `ic_launcher_background.xml` + `colors.xml` |
| 测试 | `test/icon_assets_test.dart`（6 个测试，断言 M17 几何） |
| 用户反馈 | "还是太难看，希望像谷歌公司会做的样子" |

### 等候界面现状（极简）
```dart
// recognize_page.dart L357-377
if (_isRecognizing)
  Container(
    color: cs.scrim.withValues(alpha: 0.54),
    child: Center(
      child: Card(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('识别中…'),
            ],
          ),
        ),
      ),
    ),
  ),
```

**问题**：
1. 只有一个布尔标志 `_isRecognizing`，不区分阶段
2. 底层 `RecognizeController` 已有 6 个状态（`enum RecognizeState { idle, pickingImage, preprocessing, recognizing, lookupNutrition, done, error, queued }`）但 UI 完全没读取
3. 转圈无进度感、无阶段感、无 AI 思考可视化
4. 文案单调（"识别中…"）

### 关键文件
- [android/app/src/main/res/drawable/ic_launcher_foreground.xml](file:///workspace/android/app/src/main/res/drawable/ic_launcher_foreground.xml) — 图标前景 vector drawable（M17 同心圆环）
- [android/app/src/main/res/drawable/ic_launcher_background.xml](file:///workspace/android/app/src/main/res/drawable/ic_launcher_background.xml) — 图标背景渐变
- [android/app/src/main/res/values/colors.xml](file:///workspace/android/app/src/main/res/values/colors.xml) — 颜色定义
- [test/icon_assets_test.dart](file:///workspace/test/icon_assets_test.dart) — 6 个图标资源测试
- [lib/features/recognize/recognize_page.dart](file:///workspace/lib/features/recognize/recognize_page.dart) — 拍照识别主页（loading 遮罩 L357-377，`_isRecognizing` 标志 L190）
- [lib/features/recognize/recognize_controller.dart](file:///workspace/lib/features/recognize/recognize_controller.dart) — 识别状态机（`enum RecognizeState` L19，6 个状态）

## 提议改动

### 改动 1：Seedream AI 生成 4 张 Google Lens 风图标参考图

**目的**：让用户直观挑选风格，再手工实现 vector drawable。

**实现**：用 `byted-seedream-image-generate` skill 生成 4 张参考图，prompt 描述：

```
A modern Android app icon in Google Lens style, featuring a rounded rectangle viewfinder frame containing a simplified food silhouette (apple or plate), with a horizontal scan line crossing through the center, vibrant purple-to-orange diagonal gradient background (#6750A4 to #FF6E40), clean minimal geometric design, Material Design 3 aesthetic, flat vector style, high contrast white foreground, suitable for adaptive icon, no text, centered composition, professional app icon quality
```

**4 张变体**（同一 prompt 微调）：
1. 苹果剪影 + 扫描线 + 取景框
2. 餐盘剪影 + 扫描线 + 取景框
3. 镜头光圈 + 食物轮廓 + 取景框角标
4. 简化相机 + 食物轮廓 + 渐变背景

**输出**：4 张 PNG 参考图（不直接用于 App，仅供设计参考）

### 改动 2：手工实现 Google Lens 风图标 vector drawable

**设计理念**（基于 Google Lens 风格 + App 紫橙主题）：
- **圆角矩形取景框**（外框，白色描边 4dp，圆角 8dp）= 拍照识别核心功能
- **取景框四角 L 形角标**（典型取景框装饰，4 个角各一个 L 形，白色）= 聚焦感
- **中心食物剪影**（简化苹果或餐盘，白色实心）= 食物识别
- **水平扫描线**（穿过食物中心，白色半透明渐变）= AI 扫描中
- **背景**：保留 M17 紫橙 135° 对角线渐变（#6750A4 → #FF6E40）

**画布几何**（108×108dp，安全区 66×66，中心 54,54）：
- 取景框：x=29-79, y=29-79（50×50dp，距安全区边缘 4dp）
- 取景框圆角：8dp
- 取景框描边：4dp
- 四角 L 形角标：每角 12×12dp，描边 4dp
- 中心食物剪影（苹果简化形）：直径 20dp，中心 (54,54)
- 扫描线：y=54，x=33-75，高度 2dp，两端渐变透明

**实现文件**：
- `ic_launcher_foreground.xml` — 重写为取景框+四角 L+食物剪影+扫描线
- `ic_launcher_background.xml` — 保留 M17 紫橙渐变（不变）
- `colors.xml` — 保留 M17 颜色（不变）

**monochrome 兼容**：前景纯白 alpha 通道，无渐变在前景层。系统染色时背景渐变被忽略，前景独立可识别（取景框+食物剪影+扫描线的剪影）。

### 改动 3：新建 `lib/features/recognize/recognize_progress_card.dart`（4 阶段进度卡片 widget）

**目的**：把"识别中…"升级为 4 阶段逐步打勾 + 顶部进度条的可视化组件。

**4 阶段映射**（来自 `RecognizeState` enum）：
| 阶段 | 状态 | 文案 | 图标 |
|------|------|------|------|
| 1 | `pickingImage` | 选图中… | 相机 |
| 2 | `preprocessing` | 压缩图中… | 压缩 |
| 3 | `recognizing` | AI 推理中… | 镜头 |
| 4 | `lookupNutrition` | 查库回填中… | 数据库 |

**Widget 设计**：
```dart
class RecognizeProgressCard extends StatelessWidget {
  final RecognizeState currentState;

  const RecognizeProgressCard({super.key, required this.currentState});

  @override
  Widget build(BuildContext context) {
    final stages = _stageConfig(currentState); // 返回 4 个 _Stage 对象
    final completedCount = stages.where((s) => s.status == _StageStatus.done).length;
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部进度条（LinearProgressIndicator，value = completedCount / 4）
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: completedCount / 4,
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(cs.primary),
              ),
            ),
            const SizedBox(height: 20),
            // 4 阶段竖向列表
            for (final stage in stages) _StageRow(stage: stage),
          ],
        ),
      ),
    );
  }
}
```

**单行 `_StageRow` 设计**：
- 左侧：状态圆圈（28×28dp）
  - 未到：灰色圆圈描边
  - 当前：紫色圆圈 + 内部白色转圈
  - 已完成：绿色圆圈 + 内部白色勾
- 中间：文案（默认/加粗按状态）
- 右侧：阶段图标（相机/压缩/镜头/数据库，灰色/紫/灰）

**状态判定逻辑**（`_stageConfig`）：
```dart
List<_Stage> _stageConfig(RecognizeState current) {
  const order = [
    RecognizeState.pickingImage,
    RecognizeState.preprocessing,
    RecognizeState.recognizing,
    RecognizeState.lookupNutrition,
  ];
  final currentIdx = order.indexOf(current);
  return order.asMap().entries.map((e) {
    final idx = e.key;
    final state = e.value;
    final status = idx < currentIdx
        ? _StageStatus.done
        : idx == currentIdx
            ? _StageStatus.active
            : _StageStatus.pending;
    return _Stage(state: state, status: status);
  }).toList();
}
```

**特殊状态处理**：
- `idle`：4 阶段全 pending（不应出现，loading 不显示）
- `done`：4 阶段全 done（瞬间消失，跳转校准页）
- `error`：4 阶段保持当前态（红色提示）
- `queued`：显示"已加入离线队列，将在网络恢复后识别"

### 改动 4：改 `lib/features/recognize/recognize_page.dart`（接入新 widget + 监听状态）

**4a. 替换 loading 遮罩**（L357-377）
```dart
// 改前
if (_isRecognizing)
  Container(
    color: cs.scrim.withValues(alpha: 0.54),
    child: Center(
      child: Card(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('识别中…'),
            ],
          ),
        ),
      ),
    ),
  ),

// 改后
if (_isRecognizing)
  Container(
    color: cs.scrim.withValues(alpha: 0.54),
    child: Center(
      child: RecognizeProgressCard(
        currentState: _currentRecognizeState,
      ),
    ),
  ),
```

**4b. 新增状态监听字段**（L190 附近）
```dart
// 改前
bool _isRecognizing = false;

// 改后
bool _isRecognizing = false;
RecognizeState _currentRecognizeState = RecognizeState.idle;
```

**4c. 在 `_pickAndRecognize` 中监听状态变化**（L383-553）
```dart
Future<void> _pickAndRecognize(ImageSource source) async {
  if (_isRecognizing) return;
  _lastSource = source;
  setState(() {
    _isRecognizing = true;
    _currentRecognizeState = RecognizeState.pickingImage;
  });
  try {
    final controller = await _ensureController();
    // 监听 controller.state 变化，实时更新 UI
    controller.addListener(_onRecognizeStateChanged);
    await controller.pickAndRecognize(source, mealType: _mealType);
    controller.removeListener(_onRecognizeStateChanged);
    // ... 后续跳转逻辑不变
  } finally {
    if (mounted) {
      setState(() {
        _isRecognizing = false;
        _currentRecognizeState = RecognizeState.idle;
      });
    }
  }
}

void _onRecognizeStateChanged() {
  if (!mounted) return;
  final controller = _controller; // 已初始化的 controller
  if (controller == null) return;
  setState(() {
    _currentRecognizeState = controller.current.state;
  });
}
```

**注意**：`RecognizeController` 是 Riverpod StateNotifier，`controller.current` 同步读取当前 state。需用 `addListener` 监听变化。具体监听机制需在实现时确认（StateNotifier 自带 `addListener` 返回 `void Function()`）。

### 改动 5：更新 `test/icon_assets_test.dart`（M20 几何断言）

**5a. 改 group 名**："图标资源完整性 (M17)" → "图标资源完整性 (M20)"

**5b. 改前景断言**（L66-103）
```dart
// 改前
test('ic_launcher_foreground.xml 含同心圆环+中心圆点 path（M17 重设计）', () {
  // 断言 M50,29（外环）+ M46,54（中心圆点）

// 改后
test('ic_launcher_foreground.xml 含取景框+食物剪影+扫描线 path（M20 重设计）', () {
  final file = File('$androidResDir/drawable/ic_launcher_foreground.xml');
  final content = file.readAsStringSync();
  // M20 几何：取景框圆角矩形 path
  expect(content, contains('android:pathData="M29,29'),
      reason: '取景框 path 应从 (29,29) 开始（M20 圆角矩形取景框）');
  // M20 几何：中心食物剪影（苹果简化形）
  expect(content, contains('android:pathData="M44,54'),
      reason: '食物剪影 path 应从 (44,54) 开始（M20 中心食物剪影）');
  // M20 几何：扫描线
  expect(content, contains('android:pathData="M33,54'),
      reason: '扫描线 path 应从 (33,54) 开始（M20 水平扫描线）');
  expect(content, contains('android:fillColor="@color/ic_launcher_foreground"'),
      reason: '前景应引用 @color/ic_launcher_foreground');
  // M17 同心圆环 path 应已移除
  expect(content, isNot(contains('M50,29')),
      reason: 'M17 同心圆环 path 应被 M20 取景框替换');
  expect(content, isNot(contains('M46,54')),
      reason: 'M17 中心圆点 path 应被 M20 食物剪影替换');
});
```

**5c. colors.xml + background.xml 断言不变**（保留 M17 紫橙渐变）

### 改动 6：新建 `test/features/recognize/recognize_progress_card_test.dart`（widget 测试）

**TDD Red 阶段先写测试**。覆盖场景：
1. 初始状态（pickingImage）：第 1 阶段 active，2-4 pending，进度 0/4
2. preprocessing：第 1 阶段 done，第 2 active，3-4 pending，进度 1/4
3. recognizing：1-2 done，3 active，4 pending，进度 2/4
4. lookupNutrition：1-3 done，4 active，进度 3/4
5. done：4 阶段全 done，进度 4/4
6. error：保持当前态，无变化
7. queued：显示"已加入离线队列"特殊文案
8. 进度条 value 与已完成阶段数一致
9. 当前阶段文案加粗（vs 未到阶段默认字重）
10. 已完成阶段显示勾图标（vs 当前阶段显示转圈）

**测试模式**：用 `flutter_test` 的 `pumpWidget` 渲染 `RecognizeProgressCard`，断言 widget 树结构（find.byType / find.text）。

## TDD 顺序（Red-Green-Refactor）

### Round 0：Seedream 生成参考图（非 TDD，前置步骤）
- 用 `byted-seedream-image-generate` skill 生成 4 张 Google Lens 风图标参考图
- 输出 4 张 PNG 到临时目录（不进 App 资源，仅供设计参考）
- 用户挑选风格方向（通过对话确认）

### Round 1：图标 vector drawable 重设计
- **Red**：改 `test/icon_assets_test.dart`（group 名 M17→M20，前景断言改为取景框+食物剪影+扫描线）→ 失败（旧 M17 path）
- **Green**：重写 `ic_launcher_foreground.xml`（取景框+四角 L+食物剪影+扫描线）→ 测试通过
- **Refactor**：检查 path 几何精度、注释更新

### Round 2：RecognizeProgressCard widget
- **Red**：新建 `test/features/recognize/recognize_progress_card_test.dart`（10 个测试）→ 编译失败（无实现）
- **Green**：新建 `lib/features/recognize/recognize_progress_card.dart`（widget + 状态判定逻辑）→ 测试通过
- **Refactor**：检查 widget 树结构、颜色引用、状态判定逻辑

### Round 3：接入 recognize_page
- **Red**：扩展 `test/features/recognize/recognize_page_test.dart`（如已存在，加状态切换断言；如不存在，新建端到端测试）→ 失败（旧 loading UI）
- **Green**：改 `recognize_page.dart`（替换 loading 遮罩 + 监听 controller.state + 新增 `_currentRecognizeState` 字段 + `_onRecognizeStateChanged` 回调）→ 测试通过
- **Refactor**：检查监听机制（addListener/removeListener 配对，避免内存泄漏）

### Round 4：全量回归 + 发布
- `flutter analyze` → No issues
- `flutter test --exclude-tags smoke` → 全部通过（含 10 + N 个新测试）
- 6 条硬约束复检（本改动不动 recognize 控制流/upsert/per100g/build.gradle/main/sentry，硬约束不受影响，但仍需复检）
- bump 0.19.1+30 → 0.20.0+31
- HANDOFF.md 回填 M20 章节
- commit + push + tag v0.20.0

## 假设与决策

### 已确认决策（用户通过 AskUserQuestion）
1. **图标风格**：Google Lens 风扫描镜头（圆角取景框 + 食物剪影 + 扫描线）
2. **AI 用途**：参考图 + 手工 vector drawable（符合 Android 自适应图标规范，无锯齿可缩放）
3. **等候界面**：4 阶段逐步打勾 + 顶部进度条

### 设计决策（plan 自行决定）
1. **保留 M17 紫橙渐变背景**：用户未要求换色，紫橙双色呼应 App 主题种子色（#6750A4）+ 食欲色（#FF6E40），契合"慢慢吃"理念。仅重设计前景。
2. **取景框四角 L 形角标**：典型取景框装饰，增强"拍照识别"故事感，呼应 Google Lens 风格。
3. **中心食物剪影用简化苹果**：苹果是食物的通用符号（健康/营养/食物），简化为圆形+顶部小叶+底部凹陷，缩放到 48dp 仍可识别。
4. **扫描线用半透明渐变**：静态图标不能动，扫描线表现为水平线 + 两端透明渐变，暗示"扫描中"。
5. **4 阶段不细分重试/容灾**：底层有 L1 重试/L2 切备/L3 转手动三层容灾，但 UI 只展示 4 个主阶段，避免过度复杂。容灾在 `recognizing` 阶段内部消化。
6. **`done` 状态瞬间消失**：4 阶段全 done 后立即跳转校准页，loading 遮罩消失。不展示"完成"态避免视觉闪烁。
7. **`error` 状态保持当前态**：错误时不重置进度条，让用户看到在哪个阶段失败。错误文案单独 SnackBar 提示。
8. **`queued` 状态特殊文案**：离线入队时显示"已加入离线队列，将在网络恢复后识别"，不展示 4 阶段。
9. **进度条用 LinearProgressIndicator**：MD3 标准组件，value = completedCount / 4，minHeight 6dp，圆角 4dp。
10. **状态圆圈 28×28dp**：足够大可触摸，足够小不挤占空间。已完成绿色（cs.primary）+ 白勾，当前紫色（cs.primary）+ 白转圈，未到灰色描边。

### 不变量
- **不破坏识别控制流**：`RecognizeController.pickAndRecognize` 逻辑不变，仅在 UI 层增加状态监听
- **不破坏 6 条硬约束**：本改动不动 recognize 三路径/upsert/per100g/build.gradle/main/sentry
- **不破坏缓存/容灾**：L1 重试/L2 切备/L3 转手动/CircuitBreaker 逻辑不变
- **图标 monochrome 兼容**：前景纯白 alpha 通道，系统染色可识别
- **TDD 严格循环**：每个 Round 先 Red 再 Green 再 Refactor

## 验证步骤

1. `flutter analyze` → No issues found
2. `flutter test --exclude-tags smoke` → 全部通过（含 10 + N 个新测试）
3. 6 条硬约束复检（预期全部通过，本改动不涉及硬约束相关文件）
4. 手工验证（沙箱无法完成，待用户真机）：
   - 看 App 图标是否像 Google Lens 风格（取景框+食物+扫描线）
   - 拍照识别时看 4 阶段是否逐步打勾 + 进度条推进
   - 各阶段文案是否准确（选图/压缩/AI 推理/查库回填）
   - 错误态是否保持当前进度（不重置）
   - 离线入队是否显示特殊文案

## 文件改动清单

| 文件 | 操作 | 行数估计 |
|------|------|----------|
| `android/app/src/main/res/drawable/ic_launcher_foreground.xml` | 重写 | ~80 行（取景框+四角 L+食物剪影+扫描线 + 注释） |
| `lib/features/recognize/recognize_progress_card.dart` | 新建 | ~150 行（widget + 状态判定 + _StageRow） |
| `lib/features/recognize/recognize_page.dart` | 改 | ~30 行（替换 loading + 监听状态 + 新字段） |
| `test/icon_assets_test.dart` | 改 | ~30 行（group 名 + 前景断言 M17→M20） |
| `test/features/recognize/recognize_progress_card_test.dart` | 新建 | ~200 行（10 个 widget 测试） |
| `HANDOFF.md` | 改 | M20 章节回填 |
| `pubspec.yaml` | 改 | bump 0.20.0+31 |
| 临时参考图（4 张 PNG） | AI 生成 | 不进 App 资源 |

总计 ~490 行新增/修改 + 4 张 AI 参考图。

## Round 0 执行说明（Seedream 生成参考图）

在 Round 1 开始前，先用 `byted-seedream-image-generate` skill 生成 4 张参考图：

**Prompt 模板**（4 张微调）：
```
A modern Android app icon in Google Lens style, [变体描述], featuring a rounded rectangle viewfinder frame with L-shaped corner brackets, containing a simplified food silhouette, with a horizontal scan line crossing through the center, vibrant purple-to-orange diagonal gradient background (#6750A4 to #FF6E40), clean minimal geometric design, Material Design 3 aesthetic, flat vector style, high contrast white foreground, suitable for adaptive icon, no text, centered composition, professional app icon quality
```

**4 张变体**：
1. `[变体描述]` = "an apple silhouette"（苹果剪影）
2. `[变体描述]` = "a plate with fork and knife silhouette"（餐盘+餐具剪影）
3. `[变体描述]` = "a camera aperture with food outline"（镜头光圈+食物轮廓）
4. `[变体描述]` = "a bowl with steam silhouette"（碗+蒸汽剪影）

**输出位置**：临时目录（如 `/tmp/m20-icon-refs/`），不进 App 资源，仅供设计参考。

**用户挑选**：生成后向用户展示 4 张图，用户挑选风格方向（或混合元素），再进入 Round 1 手工实现 vector drawable。
