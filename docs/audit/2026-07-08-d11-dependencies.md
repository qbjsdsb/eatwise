# D11 依赖维度检查报告

**检查日期**：2026-07-08
**检查范围**：EatWise v0.33.0+46
**HEAD commit**：`b140745`（`feat: 了解项目进展`）
**git status**：lib/ 无改动；仅 `docs/audit/` 下存在其它维度未跟踪报告
**检查方法**：通读 `pubspec.yaml`（dependencies / dev_dependencies / dependency_overrides）+ 通读 `pubspec.lock`（实际锁定版本与 transitive 依赖）+ Grep 检查每个直接依赖在 `lib/` 与 `test/` 中的 `import 'package:...'` 实际引用情况 + pub.dev/changelog 查最新版本与已知漏洞

> 方法论备注：依赖"是否被使用"以 Grep `import 'package:<dep>/` 在 `lib/` 与 `test/` 中的命中为准，并对可疑结果（如 `uuid`）追加 `Uuid(` 符号调用复核。版本"是否过时"以 pub.dev 公开 changelog / versions 页面为准（2026-07-08 检索）。安全漏洞以 NVD / GitHub Security Advisories 检索为准。

## 总体评价

EatWise 的依赖管理**整体健康**，明显优于同类个人项目平均水平。依赖来源干净（全部来自 pub.dev，无 git/path 依赖，无未签名私有源）；版本约束统一采用 `^x.x.x` caret 形式（既允许补丁/次版本更新又限制 major 破坏性变更）；`dependency_overrides` 只有一项（`sqlparser: 0.44.5`）且附详细注释说明原因与退出条件；未发现 P0 级安全漏洞。存在的主要不足是**一个完全未使用的直接依赖（`uuid`）**、**一个可降级为 transitive 的显式声明（`sqlite3`）**、以及若干**注释与实际 lock 不一致的维护性问题**，均为 P2 级。

## 依赖清单概览

| 类别 | 数量 | 说明 |
|------|------|------|
| 直接依赖（dependencies） | 21 个（含 flutter SDK） | 全部来自 pub.dev，无 git/path |
| dev_dependencies | 6 个（含 flutter_test/flutter SDK） | 含 build_runner / drift_dev 代码生成 + mocktail 测试 |
| dependency_overrides | 1 个 | `sqlparser: 0.44.5`（已注释原因） |
| pubspec.lock 总包数 | 约 170 个 | 含大量 transitive 平台 federated 实现包 |
| 锁定 Dart SDK | `>=3.12.0 <4.0.0` | pubspec.yaml 声明 `^3.10.0`（见 P2-4） |
| 锁定 Flutter SDK | `>=3.44.0` | HANDOFF 记录实际用 Flutter 3.44.4 |

## 检查项与结果

| # | 检查项 | 结论 | 关键证据 |
|---|--------|------|---------|
| 1 | 依赖版本：漏洞/过时/SDK 兼容 | ✅ 良好 | 无已知 SDK 客户端漏洞（sentry CVE 均为服务端）；drift 2.34.1 / sentry_flutter 9.24.0 / openai_dart 7.0.1 均为最新或接近最新；Dart/Flutter SDK 兼容 |
| 2 | 依赖冗余：未使用/功能重叠 | ⚠️ 1 个未使用 | `uuid` 包在 `lib/` 与 `test/` 零引用、零 `Uuid(` 调用；`http` 与 `openai_dart` 不重叠（http 用于 OFF API/APK 下载/GitHub Release，openai_dart 用于 AI 大模型） |
| 3 | 依赖来源：pub.dev / git / overrides | ✅ 优秀 | 全部 hosted（pub.flutter-io.cn 镜像），0 git 依赖，0 path 依赖；唯一 override（sqlparser）有详细注释与退出条件 |
| 4 | 版本约束：过宽/过严 | ✅ 良好 | 全部 `^x.x.x` caret 形式，无 `==` 过严约束；`flutter_riverpod: ^3.3.1` 注释过时但约束本身正确（已锁 3.3.2） |
| 5 | 本地 vs 依赖：可被标准包替代的自实现 | ✅ 良好 | `apk_installer.dart` 用 MethodChannel 自实现 APK 安装（合理，避免额外依赖）；隐私政策 rootBundle 内嵌展示（无需 url_launcher）；无手动 URL 打开/分享等可替代逻辑 |
| 6 | 平台兼容性：Android 支持 | ✅ 良好 | 所有 21 个直接依赖均支持 Android；transitive 含 linux/macos/windows/web 平台包系 federated 插件机制固有，不影响 APK |
| 7 | 包大小：APK 体积影响 | ℹ️ 已优化 | HANDOFF 记录 v0.30.1 已用 `abiFilters arm64-v8a` 瘦身 87→42.3MB（-51%）；大依赖：sentry_flutter（含 sentry-native C++）、image（纯 Dart 图像库）、openai_dart、fl_chart、drift |

