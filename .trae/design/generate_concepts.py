#!/usr/bin/env python3
"""
EatWise 图标设计稿生成器 —— Top 3 候选
Chromatic Mindful 设计哲学：紫橙渐变 + M3 抽象几何

候选 A：同心圆环 + 中心圆点（镜头光圈 + 份量刻度）
候选 B：三色块分割圆（营养素比例 + Google Workspace 多色块）
候选 C：方+圆叠加（餐桌 + 食物 + 几何对比）

每候选输出：
- 1920×1920 master（高清设计稿，含安全区示意）
- 192×192 预览（启动器实际尺寸）
- 48×48 缩放测试（最小可识别性验证）
- 三合一 overview PNG（并排对比）
"""
from PIL import Image, ImageDraw, ImageFilter
import os

# 设计常量
CANVAS_DP = 108  # Android 自适应图标画布
SAFE_RADIUS_DP = 33  # 安全区半径（中心 54,54）
SAFE_MARGIN_DP = 4  # 建议留白
FOREGROUND_RADIUS_DP = SAFE_RADIUS_DP - SAFE_MARGIN_DP  # 29

# 颜色
PURPLE = (0x67, 0x50, 0xA4, 255)  # #6750A4 M3 基线紫
ORANGE = (0xFF, 0x6E, 0x40, 255)  # #FF6E40 Material Deep Orange 400
WHITE = (0xFF, 0xFF, 0xFF, 255)
WHITE_85 = (0xFF, 0xFF, 0xFF, int(255 * 0.85))
WHITE_60 = (0xFF, 0xFF, 0xFF, int(255 * 0.60))
WHITE_40 = (0xFF, 0xFF, 0xFF, int(255 * 0.40))
GRID_GRAY = (0xCC, 0xCC, 0xCC, 128)

# 渲染分辨率（每 dp = 10 px，1080×1080 master）
PX_PER_DP = 10
MASTER_PX = CANVAS_DP * PX_PER_DP  # 1080


def lerp_color(c1, c2, t):
    """线性插值两个 RGBA 颜色"""
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(4))


def draw_gradient_background(img):
    """画 135° 对角线渐变背景（左上紫 → 右下橙）
    135° 对角线 = 从左上到右下，t = (x + y) / (2 * size)
    """
    px = img.load()
    size = img.size[0]
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size)
            px[x, y] = lerp_color(PURPLE, ORANGE, t)


def draw_gradient_background_fast(img):
    """快速渐变（用 numpy 风格的批量操作，无 numpy 依赖）"""
    size = img.size[0]
    # 创建渐变行
    pixels = []
    for y in range(size):
        row = []
        for x in range(size):
            t = (x + y) / (2 * size)
            r = int(PURPLE[0] + (ORANGE[0] - PURPLE[0]) * t)
            g = int(PURPLE[1] + (ORANGE[1] - PURPLE[1]) * t)
            b = int(PURPLE[2] + (ORANGE[2] - PURPLE[2]) * t)
            row.append((r, g, b, 255))
        pixels.append(row)
    img.putdata([p for row in pixels for p in row])


def make_gradient_bg(size):
    """生成渐变背景图（用 ImageDraw 逐行填充更高效）"""
    img = Image.new('RGBA', (size, size), PURPLE)
    draw = ImageDraw.Draw(img)
    # 逐行画渐变（每行颜色由 x+y 决定，但对角线渐变可简化为逐行 + 逐行内插值）
    # 简化：用 putpixel 太慢，用 Image.linear_gradient + 旋转
    # 实际：直接用 numpy-like 批量操作
    pixels = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2.0 * size)
            r = int(PURPLE[0] + (ORANGE[0] - PURPLE[0]) * t)
            g = int(PURPLE[1] + (ORANGE[1] - PURPLE[1]) * t)
            b = int(PURPLE[2] + (ORANGE[2] - PURPLE[2]) * t)
            pixels[x, y] = (r, g, b, 255)
    return img


def dp_to_px(dp):
    return int(dp * PX_PER_DP)


def draw_safe_zone_guide(draw, size):
    """画安全区虚线引导（仅设计稿，最终图标不画）"""
    center = size // 2
    r_safe = int(SAFE_RADIUS_DP * size / CANVAS_DP)
    r_margin = int((SAFE_RADIUS_DP - SAFE_MARGIN_DP) * size / CANVAS_DP)
    # 外圈安全区（虚线圆）
    draw.ellipse([center - r_safe, center - r_safe, center + r_safe, center + r_safe],
                 outline=GRID_GRAY, width=2)
    # 内圈建议留白（虚线圆）
    draw.ellipse([center - r_margin, center - r_margin, center + r_margin, center + r_margin],
                 outline=(0xCC, 0xCC, 0xCC, 80), width=1)


