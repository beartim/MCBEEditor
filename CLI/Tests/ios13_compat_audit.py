#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ios_dir = ROOT / 'CLI' / 'iOS'
build_script = (ROOT / 'CLI' / 'Scripts' / 'build-apple.sh').read_text(encoding='utf-8')

errors = []
if 'TARGET=arm64-apple-ios13.0' not in build_script or 'MINIMUM=13.0' not in build_script:
    errors.append('Apple release script no longer pins the iOS deployment target to 13.0')

# FileHandle.read(upToCount:) is iOS 13.4+, so it cannot appear in the iOS 13.0 binary sources.
for path in sorted(ios_dir.glob('*.swift')):
    text = path.read_text(encoding='utf-8')
    if 'read(upToCount:' in text:
        errors.append(f'{path.relative_to(ROOT)} uses FileHandle.read(upToCount:), unavailable on iOS 13.0-13.3')

if errors:
    for error in errors:
        print(f'FAIL: {error}')
    raise SystemExit(1)

print('PASS: iOS CLI source keeps the known FileHandle APIs compatible with iOS 13.0')
