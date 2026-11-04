#!/usr/bin/env python3
"""Copy only the distributable addon to a clean Godot project, then test EditorPlugin."""
import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
mode = parser.add_mutually_exclusive_group()
mode.add_argument('--headless', action='store_true', help='Run without windows (the default; retained for compatibility)')
mode.add_argument('--visual', action='store_true', help='Open graphical test windows (requires explicit user request)')
args = parser.parse_args()
output = ROOT / 'test_output'
output.mkdir(exist_ok=True)

with tempfile.TemporaryDirectory(prefix='jeff-map-install-') as temporary:
    project = Path(temporary)
    shutil.copytree(ROOT / 'addons/jeff_map_studio', project / 'addons/jeff_map_studio', ignore=shutil.ignore_patterns('*.import'))
    config = '''config_version=5
[application]
config/name="Jeff Map Studio Clean Install QA"
[rendering]
renderer/rendering_method="gl_compatibility"
[editor_plugins]
enabled=PackedStringArray("res://addons/jeff_map_studio/plugin.cfg")
'''
    (project / 'project.godot').write_text(config)
    (project / 'fixture.tscn').write_text('[gd_scene format=3]\n[node name="Fixture" type="Node2D"]\n')
    first = subprocess.run([args.godot, '--headless', '--editor', '--path', str(project), '--import'], capture_output=True, text=True, timeout=90)
    (output / 'clean_import.log').write_text(first.stdout + first.stderr)
    if first.returncode or 'SCRIPT ERROR' in first.stderr or 'ERROR:' in first.stderr:
        raise SystemExit('Clean import failed; see test_output/clean_import.log')
    shutil.copytree(ROOT / 'tests/editor_probe', project / 'addons/jeff_map_studio_test')
    config = config.replace('"res://addons/jeff_map_studio/plugin.cfg")', '"res://addons/jeff_map_studio/plugin.cfg", "res://addons/jeff_map_studio_test/plugin.cfg")')
    (project / 'project.godot').write_text(config)
    command = [args.godot, '--editor', '--path', str(project), '--resolution', '1920x1200', 'res://fixture.tscn']
    if not args.visual:
        command.insert(1, '--headless')
    run = subprocess.run(command, capture_output=True, text=True, timeout=120)
    (output / 'editor_probe.log').write_text(run.stdout + run.stderr)
    for name in ['editor_report.json', 'editor_probe.png']:
        if (project / name).exists():
            shutil.copy2(project / name, output / name)
    report_path = project / 'editor_report.json'
    if not report_path.exists():
        raise SystemExit('Editor probe did not finish; see test_output/editor_probe.log')
    report = json.loads(report_path.read_text())
    print(json.dumps(report, ensure_ascii=False))
    if run.returncode or report['failures'] or 'SCRIPT ERROR' in run.stderr or 'ERROR:' in run.stderr:
        raise SystemExit('Editor validation failed; see test_output/editor_probe.log')
    shutil.copy2(ROOT / 'tests/test_saved_scene.gd', project / 'test_saved_scene.gd')
    command = [args.godot, '--path', str(project), '--script', 'test_saved_scene.gd']
    if not args.visual:
        command.insert(1, '--headless')
    saved = subprocess.run(command, capture_output=True, text=True, timeout=90)
    saved_output = saved.stdout + saved.stderr
    (output / 'saved_scene.log').write_text(saved_output)
    if saved.returncode or 'ERROR:' in saved_output or 'FAIL:' in saved_output:
        raise SystemExit('Saved scene runtime failed; see test_output/saved_scene.log')
    print('SAVED SCENE TESTS: 1 checks, 0 failures')
