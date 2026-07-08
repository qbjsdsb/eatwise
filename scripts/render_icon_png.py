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

    # 提取所有 <path> 的属性（用 [^>] 排除 >，避免 @color/ 中的 / 截断匹配）
    paths = []
    for pm in re.finditer(r'<path\s+([^>]*?)\s*/>', content, re.DOTALL):
        attrs_str = pm.group(1)
        attrs = {}
        for am in re.finditer(r'android:(\w+)="([^"]+)"', attrs_str):
            attrs[am.group(1)] = am.group(2)
        paths.append(attrs)

    # 构建 SVG
    svg_parts = [f'<svg viewBox="0 0 108 108" xmlns="http://www.w3.org/2000/svg" width="432" height="432">']
    if gradient_def:
        svg_parts.append(gradient_def)

    # 如果是渐变填充的背景 path（background.xml 的 path 非自闭合带 <aapt:attr> 子元素，
    # 正则提取不到，用 fallback 全画布渐变 path）
    if is_background and fill_attr:
        svg_parts.append(
            f'<path d="M0,0 h108 v108 h-108 z" {fill_attr}/>'
        )

    for attrs in paths:
        path_data = attrs.get('pathData', '')
        fill = attrs.get('fillColor', '#000000')
        if fill == '#00000000':
            fill = 'none'
        else:
            fill = resolve_color(fill, colors)

        # 如果是渐变填充的背景 path（已在上面的 is_background 分支处理，跳过）
        if not path_data and fill_attr and is_background:
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

    from PIL import ImageDraw
    for density, size in DENSITIES.items():
        out_dir = f'{RES_DIR}/mipmap-{density}'
        os.makedirs(out_dir, exist_ok=True)
        # 直接渲染目标尺寸（避免 LANCZOS 缩放导致的细线颜色混合，
        # 茎 1.5dp 在缩放时颜色被抗锯齿混合，采样断言会失败）
        bg_png = cairosvg.svg2png(bytestring=bg_svg.encode('utf-8'),
                                  output_width=size, output_height=size)
        fg_png = cairosvg.svg2png(bytestring=fg_svg.encode('utf-8'),
                                  output_width=size, output_height=size)
        bg_img = Image.open(io.BytesIO(bg_png)).convert('RGBA')
        fg_img = Image.open(io.BytesIO(fg_png)).convert('RGBA')
        # 合成：背景在下，前景在上
        combined = Image.alpha_composite(bg_img, fg_img)
        # 方形
        combined.save(f'{out_dir}/ic_launcher.png', 'PNG')
        # 圆形蒙版
        mask = Image.new('L', (size, size), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, size, size], fill=255)
        circular = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        circular.paste(combined, (0, 0), mask)
        circular.save(f'{out_dir}/ic_launcher_round.png', 'PNG')
        print(f'  {density}: {size}x{size}')


if __name__ == '__main__':
    main()