## 发现的问题

### P0（严重 / 安全漏洞）

无。本次检查未发现影响 EatWise 的已知安全漏洞。

**关于 Sentry 相关 CVE 的说明**：检索到 `CVE-2026-27197`（CVSS 9.1，SAML SSO 账户接管）、`CVE-2026-26004`（IDOR）、`CVE-2025-22146` 等多个 Sentry 漏洞。这些**全部是 Sentry 服务端（self-hosted Sentry 服务器）漏洞**，影响的是部署 Sentry 服务后端的组织，**不影响 `sentry_flutter` SDK 客户端**。EatWise 作为客户端 app 使用 `sentry_flutter` 9.24.0 向 sentry.io 上报错误，不受这些 CVE 影响。

### P1（高优先级）

无。本次检查未发现过时致功能受损或有已知 bug 的依赖。

### P2（中低优先级 / 维护建议）

**P2-1：`uuid` 包完全未使用，应移除**

- **位置**：`pubspec.yaml:46` `uuid: ^4.5.0`
- **证据**：
  - `lib/` 中 `import 'package:uuid/`：0 处命中（Grep `files_with_matches`）
  - `test/` 中 `import 'package:uuid/` 与 `Uuid(`：0 处命中
  - 全仓 `Uuid(` 符号调用：0 处（仅有 bluetooth 模块的 BLE `UUID`/`Guid` 字样与 sentry_scrub 注释提及"UUID 去横线"，均与 `uuid` 包无关）
  - `pubspec.lock:1200-1207` 锁定 `uuid 4.5.3`（direct main）
- **影响**：无功能影响，但属于死依赖，增加 `pub get` 下载量与依赖树复杂度；误导后续维护者以为项目用 uuid 生成 ID。
- **现状**：项目 ID 由 drift 自增主键 + 数据库层生成，不需要 uuid。
- **建议**：从 `pubspec.yaml` 移除 `uuid: ^4.5.0`，跑 `flutter pub get` 更新 lock。

**P2-2：`sqlite3` 包显式声明但 `lib/` 无直接 import，可降级为 transitive**

- **位置**：`pubspec.yaml:15` `sqlite3: ^3.3.2`
- **证据**：
  - `lib/` 中 `import 'package:sqlite3/`：0 处命中
  - 仅 `docs/superpowers/plans/2026-07-01-sprint1-core-recognition.md:532` 设计文档中提及
  - `lib/data/database/connection.dart` 用 `package:drift/native.dart`（其内部 transitive 依赖 sqlite3），不直接 import sqlite3
  - `pubspec.lock:1104-1111` 锁定 `sqlite3 3.3.4`（direct main）
- **上下文**：pubspec.yaml 注释"drift 2.32+ + sqlite3mc 加密"已过时——`connection.dart:10-14` 注释明确"移除 sqlite3mc 加密避免 native 库兼容问题，个人自用 app 加密是过度设计"。sqlite3mc 相关代码已移除，sqlite3 现仅作 drift 的 transitive 依赖。
- **影响**：无功能影响；显式声明的唯一好处是可控制版本上限，但 drift 会自行约束 sqlite3 版本范围，显式声明属于冗余。
- **建议**：可从 `pubspec.yaml` 移除 `sqlite3: ^3.3.2`（drift 会以 transitive 拉入）。若希望保留版本控制权也可保留，但应更新注释说明"drift transitive，显式声明仅为锁版本上限"。优先级低于 P2-1。

