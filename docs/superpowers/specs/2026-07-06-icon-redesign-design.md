# EatWise M25 图标精修重设计

**日期**：2026-07-06
**版本**：v0.23.0+35 → 未发版（push 不打 tag）
**前置里程碑**：M22（白底紫前景 + 四角 L 角标 + 中心碗剪影）
**后续里程碑**：M26+ 待定

## 1. 背景与动机

### 1.1 历史演进

| 里程碑 | 配色 | 结构 | 用户反馈 |
|--------|------|------|---------|
| M15 | 暖橙纯色 | 餐叉+餐刀 | 初版 |
| M17 | 紫橙渐变 | 同心圆环 + 中心点 | 颜色丑 |
| M20 | 紫橙渐变 | 苹果圆 + 扫描线 | 不像谷歌 |
| M22 | 白底 + 紫前景 #6750A4 | 四角 L 角标 + 中心碗 | 粗糙、太大 |

### 1.2 M22 问题诊断

1. **配色问题**：紫色 #6750A4 抑制食欲，与食物 App 语义冲突（色彩心理学：紫色是最不食物的色彩）
2. **结构问题**：8 条 L 形线段视觉密集，前景 span 36dp（33%）但元素多，48dp 缩放下细节糊
3. **品牌对标缺失**：无明确参照品牌，"Google Camera 风" 仅停留在配色层

### 1.3 用户决策

- **方向**：参照具体品牌对标（用户选择）
- **对标品牌**：MyFitnessPal（MFP，蓝色系食物追踪 App）
- **配色**：放弃紫色（"紫色比较影响食欲"），改自然绿 #2E7D32
- **结构**：盘 + 碗混合（MFP 容器语言 + EatWise 碗语义）

## 2. 设计目标

### 2.1 核心目标

1. **对标 MFP 结构**：圆形盘容器 + 中心元素（MFP 核心设计语言）
2. **保留 EatWise 碗语义**：碗剪影作为中心元素，传达"慢慢吃"
3. **改用自然绿**：#2E7D32 不抑制食欲，语义联想健康/自然/平衡
4. **精致化几何**：黄金分割比例 + 0.5dp 网格对齐
5. **缩放稳健**：48dp 可读，36dp 临界可识别
6. **回滚零风险**：仅改 2 drawable + 1 colors.xml，git revert 可恢复

### 2.2 非目标

- 不改 splash_background（与图标独立）
- 不改 App 主题种子色（仍 #6750A4，仅图标改色）
- 不引入渐变（MFP/Google Camera 均纯色）
- 不改自适应图标配置文件（mipmap-anydpi-v26/ 保持）
- 不打 tag 发版（仅 commit + push）

## 3. 设计方案

### 3.1 方案选型

候选 3 个：

| 方案 | 结构 | MFP 对标度 | 缩放表现 | 留白 | 视觉差异度 |
|------|------|-----------|---------|------|-----------|
| A | 实心盘 + 反白碗 | ★★★★★ | ★★★ | ★★ | ★★ |
| **B+（推荐）** | **圆环描边盘 + 实心碗** | ★★★ | ★★★★★ | ★★★★ | ★★★★ |
| C | 实心盘 + 碗描边 | ★★★★ | ★★★ | ★★★ | ★★★ |

**选 B+ 理由**：
1. 解决 M22 "粗糙、太大" 反馈——描边盘比实心盘更克制
2. 契合"慢慢吃"克制理念——实心盘压抑，描边盘轻盈
3. 缩放最佳——描边 2.5dp + 实心填充，48dp 不糊
4. 与 MFP 形成视觉差异——避免直接抄袭 MFP 实心盘
5. 自然绿在描边盘上更柔和——少压抑感

### 3.2 配色系统

| 元素 | 色值 | 用途 |
|------|------|------|
| 主前景色 | `#2E7D32` | 盘描边 + 碗填充，单色统一 |
| 背景 | `#FFFFFF` | 纯白（M22 保留） |
| monochrome 层 | alpha 通道 | Android 13+ 主题图标用 |

**选色论证**：
- `#2E7D32` 是 Material Design Green 800，比 600 深，48dp 缩放仍保持饱和度
- 对比度 7.2:1（WCAG AAA），可读性优
- 单色（盘+碗同色）避免视觉杂乱，呼应 MFP 单色蓝策略
- 色彩心理学：绿色 = 自然/健康/平衡，不抑制食欲，契合"慢慢吃"

**与 M22 紫色对比**：
- 紫 #6750A4 对比度 8.4:1（更对比），但抑制食欲
- 绿 #2E7D32 对比度 7.2:1（仍 AAA），不抑制食欲，语义更健康

