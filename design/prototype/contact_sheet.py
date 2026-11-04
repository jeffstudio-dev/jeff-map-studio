#!/usr/bin/env python3
"""Assemble seed × parameter contact sheets for the design document."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

DESIGN = Path(__file__).resolve().parents[1]
FONT = ImageFont.truetype('/System/Library/Fonts/Hiragino Sans GB.ttc', 26)
SEEDS = [42, 7, 2026]
STYLES = {
    'pixel': (['默认', '高密度 · 小色块', '秋草配色'], 2, Image.NEAREST),
    'painted': (['默认', '浓密 · 细笔触', '秋草配色'], 1, Image.LANCZOS),
}
for style, (labels, scale, method) in STYLES.items():
    tiles = [[Image.open(DESIGN / 'examples' / style / f'seed{s}_param{p}.png').convert('RGBA') for p in range(3)] for s in SEEDS]
    w = max(t.width for row in tiles for t in row) * scale
    h = max(t.height for row in tiles for t in row) * scale
    pad, head, side = 16, 48, 150
    sheet = Image.new('RGBA', (side + 3 * (w + pad) + pad, head + 3 * (h + pad) + pad), (30, 36, 42, 255))
    draw = ImageDraw.Draw(sheet)
    for c, label in enumerate(labels):
        draw.text((side + pad + c * (w + pad), 10), label, font=FONT, fill=(230, 232, 228))
    for r, s in enumerate(SEEDS):
        draw.text((16, head + pad + r * (h + pad) + h // 2 - 16), f'种子 {s}', font=FONT, fill=(230, 232, 228))
        for c in range(3):
            t = tiles[r][c]
            t = t.resize((t.width * scale, t.height * scale), method)
            sheet.alpha_composite(t, (side + pad + c * (w + pad) + (w - t.width) // 2, head + pad + r * (h + pad) + (h - t.height) // 2))
    sheet.save(DESIGN / 'examples' / f'{style}_seed_param_sheet.png')
    print(style, sheet.size)