**P2-3：`flutter_riverpod` pubspec 注释过时（3.3.2 已是稳定版）**

- **位置**：`pubspec.yaml:23` `flutter_riverpod: ^3.3.1  # 3.3.2 仅为 3.3.2-dev.2 prerelease，最新稳定版是 3.3.1（pub.dev 已核实）`
- **证据**：
  - pub.dev：`flutter_riverpod 3.3.2` 于 2026-06-10 作为**稳定版**发布（fixes assertion error when invalidating a provider after autoDispose disposal）
  - `pubspec.lock:465-472` 已锁定 `3.3.2`（因 `^3.3.1` 允许 3.3.2）
- **影响**：无功能影响（lock 已是 3.3.2）；但注释误导后续维护者，可能致其在升级时误判版本状态。
- **建议**：更新注释为"3.3.2 已稳定（2026-06-10），含 autoDispose provider 失效后 invalidate 的 assertion 修复"。

**P2-4：Dart SDK 约束 `^3.10.0` 与实际所需 `>=3.12.0` 不一致**

- **位置**：`pubspec.yaml:7` `sdk: ^3.10.0  # drift 2.34.0 要求 Min Dart SDK 3.10（pub.dev 已核实）`
- **证据**：
  - `pubspec.lock:1329` `sdks.dart: ">=3.12.0 <4.0.0"`（实际被依赖提升至 3.12）
  - `pubspec.lock:1330` `sdks.flutter: ">=3.44.0"`
- **影响**：无运行时影响（`^3.10.0` 允许 3.12，pub get 时自动提升）；但在 Dart 3.10/3.11 环境下 `pub get` 会因 transitive 依赖要求 3.12 而失败，约束声明过宽，与实际不符。
- **建议**：将 `sdk: ^3.10.0` 更新为 `sdk: ^3.12.0` 以反映真实下限，避免在低版本 SDK 环境下产生难以理解的求解失败。同步更新注释。

**P2-5：`sqlparser 0.44.5` override + `drift_dev` 锁 2.34.0 为已知技术债**

- **位置**：`pubspec.yaml:67` `drift_dev: ^2.34.0`、`pubspec.yaml:76-80` `dependency_overrides: sqlparser: 0.44.5`、`pubspec.lock:244-251` drift_dev 2.34.0、`pubspec.lock:1112-1119` sqlparser 0.44.5（direct overridden）
- **原因（pubspec 注释 + HANDOFF 已详述）**：
  - sqlparser 0.44.6 误发 breaking change（移除 `DartPlaceholder.when`，本应 major 却发成 patch）→ drift_dev 2.34.0 build_runner 失败
  - 0.45.0 是 re-release（同样 breaking）→ drift_dev 2.34.2+1 升级到 `^0.45.0` 但需 analyzer 13，与 flutter_test SDK pin 的 test_api 0.7.11 + test 包 `analyzer <13.0.0` 约束冲突 → 版本求解失败
  - 临时方案：保持 drift_dev 2.34.0 + override sqlparser 0.44.5（0.44.6 前的稳定版）
- **当前状态**：
  - drift_dev 最新 2.34.1+1（"Require analyzer version 13"）—— 仍受同一 analyzer pin 冲突限制，无法升级
  - drift 最新 2.34.1（runtime，已由 `^2.34.0` 自动锁到 2.34.1，无冲突）
  - override 注释明确"等 Flutter SDK 更新 test_api pin 后可移除"
- **影响**：无功能影响（build_runner 已跑通 457 outputs，1172 测试通过）；属于上游 SDK 协调问题的临时绕行，需长期关注 Flutter SDK 更新。
- **建议**：定期检查 Flutter SDK 是否更新 test_api pin（解除 analyzer <13 约束）；一旦解除，移除 override 并升级 drift_dev 至 2.34.1+1。当前无需行动。

**P2-6：transitive 平台 federated 包对 Android-only 项目冗余（机制固有，无法移除）**

