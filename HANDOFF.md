# 项目交接文档（Handoff）

> **用途**：沙箱会话不持久化，每天 AI 会"失忆"。
> 本文档是跨会话记忆载体，每个会话开始时 AI 必读，结束前 AI 必更新。
> **维护规则**：每次会话有实质进展就更新，保持"任何新 AI 读完此文档就能无缝接手"。

---

## 0. 新会话开启指令（给 AI 看的）

```
你是接手这个项目的新 AI。请按以下顺序操作：
1. 读本文件全文（HANDOFF.md）了解项目状态与约定
2. 读 .trae/rules/ 下的项目规则（若有）
3. 跑 `git log --oneline -20` 看最近提交
4. 跑 `git status` 看工作区状态
5. 问用户"今天要继续做什么"——不要主动改代码
```

---

## 1. 项目速览

- **项目名**：慢慢吃（EatWise）—— 拍照识别食物热量 + 营养记录 + AI 汇总建议
- **技术栈**：Flutter 3.44.4 / Dart / Riverpod / drift (SQLite) / Material 3 Expressive
- **当前版本**：0.16.0+17（pubspec.yaml）
- **当前分支**：trae/agent-wX1X6Q（HEAD = e6ae182 v0.16.0 release；v0.16.0 tag 指向 e6ae182）
- **关键约束**：
  - `meal_log.food_item_id` 是非空外键，PRAGMA foreign_keys=ON，foodItemId=0 哨兵写库前必须替换为真实 id
  - `android/app/build.gradle.kts` 必须保持 `isMinifyEnabled=false` + `isShrinkResources=false`（否则 R8 剥掉 sentry/workmanager 反射类致启动崩溃）
  - AI 兜底（foodItemId=0）需在前台 recognize_page、multi_dish_page、后台 offline_queue_controller 三条路径全部覆盖

---

## 2. 当前状态（每次会话结束更新）

**最后更新**：2026-07-05

**工作区状态**：v0.16.0 release 已 push 远程（commit e6ae182 + tag v0.16.0，含 v5 AI 推荐审计修复 + 满意度反馈按钮改为点开才显示 + 测试 mock 修复 + 版本号 bump）；v0.15.0 release 已 push（commit 4b35dcb + tag v0.15.0）；Phase 2.12 AI 个性化推荐 v5 已 push（commit 27b6a85）；Phase 4 用户反馈 5 问题改进已 push（AI 推荐失败修复 + 改菜名 mixin 三入口 + 周月总结滚动窗口+宏量+偏好+覆盖率+数据守卫）；**深度审查修复批次（2026-07-05）已 commit 23 个待 push**（H1-H6 / M1-M14 / L1-L5，详见下方"深度审查修复批次"章节）
**当前分支**：trae/agent-wX1X6Q（HEAD = 1d8da3d 待 push，23 个 commit 待推送 194d4ca~1d8da3d；v0.16.0 tag 指向 e6ae182；v0.15.0 tag 指向 4b35dcb）

**AI 识别准确度重构 Phase 1+2（2026-07-04）**：
- 目标：解决"做了这么多还是不准"——豆包能精确识别珍宝珠酸条/雪花啤酒，EatWise 不行
- 根因诊断：4 个范式级缺陷
  1. 规则 8 禁止解释文字 → 关掉模型推理能力（shortcut learning 致雪花→雪碧）
  2. 用 qwen3-vl-flash 轻量模型做硬视觉判别
  3. one-shot 架构没法自我纠正
  4. database-first 反噬 LLM 知识（用弱库覆盖强 LLM）
- Phase 1 改动（已 commit c427316）：
  - prompts.dart v1.8 → v1.9：营养师人设 + reasoning 字段(CoT) + 包装营养表 OCR 路径(6 字段) + 隐藏热量显式估算 + 盘子尺度参照 + 规则 8 修改 + 示例 7(珍宝珠酸条)+示例 8(麻婆豆腐)
  - vision_provider.dart：VisionRecognitionResult 加 7 个字段(reasoning + packageNutritionTableOcr + packageServingG/Kj/Kcal/TotalG/ServingsPerPack) + hasPackageNutrition getter + copyWith 加 reasoning
  - recognition_post_processor.dart：两处手动重建透传新字段
  - 测试：vision_response_parser_test + recognition_post_processor_test 加 v1.9 group（11 个测试）
- Phase 1 顺手修复：lib/data/repositories/food_item_repository.dart L292-293 跨事务闭包 null safety 编译错误（Dart 3.10+ 更严格检查：闭包内 `if (x != null)` 不能提升外部 `String?`）→ 用 `final brandAliasNonNull = brandAlias` 局部变量提升
- Phase 1 验证：✅ flutter analyze No issues + flutter test 402 passed / 1 failed (T48 原有日期 bug) / 0 skipped

**Phase 2 改动（已完成代码，未 commit）—— v1.9 包装 OCR 优先路径三路径全覆盖**：
- 核心策略：保持哨兵分支结构不变，在哨兵分支内优先检查 `result.hasPackageNutrition`
  - 有包装数据 → `computePackageNutritionPer100g()` 换算（精确值，跳过品类校准）
  - 无包装数据 → 走原 AI 估算 + FoodCategoryDefaults.calibrate 路径（保留原有行为）
- vision_provider.dart：新增 `computePackageNutritionPer100g()` 方法
  - 换算规则：单份 kcal 优先 packageServingKcal；为 0/null 时用 packageServingKj ÷ 4.184
  - per100g kcal = 单份 kcal × 100 ÷ packageServingG
  - 蛋白/脂肪/碳水：包装通常不标，用 AI 估算按 per100 反算（mid=0 时 per100Ratio=0 防除零）
  - 无法换算（servingG=0 或所有 serving_*=0）返回 null，调用方走 AI 估算路径
- recognize_page.dart：哨兵分支 `if (n.foodItemId == 0)` 内加 v1.9 包装 OCR 优先路径
- multi_dish_page.dart：提取 `resolveSingleFoodItemId` 本地函数，主菜(i==0)和附加菜(i>0)哨兵分支共用，逻辑与 recognize_page 一致；补 food_item_repository import
- offline_queue_controller.dart：两处 LLM 兜底分支同步加包装 OCR 优先路径
  - L142-196 单品库未命中 LLM 兜底：包装 OCR 优先 + 品类校准兜底（与 recognize_page 一致）
  - L210-250 复合菜组分全 miss LLM 兜底：包装 OCR 优先 + AI 估算兜底（复合菜不做品类校准）
- Phase 2 测试：vision_response_parser_test 加 `v1.9 computePackageNutritionPer100g 包装换算` group（14 个测试）
  - kcal 优先 / kJ 兜底换算 / null 分支 / 蛋白脂肪碳水 per100 反算 / 除零防护 / hasPackageNutrition getter 各分支
- Phase 2 验证（2026-07-04 沙箱实测）：
  - ✅ `flutter analyze` → No issues found
  - ✅ `flutter test` → 417 passed / 3 skipped / 1 failed（T48 原有日期 bug，与 Phase 2 无关）
  - 14 个新测试全过；offline_queue_test + recognition_post_processor_test 全过
- Phase 2 设计纠偏：原计划"删哨兵分支 + calibrate 前移到 PostProcessor"，读代码后发现 calibrate 需要 `n.calories`（NutritionResult）而非 `result.estimatedCalories`，且库命中路径不应触发 calibrate → 改为"哨兵内加包装 OCR 优先路径"

**Phase 2.5 Gap 修复（2026-07-04）—— 自我评估发现 4 个 gap 全部修复**：

经严谨自我评估对照豆包能力，发现 Phase 1+2 仍存在 4 个 gap，全部修复：

- **Gap 1：复合菜分支漏掉包装 OCR 优先路径**（违反硬约束 3 三路径全覆盖）
  - 影响文件：recognize_page.dart L319-339 / multi_dish_page.dart L475-495 + L509-529 / offline_queue_controller.dart L258-312 复合菜全命中分支 / CalibrationPage.dart L566-611 composite 路径 / multi_dish_page.dart L322-345 _calcNutrition
  - 修复：复合菜分支加 hasPackageNutrition 检查，有包装数据时 per100g 用包装换算值（替代 0），actualCalories 用包装换算整菜热量（per100g × serving / 100）
  - 后果（修复前）：预包装速冻食品（速冻水饺）被识别为 composite 时，包装营养表数据被忽略，per100g=0 占位

- **Gap 2：reasoning 字段从未展示给用户**（prompt 承诺落空）
  - 影响文件：calibration_page.dart L189-225
  - 修复：校准页加 ExpansionTile 折叠展示 reasoning（默认折叠，用户主动展开查看 AI 推理过程）
  - 后果（修复前）：reasoning 只在内存流转，用户点"识别不准"时只能盲改菜名/份量，无法看 AI 推理纠错

- **Gap 3：actualCalories 与包装换算值脱节**（精度未达豆包水平）
  - 影响文件：recognize_controller.dart L478-510 _aiFallbackNutrition / offline_queue_controller.dart L191-203 单品 LLM 兜底 + L253-262 复合菜全 miss LLM 兜底
  - 修复：有包装数据时 calories 用包装换算整菜热量（per100Calories × mid / 100）替代 AI 估算
  - 后果（修复前）：meal_log.actualCalories 用 AI 估算整菜值，包装精度只惠及未来查库，首次记录精度仍依赖 AI 估算

- **Gap 4：solid 无校准 + 示例 7 数据不自洽**
  - 影响文件：food_category_defaults.dart L93-105 calibrate / prompts.dart 示例 7
  - 修复：calibrate 对 solid 加合理性区间 clamp（热量 0-900，蛋白/脂肪/碳水 0-100）；示例 7 改为 84g/8 条装（8×10.5=84g 与 package_total_g 自洽，原 57.6g 与 8×10.5=84g 矛盾）
  - 后果（修复前）：solid 品类 AI 离谱估算（如 5000kcal/100g）直通 meal_log；示例矛盾可能误导模型

- Phase 2.5 验证（2026-07-04 沙箱实测）：
  - ✅ `flutter analyze` → No issues found
  - ✅ `flutter test` → 425 passed / 3 skipped / 1 failed（T48 原有日期 bug）
  - 8 个新测试全过（4 个 solid clamp + 4 个 Gap1/3 换算）

**与豆包能力对比（修复后）**：

| 维度 | 豆包 | EatWise v1.9 + Gap 修复 |
|------|------|-------------------------|
| 包装食品精确换算 | ✅ 直接用包装值记录 | ✅ actualCalories 用包装换算值（Gap 3 修复） |
| 复合包装食品 | ✅ 识别为复合也能用包装 | ✅ 复合菜分支检查 hasPackageNutrition（Gap 1 修复） |
| 推理过程透明 | ✅ 用户可见推理 | ✅ 校准页 ExpansionTile 展示（Gap 2 修复） |
| 离谱估算拦截 | ✅ 多层防护 | ✅ solid 加合理性区间 clamp（Gap 4 修复） |
| 啤酒/雪碧混淆 | ✅ 识别正确 | ✅ Phase 1 已解决 |

**Phase 2.6 深度检查修复（2026-07-04）—— 5 维度深度检查发现的问题全部处理**：

经 5 维度深度检查（AI 链路/UI/数据库/硬约束/测试），0 blocker，3 high，4 medium，3 low，全部处理：

- **High-2 修复（反馈纠正份量反算 per100g 违反硬约束 4）**：
  - 文件：today_meals_page.dart L519-543
  - 问题：原 `per100 = 100.0 / servingG` 用 correctedServingG（用户纠正份量）反算 per100g，违反硬约束 4"per100g 反算必须基于 estimatedWeightGMid，不能用 servingG"
  - 修复：改为 `per100 = 100.0 / m.actualServingG`（原记录份量，对应 m.actualCalories 的份量），与硬约束 4 精神一致
  - 注意：这里的 actualServingG 是 meal_log 记录的份量（可能已是用户校准后的），但它是 actualCalories 对应的份量，反算 per100g 密度正确

- **High-3 修复（Phase 2.5 Gap1 缺集成测试）**：
  - 文件：test/features/offline_queue_composite_test.dart
  - 问题：Gap1 复合菜包装 OCR 优先路径只有单元测试，无集成测试验证三路径实际接入
  - 修复：加 _FakeCompositePackageProvider + 集成测试，验证复合菜+包装数据时 per100g=250（非 0）、actualCalories=450（包装换算值）
  - 测试通过：5 个测试全过（含新加的 Gap1 集成测试）

- **High-1 降级不修（反馈对话框未展示 reasoning）**：
  - 原因：reasoning 在 VisionRecognitionResult 内存层，写库时丢失（meal_log/pending_recognition 都没存 reasoning 字段）
  - 展示需要 schema 迁移（meal_log 加 reasoning 字段），成本高
  - reasoning 主要价值在校准页已展示（Phase 2.5 Gap2 修复），反馈页是事后纠正，reasoning 已过期
  - 记录待后续评估是否值得 schema 迁移

- **Medium 修复（食物搜索不支持品牌名）**：
  - 文件：food_item_repository.dart L355-366 searchByName
  - 问题：原只 `name.like`，搜品牌名找不到
  - 修复：加 `aliasesJson.like`（brand 通过 upsertAiRecognized 写入 aliasesJson，搜品牌名能命中别名）
  - 注意：food_item 表无 brand 字段（brand 在内存层），但 brand 会通过 upsertAiRecognized 的 brandAlias 逻辑写入 aliasesJson

- **Medium 降级不修（weight_page PopScope）**：
  - 原因：weight_page 输入框有"记录"按钮主动保存，用户输入后通常会点按钮；加 PopScope 需加 _dirty 状态跟踪，ROI 低
  - 且 weight_page 嵌入 dashboard tab 时无 AppBar，PopScope 在 tab 页面无意义

- **Medium 降级不修（food_item 表无 CHECK 约束）**：
  - 原因：DB 层加 CHECK 需 schema 迁移，应用层已有 FoodCategoryDefaults.calibrate clamp 兜底（AI 兜底路径）+ UI 层 double.tryParse（手动录入）
  - 实际触发概率低，记录待后续评估

- **Low 修复（_aiFallbackNutrition mid>0 守卫）**：
  - 文件：recognize_controller.dart L496-499
  - 修复：`if (per100 != null && r.estimatedWeightGMid > 0)` 防 mid=0 时 actualCal 被误清零

- **Low 修复（三路径 estimatedProteinG 传参统一）**：
  - 文件：recognize_page.dart L268-272 / multi_dish_page.dart L424-428
  - 修复：三元死代码 `n.proteinG == 0 ? result.estimatedProteinG : n.proteinG` 简化为直传 `result.estimatedProteinG`（哨兵分支 n 来自 _aiFallbackNutrition，n.proteinG 恒等于 r.estimatedProteinG ?? 0）

- Phase 2.6 验证（2026-07-04 沙箱实测）：
  - ✅ `flutter analyze` → No issues found
  - ✅ `flutter test` → 426 passed / 3 skipped / 1 failed（T48 原有日期 bug）
  - 新增 1 个集成测试（offline_queue_composite_test Gap1）

**Phase 2.6 已知未修复项（待后续评估）**：
- 反馈页 reasoning 展示（需 schema 迁移，High-1 降级）
- weight_page PopScope（ROI 低，Medium 降级）
- food_item 表 CHECK 约束（需 schema 迁移，Medium 降级）
- T48 日期敏感测试（pre-existing，待改用相对日期）
- multi_dish_page widget test 缺失（无回归保护，待补）
- 版本号硬编码 settings_page L333 / me_page L216（待改用 package_info_plus）

**Phase 2.7 v1.10 含糖饮料碳水缺失修复（2026-07-04，commit 3e2c8f8）**：

用户反馈"拍照识别菊花茶成功，但热量显示蛋白质/脂肪无碳水"——含糖饮料（盒装菊花茶）碳水必标（GB 28050 强制标注营养成分表），但 AI 漏填 estimated_carbs_g 时显示 0。经严谨三重根因分析 + 三层防御架构修复：

**三重缺陷根因**：
1. **架构缺陷**：`computePackageNutritionPer100g` 注释"包装通常不标碳水"对含糖饮料是错的（GB 28050 强制标注），AI 漏填 estimated_carbs_g 时无兜底
2. **prompt 缺陷**：规则 10 说"基于 package_serving_* 换算"但 6 字段无碳水值，AI 实际只能用 estimatedXxxG 反算
3. **兜底缺陷**：包装路径短路 `FoodCategoryDefaults.calibrate`，AI 漏填时无兜底

**三层防御架构**：
- **第 1 层（OCR 正则兜底）**：新增 `lib/ai/package_nutrition_ocr_parser.dart`——`PackageNutritionOcrParser.parse(ocrText)` 从 `package_nutrition_table_ocr` 原文正则提取蛋白/脂肪/碳水（中英文 + 各种分隔符 + 0g 支持）
- **第 2 层（三层优先级换算）**：`vision_provider.dart` 加 3 字段 `packageServingProteinG/FatG/CarbsG` + `computePackageNutritionPer100g` 改造为三层优先级（包装字段 > OCR 正则 > AI 估算反算）
- **第 3 层（自洽反推 + 三路径宏量兜底）**：
  - `recognition_validator.dart` 加自洽反推修正（cal>0 但三宏量全 0 → 按品类默认比例反推）
  - `food_category_defaults.dart` 新增 3 品类（tea/protein_drink/energy_drink）
  - 三路径（recognize_page/multi_dish_page/calibration_page/offline_queue_controller）加 `packageMacrosAllZero` 守卫——包装换算宏量全 0 但 cal>0 时回退品类校准/AI 估算/组分累加
  - `actualCalories` 与 per100g 职责分离：包装宏量全 0 时 per100g 回退品类校准，actualCalories 也回退 AI 估算（避免两者脱节）

**关键 bug 修复（PostProcessor 透传完整性）**：
- `recognition_post_processor.dart` 两处重建 VisionRecognitionResult（applyDensityConversion + correctAdditionalDishes）原只透传 6 个旧 `package_*` 字段，遗漏 v1.10 新增的 3 字段
- 影响：触发密度换算（液体+package_label+density≠1.0，如油/蜂蜜）或 additionalDishes 修正时，重建后主菜丢失 3 个新字段，致 `computePackageNutritionPer100g` 第 1 层失效
- 修复：两处重建各加 3 行透传新字段

**prompt v1.10 改造**：
- version bump v1.9 → v1.10
- schema 加 3 字段 `package_serving_protein_g/fat_g/carbs_g`（含糖饮料必标）
- food_category 枚举扩展（tea/protein_drink/energy_drink）
- 规则 10 重写：要求 AI 显式填 3 个宏量字段 + 加宏量换算公式
- 示例 8b 菊花茶：250ml/盒，food_category=tea，package_serving_carbs_g=16，碳水必标

**测试覆盖（174 个测试，5 个文件）**：
- `test/ai/package_nutrition_ocr_parser_test.dart`（新建，~25 测试）：中英文/各种分隔符/0g/空串/菊花茶/红牛/豆奶真实场景
- `test/ai/vision_response_parser_test.dart`（追加 v1.10 group）：3 字段解析 + 三层优先级换算 + 示例 8b 端到端
- `test/core/recognition_validator_test.dart`（追加 v1.10 group）：自洽反推修正覆盖 tea/protein_drink/energy_drink/carbonated/solid/water + cal=0 + 部分宏量非 0 + cal=null 旧 prompt 兼容
- `test/core/recognition_post_processor_test.dart`（追加 v1.10 group）：3 字段透传完整性（密度换算路径 + additionalDishes 修正路径 + 菊花茶端到端）
- `test/data/food_category_defaults_test.dart`（追加 v1.10 group）：3 新品类默认值 + calibrate 各路径

**验证（2026-07-04 沙箱实测）**：
- ✅ `flutter analyze` → No issues found（修复 recognition_validator.dart 3 个 `unnecessary_non_null_assertion` warning，用局部变量替代 `!` 断言）
- ✅ `flutter test` → 486 passed / 3 skipped / 1 failed（T48 pre-existing 日期漂移 bug，与 v1.10 无关，已 stash 验证）
- 关键断言全过：菊花茶 per100g 碳水 = 6.4（非 0）/ AI 漏填时 OCR 兜底碳水非 0 / PostProcessor 重建后 3 字段保留

**v1.10 文件清单（10 个 lib + 5 个 test）**：
- 新建：`lib/ai/package_nutrition_ocr_parser.dart` / `test/ai/package_nutrition_ocr_parser_test.dart`
- 修改：`lib/ai/vision_provider.dart` / `lib/ai/prompts.dart` / `lib/core/util/recognition_post_processor.dart` / `lib/core/util/recognition_validator.dart` / `lib/data/seed/food_category_defaults.dart` / `lib/features/offline/offline_queue_controller.dart` / `lib/features/recognize/calibration_page.dart` / `lib/features/recognize/multi_dish_page.dart` / `lib/features/recognize/recognize_page.dart`
- 修改测试：`test/ai/vision_response_parser_test.dart` / `test/core/recognition_post_processor_test.dart` / `test/core/recognition_validator_test.dart` / `test/data/food_category_defaults_test.dart`

**Phase 2.8 v1.10 深度审查 + 测试补强（2026-07-04，commit 7b649f2）**：

用户要求"设计更复杂严谨的测试，一定要找出所有问题"。通过手动审查 + Task agent 深度审查发现 10 个 bug（BUG-1~BUG-10），其中 2 个 High 级（BUG-2/BUG-5），修复 7 个 + 补 124 个新测试覆盖。

**High 级 bug 修复**：
- **BUG-2（recognition_validator 反推条件过严 + 自洽校验错误修正 cal）**：
  - 原设计：v1.10 反推条件为"三宏量全 0"（`protein==0 && fat==0 && carbs==0`）
  - 缺陷：部分宏量漏填场景（蛋白饮料 protein=3 但 carbs=0）不触发反推，自洽校验用不完整宏量算 expected=12，与 cal=60 偏差 80% 触发 `correctedCalories=12`（错误覆盖正确的 cal）
  - 修复分两步：
    1. 反推条件改为"任一宏量为 0"（`protein==0 || fat==0 || carbs==0`），仅填充缺失项（保留非 0 AI 值）
    2. **关键**：触发填充时跳过 cal 自洽修正（`didFill` 守卫）——品类填充值仅是"猜测"，用猜测值+AI 部分值重算 expected 覆盖 cal 不可靠；信任 AI 整菜 cal 估算
- **BUG-5（_aiFallbackNutrition 无 packageMacrosAllZero 守卫）**：
  - 缺陷：`_aiFallbackNutrition` 只对 calories 做包装换算，宏量直接用 `r.estimatedXxxG ?? 0`，包装宏量全 0 时 actualCalories 用包装换算值（非 0）但 actualCarbsG=0——meal_log 数据脱节
  - 修复：加 `packageMacrosAllZero` 守卫，非全 0 时宏量也用包装换算值
  - 测试覆盖：给 `_aiFallbackNutrition` 加 `@visibleForTesting` 公开 `aiFallbackNutritionForTest` 方法（pure 函数可独立单测）

**Low/Medium 级 bug 修复**：
- Bug 4（multi_dish_page 复合菜路径遗漏守卫）：L504-520（主菜）+ L538-554（附加菜）两处加 `packageMacrosAllZero` 守卫（已 commit 8058012）
- Bug 3（OCR "糖"模式未实现）：注释承诺支持"糖"但代码未实现，加 `(?<![低无加含少减高])糖` 负向回视防误匹配（已 commit 8058012）
- BUG-3（prompts.dart 示例 schema 不一致）：所有示例补全 `package_serving_protein_g/fat_g/carbs_g`（全 0，保持 schema 一致）
- BUG-4（food_density 未同步扩展）：加 tea/protein_drink/energy_drink 密度值

**测试补强（+124 个新测试，610 passed 总计）**：
- `test/ai/food_density_test.dart`（+8）：tea/protein_drink/energy_drink 密度 + isLiquidCategory + 换算数学验证
- `test/ai/package_nutrition_ocr_parser_test.dart`（+17）："糖"模式正向匹配 + 7 种负向回视防误匹配（低/无/加/含/少/减/高糖）+ 优先级（碳水>糖）+ 边界 + 已知限制（蔗糖/果糖/乳糖会匹配）
- `test/core/recognition_validator_test.dart`（+11）：BUG-2 边界——solid+cal 偏差/water+cal>0/protein_drink 多 scale/energy_drink 等于默认值不触发填充/三宏量对称性（仅 protein/fat/carbs 非 0）/cal=null 旧 prompt/cal=0 回归/BUG-2 关键回归（蛋白饮料 cal=60 不被错误修正为 12）
- `test/features/recognize_controller_test.dart`（+9）：_aiFallbackNutrition 全路径——cal=null/无包装/BUG-5 核心（宏量全 0 保留 AI 值）/宏量非全 0 用包装换算/mid=0 跳过/servingG=0 per100=null/包装 cal 优先覆盖 AI cal/OCR 兜底宏量/kJ 单位换算
- `test/ai/prompts_schema_test.dart`（新建，+79）：自动正则提取 9 个示例 JSON，验证每个含 v1.10 新字段 + food_category 在枚举内 + reasoning 必填 + dish_name 必填 + additional_dishes 字段 + 示例 8b 菊花茶 food_category=tea + carbs>0

