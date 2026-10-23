#!/usr/bin/env python3
"""Release gate: shared version labels and packaged metadata must agree."""
from pathlib import Path
import plistlib, re, sys, subprocess
root = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, str(root/'scripts/generate-terms.py'), '--check'], check=True)
info = plistlib.loads((root / 'Assets/Info.plist').read_bytes())
assert re.fullmatch(r'\d+\.\d+\.\d+', info['CFBundleShortVersionString']), 'Invalid release version'
assert info['CFBundleVersion'].isdigit(), 'Build must be numeric'
assert info['TagCraftReleaseChannel'], 'Missing release channel'
app = (root / 'Sources/TagCraft/App.swift').read_text()
launch = (root / 'Sources/TagCraft/Launch.swift').read_text()
assert 'Text(AppRelease.fullLabel)' in launch, 'Splash must use shared metadata'
assert 'Text(AppRelease.fullLabel)' in app, 'Toolbar must use shared metadata'
assert 'Text("Version " + AppRelease.fullLabel)' in app, 'About must use shared metadata'
assert 'static var fullLabel: String { shortLabel + " (Build " + build + ")" }' in app, 'Shared version label must include build'
for key in ['CFBundleShortVersionString', 'CFBundleVersion', 'TagCraftReleaseChannel']:
    assert f'forInfoDictionaryKey: "{key}"' in app, f'Shared release labels must read {key}'
if len(sys.argv) > 1:
    packaged = plistlib.loads((Path(sys.argv[1]) / 'Contents/Info.plist').read_bytes())
    for document in ['LICENSE', 'USAGE-NOTICE.md', 'Legal/CORE-TERMS.txt', 'Legal/TAGCRAFT-NOTES.txt']:
        assert (Path(sys.argv[1])/'Contents/Resources'/document).read_bytes() == (root/document).read_bytes(), 'Packaged document differs: '+document
    assert not (Path(sys.argv[1])/'Contents/Resources/EULA.md').exists(), 'Stale bundled EULA'
    for key in ['CFBundleShortVersionString', 'CFBundleVersion', 'TagCraftReleaseChannel']:
        assert packaged[key] == info[key], f'Packaged {key} differs from source'
print(f"Version gate passed: {info['CFBundleShortVersionString']} {info['TagCraftReleaseChannel']} (Build {info['CFBundleVersion']}); splash, toolbar and About use shared metadata.")
