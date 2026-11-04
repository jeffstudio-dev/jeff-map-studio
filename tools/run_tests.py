#!/usr/bin/env python3
"""Run behavioral Godot tests and reject engine errors even if Godot exits zero."""
import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--visual', action='store_true', help='Open graphical test windows (requires explicit user request; default is headless)')
parser.add_argument('--performance', action='store_true')
parser.add_argument('--clean-install', action='store_true')
args = parser.parse_args()
output = ROOT / 'test_output'
output.mkdir(exist_ok=True)

def run(name, command, timeout=240):
    process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    text = process.stdout + process.stderr
    (output / (name + '.log')).write_text(text)
    print('\n'.join(line for line in text.splitlines() if 'TESTS:' in line or 'PERFORMANCE:' in line))
    if process.returncode or 'ERROR:' in text or 'SCRIPT ERROR' in text or 'FAIL:' in text:
        print(text[-5000:], file=sys.stderr)
        raise SystemExit(f'{name} failed; see test_output/{name}.log')

run('import', [args.godot, '--headless', '--editor', '--path', '.', '--import'])
for name in ['core', 'assets', 'integration', 'runtime_demo', 'seams', 'blocks', 'landmarks', 'art_specs']:
    command = [args.godot, '--path', '.', '--script', f'tests/test_{name}.gd']
    if name in ('core', 'assets') or not args.visual:
        command.insert(1, '--headless')
    run(name, command)
if args.performance:
    command = [args.godot, '--path', '.', '--script', 'tests/test_performance.gd']
    if not args.visual:
        command.insert(1, '--headless')
    run('performance', command)
if args.clean_install:
    command = [sys.executable, 'tools/test_clean_install.py', '--godot', args.godot]
    if args.visual:
        command.append('--visual')
    run('clean_install', command)
print('All requested checks passed.')