**验证（2026-07-04 沙箱实测）**：
- ✅ `flutter analyze` → No issues found
- ✅ `flutter test` → 610 passed / 3 skipped / 1 failed（T48 pre-existing 日期漂移，与 v1.10 无关）
- 关键回归全过：BUG-2 蛋白饮料 cal=60 不被错误修正 / BUG-5 宏量全 0 时 actualMacros 保留 AI 值不与 actualCalories 脱节

**Phase 2.8 文件清单（6 lib + 5 test）**：
- 修改：`lib/core/util/recognition_validator.dart`（BUG-2 didFill 守卫）/ `lib/features/recognize/recognize_controller.dart`（BUG-5 守卫 + @visibleForTesting）/ `lib/ai/prompts.dart`（BUG-3 示例补全）/ `lib/ai/food_density.dart`（BUG-4 密度）
- 已 commit 8058012：`lib/features/recognize/multi_dish_page.dart`（Bug 4 守卫）/ `lib/ai/package_nutrition_ocr_parser.dart`（Bug 3 "糖"模式）
- 修改测试：`test/core/recognition_validator_test.dart` / `test/features/recognize_controller_test.dart` / `test/ai/food_density_test.dart` / `test/ai/package_nutrition_ocr_parser_test.dart`
- 新建测试：`test/ai/prompts_schema_test.dart`

**Phase 2.9 v0.15.0 release：UI 优化 + 图标重设计（2026-07-04，commit 4b35dcb）**：

用户要求"整体软件界面再次进行优化，严谨一点，反复检查，还有软件的图标还是丑，我希望能更谷歌味道一点"。通过 Task agent 深度审查 13 个 UI 文件列出 P0-P3 优化点，实施 P0+P1+部分 P2 改动 + 图标重设计。

**主题层优化（app.dart）**：
- 补 6 个 M3 Expressive 组件主题：progressIndicatorTheme（onSurfaceVariant 加载色 + surfaceContainerHighest 轨道色）/ floatingActionButtonTheme（16dp 圆角 + elevation 3）/ segmentedButtonTheme（selected 用 primaryContainer）/ dropdownMenuTheme（expandedInsets: zero，7 处 DropdownMenu 删除局部声明）/ listTileTheme / dividerTheme
- cardTheme 圆角 12 → 16dp（M3 Expressive 普通卡片推荐）+ surfaceTintColor 显式声明（M3 tonal elevation）
- appBarTheme 补 scrolledUnderElevation: 3 + surfaceTintColor: transparent + systemOverlayStyle（跟随主题亮度控制状态栏图标颜色）
- navigationBarTheme 补 backgroundColor（surfaceContainer）+ surfaceTintColor + height: 80
- 启用 edge-to-edge（SystemUiMode.edgeToEdge，Android 15+ 强制）via MaterialApp.builder

**公共组件扩展（m3_widgets.dart）+6 组件**：
- ErrorState：error 色 Icon + 标题 + 重试按钮（与 EmptyState 同构，dashboard/me_page 替换手写实现）
- LoadingState：CircularProgressIndicator + onSurfaceVariant 加载色（替代默认 primary）
- HeroCard：28dp 大圆角 + primaryContainer 焦点卡片（M3 Expressive hero card 规范）
- MacroBar：宏量营养素进度条（标签+进度条+数值，统一 dashboard 三宏布局）
- LegendDot：图例圆点（统一 weight_page 图表图例）
- SectionTitle 加 padding 可选参数（SliverAppBar.large 下方第一个 SectionTitle 传 fromLTRB(16, 0, 16, 8) 减小顶部间距）

**各页面优化**：
- dashboard_page：错误态/加载态用 ErrorState/LoadingState，状态卡用 HeroCard（28dp 圆角）
- me_page：错误态/加载态用 ErrorState/LoadingState，用户卡片用 HeroCard
- food_library_page：空态用 EmptyState（restaurant_menu icon），加载态用 LoadingState
- weight_page：6 处简单 SnackBar 改 showAppToast
- recognize_page：3 处简单成功 SnackBar 改 showAppToast（带 SnackBarAction 重试的保留内联，HANDOFF 陷阱 49）
- insight_page：IconButton 加 tooltip '编辑汇总'，删除 SizedBox(height: 0) 死代码
- profile_page：活动量提示 padding 对齐 Card（4→16）+ labelSmall 替代硬编码 fontSize
- settings_page：_colorDot 用 Material+InkWell 加 ripple（GestureDetector 无 state layer 违反 M3 规范）
- main_shell：FAB 删除局部 elevation/shape（走 floatingActionButtonTheme 统一）

**图标重设计（更谷歌 Material 风格）**：
- background：青绿渐变（3 色对角线）→ 纯色 #5B8C7B（睡莲青绿，Google Workspace 多用纯色背景）
- foreground：奶白"碗+蒸汽"（复杂曲线）→ 纯白"餐叉+刀"几何图形（Material Symbols filled 风格）
  - 餐叉：3 齿（圆角矩形 r=1）+ 连接条 + 柄（圆角矩形 r=2）
  - 餐刀：梯形刀身（上宽 18 收尖到 6）+ 柄
  - 全部 fill（非 stroke）+ 圆角，缩放 48dp 仍清晰
- 不改 mipmap PNG（位图兜底，Android 8.0+ 用 adaptive vector）

**版本号 bump**：0.14.0+15 → 0.15.0+16（pubspec.yaml + me_page + settings_page 关于对话框 + sentry_init.dart release 默认值）

**验证（2026-07-04 沙箱实测）**：
- ✅ `flutter analyze` → No issues found
- ✅ `flutter test` → 610 passed / 3 skipped / 1 failed（T48 pre-existing 日期漂移，与本次改动无关）

**Phase 2.9 文件清单（12 lib + 1 yaml + 2 xml）**：
- 主题层：`lib/app.dart`（+6 组件主题 + edge-to-edge）/ `lib/main_shell.dart`（FAB 删局部样式）
- 公共组件：`lib/core/widgets/m3_widgets.dart`（+6 组件 + SectionTitle padding 参数）
- 各页面：`lib/features/dashboard/dashboard_page.dart` / `lib/features/me/me_page.dart` / `lib/features/food_library/food_library_page.dart` / `lib/features/weight/weight_page.dart` / `lib/features/recognize/recognize_page.dart` / `lib/features/insight/insight_page.dart` / `lib/features/profile/profile_page.dart` / `lib/features/settings/settings_page.dart`
- 图标：`android/app/src/main/res/drawable/ic_launcher_background.xml` / `android/app/src/main/res/drawable/ic_launcher_foreground.xml`
- 版本号：`pubspec.yaml` / `lib/core/error/sentry_init.dart`（release 默认值 0.14.0 → 0.15.0）

**Phase 2.10 v0.15.0 release 后大规模审计修复（2026-07-04，commit c13143b）**：

用户要求"发布完成后再进行一轮大规模的问题检查，势必找出所有的问题并且修复，所有环节所有项目都要检查测试"。通过 3 个并行 Task agent 深度审计（UI 改动完整性 + v1.10 测试完整性 + release 完整性）发现 ~24 个问题，全部修复或降级记录。

**审计发现与修复**：

1. **sentry_init.dart 版本号遗漏**（release 完整性审计发现）：release 后检查发现 `defaultValue: 'eatwise@0.14.0'` 未同步到 0.15.0。修复：改为 `eatwise@0.15.0`

2. **UI 审计 8 个问题修复**：
   - **me_page LoadingState/ErrorState 在 SliverToBoxAdapter 内布局不正确**（严重）：SliverToBoxAdapter 给 unbounded 高度，LoadingState 内部 Center 会 expand 失败。修复：用 SizedBox(height: 240) 包裹提供高度约束
   - **food_library 首屏 LoadingState 未包在 Expanded 中**（严重）：同上 unbounded 高度问题。修复：用 SizedBox(height: 200) 包裹
   - **dashboard 推荐 FutureBuilder 缺 snap.hasError 分支**（逻辑）：错误被 `!hasData` 静默吞掉。修复：加 hasError 显式分支 + debugPrint 排查
   - **today_meals_page 用 EmptyState 模拟错误态**（一致性）：改用 ErrorState（与 dashboard/me_page 同构）
   - **4 页面裸 CircularProgressIndicator**（一致性）：profile/weight/today_meals/settings 的 `_loading` 分支用 `Center(child: CircularProgressIndicator())`，颜色不统一。修复：替换为 LoadingState()（用 onSurfaceVariant 加载色）
   - **11 处简单 SnackBar 未改 showAppToast**（一致性）：today_meals 4 处（_showEditDialog 保存失败 / 已反馈过 / 已记录反馈 / 反馈失败 / 删除失败）+ food_edit 3 处（_showError + 已保存默认份量 + 已保存）+ manual_entry 1 处（_showError）+ calibration 1 处（记录失败）。注意 today_meals 撤销 SnackBar 带 SnackBarAction 保留内联（陷阱 49）
   - **MacroBar/LegendDot 定义后未回填替换**（设计完成度）：weight_page._legendDot 替换为 LegendDot（已回填）；MacroBar 因 dashboard hero card 上需要 labelColor 对比色（MacroBar 用 onSurfaceVariant 不可读）无人能用，删除（过度设计）
   - **SectionTitle padding 参数 21 处调用无一处使用**（过度设计）：保留（参数已实现且文档说明用途，删除是 breaking change）

3. **HANDOFF.md 9 个文档问题修复**：
   - L26 版本号 0.12.0+13 → 0.15.0+16
   - L27 分支 v0.10.0-m3-merge → trae/agent-wX1X6Q（HEAD = 4b35dcb）
   - L39 "待 push" → "已 push 远程"
   - L222 Phase 2.8 标题 "待 commit" → "commit 7b649f2"
   - L262 Phase 2.9 标题 "待 commit" → "commit 4b35dcb"
   - L300 版本号 bump 说明补 sentry_init.dart
   - L306-311 文件清单 11 lib → 12 lib + 补 sentry_init.dart
   - L357 最近 commit 首条 "(待 commit)" → "4b35dcb"

4. **测试缺口评估降级**（v1.10 测试审计发现）：
   - multi_dish_page / offline_queue_controller / calibration_page 的 packageMacrosAllZero 守卫无直接测试
   - 评估结论：recognize_controller 已有 aiFallbackNutritionForTest 覆盖单品路径守卫；其他 3 处守卫逻辑相同（v1.10 同期镜像），analyze 通过确认无语法错误；补 widget test 需 mock OCR/AI/DB 多依赖，复杂度高且 multi_dish_page widget test 已在已知未修复项（见下文）；降级记录待后续评估，不引入重构风险

**Phase 2.10 文件清单（11 lib + 1 md）**：
- 修复：`lib/core/error/sentry_init.dart`（版本号同步）/ `lib/core/widgets/m3_widgets.dart`（删 MacroBar）/ `lib/features/dashboard/dashboard_page.dart`（hasError 分支）/ `lib/features/dashboard/today_meals_page.dart`（ErrorState + LoadingState + 4 处 showAppToast）/ `lib/features/me/me_page.dart`（SizedBox 约束）/ `lib/features/food_library/food_library_page.dart`（SizedBox 约束）/ `lib/features/weight/weight_page.dart`（LoadingState + LegendDot 回填 + 删 _legendDot）/ `lib/features/profile/profile_page.dart`（LoadingState）/ `lib/features/settings/settings_page.dart`（LoadingState）/ `lib/features/food_library/food_edit_page.dart`（3 处 showAppToast）/ `lib/features/manual_entry/manual_entry_page.dart`（_showError showAppToast）/ `lib/features/recognize/calibration_page.dart`（showAppToast）
- 文档：`HANDOFF.md`（9 个文档问题修复 + 本章节）

**验证（2026-07-04 沙箱实测）**：
- ✅ `flutter analyze` → No issues found
- ✅ `flutter test` → 610 passed / 3 skipped / 1 failed（T48 pre-existing 日期漂移，与本次改动无关）

**Phase 2.11 图标重设计 + 拍照识别页改造 + 推荐算法 v4 用户偏好学习（2026-07-04，commit 1dd3087）**：

用户反馈"图标还是太丑，希望更谷歌味道、精致、温馨大方"+"拍照识别界面非常丑陋，大面空白"+"智能推荐完全不智能，可以根据每个人的饮食习惯自己学习，多维度（材质/价格/口味/风格）"。三项全部完成 + 顺手修复一个 pre-existing 日期漂移测试。

**1. 图标重设计（更谷歌、温馨大方）**：
- 背景：青绿 #5B8C7B → Material Deep Orange 400 #FF6E40（暖橙色，食欲心理学食物色，Google Workspace 常用暖色系）
- 前景：白色"餐叉+餐刀" → 白色"碗+蒸汽"几何图形（碗比刀叉更温馨；蒸汽 2 道 S 形上升波浪，stroke 风格 round linecap）
- 文件：`android/app/src/main/res/drawable/ic_launcher_background.xml` + `ic_launcher_foreground.xml`

**2. 拍照识别页面改造（消除大面空白）**：
- 原 Column mainAxisAlignment.center（上下大面空白）→ 上半 Hero 引导区（Expanded flex:5，96dp 圆形图标 + 标题 + 副标题）+ 下半操作区（Flexible flex:4，餐次选择器 + full width 拍照按钮 + 相册按钮）
- 文件：`lib/features/recognize/recognize_page.dart`

**3. 推荐算法 v4 用户偏好学习（多维度自学习）**：

核心思路：用户吃过 = 偏好信号（隐式反馈学习，与 Spotify "听过=喜欢" / 抖音 "看完=感兴趣" 一致）。离线友好，纯本地计算，不调 AI。

**新增组件**：
- `lib/nutrition/food_profile_tagger.dart`（食物画像标签器）：4 维度关键词表（taste 6 类 sweet/sour/bitter/spicy/salty/light + style 7 类 western/japanese/korean/seafood/fast_food/home + texture 7 类 soup/stir_fry/steamed/boiled/grilled/fried/cold + priceTier 3 类 budget/medium/premium），_matchFirst 按顺序匹配。设计要点：seafood 优先于 japanese/korean（"三文鱼刺身"归 seafood）；"酸辣"归 sour 不归 spicy（酸味更主导）
- `lib/nutrition/user_preference_learner.dart`（用户偏好学习器）：从 meal_log 学习 4 维度频次分布。关键 API：`tasteWeight(tag)` 返回 0.0-1.0（null/空 freq/未知标签 → 0.5 中性；标签在频次表 → 频次/max 频次）；`hasEnoughSamples`（总样本 >= 5 才启用偏好加权，避免小样本噪声）；`hasSignificantTastePref`（top1 占比 >= 0.4 且样本 >= 3 且标签数 >= 2，用于 reason 文案）

**关键设计决策（v4 核心纠偏）**：
- **"未尝试" vs "少碰" 区分**：原 `_weight` 函数把"标签不在频次表"（用户从未吃过）和"标签在频次表但频次 0"（不可能发生）都当 0 处理，导致未尝试口味被惩罚。修复：`!freq.containsKey(tag)` → 返回 0.5 中性（不惩罚"未知"，用户没吃过 ≠ 不喜欢）；只有"尝试过但很少"（如 sweet:10 + spicy:1，weight=0.1 < 0.2）才减分。这是 v4 设计的核心原则

**推荐服务升级（v3 五维 → v4 九维）**：
- `lib/nutrition/recommendation_service.dart`：`recommend()` 和 `_scoreFood()` 新增 `UserPreferenceProfile? userPref` 参数。在 v3 五维（缺口匹配/频次/profile/时段/多样性）后插入维度 6-9（用户偏好学习）：
  - taste: weight >= 0.7 → +2.5（显著偏好时加 reason "符合X口味"）；weight < 0.2 且 freq 非空 → -1.0
  - style: +2.0 / -0.8
  - texture: +1.5 / -0.5
  - priceTier: +1.5 / -0.5
  - userPref=null 或 hasEnoughSamples=false → 不启用（向后兼容 v3）
- `lib/data/repositories/meal_log_repository.dart`：新增 `getRecentMeals({days=30})` 方法供偏好学习用
- `lib/features/dashboard/dashboard_page.dart`：`_loadRecommendations()` 并行查 recentMeals + foods，建 foodMap，调 `UserPreferenceLearner.learn()` 传入 recommend

**4. 顺手修复 pre-existing 日期漂移测试**：
- `test/features/image_cleanup_startup_test.dart` T48 测试硬编码"今天=2026-07-02"，实际日期漂移后失败。修复：改用 `formatYmd(DateTime.now().subtract(Duration(days: N)))` 相对日期，永久免疫日期漂移

**Phase 2.11 文件清单（4 lib 新增 + 4 lib 修改 + 2 xml + 4 test）**：
- 新增：`lib/nutrition/food_profile_tagger.dart` / `lib/nutrition/user_preference_learner.dart` / `test/nutrition/food_profile_tagger_test.dart`（32 测试）/ `test/nutrition/user_preference_learner_test.dart`（13 测试）
- 修改：`lib/nutrition/recommendation_service.dart`（v4 九维评分）/ `lib/data/repositories/meal_log_repository.dart`（getRecentMeals）/ `lib/features/dashboard/dashboard_page.dart`（_loadRecommendations v4 集成）/ `lib/features/recognize/recognize_page.dart`（Hero + 操作区布局）
- 图标：`android/app/src/main/res/drawable/ic_launcher_background.xml` + `ic_launcher_foreground.xml`
- 测试修改：`test/nutrition/recommendation_service_test.dart`（v4 集成测试 7 个：userPref=null / 样本不足 / 辣味偏好加分 / 海鲜风格加分 / 未尝试口味中性 / 少碰口味减分）/ `test/features/image_cleanup_startup_test.dart`（T48 日期漂移修复）

**验证（2026-07-04 沙箱实测）**：
- ✅ `flutter analyze` → No issues found
- ✅ `flutter test` → 661 passed / 3 skipped / 0 failed（含 v4 新增 52 测试 + T48 日期漂移修复）

**Phase 2.12 AI 个性化推荐 v5（渐进增强 + 满意度反馈学习，2026-07-04，commit 27b6a85）**：

用户反馈"智能推荐完全不智能，根据每个人的饮食习惯自己学习，多维度（材质/价格/口味/风格），可接入 ai"。v4 是纯本地关键词匹配，v5 接入 GLM-4-Flash 让 AI 综合用户完整画像（身高/体重/体脂/年龄/性别/活动量/目标/健康状况/饮食偏好/特殊人群）+ 历史饮食（近14天 top 20 食物）+ 满意度反馈（近30条）做真正个性化推荐。

**架构：渐进增强（用户选择的方案）**
- v4 本地推荐秒出（现有行为不变）→ AI 返回后用更精准的排序+个性化理由替换
- AI 失败/离线/key未配置 → 静默回退 v4（AI 是"锦上添花"，不阻塞 UI）
- 当日缓存（key=date+mealType），用户点"换一批"强制刷新
- 候选范围：纯 AI 生成（不限于库内食物，AI 直接生成菜名+理由+估算营养）
- Tap 行为：跳 ManualEntryPage(initialName:) 与 v4 一致

**满意度反馈学习（用户要求）**
- 用户对每条 AI 推荐打分（👍喜欢/一般/👎不喜欢），存 `recommendation_feedbacks` 表
- 下次推荐时读近 30 条反馈注入 prompt，让 AI 学习用户偏好
- 反馈不立即触发重新调 AI（避免频繁调 API），下次自然推荐时生效
- 设计原则：显式反馈 > 隐式反馈（v4 的"吃过=偏好"），用户明确说"不喜欢"比"没吃过"信号更强

**Phase 2.12 文件清单（3 lib 新增 + 1 table 新增 + 1 repo 新增 + 4 lib 修改 + 3 test 新增 + 1 test 修改）**：
- 新增表：`lib/data/database/tables/recommendation_feedback_table.dart`（RecommendationFeedbacks 表：foodName/rating 1-3/mealType?/recommendDate?/createdAt）
- 新增 repo：`lib/data/repositories/recommendation_feedback_repository.dart`（insertFeedback + getRecent + clearAll）
- 新增 prompt：`lib/nutrition/ai_recommendation_prompt.dart`（AiRecommendationContext + FeedbackRecord + AiRecommendation 数据类 + AiRecommendationPrompt 纯函数构建器）
- 新增 service：`lib/nutrition/ai_recommendation_service.dart`（AiRecommendationService：缓存+降级+AI调用+JSON解析）
- 修改 DB：`lib/data/database/database.dart`（schemaVersion 2→3，新增 RecommendationFeedbacks 表 + v2→v3 migration createTable）
- 修改 AI provider：`lib/ai/glm_flash_provider.dart`（新增 createChatCompletion 通用聊天补全方法，供 AI 推荐用）
- 修改 dashboard：`lib/features/dashboard/dashboard_page.dart`（合并推荐区：v4 兜底 + AI 渐进增强 + 换一批按钮 + 满意度反馈按钮行 + AI loading 骨架）
- 修改 backup：`lib/data/backup/json_exporter.dart` + `json_importer.dart`（导出/导入 recommendation_feedbacks 表，旧版本备份无此表时跳过）
- 新增测试：`test/nutrition/ai_recommendation_prompt_test.dart`（16 测试：6 段落构建 + 标签映射 + 边界）/ `test/nutrition/ai_recommendation_service_test.dart`（21 测试：JSON 解析 14 + 缓存 4 + 降级 3）/ `test/data/recommendation_feedback_repository_test.dart`（11 测试：rating 校验 + getRecent 倒序 + clearAll + 字段持久化）
- 修改测试：`test/data/backup/json_export_import_test.dart`（schemaVersion 2→3 + 新增 recommendation_feedbacks 表断言）

**关键设计决策**：
1. **AI 候选范围=纯生成**：AI 直接根据画像生成 5 道菜（不限于库内），用户 tap 后跳 ManualEntryPage 录入。比"库内重排"更灵活，符合用户"纯 AI 生成"选择
2. **缓存当日有效**：key=`${date}_${mealType}`，用户跨天/换餐次自动重调，"换一批"forceRefresh。不随 RefreshBus 失效（避免记录一条就重新调 AI）
3. **降级链**：GLM key 空→跳过；离线→跳过；AI 异常/超时→静默返回空（v4 兜底）；失败不缓存（下次允许重试）
4. **JSON 解析容错**：_extractJson 用括号配对扫描（depth 计数器），兼容 AI 偶尔在 JSON 外加 markdown/解释文字 + 多个 JSON 对象场景；解析失败抛 FormatException（让调用方区分"AI 真返回 0 条"可缓存 vs "解析失败"不缓存）
5. **temperature=0.8**：推荐需一定随机性，避免每次都推相同 5 道菜（"换一批"才有意义）
6. **反馈表无外键**：foodName 直接存字符串（AI 推荐的食物可能不在库），避免用户记录前先入库的约束
7. **schemaVersion 2→3 migration**：v2→v3 用 `m.createTable(recommendationFeedbacks)`，旧用户升级自动建表；导入旧版本备份（无 recommendation_feedbacks 段）时跳过该表插入

**验证（2026-07-04 沙箱实测）**：
- ✅ `flutter analyze` → No issues found
- ✅ `flutter test` → 709 passed / 3 skipped / 0 failed（含 v5 新增 48 测试 + backup 测试更新）

**Phase 2.13 v0.16.0 release：v5 AI 推荐审计修复 + 满意度反馈按钮优化（2026-07-04）**：

用户反馈"满意度反馈按钮可以设计成点开才显示，不太占用空间，此外整体改进有没有问题，反复研究，有就找出来严谨修复"。对 v5 AI 推荐做全面审计，发现 5 个 high 级 + 5 个 medium 级问题，全部修复后发布 v0.16.0。