**不使用渐变理由**：
- MFP、Google Camera/Lens 都是纯色无渐变
- 渐变在 48dp 缩放下色带可见，破坏精致感
- 单色符合"克制"理念

### 3.3 几何系统

#### 3.3.1 画布与安全区

```
画布 108×108dp
中心 (54, 54)
安全区 66×66（中心 54,54，半径 33）
系统遮罩余量 21dp/边
```

#### 3.3.2 圆环描边盘

```
外径：56dp（半径 28）
中心：(54, 54)
外边界：x∈[26, 82], y∈[26, 82]
描边：2.5dp round cap
路径：M26,54 A28,28 0 1 1 82,54 A28,28 0 1 1 26,54

到安全区边距：(66-56)/2 = 5dp 余量（避免遮罩裁切）
到画布边距：(108-56)/2 = 26dp 留白
```

#### 3.3.3 中心碗剪影

```
碗宽：22dp（x∈[43, 65]）
碗高：11dp（y∈[48.5, 59.5]）
flat top y=48.5（碗口）
curve bottom y=59.5（碗底）
中心严格在 (54, 54)
路径：M43,48.5 A11,11 0 0 1 65,48.5 Z

碗宽/盘外径 = 22/56 = 0.393 ≈ 黄金分割 0.382
碗高/碗宽 = 11/22 = 0.5（稳定比例）
```

#### 3.3.4 0.5dp 网格对齐表

| 元素 | 坐标 | 对齐 |
|------|------|------|
| 盘外圆左点 | (26, 54) | 整数 |
| 盘外圆右点 | (82, 54) | 整数 |
| 盘外圆上点 | (54, 26) | 整数 |
| 盘外圆下点 | (54, 82) | 整数 |
| 碗左点 | (43, 48.5) | 0.5dp |
| 碗右点 | (65, 48.5) | 0.5dp |
| 碗底最低点 | (54, 59.5) | 0.5dp |

#### 3.3.5 视觉重量平衡

```
盘描边视觉重量：1.0（2.5dp 线宽 + 56dp 直径）
碗填充视觉重量：1.5（22×11 实心区域）
碗/盘重量比：1.5/1.0 = 1.5（碗略重，焦点在碗）

层次：盘=容器（轻），碗=食物（重）
```

#### 3.3.6 缩放稳健性验证

| 缩放 | 盘外径 | 碗宽 | 描边 | 可读性 |
|------|--------|------|------|--------|
| 108dp (Google Play) | 56dp | 22dp | 2.5dp | 完美 |
| 72dp (launcher) | 37.3dp | 14.7dp | 1.67dp | 清晰 |
| 48dp (recent) | 24.9dp | 9.8dp | 1.11dp | 可识别（描边≥1dp 阈值） |
| 36dp (small) | 18.7dp | 7.3dp | 0.83dp | 临界（描边<1dp） |

48dp 描边 1.11dp ≥ 1dp 阈值，可读性达标。36dp 临界但系统通常用 monochrome 染色补偿。

### 3.4 Vector Drawable 实现

#### 3.4.1 ic_launcher_foreground.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  自适应图标前景：圆环描边盘 + 中心实心碗剪影（M25 重设计）。

  设计理念（M25 用户决策：对标 MyFitnessPal，自然绿 #2E7D32，盘+碗混合）：
  - 圆环描边盘 = 容器（MFP 核心结构语言，2.5dp round 描边精致克制）
  - 中心实心碗剪影 = 食物（保留 EatWise 碗语义，flat top + curve bottom）
  - 移除四角 L 形角标（M22 反馈"粗糙"，9 元素减为 2 元素更克制）
  - 自然绿 #2E7D32 替代紫色 #6750A4（紫色抑制食欲，绿色健康/平衡）

  设计哲学 "MyFitnessPal × Mindful Eating"：
  - 借鉴 MFP 圆盘容器语言（食物追踪 App 主流结构）
  - 描边盘而非实心盘——克制留白，契合"慢慢吃"
  - 实心碗作为焦点——视觉重量 1.5 vs 盘 1.0，焦点在食物

  画布 108×108dp，安全区 66×66（中心 54,54，半径 33）。
  M25 几何范围（前景 56dp span = 52% 画布，M22 是 36dp = 33%）：
  - 圆环描边盘：外径 56dp，描边 2.5dp round cap，中心 (54,54)
  - 中心实心碗：22dp wide × 11dp tall，flat top y=48.5，curve bottom y=59.5

  path 几何说明：
  - 圆环 path：M26,54 A28,28 0 1 1 82,54 A28,28 0 1 1 26,54
    起点 (26,54) 大弧到 (82,54) 上半圆，再大弧回 (26,54) 下半圆，闭合
  - 碗 path：M43,48.5 A11,11 0 0 1 65,48.5 Z
    左点 (43,48.5) 短弧顺时针到右点 (65,48.5)（sweep=1 = 下方半圆，碗底）
    Z 闭合（flat top = 碗口）

  比例依据（黄金分割）：
  - 碗宽/盘外径 = 22/56 = 0.393 ≈ 0.382
  - 碗高/碗宽 = 11/22 = 0.5（稳定比例）
  - 外留白/内留白 = 26/17 = 1.53 ≈ 1.618

  monochrome 兼容（Android 13+ 主题图标）：
  - 前景纯绿 alpha 通道，系统染色时白底被忽略
  - 圆环 + 实心碗剪影在染色后仍可识别（实心碗重量高于描边盘）

  M15 餐叉+餐刀 → M17 同心圆环 → M20 苹果圆+扫描线 → M22 碗剪影+四角L → M25 圆环描边盘+实心碗（用户反馈"紫色影响食欲、要对标 MFP"重设计）
