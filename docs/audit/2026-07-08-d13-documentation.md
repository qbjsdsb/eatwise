# D13 文档维度检查报告

## 元信息

| 项 | 值 |
|----|----|
| 检查日期 | 2026-07-08 |
| 检查范围 | EatWise v0.33.0+46（分支 `trae/agent-wX1X6Q`） |
| HEAD commit | `b140745`（`feat: 了解项目进展`） |
| v0.33.0 tag 指向 | `bb30873`（`fix(build): 修复 build_runner 失败——sqlparser 0.44.5 override`） |
| git status | `docs/audit/` 下 D5–D9 报告未跟踪（本报告亦为新增未跟踪） |
| 检查维度 | HANDOFF / README / CHANGELOG / 代码注释 / 文档组织 / 架构文档 / 决策记录 / 提交信息 |
| 检查方法 | Read（HANDOFF/README/CHANGELOG/pubspec/build.gradle.kts）+ LS（docs、.trae）+ Grep（`^/// ` 文档注释覆盖、`^## ` HANDOFF 章节）+ `git log --oneline` + `wc -l` |
| 检查纪律 | 仅研究 + 写报告，不修改任何代码或既有文档 |

> 说明：本报告 HEAD `b140745` 比 D1–D9 用的 `bb30873`（v0.33.0 tag 点）新 2 个 commit（`d36b3b0 fix(audit)` + `b140745 feat: 了解项目进展`），均未触及 lib/ 代码，对文档维度结论无影响。

---

## 总体评价

EatWise 的文档体系**"重交接、轻对外"特征明显**：面向 AI 跨会话记忆的 `HANDOFF.md`（2776 行）和面向开发的 `CHANGELOG.md`（442 行，Keep a Changelog 规范）维护得相当扎实，决策记录与已知陷阱的沉淀深度在个人项目中罕见；但面向用户/新贡献者的 `README.md` 严重过时（停留在 v0.24.0，且含 1 处 P0 级系统要求误导），架构与 schema 缺独立文档（散落在 HANDOFF 各节），commit message 存在 33 次 `feat: 了解项目进展` 无信息提交污染历史。文档组织上 `.trae/specs/`、`.trae/documents/`、`docs/superpowers/specs/` 三处职能重叠，存在迁移未完成的双轨现象。

文档注释覆盖率良好：`lib/` 104 个 dart 文件中 89 个含 `///` 文档注释（85.6%），共 510 处，集中在 `m3_widgets.dart`（72）、`recommendation_service.dart`（22）、`meal_edit_dialog.dart`（20）、`calibrated_nutrition_calculator.dart`（24）等核心模块，注释语言统一为中文，与项目风格一致。

---

## 检查项与结果