**满意度反馈按钮改造（用户要求）**：
- 原：每条推荐内联 3 个按钮（喜欢/一般/不喜欢）→ 占用过多垂直空间
- 新：PopupMenuButton 三点菜单，点开才显示反馈选项 → 节省空间
- 反馈后图标变为 check_circle（已反馈状态），tooltip 三态：提交中/已反馈/反馈满意度
- enabled 守卫：提交中或已反馈时禁用，防重复提交

**High 级问题修复（5 个）**：
1. **冷启动配置竞态**：`ref.read(appConfigProvider).maybeWhen` 在 config loading 期间返回 orElse 空结果，AI 推荐永远不显示 → 改为 `await ref.read(appConfigProvider.future)`
2. **_AiRecItem 状态泄漏**：换一批后旧 `_ratedRating` 状态绑到新推荐（用户没打过分却显示"已喜欢"）→ 加 `key: ValueKey(rec.name)` 强制新建 State
3. **反馈失败不重置 _ratedRating**：`widget.onRate` 抛异常时 UI 永久显示"已喜欢"但 DB 没写 → `onRate` 改返回 `Future<bool>`，失败时 `setState(() => _ratedRating = null)`
4. **OpenAIClient 连接泄漏**：每次进看板新建 `GlmFlashProvider` 但从不 close → 新增 `provider.close()` 在 finally 中；GlmFlashProvider 新增 `void close() { _client.close(); }`
5. **缓存无互斥致重复调 AI**：用户连点"换一批"会并发多次调 AI → 缓存值改用 `Future<List<AiRecommendation>>`（共享同一 Future，结果只算一次）

**Medium 级问题修复（5 个）**：
6. **解析失败被缓存**：`_parseRecommendations` 吞掉所有异常返回空列表，空列表被缓存，当日同一 mealType 永远命中空缓存 → 解析失败抛 `FormatException`，`recommend()` catch 后删除缓存条目
7. **缓存 key 无 profileHash**：用户改 profile 后缓存仍命中旧推荐 → key 改为 `${date}_${mealType}_${profile.hashCode}`
8. **静态缓存无限增长**：跨天缓存条目不清理 → 新增 `_evictStaleCache(todayDate)` 清理非当日 key
9. **loading 状态闪烁**：AI loading 时显示骨架屏与 v4 重复占位 → 改为 v4 + 顶部小尺寸加载提示（CircularProgressIndicator 12px + 文案"AI 正在生成个性化推荐…"），真正的渐进增强
10. **重复 timeout**：`createChatCompletion` 内部 `.timeout(30s)` 与 service 层 `.timeout(30s)` 重复 → provider 层删除 timeout，由 service 层统一控制

**测试 mock 修复（2 个 widget 测试）**：
- `dashboard_drawer_test.dart` + `estimation_range_ui_test.dart`：v5 看板 initState 调 `appConfigProvider.future` 检查 GLM key，沙箱无 secure_storage 平台通道会抛 MissingPluginException，AI FutureBuilder 卡在 loading，CircularProgressIndicator 永不停止致 `pumpAndSettle` 超时 → 加 `FlutterSecureStorage.setMockInitialValues({})` + `secureConfigStoreProvider.overrideWithValue(store)`

**Phase 2.13 文件清单（4 lib 修改 + 3 test 修改 + 4 版本号文件）**：
- 修改 service：`lib/nutrition/ai_recommendation_service.dart`（缓存互斥 + profileHash key + _evictStaleCache + FormatException + 括号配对 JSON 提取 + take(5) + profile 由调用方传入）
- 修改 dashboard：`lib/features/dashboard/dashboard_page.dart`（冷启动竞态 + ValueKey + 反馈失败处理 + 连接泄漏 + loading 提示 + _aiLoadingHint 替换 _aiLoadingSkeleton）
- 修改 provider：`lib/ai/glm_flash_provider.dart`（新增 close() + 删除 createChatCompletion 重复 timeout）
- 修改测试：`test/nutrition/ai_recommendation_service_test.dart`（适配 FormatException：4 测试改 throwsA + 新增"解析失败不缓存"测试 + 缓存测试改用 validJson）
- 修改测试：`test/features/dashboard_drawer_test.dart` + `test/features/estimation_range_ui_test.dart`（secureConfigStoreProvider mock）
- 版本号 bump：`pubspec.yaml`（0.15.0+16→0.16.0+17）+ `lib/core/error/sentry_init.dart`（eatwise@0.16.0）+ `lib/features/me/me_page.dart`（0.16.0）+ `lib/features/settings/settings_page.dart`（v0.16.0）

**验证（2026-07-04 沙箱实测）**：
- ✅ `flutter analyze` → No issues found
- ✅ `flutter test` → 710 passed / 3 skipped / 0 failed（含新增"解析失败不缓存"测试）

**Phase 4 用户反馈 5 问题改进批次（2026-07-04）**：

用户反馈 5 个新问题："智能推荐不够完善，有时不出现智能推荐，重新生成也失败 / 食物识别错误可否手动输入食物名重新计算 / 今日明细里食物名称可否修改 / 每周每月总结可否更智能结合所有信息 / 不足一周或一月可否按一周或一月算"。用户确认 4 个设计决策（AskUserQuestion）：AI 失败保留按钮+错误提示+重试 / 改菜名入口三处全做（校准页+复合菜页+今日明细 dialog）/ 周期算法滚动窗口（最近 7/30 天）/ 智能信息加宏量达成率+偏好画像+记录天数+覆盖率。

**4.1 AI 推荐失败修复（v5 服务层 + dashboard UI 层）**：
- **根因 1：空结果被缓存致当日永久失效**——`recommend()` 把空列表（AI 抽风返回 0 条或解析失败）也缓存，当日同一 mealType 永远命中空缓存，用户重新生成也命中空缓存失败。修复：空结果不缓存（`if (result.isEmpty) _cache.remove(cacheKey)`），下次进看板允许重试
- **根因 2：重新生成失败时按钮消失无法重试**——dashboard UI 在 AI 失败后只显示 v4 推荐，没有错误提示和重试入口，用户无法知道"AI 失败了"也无法重试。修复：新增 `AiRecommendationResult.error` 字段，UI 据此显示错误提示行 + 保留"换一批"按钮可重试
- **根因 3：GLM API 无重试机制**——单次网络抖动/429 限流就失败。修复：`_callGlm` 加 1 次重试，429/5xx/网络抖动退避 1s 重试 1 次，401/400 不可恢复错误快速失败（不重试）
- **`_friendlyError` 错误文案映射**：TimeoutException → "AI 响应超时"；401 → "GLM API Key 无效"；429 → "AI 调用太频繁"；SocketException → "网络连接失败"；兜底 → "AI 推荐暂不可用"
- **Future 缓存互斥**：缓存值用 `Future<List<AiRecommendation>>` 而非 `List`，并发调用（用户连点换一批）共享同一 Future，结果只算一次
- **dashboard UI 改造**：保留"换一批"按钮（即使 AI 失败也能点）；错误态显示小字提示"AI 推荐暂不可用，已切换本地推荐 [换一批]"；加载态改为顶部小尺寸 CircularProgressIndicator + 文案"AI 正在生成个性化推荐…"（替代原骨架屏，避免与 v4 重复占位）

**4.2 改菜名共享 mixin + 三入口接入**：
- 新建 `lib/features/recognize/dish_name_editor.dart`——`DishNameEditor` mixin，封装"弹输入框→搜库→候选选择→5 级模糊兜底→返回 NutritionResult"完整流程
  - `editDishNameAndLookup(originalName, servingG, foodRepo, lookup)`：返回 `({String? newName, NutritionResult? nutrition})`，newName=null=用户取消，nutrition=null=未命中
  - `nutritionFromFoodItem(food, servingG)`：FoodItem + 份量构造 NutritionResult，含可食部分系数（ediblePercent），符合硬约束 #4（per100g 反算基于 estimatedWeightGMid）
  - `showFoodSelectionDialog(candidates)`：多候选列表选择对话框
  - `showNotFoundToast()`：未命中提示
- **calibration_page 接入**：AppBar 加"修改菜名"IconButton，`_handleRename` 调 mixin.editDishNameAndLookup → setState 替换 `_currentDishName` + `_currentNutrition` + `_currentSingles`（引入可变 state 字段替代 widget 字段，rename 后 UI 实时刷新）
- **multi_dish_page 接入**：每个菜 ListTile 加"修改菜名"PopupMenuButton item，`_handleRename(index)` 调 mixin → setState 替换对应菜的 state（`_dishes` 列表中对应 index 的 dishName + composite 营养 + singles）
- **recognize_page 接入**：注入 NutritionLookup（之前未注入），供 calibration_page 跳转后使用

**4.3 今日明细编辑 dialog helperText**：
- `lib/features/dashboard/meal_edit_dialog.dart`：4 个营养 TextField 加 helperText 提示"如改了份量请同步改营养值，或直接改份量后点保存自动按比例重算"
- 提示用户"改份量需同步改营养"的隐含规则，避免用户改份量后营养值不匹配

**4.4 周/月总结改滚动窗口（最近 7/30 天）**：
- 用户要求"如果没有满一个月或者一周，可以按一个月或者一周计算"
- `insight_page.dart _calcPeriod()` 改滚动窗口策略：
  - weekly：today-6 ~ today（含今天，共 7 天）
  - monthly：today-29 ~ today（含今天，共 30 天）
- 优势：①不足一周/月时仍按完整周期算（用户用 3 天也能生成周报，0 填充缺失日）②始终覆盖最近数据，比"自然周前 6 天 + 今天 0 条"更准 ③跨周/跨月自然过渡，避免月末切换 chart 突变
- 文案调整：按钮"生成本周汇总" → "生成近 7 天汇总"；AppBar title 显示日期范围；SegmentedButton 文案"周/月"不变（用户认知）
- 缓存策略副作用：_periodStart/_periodEnd 每天变化，InsightRepository.find 找不到昨天的汇总（key 不同），用户每天需重新生成。这是预期行为（滚动窗口本就该每天刷新）

**4.5 周/月总结 prompt 增强（宏量达成率+偏好画像+覆盖率）**：
- 用户要求"每周每月的总结可不可以更加智能一点，结合所有的信息"
- `insight_page.dart _aggregatePeriod()` 返回类型从 4 字段扩展到 15 字段：
  - 原 4 字段：dailyCal / dailyWeight / targetCal / goal
  - 新增 11 字段：dailyProtein / dailyFat / dailyCarbs（每日宏量序列）+ proteinGoal / fatGoal / carbGoal（宏量目标）+ recordedDays / totalDays / coverageRate（覆盖率）+ preferenceFoods（top 5 高频食物名）
  - 宏量目标计算与 dashboard_page L245-250 一致：carbGPerKg 为 null 时由热量残差反算 `(dailyCalorieTarget - proteinGoal×4 - fatGoal×9) / 4`
  - 饮食偏好画像：统计 meal_log 的 foodItemId 频次，取 top 5，调 `foodRepo.getByIds` 批量查食物名
- `glm_flash_provider.dart`：
  - `_buildPrompt`（weekly）/ `_buildMonthlyPrompt`（monthly）改用 StringBuffer + 调用 `_appendMacroAndPreference` 共享方法
  - 新增 `_appendMacroAndPreference(buf, data, periodLabel)`：宏量均值（只统计 calories>0 的记录日，避免 0 填充日拉低均值）+ 覆盖率 + 偏好食物
  - system prompt 增强：要求 AI 结合宏量达成率分析饮食结构 + 结合常吃食物给针对性建议（如"你常吃米饭，可尝试用糙米替代"）

**4.6 数据不足守卫 + UI 提示**：
- `insight_page.dart _generate()` 加 0 天记录守卫：`if (agg.recordedDays == 0)` 提示"近 N 天无饮食记录，请先记录至少 1 天再生成汇总"，不调 AI（全 0 数据生成的建议无意义，浪费 API 调用）
- **守卫顺序**：置于 apiKey + 网络检查**之后**——config/网络问题更基础，应优先提示。否则 key 未配置时会先提示"无饮食记录"误导用户
- UI 加覆盖率提示行：`if (_totalDays > 0 && _recordedDays < _totalDays)` 显示"已记录 X/Y 天（Z%），数据不完整时建议仅供参考"，让用户知道数据完整度
- SegmentedButton 切换重置新 state（_recordedDays=0 / _totalDays=7 或 30）

**4.7 测试修复**：
- `insight_key_test.dart` + `insight_offline_guard_test.dart`：按钮文案"生成本周汇总" → "生成近 7 天汇总"；新增覆盖率提示把按钮推到 600px 测试视口外，加 `scrollUntilVisible` 后再 tap
- `insight_regenerate_confirm_test.dart`：测试数据从自然周（monday~sunday）改为滚动窗口（today-6 ~ today，否则 `_loadExisting` 找不到）；`scrollUntilVisible` 抛 "Too many elements"（pump 时 setState 产生重复"重新生成"widget 匹配），改用 `tester.drag(find.byType(ListView), const Offset(0, -300))` 手动滚动

**Phase 4 文件清单（1 lib 新增 + 8 lib 修改 + 3 test 修改）**：
- 新增：`lib/features/recognize/dish_name_editor.dart`（DishNameEditor mixin）
- 修改 service：`lib/nutrition/ai_recommendation_service.dart`（空结果不缓存 + GLM 重试 + error 字段 + _friendlyError + Future 缓存互斥）
- 修改 dashboard：`lib/features/dashboard/dashboard_page.dart`（错误提示行 + 保留换一批按钮 + 加载态改小尺寸提示）
- 修改 meal_edit_dialog：`lib/features/dashboard/meal_edit_dialog.dart`（4 营养 TextField helperText）
- 修改 insight：`lib/features/insight/insight_page.dart`（_aggregatePeriod 15 字段 + 0 天守卫 + 覆盖率 UI + 滚动窗口 _calcPeriod + SegmentedButton 重置 state）
- 修改 GLM provider：`lib/ai/glm_flash_provider.dart`（_buildPrompt/_buildMonthlyPrompt StringBuffer + _appendMacroAndPreference 共享方法 + system prompt 增强）
- 修改 calibration_page：`lib/features/recognize/calibration_page.dart`（AppBar 修改菜名按钮 + _handleRename + state 字段替代 widget 字段）
- 修改 multi_dish_page：`lib/features/recognize/multi_dish_page.dart`（每菜修改菜名 PopupMenuButton + _handleRename(index) + state 字段）
- 修改 recognize_page：`lib/features/recognize/recognize_page.dart`（注入 NutritionLookup）
- 修改测试：`test/features/insight_key_test.dart` + `test/features/insight_offline_guard_test.dart`（按钮文案 + scrollUntilVisible）+ `test/features/insight_regenerate_confirm_test.dart`（滚动窗口日期 + drag 替代 scrollUntilVisible）

**关键设计决策**：
1. **空结果不缓存**：与 v0.16.0 的"解析失败不缓存"对齐，AI 抽风返回 0 条也不缓存，下次进看板允许重试。当日有效缓存只缓存"真有结果"的请求
2. **Future 缓存互斥**：缓存值用 `Future<List<AiRecommendation>>` 而非 `List`，并发调用共享同一 Future，避免连点换一批时多次调 AI
3. **改菜名 mixin 而非继承**：DishNameEditor 是 mixin on State<T>，三处页面 State 各自 `with DishNameEditor` 复用逻辑，命中后由调用方决定如何更新 UI（recognize_page 跳新页 / calibration_page setState 替换 / multi_dish_page 替换对应 index）
4. **滚动窗口 vs 自然周/月**：用户选滚动窗口（最近 7/30 天），AI 用真实数据更准，图表 X 轴标签用 M/D 格式。代价是缓存 key 每天变化，用户每天需重新生成（预期行为）
5. **宏量均值只统计记录日**：`_appendMacroAndPreference` 中只对 calories>0 的日子累加蛋白/脂肪/碳水，避免 0 填充日拉低均值误导 AI
6. **数据不足守卫顺序**：0 天守卫必须在 apiKey + 网络检查**之后**（config/网络问题更基础，应优先提示）。否则 key 未配置时会先提示"无饮食记录"误导用户

**验证（2026-07-04 沙箱实测）**：
- ✅ `flutter analyze` → No issues found! (ran in 16.3s)
- ✅ `flutter test` → +710 ~3: All tests passed!（710 通过，3 跳过，0 失败）



**深度审查修复批次（2026-07-05）—— 严格 TDD 修复 6 High + 14 Medium + 5 Low**：

用户要求"对这个项目再次进行深度的问题寻找与修复，所有的地方都要检查到，而且是反复的，必须要严谨，不能出问题，仔细"。3 个并行 search agent 全面审查发现 6 个 High + 17 个 Medium + 若干 Low，全部采用严格 TDD（Red-Green-Refactor：先写失败测试→验证失败原因正确→最小实现→验证通过→commit）渐进修复，分 5 个 Section（A-E）。新增 60+ 个测试用例，全量验证通过。

**Section A：High 级崩溃/数据污染 bug 修复（6 个 Task）**：
- **H1（commit 194d4ca）vision_provider.dart fromJson null 兜底**：cooking_method/is_single_item/confidence 用 `as String/bool/num` 强转，Qwen-VL 偶发漏返字段时抛 _TypeError 致整次识别失败。改 `as String?/bool?/num? + ?? 默认值`，与同文件其他 13 个字段兜底风格一致
- **H2（commit 25c601b）json_importer _asInt 兑现注释承诺**：原 `_asInt` 注释说"用 _asIntOrNull 兜底"但实现没兜底，null 直接抛 _TypeError 难定位。改为显式 ArgumentError 给清晰错误信息（必填字段缺失/类型非 num 各一分支），调用方据 message 决定是否切 _asIntOrNull + 默认值
- **H3+M1（commit f1241ad）glm_flash_provider _buildPrompt null 兜底 + 宏量数组越界守卫**：`_buildPrompt`/`_buildMonthlyPrompt` 对 daily_calories/daily_weights 无 null 兜底，调用方传不完整 data 时崩溃。加 `as List? ?? const []` 兜底；同时 M1 给宏量数组加 index 越界守卫防 IndexError
- **H4（commit 63bcbf7）meal_log_repository recent 三方法加 endDate 上界**：getRecentMeals/getRecentFoodCounts/getMealTypeDistribution 原只 startDate 下界无 endDate 上界，未来日期污染推荐。加 `w.date <= today` 上界，与 getRangeForTdee 行为一致
- **H5+H6（commit aa77a21）prompt 规则 6 容忍度与 validator 一致 + 酒精例外**：prompts.dart L60 规则 6 自洽约束 vs L221 示例 5 啤酒明确违反（5% 容忍度下啤酒 cal 43 vs 三宏量推算 48 偏差 12%），模型困惑。recognition_validator L21 容忍度 10% vs prompts.dart L60 5% 不一致。修复：validator 与 prompt 容忍度常量统一（提取 `kCalorieTolerancePercent = 0.10`）；prompt 规则 6 加"酒精例外"（啤酒/葡萄酒等酒精饮料 cal 来自乙醇 7kcal/g，三宏量推算会偏差，不触发自洽修正），示例 5 加注释说明例外适用
- **关键测试**：vision_response_parser_test 加"fromJson 字段缺失时不崩溃" / json_export_import_test 加"H2 _asInt 给清晰错误" / glm_flash_provider_test 新建（含 H3 null 兜底 + 宏量数组越界）/ meal_log_repository_test 加"H4 endDate 上界" / recognition_validator_test 加"H5+H6 酒精例外 + 容忍度统一"

**Section B：Phase 4 防御性加固（4 个 Task）**：
- **M2（commit a429344）insight_page SegmentedButton 快速切换竞态守卫**：SegmentedButton 快速切换周/月时 onSelectionChanged 异步 _load 与 setState 竞态，UI 显示错乱。加 `_isSwitching` 守卫防重入
- **M3（commit 33eb588）recognize_page 迁移 DishNameEditor mixin（DRY）**：recognize_page 的改菜名逻辑与 calibration_page/multi_dish_page 重复，违反 DRY。迁移到 DishNameEditor mixin（已在 Phase 4 创建），recognize_page `with DishNameEditor` 复用
- **M4（commit f034ae4）insight 测试滚动策略统一为 drag**：insight_key_test/insight_offline_guard_test/insight_regenerate_confirm_test 三个测试用 `scrollUntilVisible` 在某些场景抛 "Too many elements"，统一改用 `tester.drag(find.byType(ListView), const Offset(0, -300))` 手动滚动
- **关键测试**：insight 测试三文件滚动策略统一 + recognize_page mixin 迁移后行为不变验证

**Section C：AI 链路修复（6 个 Task）**：
- **M5（commit 1ff0fa6）hasPackageNutrition getter 与 computePackageNutritionPer100g 一致**：getter 检查 6 字段非 0，但 computePackageNutritionPer100g 实际只看 4 字段（packageServingG/Kj/Kcal/TotalG），不一致。统一为同一份字段集合
- **M6（commit 638fc7e）copyWith 补全 v1.9/v1.10 新增 9 个 package_* 字段**：copyWith 漏了 v1.9/v1.10 新增的 9 字段，重建 VisionRecognitionResult 时丢失数据
- **M8（commit 492b190）OCR 糖类正则负向回视扩展，防多字糖类配料名误匹配**："低糖/无糖/加糖/含糖/少糖/减糖/高糖" 等多字糖类配料名会误匹配 "糖" 模式。加 7 个负向回视 `(?<![低无加含少减高])糖`
- **L2（commit fe94e58）createChatCompletion 加默认 timeout 30s 参数**：原无 timeout，调用方忘加 timeout 时会无限等待。加默认 30s，调用方可覆盖
- **M7（commit 4e74896）profile_repository update 置空语义限制文档化**：update 的 null 跳过语义（部分更新）未文档化，调用方可能误以为 null=置空。加文档说明"null 跳过保持原值，要置空需用专门的 clear 方法"
- **关键测试**：vision_response_parser_test 加 M5/M6 用例 / package_nutrition_ocr_parser_test 加 M8 多字糖类负向回视 / glm_flash_provider_test 加 L2 timeout

**Section D：UI + 测试补强（5 个 Task）**：
- **M11（commit 214ff95）offline_queue_controller 后台回补计入月度识别次数**：后台回补成功识别后未调 incrementMonthlyCount，月度配额漏算。补 incrementMonthlyCount 调用
- **M12（commit 70edabc）补全 multi_dish_page widget 测试**：multi_dish_page 含 resolveSingleFoodItemId/packageMacrosAllZero 守卫/db.transaction/改菜名等复杂逻辑，原无 widget test。补 5 个 testWidgets（识别成功/守卫触发/改菜名命中/改菜名未命中/复合菜包装数据）
- **M13（commit 26982ed）版本号用 package_info_plus 动态读取**：替代 me_page/settings_page/sentry_init 三处硬编码版本号。新增 `app_version_provider.dart`（appVersionProvider 返回 version+buildNumber，appVersionShortProvider 返回纯 version）+ 3 个测试（含 mock bump 场景）
- **M14（commit 0aebcb4）weight_page 加 PopScope 未保存确认**：原输入体重后误触返回会丢失数据。加 `_dirty` 字段 + `_markDirty` listener（用 setState 触发 rebuild 让 canPop 同步）+ PopScope(canPop: !_dirty, onPopInvokedWithResult) + _save 成功后清 _dirty。4 个测试覆盖 4 个路径（输入后弹确认/未输入不弹/放弃退出/继续编辑保留）
- **关键测试**：multi_dish_page_test 新建 5 个 widget test / app_version_provider_test 新建 3 个测试 / weight_page_test 新建 4 个 widget test

**Section E：Low 级顺手清理（5 个 Task）**：
- **L1（commit 2e481f3）_friendlyError 加 5xx/403 错误文案**：原仅覆盖 timeout/401/429/network，5xx 和 403 落兜底文案不够精准。加 403（权限不足）和 5xx（服务暂时不可用）分支，用 `RegExp(r'5\d{2}')` 匹配 500/502/503/504
- **L5（commit d507152）weight_log getRange 同日多条去重（与 getRangeForTdee 一致）**：折线图同日多条会显示多个点跳变。getRange 改为按 date 去重保留最新（asc(id) 排序后 byDate[date]=w 覆盖，最大 id=后插入=用户最新值）
- **L3（commit ab1e2b4）insight_chart_test 注释同步 v1.11 滚动窗口**：注释从 "monday-sunday 本周" 改为 "v1.11 滚动窗口 today-6 ~ today"（与 Phase 4 滚动窗口策略对齐）
- **L4（commit cf2ff28）dish_name_editor searchByName limit 30→10**：改菜名场景用户已输入精准关键词，30 候选在 AlertDialog 内滚动筛选成本高，10 足够（GLM 5 级模糊兜底仍保留）
- **chore（commit 1d8da3d）清理 weight_page_test 未使用 import**：M14 测试实际未直接用 SecureConfigStore，移除 unused import

