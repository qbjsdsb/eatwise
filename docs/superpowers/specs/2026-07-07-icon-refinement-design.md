# M26 图标精修设计文档

> **版本**：v0.29.0
> **日期**：2026-07-07
> **变更类型**：UI 视觉精修（图标重设计）
> **前置版本**：v0.28.0（M25 图标：圆环盘+实心碗+白底）

## 1. 背景与目标

### 1.1 用户反馈

用户反馈当前 M25 图标"想做得更加精致美丽一点"。

### 1.2 M25 图标局限

1. **元素单薄**：只有 2 个元素（圆环描边盘 + 实心碗剪影），视觉过于克制缺精致感
2. **无层次**：圆环 + 碗都是单色纯绿 `#2E7D32`，无色彩层次
3. **缺食物语义**：碗是抽象剪影，没有食物暗示（看不出"慢慢吃"的语义）

### 1.3 设计目标

- **精致**：增加色彩层次（4 色 vs M25 的 2 色）+ 几何层次（描边+填充 vs M25 纯填充）
- **食物语义**：碗内米粒 + 碗口叶子，暗示"自然 × 食物"
- **保留品牌延续**：主色仍为自然绿 `#2E7D32`，碗结构延续 M22→M25 演进
- **monochrome 兼容**：Android 13+ 主题图标染色后仍可识别

## 2. 设计方案

### 2.1 用户决策链

| 决策点 | 选择 |
|--------|------|
| 风格方向 | 方案 B：碗+叶子（自然×食物） |
| 叶子位置 | 右上侧飘出 |
| 背景 | 径向渐变背景 |
| 碗内元素 | 三粒米粒 |
| 碗风格 | 描边碗+内部填充 |
| 圆环盘 | 删除 |

### 2.2 视觉结构（3 元素 + 渐变背景）

```
┌──────────────────────┐
│  渐变背景（中心白→边缘淡绿）│
│         🍃            │
│      ╭─────╮          │
│      │ • • │          │
│      │  •  │          │
│      ╰─────╯          │
│      描边碗+米粒        │
└──────────────────────┘
```

### 2.3 配色（4 色 + 渐变）

| 元素 | 颜色 | Material 取值 | 说明 |
|------|------|--------------|------|
| 背景中心 | `#FFFFFF` | White | 径向渐变中心 |
| 背景边缘 | `#F1F8E9` | Light Green 50 | 极淡绿，衬托前景 |
| 碗描边 | `#1B5E20` | Green 900 | 深绿，比主色深一阶 |
| 碗填充 | `#E8F5E9` | Green 50 | 淡绿，与背景边缘同色系 |
| 叶子 | `#2E7D32` | Green 800 | 主绿，保留 M25 主色 |
| 米粒 | `#FFF59D` | Amber 200 | 淡黄，食物语义 |

### 2.4 画布几何（108×108dp，安全区 66×66，中心 54,54）

#### 2.4.1 径向渐变背景

```xml
<aapt:attr name="android:fillColor">
  <gradient
    android:type="radial"
    android:centerX="54"
    android:centerY="54"
    android:gradientRadius="54"
    android:startColor="#FFFFFF"
    android:endColor="#F1F8E9" />
</aapt:attr>
```

#### 2.4.2 描边碗 + 内部填充

**几何**：碗宽 30dp × 高 15dp，比 M25（22×11）略大（删除圆环盘后碗成为唯一主体）

- 碗口 flat top：y=51
- 碗底 curve bottom：y=66
- 碗左点：(39, 51)
- 碗右点：(69, 51)

**path**（碗轮廓 + 填充）：
```xml
<!-- 碗填充（淡绿） -->
<path
  android:fillColor="#E8F5E9"
  android:pathData="M39,51 A15,15 0 0 1 69,51 Z" />

<!-- 碗描边（深绿，2.5dp round cap） -->
<path
  android:strokeColor="#1B5E20"
  android:strokeWidth="2.5"
  android:strokeLineCap="round"
  android:fillColor="#00000000"
  android:pathData="M39,51 A15,15 0 0 1 69,51 Z" />
```

**说明**：
- `A15,15 0 0 1 69,51` 顺时针短弧到右点（sweep=1 = 下方半圆 = 碗底）
- `Z` 闭合（flat top = 碗口）
- 描边 + 填充分两个 path，避免 Android vector 描边+填充同色冲突

#### 2.4.3 碗内三粒米粒

**几何**：3 个小圆点 r=1.2dp，碗内朝上三角排列（2 下 1 上，重心略偏下避免贴碗口）

- 左下米粒：圆心 (47, 60)
- 右下米粒：圆心 (61, 60)
- 中上米粒：圆心 (54, 55)

**path**（3 个圆，淡黄填充）：
```xml
<path
  android:fillColor="#FFF59D"
  android:pathData="M47,60 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0
                    M61,60 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0
                    M54,55 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0" />
```

**说明**：
- 圆画法 `M cx,cy m -r,0 a r,r 0 1,0 2r,0 a r,r 0 1,0 -2r,0`（先移到圆心，再相对移到左侧 r 处画两个半弧）
- path 中 `M cx,cy` = 圆心坐标，与文字描述一致
- 米粒 y 范围 53.8-61.2，距碗口 y=51 2.8dp，距碗底 y=66 4.8dp，重心平衡

#### 2.4.4 右上飘出叶子

**几何**：叶子从碗口右点 (69,51) 生出，叶尖到 (80,40)，呈 45° 上扬