| # | 检查项 | 结论 | 关键证据 |
|---|--------|------|---------|
| 1 | HANDOFF.md 时效性 / 当前状态 / 未完成项 / 已知陷阱准确性 | ⚠️ 部分过时 | 第 1 节"HEAD = 6c4b57d"+"待打 tag v0.33.0" 与实际 HEAD `b140745`、tag `v0.33.0→bb30873` 不符；第 2 节从第 35 行堆到第 2356 行（2300+ 行历史状态）已成日志而非"当前状态"；第 3/4/5/6/7 节内容详实准确 |
| 2 | README 项目用途 / 构建方法 / 使用方法 | ❌ 严重过时 + 1 处 P0 误导 | 版本 badge v0.24.0（实际 v0.33.0）；"Android 8.0+（minSdk 26）"与实际 `minSdk = 31`（Android 12+）矛盾；功能矩阵未提蓝牙体脂秤；目录结构写 `data/models/`（实际无此目录）；硬约束写"6 条"（实际 6+1） |
| 3 | CHANGELOG 维护与版本记录完整性 | ✅ 优秀 | 442 行，遵循 Keep a Changelog 1.1.0 + SemVer；含 `[Unreleased]` + v0.33.0→v0.16.0 完整段；每版本有改动/修复/验证三段式 |
| 4 | 代码注释（公共 API `///` / 复杂逻辑解释 / 语言一致性） | ✅ 良好 | 89/104 文件 510 处 `///`；语言统一中文；核心算法（body_fat_calculator、tdee_calibrator、mi_scale_parser）注释解释公式来源 |
| 5 | docs/ 目录组织 / 过期文档 | ⚠️ 双轨 + 过期未标 | `docs/audit/`（D1–D9 + M23 系列）、`docs/superpowers/{specs,plans}/`（按日期）清晰；但 `.trae/specs/`（M16–M26 老 spec）、`.trae/documents/`（UI 审查 + 里程碑总结）、`docs/superpowers/specs/`（M25+ 新 spec）三处职能重叠；M23 审计报告基线 v0.21.0 已过期 12 版未标注 |
| 6 | 架构文档（概览 / 数据流图 / 数据库 schema） | ⚠️ 散落无独立文档 | 无独立 `architecture.md` / 数据流图；HANDOFF 第 3 节（3.1–3.16 架构决策）+ 第 6 节（文件地图）承担概览职能；`drift_schemas/eatwise_database/drift_schema_v1.json` 是 v1 快照，当前 schema 已 v5，未同步 |
| 7 | 决策记录（ADR / 关键设计决策文档） | ⚠️ 无 ADR 目录，靠 HANDOFF+specs 替代 | 无 `docs/adr/` 目录；HANDOFF 第 3 节"关键架构决策（不要轻易改）"是事实上的 ADR；`docs/superpowers/specs/` 每个里程碑设计文档承载决策上下文，但无统一索引 |
| 8 | 提交信息规范 / commit message 规范 | ⚠️ 规范存在但执行不严 | 主流遵循 Conventional Commits（feat/fix/chore/test/docs/perf + scope）；但 33 次 `feat: 了解项目进展` 无信息提交污染历史；早期 `M26 A:` `v0.27.0:` 等非规范前缀；最新 HEAD `b140745` 即为无信息提交 |

---

## 发现的问题

### P0（严重）

**P0-1：README.md 系统要求 `minSdk 26` 与实际 `minSdk = 31` 矛盾，误导用户安装**

- **位置**：`README.md:96` "Android 8.0+（minSdk 26）"
- **实际**：`android/app/build.gradle.kts:25` `minSdk = 31  // 动态取色（Material You）需 Android 12+（API 31）`；项目规则第 7 条硬约束明确 "minSdk = 31（dynamic_color 包硬性要求，提升后丢失 Android 7-11 用户）"
- **影响**：用户按 README 期望在 Android 8.0–11 设备安装，实际 Android 12 以下安装会失败（`INSTALL_FAILED_OLDER_SDK`）。这是"文档严重误导"级别的硬伤——README 是对外发布页（GitHub Release 链接 `qbjsdsdsb/eatwise`），用户拿到 APK 装不上会直接判定项目不可用。
- **关联过时项**（同文件，一并需修）：
  - `README.md:5` version badge `v0.24.0`（实际 `pubspec.yaml:4` `version: 0.33.0+46`）
  - `README.md:10` tests badge `1056 passed`（实际 1172 passed）
  - `README.md:97` "约 75 MB 存储空间"（v0.30.1 瘦身后 release APK ≈42 MB）
  - `README.md:115–132` 版本演进表停在 v0.24.0（缺 v0.25.0–v0.33.0 共 9 个版本）
  - `README.md:138` "✅ v0.24.0 已发布"（实际已到 v0.33.0，v0.31.0/v0.33.0 均已打 tag）
  - `README.md:167` "6 条硬约束"（实际 6+1，第 7 条 minSdk=31）
  - `README.md:65` 目录结构写 `data/models/`（实际 `lib/data/` 下无 `models/` 目录，应为 `database/tables/`）
  - `README.md:34` 功能矩阵"体重 | 体重记录 + 趋势图"（未提 v0.31.0 蓝牙体重秤同步 + v0.32.0 体脂秤2 + 体脂率 + BMR 自动升级）
