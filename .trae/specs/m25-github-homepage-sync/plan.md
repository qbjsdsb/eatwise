# M25 GitHub 仓库主页同步完善 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 GitHub 仓库主页（github.com/qbjsdsb/eatwise）与项目实际状态同步：合并 main、重写 README、创建 LICENSE + CHANGELOG.md、补全 Release v0.22.0 notes changelog、设置 About 卡片。

**Architecture:** 纯文档 + git 操作 + GitHub REST API（curl）。无代码改动，无测试。验证通过文件存在性 + API 返回值 + 链接有效性。

**Tech Stack:** Markdown / git / GitHub REST API (curl) / Bash

**前置状态：**
- 远端 main HEAD = `c7690bc`，trae/agent-wX1X6Q HEAD = `f797f71`（main 是 trae 祖先，可 ff 合并）
- Release v0.22.0 已发布（tag `d5b7483` + 2 APK 已上传），notes 仅 496 字符通用安装模板
- spec 文件：`/workspace/.trae/specs/m25-github-homepage-sync/spec.md`

---

### Task 1: 合并 main 分支

**Files:**
- 无文件改动，纯 git 操作

- [ ] **Step 1: 验证 main 是 trae/agent-wX1X6Q 祖先（可 ff 合并）**

Run:
```bash
git fetch origin main && git merge-base --is-ancestor origin/main trae/agent-wX1X6Q && echo "FF_OK" || echo "FF_FAIL"
```
Expected: `FF_OK`（main 是 trae 祖先）。若 `FF_FAIL`，停止并报告用户。

- [ ] **Step 2: 切换到 main + ff 合并 + push**

Run:
```bash
git checkout main && git merge --ff-only trae/agent-wX1X6Q && git push origin main
```
Expected: push 成功，无冲突。

- [ ] **Step 3: 验证 main HEAD = f797f71**

Run:
```bash
git log --oneline origin/main -1
```
Expected: `f797f71` 在输出中。

- [ ] **Step 4: 切回 trae 分支**

Run:
```bash
git checkout trae/agent-wX1X6Q
```
Expected: 切回 trae 分支（后续工作在此分支做）。

---

### Task 2: 创建 LICENSE 文件

**Files:**
- Create: `/workspace/LICENSE`

- [ ] **Step 1: 写 LICENSE 文件（MIT 标准文本，版权 qbjsdsb）**

Write to `/workspace/LICENSE`:

```
MIT License

Copyright (c) 2026 qbjsdsb

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: 验证文件存在 + 内容正确**

Run:
```bash
test -f /workspace/LICENSE && head -3 /workspace/LICENSE
```
Expected: 输出 `MIT License` + 空行 + `Copyright (c) 2026 qbjsdsb`

---

### Task 3: 创建 CHANGELOG.md

**Files:**
- Create: `/workspace/CHANGELOG.md`

- [ ] **Step 1: 写 CHANGELOG.md（Keep a Changelog 格式，16 个版本段）**

Write to `/workspace/CHANGELOG.md`：

```markdown
# Changelog

本项目所有重要变更记录。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

- M25 图标设计精修（进行中）
- GitHub 仓库主页同步完善

## [v0.22.0] - 2026-07-05

### M24：P1 清零（13 项 P1 修复 + 架构重构）
- **快速修复（8 项）**：Sentry tags 脱敏 / dashboard 触控目标 / update release notes 展开 / food_library 搜索 toast / backup 离线队列提示 / insight 周/月切换 loading / food_library + profile ErrorState
- **架构重构（5 项）**：跨层依赖 Provider 注入 / recognize_page _pickAndRecognize 190→23 行 / offline_queue_controller processPending 396→29 行 / multi_dish_page 986→542 行 / dashboard_page 940→304 行
- **验证**：flutter analyze No issues / flutter test 1032 passed / 6 硬约束满足 / 0 回归
- 代码健康度 B+ → A-

## [v0.21.0] - 2026-07-05

