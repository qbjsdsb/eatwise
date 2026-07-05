# EatWise App 图标重设计——M3 抽象几何 + 紫橙双色渐变

> **目标**：重设计「慢慢吃（EatWise）」App 启动器图标，符合软件功能与理念，简洁精致耐看不俗套，严格遵守 Android 自适应图标规范。
> **用户决策**：M3 抽象几何（无具体物象）+ 双色渐变（紫主 #6750A4 + 橙辅 #FF6E40）
> **技能组合**：brainstorming（创意发散）→ canvas-design（设计稿）→ byted-seedream-image-generate（AI 灵感参考）→ 手工 vector drawable XML（最终交付）

---

## Phase 1 探索结果（已完成）

### App 理念
- **项目名**：慢慢吃（EatWise）—— 拍照识别食物热量 + 营养记录 + AI 汇总建议
- **核心关键词**：拍照识别 / 食物 / 热量 / 营养 / AI 智慧 / 慢慢吃（用心品味、不急、觉知）
- **品牌色彩语言**：Material 3 Expressive + 莫奈画作色系（睡莲青绿 / 日出橙 / 鸢尾紫）

### 当前图标状态（待替换）
- **背景**：`android/app/src/main/res/drawable/ic_launcher_background.xml` —— 纯色矩形 #FF6E40（Material Deep Orange 400）
- **前景**：`android/app/src/main/res/drawable/ic_launcher_foreground.xml` —— 白色"餐叉+餐刀"几何符号（108×108dp 画布）
- **自适应图标 XML**：`mipmap-anydpi-v26/ic_launcher.xml` + `ic_launcher_round.xml`（背景+前景+monochrome 三层）
- **PNG 位图**：5 套 dpi（mdpi 48×48 / hdpi 72×72 / xhdpi 96×96 / xxhdpi 144×144 / xxxhdpi 192×192）× 2（普通+圆角）
- **颜色资源**：`values/colors.xml` 中 `ic_launcher_background=#FF6E40` + `ic_launcher_foreground=#FFFFFF`
- **AndroidManifest**：`android:icon="@mipmap/ic_launcher"` + `android:roundIcon="@mipmap/ic_launcher_round"`
- **历史反馈**：「碗+蒸汽」被嫌难看、「青莲色」被嫌丑、要求"更像谷歌公司会发布的"

### Android 自适应图标规范（硬约束）
1. **画布**：108×108dp，viewport 108×108
2. **安全区**：中心 (54, 54)，半径 33dp（直径 66dp）—— 前景内容必须在此范围内，否则 OEM 蒙版裁切
3. **背景层**：full-bleed 108×108（可纯色/渐变/图案，超出安全区无影响）
4. **前景层**：内容必须在安全区内（4dp 留白更安全）
5. **monochrome 层**：Android 13+ 主题图标，复用前景但需保证纯 alpha 通道可染色
6. **OEM 蒙版**：自动裁切为圆/方/圆角方/squircle 等，设计时不可假定特定形状
7. **缩放测试**：48dp（mdpi 启动器最小尺寸）下仍可识别

### App 主题色（参考）
- 默认种子色：M3 基线紫 #6750A4
- 预设色板：睡莲青绿 #5B8C7B / 日出橙 #E08B3C / 鸢尾紫 #6B5B95 / 番茄红 #D32F2F / 琥珀 #F57C00
- 主题变体：DynamicSchemeVariant.tonalSpot（secondary/tertiary 紧跟 primary 色相）

---

## Phase 2 用户决策（已完成）

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 图标核心意象 | **M3 抽象几何（无具体物象）** | Google Workspace 式纯几何抽象，最不俗套，靠色彩和构图传递品牌 |
| 配色方向 | **双色渐变（紫主 #6750A4 + 橙辅 #FF6E40）** | M3 Expressive 大胆配色，紫呼应 App 主题、橙呼应食欲色，渐变层次精致 |

---

## 设计挑战与策略

### 挑战
1. **抽象无物象** + **要符合"慢慢吃"理念**：纯几何如何暗示食物/营养/慢？
2. **双色渐变**在 vector drawable 中实现：Android `<gradient>` 需 API 24+，自适应图标 anydpi-v26 支持
3. **缩放可识别性**：48dp 下抽象几何容易糊成一团
4. **monochrome 兼容**：渐变图标转单色后需保持识别度