- **建议**：优先修 P0-1（minSdk 26→31，Android 8.0→12.0），同步刷新版本 badge / 演进表 / 硬约束数 / 体积 / 功能矩阵。README 应建立"发版必更"检查项。

### P1（高优先级）

**P1-1：HANDOFF.md 第 1 节"项目速览"HEAD 与 tag 状态过时**

- **位置**：`HANDOFF.md:27` "当前分支：trae/agent-wX1X6Q（HEAD = 6c4b57d 已 push 到 remote...）"
- **实际**：HEAD = `b140745`，6c4b57d 之后还有 `bb30873`（v0.33.0 tag 点）、`d36b3b0`、`b140745` 三个 commit
- **位置**：`HANDOFF.md:26` "已 push 到 trae/agent-wX1X6Q 分支，build_runner 修复完成...待打 tag v0.33.0 触发 GitHub Actions 构建"
- **实际**：`git tag` 显示 `v0.33.0` 已存在，指向 `bb30873`
- **影响**：新 AI 会话开启按规则第一步读 HANDOFF，会误以为 v0.33.0 未发版而重复打 tag 或重复构建。HANDOFF 自述"每个会话开始时 AI 必读"，第 1 节是速览，过时信息会直接误导后续决策。
- **建议**：第 1 节"当前分支/HEAD/tag"三要素每次会话结束必更（HANDOFF 第 7 节已规定，但执行不到位）。

**P1-2：HANDOFF.md 第 2 节"当前状态"沦为历史日志，2300+ 行堆积**

- **位置**：`HANDOFF.md:35`（## 2. 当前状态）到 `HANDOFF.md:2356`（## 3. 关键架构决策 前）共 2321 行
- **现状**：第 2 节自述"每次会话结束更新"，但实际是不断**追加**而非**更新**——从 v0.33.0 一路堆到 v0.16.0 时代的 M16.1–M16.9、M17–M21，每个里程碑完整保留 commit 列表 + 验证结果 + 设计文档链接
- **影响**：①HANDOFF 总 2776 行，第 2 节占 83%，AI 读取 token 成本高；②"当前状态"语义被稀释，新 AI 难以快速定位"现在到哪了"；③与 CHANGELOG.md 职能重叠（CHANGELOG 已有完整版本记录）
- **现状 mitigations**：第 2 节顶部有"最后更新：2026-07-09"和 v0.33.0/v0.32.0 最新两段，最新信息可定位；历史段落有清晰的小标题分隔
- **建议**：第 2 节只保留"最新 1–2 个版本 + 未完成项 + 待办"，历史里程碑迁入 `docs/superpowers/` 或直接引用 CHANGELOG（CHANGELOG 已是权威版本日志）。HANDOFF 第 7 节"会话结束前 AI 必做"应明确"第 2 节只保留最新状态，历史归档"。

**P1-3：无独立架构文档，新贡献者/AI 上手成本高**

- **现状**：
  - 无 `docs/architecture.md` / `ARCHITECTURE.md`
  - 无数据流图（识别→PostProcessor→CalibratedNutritionCalculator→calibration_page→meal_log 这条核心链路只在 HANDOFF 第 3.5 节文字描述）
  - 无独立数据库 schema 文档（8 张表的关系只在 `lib/data/database/tables/*.dart` 代码 + HANDOFF 散落描述）
  - `drift_schemas/eatwise_database/drift_schema_v1.json` 是 v1 快照，当前 schemaVersion 已 v5（v2 特殊人群 / v3 recommendation_feedbacks / v4 ? / v5 weight_log 加 impedance+bodyFatPct），快照未同步
