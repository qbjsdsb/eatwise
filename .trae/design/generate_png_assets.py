#!/usr/bin/env python3
"""
EatWise 图标 PNG 位图生成器 —— 候选 A：同心圆环 + 中心圆点
从 vector drawable 几何精确渲染 5 套 dpi PNG（含圆角版）

几何（在 108×108dp 画布上，中心 54,54）：
- 渐变背景：左上紫 #6750A4 → 右下橙 #FF6E40，135° 对角线
- 外环：外径 50dp（半径 25dp），环宽 6dp，内径 19dp
- 顶部缺口：8dp 宽（x=50-58，y=29-35）
- 中心圆点：直径 16dp（半径 8dp）

输出：
- mipmap-mdpi/ic_launcher.png (48×48) + ic_launcher_round.png
- mipmap-hdpi/ic_launcher.png (72×72) + ic_launcher_round.png
- mipmap-xhdpi/ic_launcher.png (96×96) + ic_launcher_round.png
- mipmap-xxhdpi/ic_launcher.png (144×144) + ic_launcher_round.png
- mipmap-xxxhdpi/ic_launcher.png (192×192) + ic_launcher_round.png
"""
from PIL import Image, ImageDraw
import os

# 设计常量
PURPLE = (0x67, 0x50, 0xA4, 255)  # #6750A4
ORANGE = (0xFF, 0x6E, 0x40, 255)  # #FF6E40
WHITE = (0xFF, 0xFF, 0xFF, 255)
TRANSPARENT = (0, 0, 0, 0)

# 渲染分辨率（master 1920×1920，每 dp = 17.78 px）
MASTER_PX = 1920
PX_PER_DP = MASTER_PX / 108  # 17.78

# 5 套 dpi 尺寸
DPI_SIZES = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
}


def make_gradient_bg(size):
    """生成 135° 对角线渐变背景（左上紫 → 右下橙）"""
    img = Image.new('RGBA', (size, size), PURPLE)
    pixels = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2.0 * size)
            r = int(PURPLE[0] + (ORANGE[0] - PURPLE[0]) * t)
            g = int(PURPLE[1] + (ORANGE[1] - PURPLE[1]) * t)
            b = int(PURPLE[2] + (ORANGE[2] - PURPLE[2]) * t)
            pixels[x, y] = (r, g, b, 255)
    return img


def make_foreground_mask(size):
    """生成前景 mask（白色=前景，黑色=透明）
    候选 A：外环（带顶部缺口）+ 中心圆点
    """
    scale = size / 108
    center = size // 2

    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)

    # 外环几何
    outer_r = int(25 * scale)   # 外径 25dp
    inner_r = int(19 * scale)   # 内径 19dp（环宽 6dp）

    # 1. 画大圆（白色）
    draw.ellipse([center - outer_r, center - outer_r,
                  center + outer_r, center + outer_r], fill=255)
    # 2. 画小圆（黑色，挖空内圆）
    draw.ellipse([center - inner_r, center - inner_r,
                  center + inner_r, center + inner_r], fill=0)
    # 3. 顶部缺口（黑色矩形，挖空顶部环段）
    gap_w = int(8 * scale)
    gap_x1 = center - gap_w // 2
    gap_x2 = center + gap_w // 2
    gap_y1 = center - outer_r
    gap_y2 = center - inner_r
    draw.rectangle([gap_x1, gap_y1, gap_x2, gap_y2], fill=0)

    # 中心圆点（白色实心圆）
    center_dot_r = int(8 * scale)
    draw.ellipse([center - center_dot_r, center - center_dot_r,
                  center + center_dot_r, center + center_dot_r], fill=255)

    return mask


def make_round_mask(size):
    """生成圆形 mask（用于 ic_launcher_round.png）"""
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse([0, 0, size - 1, size - 1], fill=255)
    return mask


def render_icon(size):
    """渲染指定尺寸的图标（前景+背景合成）"""
    # 渐变背景
    bg = make_gradient_bg(size)
    # 前景 mask
    fg_mask = make_foreground_mask(size)
    # 前景图层（纯白）
    fg = Image.new('RGBA', (size, size), WHITE)
    # 合成：背景 + 前景（按 mask）
    result = Image.composite(fg, bg, fg_mask)
    return result


def render_round_icon(size):
    """渲染圆形裁切版图标（用于 ic_launcher_round.png）"""
    # 先渲染完整图标
    icon = render_icon(size)
    # 圆形 mask
    round_mask = make_round_mask(size)
    # 圆形裁切（圆外透明）
    transparent = Image.new('RGBA', (size, size), TRANSPARENT)
    result = Image.composite(icon, transparent, round_mask)
    return result


def main():
    res_dir = '/workspace/android/app/src/main/res'

    print('渲染 master 1920×1920...')
    master = render_icon(MASTER_PX)
    master.save('/workspace/.trae/design/icon-final-master-1920.png')
    master_round = render_round_icon(MASTER_PX)
    master_round.save('/workspace/.trae/design/icon-final-master-1920-round.png')

    print('\n生成 5 套 dpi PNG:')
    for dpi_name, dpi_size in DPI_SIZES.items():
        out_dir = os.path.join(res_dir, f'mipmap-{dpi_name}')
        os.makedirs(out_dir, exist_ok=True)

        # 普通版（方形，系统按 OEM 蒙版裁切）
        icon = render_icon(dpi_size)
        icon_path = os.path.join(out_dir, 'ic_launcher.png')
        icon.save(icon_path, 'PNG')
        print(f'  {dpi_name}/ic_launcher.png ({dpi_size}×{dpi_size})')

        # 圆角版（圆形裁切，用于 roundIcon）
        icon_round = render_round_icon(dpi_size)
        icon_round_path = os.path.join(out_dir, 'ic_launcher_round.png')
        icon_round.save(icon_round_path, 'PNG')
        print(f'  {dpi_name}/ic_launcher_round.png ({dpi_size}×{dpi_size})')

    print('\n完成！')
    print('  - 5 套 dpi × 2 版本（普通+圆角）= 10 个 PNG 已替换')
    print('  - master 1920 保存在 /workspace/.trae/design/icon-final-master-1920.png')

    # 验证像素
    print('\n像素验证（xxxhdpi 192×192）:')
    verify = Image.open(os.path.join(res_dir, 'mipmap-xxxhdpi/ic_launcher.png'))
    print(f'  size: {verify.size}')
    print(f'  top-left (紫): {verify.getpixel((5, 5))}')
    print(f'  bottom-right (橙): {verify.getpixel((187, 187))}')
    print(f'  center (中心圆点白): {verify.getpixel((96, 96))}')
    print(f'  ring top (缺口透明/背景): {verify.getpixel((96, 30))}')
    print(f'  ring left (环白): {verify.getpixel((40, 96))}')


if __name__ == '__main__':
    main()