### 策略
1. **语义暗示路径**（brainstorming 重点）：
   - 「圆 + 切割」→ 暗示餐盘俯视 + 营养素比例分割
   - 「同心圆环」→ 暗示份量刻度 + 镜头光圈
   - 「弧线 + 圆点」→ 暗示"一餐" + 食物颗粒
   - 「色块叠加」→ Google Workspace 多色块抽象风（Docs/Sheets/Slides）
   - 「螺旋」→ 暗示"慢"的意象
   - 「方+圆」→ 几何对比 + 餐桌俯视
2. **渐变实现**：背景层用 `<gradient>` 线性渐变（紫→橙），前景层用纯色或半透明叠加
3. **缩放测试**：canvas-design 同时出 192×192 和 48×48 设计稿对比验证
4. **monochrome**：前景用纯白 alpha 通道，渐变只放背景层（monochrome 复用前景，渐变背景在主题图标模式下被系统染色覆盖）

---

## Proposed Implementation Plan（7 个 Task）

### Task 1: brainstorming —— 抽象几何概念发散

**Skill**: `brainstorming`

- [ ] **Step 1**: 启动 brainstorming skill，输入设计简报：
  - 项目：慢慢吃（EatWise），拍照识别食物+营养记录+AI 汇总
  - 约束：M3 抽象几何（无具体物象）+ 紫橙双色渐变 + Android 自适应图标规范
  - 目标：生成 6-8 个抽象几何概念，每个含 1 句设计理念 + 1 句"如何暗示慢慢吃/食物/营养"

- [ ] **Step 2**: 从 brainstorming 输出筛选 top 3 候选概念，进入 Task 2 出设计稿

**预期候选方向**（实际以 brainstorming 输出为准）：
- 候选 A：「三色块分割圆」—— 圆形被两条直径切成三块（紫/橙/紫橙渐变），暗示营养素比例
- 候选 B：「同心圆环 + 中心圆点」—— 紫色外环 + 橙色中心圆，暗示镜头+食物
- 候选 C：「弧线叠加」—— 紫橙两段弧线交叉，Google Workspace 多色块抽象风
- 候选 D：「螺旋渐变」—— 紫到橙的螺旋线，"慢"的意象

---

### Task 2: canvas-design —— top 3 候选设计稿

**Skill**: `canvas-design`
**输出文件**：
- `/workspace/.trae/design/icon-concept-A.png`（192×192 + 48×48 双尺寸并排）
- `/workspace/.trae/design/icon-concept-B.png`
- `/workspace/.trae/design/icon-concept-C.png`
- `/workspace/.trae/design/icon-concepts-overview.pdf`（三方案对比 PDF）

- [ ] **Step 1**: 启动 canvas-design skill，对 top 3 概念分别出设计稿
- [ ] **Step 2**: 每个设计稿包含：
  - 192×192 大尺寸预览（看清细节）
  - 48×48 缩放预览（验证缩放可识别性）
  - 紫橙双色渐变示意（标注 hex 色值）
  - 安全区 66×66 边框示意（虚线标注，验证前景不超界）
- [ ] **Step 3**: 输出 overview PDF，三方案并排对比

---

### Task 3: byted-seedream-image-generate —— AI 灵感参考（可选）

**Skill**: `byted-seedream-image-generate`
**输出文件**：`/workspace/.trae/design/ai-inspiration-{1..4}.png`

- [ ] **Step 1**: 用 Seedream 5.0 生成 4 张 AI 灵感参考图（仅作创意启发，不直接用作图标）：
  ```
  prompt 方向（4 张）：
  1. "Minimalist abstract geometric app icon, purple to orange gradient, 
     concentric circles suggesting camera lens and food portion, 
     Material Design 3 Expressive style, clean vector aesthetic"
  2. "Modern abstract app icon, circle divided into three sections by 
     gradient purple-orange, suggesting nutrition proportions, 
     Google Workspace style geometric abstraction"
  3. "Minimalist app icon, two overlapping arc shapes in purple and orange 
     gradient, abstract food plate top view, Material Symbols aesthetic"
  4. "Abstract geometric app icon, spiral gradient from purple to orange, 
     suggesting mindful slow eating, clean minimalist vector style"
  ```
  参数：`--version 5.0 --size 2048x2048 --no-watermark --output-format png`

- [ ] **Step 2**: AI 参考图与 canvas-design 设计稿对比，提取可借鉴的构图/色彩/比例元素

---

### Task 4: 用户选定最终方案

- [ ] **Step 1**: 向用户展示 top 3 canvas-design 设计稿 + 4 张 AI 灵感参考
- [ ] **Step 2**: 用 AskUserQuestion 让用户选定最终方案（或要求融合/调整）
- [ ] **Step 3**: 用户选定后冻结设计，进入 Task 5 实现