- **影响**：架构信息散落在 HANDOFF 第 3 节（3.1–3.16）+ 第 6 节文件地图 + 各 specs 文档，无统一入口。新 AI 会话需读 HANDOFF 2300+ 行第 2 节 + 第 3 节才能拼出架构全貌。
- **现状 mitigations**：HANDOFF 第 6 节"文件地图"已是简化版架构概览（关键文件一行注释）；specs/2026-07-01-eatwise-design.md 是最初设计文档
- **建议**：抽离 `docs/architecture.md`，包含：①分层架构图（ai/core/data/features）②核心数据流（识别三路径 + 离线回补 + AI 兜底）③数据库 schema（8 表 + 关系 + schemaVersion 演进）④关键约束速查。同步 `drift_schemas/` 到 v5。

**P1-4：commit message 规范执行不严，33 次无信息提交**

- **位置**：`git log --oneline --all | grep -c "了解项目进展"` = 33 次
- **样本**：`b140745 feat: 了解项目进展`（当前 HEAD）、`923345c feat: 了解项目进展`、`34a02b6 feat: 了解项目进展`、`0e80bf6 feat: 了解项目进展`、`562abed feat: 了解项目进展`、`aca62db feat: 了解项目进展`
- **现状**：项目主流遵循 Conventional Commits（`feat(bl):` `fix(audit):` `chore(M27):` `test(M27):` `docs:` `perf:` 等），但"了解项目进展"这类提交是 AI 会话开启时探查性质的空 message，信息量为零
- **早期非规范样本**：`06f0c3f v0.28.0: AI 组分滑块...`、`b5d0019 v0.27.0: AI 推理热量...`、`808ea10 M26 E: 修复...`、`37d2b17 M26 A: 修复...`（用版本号/里程碑号作 type，不符合 Conventional Commits）
- **影响**：①`git log` / `git blame` / release notes 自动生成失效；②33 次空提交稀释历史，定位真实功能 commit 成本高；③违反项目"代码风格"隐含的专业性
- **建议**：①AI 会话开启探查阶段不要 commit，探查完再带真实 message 提交；②补 `CONTRIBUTING.md` 或在 HANDOFF 第 5 节"常用命令"加 commit message 规范（type(scope): description，type ∈ feat/fix/chore/test/docs/perf/refactor/build/ci/revert）；③历史空提交不追溯（个人项目可接受），但新增必须规范。

### P2（改进建议）

**P2-1：`.trae/specs/` 与 `docs/superpowers/specs/` 双轨，迁移未完成**

- **现状**：
  - `.trae/specs/`：M16.4 / M16.6 / M16-4 / M23 / M24 / M26 时期 spec（spec.md + tasks.md + checklist.md 三件套）
  - `docs/superpowers/specs/`：M25 起的设计文档（2026-07-01 起按日期命名）
  - `.trae/documents/`：UI 审查报告 + M16.9/M17/M18/M19/M20/M21/M22 里程碑总结 + 重构文档
- **问题**：三处职能重叠（都是设计/决策文档），命名风格不一（`.trae/specs/` 按里程碑主题，`docs/superpowers/specs/` 按日期），新 AI 不确定去哪找最新设计文档
- **现状 mitigations**：M25 之后新文档统一进 `docs/superpowers/`，迁移方向正确；`.trae/` 下的是历史归档
- **建议**：①在 `docs/` 加 `INDEX.md` 索引三处文档来源；或 ②把 `.trae/specs/` + `.trae/documents/` 的历史文档迁入 `docs/superpowers/archive/`，统一命名

**P2-2：M23 审计报告基线 v0.21.0 已过期 12 版，未标注时效性**