### M22：图标精修 + 识别等待动画重构
- 图标反转配色（紫底白前景 → 白底紫前景）+ 几何精修（描边 4→2.5dp / square→round cap / 范围 50→36dp / 碗剪影替代苹果圆 / 移除扫描线）
- 识别进度卡片 TweenAnimationBuilder 平滑插值 + AnimatedSwitcher 图标 morph + done 态弹性 scale-in
- 查库阶段最小展示 300ms + done 态成功停留 400ms

## [v0.20.1] - 2026-07-05

### M21：项目全面审查 + P0/P1 修复
- P0 修复：HANDOFF.md 第 1/2 节严重不同步
- P1 修复：补 glm_4v_provider + qwen_vl_provider isRefusalForTest 单测共 16 个
- 987 测试全过 + 6 硬约束全部通过 + M19/M20 无回归

## [v0.20.0] - 2026-07-05

### M20：Google Lens 风图标 + 识别思考流程 UI
- 图标重设计：紫橙渐变 + 圆角取景框 + 苹果剪影 + 扫描线
- 识别思考流程 UI：识别中显示 AI 思考步骤卡片
- 新增 10 个 widget 测试 + 更新 6 个图标测试

## [v0.19.1] - 2026-07-05

### M19：AI 推荐去重 + 菜名归一化 + 多样性
- AI 推荐结果去重（避免重复推荐同一菜品）
- 菜名归一化（统一不同写法）
- 推荐多样性增强
- 新增 35 个 TDD 测试

## [v0.19.0] - 2026-07-05

### M18：多菜场景 AI 推理可见性 + 三路径一致性
- 多菜场景展示 AI 推理过程
- 三路径（recognize_page / multi_dish_page / offline_queue_controller）行为一致性

## [v0.18.9] - 2026-07-05

### M17：App 图标重设计——M3 抽象几何
- M3 抽象几何图标（同心圆环 + 中心圆点）
- 紫橙双色渐变背景

## [v0.18.8] - 2026-07-05

### M16.9：减小库值重要性——AI 绝对优先
- 查库命中分支重写（AI 与库偏差 > 50% 用 AI 反算 per100g + 更新库）
- 复合菜残留路径修复

## [v0.18.6] - 2026-07-05

### M16.7：Web Interface Guidelines 全 UI 审查修复
- 17 文件 195 问题修复（按 Web Interface Guidelines 规范）

## [v0.18.5] - 2026-07-05

### M16.6：营养数值一致性修复
- 三路径 actualCalories 计算统一（recognize_page / multi_dish_page / offline_queue_controller）
- meal_log.actualCalories 与 food_item.caloriesPer100g 数据一致

## [v0.18.4] - 2026-07-05

### M16.5：bump + HANDOFF 回填

## [v0.18.3] - 2026-07-05

### M16.4：bump + HANDOFF 回填 + spec 文档归档

## [v0.18.1] - 2026-07-05

### M16.2：识别流程修复 6 个 P0/P1 问题
- 用户反馈"相册内识别经常出错"

## [v0.18.0] - 2026-07-04

### M16：应用内自更新
- MainActivity.kt 修复 call.arguments 类型转换（CI build failed）
- 严格 TDD 实现 13 个 Task

## [v0.16.0] - 2026-07-04

### M15：v5 AI 推荐审计修复 + 满意度反馈按钮优化

## [v0.15.0] - 2026-07-04

### M15：UI 优化 + 图标重设计
- 暖橙纯色图标（餐叉餐刀）
```

- [ ] **Step 2: 验证 CHANGELOG.md 含全部 16 个版本段**

Run:
```bash
grep -c "^## \[v0\." /workspace/CHANGELOG.md
```
Expected: `16`

- [ ] **Step 3: 验证 Unreleased 段存在**

Run:
```bash
grep -c "^## \[Unreleased\]" /workspace/CHANGELOG.md
```
Expected: `1`

---

### Task 4: 重写 README.md（完整产品级）

**Files:**
- Modify: `/workspace/README.md`（完全重写）

- [ ] **Step 1: 备份当前 README**

Run:
```bash
cp /workspace/README.md /workspace/README.md.bak-m24
```
Expected: 无输出（备份成功）。

- [ ] **Step 2: 写新 README.md（完整产品级，14 章节）**

Write to `/workspace/README.md`：

```markdown
# EatWise 慢慢吃