叶子是水滴形（圆滑尖角），用两条贝塞尔曲线组合：
- 起点（叶柄）：(69, 51)（碗口右端，与碗 path 终点重合）
- 叶尖：(80, 40)
- 叶宽：最宽处约 4dp，在叶子中部

**path**（叶子填充主绿）：
```xml
<path
  android:fillColor="#2E7D32"
  android:pathData="M69,51 C66,48 66,42 80,40 C78,46 74,50 69,51 Z" />
```

**说明**：
- `M69,51` 叶柄起点（碗口右端）
- `C66,48 66,42 80,40` 第一条贝塞尔：叶柄→叶尖左侧弧线（叶面凸出）
- `C78,46 74,50 69,51` 第二条贝塞尔：叶尖→叶柄右侧弧线（叶背稍直）
- `Z` 闭合
- 叶尖 (80,40) 在安全区（半径 33，距中心 33.24）边缘内
- 叶子呈水滴形，左侧弧线稍凸（叶面），右侧弧线稍直（叶背）

### 2.5 monochrome 兼容（Android 13+ 主题图标）

`mipmap-anydpi-v26/ic_launcher.xml` 的 `<monochrome>` 引用 `ic_launcher_foreground`，系统染色时：
- 白底被忽略（alpha 0）
- 碗描边 + 碗填充 + 叶子 + 米粒的 alpha 通道被染色
- 染色后：碗描边（深）+ 碗填充（淡）+ 叶子（深）+ 米粒（深）层次仍可识别

**注意**：渐变背景在 monochrome 模式下被忽略（系统用单色染色），这是 Android 13+ 标准行为，可接受。

### 2.6 PNG fallback 重新生成

5 个密度（mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi）的 `ic_launcher.png` + `ic_launcher_round.png` 需重新生成：
- 用 Android Asset Studio 或 Inkscape 从 vector 渲染
- 尺寸：48×48（mdpi）→ 192×192（xxxhdpi）
- 圆角图标 `ic_launcher_round.png`：圆形裁剪

## 3. 实施步骤

### 3.1 文件修改

| 文件 | 修改 |
|------|------|
| `android/app/src/main/res/values/colors.xml` | 新增 4 个颜色定义 |
| `android/app/src/main/res/drawable/ic_launcher_background.xml` | 改为径向渐变 |
| `android/app/src/main/res/drawable/ic_launcher_foreground.xml` | 重写：碗+叶子+米粒 |
| `android/app/src/main/res/mipmap-{密度}/ic_launcher.png` | 重新生成 5 个密度 |
| `android/app/src/main/res/mipmap-{密度}/ic_launcher_round.png` | 重新生成 5 个密度 |

### 3.2 colors.xml 新增

```xml
<color name="ic_launcher_background_center">#FFFFFF</color>
<color name="ic_launcher_background_edge">#F1F8E9</color>
<color name="ic_launcher_bowl_stroke">#1B5E20</color>
<color name="ic_launcher_bowl_fill">#E8F5E9</color>
<color name="ic_launcher_leaf">#2E7D32</color>
<color name="ic_launcher_rice">#FFF59D</color>
```

### 3.3 测试更新

`test/icon_assets_test.dart` 断言更新：
- colors.xml 含 6 个新颜色定义
- ic_launcher_background.xml 含 `<gradient` + radial 类型
- ic_launcher_foreground.xml 含碗描边 path + 碗填充 path + 米粒 path + 叶子 path
- 旧 M25 几何（`M26,54` 圆环 + `M43,48.5` 实心碗）不应存在

### 3.4 PNG 重新生成

沙箱无 Android Asset Studio / Inkscape，明确用 Python + CairoSVG 渲染：

1. 安装依赖：`pip install cairosvg pillow`
2. 合成 SVG：把 `ic_launcher_background.xml` 的渐变 + `ic_launcher_foreground.xml` 的 4 个 path 合并成 108×108 SVG（Android vector 命令映射到 SVG path 命令基本一致，注意 `<aapt:attr>` 嵌套渐变需转为 SVG `<defs><radialGradient>`）
3. 渲染 5 个密度 PNG：
   - mdpi 48×48 / hdpi 72×72 / xhdpi 96×96 / xxhdpi 144×144 / xxxhdpi 192×192
   - 命令：`cairosvg.svg2png(bytestring=svg_bytes, output_width=size, output_height=size, output_path=path)`
4. 圆角版 `ic_launcher_round.png`：用 Pillow 画圆形 mask，alpha 合成裁剪

## 4. 验证

- `flutter analyze` No issues
- `flutter test` 全量通过（更新 icon_assets_test 断言）
- 6+1 硬约束满足（图标修改不影响 build.gradle / meal_log / AI 三路径等）
- 视觉验证：PNG 渲染后肉眼检查精致度（沙箱限制，只能验证文件存在+尺寸）

## 5. 版本

- **版本号**：0.28.0+40 → 0.29.0+41
- **CHANGELOG**：M26 图标精修
- **tag**：v0.29.0
- **发版**：push + tag + GitHub Release

## 6. 演进史

| 版本 | 设计 |
|------|------|
| M15 | 餐叉+餐刀+暖橙纯色 |
| M17 | 同心圆环+紫橙渐变 |
| M20 | 苹果圆+扫描线+紫橙渐变（Google Lens 风） |
| M22 | 白底紫前景+碗剪影+四角L |
| M25 | 白底自然绿+圆环描边盘+实心碗（对标 MFP） |
| **M26** | **径向渐变背景+描边碗+米粒+叶子（自然×食物）** |