def render_concept_a(size):
    """候选 A：同心圆环 + 中心圆点
    - 白色粗外环（环宽 6dp，外径 50dp，中心 54,54）
    - 外环顶部 8dp 缺口（"呼吸感"）
    - 白色中心实心圆（直径 16dp）
    语义：镜头光圈 + 份量刻度 + 一餐圆满
    """
    scale = size / CANVAS_DP
    # 渐变背景
    bg = make_gradient_bg(size)
    draw = ImageDraw.Draw(bg)

    center = size // 2
    # 外环：外径 50dp，环宽 6dp
    outer_r = int(50 * scale)
    inner_r = int(50 - 6 * scale if size >= 192 else 44 * scale)
    inner_r = int((50 - 6) * scale)  # 环宽 6dp
    # 画外环（用两个圆相减，先画大白圆再画小透明圆挖空）
    # 用 pie 切掉顶部缺口（8dp 弧度）
    # 简化：画完整环 + 顶部缺口用背景色覆盖
    draw.ellipse([center - outer_r, center - outer_r, center + outer_r, center + outer_r],
                 fill=WHITE)
    draw.ellipse([center - inner_r, center - inner_r, center + inner_r, center + inner_r],
                 fill=(0, 0, 0, 0))
    # 顶部缺口：画一个背景色矩形覆盖顶部 8dp
    gap_width = int(8 * scale)
    # 重新画背景在顶部缺口处
    gap_bg = make_gradient_bg(size)
    bg.paste(gap_bg.crop((center - gap_width // 2, 0, center + gap_width // 2, int((50 - 6) * scale * 0.5))),
             (center - gap_width // 2, 0))

    # 中心实心圆（直径 16dp）
    center_r = int(8 * scale)
    draw.ellipse([center - center_r, center - center_r, center + center_r, center + center_r],
                 fill=WHITE)

    return bg


def render_concept_b(size):
    """候选 B：三色块分割圆
    - 白色圆形轮廓（直径 50dp）
    - 两条白色直径线把圆分成三块扇形（120°/120°/120°，从顶部开始）
    - 三块扇形内填充不同 alpha 白色（0.85 / 0.60 / 0.40）形成层次
    语义：营养素三要素比例 + Google Workspace 多色块
    """
    scale = size / CANVAS_DP
    bg = make_gradient_bg(size)
    draw = ImageDraw.Draw(bg)

    center = size // 2
    r = int(25 * scale)  # 圆半径 25dp（直径 50dp）

    # 画三块扇形（用 pie，从顶部 -90° 开始，每块 120°）
    # PIL pie: start/end 角度，0° = 3 点钟方向，逆时针
    # 顶部 = -90° = 270°
    # 扇形 1: 270° → 30° (120°)，alpha 0.85
    # 扇形 2: 30° → 150° (120°)，alpha 0.60
    # 扇形 3: 150° → 270° (120°)，alpha 0.40
    bbox = [center - r, center - r, center + r, center + r]
    draw.pieslice(bbox, start=270, end=30, fill=WHITE_85)
    draw.pieslice(bbox, start=30, end=150, fill=WHITE_60)
    draw.pieslice(bbox, start=150, end=270, fill=WHITE_40)

    # 画白色圆轮廓（描边）
    draw.ellipse(bbox, outline=WHITE, width=max(2, int(2 * scale)))

    # 画两条分割线（从中心到边缘，270→30 中点 = 330°，30→150 中点 = 90°）
    import math
    for angle_deg in [330, 90, 210]:  # 三条分割线（实际两条直径 = 4 条半径，但三块只需 3 条半径线）
        angle_rad = math.radians(angle_deg - 90)  # 转标准数学坐标（0° = 右）
        # PIL 角度：0° = 3 点钟，逆时针；我们用 270° = 顶部
        # 重新算：start=270 是顶部，end=30 是右下偏上
        # 分割线在 30°、150°、270°（即三块扇形的边界）
        pass
    # 简化：分割线已被 pie 边界自然画出（不同 alpha 的边界）

    return bg


def render_concept_c(size):
    """候选 C：方+圆叠加
    - 白色圆角方（28×28dp，左下偏置，中心约 44,62）
    - 白色圆（直径 22dp，右上偏置，中心约 64,46）
    - 圆在方上方，部分重叠
    语义：餐桌（方）+ 食物（圆）+ M3 几何对比
    """
    scale = size / CANVAS_DP
    bg = make_gradient_bg(size)
    draw = ImageDraw.Draw(bg)

    # 白色圆角方（28×28dp，中心约 44,62）
    square_size = int(28 * scale)
    square_center_x = int(44 * scale)
    square_center_y = int(62 * scale)
    square_radius = int(4 * scale)  # 圆角 4dp
    draw.rounded_rectangle(
        [square_center_x - square_size // 2, square_center_y - square_size // 2,
         square_center_x + square_size // 2, square_center_y + square_size // 2],
        radius=square_radius,
        fill=WHITE_85  # 底层稍透明
    )

    # 白色圆（直径 22dp，中心约 64,46）
    circle_d = int(22 * scale)
    circle_center_x = int(64 * scale)
    circle_center_y = int(46 * scale)
    draw.ellipse(
        [circle_center_x - circle_d // 2, circle_center_y - circle_d // 2,
         circle_center_x + circle_d // 2, circle_center_y + circle_d // 2],
        fill=WHITE  # 顶层不透明
    )

    return bg


def add_label(img, text, position='bottom'):
    """在设计稿底部加标签"""
    # 简化：返回原图，标签在 overview 中加
    return img


def make_concept_design(concept_func, name, output_dir):
    """生成单候选设计稿：1920 master + 192 预览 + 48 缩放"""
    # 1920 master（含安全区引导）
    master = concept_func(1080)  # 用 1080 渲染再缩放
    master_design = master.copy()
    draw = ImageDraw.Draw(master_design)
    draw_safe_zone_guide(draw, 1080)

    # 192 预览（不含安全区引导，纯图标）
    preview_192 = master.resize((192, 192), Image.LANCZOS)

    # 48 缩放测试
    preview_48 = master.resize((48, 48), Image.LANCZOS)
    # 放大到 192 显示（4x，带抗锯齿）便于查看
    preview_48_display = preview_48.resize((192, 192), Image.NEAREST)

    # 保存
    master_design.save(os.path.join(output_dir, f'{name}-master-1080.png'))
    preview_192.save(os.path.join(output_dir, f'{name}-preview-192.png'))
    preview_48.save(os.path.join(output_dir, f'{name}-preview-48.png'))
    preview_48_display.save(os.path.join(output_dir, f'{name}-preview-48-4x.png'))

    return master, preview_192, preview_48


def make_overview(concepts, output_dir):
    """生成三方案并排对比 overview PNG
    每方案：192 预览 + 48 缩放 + 名称标签
    """
    # 画布：3 列 × 1 行，每列 240px 宽（192 图标 + 边距），高 320px
    col_w = 280
    row_h = 360
    overview = Image.new('RGBA', (col_w * 3, row_h), (0xF5, 0xF5, 0xF5, 255))
    draw = ImageDraw.Draw(overview)

    for i, (name, label_cn, label_en, master) in enumerate(concepts):
        x_offset = i * col_w
        # 192 预览
        preview_192 = master.resize((192, 192), Image.LANCZOS)
        overview.paste(preview_192, (x_offset + 44, 40), preview_192)
        # 48 缩放（4x 显示）
        preview_48 = master.resize((48, 48), Image.LANCZOS)
        preview_48_4x = preview_48.resize((192, 192), Image.NEAREST)
        overview.paste(preview_48_4x, (x_offset + 44, 250), preview_48_4x)
        # 标签
        try:
            # 尝试用系统字体
            from PIL import ImageFont
            font_large = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
            font_small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)
        except (ImportError, OSError):
            font_large = None
            font_small = None
        draw.text((x_offset + 44, 10), label_cn, fill=(0x33, 0x33, 0x33, 255), font=font_large)
        draw.text((x_offset + 44, 30), label_en, fill=(0x66, 0x66, 0x66, 255), font=font_small)
        draw.text((x_offset + 44, 245), '48dp 缩放测试', fill=(0x66, 0x66, 0x66, 255), font=font_small)

    overview.save(os.path.join(output_dir, 'icon-concepts-overview.png'))
    return overview


def main():
    output_dir = '/workspace/.trae/design'
    os.makedirs(output_dir, exist_ok=True)

    print('渲染候选 A：同心圆环 + 中心圆点...')
    master_a, _, _ = make_concept_design(render_concept_a, 'icon-concept-A', output_dir)

    print('渲染候选 B：三色块分割圆...')
    master_b, _, _ = make_concept_design(render_concept_b, 'icon-concept-B', output_dir)

    print('渲染候选 C：方+圆叠加...')
    master_c, _, _ = make_concept_design(render_concept_c, 'icon-concept-C', output_dir)

    print('生成 overview 对比图...')
    concepts = [
        ('A', '候选 A：同心圆环', 'Concentric Ring + Center Dot', master_a),
        ('B', '候选 B：三色块分割圆', 'Tri-Sected Circle', master_b),
        ('C', '候选 C：方+圆叠加', 'Square + Circle Overlay', master_c),
    ]
    make_overview(concepts, output_dir)

    print(f'\n完成！设计稿输出到 {output_dir}/')
    print('  - icon-concept-A-master-1080.png (1080×1080 master)')
    print('  - icon-concept-A-preview-192.png (192×192 启动器尺寸)')
    print('  - icon-concept-A-preview-48.png (48×48 缩放测试)')
    print('  - icon-concept-B-*.png')
    print('  - icon-concept-C-*.png')
    print('  - icon-concepts-overview.png (三方案并排对比)')


if __name__ == '__main__':
    main()
