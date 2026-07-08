# M27 图标重设计：碗+萌芽 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正 M26 图标碗颠倒（sweep-flag 写反）+ 叶子突兀问题，重设计为"碗+茎+双叶萌芽"构图，精致打磨。

**Architecture:** 修改 `ic_launcher_foreground.xml`（碗 sweep 1→0 + 米粒 3→2 + 删除飘叶 + 新增茎+顶叶+侧叶）+ `colors.xml` 加侧叶色 + 重写 `render_icon_png.py`（M15 叉刀 → cairosvg 从 XML 渲染）+ 更新 `icon_assets_test.dart` 断言 + bump v0.33.0+46 + CHANGELOG/HANDOFF。

**Tech Stack:** Android vector drawable / cairosvg + Pillow（PNG 渲染）/ Flutter test

---

## 文件结构

### 修改文件
- `android/app/src/main/res/drawable/ic_launcher_foreground.xml` — 碗 sweep 修正 + 茎+双叶+2粒米
- `android/app/src/main/res/values/colors.xml` — 新增 `ic_launcher_leaf_side` `#388E3C`
- `scripts/render_icon_png.py` — 重写为 cairosvg 从 XML 渲染（M15 叉刀 → M27 碗+萌芽）
- `test/icon_assets_test.dart` — 断言更新为 M27 几何
- `pubspec.yaml` — version `0.32.0+45` → `0.33.0+46`
- `CHANGELOG.md` — 新增 `[v0.33.0]` 段落
- `HANDOFF.md` — 当前版本 + 当前状态同步

### 不变文件
- `android/app/src/main/res/drawable/ic_launcher_background.xml`（径向渐变保留）
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`（adaptive-icon 引用不变）
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml`（同上）
- `android/app/src/main/AndroidManifest.xml`（roundIcon 声明不变）

---

## Task 1: colors.xml 新增侧叶色

**Files:**
- Modify: `android/app/src/main/res/values/colors.xml`

- [ ] **Step 1: 在 `ic_launcher_leaf` 后新增 `ic_launcher_leaf_side`**

用 Edit 工具，在 `colors.xml` 的 `ic_launcher_leaf` 行后新增侧叶色：

旧：
```xml
    <color name="ic_launcher_leaf">#2E7D32</color>
    <color name="ic_launcher_rice">#FFF59D</color>
```

新：
```xml
    <color name="ic_launcher_leaf">#2E7D32</color>
    <color name="ic_launcher_leaf_side">#388E3C</color>
    <color name="ic_launcher_rice">#FFF59D</color>
```

同时更新 `ic_launcher_leaf` 行后的注释说明（如有的话），保持注释与代码一致。M26 注释块最后加一行说明 M27 新增侧叶色。

- [ ] **Step 2: 验证 colors.xml 内容**

Read `colors.xml` 确认新增行存在且色值正确 `#388E3C`（Green 600）。

---

## Task 2: ic_launcher_foreground.xml 重写（碗+萌芽）

**Files:**
- Modify: `android/app/src/main/res/drawable/ic_launcher_foreground.xml`

- [ ] **Step 1: 用 Write 工具整体重写 foreground.xml**

完整新内容：

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
  自适应图标前景：碗 + 茎 + 双叶萌芽 + 2 粒米（M27 重设计）。

  设计理念（M27 用户决策：修正 M26 碗颠倒 + 叶子突兀，碗+萌芽=食物×成长）：
  - 描边碗+内部填充 = 容器（深绿描边 + 淡绿填充，碗口朝上修正 sweep-flag）
  - 2 粒米粒 = 食物（淡黄，碗底对称，让位萌芽焦点）
  - 茎 = 生命（主绿，从碗中央底部向上生长，比碗描边细 1dp）
  - 顶叶 + 侧叶 = 萌芽（主绿顶叶右上 + 中绿侧叶左上，左右对称层次区分）
  - 语义：碗(食物) + 萌芽双叶(健康/成长) = 健康饮食的生命力意象

  画布 108×108dp，安全区 66×66（中心 54,54，半径 33）。
  M27 几何：
  - 碗：30×15dp，碗口 y=51 朝上，碗底 y=66 朝下（sweep=0 修正 M26 的 sweep=1 颠倒）
    碗左点 (39,51) 碗右点 (69,51)，A15,15 半径 15 逆时针短弧 sweep=0
  - 米粒：r=1.2dp，2 粒碗底对称
    左 (50,61) 右 (58,61)
  - 茎：直线 (54,61)→(54,38)，高 23dp，1.5dp round cap
  - 顶叶：水滴形，叶柄 (54,38) 叶尖 (62,30)，右上 30°
    C52,35 52,31 62,30 + C60,34 57,37 54,38
  - 侧叶：水滴形，叶柄 (54,46) 叶尖 (46,38)，左上 30°
    C52,43 52,39 46,38 + C48,42 51,45 54,46

  配色层次（5 色 + 渐变 vs M26 的 4 色）：
  - 碗描边 #1B5E20（Green 900）→ 重量最高
  - 碗填充 #E8F5E9（Green 50）→ 中等重量
  - 茎+顶叶 #2E7D32（Green 800）→ 重量高（焦点）
  - 侧叶 #388E3C（Green 600）→ 中等（副焦点，比顶叶浅一阶）
  - 米粒 #FFF59D（Amber 200）→ 食物语义对比色

  monochrome 兼容（Android 13+ 主题图标）：
  - 系统染色时背景渐变被忽略，前景各 path 的 alpha 通道被染色
  - 茎+双叶+碗描边+碗填充+米粒 在染色后层次仍可识别（实心>描边重量）

  M26 描边碗+米粒+右上飘叶 → M27 描边碗+米粒+茎+双叶萌芽（修正颠倒 + 叶子归位）
