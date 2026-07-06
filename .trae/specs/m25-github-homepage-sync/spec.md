# M25: GitHub 仓库主页同步完善

**状态**：待用户审批
**日期**：2026-07-05
**前置**：M24 已 commit `d5b7483` + push `trae/agent-wX1X6Q` + tag `v0.22.0`；远端 main = `c7690bc`（落后 trae 分支）

---

## 1. 背景

GitHub 仓库主页（`github.com/qbjsdsb/eatwise`）与项目实际状态严重脱节：

- **README.md 严重过时**：L83 仍写"🚧 设计阶段 — 尚未开始编码"，实际已到 v0.22.0；目录结构缺 `features/update/weight/me/backup/` 等 4 个模块；技术栈表缺 M3 Expressive / GLM-4-Flash / sentry_flutter；"iOS + Android 一套代码"不实（实际仅 Android）；文档路径 `docs/superpowers/specs/` 不存在（实际 `.trae/specs/`）
- **main 分支落后**：远端 main HEAD = `c7690bc`，trae 分支 HEAD = `f797f71`，M24 commit `d5b7483` + HANDOFF 更新 commit `f797f71` 均未合并到 main
- **无 GitHub Release v0.22.0**：tag 已推但 Release notes 未创建
- **About 卡片元数据缺失**：description / topics 未设置（待 curl API 验证当前值）
- **缺 LICENSE 文件**：README 写 MIT 但无 LICENSE 文件
- **缺 CHANGELOG.md**：版本演进只在 HANDOFF.md，公开访客看不到
- **HANDOFF 部分过时**：L74 写 `origin/main HEAD = b7955c5`，实际 `c7690bc`

## 2. 目标

让任何访客打开 `github.com/qbjsdsb/eatwise` 5 秒内明白：这是什么 / 当前版本 / 能干什么 / 怎么装 / 历史怎么演进。

## 3. 范围

全量 A+B+C+D（用户已批准）：
- A. README.md 完整产品级重写
- B. About 卡片元数据（description + topics）
- C. 合并 main + 创建 GitHub Release v0.22.0
- D. 资源补全：LICENSE + CHANGELOG.md

## 4. 改动清单

### 4.1 文件创建/修改（沙箱完成）

| 路径 | 操作 | 内容 |
|---|---|---|
| `README.md` | 重写 | 见 4.1.1 大纲 |
| `LICENSE` | 创建 | MIT 完整文本，版权 `qbjsdsb` |
| `CHANGELOG.md` | 创建 | 见 4.1.2 大纲 |
| `HANDOFF.md` | 修订 | 修 L74 main HEAD 描述（`b7955c5` → 实际值）；补 M25 段 |

#### 4.1.1 README.md 大纲（完整产品级）

1. **标题 + 一句话品牌定位**：`# EatWise 慢慢吃` + `> 拍照识别食物热量 + 营养记录 + AI 周/月汇总建议 — Flutter Android App（个人自用）`
2. **Badges 行**：version / Flutter / Dart / license / last commit / code size / repo stars（用 shields.io）
3. **核心特性 4 图标列表**：📸 AI 拍照识别 / 🥗 本地食物库回填 / 📊 周/月 AI 汇总 / 🔒 本地加密无后端
4. **截图区**：当前 M22 图标 + 3 个截图占位（识别 / dashboard / insight），注明"截图待补"
5. **功能矩阵表**：识别（单品+多菜+离线回补）/ 营养（查库+校准+包装OCR）/ 汇总（周+月）/ 体重趋势 / 备份导入导出 / 应用内更新 / 隐私
6. **技术栈表**：完整 14 行（Flutter / drift+sqlite3mc / flutter_secure_storage / image_picker / flutter_image_compress / fl_chart / flutter_riverpod / go_router / Qwen-VL / GLM-4V-Plus / GLM-4-Flash / sentry_flutter / 中国食物成分表 / Material 3 Expressive），每行注释选型理由
7. **目录结构**：同步 v0.22.0 真实结构（含 features/update/weight/me/backup/me/ + .trae/specs/）
8. **安装**：APK 下载链接（指向 Release v0.22.0）+ 系统要求（Android 8.0+ / minSdk 26）+ 真机安装步骤 + 签名说明（v0.18.0 起可覆盖安装，v0.17.0 旧版需卸载一次因签名切换）
9. **版本演进表**：v0.15.0 → v0.22.0 共 16 个 tag，每个一句话核心改动
10. **状态**：`✅ v0.22.0 已发布（2026-07-05）` + 链接 Release
11. **文档**：链接 HANDOFF.md（项目交接）+ .trae/specs/（设计文档目录）+ CHANGELOG.md
12. **安全与隐私**：本地 AES 加密 / EXIF 剥离 / API key 不入库 / Sentry 脱敏
13. **开发**：Flutter 版本 / `flutter analyze` / `flutter test` 基线 / 6 硬约束摘要
14. **许可证**：MIT + 显式声明 LICENSE 文件

#### 4.1.2 CHANGELOG.md 大纲（完整版）

