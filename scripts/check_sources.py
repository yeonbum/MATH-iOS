#!/usr/bin/env python3
"""Non-macOS checks only: structural, Swift syntax, YAML, plist, asset/config sanity."""
from pathlib import Path
from plistlib import load
from subprocess import run
import shutil
import json
import sys

root = Path(__file__).resolve().parents[1]
project = root / 'project.yml'
files = list((root / 'iosApp/MATE').rglob('*.swift'))
assert len(files) >= 10, 'Swift source files missing'
assert (root / 'iosApp/Native/MateEngine.mm').exists()
assert (root / '.github/workflows/ios-build.yml').exists()
with open(root / 'iosApp/MATE/Info.plist', 'rb') as f:
    info = load(f)
assert info['CFBundleDisplayName'] == 'MATE'
json.loads((root / 'iosApp/MATE/Assets.xcassets/AppIcon.appiconset/Contents.json').read_text())
if shutil.which('swiftc'):
    for file in files:
        proc = run(['swiftc', '-frontend', '-parse', str(file)], capture_output=True, text=True)
        if proc.returncode:
            print(file, proc.stdout, proc.stderr, file=sys.stderr)
            sys.exit(proc.returncode)
if shutil.which('bash'):
    for file in (root / 'scripts').glob('*.sh'):
        proc = run(['bash', '-n', str(file)], capture_output=True, text=True)
        assert proc.returncode == 0, str(file) + proc.stderr
try:
    import yaml
    assert yaml.safe_load(project.read_text())['targets']['MATE']['type'] == 'application'
except ImportError:
    print('PyYAML not installed; skipped YAML semantic validation')
print(f'PASS: plist, app icon, {len(files)} Swift files, native bridge, scripts, project structure')
print('NOTE: NOT an Xcode/Metal/iOS runtime build test')