-->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">

    <!-- 碗填充（淡绿 #E8F5E9，30×15dp，sweep=0 修正朝上）：
         M39,51 左点（碗口左端）
         A15,15 0 0 0 69,51 逆时针短弧到右点（sweep=0 = 下方半圆 = 碗底，y-down 坐标系）
         Z 闭合（flat top = 碗口朝上） -->
    <path
        android:fillColor="@color/ic_launcher_bowl_fill"
        android:pathData="M39,51 A15,15 0 0 0 69,51 Z" />

    <!-- 碗描边（深绿 #1B5E20，2.5dp round cap，无填充） -->
    <path
        android:strokeColor="@color/ic_launcher_bowl_stroke"
        android:strokeWidth="2.5"
        android:strokeLineCap="round"
        android:fillColor="#00000000"
        android:pathData="M39,51 A15,15 0 0 0 69,51 Z" />

    <!-- 2 粒米粒（淡黄 #FFF59D，r=1.2dp，碗底对称）：
         M50,61 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0  左米粒
         M58,61 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0  右米粒 -->
    <path
        android:fillColor="@color/ic_launcher_rice"
        android:pathData="M50,61 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0 M58,61 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0" />

    <!-- 茎（主绿 #2E7D32，1.5dp round cap，从碗内中央底部向上生长）：
         M54,61 起点（碗内底部中央，两粒米之间）
         L54,38 终点（碗口上方 13dp，茎高 23dp） -->
    <path
        android:strokeColor="@color/ic_launcher_leaf"
        android:strokeWidth="1.5"
        android:strokeLineCap="round"
        android:fillColor="#00000000"
        android:pathData="M54,61 L54,38" />

    <!-- 顶叶（主绿 #2E7D32，水滴形，茎尖右上 30°）：
         M54,38 叶柄起点（茎顶）
         C52,35 52,31 62,30 第一条贝塞尔：叶柄→叶尖左侧弧线（叶面凸出）
         C60,34 57,37 54,38 第二条贝塞尔：叶尖→叶柄右侧弧线（叶背稍直）
         Z 闭合 -->
    <path
        android:fillColor="@color/ic_launcher_leaf"
        android:pathData="M54,38 C52,35 52,31 62,30 C60,34 57,37 54,38 Z" />

    <!-- 侧叶（中绿 #388E3C，水滴形，茎中部左上 30°，比顶叶浅一阶）：
         M54,46 叶柄起点（茎中部）
         C52,43 52,39 46,38 第一条贝塞尔：叶柄→叶尖左侧弧线
         C48,42 51,45 54,46 第二条贝塞尔：叶尖→叶柄右侧弧线
         Z 闭合 -->
    <path
        android:fillColor="@color/ic_launcher_leaf_side"
        android:pathData="M54,46 C52,43 52,39 46,38 C48,42 51,45 54,46 Z" />
</vector>
```

- [ ] **Step 2: 用 cairosvg 渲染验证几何（像素采样）**

运行 Python 脚本验证关键像素（避免茎 x=54 干扰，用 x=44 验证碗朝向）：

```bash
cd /workspace && python3 << 'EOF'
import cairosvg
from PIL import Image
import io

# 从 colors.xml 读色值
colors = {
    'bowl_fill': '#E8F5E9', 'bowl_stroke': '#1B5E20',
    'leaf': '#2E7D32', 'leaf_side': '#388E3C', 'rice': '#FFF59D',
    'bg_center': '#FFFFFF', 'bg_edge': '#F1F8E9',
}

svg = f'''<svg viewBox="0 0 108 108" xmlns="http://www.w3.org/2000/svg" width="432" height="432">
  <defs>
    <radialGradient id="bg" cx="54" cy="54" r="54" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="{colors["bg_center"]}"/>
      <stop offset="100%" stop-color="{colors["bg_edge"]}"/>
    </radialGradient>
  </defs>
  <rect width="108" height="108" fill="url(#bg)"/>
  <path d="M39,51 A15,15 0 0 0 69,51 Z" fill="{colors["bowl_fill"]}"/>
  <path d="M39,51 A15,15 0 0 0 69,51 Z" fill="none" stroke="{colors["bowl_stroke"]}" stroke-width="2.5" stroke-linecap="round"/>
  <path d="M50,61 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0 M58,61 m-1.2,0 a1.2,1.2 0 1,0 2.4,0 a1.2,1.2 0 1,0 -2.4,0" fill="{colors["rice"]}"/>
  <line x1="54" y1="61" x2="54" y2="38" stroke="{colors["leaf"]}" stroke-width="1.5" stroke-linecap="round"/>
  <path d="M54,38 C52,35 52,31 62,30 C60,34 57,37 54,38 Z" fill="{colors["leaf"]}"/>
  <path d="M54,46 C52,43 52,39 46,38 C48,42 51,45 54,46 Z" fill="{colors["leaf_side"]}"/>
</svg>'''
png_bytes = cairosvg.svg2png(bytestring=svg.encode(), output_width=432, output_height=432)
img = Image.open(io.BytesIO(png_bytes)).convert('RGBA')
def px(x, y): return img.getpixel((int(x*4), int(y*4)))

