# M16.4 深度审查修复 Spec

## Why

M16.2/M16.3 修复后用户反馈"识别经常出错"+"米粉汤碳水 991g 异常"已解决，但全代码深度审查发现 4 个 P1（OFF 云查路径 + 推荐算法）+ 7 个 P2（DB 加密/精度/可观测性等）+ 7 个 P3（测试断言/注释/一致性）共 18 个问题，其中 4 个 P1 集中在 OFF 云查路径（识别准确度的剩余根因之一）和推荐算法偏好学习，影响主要功能准确度，需严谨修复并发布 v0.18.3。

## What Changes

### P1 修复（4 个，立即修复）

- **P1-1** `lib/ai/off_provider.dart:84` OFF User-Agent 硬编码版本号 0.4.0 → 动态读取 `PackageInfo.fromPlatform()`，与 `github_release_client.dart` User-Agent 统一
- **P1-2** `lib/ai/off_provider.dart:133` OFF serving_size 正则只匹配 g 不匹配 ml → 扩展支持 ml（按密度 1.0 兜底为 g），解决饮料按 100g 算的 5 倍偏差
- **P1-3** `lib/ai/nutrition_lookup.dart:83-87` OFF 命中后不乘 ediblePercent → 区分加工食品（不乘）vs 生鲜食品（乘 ediblePercent），与 DB 命中路径行为一致
- **P1-4** `lib/nutrition/user_preference_learner.dart:36-38` `hasEnoughSamples` 漏算 textureFreq + priceTierFreq → 4 个维度全部纳入统计

### P2 修复（4 个，下个迭代）

- **P2-1** `lib/data/repositories/meal_log_repository.dart:155-168` `getMedianServing` 加 endDate 上界（与 H4 一致）
- **P2-2** `lib/nutrition/tdee_calibrator.dart:83` `.toInt()` → `.round()` 保留精度
- **P2-3** `lib/data/repositories/food_item_repository.dart:69-79` `findByNameOrAlias` 优先级 3/4（contains 匹配）加 `_isDirtyFoodItem` 过滤（与 1/2 一致，双保险）
- **P2-4** `lib/features/offline/offline_queue_controller.dart:62,70` fire-and-forget `processPending().catchError` 内加 best-effort Sentry 上报，保留可观测性

### P3 修复（3 个，后续清理）

- **P3-1** `test/features/multi_dish_page_test.dart:150-152` 未命中菜品提示 OR 容错断言 → 固定文案后精确断言
- **P3-2** `lib/main.dart:31` `_writeBootLog` 空 catch 块加注释
- **P3-3** `lib/ai/food_density.dart:33` `densityOf('solid')` 文档明确"调用方应先 isLiquidCategory 判断"

### 不修复（按 HANDOFF 已知问题，需设计/UX 决策）

- P1-2 prompts 规则冲突（需设计讨论）
- P1-3 多菜 take(5) 截断（需 UX 决策）
- P2 DB 加密评估（需评估 sqlite3mc/sqlcipher CI 兼容性）
- P2-2 非 VisionRecognitionException 显示生涩 toString
- P2-3 解码失败垃圾图直送 API
- P2-4 mediaType 硬编码
- P3 sentry 中文别名（白名单策略更严格，需独立设计）

## Impact

- **Affected specs**: 无（本次为代码质量修复，无功能新增）
- **Affected code**:
  - `lib/ai/off_provider.dart`（P1-1 + P1-2）
  - `lib/ai/nutrition_lookup.dart`（P1-3）
  - `lib/nutrition/user_preference_learner.dart`（P1-4）
  - `lib/data/repositories/meal_log_repository.dart`（P2-1）
  - `lib/nutrition/tdee_calibrator.dart`（P2-2）
  - `lib/data/repositories/food_item_repository.dart`（P2-3）
  - `lib/features/offline/offline_queue_controller.dart`（P2-4）
  - `test/features/multi_dish_page_test.dart`（P3-1）
  - `lib/main.dart`（P3-2）
  - `lib/ai/food_density.dart`（P3-3）
  - `pubspec.yaml`（版本号 bump）
  - `HANDOFF.md`（M16.4 章节回填）
  - 对应测试文件（TDD 新增/更新测试）

## ADDED Requirements

### Requirement: OFF User-Agent 动态版本号