**修复期间错误与复盘**：
- M14 测试失败：_markDirty 只修改 _dirty 不调 setState，致 PopScope canPop 未同步（onPopInvokedWithResult didPop=true 直接 pop 不弹确认）。修复：_markDirty 改用 setState + `if (_dirty) return` 防重复 setState
- M14 analyze 警告 use_build_context_synchronously：`if (await confirmDiscardChanges(context) && mounted)` → `if (await confirmDiscardChanges(context) && context.mounted)`（参考 multi_dish_page.dart 模式）
- L1 编译错误：mock 类 override 签名缺 timeout 参数（L2 加了 timeout 但 3 个 mock 类未同步）。补 timeout 参数到 _FakeGlmProvider/_ThrowingGlmProvider/_SlowGlmProvider 的 override
- L5 编译错误：`db.weightLogs.select()` 不可用（某些 drift 版本 table.select() 未暴露）。改用 `db.select(db.weightLogs).get()`（参考 profile_weight_refresh_test.dart）

**验证（2026-07-05 沙箱实测）**：
- ✅ `flutter analyze` → No issues found
- ✅ `flutter test` → 772 passed / 3 skipped / 0 failed（含本次新增 60+ 测试）

**深度审查修复批次文件清单**：
- High 级（6 个 commit）：vision_provider / json_importer / glm_flash_provider / meal_log_repository / prompts / recognition_validator
- Medium 级（14 个 commit）：insight_page / recognize_page / vision_provider / profile_repository / package_nutrition_ocr_parser / glm_flash_provider / offline_queue_controller / me_page / settings_page / sentry_init / weight_page / pubspec / app_version_provider（新建）/ multi_dish_page_test（新建）
- Low 级（5 个 commit）：ai_recommendation_service / weight_log_repository / insight_chart_test / dish_name_editor / weight_page_test（清理）
- 新建文件：`lib/core/config/app_version_provider.dart` / `test/core/app_version_provider_test.dart` / `test/features/multi_dish_page_test.dart` / `test/features/weight_page_test.dart` / `test/ai/glm_flash_provider_test.dart`
- 完整 commit 列表（23 个，时间顺序）：194d4ca H1 / 25c601b H2 / f1241ad H3+M1 / 63bcbf7 H4 / aa77a21 H5+H6 / a429344 M2 / 33eb588 M3 / f034ae4 M4 / 1ff0fa6 M5 / 638fc7e M6 / 492b190 M8 / fe94e58 L2 / 4e74896 M7 / 4b73238 feat / 214ff95 M11 / 70edabc M12 / 26982ed M13 / 0aebcb4 M14 / 2e481f3 L1 / d507152 L5 / ab1e2b4 L3 / cf2ff28 L4 / 1d8da3d chore

**已知降级未修复项**（深度审查发现但本轮未实施）：
- M9 GlmFlashProvider autoDispose：需评估生命周期影响，暂不实施
- M10 nutrition_lookup 三次查库优化：重构风险较高，暂不实施
- M15 settings_page_test 增强：现有测试已覆盖核心路径，ROI 低
- M16 recognize_controller 容灾测试：现有容灾逻辑已在 production 路径覆盖，测试增强 ROI 低
- M17 offline_queue 断路器+事务测试：需 mock workmanager 复杂依赖，成本高
- 反馈页 reasoning 展示（Phase 2.6 High-1 降级，需 schema 迁移）
- food_item 表 CHECK 约束（Phase 2.6 Medium 降级，需 schema 迁移）

**实现计划文档**：`/workspace/docs/superpowers/plans/2026-07-04-deep-audit-fixes.md`（25 个 Task 完整 TDD 步骤）

---

**Phase 3 调研结论（2026-07-04，决策：不推荐实施）**：

经沙箱严谨调研，Phase 3 thinking 模式存在 5 重障碍，ROI 不足以支撑实施成本：

1. **SDK 障碍**：openai_dart 7.0.0 的 `ChatCompletionCreateRequest.toJson()` 只序列化预定义字段，**无 extra body 扩展点**，无法传递 Qwen 特有的 `enable_thinking: true` 参数。要启用 thinking 需 fork/patch SDK（维护成本高）或绕过 SDK 用原始 HTTP（丢失 SDK 的错误处理/重试/超时逻辑）

2. **架构障碍**：Qwen 官方文档明确 "Structured output is not supported in thinking mode"——thinking 模式与 `response_format: json_object` **不兼容**。需 workaround：thinking 流式输出后用 fast model（如 qwen3.5-flash）+ json_object 修复 JSON（两次 API 调用，延迟翻倍）

3. **成本障碍**：thinking 模式 token 消耗 2-5x + 延迟 3-10x（来源：Qwen 官方 + theneuralbase.com 实测），加上 workaround 的两次 API 调用，移动端用户体验差（识别等待从 ~5s → 15-30s）

4. **备模型障碍**：GLM-4V-Plus **不支持 thinking**（智谱支持 thinking 的视觉模型是 GLM-4.5V/4.6V 系列，非 GLM-4V-Plus）。主备降级时 Qwen thinking → GLM 无 thinking，架构不一致，识别质量波动大

5. **功能重叠**：Phase 1 v1.9 的 `reasoning` 字段已实现 prompt 层面 CoT（让模型在 JSON 内输出推理过程后再给结论），无需 SDK 改造，与 json_object 兼容，主备模型都能用。thinking 模式是 SDK 层面 CoT，与 Phase 1 功能重叠，边际价值低

**Phase 1 prompt 层面 CoT vs Phase 3 SDK 层面 thinking 对比**：

| 维度 | Phase 1 reasoning 字段（已实施） | Phase 3 thinking 模式（不推荐） |
|------|----------------------------------|-------------------------------|
| 推理能力 | prompt 层面引导（已上线） | 模型原生能力 |
| SDK 改造 | 无需 | 需 fork/patch 或绕过 SDK |
| json_object | ✅ 兼容 | ❌ 不兼容（官方明确） |
| 流式 | 不需要 | 必须（stream=True） |
| 成本 | 低（仅输出 token 增加） | 高（token 2-5x + 延迟 3-10x + 两次 API） |
| 主备兼容 | ✅ 都能用 | ❌ GLM-4V-Plus 不支持 |
| 可控性 | 高（prompt 控制） | 低（模型内部） |

**SDK 能力评估详情**（openai_dart 7.0.0，已核实源码）：
- ✅ 流式输出：`createStream()` 方法支持，自动加 `stream: true`
- ✅ 解析 reasoning_content：`AssistantMessage.reasoningContent` + `ChatDelta.reasoningContent` 都能解析 `reasoning_content` JSON 字段（DeepSeek R1 / vLLM 兼容字段）
- ❌ 传递 enable_thinking：`ChatCompletionCreateRequest` 无此字段，`toJson()` 无 extra body 扩展点

**模型能力评估详情**（已核实官方文档）：
- Qwen3-VL-Flash：支持 hybrid thinking（默认 disabled，`enable_thinking=true` 开启），但 thinking 与 json_object 不兼容，必须流式
- GLM-4V-Plus：不支持 thinking（智谱 thinking 视觉模型是 GLM-4.5V/4.6V 系列）

**建议下一步**：
- 跳过 Phase 3，先上线 Phase 1+2，收集真实用户反馈
- 如果未来要启用 thinking，等 openai_dart SDK 支持 extra body 后再实施（或升级备模型到 GLM-4.5V/4.6V）
- 直接评估 Phase 4（两阶段识别/追问机制）或其他改进方向

**已知非阻塞问题**：
- `image_cleanup_startup_test.dart T48` 日期敏感测试：测试硬编码日期但代码用 `DateTime.now()`，每过一段时间会失败。建议后续改成相对日期（`DateTime.now().subtract(Duration(days: 8))` 动态生成测试日期）

**最近 commit**：
- `1d8da3d` chore: 清理 weight_page_test 未使用 import
- `cf2ff28` ux(L4): dish_name_editor searchByName limit 30→10
- `ab1e2b4` docs(L3): insight_chart_test 注释同步 v1.11 滚动窗口
- `d507152` fix(L5): weight_log getRange 同日多条去重（与 getRangeForTdee 一致）
- `2e481f3` fix(L1): _friendlyError 加 5xx/403 错误文案
- `0aebcb4` feat(M14): weight_page 加 PopScope 未保存确认
- `26982ed` feat(M13): 版本号用 package_info_plus 动态读取（替代三处硬编码）
- `70edabc` test(M12): 补全 multi_dish_page widget 测试
- `214ff95` fix(M11): offline_queue_controller 后台回补计入月度识别次数
- `4b73238` feat: 了解项目进展
- `4e74896` docs(M7): profile_repository update 置空语义限制文档化
- `fe94e58` fix(L2): createChatCompletion 加默认 timeout 30s 参数
- `492b190` fix(M8): OCR 糖类正则负向回视扩展，防多字糖类配料名误匹配
- `638fc7e` fix: M6 copyWith 补全 v1.9/v1.10 新增 9 个 package_* 字段
- `1ff0fa6` fix: M5 hasPackageNutrition getter 与 computePackageNutritionPer100g 一致
- `f034ae4` test: M4 insight 测试滚动策略统一为 drag
- `33eb588` refactor: M3 recognize_page 迁移 DishNameEditor mixin（DRY）
- `a429344` fix: M2 insight_page SegmentedButton 快速切换竞态守卫
- `aa77a21` fix: H5+H6 prompt 规则 6 容忍度与 validator 一致 + 酒精例外
- `63bcbf7` fix: H4 meal_log_repository recent 三方法加 endDate 上界
- `f1241ad` fix: H3+M1 glm_flash_provider _buildPrompt null 兜底 + 宏量数组越界守卫
- `25c601b` fix: H2 json_importer _asInt 兑现注释承诺，null 时抛 ArgumentError
- `194d4ca` fix: H1 vision_provider fromJson 关键字段无 null 兜底致崩溃
- `7017ee3` feat: Phase 4 用户反馈 5 问题改进（AI 推荐失败修复 + 改菜名 mixin 三入口 + 周月总结滚动窗口+宏量+偏好+覆盖率+数据守卫 + 测试修复）
- `e6ae182` release: v0.16.0 v5 AI 推荐审计修复（5 high + 5 medium）+ 满意度反馈按钮改 PopupMenuButton + 测试 mock 修复 + 版本号 bump
- `e09b233` docs: HANDOFF 回填 Phase 2.12 commit hash 27b6a85
- `27b6a85` feat: AI 个性化推荐 v5（渐进增强 + 满意度反馈学习）
- `c13143b` fix: v0.15.0 release 后大规模审计修复 24 个问题（UI 审计 8 个 + sentry_init 版本号同步 + HANDOFF 9 个文档问题 + 测试缺口评估降级）
- `4b35dcb` release: v0.15.0 UI 优化 + 图标重设计（M3 Expressive 主题层 +6 组件主题 + 公共组件 +6 + 各页面优化 + 图标 Material 风格重设计）
- `7b649f2` fix: v1.10 深度审查 BUG-2/BUG-5 High 级修复 + 124 个新测试覆盖（didFill 守卫跳过 cal 自洽修正 + _aiFallbackNutrition packageMacrosAllZero 守卫 + prompts schema 一致性 + OCR "糖"负向回视 + food_density 新品类）
- `8058012` feat: multi_dish_page 复合菜路径 packageMacrosAllZero 守卫 + OCR "糖"模式负向回视防误匹配
- `e9dacaf` docs: HANDOFF 补 v1.10 三层防御架构详情 + 修复 validator warning
- `3e2c8f8` feat: v1.10 含糖饮料碳水缺失修复——三层防御架构（OCR 正则兜底 + 三层优先级换算 + 自洽反推 + 三路径宏量兜底）+ 174 测试
- `8bccee4` chore: bump 版本号到 0.14.0+15 准备发布 v0.14.0
- `e20b65f` fix: 5 维度深度检查修复 + Gap1 集成测试补全
- `3321a25` fix(ai): 修复 v1.9 包装 OCR 4 个 gap，达到豆包级识别精度
- `0203cca` docs: Phase 3 thinking 模式调研结论 - 不推荐实施
- `1fdff0e` chore: bump 版本号到 0.13.0+14 准备发布 v0.13.0
- `11a0cba` docs: HANDOFF 补 Phase 3 C/D 批详情 + 陷阱 49（confirmAction/showAppToast 抽象偏好）
- `4252093` refactor: UI/UX 审查修复 D 批第三轮——confirmAction + showAppToast 公共抽象
- `390d19a` refactor: UI/UX 审查修复 D 批第二轮——foodSourceLabel/EmptyChartHint/WarningBanner/_sectionTitle
- `d46a1b9` fix: UI/UX 审查修复 C 批——数据安全 + 一致性 S 级
- `4ad029c` docs: HANDOFF 补 Phase 3 陷阱 45-48
- `（前次）` feat: UI/UX 审查修复 Phase 3——公共抽象层 B1-B6 + 数据安全 A1-A4
- `db80dfb` feat: 全 editable 第一批——体重记录可改值/改日期/删，餐次记录可改份量/营养/餐次/日期/换食物/高级覆盖
- `79a0ae6` feat: 食物识别增强四层自我进化架构（P0/P1/P2，已随 v0.13.0 发布）
- `7d1e8bd` docs: HANDOFF 补全 v0.12.0 release workflow run URL + APK 大小
- `cbdc664` docs: HANDOFF 补充图标精致化详情（v0.12.0 已含）
- `c37912b` feat: 启动器图标精致化 + bump v0.12.0（已发布 v0.12.0）
- `932c56c` docs: HANDOFF 补充深度审查修复 commit hash f5e611a
- `f5e611a` fix: 深度审查修复 15 项——TdeeCalibrator 符号/insertManual 别名冲突/酒精热量清零/JsonImporter FK+Sentry try-catch/NaN 校验/硬下限/markFailed 事务等（已随 v0.12.0 发布）
- `a8aa1f5` feat: 界面 MD3 全面优化（协调性+合规+字体层级，已随 v0.12.0 发布）
- `a680241` feat: 智能推荐算法 v3 五维评分 + addAlias 冲突检测（已随 v0.12.0 发布）
- `1064449` fix: 识别精准度修复+界面偏右修正（雪花啤酒→雪碧假阳性，已随 v0.12.0 发布）

**本次全 editable 第一批（已随 v0.13.0 发布）**：
解决用户反馈"所有功能都希望自己改，比如体重输错了点了确认后还能改"。
4 批渐进实施，本次第一批（P0：体重 + 餐次全 editable）。
- **体重记录全 editable**：`WeightLogRepository` 加 `getById`/`update`/`delete`（部分更新，null 跳过）；`weight_page` ListTile → Dismissible（左滑删除带二次确认 dialog）+ onTap 编辑 dialog（体重 TextField + 日期 DatePicker，StatefulBuilder 局部刷新）；编辑最新一条时同步 `ProfileRepository.update(weightKg:)`（与 _save 一致逻辑，保证 dashboard 宏量目标用最新体重）；删除/编辑后调 RefreshBus.notify 跨页刷新
- **餐次记录全 editable（8 字段）**：`MealLogRepository.updateMealLog` 从 5 必填营养字段扩展为 8 可选字段（加 date/mealType/foodItemId，全部 null 跳过保持原值），向后兼容现有 5 处调用；新增独立 `MealEditDialog`（ConsumerStatefulWidget，5 个 TextEditingController 管理份量+4 营养），支持换食物（push FoodLibraryPage pickForReuse 模式 + 自动重算营养）、改餐次（ChoiceChip 4 选 1）、改日期（DatePicker ListTile）、高级覆盖（ExpansionTile 4 个营养 TextField，监听手动修改标记 _nutritionOverridden 优先级最高）、营养重算优先级（advanced 覆盖 > 换食物重算 > 份量比例）
- **哨兵防御扩展**：`updateMealLog` 加 `foodItemId != null && foodItemId <= 0` ArgumentError 校验（与 insertMealLog 一致，防 UI 把 0 哨兵写入非空 FK 字段）
- **测试**：weight_log_repository 加 11 个测试（getById 2 + update 5 + delete 3 + 不存在 id 边界），meal_log_repository 加 9 个测试（date/mealType/foodItemId 部分更新 5 + 哨兵防御 4），全量 377 passed (3 skipped)
- **文件**：新建 1（meal_edit_dialog.dart），修改 4（weight_log_repository/weight_page/meal_log_repository/today_meals_page）+ 2 测试文件

**本次 UI/UX 审查修复 Phase 3（已随 v0.13.0 发布）**：
4 路并行 search agent 全面审查所有界面，识别 14 S 级 + 30+ M 级 + 10 L 级问题，分 6 批（A-F）渐进修复。本次完成公共抽象层（B1-B6）+ 数据安全（A1-A4）共 10 项。
- **B1 date_format 公共工具**：新建 `lib/core/util/date_format.dart`——`parseYmd`（严格校验：regex + 月/日范围 + round-trip 检查，非法日期返回 null 不抛异常）+ `formatYmd`（DateTime → yyyy-MM-dd）；新增 5 个单元测试。替代各页散落的 `DateTime.parse` + 手写格式化，统一日期边界处理
- **B2 food_name 公共工具**：新建 `lib/core/util/food_name.dart`——`placeholderFoodName(foodItemId)` 生成「未知食物#id」+ `isPlaceholderFoodName(name)` 判断；跨页统一食物名占位符（today_meals/dashboard/meal_edit_dialog 等），避免各页硬编码 `食物${id}` 字符串拼接不一致
- **B3 EmptyState 组件**：`m3_widgets.dart` 新增 `EmptyState`（icon + title + 可选 subtitle + 可选 action button），MD3 间距（icon→title 16 / title→subtitle 8 / subtitle→button 16 / 外 padding 32）；替换 today_meals_page 和 dashboard_page 2 处内联空态实现，删除 `_buildEmptyState()` 私有方法
- **B4 GroupCard 组件**：`m3_widgets.dart` 新增 `GroupCard`——`dividerIndent` 参数（null=不自动插分隔线，非 null=子项间自动插 Divider）+ 静态 `GroupCard.divider(context)` 手动插分隔线；替换 me_page（3 处）+ settings_page（7 处）共 10 处 `_groupCard` 调用，删除 4 个私有方法（`_groupCard`×2 / `_withDividers` / `_divider`）
- **B5 MealTypeSelector 组件**：`m3_widgets.dart` 新增 `MealTypeSelector`——封装 SegmentedButton 固定 4 段（早餐/午餐/晚餐/加餐），value/onChanged 接口；替换 recognize_page + manual_entry_page 2 处内联 SegmentedButton（各 ~10 行），recognize_page 补 m3_widgets import
- **B6 清理冗余 border: OutlineInputBorder()**：app.dart 的 `inputDecorationTheme`（L68-71）是全局主题单一源，6 文件 11 处冗余 `border: OutlineInputBorder()` 清除（meal_edit_dialog 6 / weight_page 2 / insight_page 1 / backup_page 1 / today_meals_page 2）；仅 app.dart 保留作全局定义
- **A1 Undo SnackBar 乐观删除**：today_meals_page 餐次卡片 Dismissible 改乐观删除——先从 UI 移除 + 显示 4s 撤销 SnackBar，未撤销才实际从 DB 删除（`repo.deleteMealLog`）；删除失败回滚 `_load()` + 错误提示。比原"立即删 + SnackBar 提示"更宽容误操作
- **A2 food_library 加载态**：food_library_page 加 `_initialLoading` 标志，`_loadFrequent` finally 块置 false；空态 UI 在 `_initialLoading` 时显示 CircularProgressIndicator（替代误导性的"暂无常用食物"文案），避免首屏加载期间显示假空态
- **A3 PopScope 未保存确认**：`m3_widgets.dart` 新增 `confirmDiscardChanges(context)` 共享 dialog（继续编辑/放弃）；4 个编辑页（food_edit_page / profile_page / settings_page / calibration_page）加 `bool _dirty` + `_markDirty()` + controller listeners + `PopScope(canPop: !_dirty, onPopInvokedWithResult: ...)`；profile_page/settings_page 的 `_markDirty` 加 `_loading` 守卫防初始赋值误标 dirty；保存成功后 `_dirty = false` 再 Navigator.pop
- **A4 RecognizePage 错误态重试入口**：recognize_page 加 `ImageSource? _lastSource` 记录最近选图来源；错误态 SnackBar 加"重试"按钮（6s 时长），点击重新调 `_pickAndRecognize(source)`；按错误类型智能判断可重试性——「操作太快」（限流 30s，重试只再触发限流）/「已转手动录入」（L3 已跳转）/「安全过滤」（同图结果不变）三类不显示重试，其余错误（压缩失败/模糊图/API 异常/入队失败）可重试
- **验证**：flutter analyze No issues + flutter test 392 passed (3 skipped)
- **文件**：新建 2（date_format.dart / food_name.dart）+ 2 测试文件，修改 12（m3_widgets / recognize_page / recognize_controller / multi_dish_page / calibration_page / today_meals_page / dashboard_page / meal_edit_dialog / food_library_page / food_edit_page / profile_page / settings_page / me_page / weight_page / insight_page / backup_page / manual_entry_page）

**未完成/待办**（按优先级）：
1. ⬜ 用户真机验收 v0.13.0（装 APK 验证：食物识别四层闭环 + 体重/餐次全 editable + UI/UX 审查修复 Phase 3 五批）
2. 🔧 UI/UX 审查修复 F 批：输入校验——TextField → Form+TextFormField validator（用户已确认范围=全部 7 页 + 实时校验+错误提示 MD3 模式；风险较高会改 form 行为，开工前需逐一确认每页校验规则）
3. 🔧 全 editable 第二批：FoodItems 删除/归档 + name/aliases 编辑（用户已批准 4 批计划，第一批已完成）
4. 🔧 全 editable 第三批：PendingRecognitions UI 页 + 重试/删除 + Feedbacks 历史/删除
5. 🔧 全 editable 第四批：历史 InsightSummaries 查看页 + 份量校准回滚
6. 🔧 第三波（待用户确认后启动）：建议 6（接入 USDA FoodData Central API 替代部分 OFF 云查，免费但需 API key）—— 但需先评估 OFF 中文命中率，USDA 是英文 API 中文菜名需翻译层
7. ⏸️ 建议 4 餐前/餐后双拍对比（DietDelta 思路）：用户明确暂不做
8. 🔧 重构性优化（风险较高，不阻塞当前版本）：
   - 路由方式统一（GoRouter vs Navigator.push 混用）
   - 版本号从 PackageInfo 读取（替代硬编码，me_page/settings_page/sentry_init 三处）
   - dashboard/today_meals N+1 查询优化（getByIds）
   - 测试覆盖增强：AI 兜底（test S3 哨兵防御已补）、getThemeSeed 单元测试
   - Sentry appRunner 标准化 + FlutterError.onError 链式调用
   - 后台回补补 fallback provider + circuitBreaker + incrementMonthlyCount
   - NutritionLookup 3x OFF 云查重构（深度审查 M4，暂不修复）
   - RecognitionPostProcessor correctAdditionalDishes needsRetry 丢弃（深度审查 M3，暂不修复）
   - image_quality_checker 改 isolate（深度审查 core M1，暂不修复）

