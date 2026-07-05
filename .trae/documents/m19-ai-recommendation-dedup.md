# M19 AI 推荐去重 + 菜名归一化（v0.19.1）

## 摘要

用户反馈"智能推荐不够智能，经常推送重复的饭菜"。Phase 1 探索确认根因：当前 v5 AI 推荐仅在 prompt 层做软约束（system prompt 第 3 条"避免与近 3 天吃过的食物重复"），后处理层零兜底，时间窗口仅 3 天，仅菜名精确匹配。LLM 软约束不可靠（GLM-4-Flash + temperature=0.8），AI 违规返回重名菜时代码层不拦截。

本次改进采用**多管齐下**策略：后处理硬过滤 + 菜名归一化 + 时间窗口扩到 7 天 + prompt 强化 + 信号优先级声明 + AI 返回内部去重。TDD 严格循环（Red-Green-Refactor）。

## 当前状态分析

### 推荐流程（v5）
1. `dashboard_page.dart` 触发 → `AiRecommendationService.recommend()`
2. `_fetchFromAi`：聚合 14 天 meal_log + 30 条反馈 → 构建 prompt → 调 GLM-4-Flash
3. `_parseRecommendations`：JSON 解析 + `take(5)`
4. 失败/空结果静默返回空，v4 本地推荐兜底

### 去重现状（弱）
| 层 | 现状 | 问题 |
|----|------|------|
| Prompt 层 | system prompt 第 3 条"避免与近 3 天重复" | 软约束，LLM 不保证遵守 |
| 后处理层 | 无 | AI 违规返回重名菜不拦截 |
| 时间窗口 | 3 天 | 4 天前吃过的菜不受约束 |
| 去重维度 | 菜名精确匹配 | "鸡胸肉沙拉" vs "烤鸡胸沙拉" 视为不同 |
| 信号优先级 | 历史段（14 天 top 20 频次）与去重段（3 天）无优先级 | AI 可能误把高频食物理解为"应该推荐" |
| AI 内部去重 | 无 | AI 可能返回同一道菜两次 |

