#!/usr/bin/env python3
"""Export every layer of the concept sheets plus slice data (Aseprite batch mode, no window)."""
import json, subprocess, sys
from pathlib import Path

DESIGN = Path(__file__).resolve().parents[1]
ASEPRITE = sys.argv[1]
OUT = DESIGN / 'concepts' / 'export'
OUT.mkdir(exist_ok=True)
for sheet in sorted((DESIGN / 'concepts').glob('*.aseprite')):
    data = OUT / f'{sheet.stem}.json'
    subprocess.run([ASEPRITE, '-b', str(sheet), '--sheet', str(OUT / f'{sheet.stem}_flat.png'), '--data', str(data),
                    '--format', 'json-array', '--list-slices', '--list-layers'], check=True, capture_output=True)
    layers = [layer['name'] for layer in json.loads(data.read_text())['meta']['layers']]
    for layer in layers:
        subprocess.run([ASEPRITE, '-b', '--layer', layer, str(sheet), '--sheet', str(OUT / f'{sheet.stem}_{layer}.png')],
                       check=True, capture_output=True)
    scale = '4' if sheet.stem.startswith('pixel') else '2'
    preview = DESIGN / 'examples' / f'concept_{sheet.stem}.png'
    subprocess.run([ASEPRITE, '-b', str(sheet), '--scale', scale, '--sheet', str(preview)], check=True, capture_output=True)
    # Review copy on a neutral backdrop so white brush stamps stay visible.
    from PIL import Image
    image = Image.open(preview).convert('RGBA')
    backdrop = Image.new('RGBA', image.size, (58, 64, 72, 255))
    backdrop.alpha_composite(image)
    backdrop.save(preview)
    slices = [s['name'] for s in json.loads(data.read_text())['meta']['slices']]
    print(sheet.name, 'layers:', layers, 'slices:', len(slices))
