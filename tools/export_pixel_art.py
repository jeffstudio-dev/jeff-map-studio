#!/usr/bin/env python3
"""Export the pixel-style Aseprite sources and import them as Godot resources.

Both steps run in the background: Aseprite in batch mode (-b), Godot with --headless.
Usage: python3 tools/export_pixel_art.py --aseprite /path/to/aseprite --godot /path/to/godot
"""
import argparse
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'addons/jeff_map_studio/assets/pixel'
parser = argparse.ArgumentParser()
parser.add_argument('--aseprite', required=True)
parser.add_argument('--godot', required=True)
args = parser.parse_args()

for name in ['landmarks', 'clusters']:
    subprocess.run([args.aseprite, '-b', str(ART / f'{name}.aseprite'), '--sheet', str(ART / f'{name}.png'),
                    '--sheet-type', 'horizontal', '--data', str(ART / f'{name}.json'), '--format', 'json-array',
                    '--list-tags'], check=True, capture_output=True)
    print('Exported', name)
process = subprocess.run([args.godot, '--headless', '--path', '.', '--script', 'tools/import_pixel_art.gd'],
                         cwd=ROOT, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=120)
text = process.stdout + process.stderr
print('\n'.join(line for line in text.splitlines() if line.startswith('Imported') or 'ERROR' in line))
if process.returncode or 'ERROR' in text:
    raise SystemExit('Godot import failed')
