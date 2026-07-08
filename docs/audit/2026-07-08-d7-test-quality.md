# D7 测试质量检查报告

**检查日期**：2026-07-08
**检查范围**：EatWise v0.33.0+46（1172 passed, 3 skipped, 0 failed）
**检查方法**：静态扫描 `test/` 目录（114 个测试文件）+ 抽样精读 8 个核心测试文件 + 覆盖率交叉比对 `lib/`
**沙箱基线**：drift `NativeDatabase.memory()` 内存数据库 + Fake VisionProvider，无真机/模拟器

---

## 测试概览

| 指标 | 数值 | 说明 |
|------|------|------|
| 测试文件数 | 114 | `test/**/*.dart` |
| 通过 | 1172 | HANDOFF.md 基线 |
| 跳过 | 3 | 全部在 `test/smoke/`，条件跳过（缺 API key / 图片） |
| 失败 | 0 | — |
| 测试目录 | `ai/` `background/` `core/` `data/` `features/` `nutrition/` `integration/` `smoke/` `widgets/` `fixtures/` | 镜像 `lib/` 主要分层 |
| 测试框架 | flutter_test + mocktail ^1.0.0 | mocktail 仅 10 文件使用，其余手写 Fake |
| DB 隔离 | `NativeDatabase.memory()` + `tearDown(db.close())` | 53 文件含 tearDown，模式一致 |

### 测试分布（按目录，`test(`/`testWidgets(` 调用数近似）

| 目录 | 文件数 | 测试密度 |
|------|--------|----------|
| `test/features/` | 66 | 最高（核心业务逻辑） |
| `test/data/` | 16 | 高（仓储层 + 备份导入导出） |
| `test/core/` | 14 | 中（更新/校验/配置） |
| `test/ai/` | 12 | 中（视觉 Provider + 营养查库） |
| `test/nutrition/` | 9 | 中（TDEE/体脂/推荐） |
| `test/integration/` | 2 | sprint1/sprint2 e2e（Fake Provider） |
| `test/smoke/` | 3 | 真实 API 冒烟（条件跳过） |
| 其他（根目录/widgets/background） | 8 | 杂项 |

---

## 检查项与结果

| # | 检查项 | 结果 | 证据 |
|---|--------|------|------|
| 1 | 核心模块测试覆盖率 | 🟡 基本覆盖，存在缺口 | 6 个清单模块均有测试；`recognize_controller` 核心流程仅构造器验证；3 个 lib 模块零测试（见下） |
| 2 | 测试隔离（setUp/tearDown） | 🟢 良好 | 53 文件 tearDown 一致用 `db.close()`；circuit_breaker 用可注入 Map + fake 时钟；smoke 用 `addTearDown(db.close)`；未见跨测试状态泄漏 |
| 3 | 测试命名 | 🟡 清晰但不统一 | 行为描述清晰（中文 + 场景前缀如 `v2:`/`M16.6:`/`T36:`），但混用 should-when / 描述式 / 场景编号三种风格 |
| 4 | 测试质量（断言/mock） | 🟢 整体高，局部弱 | 0 处 `expect(true,true)` 无意义断言；Fake 优于 mocktail（符合 Effective Dart）；body_fat_calculator 4 个分支测试断言过弱 |
| 5 | skipped 测试合理性 | 🟢 合理，保留 | 3 个全部条件跳过（`canRun ? false : '需 API_KEY'`），环境就绪即跑，非 broken |
| 6 | 集成/端到端测试 | 🟡 部分覆盖 | `test/integration/` 2 个 sprint e2e（Fake + 内存 DB，覆盖 10 步全日流程）；**无 Flutter `integration_test/` 目录**，无真机 widget drive |
| 7 | 测试文件组织 | 🟡 基本镜像，有偏差 | `ai/core/data/features/nutrition/` 镜像良好；5 个文件散落 `test/` 根目录未归入子目录 |
| 8 | 边界条件测试 | 🟢 优秀 | 哨兵 `foodItemId=0/-1`、空数据、极值（impedance=0/2999、weightKg=0）、clamp（体脂 5/75）、长度错误、去重、未来日期污染均有专门测试 |