---

### Task 5: 手工实现 Android vector drawable

**Files**:
- 修改：`android/app/src/main/res/drawable/ic_launcher_background.xml`（渐变背景）
- 修改：`android/app/src/main/res/drawable/ic_launcher_foreground.xml`（抽象几何前景）
- 修改：`android/app/src/main/res/values/colors.xml`（新增渐变色值）
- 不变：`mipmap-anydpi-v26/ic_launcher.xml` + `ic_launcher_round.xml`（adaptive-icon 结构不变）

- [ ] **Step 1**: 写 `ic_launcher_background.xml` 渐变背景
  - 用 `<vector>` + `<gradient>` 实现紫→橙线性渐变（API 24+，自适应图标 anydpi-v26 支持）
  - 渐变方向：左上紫 #6750A4 → 右下橙 #FF6E40（135° 对角线，最具表现力）
  - 全画布 108×108 full-bleed（背景可超安全区）

- [ ] **Step 2**: 写 `ic_launcher_foreground.xml` 抽象几何前景
  - 按用户选定方案画几何图形（圆/弧/线/色块组合）
  - 内容严格在安全区 (54,54) 半径 33 内（建议留 4dp 余量，即半径 29）
  - 前景用纯白色 #FFFFFF（在渐变背景上高对比）
  - 若方案含多色块，用半透明白色叠加（如 #FFFFFF alpha 0.85 / 0.6 / 0.4 形成层次）

- [ ] **Step 3**: 更新 `values/colors.xml`
  - 保留 `ic_launcher_background` 兼容旧 PNG 引用（改为渐变起始色 #6750A4）
  - 新增 `ic_launcher_background_end` #FF6E40（渐变结束色）
  - `ic_launcher_foreground` 仍 #FFFFFF

- [ ] **Step 4**: 验证 monochrome 兼容性
  - monochrome 复用前景，需保证前景是纯 alpha 通道图形（无渐变在前景层）
  - 系统在主题图标模式下会用单色染色前景，渐变背景被忽略，前景必须独立可识别

---

### Task 6: 生成 mipmap PNG 多 dpi 位图

**原因**：Android < 8.0（API < 26）不支持自适应图标，需 PNG 兜底；启动器在某些场景也会用 PNG

**方法**：用 `flutter launcher_icon` 包或 ImageMagick 从 192×192 master PNG 缩放

- [ ] **Step 1**: 从 vector drawable 渲染 192×192 master PNG
  - 选项 A：用 Android Studio 内置工具渲染（沙箱无 GUI，不可用）
  - 选项 B：用 `resvg` 或 `vectordrawable-cli` 命令行渲染（沙箱需安装）
  - 选项 C：用 canvas-design 直接输出 192×192 PNG master（最可靠）

- [ ] **Step 2**: 从 192×192 master 缩放生成 5 套 dpi
  - mdpi 48×48 / hdpi 72×72 / xhdpi 96×96 / xxhdpi 144×144 / xxxhdpi 192×192
  - 用 ImageMagick：`convert master.png -resize 48x48 mipmap-mdpi/ic_launcher.png`
  - 圆角版（ic_launcher_round.png）单独处理：圆角蒙版

- [ ] **Step 3**: 替换 10 个 PNG 文件
  - `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`
  - `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_round.png`

---

### Task 7: 验证 + 发布

- [ ] **Step 1**: `flutter analyze` 无错误
- [ ] **Step 2**: `flutter build apk --debug` 验证图标资源打包成功（沙箱可能无法完整 build，至少 `flutter analyze` + 资源检查）
- [ ] **Step 3**: 6 条硬约束验证（重点：build.gradle.kts isMinifyEnabled=false 不变）
- [ ] **Step 4**: bump `pubspec.yaml` 0.18.8+27 → 0.18.9+28
- [ ] **Step 5**: 更新 `HANDOFF.md` 新增 M17 图标重设计章节
- [ ] **Step 6**: 严肃 commit + push + tag v0.18.9
  ```bash
  git add android/app/src/main/res/ pubspec.yaml HANDOFF.md
  git commit -m "M17: App 图标重设计——M3 抽象几何 + 紫橙双色渐变

  用户反馈当前图标「实在太丑」，要求重新设计：
  简洁精致、耐看不俗套、严格安卓设计规范。

  设计方向（用户决策）：
  - M3 抽象几何（无具体物象）—— Google Workspace 式纯几何抽象
  - 双色渐变（紫主 #6750A4 + 橙辅 #FF6E40）—— M3 Expressive 大胆配色

  实现：
  - ic_launcher_background.xml: 紫→橙线性渐变（135° 对角线）
  - ic_launcher_foreground.xml: 抽象几何图形（用户选定方案）
  - colors.xml: 新增渐变色值
  - 5 套 dpi PNG (mdpi~xxxhdpi) 重新生成
  - monochrome 兼容 Android 13+ 主题图标

  Skill 协作：brainstorming 发散 → canvas-design 出设计稿 →
  byted-seedream-image-generate AI 灵感参考 → 手工 vector drawable 实现

  bump 0.18.8+27 → 0.18.9+28 + HANDOFF M17 章节。"
  git push origin trae/agent-wX1X6Q
  git tag v0.18.9
  git push origin v0.18.9
  ```

