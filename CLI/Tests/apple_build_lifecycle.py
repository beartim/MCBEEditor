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

        # Run the host test branch too: database-dependent smoke tests must
        # receive an already built fixture tool, and a fixture failure must
        # leave the previous validated CLI in place.
        core_scripts = root / 'Scripts'
        core_scripts.mkdir()
        executable(core_scripts / 'test_end_missing_subchunks.sh', 'exit 0\n')
        executable(bins / 'cmake', '''if [[ "$*" == *"--target mcbe_cli_create_test_db"* ]]; then
  [[ "$FAIL_AT" != fixture ]] || exit 1
  native="$2"
  mkdir -p "$native/tools"
  printf '#!/bin/bash\\nexit 0\\n' > "$native/tools/mcbe_cli_create_test_db"
  chmod +x "$native/tools/mcbe_cli_create_test_db"
  echo fixture >> "$TRACE_FILE"
fi
''')
        executable(bins / 'python3', '''case "$1" in
  *session_smoke.py|*environment_smoke.py)
    script="$1"; shift
    [[ "$1" == --fixture-tool && -x "$2" && "$3" == -- ]] || exit 91
    echo "$(basename "$script")" >> "$TRACE_FILE" ;;
esac
''')
        executable(bins / 'xcrun', '''case "$*" in
  *--show-sdk-path*) echo /mock-sdk ;;
  *--find*) echo /mock-clang ;;
  *swiftc*)
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == -o ]]; then
        shift
        if [[ "$1" == */cli-native-tests ]]; then
          printf '#!/bin/bash\\nexit 0\\n' > "$1"; chmod +x "$1"
        else
          printf new-binary > "$1"
        fi
        break
      fi
      shift
    done ;;
  *) exit 99 ;;
esac
''')
        for failure in ('fixture', 'none'):
            target.write_bytes(b'previous-verified-binary')
            trace = root / ('trace-' + failure)
            env = dict(os.environ, PATH=str(bins) + os.pathsep + os.environ['PATH'],
                       FAIL_AT=failure, TRACE_FILE=str(trace))
            result = subprocess.run(['bash', str(scripts / 'build-apple.sh'), 'host', str(out), '--test'],
                                    env=env, capture_output=True, timeout=20)
            if failure == 'fixture':
                assert result.returncode != 0, 'fixture build failure did not fail the host build'
                assert target.read_bytes() == b'previous-verified-binary'
                assert not trace.exists(), 'smoke tests ran after a failed fixture build'
            else:
                assert result.returncode == 0, result.stderr
                assert trace.read_text().splitlines() == ['fixture', 'session_smoke.py', 'environment_smoke.py']
                assert target.read_bytes() == b'new-binary'
            assert not list(out.glob('.mcbe-build.*')), 'temporary host build left behind'
        print('PASS: Apple host tests receive a built database fixture; fixture failure preserves the prior CLI (tool doubles only)')


if __name__ == '__main__':
    main()