---

## 覆盖率缺口

### 清单 6 模块覆盖情况

| 模块 | 测试文件 | 测试数 | 评估 |
|------|----------|--------|------|
| `recognize_controller` | `test/features/recognize_controller_test.dart` | 17 | ⚠️ **核心流程未测**（见 P1-1） |
| `nutrition_calculator` | `test/features/nutrition_calculator_test.dart` | 19 | ✅ 充分（Mifflin/Katch/TDEE/目标热量/硬下限，公式手算注释） |
| `mi_scale_parser` | `test/mi_scale_parser_test.dart` | 17 | ✅ 优秀（v1+v2 协议、openScale 真实样本、长度/去重边界） |
| `body_fat_calculator` | `test/nutrition/body_fat_calculator_test.dart` | 14 | 🟡 夹具强、分支弱（见 P1-2） |
| `circuit_breaker` | `test/features/circuit_breaker_test.dart` | 12 | ✅ 优秀（可注入时钟、closed/open/halfOpen 全转换、跨实例持久化、429 不计失败） |
| `json_importer` | `test/data/backup/json_export_import_test.dart` + `json_importer_image_check_test.dart` | 7 | ✅ 充分（导出→导入 round-trip、schemaVersion 校验、外键完整、图片清理） |

### `lib/` 模块零测试或弱测试

| 模块 | 状态 | 原因/影响 |
|------|------|-----------|
| `lib/data/bluetooth/mi_scale_scanner.dart` | ❌ 零测试 | BLE 扫描依赖 `flutter_blue_plus` 平台插件 + 真实硬件，沙箱不可测。**Parser 已充分测试**，Scanner 是薄封装层，风险可控但应记录 |
| `lib/background/background_dispatcher.dart` | ❌ 无专属测试 | 仅在 `background_tasks_test.dart` 间接引用。WorkManager 调度入口未单测 |
| `lib/core/error/sentry_init.dart`（`initSentryAndRunApp`） | ❌ 零测试 | App 引导入口，硬约束 6 涉及（命名参数 `container:` + `app:`），但引导副作用难测 |
| `lib/core/widgets/m3_widgets.dart` | ❌ 零测试 | 通用 UI 组件，靠各 page testWidgets 间接覆盖 |
| `lib/main.dart` / `lib/main_shell.dart` | ⚠️ 弱覆盖 | 仅 `dashboard_drawer_test`/`image_cleanup_startup_test` 2 处引用 |
| `lib/app.dart` | ⚠️ 弱覆盖 | 仅 `app_dynamic_color_test` 1 处 |

### AI 兜底三路径覆盖（硬约束 3）

| 路径 | 测试文件 | 覆盖 |
|------|----------|------|
| `recognize_page`（单品） | `recognize_page_test.dart`（5）+ `plan_d_calibrate_removal_test.dart` | ✅ |
| `multi_dish_page`（主菜+附加菜） | `multi_dish_page_test.dart`（14）+ `calibrated_nutrition_calculator_test.dart`（21） | ✅ |
| `offline_queue_controller`（后台回补） | `offline_queue_test.dart`（17）+ `offline_queue_composite_test.dart`（8）+ `background_tasks_test.dart` | ✅ |

**三路径均覆盖，硬约束 3 满足。**

---

## 发现的问题

### P0（严重：核心功能无测试 + 有已知 bug）

**无。** 未发现"核心功能零测试且存在已知 bug"的情形。核心数据路径（meal_log 写库、外键、哨兵防御、AI 三路径）均有测试覆盖，且 HANDOFF 记录 0 回归。

### P1（高优先级：核心功能测试不足 / 应修复）

#### P1-1：`recognize_controller.pickAndRecognize` 核心流程零单测