# 碗朝向（x=44 避开茎 x=54）
assert px(44,45) > (240,240,240,255)[:3], f'碗口上方应为背景, got {px(44,45)}'
assert px(44,51)[0] < 60, f'碗口描边应为深绿, got {px(44,51)}'
assert px(44,58) == (232,245,233,255), f'碗内应为填充淡绿, got {px(44,58)}'
assert px(44,68) > (240,240,240,255)[:3], f'碗底下应为背景, got {px(44,68)}'
# 茎
assert px(54,50) == (46,125,50,255), f'茎应为主绿, got {px(54,50)}'
# 顶叶
assert px(57,34) == (46,125,50,255), f'顶叶应为主绿, got {px(57,34)}'
# 侧叶
assert px(49,42) == (56,142,60,255), f'侧叶应为中绿, got {px(49,42)}'
# 米粒
assert px(50,61) == (255,245,157,255), f'左米粒应为淡黄, got {px(50,61)}'
assert px(58,61) == (255,245,157,255), f'右米粒应为淡黄, got {px(58,61)}'
print('✓ M27 几何像素验证全部通过（碗口朝上 + 茎 + 双叶 + 2粒米）')
EOF
```

预期输出：`✓ M27 几何像素验证全部通过（碗口朝上 + 茎 + 双叶 + 2粒米）`

- [ ] **Step 3: 提交**

```bash
git add android/app/src/main/res/values/colors.xml android/app/src/main/res/drawable/ic_launcher_foreground.xml
git commit -m "$(cat <<'EOF'
feat(M27): 图标重设计碗+萌芽（修正碗颠倒 + 叶子归位）

- colors.xml: 新增 ic_launcher_leaf_side #388E3C（侧叶 Green 600）
- ic_launcher_foreground.xml:
  - 碗 sweep-flag 1→0（修正 M26 碗口朝上，M26 sweep=1 在 y-down 实际朝下）
  - 米粒 3→2 粒（让位萌芽焦点，碗底对称 (50,61)+(58,61)）
  - 删除 M26 右上飘叶（(69,51)→(80,40) 突兀无连接）
  - 新增茎（(54,61)→(54,38) 主绿 1.5dp，从碗中央底部向上生长）
  - 新增顶叶（(54,38)→(62,30) 主绿，茎尖右上 30°）
  - 新增侧叶（(54,46)→(46,38) 中绿，茎中部左上 30°，比顶叶浅一阶）

语义升级：碗(食物)+萌芽双叶(健康/成长)=健康饮食生命力
cairosvg 像素采样验证：碗口朝上/碗底朝下/茎/双叶/米粒全部正确
EOF
)"
```

---

## Task 3: 重写 render_icon_png.py（cairosvg 从 XML 渲染）

**Files:**
- Modify: `scripts/render_icon_png.py`

- [ ] **Step 1: 用 Write 工具整体重写 render_icon_png.py**

完整新内容（用 cairosvg 从 XML 渲染，避免脚本与 XML 脱节）：

```python
#!/usr/bin/env python3
"""
从 ic_launcher_foreground.xml + ic_launcher_background.xml 渲染 PNG fallback。
5 个密度：mdpi 48 / hdpi 72 / xhdpi 96 / xxhdpi 144 / xxxhdpi 192
2 个版本：ic_launcher.png（方形）+ ic_launcher_round.png（圆形蒙版）

M27：用 cairosvg 从 Android vector XML 渲染（替代 M15 叉刀硬编码几何）。
流程：读 colors.xml 解析 @color 引用 → 转 XML 为 SVG → cairosvg 渲染 → PIL 缩放。
"""
import os
import re
import io
import cairosvg
from PIL import Image

RES_DIR = 'android/app/src/main/res'
DENSITIES = {
    'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192,
}


def parse_colors(xml_path):
    """读 values/colors.xml，返回 {name: '#RRGGBB'} 字典。"""
    with open(xml_path, 'r', encoding='utf-8') as f:
        content = f.read()
    colors = {}
    for m in re.finditer(r'<color name="([^"]+)">(#[0-9A-Fa-f]{6,8})</color>', content):
        colors[m.group(1)] = m.group(2)
    return colors


def resolve_color(value, colors):
    """@color/xxx → 实际色值，已是 #xxx 直接返回。"""
    if value.startswith('@color/'):
        name = value[len('@color/'):]
        return colors.get(name, '#000000')
    return value