- **现象**：`pubspec.lock` 含大量非 Android 平台实现包，如 `flutter_blue_plus_darwin/linux/web/winrt`、`flutter_secure_storage_darwin/linux/web/windows`、`flutter_image_compress_macos/ohos/web`、`image_picker_ios/linux/macos/windows`、`path_provider_foundation/linux/windows`、`permission_handler_apple/html/windows`、`workmanager_apple`、`file_selector_*`、`bluez`、`xdg_directories`、`win32` 等。
- **原因**：Flutter federated 插件机制——平台插件声明所有平台实现为 transitive 依赖，`pub get` 会全部拉入。
- **影响**：增加 `pub get` 下载量与磁盘占用，但**不影响最终 APK 体积**（Flutter 构建时 tree-shaking 只打包 Android 平台代码 + Android native 库）。
- **建议**：无需处理，属生态机制。若关注 `pub get` 速度，可考虑用 dependency_overrides 排除特定平台实现，但收益极低、风险高（可能破坏插件解析），不建议。

## 维护建议汇总

| 优先级 | 建议 | 工作量 |
|--------|------|--------|
| P2-1 | 移除未使用的 `uuid` 依赖 | 1 行删除 + pub get |
| P2-3 | 更新 `flutter_riverpod` 注释（3.3.2 已稳定） | 注释修改 |
| P2-4 | Dart SDK 约束 `^3.10.0` → `^3.12.0` + 更新注释 | 1 行 + 注释 |
| P2-2 | 可选：移除 `sqlite3` 显式声明（drift transitive 已覆盖） | 1 行删除 + pub get |
| P2-5 | 持续关注 Flutter SDK 更新 test_api pin 以解除 sqlparser override | 被动等待 |

## 依赖来源与约束统计

- **来源**：170 个包全部 `source: hosted`，URL 均为 `https://pub.flutter-io.cn`（pub.dev 中国镜像），无 `git` / `path` / `sdk`（除 flutter/flutter_test/flutter_web_plugins/sky_engine 5 个 SDK 包）
- **约束形式**：直接依赖全部 `^x.x.x` caret（允许补丁+次版本，限制 major），无 `any`（过宽）/ `==`（过严）；唯一精确版本是 `dependency_overrides: sqlparser: 0.44.5`（override 必须精确，合理）
- **版本新鲜度**（2026-07-08 检索 pub.dev）：
  - `drift 2.34.1`（最新 2.34.1）✅
  - `flutter_riverpod 3.3.2`（最新 3.3.2）✅
  - `sentry_flutter 9.24.0`（最新 ≥9.23.0，lock 已超搜索缓存）✅
  - `openai_dart 7.0.1`（最新 7.0.0/7.0.1，7.0.0 有 breaking 但仅影响 MCP serverUrl 读取，项目用视觉识别不涉及）✅
  - `go_router 17.3.0`、`fl_chart 0.70.2`、`connectivity_plus 6.1.5`、`http 1.6.0` 等均在新近版本 ✅

## 平台兼容性

- **唯一目标平台**：Android（HANDOFF 与 project rules 确认，minSdk=31）
- **直接依赖 Android 支持**：21/21 全部支持 Android ✅
- **关键 native 依赖**：
  - `drift` → `NativeDatabase` 通过 FFI 调系统 `libsqlite3.so`（Android 自带）
  - `sentry_flutter` → 含 sentry-native C++ 库（APK 体积主要贡献者之一）
  - `flutter_blue_plus` → BLE 扫描（Android Bluetooth LE API）
  - `workmanager` → Android WorkManager（后台兜底，受 R8 反射类保留约束，见硬约束 #1）
  - `flutter_image_compress` → Android native 图片压缩

## 结论

EatWise 依赖维度无 P0/P1 问题，可安全继续开发。建议优先处理 P2-1（移除 `uuid` 死依赖）与 P2-3/P2-4（注释/SDK 约束对齐），均为低风险一行修改。P2-5（sqlparser override）属上游协调问题，保持现状并定期关注 Flutter SDK 更新即可。

---

**检查工具**：Read（pubspec.yaml / pubspec.lock / connection.dart / image_quality_checker.dart / off_provider.dart）、Grep（import 引用核查）、WebSearch（pub.dev 版本与 CVE 检索）、RunCommand（git log/status）
