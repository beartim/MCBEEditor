#!/usr/bin/env python3
"""Windows outer-EXE checks, including a real native LevelDB open.

Requires the native fixture generator from build-windows.ps1 -Test.
Never runs against a user's world. Does not replace gameplay validation.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from session_smoke import level_dat


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', required=True, type=Path)
    parser.add_argument('--fixture-tool', required=True, type=Path)
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('Windows is required; this test must not silently skip')
    exe, fixture = args.exe.resolve(strict=True), args.fixture_tool.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix='mcbe-portable-') as temporary:
        root = Path(temporary)
        binary = root / '中文 portable bin'
        cwd = root / '调用目录 with spaces'
        binary.mkdir()
        cwd.mkdir()
        target = binary / 'mcbe-cli.exe'
        shutil.copy2(exe, target)
        commands = binary / 'Commands'
        commands.mkdir()
        sentinel = b'# user command file must survive\r\n'
        (commands / 'Command.txt').write_bytes(sentinel)

        def run(argv, expected=0, data=None):
            result = subprocess.run([str(target), *argv], cwd=cwd, input=data,
                                    capture_output=True, timeout=60)
            assert result.returncode == expected, (argv, result.returncode, result.stdout, result.stderr)
            assert b'\x1b' not in result.stdout + result.stderr, 'redirected ANSI output'
            assert (commands / 'Command.txt').read_bytes() == sentinel, 'user script changed'
            runtime = binary / 'Cache' / 'Runtime'
            assert not runtime.exists() or not list(runtime.iterdir()), 'extraction left behind'
            return result

        run(['--unknown'], 2)
        run(['--check-file', 'missing.txt'], 3)
        run(['--check-file', '-'], data=b'weather query\n')
        run(['--interactive'], data=b':history\n:quit\n')
        relative = cwd / '命令 with spaces.txt'
        relative.write_text('weather query\n', encoding='utf-8')
        run(['--check-file', relative.name])
        # Fixture generator uses a narrow main(argv) on Windows: create at an
        # ASCII relative path, then move the closed DB into the Unicode world.
        subprocess.run([str(fixture), 'fixture-db'], cwd=root, check=True, timeout=30)
        world = cwd / '测试世界 with spaces'
        world.mkdir()
        shutil.move(str(root / 'fixture-db'), world / 'db')
        (world / 'level.dat').write_bytes(level_dat())
        before = {p.relative_to(world): p.read_bytes() for p in world.rglob('*') if p.is_file()}
        run(['--world', world.name, '--command', 'chunk query'])
        after = {p.relative_to(world): p.read_bytes() for p in world.rglob('*') if p.is_file()}
        assert before == after, 'read-only native query changed the source world'
        assert (commands / 'ReadMe.txt').is_file()
        assert not (cwd / 'Commands').exists(), 'portable root changed to caller cwd'
    print('PASS: outer EXE Unicode/relative paths, stdin, exit codes, native LevelDB, cleanup and Command.txt preservation')


if __name__ == '__main__':
    main()
