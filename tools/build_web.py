#!/usr/bin/env python3
"""Export the Map Studio workspace for the browser into docs/play/ (headless, no window).

Usage: python3 tools/build_web.py --godot /path/to/godot [--template /path/to/web_nothreads_release.zip]
--template is only needed when the export templates matching the editor are not installed;
it is written into export_presets.cfg for this run and the file is restored afterwards.
"""
import argparse
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRESETS = ROOT / 'export_presets.cfg'
OUT = ROOT / 'docs/play'
parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--template')
args = parser.parse_args()

original = PRESETS.read_text()
try:
    if args.template:
        PRESETS.write_text(original.replace('custom_template/release=""', f'custom_template/release="{args.template}"'))
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    process = subprocess.run([args.godot, '--headless', '--path', '.', '--export-release', 'Web', str(OUT / 'index.html')],
                             cwd=ROOT, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=600)
    text = process.stdout + process.stderr
    errors = [line for line in text.splitlines() if 'ERROR' in line]
    print('\n'.join(errors[-20:]))
    if process.returncode or not (OUT / 'index.pck').exists():
        raise SystemExit('Web export failed')
finally:
    PRESETS.write_text(original)
for path in sorted(OUT.iterdir()):
    print(f'{path.stat().st_size / 1048576:7.2f} MB  {path.name}')