def xml_to_svg(xml_path, colors, is_background=False):
    """读 Android vector XML，转为等价 SVG 字符串（108×108 viewBox）。
    处理：@color 引用、<aapt:attr> 内联渐变、pathData。
    """
    with open(xml_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 处理 <aapt:attr name="android:fillColor"><gradient .../></aapt:attr>
    # 转 SVG <defs><radialGradient/></defs> + fill="url(#id)"
    gradient_match = re.search(
        r'<aapt:attr name="android:fillColor">\s*'
        r'<gradient\s+android:type="radial"\s+'
        r'android:centerX="([^"]+)"\s+'
        r'android:centerY="([^"]+)"\s+'
        r'android:gradientRadius="([^"]+)"\s+'
        r'android:startColor="([^"]+)"\s+'
        r'android:endColor="([^"]+)"\s*/>',
        content)
    gradient_def = ''
    fill_attr = ''
    if gradient_match:
        cx, cy, r, start, end = gradient_match.groups()
        start = resolve_color(start, colors)
        end = resolve_color(end, colors)
        gradient_def = (
            f'<defs><radialGradient id="bg" cx="{cx}" cy="{cy}" r="{r}" '
            f'gradientUnits="userSpaceOnUse">'
            f'<stop offset="0%" stop-color="{start}"/>'
            f'<stop offset="100%" stop-color="{end}"/>'
            f'</radialGradient></defs>'
        )
        fill_attr = 'fill="url(#bg)"'

    # 提取所有 <path> 的属性
    paths = []
    for pm in re.finditer(r'<path\s+([^/]*?)/>', content, re.DOTALL):
        attrs_str = pm.group(1)
        attrs = {}
        for am in re.finditer(r'android:(\w+)="([^"]+)"', attrs_str):
            attrs[am.group(1)] = am.group(2)
        paths.append(attrs)

    # 构建 SVG
    svg_parts = [f'<svg viewBox="0 0 108 108" xmlns="http://www.w3.org/2000/svg" width="432" height="432">']
    if gradient_def:
        svg_parts.append(gradient_def)

    for attrs in paths:
        path_data = attrs.get('pathData', '')
        fill = attrs.get('fillColor', '#000000')
        if fill == '#00000000':
            fill = 'none'
        else:
            fill = resolve_color(fill, colors)

        # 如果是渐变填充的背景 path
        if not path_data and fill_attr and is_background:
            svg_parts.append(
                f'<path d="M0,0 h108 v108 h-108 z" {fill_attr}/>'
            )
            continue

        stroke = attrs.get('strokeColor')
        if stroke:
            stroke = resolve_color(stroke, colors)
        stroke_width = attrs.get('strokeWidth', '0')
        stroke_linecap = attrs.get('strokeLineCap', 'butt')

        path_attrs = [f'd="{path_data}"', f'fill="{fill}"']
        if stroke:
            path_attrs.append(f'stroke="{stroke}"')
            path_attrs.append(f'stroke-width="{stroke_width}"')
            path_attrs.append(f'stroke-linecap="{stroke_linecap}"')

        svg_parts.append(f'<path {" ".join(path_attrs)}/>')

    svg_parts.append('</svg>')
    return '\n'.join(svg_parts)


def render_at_size(svg_str, size, circular=False):
    """cairosvg 渲染 432×432 → PIL 缩放到目标 size。"""
    png_bytes = cairosvg.svg2png(bytestring=svg_str.encode('utf-8'),
                                 output_width=432, output_height=432)
    img = Image.open(io.BytesIO(png_bytes)).convert('RGBA')
    if circular:
        mask = Image.new('L', (432, 432), 0)
        ImageDraw = ImageDraw = __import__('PIL.ImageDraw', fromlist=['ImageDraw']).ImageDraw
        ImageDraw.Draw(mask).ellipse([0, 0, 432, 432], fill=255)
        circular_img = Image.new('RGBA', (432, 432), (0, 0, 0, 0))
        circular_img.paste(img, (0, 0), mask)
        img = circular_img
    return img.resize((size, size), Image.LANCZOS)


def main():
    colors = parse_colors(f'{RES_DIR}/values/colors.xml')
    bg_svg = xml_to_svg(f'{RES_DIR}/drawable/ic_launcher_background.xml',
                        colors, is_background=True)
    fg_svg = xml_to_svg(f'{RES_DIR}/drawable/ic_launcher_foreground.xml',
                        colors, is_background=False)

    # 先渲染 432×432 两层用于合成
    bg_png = cairosvg.svg2png(bytestring=bg_svg.encode('utf-8'),
                              output_width=432, output_height=432)
    fg_png = cairosvg.svg2png(bytestring=fg_svg.encode('utf-8'),
                              output_width=432, output_height=432)
    bg_img = Image.open(io.BytesIO(bg_png)).convert('RGBA')
    fg_img = Image.open(io.BytesIO(fg_png)).convert('RGBA')
    # 合成：背景在下，前景在上
    combined = Image.alpha_composite(bg_img, fg_img)

    for density, size in DENSITIES.items():
        out_dir = f'{RES_DIR}/mipmap-{density}'
        os.makedirs(out_dir, exist_ok=True)
        # 方形
        square = combined.resize((size, size), Image.LANCZOS)
        square.save(f'{out_dir}/ic_launcher.png', 'PNG')
        # 圆形
        mask = Image.new('L', (432, 432), 0)
        from PIL import ImageDraw
        ImageDraw.Draw(mask).ellipse([0, 0, 432, 432], fill=255)
        circular = Image.new('RGBA', (432, 432), (0, 0, 0, 0))
        circular.paste(combined, (0, 0), mask)
        circular.resize((size, size), Image.LANCZOS).save(
            f'{out_dir}/ic_launcher_round.png', 'PNG')
        print(f'  {density}: {size}x{size}')


if __name__ == '__main__':
    main()
```

- [ ] **Step 2: 运行脚本生成 5 密度 PNG**

```bash
cd /workspace && python3 scripts/render_icon_png.py
```

预期输出：
```
  mdpi: 48x48
  hdpi: 72x72
  xhdpi: 96x96
  xxhdpi: 144x144
  xxxhdpi: 192x192
```

- [ ] **Step 3: 像素采样验证生成的 xxxhdpi PNG**

```bash
cd /workspace && python3 << 'EOF'
from PIL import Image
img = Image.open('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png').convert('RGBA')
w, h = img.size
assert w == 192 and h == 192, f'size mismatch: {w}x{h}'
# 192 = 108 * 16/9，坐标按比例：x_108 * 192/108 = x_108 * 16/9
def px(x108, y108):
    return img.getpixel((int(x108 * 192/108), int(y108 * 192/108)))

# 验证碗口朝上（避开茎 x=54，用 x=44）
assert px(44, 45)[0] > 240, f'碗口上方应为背景, got {px(44,45)}'
assert px(44, 51)[0] < 60, f'碗口描边应为深绿, got {px(44,51)}'
assert px(44, 68)[0] > 240, f'碗底下应为背景, got {px(44,68)}'
# 验证茎
assert px(54, 50) == (46, 125, 50, 255), f'茎应为主绿, got {px(54,50)}'
# 验证顶叶
assert px(57, 34) == (46, 125, 50, 255), f'顶叶应为主绿, got {px(57,34)}'
# 验证侧叶
assert px(49, 42) == (56, 142, 60, 255), f'侧叶应为中绿, got {px(49,42)}'
# 验证米粒
assert px(50, 61) == (255, 245, 157, 255), f'左米粒应为淡黄, got {px(50,61)}'
print('✓ 5 密度 PNG 渲染正确（xxxhdpi 采样通过）')
EOF
```

预期输出：`✓ 5 密度 PNG 渲染正确（xxxhdpi 采样通过）`

- [ ] **Step 4: 提交**

```bash
git add scripts/render_icon_png.py android/app/src/main/res/mipmap-mdpi/ic_launcher.png android/app/src/main/res/mipmap-mdpi/ic_launcher_round.png android/app/src/main/res/mipmap-hdpi/ic_launcher.png android/app/src/main/res/mipmap-hdpi/ic_launcher_round.png android/app/src/main/res/mipmap-xhdpi/ic_launcher.png android/app/src/main/res/mipmap-xhdpi/ic_launcher_round.png android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png android/app/src/main/res/mipmap-xxhdpi/ic_launcher_round.png android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png
git commit -m "$(cat <<'EOF'
chore(M27): 重写 render_icon_png.py 用 cairosvg 从 XML 渲染

- scripts/render_icon_png.py: M15 叉刀硬编码几何 → cairosvg 从 ic_launcher_*.xml 渲染
  - 解析 values/colors.xml @color 引用 → 实际色值
  - <aapt:attr> 内联渐变 → SVG <defs><radialGradient>
  - 背景层+前景层合成 → 5 密度 PNG + 圆形蒙版
- 重新生成 5 密度 ic_launcher.png + ic_launcher_round.png（M27 碗+萌芽）
- 像素采样验证 xxxhdpi：碗口朝上/茎/双叶/米粒全部正确
EOF
)"
```

---

## Task 4: 更新 icon_assets_test.dart 断言（M27）

**Files:**
- Modify: `test/icon_assets_test.dart`

- [ ] **Step 1: 用 Write 工具整体重写 test/icon_assets_test.dart**

完整新内容（更新断言为 M27 几何）：

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 验证 Android 图标资源完整性
///
/// 历史：M15 餐叉+餐刀+暖橙纯色 → M17 同心圆环+紫橙渐变 → M20 Google Lens 风
/// （四角 L+苹果圆+扫描线+紫橙渐变）→ M22 白底紫前景反转+精修取景框+碗剪影
/// → M25 白底自然绿前景+圆环描边盘+实心碗（对标 MyFitnessPal）
/// → M26 径向渐变背景+描边碗+米粒+右上飘出叶子（精致美丽，但有碗颠倒 bug）
/// → M27 径向渐变背景+描边碗+米粒+茎+双叶萌芽（修正颠倒 + 叶子归位 + 生命力语义）
/// 测试断言随设计演进更新，确保资源文件与设计意图保持一致。
void main() {
  group('图标资源完整性 (M27)', () {
    const androidResDir = 'android/app/src/main/res';

    test('colors.xml 含 M27 七色配色定义', () {
      final file = File('$androidResDir/values/colors.xml');
      final content = file.readAsStringSync();
      // M26 保留 6 色
      expect(
        content,
        contains('<color name="ic_launcher_background_center">#FFFFFF</color>'),
        reason: 'M26 背景中心白（径向渐变中心）',
      );
      expect(
        content,
        contains('<color name="ic_launcher_background_edge">#F1F8E9</color>'),
        reason: 'M26 背景边缘 Light Green 50（径向渐变边缘）',
      );
      expect(
        content,
        contains('<color name="ic_launcher_bowl_stroke">#1B5E20</color>'),
        reason: 'M26 碗描边 Green 900（深绿比主色深一阶）',
      );
      expect(
        content,
        contains('<color name="ic_launcher_bowl_fill">#E8F5E9</color>'),
        reason: 'M26 碗填充 Green 50（淡绿）',
      );
      expect(
        content,
        contains('<color name="ic_launcher_leaf">#2E7D32</color>'),
        reason: 'M26/M27 茎+顶叶 Green 800（主绿）',
      );
      expect(
        content,
        contains('<color name="ic_launcher_rice">#FFF59D</color>'),
        reason: 'M26 米粒 Amber 200（淡黄食物语义）',
      );
      // M27 新增侧叶色
      expect(
        content,
        contains('<color name="ic_launcher_leaf_side">#388E3C</color>'),
        reason: 'M27 侧叶 Green 600（比顶叶浅一阶，层次区分）',
      );
    });

    test('ic_launcher_background.xml 含径向渐变（M26 保留）', () {
      final file = File('$androidResDir/drawable/ic_launcher_background.xml');
      final content = file.readAsStringSync();
      expect(content, contains('<gradient'),
          reason: 'M26 背景应含 <gradient> 标签');
      expect(content, contains('android:type="radial"'),
          reason: 'M26 渐变类型 radial（径向）');
      expect(content, contains('android:centerX="54"'),
          reason: 'M26 渐变中心 X=54（画布中心）');
      expect(content, contains('android:centerY="54"'),
          reason: 'M26 渐变中心 Y=54（画布中心）');
      expect(content, contains('android:gradientRadius="54"'),
          reason: 'M26 渐变半径 54dp');
      expect(content, contains('@color/ic_launcher_background_center'),
          reason: 'M26 引用背景中心色');
      expect(content, contains('@color/ic_launcher_background_edge'),
          reason: 'M26 引用背景边缘色');
    });

    test('ic_launcher_foreground.xml 含碗+茎+双叶+2粒米（M27 重设计）', () {
      final file = File('$androidResDir/drawable/ic_launcher_foreground.xml');
      final content = file.readAsStringSync();
      // M27 碗几何：M39,51 A15,15 0 0 0（sweep=0 修正 M26 的 sweep=1 颠倒）
      expect(
        content,
        contains('M39,51 A15,15 0 0 0 69,51'),
        reason: 'M27 碗 path sweep=0（碗口朝上，修正 M26 sweep=1 颠倒）',
      );
      // M27 米粒几何：2 粒碗底对称 M50,61 + M58,61
      expect(
        content,
        contains('M50,61 m-1.2,0'),
        reason: 'M27 左米粒圆心 (50,61)，r=1.2dp',
      );
      expect(
        content,
        contains('M58,61 m-1.2,0'),
        reason: 'M27 右米粒圆心 (58,61)，r=1.2dp',
      );
      // M27 茎几何：M54,61 L54,38（直线从碗内底部到碗口上方）
      expect(
        content,
        contains('M54,61 L54,38'),
        reason: 'M27 茎 path：起点 (54,61) 碗内底部 → 终点 (54,38) 碗口上方',
      );
      // M27 顶叶几何：M54,38 C52,35 52,31 62,30（茎尖右上 30°）
      expect(
        content,
        contains('M54,38 C52,35 52,31 62,30'),
        reason: 'M27 顶叶 path：叶柄 (54,38) → 叶尖 (62,30) 右上 30°',
      );
      // M27 侧叶几何：M54,46 C52,43 52,39 46,38（茎中部左上 30°）
      expect(
        content,
        contains('M54,46 C52,43 52,39 46,38'),
        reason: 'M27 侧叶 path：叶柄 (54,46) → 叶尖 (46,38) 左上 30°',
      );
      // M27 五色引用
      expect(content, contains('@color/ic_launcher_bowl_fill'),
          reason: 'M27 碗填充引用淡绿');
      expect(content, contains('@color/ic_launcher_bowl_stroke'),
          reason: 'M27 碗描边引用深绿');
      expect(content, contains('@color/ic_launcher_rice'),
          reason: 'M27 米粒引用淡黄');
      expect(content, contains('@color/ic_launcher_leaf'),
          reason: 'M27 茎+顶叶引用主绿');
      expect(content, contains('@color/ic_launcher_leaf_side'),
          reason: 'M27 侧叶引用中绿（M27 新增）');
      // M26 旧几何不应存在
      expect(
        content,
        isNot(contains('A15,15 0 0 1 69,51')),
        reason: 'M26 碗 sweep=1（颠倒）应被 M27 sweep=0 替换',
      );
      expect(
        content,
        isNot(contains('M69,51 C66,48 66,42 80,40')),
        reason: 'M26 右上飘叶 path 应被 M27 茎+双叶替换',
      );
      // M25 旧几何不应存在
      expect(content, isNot(contains('M26,54')),
          reason: 'M25 圆环盘 M26,54 应不存在');
      expect(content, isNot(contains('M43,48.5')),
          reason: 'M25 实心碗 M43,48.5 应不存在');
      // M22 旧几何不应存在
      expect(content, isNot(contains('M36,36')),
          reason: 'M22 四角 L 起点 M36,36 应不存在');
      // M20 旧几何不应存在
      expect(content, isNot(contains('M33,54')),
          reason: 'M20 扫描线 M33,54 应不存在');
    });

    test('mipmap-anydpi-v26/ic_launcher_round.xml 存在且引用正确', () {
      final file =
          File('$androidResDir/mipmap-anydpi-v26/ic_launcher_round.xml');
      expect(file.existsSync(), true, reason: '圆角 adaptive-icon 应存在');
      final content = file.readAsStringSync();
      expect(content,
          contains('<background android:drawable="@drawable/ic_launcher_background" />'));
      expect(content,
          contains('<foreground android:drawable="@drawable/ic_launcher_foreground" />'));
      expect(content,
          contains('<monochrome android:drawable="@drawable/ic_launcher_foreground" />'));
    });

    test('AndroidManifest.xml 含 android:roundIcon 声明', () {
      final file = File('android/app/src/main/AndroidManifest.xml');
      final content = file.readAsStringSync();
      expect(
        content,
        contains('android:roundIcon="@mipmap/ic_launcher_round"'),
        reason: 'AndroidManifest 应声明 android:roundIcon（部分启动器需要）',
      );
    });

    test('5 个 mipmap 密度都有 ic_launcher.png 和 ic_launcher_round.png', () {
      const densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
      for (final d in densities) {
        final png = File('$androidResDir/mipmap-$d/ic_launcher.png');
        expect(
          png.existsSync(),
          true,
          reason: 'mipmap-$d/ic_launcher.png 应存在（方形图标 PNG fallback）',
        );
        final pngRound =
            File('$androidResDir/mipmap-$d/ic_launcher_round.png');
        expect(
          pngRound.existsSync(),
          true,
          reason: 'mipmap-$d/ic_launcher_round.png 应存在（圆角图标 PNG fallback）',
        );
      }
    });
  });
}
```