**位置**：`test/features/recognize_controller_test.dart`

**现状**：17 个测试全部是构造器签名编译期验证 + 回调可调用性验证（`onOfflineEnqueueForTest`/`onL3FallbackForTest` 直接调用）。文件头注释明确承认：「沙箱 host test 无法完整跑 pickAndRecognize 流程」，完整流程标 `@Tags(['smoke'])` 待真机验证。

**未覆盖的核心逻辑**：
- 限流（`_lastRecognizeTime` 时间窗拒绝）
- 429 限流等待重试
- 非 retryable 异常 → L3 转手动回调路由
- retryable 异常 → 离线入队
- 断路器 open 时拒绝调用

**风险**：`recognize_controller` 是拍照识别的编排核心，限流/重试/降级路由逻辑全靠人工真机验证，回归风险高。`circuit_breaker` 已用可注入时钟 + Map storage 完美解耦，`recognize_controller` 同样可注入 `DateTime.now()` + Fake VisionProvider + Fake ImagePicker 接口来单测编排逻辑，当前未做。

**建议**：抽取 `pickAndRecognize` 的编排逻辑为纯函数或可注入依赖的方法，对限流/429/L3 路由/离线入队四个分支写单测（不依赖 ImagePicker 平台插件）。

#### P1-2：`body_fat_calculator` 分支测试断言过弱

**位置**：`test/nutrition/body_fat_calculator_test.dart` 行 87-114

**现状**：4 个性别/年龄/体重分支测试仅断言 `expect(bf, isNotNull)` 或 `expect(bf! > 0, true)`，未验证具体计算值。

**问题**：分支覆盖达 100% 但**断言无法捕获公式回归**——若 `lbmSub`/`coeff` 分支取错值导致体脂率偏差 10%，测试仍通过。对比同文件前 3 个 openScale 夹具测试用 `closeTo(23.32, 0.05)` 精确断言，标准不一致。

**建议**：为 4 个分支测试补 openScale 对照值或手算期望值，用 `closeTo(expected, tolerance)` 替代 `isNotNull`。

#### P1-3：无 Flutter `integration_test/` 真机/widget 端到端测试

**现状**：项目无 `integration_test/` 目录（Flutter 官方真机集成测试约定）。`test/integration/sprint1_e2e_test.dart`、`sprint2_e2e_test.dart` 实为**单元测试**（内存 DB + Fake VisionProvider，`flutter test` 运行），不验证真实 widget 渲染、平台插件、BLE 硬件、Sentry 上报。

**影响**：
- 关键用户流程（拍照→识别→校准→写库→看板刷新）的 widget 链路无自动化验证
- BLE 扫描（M27 新增）、应用内更新（APK 下载安装）、Sentry 初始化等平台能力零自动化覆盖
- `testWidgets` 散布在 66 个 features 测试中，但多为单页/单组件，无跨页导航端到端

**建议**：建立 `integration_test/` 目录，至少补 1-2 个核心流程（拍照识别全链路、备份导出导入）的真机集成测试，CI 中可选运行。

### P2（中低优先级：测试质量/组织改进）

#### P2-1：skipped 测试评估——全部合理，保留

3 个 skipped 测试全在 `test/smoke/`：
- `real_api_smoke_test.dart`（2 处 skip）：需 `QWEN_API_KEY` + `/tmp/apple.jpg`
- `glm_flash_smoke_test.dart`（1 处 skip）：需 `GLM_API_KEY`

均用 `skip: canRun ? false : '需 ...'` 条件跳过，**环境就绪即自动运行**，非 broken 测试。设计合理，**不应删除或强制修复**。建议在 CI 加一个带 secret 的 smoke job 让其定期真跑。

#### P2-2：测试命名风格不统一

