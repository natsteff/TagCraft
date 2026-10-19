#!/usr/bin/env python3
"""Release gate: shared version labels and packaged metadata must agree."""
from pathlib import Path
import plistlib, re, sys
root = Path(__file__).resolve().parents[1]
info = plistlib.loads((root / 'Assets/Info.plist').read_bytes())
assert re.fullmatch(r'\d+\.\d+\.\d+', info['CFBundleShortVersionString']), 'Invalid release version'
assert info['CFBundleVersion'].isdigit(), 'Build must be numeric'
assert info['TagCraftReleaseChannel'], 'Missing release channel'
app = (root / 'Sources/TagCraft/App.swift').read_text()
launch = (root / 'Sources/TagCraft/Launch.swift').read_text()
assert 'Text(AppRelease.shortLabel)' in launch, 'Splash must use shared metadata'
assert 'Text(AppRelease.shortLabel)' in app, 'Toolbar must use shared metadata'
assert 'Text("Version " + AppRelease.shortLabel + " (Build " + AppRelease.build + ")")' in app, 'About must use shared metadata'
for key in ['CFBundleShortVersionString', 'CFBundleVersion', 'TagCraftReleaseChannel']:
    assert f'forInfoDictionaryKey: "{key}"' in app, f'Shared release labels must read {key}'
if len(sys.argv) > 1:
    packaged = plistlib.loads((Path(sys.argv[1]) / 'Contents/Info.plist').read_bytes())
    for key in ['CFBundleShortVersionString', 'CFBundleVersion', 'TagCraftReleaseChannel']:
        assert packaged[key] == info[key], f'Packaged {key} differs from source'
print(f"Version gate passed: {info['CFBundleShortVersionString']} {info['TagCraftReleaseChannel']} (Build {info['CFBundleVersion']}); splash, toolbar and About use shared metadata.")