- [ ] **Step 2: 运行测试验证通过**

```bash
cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test test/icon_assets_test.dart
```

预期：所有测试 PASS。

- [ ] **Step 3: 提交**

```bash
git add test/icon_assets_test.dart
git commit -m "test(M27): icon_assets_test 断言更新为 M27 几何（碗 sweep=0/茎/双叶/2粒米）"
```

---

## Task 5: 全量验证 + flutter analyze

**Files:** 无文件改动

- [ ] **Step 1: flutter analyze**

```bash
cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter analyze 2>&1 | tail -3
```

预期：`No issues found!`

- [ ] **Step 2: flutter test 全量**

```bash
cd /workspace && export PATH=/tmp/flutter/bin:$PATH && flutter test 2>&1 | tail -5
```

预期：1172+ passed / 3 skipped / 0 failed（基线 1172 + icon_assets_test 改动不增减数量，0 回归）。

- [ ] **Step 3: 6+1 硬约束核查**

```bash
cd /workspace && git diff HEAD~3 --stat -- android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml
```

预期：无输出（本次未触碰 build.gradle.kts / AndroidManifest.xml）。

- [ ] **Step 4: 无需提交（验证步骤）**

本 Task 无文件改动，跳过提交。

---

## Task 6: bump v0.33.0+46 + CHANGELOG + HANDOFF