The system SHALL use the actual app version (from `PackageInfo.fromPlatform()`) in the OFF API User-Agent header, instead of hardcoded "0.4.0".

#### Scenario: User-Agent 包含实际版本号
- **WHEN** OFF API 被调用
- **THEN** User-Agent header 形如 `EatWise/0.18.3 (Android; food-matching) contact@eatwise.app`，版本号与 `pubspec.yaml` 一致

### Requirement: OFF serving_size 支持 ml 单位

The system SHALL parse both "g" and "ml" units from OFF `serving_size` field, treating ml as g by density 1.0 (water-like) for liquid products.

#### Scenario: 饮料 serving_size 含 ml
- **WHEN** OFF 数据返回 `serving_size: "330 ml"`
- **THEN** 解析为 330g（按密度 1.0 兜底），而非回退 defaultServingG=100

#### Scenario: 加工食品 serving_size 含 g
- **WHEN** OFF 数据返回 `serving_size: "30 g"`
- **THEN** 解析为 30g（行为不变）

### Requirement: OFF 命中营养按 ediblePercent 调整（生鲜食品）

The system SHALL multiply OFF nutrition values by `ediblePercent/100` for raw/unprocessed foods (fruits, meats with bone/shell), to be consistent with DB hit path behavior. Processed foods (ediblePercent=100) are unaffected.

#### Scenario: 香蕉（edible=65%）OFF 命中
- **WHEN** AI 估算香蕉 servingG=200g（含皮整重），OFF 命中 per100g 碳水=22g，ediblePercent=65
- **THEN** 实际碳水 = 22 × 200 × 0.65 / 100 = 28.6g（与 DB 命中路径一致）

#### Scenario: 加工饼干（edible=100%）OFF 命中
- **WHEN** OFF 命中加工饼干
- **THEN** 实际碳水 = per100g × servingG / 100（行为不变，ediblePercent=100 不影响）

### Requirement: hasEnoughSamples 统计 4 个维度

The system SHALL count samples across all 4 preference dimensions (taste/style/texture/priceTier) in `hasEnoughSamples`, not just taste + style.

#### Scenario: 用户所有食物仅有 texture 标签
- **WHEN** 用户记录的 10 个食物都无 taste/style 标签但有 texture 标签
- **THEN** `hasEnoughSamples` 返回 true（total ≥ 阈值），启用偏好加权

### Requirement: getMedianServing 加 endDate 上界

The system SHALL filter future meal logs in `getMedianServing`, consistent with H4 fix for `getRecentMeals`/`getRecentFoodCounts`/`getMealTypeDistribution`.

#### Scenario: 预录未来餐次不污染中位数
- **WHEN** 用户预录明天的早餐 500g
- **THEN** `getMedianServing` 不计入明天记录，只统计 ≤ today 的记录

### Requirement: tdee_calibrator 用 round() 保留精度

The system SHALL use `.round()` instead of `.toInt()` for tdeeAdjustmentKcal, preserving 0.5 kcal precision.

#### Scenario: 微调值 -99.7
- **WHEN** rawAdjustment = -99.7
- **THEN** tdeeAdjustmentKcal = -100（round），而非 -99（toInt 截断）

### Requirement: findByNameOrAlias 优先级 3/4 加脏数据过滤

The system SHALL apply `_isDirtyFoodItem` filter to priority 3/4 (contains match) in `findByNameOrAlias`, consistent with priority 1/2, as defense-in-depth against dirty data.

#### Scenario: 脏数据条目通过 contains 命中
- **WHEN** 用户搜索"米粉"，优先级 1/2 全跳过（脏数据），优先级 3 contains 命中脏条目
- **THEN** 跳过脏条目，继续找下一条 contains 命中

### Requirement: fire-and-forget processPending 上报 Sentry

The system SHALL report caught exceptions in `processPending().catchError` to Sentry (best-effort), preserving observability for DB write failures / food_item upsert failures.

#### Scenario: processPending 抛 DB 异常
- **WHEN** 网络恢复触发 processPending，DB 写入失败
- **THEN** 异常被 catchError 捕获 + Sentry 上报（不阻塞调用方）

## MODIFIED Requirements

无（本次为新增修复，不修改现有需求）

## REMOVED Requirements

无
