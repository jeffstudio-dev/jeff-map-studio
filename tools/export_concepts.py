#!/usr/bin/env python3
"""Export terrain concept sheets from Aseprite and import them as Godot resources.

Aseprite runs in batch mode (-b) and Godot with --headless; no window opens.
Usage: python3 tools/export_concepts.py --aseprite /path/to/aseprite --godot /path/to/godot
"""
import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONCEPTS = ROOT / 'addons/jeff_map_studio/art/concepts'
parser = argparse.ArgumentParser()
parser.add_argument('--aseprite', required=True)
parser.add_argument('--godot', required=True)
args = parser.parse_args()

for sheet in sorted(CONCEPTS.glob('*/*.aseprite')):
    out = sheet.parent / 'export'
    out.mkdir(exist_ok=True)
    data = out / f'{sheet.stem}.json'
    subprocess.run([args.aseprite, '-b', str(sheet), '--data', str(data), '--format', 'json-array',
                    '--list-slices', '--list-layers', '--sheet', str(out / f'{sheet.stem}_flat.png')], check=True, capture_output=True)
    layers = [layer['name'] for layer in json.loads(data.read_text())['meta']['layers']]
    for name in ['palette', 'motifs', 'reference']:
        if name in layers:
            subprocess.run([args.aseprite, '-b', '--layer', name, str(sheet), '--sheet', str(out / f'{sheet.stem}_{name}.png')],
                           check=True, capture_output=True)
    print('Exported', sheet.relative_to(ROOT))
process = subprocess.run([args.godot, '--headless', '--path', '.', '--script', 'tools/import_concepts.gd'], cwd=ROOT,
                         capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=120)
text = process.stdout + process.stderr
print('\n'.join(line for line in text.splitlines() if line.startswith('Imported') or 'ERROR' in line))
if process.returncode or 'ERROR' in text:
    raise SystemExit('Godot import failed')