**Files:**
- Modify: `pubspec.yaml`
- Modify: `CHANGELOG.md`
- Modify: `HANDOFF.md`

- [ ] **Step 1: pubspec.yaml version bump**

用 Edit 工具改 `pubspec.yaml` 第 4 行：

旧：`version: 0.32.0+45`
新：`version: 0.33.0+46`

- [ ] **Step 2: CHANGELOG.md 新增 [v0.33.0] 段落**

用 Edit 工具，在 `## [Unreleased]` 和 `## [v0.32.0]` 之间插入：

```markdown
## [v0.33.0] - 2026-07-09

### M27 图标重设计：碗+萌芽（修正颠倒 + 叶子归位）

用户反馈 M26 图标"颠倒"+"叶子突兀"。根因：M26 碗 path `sweep-flag=1` 在 y-down 坐标系实际渲染为碗口朝下（注释判断错误）；右上飘叶与碗无视觉连接。

#### 改动
- `ic_launcher_foreground.xml`：
  - 碗 `sweep-flag` 1→0（修正颠倒，碗口朝上、碗底朝下）
  - 米粒 3→2 粒碗底对称（让位萌芽焦点）
  - 删除 M26 右上飘叶（突兀无连接）
  - 新增茎（碗中央底部→碗口上方，主绿 1.5dp）
  - 新增顶叶（茎尖右上 30°，主绿）
  - 新增侧叶（茎中部左上 30°，中绿 Green 600 比顶叶浅一阶）
- `colors.xml`：新增 `ic_launcher_leaf_side` `#388E3C`（侧叶色）
- `scripts/render_icon_png.py`：重写为 cairosvg 从 XML 渲染（替代 M15 叉刀硬编码）
- 重新生成 5 密度 PNG fallback