---

## Assumptions & Decisions

### 决策 1：最终交付物为 vector drawable XML（非 PNG 位图）
- **理由**：Android 自适应图标规范要求矢量，缩放无损，OEM 蒙版正确裁切
- **PNG 仅作兜底**：Android < 8.0 + 启动器特殊场景

### 决策 2：渐变放在背景层，前景用纯白 alpha
- **理由 1**：monochrome 复用前景，前景有渐变会破坏主题图标染色
- **理由 2**：前景纯白在渐变背景上对比度最高，缩放最清晰
- **理由 3**：M3 Expressive 推荐"渐变大色块 + 纯色前景符号"组合

### 决策 3：Skill 协作流程
- brainstorming → 发散概念（避免 AI 直接画图俗套）
- canvas-design → 出可控的矢量设计稿（保证 Material 风格）
- Seedream 5.0 → AI 灵感参考（仅创意启发，不直接用）
- 手工 XML → 最终交付（保证规范合规）

### 决策 4：版本号 bump 0.18.9+28
- 图标是用户可见变更，需 bump 版本号触发应用内更新提示

### 假设
1. 沙箱有 ImageMagick（`convert` 命令）可用于 PNG 缩放；若无，用 Python PIL 兜底
2. 沙箱无 Android Studio GUI，PNG master 由 canvas-design 直接输出
3. 用户在 Task 4 会选定一个方案（或要求小调整），不会推翻整个方向

---

## Verification Steps

1. **设计稿验证**（Task 2）：
   - 192×192 大尺寸细节清晰 ✅
   - 48×48 缩放仍可识别 ✅
   - 安全区 66×66 边框内 ✅
   - 紫橙渐变色值正确（#6750A4 → #FF6E40）✅

2. **vector drawable 验证**（Task 5）：
   - XML 语法合法（`flutter analyze` 通过）✅
   - 渐变在 API 24+ 正常渲染（anydpi-v26 支持）✅
   - 前景内容在安全区内（半径 33 + 4dp 余量）✅
   - monochrome 染色后仍可识别 ✅

3. **PNG 兜底验证**（Task 6）：
   - 5 套 dpi PNG 尺寸正确（48/72/96/144/192）✅
   - 圆角版（ic_launcher_round.png）圆角蒙版正确 ✅

4. **发布验证**（Task 7）：
   - flutter analyze No issues ✅
   - 6 条硬约束全部满足 ✅
   - commit + push + tag v0.18.9 ✅

---

## Self-Review

### 1. Spec coverage
- ✅ 符合软件功能和理念：抽象几何 + 紫橙渐变 + brainstorming 暗示"慢慢吃"语义
- ✅ 美观 + 简洁精致：M3 Expressive 大胆配色 + 几何极简
- ✅ 耐看 + 不俗套：抽象无物象 + 双色渐变层次
- ✅ 严格安卓设计规范：自适应图标三层 + 安全区 + monochrome + 5 套 dpi PNG
- ✅ 严肃 commit + push + tag：Task 7 完整发布流程

### 2. 风险评估
- **风险 1**：抽象几何在 48dp 下糊成一团
  - 缓解：canvas-design 出 48×48 缩放预览，Task 2 验证；图形保持粗线条（≥4dp 宽度）
- **风险 2**：双色渐变在某些 OEM 启动器渲染异常
  - 缓解：渐变只放背景层（full-bleed 108×108），前景纯色高对比，即使背景渲染异常图标仍可识别
- **风险 3**：沙箱无 ImageMagick / resvg
  - 缓解：canvas-design 直接输出 5 套 dpi PNG（绕过 vector→PNG 转换）
- **风险 4**：用户对 Task 4 选定方案仍不满意
  - 缓解：Task 4 允许融合/小调整，必要时回到 Task 2 出新方案