### 关键文件
- [lib/nutrition/ai_recommendation_prompt.dart](file:///workspace/lib/nutrition/ai_recommendation_prompt.dart) — prompt 构建（system prompt L76-86, buildUserPrompt L89-112, _historySection L151-165）
- [lib/nutrition/ai_recommendation_service.dart](file:///workspace/lib/nutrition/ai_recommendation_service.dart) — 服务（_fetchFromAi L174-231, recentFoodNames 构建 L191-203, _parseRecommendations L269-304）
- [test/nutrition/ai_recommendation_prompt_test.dart](file:///workspace/test/nutrition/ai_recommendation_prompt_test.dart) — 16 个 prompt 测试
- [test/nutrition/ai_recommendation_service_test.dart](file:///workspace/test/nutrition/ai_recommendation_service_test.dart) — 21 个 service 测试

## 提议改动

### 改动 1：新建 `lib/nutrition/dish_name_normalizer.dart`（菜名归一化纯函数）

**目的**：让"鸡胸肉沙拉"和"烤鸡胸沙拉"在去重时被视为同一道菜。

**实现**：纯函数 `normalizeDishName(String name) → String`，规则（按顺序应用）：
1. 去括号及内容：`"鸡胸肉(去皮)"` → `"鸡胸肉"`
2. 去份量后缀：`"鸡胸肉200g"` / `"鸡胸肉 200 克"` → `"鸡胸肉"`（正则 `\s*\d+\s*[gG克]\s*`）
3. 去品牌前缀：`"某品牌鸡胸肉"` → `"鸡胸肉"`（仅当含"品牌"/"牌"关键字时）
4. 去烹饪方式前缀：`"炒番茄蛋"` / `"凉拌黄瓜"` / `"清蒸鲈鱼"` → `"番茄蛋"` / `"黄瓜"` / `"鲈鱼"`
   - 烹饪方式词典：`['炒', '凉拌', '清蒸', '红烧', '煎', '炸', '烤', '焖', '炖', '煮', '卤', '腌', '拌', '蒸']`
   - 仅当菜名以词典中的词开头且剩余部分非空时才去
5. trim + 空字符串兜底返回原值

**不变量**：
- 纯函数，无副作用，无 IO
- 输入空字符串 / null 字符 → 返回空字符串
- 输入纯修饰词（如"凉拌"）→ 返回原值（避免归一化为空）

### 改动 2：改 `lib/nutrition/ai_recommendation_service.dart`

**2a. 时间窗口 3 天 → 7 天**（L193）
```dart
// 改前
for (var i = 0; i < 3; i++) {
// 改后
for (var i = 0; i < 7; i++) {
```

**2b. recentFoodNames 归一化**（L200）
```dart
// 改前
if (food != null) recentFoodNames.add(food.name);
// 改后
if (food != null) {
  recentFoodNames.add(normalizeDishName(food.name));
}
```

**2c. 后处理硬过滤 + AI 内部去重**（L229-230，`_fetchFromAi` 末尾）
```dart
// 改前
final all = _parseRecommendations(raw);
return all.take(5).toList();

// 改后
final all = _parseRecommendations(raw);
final deduped = _deduplicateAgainstHistory(all, recentFoodNames);
return deduped.take(5).toList();
```

**2d. 新增私有方法 `_deduplicateAgainstHistory`**
```dart
/// 后处理去重：AI 返回内部去重 + 与近 7 天已吃食物归一化去重
///
/// 策略：
/// 1. AI 返回内部去重：同一归一化菜名出现多次，只保留首次
/// 2. 历史去重：归一化菜名 ∈ recentFoodNames（已归一化）则剔除
///
/// 返回去重后的列表（可能少于 5 道，调用方 take(5) 安全）
/// 少于 5 道时不补足（避免再调 AI 的成本 + v4 兜底已混合展示）
static List<AiRecommendation> _deduplicateAgainstHistory(
  List<AiRecommendation> recs,
  Set<String> recentFoodNames,
) {
  final seen = <String>{}; // AI 返回内部已见归一化菜名
  final result = <AiRecommendation>[];
  for (final rec in recs) {
    final normalized = normalizeDishName(rec.name);
    // AI 内部去重
    if (seen.contains(normalized)) continue;
    // 历史去重
    if (recentFoodNames.contains(normalized)) continue;
    seen.add(normalized);
    result.add(rec);
  }
  return result;
}
```

**2e. import**
```dart
import 'dish_name_normalizer.dart';
```

### 改动 3：改 `lib/nutrition/ai_recommendation_prompt.dart`

**3a. system prompt 第 3 条强化**（L80）
```dart
// 改前
'3. 避免与近 3 天吃过的食物重复\n'
// 改后
'3. 禁止与近 7 天吃过的食物重复（硬约束，不可违反）\n'
```

**3b. 历史段加优先级声明**（L164，`_historySection` 末尾）
```dart
// 改前
final top = sorted.take(20).map((e) => '${e.key}(${e.value}次)').join('、');
return '常吃食物（按频次）：$top';

// 改后
final top = sorted.take(20).map((e) => '${e.key}(${e.value}次)').join('、');
return '常吃食物（按频次）：$top\n'
    '（注：高频仅反映偏好，去重约束优先于频次偏好，不可推荐近 7 天已吃过的食物）';
```

**3c. 去重段标题 3 天 → 7 天**（L100）
```dart
// 改前
buf.writeln('## 近 3 天已吃食物（避免重复推荐）');
// 改后
buf.writeln('## 近 7 天已吃食物（禁止重复推荐）');
```

### 改动 4：新建 `test/nutrition/dish_name_normalizer_test.dart`

TDD Red 阶段先写测试。覆盖场景：
1. 去括号及内容：`"鸡胸肉(去皮)"` → `"鸡胸肉"`
2. 去份量后缀：`"鸡胸肉200g"` → `"鸡胸肉"` / `"鸡胸肉 200 克"` → `"鸡胸肉"`
3. 去品牌前缀：`"某品牌鸡胸肉"` → `"鸡胸肉"`
4. 去烹饪方式前缀：`"炒番茄蛋"` → `"番茄蛋"` / `"凉拌黄瓜"` → `"黄瓜"` / `"清蒸鲈鱼"` → `"鲈鱼"`
5. 组合场景：`"某品牌炒鸡胸肉(去皮)200g"` → `"鸡胸肉"`
6. 边界：空字符串 → 空字符串
7. 边界：纯修饰词（`"凉拌"`）→ 返回原值（避免归一化为空）
8. 边界：无修饰词（`"鸡胸肉"`）→ 返回原值
9. 归一化后相同：`"鸡胸肉沙拉"` vs `"烤鸡胸沙拉"` → 注意：这俩归一化后不同（"鸡胸肉沙拉" vs "鸡胸沙拉"），需调整测试期望或归一化规则

**重要决策**：用户感知的"鸡胸肉沙拉" vs "烤鸡胸沙拉"重复，归一化规则只去前缀烹饪方式，"烤鸡胸沙拉" → "鸡胸沙拉"（去"烤"），"鸡胸肉沙拉"无前缀烹饪方式 → 不变。这俩归一化后仍不同。要真正消除这种重复，需要食材维度去重（用户未选）。**本 plan 接受这个限制**：归一化只覆盖"前缀烹饪方式 + 括号 + 份量 + 品牌"4 类明确场景，不覆盖"食材重叠"的模糊匹配。在 plan 假设里说明此限制。

### 改动 5：扩展 `test/nutrition/ai_recommendation_service_test.dart`

新增测试组 `后处理去重`：
1. AI 返回含 recentFoodNames 精确重名 → 被过滤
2. AI 返回含 recentFoodNames 归一化重名 → 被过滤（"鸡胸肉(去皮)" vs "鸡胸肉"）
3. AI 返回内部重复（同一菜名两次）→ 只留一个
4. AI 返回全部命中 recentFoodNames → 返回空列表
5. AI 返回 5 道菜，2 道命中 → 返回 3 道
6. recentFoodNames 为空 → 不过滤

**测试挑战**：`_fetchFromAi` 是私有方法，且依赖 `_callGlm` mock。需通过 `recommend()` 端到端测试，mock `_FakeGlmProvider` 返回固定 JSON + 预置 meal_log。参考现有 service 测试的 `_FakeGlmProvider` 模式。

### 改动 6：扩展 `test/nutrition/ai_recommendation_prompt_test.dart`

更新现有测试断言（system prompt 第 3 条 + 历史段优先级声明 + 去重段标题）：
1. system prompt 含"禁止"和"7 天"
2. system prompt 不含"避免"和"3 天"（旧文案）
3. 历史段含"去重约束优先于频次偏好"
4. 去重段标题为"近 7 天已吃食物（禁止重复推荐）"

## TDD 顺序（Red-Green-Refactor）

### Round 1：菜名归一化
- **Red**：写 `test/nutrition/dish_name_normalizer_test.dart`（9 个测试）→ 编译失败（无实现）
- **Green**：新建 `lib/nutrition/dish_name_normalizer.dart` → 测试通过
- **Refactor**：检查规则顺序、边界处理

### Round 2：后处理去重 + 时间窗口
- **Red**：扩展 `test/nutrition/ai_recommendation_service_test.dart`（6 个去重测试 + 时间窗口 7 天验证）→ 失败（无去重逻辑）
- **Green**：改 `ai_recommendation_service.dart`（时间窗口 3→7 + recentFoodNames 归一化 + `_deduplicateAgainstHistory`）→ 测试通过
- **Refactor**：检查 `_deduplicateAgainstHistory` 是否可提取为静态方法（易测）

### Round 3：Prompt 强化
- **Red**：扩展 `test/nutrition/ai_recommendation_prompt_test.dart`（4 个断言更新）→ 失败（旧文案）
- **Green**：改 `ai_recommendation_prompt.dart`（system prompt 第 3 条 + 历史段优先级 + 去重段标题）→ 测试通过
- **Refactor**：检查 prompt 文案清晰度

### Round 4：全量回归 + 发布
- `flutter analyze` → No issues
- `flutter test --exclude-tags smoke` → 全部通过
- 6 条硬约束复检（本改动不动 recognize/offline/build.gradle，硬约束不受影响，但仍需复检）
- bump 0.19.0+29 → 0.19.1+30
- HANDOFF.md 回填 M19 章节
- commit + push + tag v0.19.1

## 假设与决策

### 已确认决策（用户通过 AskUserQuestion）
1. **去重强度**：多管齐下（后处理硬过滤 + prompt 强化 + 菜名归一化 + 时间窗口 7 天 + 信号优先级声明）
2. **去重维度**：菜名归一化（去括号/去修饰词/去烹饪方式前缀）

### 设计决策（plan 自行决定）
1. **过滤后少于 5 道不补足**：避免再调 AI 的成本 + v4 兜底已混合展示。UI 显示"已为你过滤掉 N 道重复"提示（可选，本 plan 不强制）。
2. **归一化规则覆盖 4 类明确场景**：括号 / 份量 / 品牌 / 烹饪方式前缀。**不覆盖食材重叠模糊匹配**（如"鸡胸肉沙拉" vs "烤鸡胸沙拉"），这需要食材维度去重（用户未选）。本 plan 接受此限制。
3. **时间窗口 7 天**：用户日常饮食周期通常 7-14 天，7 天平衡"去重有效性"与"推荐多样性"（14 天可能致去重段过大、AI 选择空间过小）。
4. **AI 内部去重**：AI 可能返回同一道菜两次（GLM-4-Flash 偶发），后处理必须兜底。归一化后判定。
5. **`_deduplicateAgainstHistory` 设为静态方法**：纯函数易测，与 `_parseRecommendations` 一致风格。
6. **不引入食材维度去重**：用户未选，且依赖 FoodProfileTagger 准确度，复杂度高。留作未来 M20 候选。

### 不变量
- **不破坏 v4 兜底**：AI 失败/空结果仍静默返回空，v4 兜底展示
- **不破坏缓存**：去重发生在 `_fetchFromAi` 内，缓存的是去重后的结果，行为一致
- **不破坏 6 条硬约束**：本改动不动 recognize/offline/build.gradle/main/sentry，硬约束不受影响
- **TDD 严格循环**：每个 Round 先 Red 再 Green 再 Refactor

## 验证步骤

1. `flutter analyze` → No issues found
2. `flutter test --exclude-tags smoke` → 全部通过（含 9 + 6 + 4 = 19 个新测试）
3. 6 条硬约束复检（预期全部通过，本改动不涉及硬约束相关文件）
4. 手工验证（沙箱无法完成，待用户真机）：
   - 拍照记录几道菜 → 等几天 → 看推荐是否避开近 7 天吃过的
   - 看 AI 估算卡片是否显示"已过滤 N 道重复"（如果加 UI 提示）
   - 看"换一批"是否仍能刷新

## 文件改动清单

| 文件 | 操作 | 行数估计 |
|------|------|----------|
| `lib/nutrition/dish_name_normalizer.dart` | 新建 | ~60 行 |
| `lib/nutrition/ai_recommendation_service.dart` | 改 | ~30 行（时间窗口 + 归一化 + 去重方法） |
| `lib/nutrition/ai_recommendation_prompt.dart` | 改 | ~5 行（system prompt + 历史段 + 去重段标题） |
| `test/nutrition/dish_name_normalizer_test.dart` | 新建 | ~120 行（9 个测试） |
| `test/nutrition/ai_recommendation_service_test.dart` | 扩展 | ~150 行（6 个去重测试） |
| `test/nutrition/ai_recommendation_prompt_test.dart` | 扩展 | ~30 行（4 个断言更新） |
| `HANDOFF.md` | 改 | M19 章节回填 |
| `pubspec.yaml` | 改 | bump 0.19.1+30 |

总计 ~400 行新增/修改。