#### 语义升级
碗(食物) + 萌芽双叶(健康/成长) = 健康饮食的生命力意象（vs M26 碗+飘叶的自然×食物）

#### 验证
- cairosvg 像素采样：碗口朝上/碗底朝下/茎/顶叶/侧叶/2粒米全部正确
- flutter analyze No issues
- flutter test 1172 passed / 3 skipped / 0 failed（0 回归）
- 6+1 硬约束全部满足（未触碰 build.gradle.kts / AndroidManifest）

```

- [ ] **Step 3: HANDOFF.md 更新**

读 HANDOFF.md 第 1 节"当前版本"，将 `0.32.0+45` 更新为 `0.33.0+46`。

读 HANDOFF.md 第 2 节"当前状态"，在 v0.32.0 描述后新增 v0.33.0 描述段落：

```markdown
### v0.33.0（2026-07-09）：M27 图标重设计碗+萌芽

**用户反馈**：M26 图标"颠倒"+"叶子突兀"。

**根因（cairosvg 实测验证）**：M26 碗 path `M39,51 A15,15 0 0 1 69,51 Z` 的 `sweep-flag=1` 在 y-down 坐标系实际渲染为弧线在上方（碗口朝下倒扣），注释"sweep=1 = 下方半圆"是错误判断。正确应为 `sweep=0`。米粒 y=55-60 落在倒扣碗的下方背景区，实际不在碗内。