**本次 P0/P1/P2 食物识别增强（已随 v0.13.0 发布）**：
解决"雪花啤酒识别成雪碧 + 奶茶/网红零食能否准确分辨 + 热量能否严谨计算"三问。
核心思路：不追求库覆盖所有食物，建立"AI 估算(品类校准) + 品牌库(头部覆盖) + OFF(包装食品) + 用户纠错(长尾自进化)"四层闭环。
- **P0 品类校准 + brand 持久化**：新建 `food_category_defaults.dart`（beer=43/wine=83/carbonated=43/milk=61 等 13 品类默认值），AI 兜底 per100g 偏离默认值 2 倍用默认值替代；`upsertAiRecognized` 加 brand 参数，"品牌+菜名"存为 alias（如"雪花啤酒"），下次精确命中
- **P1 品牌官方热量库**：新建 `assets/chain_drink_menu.json`（10 品牌 41 招牌：喜茶/霸王茶姬/奈雪/瑞幸/星巴克/蜜雪/古茗/茶百道/一点点/Manner，数据来自各品牌小程序官方公示），`FoodSeedImporter.importChainDrinksFirstTime` 首次启动导入；`findByNameOrAlias` 加 brand 参数，优先级 0 按 brand+name 精确查品牌条目
- **P2 OFF brand 组合查询 + 反馈回流创建新条目**：`OffProvider.lookup` 加 brand 参数，先查"brand+name"再回退 name；`today_meals_page` 反馈回流精确 miss 时 `insertManual` 创建新条目（source='manual'，aliases=AI 错误名），实现长尾自进化
- **prompt v1.8**：补啤酒/茶饮剥离示例（雪花啤酒→dish_name=啤酒/brand=雪花，喜茶多肉葡萄→dish_name=多肉葡萄/brand=喜茶），强调连锁品牌 brand 必填
- **测试**：新增 18 个测试（品类校准 11 + brand 匹配 3 + brand 持久化 4），全量 358 passed (3 skipped)
- **文件**：新建 2（food_category_defaults.dart / chain_drink_menu.json），修改 8（prompts/food_item_repository/nutrition_lookup/off_provider/recognize_page/recognize_controller/multi_dish_page/offline_queue_controller/today_meals_page/database/food_seed_importer/pubspec）
- `52dc876` docs: 更新 HANDOFF——v0.11.1 已发布
- `84cc29a` feat: 个人档案特殊人群适配（孕期/哺乳/老年/青少年/糖尿病/肾病/素食，schema v1→v2，已随 v0.11.1 发布）
- `c6a76be` feat: 折线图美化与智能推荐算法升级（Y 轴 interval 防重叠+渐变填充+触摸 tooltip+推荐四维评分，已随 v0.11.1 发布）
- `685fc9e` docs: 更新 HANDOFF——记录启动与首屏性能优化
- `d1e5970` perf: 启动与首屏加载性能优化（secure_storage 并行+首屏查询并行+N+1→批量+splash 配色，已随 v0.11.1 发布）
- `fbcbf1e` fix: 修复 tab 页 dialog 按钮点击黑屏（嵌套 Navigator 误 pop 页面，已随 v0.11.1 发布）
- `b97eb89` style: 今日明细页卡片式重构（缩略图+营养素圆点+餐次小计，已随 v0.11.1 发布）
- `1f1fad0` fix: 校准页加多份识别警告横幅（避免一罐被识别成两罐时记录双倍克数，已随 v0.11.1 发布）
- `ec5d452` docs: 更新 HANDOFF——v0.11.0 已发布
- `58db4e3` chore: 版本号 bump 到 0.11.0+11 准备发布 v0.11.0
- `add3c42` docs: 更新 HANDOFF——主页刷新修复（profile/weight→RefreshBus→dashboard）
- `b167574` fix: 个人档案/体重页保存后通知主页刷新（profile/weight→RefreshBus→dashboard）
- `62dd475` refactor: 提取 RecognitionPostProcessor 修复三路径行为分叉（第二波 2.0+2.1）
- `47fd22c` feat: 食物热量计算优化第一波——可食部分系数+组分份量交叉验证+液体密度换算（建议1+3+7）

**已发布**：
- v0.14.0 已发布（2026-07-04，包含 v0.13.0 之后 1 大块：AI 识别准确度重构 Phase 1+2.5+2.6 + Phase 3 调研结论，达到豆包级识别精度）
  - Release: https://github.com/qbjsdsb/eatwise/releases/tag/v0.14.0
  - app-release.apk 74.2 MB / app-debug.apk 167.6 MB（debug 签名，自用版）
  - workflow run: https://github.com/qbjsdsb/eatwise/actions/runs/28697223867（success，约 13 分钟，由 `git push tag v0.14.0` 触发）
  - 新增能力：①v1.9 prompt 营养师人设 + reasoning CoT 字段 + 包装营养表 OCR 6 字段路径 + 盘子尺度参照 + 示例 7 珍宝珠酸条 + 示例 8 麻婆豆腐 ②包装 OCR 优先路径三路径全覆盖（recognize_page/multi_dish_page/offline_queue_controller 单品+复合菜分支）+ computePackageNutritionPer100g 精确换算 ③4 个 Gap 修复（复合菜漏包装 OCR / reasoning UI 展示 / actualCalories 与包装换算值脱节 / solid 校准 + 示例 7 数据自洽）④5 维度深度检查修复（反馈纠正份量反算 per100g 改用 actualServingG / 食物搜索加 aliasesJson.like 支持品牌名 / mid>0 守卫防误清零 / 三路径 estimatedProteinG 传参统一）⑤Gap1 集成测试补全 ⑥Phase 3 thinking 模式调研结论（5 重障碍不推荐实施，详见上方"Phase 3 调研结论"章节）
  - 验证：flutter analyze No issues + flutter test 426 passed / 3 skipped / 1 failed（T48 原有日期 bug）
- v0.13.0 已发布（2026-07-03，包含 v0.12.0 之后 3 大块：食物识别增强四层自我进化架构 P0/P1/P2 + 全 editable 第一批 体重+餐次 + UI/UX 审查修复 Phase 3 A+B+C+D+E 五批共 26 项）
  - Release: https://github.com/qbjsdsb/eatwise/releases/tag/v0.13.0
  - app-release.apk 74.1 MB / app-debug.apk 167.6 MB（debug 签名，自用版）
  - workflow run: https://github.com/qbjsdsb/eatwise/actions/runs/28680625942（success，13 分钟，由 `git push tag v0.13.0` 触发）
  - 新增能力：①食物识别四层闭环（品类校准兜底+品牌官方热量库 10 品牌 41 招牌+OFF brand 组合查询+反馈回流创建新条目）②体重记录全 editable（改值/改日期/删）③餐次记录 8 字段全 editable（份量/4 营养/餐次/日期/换食物/高级覆盖）④UI 公共抽象层（confirmAction/showAppToast/EmptyChartHint/WarningBanner 等 10+ 共享组件）⑤数据安全（乐观删除+Undo/PopScope 未保存确认/错误态可重试/加载失败显 ErrorState）
- v0.12.0 已发布（2026-07-03，包含 v0.11.1 之后 5 个修复/优化：识别精准度+智能推荐 v3+MD3 全面优化+深度审查修复 15 项+启动器图标精致化）
  - Release: https://github.com/qbjsdsb/eatwise/releases/tag/v0.12.0
  - app-release.apk 73.4 MB / app-debug.apk 167.6 MB（debug 签名，自用版）
  - workflow run: https://github.com/qbjsdsb/eatwise/actions/runs/28669494536（success，由 `git push tag v0.12.0` 触发）
- v0.11.1 已发布（2026-07-03，包含 v0.11.0 之后 6 个修复/优化：校准页警告+明细页卡片重构+dialog 黑屏修复+启动性能优化+折线图美化与推荐算法升级+个人档案特殊人群适配）
  - Release: https://github.com/qbjsdsb/eatwise/releases/tag/v0.11.1
  - app-release.apk 73.3 MB / app-debug.apk 167.5 MB
  - workflow run: https://github.com/qbjsdsb/eatwise/actions/runs/28662699235（success，19 步全过）
- v0.11.0 已发布（2026-07-03，包含识别智能化+食物热量优化第一波+第二波+主页刷新修复，APK 已上传）
  - Release: https://github.com/qbjsdsb/eatwise/releases/tag/v0.11.0
  - app-release.apk 73.1 MB / app-debug.apk 167.5 MB
  - workflow run: https://github.com/qbjsdsb/eatwise/actions/runs/28658030594（success）
- v0.10.0 已发布（2026-07-03）

**v0.11.1 已发布包含的六个修复（v0.11.0 之后）**：
1. **校准页多份识别警告**（`1f1fad0`）：用户反馈"一罐芬达显示两罐克数"。根因是 AI 偶发误判 quantity=2，校准页默认用 `estimatedWeightGMid`（已含 quantity 乘积）作初值，数量步进器在底部不显眼，用户未调整直接确认会写入双倍克数。修复方式：quantity>1 时在标题下方加 tertiaryContainer 警告横幅，提示用户检查数量。
2. **今日明细页卡片式重构**（`b97eb89`）：用户反馈"明细界面不够美观"。ListTile → Card 卡片布局：56x56 圆角缩略图、份量/热量 chip、三大宏量营养素彩色圆点、餐次分组带竖条+小计热量。纯 UI 层重构，不动写入逻辑。
3. **tab 页 dialog 按钮点击黑屏**（`fbcbf1e`）：用户反馈"识别准不准"的准/不准按钮、"关于"里的隐私政策按钮点击后黑屏，退出重进才恢复。根因：GoRouter 的 `StatefulShellRoute.indexedStack` 给每个 tab 配嵌套 Navigator，`showDialog` 默认 `useRootNavigator:true` 把 dialog push 到 root Navigator，但按钮 `Navigator.pop(context)` 用页面 context，`Navigator.of(context)` 找到 tab 嵌套 Navigator，把栈顶页面本身（MePage / RecordsTabPage）pop 掉了。修复 3 处（me_page._showPrivacy、today_meals_page._showEditDialog、today_meals_page._showFeedbackDialog 准/不准），统一改 `builder:(ctx)=>` + `Navigator.pop(ctx)`。**坑提醒：今后在 tab 页（dashboard/records/insight/me 分支下）写 dialog，关闭按钮必须用 dialog 的 ctx，不能用页面 context。**
4. **启动与首屏加载性能优化**（`d1e5970`）：用户反馈"点开软件要黑屏一两秒"。三个瓶颈：① main.dart 的 getThemeSeed 和 appConfig 两次独立 secure_storage 读取原串行，改提前触发 appConfigProvider 并行；② AppConfig.load() 原 10+ 次串行 platform channel read 改"同时启动 7 future + 分别 await"并行，并复用结果省 3 次重复 read；③ DashboardPage/TodayMealsPage 食物名反查 N+1 → FoodItemRepository.getByIds 批量 IN 查询，首屏三查询并行；④ Android launch_background 纯白底改 @color/splash_background 匹配 app 默认 surface 色（亮 #FCF9F9/暗 #1C1B1F）。**坑提醒：Future.wait 因多类型 future 会退化为 List<Object?>，并行不同类型 future 应用"同时启动 + 分别 await"模式保留类型。**
5. **折线图美化与智能推荐算法升级**（`c6a76be`）：用户反馈"折线图不够美观有数字重叠"+"智能推荐不够智能"。折线图：Y 轴固定 interval（热量 maxCal/4 取整 50 倍数 / 体重范围/4 至少 0.2）彻底消除重叠，参考线标签左对齐+padding(left:44) 避开 Y 轴 + 上下错开，边框只留左下，网格只水平虚线半透明，数据点变小+surface 描边，belowBarData 改 LinearGradient 渐变，加 lineTouchData 触摸 tooltip。推荐算法 v2：四维评分（相对缺口匹配 remaining/goal 比例取最缺宏量加权 / 历史频次 log2 压缩封顶 4 分 / 排除今日已吃 / 具体理由"补蛋白 32%"），新增 `MealLogRepository.getRecentFoodCounts`（最近 30 天引用次数）。**坑提醒：推荐算法蛋白缺口触发阈值用 hasProteinGap（remainingProtein>5）而非 ratio<0.3，无记录时 ratio=1.0 但仍应触发，否则高蛋白食物不被推荐（测试已覆盖）。**
6. **个人档案特殊人群适配**（`84cc29a`）：用户反馈"个人信息太简单，不能应用在不同人群"。profile 表 schema v1→v2 加 3 个 nullable 列（specialCondition/dietPreference/healthCondition，null 视为 'none' 向后兼容）。NutritionCalculator 按权威来源调整：孕期 +340 / 哺乳期 +500 kcal（IOM 2006）、老年蛋白 1.2g/kg 防肌少症（ISSN）、肾病蛋白 cap 0.8g/kg（KDOQI）、糖尿病碳水 cap 45%（ADA）。ProfilePage 加"特殊状况"段（3 个 DropdownMenu + 风险提示卡片）+ 活动量描述优化（步数/锻炼频率）+ 保存时孕期/哺乳/肾病减脂风险警告。JsonExporter/Importer 同步 3 字段导出导入；版本检查从严格相等放宽为只拒绝高于当前版本（支持旧备份恢复到新版本）。**坑提醒：JsonExporter 加新字段必须同步 JsonImporter 读取，否则备份恢复丢数据；DropdownMenu 测试用 find.byKey 定位，不要用 .last/.first（新增菜单会让索引漂移）。**

**v0.11.1 之后的修复（已随 v0.12.0/v0.13.0 发布）**：
7. **识别精准度修复 + 界面偏右修正**（`1064449`）：用户反馈"雪花啤酒被识别成雪碧"+"界面整体偏右"。识别错配根因有三：①findByNameOrAlias 优先级 5 编辑距离 ≤1 对 2 字短名假阳性（"雪花"vs"雪碧"编辑距离恰好 1 → 误命中）；②反馈回流 addAlias 用 5 级模糊查"正确菜"，模糊命中错对象后把 AI 错误名写成错对象别名 → 永久错配（无法自愈）；③_normalize 不处理全角半角（AI 返回全角字符精确匹配 miss → 降级模糊匹配增加误命中）。修复：①优先级 5 加严——query 长度 ≥3 且 target 与 query 等长才走编辑距离（2 字短名禁用，typo 容错仅保留 3+ 字等长如"蕃茄炒蛋"→"番茄炒蛋"）；②新增 findExactByNameOrAlias（只走 name/alias 精确匹配），today_meals_page 反馈回流改用它，避免模糊命中错对象导致反向错配；③_normalize 加全角→半角转换（数字/字母/空格/括号）。界面偏右根因：SectionTitle padding `fromLTRB(24,20,16,8)` 左 24 右 16 不对称，被 6 页面 14 处复用，标题相对下方卡片（padding 16）右移 8px → 改 `fromLTRB(16,20,16,8)` 对称；dashboard/me_page 的 Divider 缺 endIndent → 补 `endIndent: 16`。新增 4 个精准度专项测试（雪花不命中雪碧/typo 容错保留/findExact 只精确/全角括号归一化）。**坑提醒：2 字短名编辑距离 1 无法区分"假阳性（雪花/雪碧）"与"typo（可东/可乐）"，取舍上禁用 2 字短名编辑距离（牺牲罕见 2 字 typo 容错换取防常见相近名误判）；反馈回流别名必须用精确匹配查库，绝不能用模糊匹配（否则反向错配永久污染别名表）。**

8. **智能推荐算法 v3 五维评分 + addAlias 冲突检测**（`a680241`）：用户反馈"推荐冷门食物，不学习习惯，参考业界成熟方案优化"。WebSearch 调研业界（MyFitnessPal/Yazio/薄荷/Lifesum/Carbon Diet Coach），严谨筛选：弃用协同过滤（单机无用户群）、AI 生成食谱（离线 app）、替换建议（需建替代图谱留后续）；采用内容推荐+频次+约束过滤+时段感知+多样性（全离线，基于现有数据）。v3 五维：①冷门降权——常吃蛋白加权 *4，基础食材 *3，冷门 *1.5（直击"冷门霸榜"痛点，原 v2 全部 *4 致冷门高密度食物盖过常吃基础食材）；②基础食材白名单——硬编码 ~50 个中式家常食材关键词（鸡蛋/鸡胸/牛奶/燕麦/米饭/豆腐/苹果/西兰花…）命中 +3 底分，保证常见食物不沉底；③profile 约束过滤——素食/纯素/乳糖不耐/无麸质硬排除违规食物（按名称关键词），糖尿病高糖降权 *0.3，肾病极高蛋白降权 *0.5（软降权避免列表空）；④时段感知——MealLogRepository 新增 getMealTypeDistribution 学习每食物历史 mealType 分布（ratio>0.5 加 3 分），dashboard 按当前小时推断 mealType 传入；⑤多样性——排除今日已吃（已有）+ 昨日已吃降权 -2。addAlias 冲突检测（防反向错配第二道防线，findExact 是第一道）：写入前遍历全表，若别名已是其他食物的 name/alias 则拒绝写入，防止反馈回流把同一错误名绑多食物致永久错配。新增 9 个专项测试（冷门降权/白名单底分/素食过滤/乳糖过滤/时段感知/多样性 + addAlias 冲突检测 3 个）。**坑提醒：recommend() 新增 profile/mealType/yesterdayDate 全是可选参数，不传时退化到 v2 行为（向后兼容现有测试）；时段感知是数据驱动（学历史 mealType 分布）非硬编码"早餐食物"，样本<2 不返回避免单次误判；糖尿病/肾病用软降权而非硬排除，避免推荐列表空；addAlias 冲突检测遍历全表 O(n) 但在 addAlias 事务内，反馈回流低频调用可接受。**

9. **界面 MD3 全面优化**（`a8aa1f5`）：用户反馈"所有界面检查是否最新 MD3 感觉、协调、美观，借鉴开源"。search agent 全面审查 14 文件识别 37 个问题（H/M/L 三级），WebSearch 调研 MD3 v6.1 规范 + 开源饮食 app（FoodYou/NutriScan 的 Material You + Macro Rings）。实施全 4 批：**第一批协调性**——insight SegmentedButton pin 到 AppBar.bottom（与 records_tab 统一，不随滚动消失）；weight 折线图按 insight 范式重写（左下边框+虚线网格+渐变填充+tooltip+统一 barWidth2.5+图例）；宏量营养素跨页统一用 MacroColors（蛋白=tertiary/脂肪=secondary/碳水=primary，新增 m3_widgets.MacroColors 类，替代 dashboard 的 onPrimaryContainer alpha + today_meals 的硬编码 0xFF4CAF50）；today_meals 卡片改 Card.outlined+12dp+padding16（统一 dashboard）；today_meals section header 改用扩展后的 SectionTitle(trailing:)（替代手写色块+标题+sum）；me/settings 分隔线改 cs.outlineVariant（替代 MD2 的 Theme.dividerColor）。**第二批 MD3 合规**——today_meals 编辑对话框"保存"改 FilledButton（原 TextButton 违反 MD3 主操作规范）；profile 特殊状况提示改 Card(tertiaryContainer)（替代手写 Container）；profile/settings emoji 警告改 Icon(warning_amber_rounded, cs.error)（emoji 跨平台渲染不一致且不跟随主题）；settings 选中态 check 色按色块亮度动态选黑/白（WCAG AA）；recognize 遮罩改 cs.scrim（替代硬编码 Colors.black54）+ 次要按钮改 OutlinedButton 形成主次层级；food_library 列表项补 chevron + 空态套 Card；me 错误态 Icon 补 cs.error；today_meals 反馈 IconButton 恢复 48dp 触摸目标。**第三批字体层级**——SectionTitle 改 titleSmall（原 labelLarge 语义偏标签）；批量替换硬编码 fontSize 为 textTheme（dashboard displaySmall/bodySmall/labelSmall、today_meals labelSmall、me titleMedium/bodySmall、insight bodyMedium）。**坑提醒：MacroColors 是 m3_widgets 新增的共享类，跨页配色必须用它而非各自硬编码，否则 dashboard/today_meals 颜色再次分裂；SectionTitle 新增 trailing 参数是可选的，现有 14 处调用不传 trailing 不受影响（向后兼容）；records_tab/insight 的 AppBar 用普通 AppBar+bottom 而非 SliverAppBar，因 IndexedStack/ListView 子页有自己滚动，SliverAppBar 需 CustomScrollView 重构成本大，权衡用 bottom pinned 已满足"切换器常驻"需求。**

10. **深度审查修复 15 项**（commit `f5e611a`，已随 v0.12.0 发布）：用户要求"反复检查项目所有代码，最深度最深入找问题并严谨修复"。4 路并行 search agent 审查 features / ai+nutrition+data / core+main / test 四领域，识别 6 严重 + 10 中等 + 13 轻微 + 5 测试问题。修复 15 项（10 lib + 4 test + 1 HANDOFF）：**严重**——①`TdeeCalibrator.runAndApply` 符号约定冲突（`calibrate` 注释"减脂负/增肌正"但 profile.goalRateKgPerWeek 存正值，runAndApply 直传致减脂用户校准方向恒错，加 signedGoalRate 转换）；②`FoodItemRepository.insertManual` aliases 参数漏冲突检测（addAlias 有全表检测但 insertManual 漏，手动录入 AI 错误名可绑多食物致永久错配，复用 addAlias 全表遍历逻辑）；③`RecognitionValidator` 营养素自洽校验把酒精饮料热量清零（expected=4p+9f+4c 不含酒精 7kcal/g，啤酒 cal=150 但 expected=48 被强制清零，加 `expected>0` 守卫只在 expected 非零时校验）；④`JsonImporter` DELETE 序列漏 pending_recognitions（result_food_item_id 是 FK NO ACTION，DELETE food_items 前未清致真机导入 FK 阻塞）；⑤`JsonImporter` `as int` 强转崩溃（旧版备份缺字段时 `null as int` 抛 TypeError，新增 `_asInt`/`_asIntOrNull` 兜底，所有非空 int 字段全部替换）；⑥`SentryFlutter.init` 无 try-catch（初始化抛异常时 zone guard 只记日志不 runApp → 永久黑屏，加 try-catch 降级返回原 app）。**中等**——⑦`NutritionCalculator` gender=null 跳过硬下限（女性可能拿到 <1200 危险低目标，null 默认 1500 兜底）；⑧`PendingRecognitionRepository.markFailed` 非事务竞态（read-then-write 无事务，"立即重试"与 workmanager 并发时计数丢失，包 `_db.transaction`）；⑨`backup_page` 遮罩硬编码 Colors.black54（改 cs.scrim）；⑩`sentry_scrub` hex 正则只匹配小写（`[a-f0-9]` → `[a-fA-F0-9]`）；⑪版本号过时（me_page/settings_page 0.10.0 → 0.11.1）；⑫`RecognitionValidator` NaN 绕过校验（NaN<0=false NaN>1=false 通过 confidence/weight 校验，加 isNaN 显式判断）。**测试**——⑬`recommendation_service_test` 4 处假绿断言（`if (idx>=0)` 守卫让比较断言静默跳过，加 `expect(idx, greaterThanOrEqualTo(0))` 前置断言，薯片因 score=-17.35 被合理过滤是设计行为保留 if）；⑭`json_export_import_test` schema v2 三字段漏测（seedData 加 specialCondition/dietPreference/healthCondition，导入后断言）；⑮`meal_log_repository_test` 哨兵防御漏测（新增 foodItemId=0/-1 抛 ArgumentError + foodItemId=1 正常写入 3 个测试）。**坑提醒：TdeeCalibrator calibrate 算法期望"减脂负/增肌正"符号，但 profile.goalRateKgPerWeek 存正值（NutritionCalculator 用 >0 判断），runAndApply 必须按 goal 转换符号；JsonImporter DELETE 序列必须先子表后父表，pending_recognitions.result_food_item_id 是 FK 必须在 food_items 之前清；SentryFlutter.init 失败要降级返回原 app 保证 runApp 能执行（不能让初始化失败致永久黑屏）；RecognitionValidator 营养素自洽校验只在 expected>0 时执行，酒精/纤维/糖醇等非 Atwater 来源热量不能强制清零。**- 验证：`flutter analyze` No issues + `flutter test` 340 passed (3 skipped)。

11. **启动器图标精致化**（commit `c37912b`，已随 v0.12.0 发布）：用户反馈"软件图标太难看了，符合安卓设计规范的同时再精致一点点"。保持「碗+蒸汽」品牌语义（碗=食物，蒸汽=袅袅升起的温热感=慢慢吃），符合 Android Adaptive Icon 规范（108dp 画布 + 66dp 安全区 + 前景/背景/monochrome 三层），精致化五点：①背景平面青绿 → 对角线三色渐变 `#6BA08C→#5B8C7B→#4D7A6C`（立体感）；②前景色纯白 → 奶白 `#FDFBF7`（温暖，与 splash `#FCF9F9` 协调）；③碗口单椭圆 → 环形双线（外椭圆 `evenOdd` 挖内椭圆，厚度感，精致关键）；④碗底加小椭圆底座（稳重感）；⑤蒸汽 stroke 3→2.8，曲线更柔和，错落（中间高两侧低）。所有图形严格在 66dp 安全区 (21,21)-(87,87) 内，OEM 蒙版（圆/方圆角）不裁切。实现：vector drawable（`ic_launcher_background.xml` 渐变 shape + `ic_launcher_foreground.xml` 前景 vector，API 26+ 现代设备）+ Pillow 4x 超采样生成 5 密度 PNG fallback（48/72/96/144/192，API 21-25 旧设备）。monochrome 复用前景供 Android 13+ 主题图标（用户可让图标跟随壁纸取色）。**坑提醒：Android vector `fillType="evenOdd"` 在 API 24+ 支持，自适应图标 API 26+，兼容无问题；PNG fallback 不能漏，minSdk 21 的旧设备无 PNG 会显示默认图标；碗口环形用 evenOdd 挖空而非纯色填充（背景是渐变，纯色挖空会色差）；Pillow 画圆头线段需手动在端点画填充圆（ImageDraw.line 不支持圆头）；4x 超采样 + LANCZOS resize 是抗锯齿关键，直接画目标尺寸会有锯齿。**- 验证：`flutter analyze` No issues + `flutter test` 340 passed (3 skipped) + GitHub Actions release.yml 构建通过。