- **位置**：`docs/audit/m23-comprehensive-audit-report.md` + `m23-dim1-ui.md` / `m23-dim2-functional.md` / `m23-dim3-quality.md` / `m23-dim4-security.md`
- **现状**：基线 commit `13701c5`，应用版本 v0.21.0+33（2026-07-05），当前已 v0.33.0+46（2026-07-08），过了 12 个版本（M24–M27）
- **影响**：M23 报告里 67 条 P0/P1/P2 发现可能已在 M24（fix-m23-p1-audit-findings）/M26（fix-ui-audit-p1-round2）修复，新读者误以为这些问题仍在
- **现状 mitigations**：D5 报告头部已写"对照 M23 既有审计核对历史发现闭环情况"，说明 D 系列审计已在做闭环核对
- **建议**：在 M23 报告头部加"⚠️ 本报告基线 v0.21.0，部分发现已在 M24/M26 修复，请对照 D1–D9 系列报告确认现状"横幅；或归档至 `docs/audit/archive/`

**P2-3：`drift_schemas/` schema 快照停留在 v1，未随 schemaVersion 演进同步**

- **位置**：`drift_schemas/eatwise_database/drift_schema_v1.json`
- **现状**：当前 schemaVersion = 5（v2 特殊人群 / v3 recommendation_feedbacks / v5 weight_log 加 impedance+bodyFatPct），但快照只有 v1
- **影响**：drift schema 快照用于迁移验证 / 跨版本兼容测试，停留在 v1 无法覆盖 v2–v5 的迁移路径回归
- **建议**：跑 `dart run drift_dev schema dump <db.dart> drift_schemas/` 生成 v2–v5 快照；纳入 CI 校验

**P2-4：README 截图"待补"自项目起未补**

- **位置**：`README.md:19–25` "截图待补（真机采集后放 `docs/screenshots/`）"+ 三列 `_待补_`
- **现状**：`docs/` 下无 `screenshots/` 目录
- **影响**：对外发布页无截图，用户无法预览 app 长什么样
- **现状 mitigations**：个人自用项目，无截图不影响功能；GitHub Release body 有完整 changelog
- **建议**：低优先级，真机采集 3 张关键页（识别 / Dashboard / Insight）放 `docs/screenshots/`

**P2-5：CHANGELOG.md `[Unreleased]` 段为空，发版后未清理**

- **位置**：`CHANGELOG.md:5` `## [Unreleased]`（空行）
- **现状**：v0.33.0 已发版（tag `v0.33.0` 指向 `bb30873`），`[Unreleased]` 段无内容
- **影响**：符合 Keep a Changelog 规范（发版后 Unreleased 清空待下次填充），非问题；但当前 HEAD `b140745` 有 `d36b3b0 fix(audit): 修复 P0 批检查发现的 3 个 P1 bug` 未记入任何版本段
- **建议**：把 `d36b3b0` 的 audit fix 记入 `[Unreleased]`，下次发版归入新版本段

**P2-6：无 `CONTRIBUTING.md`，commit message / 分支 / 文档规范散落**

- **现状**：commit 规范在 HANDOFF 第 5 节"常用命令"未提；硬约束在 HANDOFF 第 1 节 + 项目规则 + README 三处；文档组织规则无明文
- **影响**：新 AI / 新贡献者需读 HANDOFF 全文 + 项目规则才能拼出规范
- **建议**：个人项目可不建 `CONTRIBUTING.md`，但建议在 HANDOFF 第 5 节加"commit message 规范"一行（type(scope): description）

**P2-7：文档注释覆盖率统计（FYI，非问题）**

- **统计**：`lib/` 104 dart 文件，89 个含 `///` 文档注释（85.6%），共 510 处，平均 4.9 处/文件
- **高密度文件**（≥10 处）：`m3_widgets.dart`（72）、`calibrated_nutrition_calculator.dart`（24）、`recommendation_service.dart`（22）、`meal_edit_dialog.dart`（20）、`mi_scale_parser.dart`（14）、`version_comparator.dart`（13）、`recognize_progress_card.dart`（12）、`circuit_breaker.dart`（11）、`nutrition_preview.dart`（11）、`mi_scale_scanner.dart`（11）、`user_preference_learner.dart`（10）
- **零注释文件**（15 个）：多为简单 UI 页或已废弃文件，如 `lib/app.dart`、`lib/ai/food_density.dart` 部分、部分 `features/*/` 简单页
- **语言一致性**：✅ 全部中文，与项目规则"注释用中文"一致
- **建议**：公共 API（repository / provider / 工具类）优先补 `///`；UI 页面可不强求。当前覆盖率对个人项目已属良好，非优先改进项。

