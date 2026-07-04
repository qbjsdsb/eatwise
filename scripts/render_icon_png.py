#!/usr/bin/env python3
"""
M15-A5: 从 ic_launcher_foreground.xml 的 path 几何渲染 PNG fallback。
5 个密度：mdpi 48 / hdpi 72 / xhdpi 96 / xxhdpi 144 / xxxhdpi 192
2 个版本：ic_launcher.png（方形）+ ic_launcher_round.png（圆形蒙版）
"""
from PIL import Image, ImageDraw

BG_COLOR = (0xFF, 0x6E, 0x40, 0xFF)
FG_COLOR = (0xFF, 0xFF, 0xFF, 0xFF)

DENSITIES = {
    'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192,
}

# 108×108 viewport 几何（与 ic_launcher_foreground.xml 一致）
FORK_TINES = [(38, 24, 42, 37), (43, 24, 47, 37), (48, 24, 52, 37)]
FORK_CONNECTOR = (38, 36, 54, 40)
FORK_HANDLE = (44, 40, 48, 68)
KNIFE_BLADE = (62, 24, 76, 52)
KNIFE_NECK = (66, 52, 72, 54)
KNIFE_HANDLE = (66, 54, 70, 70)


def render_icon(size, circular=False):
    base = Image.new('RGBA', (108, 108), (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)
    draw.rectangle([0, 0, 108, 108], fill=BG_COLOR)
    for tine in FORK_TINES:
        draw.rounded_rectangle(tine, radius=1.5, fill=FG_COLOR)
    draw.rounded_rectangle(FORK_CONNECTOR, radius=2, fill=FG_COLOR)
    draw.rounded_rectangle(FORK_HANDLE, radius=2, fill=FG_COLOR)
    draw.rounded_rectangle(KNIFE_BLADE, radius=2, fill=FG_COLOR)
    draw.rectangle(KNIFE_NECK, fill=FG_COLOR)
    draw.rounded_rectangle(KNIFE_HANDLE, radius=2, fill=FG_COLOR)
    if circular:
        mask = Image.new('L', (108, 108), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, 108, 108], fill=255)
        circular_img = Image.new('RGBA', (108, 108), (0, 0, 0, 0))
        circular_img.paste(base, (0, 0), mask)
        base = circular_img
    return base.resize((size, size), Image.LANCZOS)


def main():
    import os
    res_dir = 'android/app/src/main/res'
    for density, size in DENSITIES.items():
        out_dir = f'{res_dir}/mipmap-{density}'
        os.makedirs(out_dir, exist_ok=True)
        render_icon(size, circular=False).save(f'{out_dir}/ic_launcher.png', 'PNG')
        render_icon(size, circular=True).save(f'{out_dir}/ic_launcher_round.png', 'PNG')
        print(f'  {density}: {size}x{size}')


if __name__ == '__main__':
    main()