> 拍照识别食物热量 + 营养记录 + AI 周/月汇总建议 — Flutter Android App（个人自用）

![Version](https://img.shields.io/badge/version-v0.22.0-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.44.4-blue)
![Dart](https://img.shields.io/badge/Dart-3.x-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Android-green)
![Tests](https://img.shields.io/badge/tests-1032%20passed-brightgreen)

## 核心特性

- 📸 **AI 拍照识别**：拍一张食物照片，Qwen-VL / GLM-4V 自动识别菜名 + 估算份量
- 🥗 **本地食物库回填**：从《中国食物成分表》第6版查库回填营养素，单品误差 ±3-5%
- 📊 **AI 周/月汇总**：GLM-4-Flash 生成长期饮食建议，洞察趋势
- 🔒 **本地优先 + 隐私加密**：所有数据存本地 AES 加密 SQLite，无后端，EXIF 剥离

## 截图

> 截图待补（真机采集后放 `docs/screenshots/`）

| 识别 | Dashboard | Insight |
|---|---|---|
| _待补_ | _待补_ | _待补_ |

## 功能矩阵

| 模块 | 功能 |
|---|---|
| 识别 | 单品识别 + 多菜识别 + 离线队列回补（三路径一致性） |
| 营养 | 查库回填 + 品类校准 + 包装 OCR 优先 + AI 估算兜底 |
| 汇总 | 周报 + 月报（GLM-4-Flash）+ 满意度反馈 + 去重 + 多样性 |
| 体重 | 体重记录 + 趋势图 |
| 备份 | JSON 导出/导入 + 图片清理 + 自动备份 |
| 更新 | 应用内自更新（GitHub API + APK 下载 + 系统安装器） |
| 隐私 | AES 加密 / EXIF 剥离 / API key 不入库 / Sentry 脱敏 |

## 技术栈

| 层 | 选型 | 理由 |
|---|---|---|
| 框架 | Flutter 3.44.4 | 跨平台一套代码（实际仅 Android） |
| 本地数据库 | drift + sqlite3 build hooks (sqlite3mc, SQLite3MultipleCiphers) | AES 加密；sqlcipher_flutter_libs 已 EOL 故弃用 |
| 密钥存储 | flutter_secure_storage | Keychain / Keystore 平台原生 |
| 拍照 | image_picker | flutter.dev 一方包 |
| 图片预处理 | flutter_image_compress | 默认剥离 EXIF + 压缩 |
| 图表 | fl_chart | Material 风格图表 |
| 状态管理 | flutter_riverpod | 类型安全 + 可测 |
| 路由 | go_router | 声明式路由 |
| 视觉大模型 | Qwen-VL（首选）/ GLM-4V-Plus（备选） | 多模态识别 |
| 文本大模型 | GLM-4-Flash | 免费，周/月汇总 |
| 错误监控 | sentry_flutter | 脱敏后上报 |
| 中文食物库 | 《中国食物成分表》第6版（Sanotsu/china-food-composition-data） | 权威数据源 |
| 视觉规范 | Material 3 Expressive | 最新 Material 设计语言 |

## 目录结构

```
lib/
  main.dart
  app.dart
  core/                 # 通用工具、主题、错误处理、Sentry 脱敏
  data/
    database/           # drift 定义 + migrations/
    models/             # 数据模型
    repositories/       # 仓储层
  features/
    profile/            # 个人档案 + 热量目标
    recognize/          # 拍照识别（含 multi_dish/ 子目录 + offline_queue_controller）
    dashboard/          # 今日额度看板（含 dashboard/ 子目录）
    food_library/       # 食物库
    manual_entry/       # 手动录入兜底
    weight/             # 体重记录
    insight/            # 长期趋势 + AI 周/月汇总
    backup/             # 备份导入导出
    update/             # 应用内自更新
    me/                 # 个人中心
  ai/                   # vision_provider + nutrition_lookup + prompts
.trae/
  specs/                # 设计文档（按里程碑组织）
  design/               # 设计稿 + 图标候选
test/                   # 单测 + widget 测试
HANDOFF.md              # 项目交接文档（跨会话记忆）
CHANGELOG.md            # 版本变更记录
```

## 安装

### 下载 APK

前往 [Releases](https://github.com/qbjsdsb/eatwise/releases) 下载最新版 APK（优先 `app-release.apk`，闪退改装 `app-debug.apk`）。

### 系统要求

- Android 8.0+（minSdk 26）
- 约 75 MB 存储空间

### 真机安装步骤

1. 下载 `app-release.apk` 传到手机
2. 手机设置开启"允许安装未知来源应用"
3. **直接覆盖安装即可**（v0.18.0 起用固定 keystore 签名；v0.17.0 及之前需先卸载一次以切换签名）
4. 首次启动在「设置」页填入你的 Qwen API Key（视觉识别用）
5. 在「设置 → 检查更新」可一键升级到下一版

### 闪退排查

如果 `app-release.apk` 闪退，请改装 `app-debug.apk`：debug 版崩溃时会显示红色错误页 + 完整堆栈，截图发给开发者即可定位根因。

## 版本演进

| 版本 | 日期 | 核心改动 |
|---|---|---|
| v0.22.0 | 2026-07-05 | M24 P1 清零（13 项 P1 修复 + 5 项架构重构） |
| v0.21.0 | 2026-07-05 | M22 图标精修 + 识别等待动画重构 |
| v0.20.1 | 2026-07-05 | M21 项目全面审查 + P0/P1 修复 |
| v0.20.0 | 2026-07-05 | M20 Google Lens 风图标 + 识别思考流程 UI |
| v0.19.1 | 2026-07-05 | M19 AI 推荐去重 + 菜名归一化 + 多样性 |
| v0.19.0 | 2026-07-05 | M18 多菜场景 AI 推理可见性 + 三路径一致性 |
| v0.18.9 | 2026-07-05 | M17 App 图标重设计 M3 抽象几何 |
| v0.18.8 | 2026-07-05 | M16.9 AI 绝对优先（查库命中分支重写） |
| v0.18.6 | 2026-07-05 | M16.7 Web Interface Guidelines 全 UI 审查 |
| v0.18.5 | 2026-07-05 | M16.6 营养数值一致性修复 |
| v0.18.4 | 2026-07-05 | M16.5 bump + HANDOFF 回填 |
| v0.18.3 | 2026-07-05 | M16.4 bump + spec 归档 |
| v0.18.1 | 2026-07-05 | M16.2 识别流程修复 6 个 P0/P1 |
| v0.18.0 | 2026-07-04 | M16 应用内自更新（13 Task TDD） |
| v0.16.0 | 2026-07-04 | M15 v5 AI 推荐审计 + 满意度反馈 |
| v0.15.0 | 2026-07-04 | M15 UI 优化 + 图标重设计 |

完整变更见 [CHANGELOG.md](CHANGELOG.md)。

## 状态

✅ **v0.22.0 已发布**（2026-07-05）— [Release v0.22.0](https://github.com/qbjsdsb/eatwise/releases/tag/v0.22.0)

## 文档

- [HANDOFF.md](HANDOFF.md) — 项目交接文档（跨会话记忆载体，每个会话开始必读）
- [CHANGELOG.md](CHANGELOG.md) — 完整版本变更记录
- [.trae/specs/](.trae/specs/) — 设计文档目录（按里程碑组织）

## 安全与隐私

- **本地加密**：SQLite 数据库 AES 加密（sqlite3mc），密钥存 flutter_secure_storage
- **EXIF 剥离**：图片上传前自动剥离 EXIF 元数据
- **API key 不入库**：API key 存 flutter_secure_storage，不入数据库
- **Sentry 脱敏**：Sentry 上报前脱敏 extra + tags（M24 A1 修复）
- **无后端**：纯前端，无服务器，无云服务

## 开发

```bash
# 环境要求
Flutter 3.44.4 / Dart 3.x

# 静态分析
flutter analyze

# 测试（基线：1032 passed / 3 skipped / 0 failed）
flutter test
```

### 6 条硬约束（开发时必须遵守）

1. `android/app/build.gradle.kts` 必须保持 `isMinifyEnabled = false` + `isShrinkResources = false`
2. `meal_log.food_item_id` 是非空外键，哨兵 `foodItemId=0` 写库前必须替换为真实 id
3. AI 兜底三路径必须全部覆盖：`recognize_page` + `multi_dish_page` + `offline_queue_controller`
4. `per100g` 反算必须基于 `estimatedWeightGMid`（不能用 `servingG`）
5. `SecureConfigStore` 没有 `instance` 静态属性，用 `SecureConfigStore()` 或 `container.read(secureConfigStoreProvider)`
6. `initSentryAndRunApp` 参数是命名参数 `container:` + `app:`

详见 [HANDOFF.md](HANDOFF.md)。

## 许可证

[MIT](LICENSE)
```

- [ ] **Step 3: 验证 README 行数 > 100**

Run:
```bash
wc -l /workspace/README.md
```
Expected: 行数 > 100。

- [ ] **Step 4: 验证内部链接文件存在**

Run:
```bash
test -f /workspace/HANDOFF.md && test -f /workspace/CHANGELOG.md && test -f /workspace/LICENSE && test -d /workspace/.trae/specs && echo "LINKS_OK"
```
Expected: `LINKS_OK`（所有链接目标存在）。

- [ ] **Step 5: 删除备份**

Run:
```bash
rm /workspace/README.md.bak-m24
```
Expected: 无输出。

---

### Task 5: 修订 HANDOFF.md

**Files:**
- Modify: `/workspace/HANDOFF.md`（修 L74 main HEAD 描述 + 补 M25 段）

- [ ] **Step 1: 修 L74 main HEAD 描述**

Edit `/workspace/HANDOFF.md`：

old_string:
```
**当前分支**：trae/agent-wX1X6Q（本地 HEAD = M24 commit d5b7483；远端 origin/trae/agent-wX1X6Q HEAD = d5b7483；origin/main HEAD = b7955c5（v0.21.0，待合并 M24 到 main）；tag v0.21.0 → 13701c5，tag v0.22.0 → d5b7483；**M24 已 push + tag，下一步待用户决定是否合并到 main + GitHub Release**）
```

new_string:
```
**当前分支**：trae/agent-wX1X6Q（本地 HEAD = M25 docs commit；远端 origin/trae/agent-wX1X6Q HEAD = M25 docs commit；origin/main HEAD = f797f71（已合并 M24，ff 合并）；tag v0.21.0 → 13701c5，tag v0.22.0 → d5b7483；**M24 已合并到 main + Release v0.22.0 notes 已 PATCH 补 M24 changelog；M25 GitHub 主页同步完善进行中**）
```

- [ ] **Step 2: 在 M24 段后插入 M25 段**

Edit `/workspace/HANDOFF.md`：在第 2 节"M24 全部完成"段之后、下一个 "**M24 Task B5**" 段之前，插入：

```
**M25 GitHub 仓库主页同步完善（2026-07-05）**：已完成。M24 完成后 GitHub 仓库主页与项目实际状态严重脱节（README 仍写"设计阶段"、main 落后 trae 分支、Release notes 仅通用模板无 changelog、缺 LICENSE + CHANGELOG.md）。本次同步：
- 合并 trae/agent-wX1X6Q → main（ff 合并，main HEAD = f797f71）
- 重写 README.md（14 章节产品级：badges + 核心特性 + 功能矩阵 + 技术栈 13 行 + 目录结构 + 安装 + 版本演进表 16 行 + 安全隐私 + 6 硬约束 + 许可证）
- 创建 LICENSE（MIT，版权 qbjsdsb）
- 创建 CHANGELOG.md（Keep a Changelog 格式，16 个版本段 v0.15.0→v0.22.0 + Unreleased 段）
- PATCH Release v0.22.0 notes：补 M24 changelog 段（13 项修复 + 5 项重构 + 验证 + 升级须知）+ 保留原 4 段通用模板
- 设置 About 卡片 description + 12 个 topics
```

- [ ] **Step 3: 验证 HANDOFF 修订**

Run:
```bash
grep -c "M25 GitHub 仓库主页同步完善" /workspace/HANDOFF.md
```
Expected: `1`（M25 段已插入）。

Run:
```bash
grep -c "已合并 M24，ff 合并" /workspace/HANDOFF.md
```
Expected: `1`（L74 已修订）。

---

### Task 6: commit + push 文档批量

**Files:**
- Stage: `/workspace/README.md` `/workspace/LICENSE` `/workspace/CHANGELOG.md` `/workspace/HANDOFF.md` `/workspace/.trae/specs/m25-github-homepage-sync/`

- [ ] **Step 1: 暂存文件**

Run:
```bash
git add README.md LICENSE CHANGELOG.md HANDOFF.md .trae/specs/m25-github-homepage-sync/
```
Expected: 无输出。

- [ ] **Step 2: 验证暂存内容**

Run:
```bash
git status --short
```
Expected: 5 个文件 staged（README.md / LICENSE / CHANGELOG.md / HANDOFF.md / .trae/specs/m25-github-homepage-sync/）。

- [ ] **Step 3: commit**

Run:
```bash
git commit -m "$(cat <<'EOF'
docs: M25 GitHub 仓库主页同步完善

M24 完成后 GitHub 仓库主页与项目实际状态严重脱节，本次同步：
- 合并 trae/agent-wX1X6Q → main（ff 合并，main HEAD = f797f71）
- 重写 README.md（14 章节产品级：badges + 核心特性 + 功能矩阵 + 技术栈 + 目录结构 + 安装 + 版本演进表 + 安全隐私 + 6 硬约束）
- 创建 LICENSE（MIT，版权 qbjsdsb）
- 创建 CHANGELOG.md（Keep a Changelog 格式，16 个版本段 v0.15.0→v0.22.0）
- 修订 HANDOFF.md（修 L74 main HEAD + 补 M25 段）
EOF
)"
```
Expected: commit 成功。

- [ ] **Step 4: push**

Run:
```bash
git push origin trae/agent-wX1X6Q
```
Expected: push 成功。

- [ ] **Step 5: 同步 push main（docs commit 也要在 main 上）**

Run:
```bash
git checkout main && git merge --ff-only trae/agent-wX1X6Q && git push origin main && git checkout trae/agent-wX1X6Q
```
Expected: main 也推进到 docs commit。

---

### Task 7: PATCH Release v0.22.0 notes（补 M24 changelog）

**Files:**
- 无文件改动，curl API 操作

- [ ] **Step 1: 提取 token 到环境变量（避免泄漏到日志）**

Run:
```bash
export GH_TOKEN=$(git remote get-url origin | sed -n 's|https://x-access-token:\([^@]*\)@.*|\1|p')
test -n "$GH_TOKEN" && echo "TOKEN_OK" || echo "TOKEN_FAIL"
```
Expected: `TOKEN_OK`。

- [ ] **Step 2: 获取当前 Release v0.22.0 的 release_id**

Run:
```bash
RELEASE_ID=$(curl -s https://api.github.com/repos/qbjsdsb/eatwise/releases/tags/v0.22.0 | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "RELEASE_ID=$RELEASE_ID"
```
Expected: 输出 `RELEASE_ID=<数字>`。

- [ ] **Step 3: PATCH Release notes**

Run:
```bash
curl -s -X PATCH https://api.github.com/repos/qbjsdsb/eatwise/releases/$RELEASE_ID \
  -H "Authorization: token $GH_TOKEN" \
  -H "Content-Type: application/json" \
  -d @- <<'EOF' | python3 -c "import sys,json; r=json.load(sys.stdin); print('updated:', r.get('updated_at','FAIL')); print('body_len:', len(r.get('body','')))"
{
  "body": "## 本次改动（M24 — P1 清零）\n\nM23 全面细致审查发现 67 项问题（0 P0 / 13 P1 / 54 P2），本里程碑一次性修完全部 13 项 P1，代码健康度从 B+ 提升到 A-。全程严格 TDD + sub-agent 二次审查 + 6 硬约束核查。\n\n### 快速修复（8 项）\n- **A1** Sentry 脱敏补 `event.tags`（与 extra 同模式）\n- **A2** dashboard 推荐刷新按钮触控目标 32→48dp\n- **A3** update release notes 展开/收起 AnimatedSize 过渡\n- **A4** food_library 搜索失败 toast 提示\n- **A5** backup 导入弹窗补\"离线队列 N 条待识别将清空\"+ 修复 dispose 时序\n- **A6** insight 周/月切换 loading + AnimatedSwitcher 过渡\n- **A7** food_library 加载失败 ErrorState + 重试\n- **A8** profile 加载失败 ErrorState + 重试（跨页一致）\n\n### 架构重构（5 项）\n- **B1** 跨层依赖统一用 Repository Provider（feature 层不再直接 new Repo(db)，新增 6 个 FutureProvider；offline_queue_controller 是 isolate 例外保留 _db 注入）\n- **B2** recognize_page `_pickAndRecognize` 190→23 行（拆 4 子方法）\n- **B3** offline_queue_controller `processPending` 396→29 行（拆 _processOnePending + _processSingleItem + _processComposite）\n- **B4** multi_dish_page 986→542 行（拆 4 子文件到 multi_dish/ 子目录）\n- **B5** dashboard_page 940→304 行（拆 6 子文件到 dashboard/ 子目录）\n\n### 验证\n- `flutter analyze`：No issues found\n- `flutter test`：1032 passed / 3 skipped / 0 failed（+22 新测试，0 回归）\n- 6 硬约束全部满足：minify=false / 哨兵 10 处全保留 / AI 三路径覆盖 / per100g 基于 estimatedWeightGMid / SecureConfigStore 无 instance / initSentryAndRunApp 命名参数\n- 文件行数全部达标：multi_dish_page 542 / dashboard_page 304 / _pickAndRecognize 23 / processPending 29\n\n### 升级须知\n- v0.18.0 起可覆盖安装（无需卸载）\n- 重点验证：错误态覆盖（profile/food_library 加载失败显示 ErrorState + 重试）/ insight 周/月切换 loading / update release notes 展开/收起 / 备份导入弹窗离线队列提示 / 搜索失败 toast\n- 架构重构无回归验证：识别主流程（单品+多菜+后台回补三路径）/ dashboard 推荐刷新 / 食物库增删改查\n\n---\n\n## 安装说明\n\n1. 下载下方 apk（优先下 app-release.apk）\n2. 手机用数据线传过去（或扫码下载）\n3. 手机设置开启\"允许安装未知来源应用\"\n4. **直接覆盖安装即可**（v0.18.0 起用固定 keystore 签名，无需卸载旧版；v0.17.0 及之前需先卸载一次以切换签名）\n5. 首次启动在「设置」页填入你的 Qwen API Key（视觉识别用）\n6. 在「设置 → 检查更新」可一键升级到下一版\n\n## ⚠️ 闪退排查：请先装 app-debug.apk\n\n如果 app-release.apk 闪退，请改装 **app-debug.apk**：\n- debug 版崩溃时会显示**红色错误页+完整堆栈**\n- 截图发给开发者即可定位根因\n\n## 签名说明\n\n本包使用固定 release 签名（v0.18.0 起），可正常覆盖安装，但**不能上架应用商店**。\n\n## 版本信息\n\n- 应用版本: 0.22.0\n- 构建时间: 28748696263\n- 提交: d5b74833b5aeb727185568802b94673d8a63b1c8\n"
}
EOF
```
Expected: `updated: <时间戳>` + `body_len: <数字 > 2000>`。

- [ ] **Step 4: 验证 PATCH 成功（关键字检查）**

Run:
```bash
curl -s https://api.github.com/repos/qbjsdsb/eatwise/releases/tags/v0.22.0 | python3 -c "
import sys, json
r = json.load(sys.stdin)
body = r['body']
for kw in ['M24', 'A1', 'B1', 'P1 清零', '安装说明', '闪退排查']:
    print(f'{kw}: {\"OK\" if kw in body else \"MISSING\"}')
"
```
Expected: 全部 `OK`。

- [ ] **Step 5: 清理 token 环境变量**

Run:
```bash
unset GH_TOKEN
```
Expected: 无输出。

---

### Task 8: 设置 About 卡片 description + topics

**Files:**
- 无文件改动，curl API 操作

- [ ] **Step 1: 提取 token**

Run:
```bash
export GH_TOKEN=$(git remote get-url origin | sed -n 's|https://x-access-token:\([^@]*\)@.*|\1|p')
```
Expected: 无输出。

- [ ] **Step 2: PATCH 仓库 description + topics**

Run:
```bash
curl -s -X PATCH https://api.github.com/repos/qbjsdsb/eatwise \
  -H "Authorization: token $GH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "拍照识别食物热量 + 营养记录 + AI 周/月汇总建议 — Flutter Android App（个人自用）",
    "topics": ["flutter","android","food-tracking","nutrition","ai","qwen-vl","glm-4v","drift","material-3","local-first","privacy","sqlite"]
  }' | python3 -c "
import sys, json
r = json.load(sys.stdin)
print('description:', r.get('description','FAIL'))
print('topics:', r.get('topics',[]))
"
```
Expected: `description: 拍照识别食物热量...` + `topics: ['flutter', 'android', ...]`（12 个）。

- [ ] **Step 3: 验证（匿名访问，确认公开可见）**

Run:
```bash
curl -s https://api.github.com/repos/qbjsdsb/eatwise | python3 -c "
import sys, json
r = json.load(sys.stdin)
print('description:', r.get('description','FAIL'))
print('topics:', r.get('topics',[]))
print('topics_count:', len(r.get('topics',[])))
"
```
Expected: description + 12 个 topics 全部可见。

- [ ] **Step 4: 清理 token**

Run:
```bash
unset GH_TOKEN
```
Expected: 无输出。

---

## 验证清单（全部完成后执行）

- [ ] `git log --oneline origin/main -1` HEAD 含 M25 docs commit
- [ ] `curl https://api.github.com/repos/qbjsdsb/eatwise/releases/tags/v0.22.0` body 含 "M24" / "A1" / "B1" / "P1 清零"
- [ ] `curl https://api.github.com/repos/qbjsdsb/eatwise` description + topics 已设置
- [ ] `test -f /workspace/README.md && wc -l /workspace/README.md` 行数 > 100
- [ ] `test -f /workspace/LICENSE` 存在
- [ ] `grep -c "^## \[v0\." /workspace/CHANGELOG.md` = 16
- [ ] `grep -c "M25 GitHub 仓库主页同步完善" /workspace/HANDOFF.md` = 1
- [ ] README 内部链接（HANDOFF.md / CHANGELOG.md / LICENSE / .trae/specs/）文件全部存在

---

## Self-Review

**1. Spec coverage：**
- ✅ A. README.md 完整产品级重写 → Task 4
- ✅ B. About 卡片元数据 → Task 8
- ✅ C. 合并 main + 更新 Release v0.22.0 notes → Task 1 + Task 7
- ✅ D. 资源补全 LICENSE + CHANGELOG.md → Task 2 + Task 3
- ✅ 修订 HANDOFF → Task 5
- ✅ commit + push → Task 6

**2. Placeholder scan：** 无 TBD / TODO / "实现细节后补"。所有步骤含完整内容。

**3. Type consistency：** 无类型/方法签名问题（纯文档 + API 任务）。

**4. 风险点：**
- Task 1 Step 1 验证 ff 合并可行性，失败则停止
- Task 7/8 token 从 git remote 提取，不写明文
- Task 7 Release notes body 是单行 JSON 字符串（\n 转义），避免 heredoc 嵌套问题
