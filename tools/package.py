#!/usr/bin/env python3
"""Build installable addon and complete demo archives, excluding caches and QA output."""
import hashlib
import configparser
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = configparser.ConfigParser()
CONFIG.read(ROOT / 'addons/jeff_map_studio/plugin.cfg')
VERSION = CONFIG['plugin']['version'].strip('"')
OUT = ROOT / 'dist'
OUT.mkdir(exist_ok=True)
EXCLUDED = {'.git', '.godot', 'dist', 'test_output', '__pycache__'}

def include(path):
    return path.is_file() and not any(part in EXCLUDED for part in path.relative_to(ROOT).parts) and path.name != '.DS_Store' and path.suffix != '.import'

archives = {}
for name, paths in [(f'jeff-map-studio-{VERSION}-addon.zip', (ROOT / 'addons').rglob('*')), (f'jeff-map-studio-{VERSION}-project.zip', ROOT.rglob('*'))]:
    output = OUT / name
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(filter(include, paths)):
            archive.write(path, path.relative_to(ROOT).as_posix())
    archives[name] = {'bytes': output.stat().st_size, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}
(OUT / 'manifest.json').write_text(json.dumps({'version': VERSION, 'godot_tested': '4.7.2', 'archives': archives}, indent=2))
print(json.dumps(archives, indent=2))