**重设计（方向 B 碗+萌芽）**：
- 碗 sweep 1→0 修正颠倒
- 米粒 3→2 粒碗底对称（让位萌芽焦点）
- 删除 M26 右上飘叶（突兀无连接）
- 新增茎（碗中央底部 (54,61) → 碗口上方 (54,38)，主绿 1.5dp）
- 新增顶叶（茎尖右上 30°，主绿 #2E7D32）
- 新增侧叶（茎中部左上 30°，中绿 #388E3C 比顶叶浅一阶）
- 语义升级：碗(食物)+萌芽双叶(健康/成长)=健康饮食生命力

**新增陷阱**：
- Android vector `sweep-flag` 在 y-down 坐标系：sweep=0 弧线在下（碗口朝上），sweep=1 弧线在上（碗口朝下）。注释别凭直觉写，要 cairosvg 实测验证。
- `scripts/render_icon_png.py` 之前是 M15 叉刀硬编码几何（与实际 PNG 不符），M27 重写为 cairosvg 从 XML 渲染，避免脚本与 XML 脱节。

**验证**：cairosvg 像素采样全通过 / flutter analyze No issues / flutter test 1172 passed 0 回归 / 6+1 硬约束满足。
```

- [ ] **Step 4: 提交**

```bash
cd /workspace && git add pubspec.yaml CHANGELOG.md HANDOFF.md
git commit -m "$(cat <<'EOF'
chore(M27): bump v0.33.0+46 + CHANGELOG + HANDOFF

- pubspec.yaml: 0.32.0+45 → 0.33.0+46
- CHANGELOG.md: 新增 [v0.33.0] 段落（改动/语义升级/验证 3 节）
- HANDOFF.md: 当前版本 + 当前状态同步 v0.33.0 + 新增 sweep-flag 陷阱
EOF
)"
```

---

## Task 7: push

**Files:** 无文件改动

- [ ] **Step 1: git push**

```bash
cd /workspace && git push origin trae/agent-wX1X6Q
```

预期：`trae/agent-wX1X6Q -> trae/agent-wX1X6Q`（不打 tag 不发 release）。

---

## 验收清单

- [ ] cairosvg 像素采样：碗口朝上、碗底朝下、茎、顶叶、侧叶、2 粒米全部正确
- [ ] 5 密度 PNG fallback 重新生成且像素采样通过
- [ ] flutter analyze No issues
- [ ] flutter test 1172 passed / 0 回归
- [ ] icon_assets_test.dart 断言更新为 M27 几何
- [ ] 6+1 硬约束全部满足
- [ ] pubspec.yaml v0.33.0+46
- [ ] CHANGELOG.md + HANDOFF.md 同步
- [ ] git push 成功（不打 tag 不发 release）