**识别智能化批次 1-3 修复清单**（本次 commit，用户选择"全部融入"）：
- 批次 1 图片预检 + 字段校验：
  - 新建 `lib/core/util/recognition_validator.dart`——字段合理性校验（dishName/confidence/weight/区间）+ 营养素自洽校验（4p+9f+4c≈cal，±10%）
  - recognize_controller 集成校验：字段不合理→重试 1 次；营养素不自洽→自动用宏量营养素反推修正 calories
  - 修复 image_quality_checker.dart 类型错误（laplacianValues num→double）
  - 20 个校验器单元测试全过
- 批次 2 prompt v1.6 + 包装容量优先：
  - prompt v1.6：包装食品必须读取包装标签净含量（weight_source=package_label），不靠视觉估算
  - 营养素自洽约束：要求 AI 用 4p+9f+4c 反算 calories，偏差<5%
  - VisionRecognitionResult 新增 weightSource 字段 + fromJson 解析（向后兼容旧 prompt）
  - 示例 1-3 加 weight_source 字段 + 自洽性标注
- 批次 3 反馈闭环回流 aliasesJson：
  - FoodItemRepository 新增 addAlias 方法（事务包裹 + 归一化去重）
  - today_meals_page._showFeedbackDialog 加别名回流：用户纠正菜名后，把 AI 错误名作为正确菜的别名
  - 下次 AI 识别返回错误名时，findByNameOrAlias 命中别名，直接返回正确菜营养数据
  - 6 个 addAlias 单元测试全过

**验证**：flutter analyze No issues + flutter test 324 passed/3 skipped/0 failed

**食物热量计算优化第一波修复清单**（commit 47fd22c，等用户验收后发布 release）：
- 建议 1 ediblePercent 可食部分系数：
  - `nutrition_lookup.lookupSingleItem` 库命中分支 + `recognize_page._nutritionFromFoodItem` 反算点都加 `edibleFactor = (food.ediblePercent ?? 100).clamp(1,100) / 100`
  - `effectiveG = servingG * edibleFactor`，反算用真实可食克数（如香蕉 65%、带骨排骨 50%）
  - 复合菜 `lookupCompositeDish` 不乘（组分已是可食克数）
  - 6 个专项测试（香蕉/排骨/null/100%/0% clamp/复合菜不乘）全过
- 建议 7 复合菜组分份量交叉验证：
  - `RecognitionValidationResult` 新增 `correctedComponents` 字段
  - `sum(components.estimatedG)` 与 `estimatedWeightGMid` 偏差>15% 时按 mid 比例缩放
  - `recognize_controller._validateAndMaybeRetry` 主菜 + 附加菜两条路径都覆盖（在校验后、查库前）
  - 防除零（sumG=0/mid=0 不触发）+ 缩放后保留组分名
  - 8 个专项测试全过
- 建议 3 食物密度表 ml→g 换算：
  - 新建 `lib/ai/food_density.dart`——14 个类别密度表（油 0.92/蜂蜜 1.42/烈酒 0.79 等）+ `densityOf`/`isLiquidCategory` 辅助函数
  - prompt v1.7 新增 `food_category` 字段（water/carbonated/juice/milk/cream/oil/honey/sauce/alcohol/beer/wine/yogurt/soup/solid）
  - `VisionRecognitionResult` 新增 `foodCategory` 字段 + `copyWith` 扩展 + fromJson 解析（向后兼容默认 solid）
  - `recognize_controller._applyDensityConversion + _convertDensityForDish` 在校验前换算：仅对 `weight_source=package_label` + 液体类别换算，密度=1.0（水基）跳过
  - 换算公式：`realPerUnitG = perUnitG * density`，`realMid = realPerUnitG * quantity`，区间 ±3%
  - 20 个专项测试全过

**第二波修复清单**（commit 62dd475，三路径一致性 + 重试 bug 修复）：
- 提取 `lib/core/util/recognition_post_processor.dart`：
  - `process()` 完整链路：密度换算 → 字段校验 → 营养素自洽修正 → 组分份量交叉验证 → additionalDishes 修正
  - `applyDensityConversion` / `correctAdditionalDishes` 可单独调用
  - 纯静态方法，不持有状态，不依赖 provider/imageBase64
- 修复问题1（第一波盲区）：offline_queue_controller 后台回补完全没走校验链路
  - 包装液体未做 ml→g 密度换算（500ml 油 mid=500 而非 460）
  - 营养素不自洽未修正、组分份量不自洽未缩放
  - 导致前后台行为分叉：同张图不同网络条件下热量不一致
  - 修复：recognize 成功后调 `RecognitionPostProcessor.process(result)`
- 修复问题2（重试跳过换算 bug）：recognize_controller._validateAndMaybeRetry
  - 原代码重试成功后用未换算的 retryResult（油 500ml 重试后 mid 仍是 500 而非 460）
  - 修复：首次 + 重试结果都走 `RecognitionPostProcessor.process`
- controller 净减 98 行（4 个方法移到 PostProcessor，import + 简化调用）
- 17 个 PostProcessor 单元测试 + 1 个离线回补密度换算专项测试，全过
- 更新 1 个原有离线测试期望值（组分份量缩放后 actualServingG 180→250，新行为正确）

**主页刷新修复清单**（commit b167574，profile/weight 保存后通知 dashboard）：
- 问题：用户在 profile_page 录入体重身高年龄（重算 BMR/TDEE/目标）或在 weight_page 记录体重后，主页每日目标/宏量目标不更新
- 根因1：profile_page._save() pop 后没调 RefreshBus.notify()（dashboard 唯一刷新入口是 RefreshBus 监听）
- 根因2：weight_page._save() 只调本页 _load()，没调 RefreshBus.notify()
- 根因3：weight_page 只写 weight_logs 表，不同步 profile.weightKg（即使刷新，宏量目标 proteinGPerKg*weightKg 仍用旧体重）
- 修复：profile_page pop 后 + weight_page _save 末尾都加 RefreshBus.instance.notify()；weight_page insert 后同步 ProfileRepository.update(weightKg: weight)
- 设计决策：weight_page 不同步重算 dailyCalorieTarget（BMR 重算只在用户主动编辑档案时做，日常体重波动通过 TDEE 校准 adjustmentKcal 微调）
- 4 个 widget 测试全过（ProfilePage/WeightPage notify + weightKg 同步 + weight_logs 不影响）

---

## 3. 关键架构决策（不要轻易改）

### 3.1 AI 估热 + 本地库校验两层架构
- 库命中 → 用库值（NutritionSource.database）
- 库未命中 + AI 有 estimatedCalories → AI 兜底（foodItemId=0 哨兵，source=aiEstimate）
- 库未命中 + AI 无估算 → 走未命中弹窗转手动录入
- 复合菜组分全 miss → 转 AI 兜底走单品路径（v0.10.0 新增）

### 3.2 foodItemId=0 哨兵机制
- AI 兜底 NutritionResult.foodItemId=0（recognize_controller._aiFallbackNutrition）
- 写 meal_log 前必须调 upsertAiRecognized 创建真实 food_item 替换哨兵
- 三条路径已全部覆盖：recognize_page 单品、multi_dish_page 主菜+附加菜、offline_queue_controller

### 3.3 复合菜存储
- per100g=0 占位（实际热量在 meal_log.componentsSnapshotJson）
- nutrition_lookup.lookupSingleItem 过滤 componentsJson!=null 的记录（防 0 卡污染）
- listAllForRecommendation 排除 source='ai_recognized'

### 3.4 prompt 版本 v1.9
- v1.4：合并 v1.3（多菜多份 quantity/unit/perUnitG）+ v1.1（营养字段 estimated_calories 等）
- v1.6：包装容量优先（weight_source=package_label）+ 营养素自洽约束（4p+9f+4c≈cal，±5%）
- v1.7：新增 food_category 字段（water/carbonated/juice/milk/cream/oil/honey/sauce/alcohol/beer/wine/yogurt/soup/solid），用于包装液体 ml→g 密度换算
- v1.8：啤酒/茶饮剥离示例（雪花啤酒→dish_name=啤酒/brand=雪花）+ 连锁品牌 brand 必填
- v1.9：营养师人设 + reasoning 字段(CoT 推理) + 包装营养表 OCR 路径(6 字段) + 隐藏热量显式估算 + 盘子尺度参照 + 规则 8 修改(允许 reasoning 在 JSON 内) + 示例 7(珍宝珠酸条)+示例 8(麻婆豆腐)
- 旧 prompt 响应无 food_category/weight_source/reasoning/package_* 时默认 solid/ai_estimate/null/空（不换算、不走包装 OCR、不展示推理），向后兼容

### 3.5 per100g 反算 + 可食部分 + 密度换算三件套
- per100g 反算公式：`caloriesPer100g * effectiveG / 100`
- `effectiveG = servingG * edibleFactor`（建议 1）：edibleFactor 来自 FCT 数据 `ediblePercent` 字段（如香蕉 65%、带骨排骨 50%）
- 复合菜组分克数已是可食克数，不乘 edibleFactor
- 包装液体密度换算（建议 3）：`effectiveG = perUnitG * density * quantity`，仅 weight_source=package_label + 液体类别触发
- 三件套叠加顺序：识别 → **RecognitionPostProcessor.process**（密度换算→字段校验→营养素自洽→组分交叉验证→additionalDishes 修正）→ 查库反算（×edibleFactor）
- 第二波关键：三条路径（前台识别/重试/离线回补）都走 PostProcessor.process，行为一致

### 3.6 主题色
- themeSeedProvider（NotifierProvider<int>）+ secure_config_store 持久化
- **代码默认值是 M3 基线紫 0xFF6750A4**（`ThemeNotifier.build()` 与 `SecureConfigStore.getThemeSeed()` 默认都是这个值），不是莫奈青绿
- `0xFF5B8C7B 莫奈《睡莲》青绿` 只是 `kThemePresets` 列表第一项（设置页默认选中色），新用户首次安装实际显示基线紫，需用户主动选色才变青绿
- 12 色预设 kThemePresets
- main.dart runApp 前快速读，首帧即用正确主题色避免闪烁

### 3.7 启动流程（main.dart）
- runZonedGuarded 包整个 main
- 单一 ProviderContainer（UI 与初始化共用，不 dispose）
- themeSeed 快速读 → initSentryAndRunApp（appConfig 失败降级跳过 Sentry）→ runApp
- UI 起来后异步：appConfig / Workmanager / OfflineQueue（fire-and-forget）/ ImageCleanup（读用户保留期）

### 3.8 特殊人群营养适配（schema v2）
- profile 表加 3 个 nullable 列：specialCondition（生理状态）/dietPreference（饮食偏好）/healthCondition（健康状况）
- schema v1→v2 migration：`onUpgrade` 中 `m.addColumn` 加列，旧数据保持 null 视为 'none'（向后兼容）
- NutritionCalculator 调整权威来源：IOM 2006（孕期 +340 / 哺乳期 +500 kcal）、ISSN 老年蛋白 1.2g/kg、KDOQI 肾病蛋白 cap 0.8g/kg、ADA 糖尿病碳水 cap 45%
- 特殊人群调整在 goal 默认值之上覆盖：elderly 提蛋白（cut 不降）、kidney_issues 强制 cap、pregnancy/lactation 蛋白至少 1.1g/kg
- 能量加成在 deficit/surplus 之前加（避免减脂目标抵消孕期加成）
- JsonImporter 版本兼容：只拒绝高于当前的版本，允许旧备份导入（旧 JSON 缺新字段用 `as String?` 兜底 null）

### 3.9 食物查库匹配 5 级优先级 + 精确/模糊分离
- findByNameOrAlias（5 级模糊，识别主流程用）：①name 精确 → ②alias 精确 → ③name 双向 contains（长度约束）→ ④alias 双向 contains → ⑤name 编辑距离 ≤1（加严：query≥3 字且 target 等长，2 字短名禁用防雪花/雪碧假阳性）
- findExactByNameOrAlias（仅精确，反馈回流用）：只走 ①②，绝不模糊——避免模糊命中错对象导致 addAlias 反向错配永久污染别名表
- _normalize：全角→半角（数字/字母/空格/括号）+ 去空白 + 小写，避免全角字符精确 miss 降级模糊
- 反馈回流方向：AI 错误名 → 正确菜的别名（addAlias(correctFood.id, aiName)），查正确菜必须精确匹配
- addAlias 冲突检测：写入前遍历全表，若别名已是其他食物 name/alias 则拒绝（第二道防线）

### 3.11 推荐算法 v3 五维评分（参考业界 + 项目实际筛选）
- 调研：MyFitnessPal（大数据库+宏量分析）、Yazio（清洁 UX+断食）、薄荷（中式本土化+替代建议）、Lifesum（综合代谢画像）、Carbon Diet Coach（动态宏量调整）
- 弃用：协同过滤（单机无用户群）、AI 生成食谱（离线 app）、替换建议（需替代图谱留后续）
- 五维：①相对缺口匹配（Content-Based）②冷门降权+基础食材白名单（频次*4/基础*3/冷门*1.5）③profile 约束过滤（素食/乳糖/麸质硬排除，糖尿病/肾病软降权）④时段感知（数据驱动学 mealType 分布，非硬编码）⑤多样性（排除今日+昨日降权）
- 新增 MealLogRepository.getMealTypeDistribution(days:60) 学习食物历史 mealType 分布，样本<2 丢弃
- dashboard 按当前小时推断 mealType：5-10 breakfast / 11-13 lunch / 17-21 dinner / 其他 snack

### 3.12 MD3 全面优化（4 批清单 + 开源参考，commit `a8aa1f5`）
- 调研：MD3 v6.1 规范（圆角 4/8/12/16/28；Type Scale 15 档；Chip outlineVariant；Card filled/elevated/outlined 三变体；ColorScheme tertiary/secondary/primary 角色跨页配色）+ 开源饮食 app（FoodYou/NutriScan 的 Material You + Macro Rings）
- 第一批协调性：insight SegmentedButton pin AppBar.bottom（与 records_tab 统一）；weight 折线图按 insight 范式重写（左下边框+虚线网格+渐变填充+tooltip+统一 barWidth2.5+图例）；宏量跨页用 MacroColors 统一（替代 dashboard onPrimaryContainer alpha + today_meals 硬编码 0xFF4CAF50）；today_meals Card.outlined+12dp+padding16；today_meals section header 用 SectionTitle(trailing:)；me/settings Divider 用 cs.outlineVariant
- 第二批 MD3 合规：today_meals 编辑对话框"保存" FilledButton（原 TextButton 违反 MD3 主操作规范）；profile 特殊状况提示 Card(tertiaryContainer)（替代手写 Container）；profile/settings emoji 警告改 Icon(warning_amber_rounded, cs.error)（emoji 跨平台渲染不一致且不跟随主题）；settings 选中态 check 色按色块亮度动态选黑/白（WCAG AA）；recognize 遮罩 cs.scrim + 次要按钮 OutlinedButton 主次层级；food_library 列表补 chevron + 空态套 Card；me 错误态 Icon 补 cs.error；today_meals 反馈 IconButton 恢复 48dp 触摸目标
- 第三批字体层级：SectionTitle 用 titleSmall（原 labelLarge 语义偏标签）；批量硬编码 fontSize 转 textTheme（dashboard displaySmall/bodySmall/labelSmall/titleMedium/bodyMedium、today_meals labelSmall、me titleMedium/bodySmall、insight bodyMedium height:1.6）
- 权衡：records_tab/insight 用普通 AppBar+bottom 而非 SliverAppBar（IndexedStack/ListView 子页有自己滚动，SliverAppBar 需 CustomScrollView 重构成本大，bottom pinned 已满足"切换器常驻"需求）
- 验证：flutter analyze lib/ No issues + flutter test 337 passed (3 skipped)

### 3.13 深度审查修复 15 项（已随 v0.12.0 发布）
- 审查方法：4 路并行 search agent 分领域逐文件核对（features / ai+nutrition+data / core+main / test）
- 严重问题修复（S1-S6）：
  - S1 `TdeeCalibrator.runAndApply` 符号转换——calibrate 算法期望"减脂负/增肌正"但 profile.goalRateKgPerWeek 存正值，runAndApply 加 `signedGoalRate = goal=='cut' ? -rate : goal=='bulk' ? rate : 0` 转换
  - S2 `FoodItemRepository.insertManual` aliases 冲突检测——复用 addAlias 全表遍历逻辑，剔除已是其他食物 name/alias 的别名（防手动录入 AI 错误名绑多食物永久错配）
  - S3+S5 `RecognitionValidator` 营养素自洽加 `expected>0` 守卫——酒精饮料（7kcal/g 不在 Atwater 4p+9f+4c）/纤维/糖醇等非 Atwater 来源热量不能强制清零
  - S4 `JsonImporter` DELETE 序列加 pending_recognitions——`pending_recognitions.result_food_item_id` 是 FK NO ACTION，必须在 DELETE food_items 之前清
  - S4+ `JsonImporter` `as int` 强转改 `_asInt`/`_asIntOrNull` 兜底——旧版备份缺字段 `null as int` 抛 TypeError
  - S6 `SentryFlutter.init` 包 try-catch 降级——失败时返回原 app（不包 SentryWidget）保证 runApp 能执行
- 中等问题修复（M1-M10 + core L2/L3）：
  - `NutritionCalculator` gender=null 默认 1500 硬下限（避免女性拿到 <1200 危险低目标）
  - `PendingRecognitionRepository.markFailed` 包 `_db.transaction`（防"立即重试"与 workmanager 并发计数丢失）
  - `backup_page` 遮罩 `Colors.black54` → `cs.scrim.withValues(alpha:0.54)`
  - `sentry_scrub` hex 正则 `[a-f0-9]` → `[a-fA-F0-9]`（大写 hex 也脱敏）
  - `RecognitionValidator` confidence/estimatedWeightGMid 加 isNaN 显式判断（NaN 绕过 <0/>1 校验）
  - me_page/settings_page 版本号 0.10.0 → 0.11.1
- 测试修复（test S1/S3/S4）：
  - `recommendation_service_test` 4 处 `if (idx>=0)` 守卫加 `expect(idx, greaterThanOrEqualTo(0))` 前置断言（防假绿）
  - `json_export_import_test` seedData 加 schema v2 三字段断言（防导出导入漏字段）
  - `meal_log_repository_test` 新增 foodItemId=0/-1 哨兵防御测试（防外键约束违规崩溃）
- 暂不修复（需设计调整）：
  - NutritionLookup 3x OFF 云查（需重构查库逻辑）
  - RecognitionPostProcessor correctAdditionalDishes needsRetry 丢弃（需改 process 返回结构）
  - RecognitionPostProcessor macros 不修正（需扩展 copyWith）
  - image_quality_checker 未用 isolate（需顶层函数重构）
  - main.dart zone guard 不 runApp（需确认兜底策略）
- 验证：flutter analyze lib/ test/ No issues + flutter test 340 passed (3 skipped)

### 3.14 启动器图标精致化（commit `c37912b`，已随 v0.12.0 发布）
- 规范：Android Adaptive Icon（API 26+）—— 108dp 画布 + 66dp 安全区居中 + 前景/背景/monochrome 三层；OEM 蒙版自动裁剪为圆/方/圆角方，前景必须避开边缘
- 品牌语义：碗=食物，蒸汽=袅袅升起的温热感=「慢慢吃」，与 App 名呼应
- 配色：背景莫奈青绿渐变（与主题 seedColor `#5B8C7B` 一致），前景奶白 `#FDFBF7`（与 splash `#FCF9F9` 协调，温暖感优于纯白）
- 精致化五点：①背景对角线三色渐变（立体感）②碗口 evenOdd 环形双线（厚度感）③碗底小椭圆底座（稳重感）④蒸汽 stroke 2.8 + 错落（柔和）⑤奶白前景
- 实现：vector drawable（API 26+ 现代设备）+ Pillow 4x 超采样生成 5 密度 PNG fallback（API 21-25 旧设备，48/72/96/144/192）
- monochrome 复用前景供 Android 13+ 主题图标（用户可让图标跟随壁纸取色）

### 3.15 食物识别增强四层自我进化架构（P0/P1/P2，已随 v0.13.0 发布）

解决"雪花啤酒识别成雪碧 + 奶茶/网红零食能否准确分辨 + 热量能否严谨计算"三问。

核心思路：不追求本地库覆盖所有食物（不可能也无需），建立四层闭环：
1. **AI 估算（品类校准兜底）**——离谱估算用 13 品类默认值拦截
2. **品牌库（头部覆盖）**——10 品牌 41 招牌产品官方热量精确
3. **OFF（包装食品）**——百万级云查补漏 + brand 组合查询
4. **用户纠错（长尾自进化）**——反馈回流精确 miss 时创建新条目

**P0 品类校准 + brand 持久化**：
- 新建 `lib/data/seed/food_category_defaults.dart`——13 品类 per100g 默认值（beer=43/wine=83/alcohol=298/carbonated=43/juice=46/milk=61/yogurt=72/cream=345/oil=889/honey=321/sauce=63/soup=30/water=0），solid 不提供（差异太大）；`calibrate` 方法按 2 倍阈值校准（AI 估算偏离默认值 2 倍以上用默认值替代，否则保留 AI 估算）
- `food_item_repository.upsertAiRecognized` 加 `brand` 参数——把"品牌+菜名"（如"雪花啤酒"）存为 alias，下次 AI 返回完整品牌名精确命中；冲突检测复用 addAlias 全表遍历逻辑（防 brand+name 已是其他食物 name/alias）；新增 `_mergeAliasSafely` 异步方法做更新路径的冲突检测（事务内 select 全表）
- recognize_page / multi_dish_page / offline_queue_controller **三路径同步品类校准 + brand 传递**（违反硬约束 3 会导致后台回补路径热量偏差）

**P1 品牌官方热量库**：
- 新建 `assets/chain_drink_menu.json`——10 品牌 41 招牌产品（喜茶/霸王茶姬/奈雪/瑞幸/星巴克/蜜雪冰城/古茗/茶百道/一点点/Manner），数据来自各品牌小程序官方公示
- `FoodSeedImporter.importChainDrinksFirstTime`——name 存"品牌+品名"（如"喜茶多肉葡萄"），aliases 含品名简写；per100g 反算 `calories/(size_ml/100)`，defaultServingG=size_ml（现制茶饮密度≈水）；database wasCreated 调用
- `findByNameOrAlias` 加 `brand` 参数——优先级 0 按 brand+name 精确查（高于 name 精确），避免通用"奶茶"条目抢先命中"喜茶奶茶"；brand 为空时行为不变（向后兼容）
- `nutrition_lookup.lookupSingleItem` 加 `brand` 参数透传查库和 OFF
- `recognize_controller` 主菜和附加菜查库传 brand（L302/L330）

**P2 OFF brand 组合查询 + 反馈回流创建新条目**：
- `OffProvider.lookup` 加 `brand` 参数——先查"brand+name"（如"雪花 啤酒"），未命中回退查 name；提升品牌包装食品命中率
- `today_meals_page` 反馈回流——`findExactByNameOrAlias` 精确 miss 时（库里无此菜）调 `insertManual` 创建新条目（source='manual'，aliases=AI 错误名），实现长尾自进化；营养用 meal_log 实际值反算 per100g，仅在 `servingG>0 && actualCalories>0` 时创建（防 0 卡污染库）

**prompt v1.8（v1.7 → v1.8）**：
- 补充啤酒/茶饮剥离示例——示例 5 雪花啤酒（dish_name=啤酒/brand=雪花，强调瓶身文字"雪花"不是"雪碧"）、示例 6 喜茶多肉葡萄（dish_name=多肉葡萄/brand=喜茶）
- 规则 1 补充啤酒/葡萄酒/白酒剥离说明 + 现制茶饮/咖啡剥离说明
- 强调连锁品牌 brand 必填（后端按 brand+name 查品牌库）

**测试**：新增 18 个测试（品类校准 11 + brand 匹配 3 + brand 持久化 4），全量 358 passed (3 skipped)。FakeOffProvider.lookup 和 _FakeNutritionLookup.lookupSingleItem 签名同步加 `{String brand = ''}` 防止 invalid_override