混用三种风格：
- 描述式中文：`'连续 5 次失败 → open，拒绝调用'`
- should-when：`'foodItemId=0 抛 ArgumentError'`
- 场景编号前缀：`'v2: 查库命中 + AI 偏差大时...'`、`'M16.6: ...'`、`'T36：...'`

均清晰可读，但缺乏统一约定。建议确立一种主风格（推荐描述式中文，去掉里程碑编号前缀——里程碑号属于 git 历史信息，不应污染测试名）。

#### P2-3：5 个测试文件散落 `test/` 根目录，未镜像 `lib/` 结构

| 根目录文件 | 应归属 |
|------------|--------|
| `test/mi_scale_parser_test.dart` | `test/data/bluetooth/` |
| `test/app_dynamic_color_test.dart` | `test/core/` 或 `test/features/` |
| `test/android_update_assets_test.dart` | `test/core/` |
| `test/icon_assets_test.dart` | `test/core/` |

#### P2-4：mocktail 与手写 Fake 混用，无统一规范

10 文件用 mocktail（集中在 `core/update/`、`secure_config_store`），其余用手写 Fake（`_FakeVisionProvider implements VisionProvider`）。两者均合理（Fake 更适合复杂接口，mocktail 更适合简单 stub），但无项目级约定。建议在 `analysis_options.yaml` 或 CONTRIBUTING 中说明选择偏好（推荐：接口复杂用手写 Fake，简单一次性 stub 用 mocktail）。

#### P2-5：`mi_scale_scanner` / `background_dispatcher` / `sentry_init` 零测试

均为平台/引导层，沙箱难测。建议：
- `mi_scale_scanner`：补 mock `FlutterBluePlus` 的纯逻辑测试（扫描结果过滤、packet_id 去重、isClosed 守卫），不依赖真实 BLE
- `background_dispatcher`：补 WorkManager callback 路由的纯逻辑测试
- `sentry_init`：至少补命名参数签名编译期测试（硬约束 6 已要求 `container:` + `app:`）

---

## 改进建议

### 短期（低投入高收益）

1. **P1-2**：为 `body_fat_calculator` 4 个分支测试补精确期望值（30 分钟，直接用 openScale 计算器对照）
2. **P2-3**：移动 5 个根目录测试文件到对应子目录（10 分钟，需更新 import）
3. **P2-1**：CI 加 smoke job，配置 secret 让 3 个 skipped 测试定期真跑

### 中期（架构性）

4. **P1-1**：重构 `recognize_controller.pickAndRecognize`，将编排逻辑（限流/429/L3 路由/离线入队）与平台插件调用（ImagePicker/Compress）解耦，对编排逻辑补单测。参照 `circuit_breaker` 的可注入时钟 + storage 模式
5. **P1-3**：建立 `integration_test/` 目录，补拍照识别全链路 + 备份导出导入 2 个真机集成测试

### 长期（质量文化）

6. **P2-2**：确立测试命名规范，去掉里程碑编号前缀
7. **P2-4**：确立 mocktail vs Fake 选择指南
8. 引入覆盖率工具（`flutter test --coverage` + `lcov`），量化覆盖率缺口，将 P1-1/P2-5 纳入覆盖率门禁

---

## 总体评价

EatWise 测试体系**整体质量高**，体现为：
- ✅ 边界条件测试优秀（哨兵防御、空/极值/clamp/去重/未来日期污染均有专测）
- ✅ 数据隔离规范（内存 DB + tearDown close 一致）
- ✅ Fake 优先于 mock（符合 Effective Dart，VisionProvider/NutritionLookup 手写 Fake 可读性强）
- ✅ 真实夹具驱动（openScale BIA 双源验证、BLE 真实抓包样本）
- ✅ AI 兜底硬约束三路径全覆盖
- ✅ 0 无意义断言、0 TODO 测试债

主要短板集中在**编排层单测缺口**（P1-1，`recognize_controller` 核心流程靠真机验证）和**真机集成测试缺位**（P1-3）。skipped 测试处理得当，无需修复。无 P0 级问题。