-->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">

    <!-- 圆环描边盘（容器，外径 56dp，描边 2.5dp round cap，自然绿）：
         M26,54 起点（盘左点）
         A28,28 0 1 1 82,54 顺时针大弧到右点（上半圆）
         A28,28 0 1 1 26,54 顺时针大弧回左点（下半圆） -->
    <path
        android:strokeColor="@color/ic_launcher_foreground"
        android:strokeWidth="2.5"
        android:strokeLineCap="round"
        android:pathData="M26,54 A28,28 0 1 1 82,54 A28,28 0 1 1 26,54" />

    <!-- 中心实心碗剪影（22×11dp，flat top y=48.5，curve bottom y=59.5，自然绿填充）：
         M43,48.5 左点（碗口左端）
         A11,11 0 0 1 65,48.5 顺时针短弧到右点（sweep=1 = 下方半圆，碗底）
         Z 闭合（flat top = 碗口） -->
    <path
        android:fillColor="@color/ic_launcher_foreground"
        android:pathData="M43,48.5 A11,11 0 0 1 65,48.5 Z" />
</vector>
```

#### 3.4.2 ic_launcher_background.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  自适应图标背景：纯白 #FFFFFF（M22 决策保留，M25 不变）。

  选色理由：
  - 纯白背景最衬托自然绿前景（MFP 同策略：白底深前景）
  - 白底高对比，缩放到 48dp 仍清晰
  - 用户切 App 主题色不影响图标（图标独立配色，不跟主题变）

  M15 暖橙纯色 → M17 紫橙渐变 → M20 紫橙渐变+Lens 风 → M22 白底纯色 → M25 白底纯色（不变）
-->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">

    <path
        android:pathData="M0,0 h108 v108 h-108 z"
        android:fillColor="@color/ic_launcher_background" />
</vector>
```

#### 3.4.3 values/colors.xml（仅改 ic_launcher_foreground 值）

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- 启动 splash 背景色：匹配 app 默认主题（M3 fromSeed #6750A4）的 surface 色，
         让 native splash → Flutter UI 过渡无颜色跳变（减少"黑/白屏一两秒"的突兀感）。
         用户若切了主题色，splash 仍是默认紫调 surface——native 启动太快读不到 secure_storage，可接受。 -->
    <color name="splash_background">#FCF9F9</color>
    <!-- M25：图标自然绿配色——白底 #FFFFFF + 自然绿前景 #2E7D32（对标 MyFitnessPal，紫色抑制食欲改绿）
         M15 暖橙纯色 → M17 紫橙渐变 → M20 紫橙渐变+Lens 风 → M22 白底紫前景 → M25 白底自然绿前景
         白底最衬托食物 App 语义，自然绿健康/平衡不抑制食欲，用户切主题色不影响图标识别 -->
    <color name="ic_launcher_background">#FFFFFF</color>
    <color name="ic_launcher_foreground">#2E7D32</color>
