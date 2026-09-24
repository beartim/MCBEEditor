#!/usr/bin/env python3
"""Run the real build shell with isolated tool doubles; not a native build test."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def executable(path, text):
    path.write_text('#!/bin/bash\n' + text)
    path.chmod(0o755)


def main():
    with tempfile.TemporaryDirectory(prefix='mcbe-apple-build-') as temporary:
        root = Path(temporary)
        scripts = root / 'CLI/Scripts'
        scripts.mkdir(parents=True)
        shutil.copy2(ROOT / 'CLI/Scripts/build-apple.sh', scripts)
        executable(scripts / 'bootstrap-apple-native.sh', 'exit 0\n')
        ios = root / 'CLI/iOS'
        ios.mkdir()
        (ios / 'sources.txt').write_text('CLI/iOS/CliEntry.swift\n')
        bins = root / 'tools'
        bins.mkdir()
        executable(bins / 'uname', 'if [[ "$1" == -s ]]; then echo Darwin; else echo arm64; fi\n')
        executable(bins / 'cmake', 'exit 0\n')
        executable(bins / 'xcrun', '''case "$*" in
  *--show-sdk-path*) echo /mock-sdk ;;
  *--find*) echo /mock-clang ;;
  *swiftc*)
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == -o ]]; then shift; printf new-binary > "$1"; break; fi
      shift
    done
    [[ "$FAIL_AT" != compile ]] ;;
  *lipo*) if [[ "$FAIL_AT" == arch ]]; then echo x86_64; else echo arm64; fi ;;
  *vtool*) if [[ "$FAIL_AT" == platform ]]; then printf 'platform MACOS\nminos 13.0\n'; else printf 'platform IOS\nminos 13.0\n'; fi ;;
  *) exit 99 ;;
esac
''')
        executable(bins / 'codesign', '[[ "$FAIL_AT" != sign ]] || exit 1\n[[ "$FAIL_AT" != verify || "$1" != --verify ]]\n')
        executable(bins / 'shasum', 'echo mock-hash\n')
        out = root / 'output with spaces'
        out.mkdir()
        target = out / 'mcbe-cli'
        for failure in ('compile', 'arch', 'platform', 'sign', 'verify', 'none'):
            target.write_bytes(b'previous-verified-binary')
            env = dict(os.environ, PATH=str(bins) + os.pathsep + os.environ['PATH'], FAIL_AT=failure)
            result = subprocess.run(['bash', str(scripts / 'build-apple.sh'), 'ios', str(out)],
                                    env=env, capture_output=True, timeout=20)
            if failure == 'none':
                assert result.returncode == 0, result.stderr
                assert target.read_bytes() == b'new-binary'
            else:
                assert result.returncode != 0, failure
                assert target.read_bytes() == b'previous-verified-binary', failure + ': failed build replaced approved binary'
            assert not list(out.glob('.mcbe-build.*')), 'temporary build left behind'
        print('PASS: real Apple build shell retains prior binary on compile/architecture/platform/sign/verify failure and publishes on success (tool doubles only)')


if __name__ == '__main__':
    main()