---

## 维度结论

| 维度 | 评级 | 一句话结论 |
|------|------|-----------|
| HANDOFF.md | B | 第 3–7 节优秀，第 1 节 HEAD/tag 过时，第 2 节堆积成日志 |
| README.md | D | P0 级 minSdk 误导 + 全文停留在 v0.24.0，急需刷新 |
| CHANGELOG.md | A | 规范、完整、及时，个人项目标杆 |
| 代码注释 | B+ | 覆盖率 85.6%，语言统一，核心算法注释到位 |
| 文档组织 | B- | docs/ 清晰，但 .trae/ 三处重叠 + M23 报告过期未标 |
| 架构文档 | C | 无独立文档，散落 HANDOFF，schema 快照过期 |
| 决策记录 | B | 无 ADR 目录，HANDOFF 第 3 节 + specs 替代，深度够但无索引 |
| 提交信息 | C+ | 主流规范，但 33 次空提交 + 早期非规范前缀 |

**整体**：B−（个人项目语境下）。核心问题是 README 过时（P0）和 HANDOFF 第 2 节堆积（P1），这两项修复后可达 B+。架构文档缺失对个人自用项目可接受（信息都在 HANDOFF），但若未来开放贡献或交接需补。

---

## 修复优先级建议

1. **P0-1**（立即）：README minSdk 26→31 + Android 8.0→12.0 + 版本 badge/演进表/硬约束数刷新
2. **P1-1**（下次会话）：HANDOFF 第 1 节 HEAD/tag 三要素更新到 `b140745` / `v0.33.0→bb30873`
3. **P1-2**（近期）：HANDOFF 第 2 节瘦身，历史里程碑迁出
4. **P1-4**（持续）：commit message 规范化，停止 `feat: 了解项目进展` 空提交
5. **P1-3 / P2-3**（中期）：抽离 architecture.md + 同步 drift_schemas 到 v5
6. **P2-1 / P2-2**（低优先）：文档目录统一 + M23 报告标注时效

---

## 检查覆盖说明

- ✅ HANDOFF.md：Read 前 200 行（第 0–2 节顶部）+ Grep `^## ` 全部 22 个章节定位 + Read 第 3 节（2357–2515）+ 第 4 节（2595–2694）+ 第 5/6/7 节（2696–2776）
- ✅ README.md：Read 全 180 行
- ✅ CHANGELOG.md：Read 前 120 行（v0.33.0→v0.30.0 段，格式样本充分）
- ✅ 代码注释：Grep `^/// ` 全 lib/ 计数（89 文件 510 处）+ Grep `^/// ` head_limit=5 抽样
- ✅ docs/ 目录：LS 全列 + LS `.trae/specs/` + LS `.trae/documents/`
- ✅ 架构/schema：`find -iname "*architect*" -o -iname "*schema*" -o -iname "*adr*"` 确认无独立文档 + 检查 `drift_schemas/`
- ✅ commit message：`git log --oneline -30` + `git log --oneline -60 | awk` 类型统计 + `grep -c "了解项目进展"` 全分支计数 + 非规范前缀过滤
- ✅ 实际 minSdk：Read `android/app/build.gradle.kts` Grep `minSdk|abiFilters|isMinifyEnabled` 确认 = 31
- ✅ 实际版本：Read `pubspec.yaml:4` 确认 `version: 0.33.0+46`
- ✅ git 状态：`git status` + `git branch -vv` + `git tag` + `git rev-list -n 1 v0.33.0` 确认 tag 指向