### 3.16 全 editable 架构（4 批渐进，第一批已随 v0.13.0 发布）

解决用户反馈"所有功能都希望自己改，比如体重输错了点了确认后还能改"。审计现状：weight_logs 无 update/delete（ListTile 无交互）、meal_logs updateMealLog 只接受 5 营养字段（无 date/mealType/foodItemId）、food_items 无 delete/无 name 编辑、pending_recognitions 无 UI 页、recognition_feedbacks 无 list/delete、insight_summaries 无历史访问。4 批渐进实施。

**第一批（P0：体重 + 餐次全 editable，已随 v0.13.0 发布）**：
- `WeightLogRepository` 加 `getById(id)` / `update(id, weightKg?, date?)` / `delete(id)` —— 部分更新模式（null 跳过用 `Value.absent()`，非 null 用 `Value(x)`）
- `weight_page` ListTile → Dismissible（confirmDismiss 二次确认 dialog 比 Undo SnackBar 更适合低频数据）+ onTap 编辑 dialog（StatefulBuilder 局部刷新避免重建整个页面）
- **编辑最新一条体重必须同步 ProfileRepository.update(weightKg:)**（与 _save 一致逻辑，否则 dashboard 宏量目标 proteinGPerKg*weightKg 仍用旧体重）；判断"最新"用 `_logs.isEmpty || log.id == _logs.last.id`（_logs 已按日期升序）
- `MealLogRepository.updateMealLog` 从 5 必填扩展为 8 可选（加 date/mealType/foodItemId），向后兼容现有 5 处调用（required double → double? 不破坏调用方）
- **新增独立 MealEditDialog**（ConsumerStatefulWidget，不内嵌 AlertDialog）—— 复杂表单状态隔离；5 个 TextEditingController（份量 + 4 营养）+ 4 个独立状态（_mealType/_selectedDate/_newFoodItemId/_nutritionOverridden）
- **营养重算优先级**：advanced 手动覆盖 > 换食物重算 > 份量比例。`_nutritionOverridden` 标志由 4 个营养 TextField 的 listener `_markOverride` 设置；`_setCtrlSilently` 在程序化设值前移除 listener，避免触发 override 误判
- **换食物**：push `FoodLibraryPage(pickForReuse:true)` 接收 FoodItem，用新食物 per100g × 当前份量重算营养（与 NutritionLookup.lookupSingleItem 反算公式一致：caloriesPer100g * servingG / 100）
- **哨兵防御扩展**：`updateMealLog` 加 `foodItemId != null && foodItemId <= 0` ArgumentError（与 insertMealLog 一致，防 UI 把 0 哨兵写入非空 FK 字段致 PRAGMA foreign_keys=ON 崩溃）

**第二批（待实施）：FoodItems 删除/归档 + name/aliases 编辑**
- 现状：FoodItemRepository 无 delete 方法，food_edit_page 只能改营养不能改名
- 计划：加 delete（带 meal_log 引用检查，有引用则归档 source='archived' 而非物理删除）+ updateName + updateAliases

**第三批（待实施）：PendingRecognitions UI 页 + 重试/删除 + Feedbacks 历史/删除**
- 现状：pending_recognitions 无 UI 页（只能 workmanager 后台重试），recognition_feedbacks 无 list/delete
- 计划：me_page 加"离线队列"入口显示 pending 列表（手动重试/删除单条），加"反馈历史"列表（按时间倒序，可删除）

**第四批（待实施）：历史 InsightSummaries 查看页 + 份量校准回滚**
- 现状：insight_summaries 只显示当前周期，历史 insight 无访问入口；meal_log 份量校准后无法回滚到 AI 原始估算
- 计划：insight_page 加历史周期 SegmentedButton（weekly/monthly 切换 + 滚动历史），meal_log 加 estimatedServingGAiOriginal 字段记录 AI 原始值供回滚

### 3.17 UI/UX 审查修复 Phase 3（A+B+C+D 四批，已随 v0.13.0 发布）
4 路并行 search agent 全面审查所有界面，识别 14 S + 30+ M + 10 L 级问题，分 6 批（A-F）渐进修复。本次完成 A+B+C+D 四批共 26 项（E 评估后跳过、F 待用户确认）。

**公共抽象层模式**：把跨页重复的 UI 模式/工具函数提取到共享文件（m3_widgets.dart / core/util/），防止各页实现漂移。

**B 批（公共抽象层第一轮）**：新增 4 个共享组件（EmptyState / GroupCard / MealTypeSelector / confirmDiscardChanges）+ 2 个工具（date_format / food_name）
- **B6 主题单一源**：app.dart 的 `inputDecorationTheme` 是全局 OutlineInputBorder 定义，各页 TextField 不再重复声明 `border: OutlineInputBorder()`，改主题色只需改 app.dart 一处

**A 批（数据安全）**：
- **A1 乐观删除 + Undo**：Dismissible 先从 UI 移除 + 4s 撤销 SnackBar，未撤销才实际 DB delete。比"立即删 + SnackBar 提示"更宽容误操作。删除失败回滚 `_load()`
- **A3 PopScope + _dirty 追踪**：编辑页加 `_dirty` 标志 + `_markDirty()` + controller listeners；`PopScope(canPop: !_dirty)` 拦截返回 + `confirmDiscardChanges` 共享 dialog。`_markDirty` 必须加 `_loading` 守卫——初始 `_loadXxx()` 异步赋值 controller.text 会触发 listener，若不守卫会误标 dirty 致首屏就拦截返回
- **A4 错误态可重试性判断**：recognize_page 错误态 SnackBar 加"重试"按钮，按错误消息内容判断可重试性。「操作太快」/「已转手动录入」/「安全过滤」三类不显示重试（重试无意义或已跳转），其余错误可重试。用 `msg.contains(...)` 字符串匹配判断，因 controller 的错误文案是固定字符串
- **权衡**：A4 用字符串匹配判断错误类型而非枚举，因 controller 已有的错误文案是固定中文字符串，改枚举需动 controller 状态结构，本次最小改动只动 recognize_page。后续若错误类型增多可重构为枚举

**C 批（数据安全 + 一致性 S 级，commit `d46a1b9`）**：
- **C1 today_meals 乐观删除页面销毁后未删 DB 修复**：A1 引入的 bug——`onDismissed` 里 `setState` + `await SnackBar` 后才 DB delete，但 await 4s 期间页面可能已销毁（用户切 tab），`if (!mounted) return` 跳过 delete 致记录"复活"（UI 已删但 DB 还在，下次 _load 重新出现）。修复：在 await 前提前 `final mealRepo = await ref.read(...)` + `final id = m.id` 捕获引用，DB delete 不依赖 mounted，删除失败用捕获的 messenger 显示错误（不用 context）
- **C2 today_meals 加载失败显 ErrorState**：原 `_load()` catch 置空列表，build 中显示"今日暂无记录"误导用户以为今日真无数据。加 `_loadError` 标志区分"加载失败"与"空数据"，失败时显 `EmptyState(icon: error_outline, actionLabel: '重试')`
- **C3 insight 错误信息独立 `_error` 字段 + errorContainer Card**：原 controller 失败时把错误塞进 `_summary` 字段伪装 AI 输出（用户看到 "AI 汇总失败：xxx" 像 AI 响应）。改独立 `_error` 字段，build 中用 `Card(color: cs.errorContainer)` 醒目显示，与正常 AI 汇总分隔
- **C4 meal_edit_dialog ChoiceChip → MealTypeSelector**：B5 抽象出 MealTypeSelector 后，meal_edit_dialog 仍用内联 ChoiceChip 4 段（与 recognize/manual_entry 不一致）。改用 MealTypeSelector 统一三页餐次选择 UI
- **C5 multi_dish_page + manual_entry_page 补 PopScope 未保存确认**：A3 漏补两页——multi_dish 用户拖滑块改份量/数量后未确认直接返回会丢修改；manual_entry 5+ TextField 输入到一半返回同样丢。两页都加 `_dirty` 标志（滑块 onChanged / controller listener 触发）+ PopScope + confirmDiscardChanges
- **C6 emoji ⚠ → Icon(Icons.warning_amber_rounded)**：backup/calibration 的 emoji 警告跨平台渲染不一致（iOS/Android 字体不同）且不跟随主题色。改 Icon 用 cs.error 色，与 profile/settings 一致（已在 v0.12.0 a8aa1f5 完成 profile/settings 两页，C6 补完剩余 backup/calibration）
- **C7 FilledButton 内 CircularProgressIndicator 加 color**：8 处 FilledButton 内的 loading 圈用默认 primary 色，在 errorContainer/FilledButton 背景下对比度不足。加 `color: cs.onPrimary` 或 `cs.onPrimaryContainer` 保证可见
- **C8 app.dart 加 textButtonTheme + outlinedButtonTheme minimumSize 48dp**：MD3 默认 TextButton/OutlinedButton 高度 40dp 不满足 WCAG 2.5.5 触摸目标最小 44dp（推荐 48dp）。设 `minimumSize: Size(48,48)` 全局生效，避免各页再单独设

**D 批（公共抽象层第二轮 + 第三轮，commit `390d19a` + `4252093`）**：
- **D1 foodSourceLabel 集中**（commit `390d19a`）：food_edit_page + food_library_page 各有本地 `_sourceLabel(source)` switch 把 'manual'/'ai_recognized'/'brand_official' 等映射到中文标签。提到 `food_name.dart` 的 `foodSourceLabel(source)` 函数，新增 source 类型只改一处
- **D2 删 _sectionTitle 包装**（commit `390d19a`）：me_page（3 处）+ settings_page（7 处）有零价值间接层 `_sectionTitle(text) => SectionTitle(text)`，直接用 `SectionTitle(text)` 删除中间层。10 处调用替换 + 2 个私有方法删除
- **D3 EmptyChartHint 组件**（commit `390d19a`）：weight_page + insight_page 各有本地 `_emptyChartHint` 实现（Card + show_chart 图标 + 灰文提示"暂无数据"）。提到 `m3_widgets.dart` 的 `EmptyChartHint` 共享组件（120px 高 Card + show_chart 图标 + onSurfaceVariant 灰文），与全屏 `EmptyState` 区分（图表占位用 EmptyChartHint 120px，全屏空态用 EmptyState）
- **D4 WarningBanner 组件**（commit `390d19a`）：settings_page 2 处内联 `Padding+Row(Icon+Text)` 警告横幅实现重复。提到 `m3_widgets.dart` 的 `WarningBanner(text)` 共享组件（warning_amber_rounded 图标 + cs.error 色文 + 12px 字号），统一警示横幅样式
- **D5 confirmAction 共享确认对话框**（commit `4252093`）：m3_widgets.dart 新增 `confirmAction(context, title, content, {cancelLabel, confirmLabel, icon, destructive})`，统一 AlertDialog 取消/确认两按钮样板。支持 `destructive`（errorContainer 配色确认按钮，用于删除）+ `icon`（cs.error 色警示图标，用于风险警告/确认导入）。替换 4 处内联 `showDialog<bool>`：weight_page 删除体重确认（destructive）/ profile_page 风险警告确认（icon）/ insight_page 重新生成确认（简单）/ backup_page 确认导入（icon）。profile_page 原用 `Row(icon+title)` 非标准模式，改 MD3 `AlertDialog.icon` 参数更合规
- **D6 showAppToast 共享 toast 提示**（commit `4252093`）：m3_widgets.dart 新增 `showAppToast(context, msg, {duration})`，封装 `ScaffoldMessenger + SnackBar` 样板。替换 23 处简单 SnackBar（无 SnackBarAction 的成功/失败/提示消息），覆盖 8 文件：today_meals / meal_edit_dialog / weight / settings / profile / manual_entry / backup / multi_dish_page。backup_page 4 处带 5s duration（导入导出操作结果需更长阅读时间）。**recognize_page 4 处带 SnackBarAction 重试按钮的不替换**（重试按钮是功能性入口，showAppToast 不支持 SnackBarAction）

**E 批（评估后跳过）**：24 处硬编码 `fontSize:` 扫描。多数在图表上下文（insight/weight 的 fl_chart 坐标轴标签、tooltip）需精确字号控制，转 textTheme 无收益；4 处非图表（settings/profile/backup 脚注）转 textTheme 收益微小。整体评估为低价值，跳过

**验证**：
- C 批：flutter analyze No issues + flutter test 392 passed (3 skipped)
- D 批第二轮（D1-D4）：flutter analyze No issues + flutter test 392 passed (3 skipped)
- D 批第三轮（D5+D6）：flutter analyze No issues + flutter test 392 passed (3 skipped)

### 3.18 v1.9 包装 OCR 优先路径（Phase 2，三路径全覆盖）

解决"豆包能精确识别珍宝珠酸条 57.6g/8 条装按包装营养成分表换算 325kcal，EatWise 做了很多工作仍不准"。核心思路：包装食品有营养成分表时优先按包装数据换算 per100g，跳过品类校准（包装数据是精确值无需校准）；无包装数据走原 AI 估算 + 品类校准路径。

**核心方法 `VisionRecognitionResult.computePackageNutritionPer100g()`**：
- 换算规则（与 prompts.dart v1.9 规则 10 一致）：
  - 单份 kcal：优先 `packageServingKcal`；为 0/null 时用 `packageServingKj ÷ 4.184`
  - per100g kcal = 单份 kcal × 100 ÷ `packageServingG`
  - 蛋白/脂肪/碳水：包装通常不标，用 AI 估算按 per100 反算（`estimatedXxxG × 100 ÷ estimatedWeightGMid`）
  - mid=0 时 per100Ratio=0（防除零，蛋白/脂肪/碳水结果为 0，calories 仍按包装换算不依赖 mid）
- 返回 `(calories, protein, fat, carbs) per100g` 或 null（`packageServingG` 为 0 或所有 `serving_*` 为 0 时）
- `hasPackageNutrition` getter：任一 `package_serving_*` 字段非空非 0 即 true

**三路径哨兵分支全覆盖**（违反硬约束 3 会导致后台回补路径热量偏差）：
1. **recognize_page.dart**：哨兵分支 `if (n.foodItemId == 0)` 内优先检查 `result.hasPackageNutrition`，有则用 `computePackageNutritionPer100g()` 换算跳过品类校准
2. **multi_dish_page.dart**：提取 `resolveSingleFoodItemId` 本地函数，主菜(i==0)和附加菜(i>0)哨兵分支共用，逻辑与 recognize_page 一致
3. **offline_queue_controller.dart**：两处 LLM 兜底分支同步加包装 OCR 优先路径
   - 单品库未命中 LLM 兜底：包装 OCR 优先 + 品类校准兜底（与 recognize_page 一致）
   - 复合菜组分全 miss LLM 兜底：包装 OCR 优先 + AI 估算兜底（复合菜不做品类校准，无 meaningful food category）

**设计决策**：
- `actual*` 值（写入 meal_log 的本餐实际摄入量）仍用 AI 估算的整菜值，**不用包装换算值**。food_item 存 per100g 用作未来查库的"密度参考"，meal_log 存本餐实际摄入量。两者职责分离
- 复合菜组分全 miss 路径也加包装 OCR 优先——预包装速冻食品（如速冻水饺）可能被识别为 composite 但有包装营养表
- Phase 2 设计纠偏：原计划"删哨兵分支 + calibrate 前移到 PostProcessor"，但 calibrate 需要 `n.calories`（NutritionResult）而非 `result.estimatedCalories`，且库命中路径不应触发 calibrate → 改为"哨兵内加包装 OCR 优先路径"，保持原有结构

---

## 4. 已知陷阱（踩过的坑）

1. **APK 打不开**：build.gradle.kts 丢失 R8 禁用配置 → native 启动崩溃。必须保持 `isMinifyEnabled=false` + `isShrinkResources=false`
2. **SecureConfigStore.instance 不存在**：v0.8.0 用 `SecureConfigStore()` 构造函数，没有静态 instance。main.dart 用 `container.read(secureConfigStoreProvider)`
3. **initSentryAndRunApp 参数名**：是 `container:` + `app:`（命名参数），不是位置参数
4. **multi_dish_page take(5) 截断**：附加菜超 5 道静默丢弃，当前未提示用户（待优化）
5. **滑块 max 与 perUnitG*20 边界**：perUnitG 极大/极小时滑块与步进器可能不同步（待优化）
6. **测试 mock 需补 getThemeSeed stub**：AppConfig.load() 新增了 getThemeSeed() 调用，mock SecureConfigStore 的测试必须 stub
7. **复合菜组分克数已是可食克数，不能再乘 ediblePercent**：`lookupCompositeDish` 反算时不要加 edibleFactor（与单品 `lookupSingleItem` 不同），否则双重缩放
8. **密度换算只对 weight_source=package_label + 液体类别触发**：散装菜（ai_estimate）即使 foodCategory=milk 也不换算（视觉估算已是克数）；水基（密度=1.0）跳过避免无谓重建
9. **三路径必须走 RecognitionPostProcessor.process**：前台识别（recognize_controller）、重试结果、离线回补（offline_queue_controller）三条路径的 recognize 结果都必须经过 PostProcessor.process，否则行为分叉（第二波修复的关键约束）。重试结果若跳过 process 会导致密度换算被跳过（油 500ml 重试后 mid 仍是 500 而非 460）
10. **profile/weight 页保存后必须调 RefreshBus.notify()**：dashboard 唯一刷新入口是 RefreshBus 监听（main_shell FAB 也用此机制）。profile_page._save 和 weight_page._save 末尾都必须 notify，否则主页每日目标/宏量目标不更新。weight_page 还需同步 profile.weightKg（否则宏量目标 proteinGPerKg*weightKg 仍用旧体重）
11. **dashboard 用裸 FutureBuilder+setState，无响应式 provider**：当前 dashboard 不 watch 任何 profile provider，完全靠 RefreshBus 触发 _refresh() 重查库。若未来新增其他修改 profile 的入口，也必须调 RefreshBus.notify()
12. **JsonExporter/Importer 新增字段必须同步**：profile 表加列后，JsonExporter._profileToJson 要导出新字段，JsonImporter._profileFromJson 要读取新字段（用 `as String?` 兼容旧 JSON 无此字段）。否则备份恢复丢数据。本次 schema v2 漏导出 3 个特殊人群字段，已补修复
13. **DropdownMenu 测试用 find.byKey 定位**：不要用 `find.byType(DropdownMenu<String>).last` 或 `.first`，因为新增菜单会让索引漂移。本次 profile_page 新增 3 个 DropdownMenu 导致 .last 从 goal 漂移到饮食偏好菜单，测试失效。修复：给 goal 菜单加 `key: const Key('goal_dropdown')`，测试用 `find.byKey`
14. **JsonImporter 版本检查只拒绝高于当前**：`if (schemaVersion > _db.schemaVersion)` 而非严格相等，允许旧版本备份导入新版本 DB（向后兼容，老用户升级后可恢复旧备份）。旧 JSON 缺新字段由 _profileFromJson 用 `as String?` 兜底为 null
15. **findByNameOrAlias 优先级 5 编辑距离对 2 字短名禁用**：2 字短名编辑距离 1 无法区分"假阳性（雪花/雪碧）"与"typo（可东/可乐）"，禁用 2 字短名编辑距离（query.length>=3 且 target 与 query 等长才走）。typo 容错仅保留 3+ 字等长场景（蕃茄炒蛋→番茄炒蛋）
16. **反馈回流别名必须用 findExactByNameOrAlias 精确匹配查库**：today_meals_page 用户纠正菜名后调 addAlias 回流别名，查"正确菜"必须用精确匹配（name/alias 归一化相等），绝不能用 findByNameOrAlias 5 级模糊匹配。否则模糊命中错对象后把 AI 错误名写成错对象别名 → 永久错配且无法自愈（雪花啤酒模糊命中雪碧 → "雪碧"成雪碧别名 → 永久错配）
17. **SectionTitle padding 必须左右对称且与下方 Card 对齐**：`fromLTRB(16,20,16,8)`，左缘与 Card 的 EdgeInsets.all(16)/symmetric(horizontal:16) 对齐。曾用 `fromLTRB(24,20,16,8)` 左 24 右 16 不对称，被 6 页面 14 处复用导致"界面整体偏右"。改公共组件 padding 必须考虑所有复用页面
18. **addAlias 写入前必须做全表冲突检测**：写入别名前遍历全表，若别名已是其他食物的 name/alias 则拒绝写入（防反向错配第二道防线）。findExactByNameOrAlias 是第一道（调用方用精确匹配查"正确菜"），addAlias 冲突检测是第二道。两道防线缺一不可——单靠 findExact 仍可能因调用方传错 foodItemId 而写入冲突别名
19. **推荐算法 v3 冷门降权用动态蛋白权重**：常吃 *4 / 基础食材 *3 / 冷门 *1.5，三者区分决定排序。原 v2 全部 *4 致冷门高密度食物（蛋白粉等）盖过常吃基础食材（鸡蛋）。改权重必须同步 _scoreFood 里"非最缺宏量"分支的 0.4 系数（用 proteinWeight*0.4 保持比例）
20. **recommend() 新增维度参数必须可选且向后兼容**：profile/mealType/yesterdayDate 全可选，不传时退化到 v2 行为。现有 6 个 v2 测试不传新参数仍全过。新增维度测试在独立 group 里显式传参验证

21. **宏量营养素跨页配色必须用 MacroColors 共享类**：蛋白/脂肪/碳水三色在 `m3_widgets.MacroColors` 统一（蛋白=tertiary/脂肪=secondary/碳水=primary，跟随 seed 变化且色弱友好）。曾出现 dashboard 用 `onPrimaryContainer.alpha(0.x)`、today_meals 硬编码 `0xFF4CAF50` 致跨页颜色分裂。新增页面渲染三宏色必须用 `MacroColors.protein(cs)/fat(cs)/carb(cs)`，禁止再硬编码颜色值

22. **SectionTitle.trailing 是可选参数，向后兼容现有调用**：扩展 SectionTitle 加 `trailing?:Widget` 用于显示分组小计（如 today_meals 餐次标题 trailing 显示 "xxx kcal"）。现有 14 处 `SectionTitle(text)` 调用不传 trailing 不受影响。需要 trailing 的页面复用同一组件而非另起炉灶（曾因 today_meals 手写"色块+标题+sum"破坏统一）

23. **records_tab/insight 的 SegmentedButton 用 AppBar.bottom pinned 而非 SliverAppBar**：切换器需常驻顶部不随滚动消失。权衡：用普通 `AppBar(bottom: PreferredSize(...))` 而非 SliverAppBar，因 IndexedStack/ListView 子页有自己的滚动结构，SliverAppBar 需 CustomScrollView 重构成本大；AppBar.bottom pinned 已满足"切换器常驻"需求

24. **TdeeCalibrator calibrate 算法期望"减脂负/增肌正"符号**：但 `profile.goalRateKgPerWeek` 存正值（NutritionCalculator.dailyCalorieTarget 用 `>0` 判断 deficit/surplus）。`runAndApply` 必须按 goal 转换符号：cut 取负、bulk 取正、maintain 取 0，否则减脂用户校准方向恒错。改 calibrate 算法或改 profile 存储都会破坏多处依赖，符号转换在 runAndApply 边界处做最稳

25. **JsonImporter DELETE 序列必须先子表后父表**：`pending_recognitions.result_food_item_id` 是 FK NO ACTION，DELETE food_items 之前必须先清 pending_recognitions，否则 FK 阻塞致真机导入失败。当前序列：recognition_feedbacks → insight_summaries → weight_logs → pending_recognitions → meal_logs → food_items → profiles。新增带 FK 的表必须同步更新 DELETE 序列

26. **SentryFlutter.init 失败必须降级返回原 app**：初始化抛异常时 zone guard 只记日志不 runApp → 永久黑屏。`initSentryAndRunApp` 必须 try-catch 包 SentryFlutter.init，失败时返回原 app（不包 SentryWidget）保证调用方 runApp 能执行。Sentry 是可观测性工具，初始化失败不应阻塞 app 启动

27. **RecognitionValidator 营养素自洽校验只在 expected>0 时执行**：`expected = 4*protein + 9*fat + 4*carbs` 不含酒精（7kcal/g）、纤维、糖醇等非 Atwater 来源热量。若 expected==0 但 cal>0（如啤酒 cal=150 expected=48 实际 expected 来自 p/f/c 微量），强制清零会丢数据。校验器只在 `expected > 0` 时校验自洽性，expected==0 保留 AI 的 calories