格式参考 Keep a Changelog，逆向整理 16 个 tag：

- 每个版本一个 `## [v0.22.0] - 2026-07-05` 段
- 每段：核心改动 1-3 句 + 链接到对应 Release
- 来源：git tag 日期 + HANDOFF.md 各里程碑章节 + commit log
- 顶部 `## [Unreleased]` 占位（M25 图标 + 后续）

### 4.2 Git 操作（沙箱完成）

| 操作 | 命令 | 说明 |
|---|---|---|
| 合并 main | `git checkout main && git merge --ff-only trae/agent-wX1X6Q` | fast-forward 合并，无冲突（main 是 trae 祖先） |
| push main | `git push origin main` | 推送合并后 main |
| 创建 Release v0.22.0 | `curl -X POST https://api.github.com/repos/qbjsdsb/eatwise/releases` | body 见 4.2.1 |

#### 4.2.1 Release v0.22.0 notes 内容

```
## v0.22.0 — P1 清零（M24）

M23 全面细致审查发现 67 项问题（0 P0 / 13 P1 / 54 P2），本里程碑一次性修完全部 13 项 P1，代码健康度从 B+ 提升到 A-。

### 快速修复（8 项）
- A1-A8 列表（从 HANDOFF 提取）

### 架构重构（5 项）
- B1-B5 列表

### 验证
- flutter analyze: No issues
- flutter test: 1032 passed / 0 failed
- 6 硬约束全部满足

### 升级须知
- v0.18.0 起可覆盖安装
- 验证 M24 修复点：错误态 / insight 切换 / update notes / 备份弹窗 / 搜索 toast
- 验证架构重构无回归：识别三路径 / dashboard / 食物库

### APK
（待用户本地构建上传）
```

### 4.3 About 卡片元数据（沙箱 curl API 完成）

```bash
# 设置 description + topics
curl -X PATCH https://api.github.com/repos/qbjsdsb/eatwise \
  -H "Authorization: token <token>" \
  -d '{
    "description": "拍照识别食物热量 + 营养记录 + AI 周/月汇总建议 — Flutter Android App（个人自用）",
    "topics": ["flutter","android","food-tracking","nutrition","ai","qwen-vl","glm-4v","drift","material-3","local-first","privacy","sqlite"]
  }'
```

token 从 `git remote -v` 提取（origin URL 内嵌 `ghu_...` token）。

## 5. 执行顺序

1. **合并 main**：`git checkout main && git merge --ff-only trae/agent-wX1X6Q && git push origin main`
2. **写 LICENSE + CHANGELOG.md + 重写 README.md**
3. **修订 HANDOFF.md**（修 L74 main HEAD + 补 M25 段）
4. **commit + push**（README/LICENSE/CHANGELOG/HANDOFF 一个 commit：「docs: 同步 GitHub 主页到 v0.22.0」）
5. **创建 GitHub Release v0.22.0**（curl API，tag 已存在 `d5b7483`）
6. **设置 About 卡片 description + topics**（curl API）

## 6. 验证标准

- `git log --oneline origin/main` HEAD = `f797f71`（合并成功）
- `curl https://api.github.com/repos/qbjsdsb/eatwise/releases/tags/v0.22.0` 返回 200 + body 含 M24 章节
- `curl https://api.github.com/repos/qbjsdsb/eatwise` 返回 description + topics 已设置
- README.md 内所有内部链接（HANDOFF.md / CHANGELOG.md / .trae/specs/）相对路径正确
- README.md 行数 > 100（产品级标准）
- CHANGELOG.md 含全部 16 个版本段
- LICENSE 文件存在且为 MIT 标准文本

## 7. 风险与缓解

| 风险 | 概率 | 缓解 |
|---|---|---|
| main ff 合并失败（main 不是 trae 祖先） | 低 | 先 `git fetch origin main` 验证；若非祖先改 `--no-ff` + 备选方案 |
| curl API token 泄漏到日志 | 中 | 用环境变量传 token，不在命令行明文 |
| README 内部链接 404 | 中 | 仅用相对路径 + 验证文件存在；不引用未创建文件 |
| Release notes 格式被 GitHub Markdown 渲染异常 | 低 | 用标准 Markdown，避免 HTML |
| About topics 含敏感词被 GitHub 拒绝 | 低 | 全用通用技术词，无品牌/敏感词 |

## 8. 出口

- 6 项验证全过
- commit + push 成功
- Release v0.22.0 + About 卡片设置成功
- HANDOFF.md M25 段记录完成

## 9. 不在范围

- M25 图标设计（用户暂搁，独立 spec）
- APK 构建 + 上传（沙箱无 Flutter 构建能力，用户手动）
- 截图采集 + 上传（用户真机截图后放 `docs/screenshots/`）
- Social Preview 图（用户用 M25 候选图标上传）
- 删除 classic PAT（用户手动 https://github.com/settings/tokens）
- `.github/workflows/` 修改（已有 ci.yml + release.yml，不动）
- Issue/PR template（个人项目，不需要）