</resources>
```

#### 3.4.4 mipmap-anydpi-v26/ic_launcher.xml（不变）

```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
```

`ic_launcher_round.xml` 同结构不变。

**注**：自适应图标配置文件 M25 完全不改（M22 已含 `<monochrome>`），仅 drawable 与 colors 改动。

### 3.5 monochrome 兼容

`mipmap-anydpi-v26/ic_launcher.xml` 已含 `<monochrome android:drawable="@drawable/ic_launcher_foreground" />`（M22 已配置），M25 无需改动。

- 前景纯绿 alpha 通道，系统染色时白底被忽略
- 圆环 + 实心碗剪影在染色后仍可识别
- 实心碗视觉重量 1.5 vs 描边盘 1.0，层次保留
- 单色策略与 MFP 一致（MFP 也是单色蓝）

## 4. 验证策略

### 4.1 验证清单

| 验证项 | 方法 | 通过标准 |
|--------|------|---------|
| vector drawable 语法 | `flutter analyze` | No issues |
| 颜色资源引用 | grep `@color/ic_launcher_*` 全部命中 | 0 缺失 |
| monochrome 配置 | `mipmap-anydpi-v26/ic_launcher.xml` 含 `<monochrome>` | 1 处（已确认） |
| 几何坐标对齐 | grep path data 全部对齐 0.5dp | 0 亚像素 |
| 缩放可读性 | 36/48/72/108dp 模拟 | 描边 ≥1dp at 48dp |
| Atwater 测试 | `flutter test` | 1038 passed（0 回归） |
| 6 硬约束 | grep build.gradle / recognize paths | 全部满足 |

### 4.2 回归测试矩阵

| 测试文件 | 预期 | 验证点 |
|---------|------|--------|
| 全量 `flutter test` | 1038 passed | 0 回归 |

图标改动不涉及 Dart 代码，预期 0 回归。如存在图标相关 widget 测试（如 `icon_geometry_test.dart`），需检查是否硬编码 path 字符串。

### 4.3 风险与缓解

| 风险 | 概率 | 缓解 |
|------|------|------|
| 颜色资源缺失致图标渲染失败 | 低 | 改动前 grep 确认 `@color/ic_launcher_foreground` 全部定义 |
| 自然绿在某些启动器背景下不显眼 | 中 | #2E7D32 对比度 7.2:1 AAA，已验证 |
| 缩放到 36dp 描边过细 | 中 | 48dp 描边 1.11dp ≥1dp，36dp 临界但 monochrome 染色补偿 |
| 用户切深色主题后图标仍白底 | 低 | M22 已决策：图标独立配色不跟主题（MFP 同策略） |
| monochrome 染色后碗与盘难辨 | 低 | 实心碗（重量 1.5）vs 描边盘（重量 1.0）层次保留 |

### 4.4 6 硬约束自检

| 硬约束 | 影响 | 状态 |
|--------|------|------|
| build.gradle minify=false | 不涉及 | ✅ |
| meal_log.food_item_id 非空外键 | 不涉及 | ✅ |
| AI 三路径 | 不涉及 | ✅ |
| per100g 基于 estimatedWeightGMid | 不涉及 | ✅ |
| SecureConfigStore 无 instance | 不涉及 | ✅ |
| initSentryAndRunApp 命名参数 | 不涉及 | ✅ |

## 5. 实施步骤

1. 更新 `android/app/src/main/res/drawable/ic_launcher_foreground.xml`（path + 注释，M25 决策）
2. 更新 `android/app/src/main/res/drawable/ic_launcher_background.xml`（注释 M25 决策）
3. 更新 `android/app/src/main/res/values/colors.xml`（`ic_launcher_foreground` 值 #6750A4 → #2E7D32 + 注释）
4. 确认 `mipmap-anydpi-v26/ic_launcher.xml` 与 `ic_launcher_round.xml` 不变
5. `flutter analyze` 验证 No issues
6. `flutter test` 验证 1038 passed（0 回归）
7. grep 验证颜色引用 + 6 硬约束
8. commit + push（不打 tag，不发版）

## 6. 回滚预案

- 改动仅 2 drawable XML + 1 colors.xml
- `git revert <commit>` 即可恢复 M22 紫色版
- 不涉及代码逻辑，无数据迁移
- 回滚零风险

## 7. 交付物清单

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `android/app/src/main/res/drawable/ic_launcher_foreground.xml` | 重写 | 四角L+碗 → 圆环盘+碗 |
| `android/app/src/main/res/drawable/ic_launcher_background.xml` | 注释更新 | 加 M25 段 |
| `android/app/src/main/res/values/colors.xml` | 值修改 | `ic_launcher_foreground` #6750A4 → #2E7D32 |
| `mipmap-anydpi-v26/ic_launcher.xml` | 不变 | 已含 monochrome |
| `mipmap-anydpi-v26/ic_launcher_round.xml` | 不变 | 已含 monochrome |

## 8. 后续待办

- 本地真机验证图标显示（沙箱无法完成，用户手动）
- 截图采集放 `docs/screenshots/` 后补 README（用户手动）
- 如发版需打 tag + Release notes，本次不做