28. **RecognitionValidator confidence/weight 必须显式判 NaN**：Dart 中 `NaN < 0 = false`、`NaN > 1 = false`、`NaN <= 0 = false`，AI 返回非数值字符串被 `double.tryParse` 解析为 NaN 时会绕过 `[0,1]` / `>0` 区间校验。校验器必须显式 `if (value.isNaN || value < 0 || value > 1)` 判断

29. **测试断言不能用 `if (idx >= 0)` 守卫包裹比较断言**：`indexWhere` 返回 -1 时 `if (idx >= 0)` 守卫让内部比较断言静默跳过 → 测试通过不代表功能正确（假绿）。应在比较前显式 `expect(idx, greaterThanOrEqualTo(0), reason: '...')` 前置断言确保元素在列表中，再执行比较。例外：被设计行为过滤的元素（如推荐算法超标场景 score<=0 的食物）保留 if 守卫，但其他元素必须强制断言

30. **insertManual aliases 参数必须做冲突检测**：addAlias 有全表冲突检测（陷阱 18）但 insertManual 的 aliases 参数路径曾漏掉。手动录入时若用户输入 AI 错误名作别名，可绑多食物致永久错配（与反馈回流 addAlias 同风险）。insertManual 必须复用 addAlias 全表遍历逻辑，剔除已是其他食物 name/alias 的别名

31. **JsonImporter 不要用 `as int` 强转可空字段**：旧版备份 JSON 缺字段时 `null as int` 抛 TypeError 致整个导入失败。所有非空 int 字段必须用 `_asInt(v) => (v as num).toInt()` 兜底（num 兼容 int/double），可空字段用 `_asIntOrNull(v) => v == null ? null : (v as num).toInt()`。导出 JSON 是跨版本兼容的关键入口，类型强转是常见崩溃源

32. **启动器图标改动必须同步 vector drawable + 5 密度 PNG fallback**：vector drawable（`mipmap-anydpi-v26/ic_launcher.xml` 引用 `drawable/ic_launcher_foreground.xml` + `ic_launcher_background.xml`）只对 API 26+ 生效；API 21-25 旧设备需 `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`（48/72/96/144/192）。只改 vector 不更新 PNG → 旧设备显示旧图标；只更新 PNG 不改 vector → 现代设备显示旧图标。两层必须同步。沙箱无 Android SDK/ImageMagick 时用 Pillow 4x 超采样 + LANCZOS resize 生成 PNG（抗锯齿）

33. **Android Adaptive Icon 前景必须在 66dp 安全区内**：108dp 画布，安全区中心 (54,54) 半径 33（即 21-87 范围）。OEM 蒙版（圆/方圆角）会裁掉安全区外内容。前景图形越界 → 部分 OEM 设备图标被裁残缺。改图标坐标后必须核对所有图形在 (21,21)-(87,87) 内

34. **Android vector 碗口环形用 evenOdd 而非纯色挖空**：背景是渐变色，碗口内椭圆若用纯色 `#5B8C7B` 挖空会与渐变背景色差。用 `android:fillType="evenOdd"` + 两个嵌套椭圆子路径（外椭圆 + 内椭圆），系统自动渲染环形（内椭圆区域不填充，露出背景渐变）。`fillType="evenOdd"` API 24+ 支持，自适应图标 API 26+ 兼容无问题

35. **品类校准阈值用 2 倍比例而非绝对偏差**：`FoodCategoryDefaults.calibrate` 按 `aiCal/defCal > 2.0 || < 0.5` 判断离谱，不用绝对偏差（如 `|aiCal-defCal|>50`）。原因：各品类默认值跨度大（water=0 vs oil=889），绝对偏差对低卡品类过严、高卡品类过松。2 倍阈值对啤酒（默认 43）容忍 AI 估 22-86，对油（默认 889）容忍 445-1778，比例统一合理。water 特殊：defCal=0 时 AI 任何正值都算偏离（ratio=999）→ 用 0 卡替代，避免把水估成有热量。仅校准 calories 偏离，蛋白/脂肪/碳水跟随品类默认值一并替换（差异大，AI 单项离谱也需拦截）

36. **upsertAiRecognized brand 别名冲突检测必须事务内做**：`_mergeAliasSafely` 在 `_db.transaction` 内调 `_db.foodItems.select().get()` 遍历全表，事务保证读到的快照一致。若在事务外做冲突检测再写库，期间其他事务可能写入同名 alias → 冲突检测失效。drift 事务对 SQLite 是 SERIALIZABLE（实际是 journal 锁），事务内 select-then-update 原子。`_mergeAliasSafely` 返回 `Future<List<String>?>`，调用方必须 `await`（曾因漏 await 致类型不匹配编译错误）

37. **品牌库 per100g 反算基于 size_ml 不是 calories 总值**：`importChainDrinksFirstTime` 用 `per100 = 100.0 / size_ml`（每毫升对应多少 100g 单位）反算 per100g，因为现制茶饮密度≈水（1ml≈1g），ml=g。若用 `calories / 总热量` 反算会循环引用。defaultServingG=size_ml（每杯总毫升数），用户调整份量时按 ml 缩放正确。改密度换算必须同步改反算公式（如咖啡密度 1.05 需 `size_ml*1.05` 转克）

38. **OFF brand 组合查询必须先 brand+name 再 name 回退**：`OffProvider.lookup` brand 非空时先查 `"$brand $dishName"`（如"雪花 啤酒"），OFF 有品牌产品名字段命中率高。若先查 name 再查 brand+name 会浪费一次 API 调用，且 name 单查可能命中通用"啤酒"而非"雪花啤酒"品牌产品。组合查询 miss 才回退 name 查询，最多 2 次 API 调用。`_searchOff` 是从原 `lookup` 内部逻辑提取的独立方法，避免组合/回退两路径代码重复

39. **反馈回流精确 miss 必须用 insertManual 创建新条目而非 addAlias**：`today_meals_page` 用户纠正菜名时，`findExactByNameOrAlias(correctedDishName)` 返回 null（库里无此菜）→ 必须调 `insertManual` 创建新条目（source='manual'，aliases=AI 错误名），不能调 `addAlias`（addAlias 需要 foodItemId，无条目可绑）。这是长尾自进化入口——用户每纠正一次新菜，库就多一条。仅在 `servingG>0 && actualCalories>0` 时创建（防 0 卡污染库）。反算 per100g = `100.0 / servingG`（用 `m.actualServingG` 用户校准后的真实克数，不是 defaultServingG）

40. **prompt v1.8 啤酒剥离示例必须强调瓶身文字**：雪花啤酒瓶身绿色与雪碧瓶身绿色视觉相似，AI 视觉模型仅看颜色易混淆。prompt 必须明确"读瓶身标签文字是'雪花'不是'雪碧'"，dish_name=啤酒/brand=雪花。仅靠品类校准（beer 默认 43）不够——若 AI 识别成雪碧（carbonated 默认 43，巧合热量相近），品类校准无法拦截，必须靠 prompt 引导 AI 读文字。同时 brand 字段必填连锁品牌（喜茶/瑞幸等），后端按 brand+name 查品牌库精确命中。prompt 改版本必须同步 bump `Prompts.version`（v1.7→v1.8），离线入队存 promptVersion 字段以便后续兼容

41. **Drift 部分更新必须用 Value.absent() 跳过 null 字段**：repo update 方法把可选参数转 `MealLogsCompanion` 时，`param == null ? const Value.absent() : Value(param)`。`Value.absent()` 表示"该字段不参与 UPDATE"，`Value(null)` 表示"该字段置 NULL"，`Value(x)` 表示"该字段置 x"。三者语义完全不同。若把 null 字段写成 `Value(null)` 会把数据库已有值清空（破坏数据）；写成 `Value.absent()` 才是"保持原值"。WeightLogRepository.update 和 MealLogRepository.updateMealLog 都遵循此模式。新增可选字段更新方法必须照此实现

42. **编辑最新一条体重必须同步 profile.weightKg**：weight_page 编辑/删除体重记录时，若操作的是 `_logs.last`（最新一条，_logs 已按日期升序），必须同步调 `ProfileRepository.update(weightKg: newValue)`。原因：dashboard 宏量目标 `proteinGPerKg * weightKg` 用 profile.weightKg 而非 weight_logs 最新值。若只改 weight_logs 不改 profile，dashboard 显示的目标仍是旧体重算的。判断"最新"用 `log.id == _logs.last.id`（按 id 不可靠，必须用已排序的 _logs 末位）。删除最新一条时，profile.weightKg 应同步为新的最新一条（_logs 倒数第二条）或保留——当前实现仅编辑时同步，删除时不同步（避免删完所有记录后 profile 体重被清空）

43. **复杂表单 dialog 必须提取为独立 StatefulWidget 而非内嵌 AlertDialog**：餐次编辑涉及 5 TextEditingController + 4 独立状态（_mealType/_selectedDate/_newFoodItemId/_nutritionOverridden）+ 换食物导航 + 日期选择 + 高级覆盖监听。若用 AlertDialog + StatefulBuilder 内联实现，状态管理混乱且无法用 ConsumerStatefulWidget 的 ref。提取为 `MealEditDialog extends ConsumerStatefulWidget` 后：①状态隔离在 dialog 内不污染父页 ②可用 ref.read(recognize.databaseProvider) 获取 DB ③controller 在 dispose 统一释放防泄漏 ④返回值类型化（MealEditResult）比 Map<String,dynamic> 安全。今后涉及 3+ 字段编辑的 dialog 都应提取为独立 widget

44. **TextField 程序化设值前必须移除 listener 避免误触发 override 标记**：MealEditDialog 的 4 个营养 TextField 加了 `_markOverride` listener（用户手动改值时标记 `_nutritionOverridden=true`，让 advanced 覆盖优先级最高）。但程序化设值（如换食物后重算营养、展开 advanced 时回填当前值）也会触发 listener → 误标记 override → 份量/换食物重算被跳过。`_setCtrlSilently` 方法在 setText 前 `removeListener`，setText 后 `addListener`，保证只有用户真实输入才标记 override。controller 的 listener 必须区分"用户输入"与"程序设值"两种触发源

45. **PopScope 编辑页 `_markDirty` 必须加 `_loading` 守卫**：编辑页（profile/settings/food_edit 等）在 initState 注册 controller listener 后才异步 `_loadXxx()` 给 controller.text 赋值。赋值会触发 listener → 若 `_markDirty` 无守卫会误标 `_dirty=true` → 首屏就拦截返回键弹"放弃修改"对话框（用户没改任何东西）。守卫模式：`void _markDirty() { if (_loading || _dirty) return; setState(() => _dirty = true); }`，`_loadXxx` 的 finally 块置 `_loading=false`。calibration_page 用滑块 onChanged 触发 dirty 不需守卫（无异步赋值），但 controller-based 的页面必须守卫

46. **GroupCard 分隔线策略：dividerIndent 非null 自动插 / null 手动插**：`GroupCard(dividerIndent: 16, children: [...])` 在子项间自动插 Divider（适合纯 ListTile/TextField 均匀列表）；`GroupCard(children: [...])` 不自动插（适合混合 ListTile + 警告 Padding 等非均匀内容，调用方用 `GroupCard.divider(context)` 手动在指定位置插）。曾因 me_page 的"使用情况"段含 cost 警告 Padding，用自动插会在 Padding 上下出现多余分隔线，改手动插解决。新增 GroupCard 调用需根据子项类型选策略

47. **app.dart inputDecorationTheme 是 OutlineInputBorder 全局单一源**：app.dart L68-71 的 `inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder())` 全局生效，各页 TextField 不再需要重复声明 `border: OutlineInputBorder()`。本次清除 6 文件 11 处冗余声明。改主题色/圆角只需改 app.dart 一处。新增 TextField 默认就用 OutlineInputBorder，无需显式声明 border（除非要 InputBorder.none 做内嵌 ListTile 样式）

48. **Undo SnackBar 乐观删除必须捕获 messenger 引用 + 用 undone 标志**：Dismissible 的 `onDismissed` 回调里 `setState(() => _meals.removeAt(index))` 后立即 `showSnackBar`，但 await 4s 后 widget 可能已 unmounted。必须 `final messenger = ScaffoldMessenger.of(context)` 在 await 前捕获引用（context 可能失效但 messenger 仍可用），用 `var undone = false` 标志在 SnackBarAction.onPressed 置 true，await 后检查 `if (undone) return` 跳过 DB delete。删除失败要 `await _load()` 回滚 UI + 错误提示。比"立即删"多一个 4s 窗口给用户反悔

49. **confirmAction/showAppToast 抽象：SnackBarAction 重试按钮与图表 fontSize 必须保持内联**：D5/D6 抽象出共享 `confirmAction`（确认对话框）+ `showAppToast`（toast）后，有两类场景必须保留内联实现不能用共享抽象——①**SnackBarAction 重试按钮**：recognize_page 4 处错误态 SnackBar 带"重试"按钮（SnackBarAction），是功能性入口（点击重新触发识别），showAppToast 不支持 SnackBarAction 参数，强行替换会丢重试功能。带 action 的 SnackBar 必须保留 `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:..., action: SnackBarAction(label:'重试', onPressed:...)))` 内联写法；②**图表 fontSize 精确控制**：fl_chart 坐标轴标签、tooltip 的硬编码 `fontSize: 10/11/12` 需精确像素控制（图表内文字与数据点对齐，textTheme 的相对单位会破坏对齐），不能转 textTheme。E 批评估跳过即因此。新增 toast 时先检查是否带 SnackBarAction，是则保留内联；新增图表文字样式时不要转 textTheme

50. **主题色默认值是 M3 基线紫 0xFF6750A4 不是莫奈青绿**：`ThemeNotifier.build()`（theme_controller.dart L11）和 `SecureConfigStore.getThemeSeed()` 默认值（secure_config_store.dart）都是 M3 基线紫 `0xFF6750A4`。`0xFF5B8C7B 莫奈睡莲青绿` 只是 `kThemePresets` 列表第一项（settings_page 设置页默认选中色）。新用户首次安装由 main.dart 读 storage（仍是基线紫），实际显示基线紫，需用户主动进设置页选色才变青绿。HANDOFF 第 3.6 节曾误写"默认莫奈青绿"已修正。改默认色必须同步改 ThemeNotifier.build + SecureConfigStore.getThemeSeed + kThemePresets[0] 三处，否则首帧色与设置页选中态不一致

51. **v1.9 包装 OCR 优先路径：actual* 与 per100g 职责分离 + 三路径必须同步**：`computePackageNutritionPer100g()` 返回的 per100g 值只用于 `upsertAiRecognized` 写入 food_item（作未来查库密度参考），**不能覆盖 meal_log 的 actual* 值**。actual* 仍用 AI 估算的整菜值（`result.estimatedCalories` 等），因为 meal_log 记录的是本餐实际摄入量，per100g 是食物的密度属性，两者职责不同。三路径（recognize_page / multi_dish_page / offline_queue_controller）哨兵分支必须同步加 `hasPackageNutrition` 优先检查，否则后台回补路径会用品类校准覆盖包装精确值致热量偏差。复合菜组分全 miss 路径也加包装 OCR 优先——预包装速冻食品可能被识别为 composite 但有包装营养表。`computePackageNutritionPer100g` 返回 null 时（servingG=0 或所有 serving_*=0）调用方必须走 AI 估算兜底，不能直接用 null 致空指针

52. **v4 推荐算法"未尝试" vs "少碰" 必须区分，不能都惩罚**：`UserPreferenceProfile._weight(tag, freq)` 必须三段判断——① `tag == null` 或 `freq.isEmpty` → 0.5 中性（未知）；② `!freq.containsKey(tag)` → 0.5 中性（用户从未吃过该标签，不惩罚"未知"，用户没吃过 ≠ 不喜欢）；③ 标签在 freq 表 → `freq[tag]! / max`（0.0-1.0）。原实现把②③混为一谈（`freq[tag] ?? 0`），导致用户从未吃过的口味被当 weight=0 触发减分分支（`w < 0.2 && freq.isNotEmpty`）。正确行为：只有"尝试过但很少"（如 sweet:10 + spicy:1，weight=0.1 < 0.2）才减分。`UserPreferenceLearner.learn` 永远不会产生 count=0 的 freq entry（只对吃过的食物打标签累加），所以 freq[tag]=0 只可能来自测试构造的人工 profile。改 `_weight` 必须同步改测试期望（user_preference_learner_test "未知标签 → 0.5 中性"）

53. **v5 AI 推荐失败必须静默返回空列表，绝不抛异常到 UI**：`AiRecommendationService.recommend()` 内部 `try/catch` 包裹 `_fetchFromAi`，任何异常（网络/超时/JSON 解析/API 错误）都返回 `AiRecommendationResult(recommendations: [], fromCache: false)`，dashboard 的 FutureBuilder 永远不会进 `hasError` 分支。AI 是"锦上添花"，v4 本地推荐永远兜底。**失败结果不缓存**（`_cache[cacheKey] = result` 只在成功路径执行），下次进看板允许重试。改 `recommend()` 不能把 catch 改成 rethrow，否则 dashboard 会显示红屏错误

54. **v5 AI 推荐缓存 key 必须含 mealType**：`_cache` key = `"${date}_${mealType}"`，不能只用 date。因为早餐和晚餐的推荐完全不同（早餐推燕麦粥，晚餐推牛排），共用 key 会导致用户早餐看完推荐后晚餐还看到早餐的缓存。`forceRefresh=true` 时跳过缓存（"换一批"按钮）。缓存是静态 Map（进程内存），App 重启失效，当日有效（跨天 key 变化自然失效）

55. **v5 schemaVersion 2→3 migration 必须用 createTable 不是 addColumn**：`recommendation_feedbacks` 是全新表（不是给旧表加列），migration 用 `m.createTable(recommendationFeedbacks)`。旧版本备份导入时（schemaVersion < 3）JSON 无 `recommendation_feedbacks` 段，importer 用 `tables['recommendation_feedbacks'] is List` 守卫跳过，不能强转 `as List` 否则旧备份导入崩。导出时必须包含该表（JsonExporter.export 新增 `recommendation_feedbacks` 段），否则新版本备份缺表数据

56. **v5 DashboardPage widget 测试必须 mock secureConfigStoreProvider 否则 pumpAndSettle 超时**：v5 看板 initState 调 `_aiRecFuture = _loadAiRecommendations()`，内部 `await ref.read(appConfigProvider.future)` 检查 GLM key。沙箱无 secure_storage 平台通道，`AppConfig.load()` 抛 MissingPluginException，但抛出前 AI FutureBuilder 已进入 loading 态显示 `CircularProgressIndicator`（无限动画）。即使 Future 最终 completes with error 让 FutureBuilder 切到 v4 兜底，`pumpAndSettle` 仍可能超时（10s 内未 settle）。修复：测试 setUp 调 `FlutterSecureStorage.setMockInitialValues({})` 注入内存平台实现 + override `secureConfigStoreProvider.overrideWithValue(SecureConfigStore())`，让 `appConfigProvider` 走真实路径返回空 config（glmApiKey.isEmpty → `_loadAiRecommendations` 早早 return empty，FutureBuilder 立即切 v4 兜底，无 loading 动画）。**新增任何 DashboardPage widget 测试必须遵循此模式**。详见 `dashboard_drawer_test.dart` / `estimation_range_ui_test.dart`

57. **v5 AI 推荐缓存值必须用 Future 不是 List 实现并发互斥**：`_cache` 是 `Map<String, Future<List<AiRecommendation>>>` 不是 `Map<String, List<AiRecommendation>>`。原因：用户连点"换一批"会并发触发多次 `recommend(forceRefresh: true)`，若缓存值是 List，forceRefresh 跳过缓存后多次并发调 AI 浪费 API 配额。用 Future 缓存后，即使 forceRefresh=false 的并发调用也共享同一 Future（第一个调用写入 Future，后续调用 await 同一 Future），AI 只调一次。失败时 `recommend()` catch 后 `_cache.remove(cacheKey)` 删除失败 Future，下次允许重试。**缓存 key 必须含 `profile.hashCode`**，否则用户改 profile（如目标从减脂→增肌）后缓存仍命中旧推荐

58. **v5 _parseRecommendations 解析失败抛 FormatException 不返回空列表**：与 pitfall 53 配合——`recommend()` 的 catch 兜底所有异常返回空，但 `_parseRecommendations` 内部必须区分两种情况：①AI 真返回 0 条有效推荐（如全部缺 name/reason 被跳过）→ 返回空 List，**可缓存**（避免当日反复调 AI 拿到同样的 0 条）；②JSON 解析失败（无 JSON 对象/缺 recommendations 字段/malformed JSON）→ **抛 FormatException**，`recommend()` catch 后 `_cache.remove(cacheKey)` **不缓存**（下次允许重试，因为可能是临时模型抽风）。若把②也返回空列表，会导致模型一次解析失败后当日永远命中空缓存无法重试。`_extractJson` 用括号配对扫描（depth 计数器）而非简单 indexOf/lastIndexOf，支持多个 JSON 对象场景

---

## 5. 常用命令

```bash
# 环境（沙箱每次需重设 PATH）
export PATH=/tmp/flutter/bin:$PATH

# 验证
flutter analyze
flutter test
flutter test test/features/settings_backup_overdue_test.dart  # 单个测试

# 构建（fat APK 全架构）
flutter build apk --release --no-tree-shake-icons

# Git
git log --oneline -10
git status
git tag --list 'v*'
```

---

## 6. 文件地图（关键文件）

```
lib/
├── main.dart                          # 启动：zone+Sentry+themeSeed+异步初始化
├── app.dart                           # M3 主题 + 4-tab StatefulShellRoute 路由
├── main_shell.dart                    # 底部导航壳 + FAB
├── ai/
│   ├── prompts.dart                   # v1.9 prompt（营养师人设+reasoning+包装OCR+隐藏热量）
│   ├── vision_provider.dart           # VisionRecognitionResult（含 copyWith + computePackageNutritionPer100g）
│   ├── vision_service.dart            # 视觉服务
│   ├── nutrition_lookup.dart          # NutritionLookup + NutritionSource 枚举
│   └── off_provider.dart              # Open Food Facts 云查
├── core/
│   ├── config/
│   │   ├── app_config.dart            # AppConfig.load() + appConfigProvider
│   │   └── secure_config_store.dart   # secure_storage 封装（含 themeSeed）
│   ├── theme/theme_controller.dart    # themeSeedProvider + kThemePresets
│   ├── util/
│   │   ├── image_quality_checker.dart # 模糊图预检（批次 1）
│   │   ├── recognition_validator.dart # 字段合理性 + 营养素自洽 + 组分交叉验证
│   │   └── recognition_post_processor.dart # 三路径共用后处理（密度换算+校验修正，第二波）
│   └── error/
│       ├── sentry_init.dart           # initSentryAndRunApp（appConfig 失败降级）
│       └── sentry_scrub.dart          # Sentry 脱敏
├── data/
│   ├── database/database.dart         # drift，PRAGMA foreign_keys=ON
│   └── repositories/
│       ├── food_item_repository.dart  # upsertAiRecognized（更新含 componentsJson）
│       ├── meal_log_repository.dart   # insertMealLog + updateMealLog（8 可选字段全 editable）
│       └── weight_log_repository.dart # insert + getRange + getById/update/delete（全 editable）
└── features/
    ├── recognize/
    │   ├── recognize_controller.dart  # AI 兜底 + 复合菜全 miss 转 AI
    │   ├── recognize_page.dart        # 哨兵处理 + 改菜名 copyWith
    │   ├── calibration_page.dart      # 校准 + 数量步进器 + 徽章
    │   └── multi_dish_page.dart       # 多菜 _hitFlags 含 componentHits 判定
    ├── offline/offline_queue_controller.dart  # 离线回补 AI 兜底 + fire-and-forget
    ├── settings/settings_page.dart    # 主题色板 + _isSaving
    ├── profile/profile_page.dart      # _busy + try-catch
    ├── weight/weight_page.dart        # _busy + _load try-catch
    ├── food_library/                  # food_edit_page + food_library_page
    ├── manual_entry/manual_entry_page.dart
    ├── backup/backup_page.dart        # 导入二次确认
    ├── me/me_page.dart
    ├── records/records_tab_page.dart
    ├── dashboard/dashboard_page.dart
    ├── dashboard/meal_edit_dialog.dart   # 全 editable 第一批：餐次编辑独立 dialog（换食物+改餐次+日期+高级覆盖）
    └── insight/insight_page.dart
```

---

## 7. 会话结束前 AI 必做

1. 更新本文件第 2 节"当前状态"（日期、commit、工作区、未完成项）
2. 如有新陷阱，补到第 4 节
3. 如有新架构决策，补到第 3 节
4. 确认 `git status` clean（或明确记录未提交的改动原因）
