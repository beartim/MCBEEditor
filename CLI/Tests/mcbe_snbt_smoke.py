#!/usr/bin/env python3
"""MCBE-SNBT byte-exact fixtures, error atomicity and cross-language interchange.

python3 CLI/Tests/mcbe_snbt_smoke.py --backend cli -- /path/to/mcbe-cli
Probe contract: probe decode|encode INPUT OUTPUT (nonzero + stderr on errors).
"""
from __future__ import annotations
import argparse
import gzip
import json
import os
from pathlib import Path
import subprocess
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend', choices=('cli', 'probe'), default='cli')
    parser.add_argument('--artifact-dir', type=Path)
    parser.add_argument('--input-canonical', type=Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('supply a real executable after --')
    cases = json.loads((ROOT / 'Tests/Fixtures/mcbe_snbt.json').read_text(encoding='utf-8'))['cases']
    imported = json.loads(args.input_canonical.read_text(encoding='utf-8')) if args.input_canonical else None
    calls, checked, canonical = 0, 0, {}
    with tempfile.TemporaryDirectory(prefix='mcbe-snbt-') as tmp:
        root = Path(tmp)
        env = dict(os.environ, MCBEEDITOR_PORTABLE_ROOT=str(root / 'portable'))
        def invoke(operation, source, target, *, success=True, overwrite=True, fmt=None):
            nonlocal calls
            if args.backend == 'probe':
                options = [operation, str(source), str(target)]
            else:
                options = ['--convert', str(source), '--to', fmt or ('little-endian' if operation == 'decode' else 'txt'), '--output', str(target)]
                if overwrite:
                    options.append('--overwrite')
            result = subprocess.run(command + options, env=env, capture_output=True, timeout=30)
            assert result.returncode >= 0, (source.name, 'process crashed', result.returncode, result.stderr)
            if success:
                assert result.returncode == 0, (source.name, options, result.returncode, result.stdout, result.stderr)
                assert not result.stderr, result.stderr
                assert target.is_file(), target
            else:
                assert result.returncode != 0 and result.stderr, (source.name, options, result.returncode, result.stdout, result.stderr)
                assert not result.stdout, 'failure reported success'
            assert not list(root.glob('.mcbe-convert-*.tmp')), 'temporary output leaked'
            calls += 1

        for case in cases:
            name = case['id']
            source = root / (name + '.txt')
            binary = root / (name + '.nbt')
            if case['valid']:
                expected = bytes.fromhex(case['little_endian_hex'])
                if imported is not None:
                    source.write_text(imported[name], encoding='utf-8')
                    invoke('decode', source, binary)
                    assert binary.read_bytes() == expected, (name, 'cross-language mismatch')
                else:
                    if case.get('binary_only'):
                        binary.write_bytes(expected)
                    else:
                        source.write_text(case['text'], encoding='utf-8')
                        invoke('decode', source, binary)
                        assert binary.read_bytes() == expected, (name, 'decode mismatch', binary.read_bytes().hex(), expected.hex())
                    exported = root / (name + '-export.txt')
                    invoke('encode', binary, exported)
                    text = exported.read_text(encoding='utf-8')
                    assert text.strip().startswith('[') and text.strip().endswith(']'), name
                    for fragment in case.get('canonical_fragments', []):
                        assert fragment in text, (name, 'canonical empty-list spelling', fragment, text)
                    canonical[name] = text
                    roundtrip = root / (name + '-roundtrip.nbt')
                    invoke('decode', exported, roundtrip)
                    assert roundtrip.read_bytes() == expected, (name, 'roundtrip mismatch')
            elif imported is None:
                source.write_text(case['text'], encoding='utf-8')
                binary.write_bytes(b'keep existing output')
                invoke('decode', source, binary, success=False)
                assert binary.read_bytes() == b'keep existing output', name
            else:
                continue
            checked += 1

        if imported is None:
            malformed = root / 'invalid-bytes.txt'
            target = root / 'invalid-bytes.nbt'
            # Explicit .txt must be strict UTF-8, not binary sniffing or lossy replacement.
            for payload in (b'\xff', b"'String'\"s\"=\"\xc0\xaf\"", ('\'Compound\'"n"="{' * 400 + '\'Int\'"x"="1"' + '}"' * 400).encode()):
                malformed.write_bytes(payload)
                target.write_bytes(b'preserve target')
                invoke('decode', malformed, target, success=False)
                assert target.read_bytes() == b'preserve target'
                checked += 1
            if args.backend == 'cli':
                plain = root / 'sample.nbt'
                expected = bytes.fromhex(cases[0]['little_endian_hex'])
                plain.write_bytes(expected)
                textfile = root / 'sample.txt'
                invoke('encode', plain, textfile, fmt='mcbe-snbt')
                sentinel = textfile.read_bytes()
                invoke('encode', plain, textfile, overwrite=False, success=False)
                assert textfile.read_bytes() == sentinel
                wrong = root / 'wrong.json'
                wrong.write_bytes(b'extension guard')
                invoke('encode', plain, wrong, success=False)
                assert wrong.read_bytes() == b'extension guard'
                for wrapper in (gzip.compress, zlib.compress):
                    compressed = root / 'compressed.nbt'
                    compressed.write_bytes(wrapper(expected))
                    invoke('encode', compressed, textfile)
                    invoke('decode', textfile, plain)
                    assert plain.read_bytes() == expected
                # Text files are accepted under mixed-case extensions; unlike JSON [],
                # an empty MCBE-SNBT root sequence remains invalid.
                upper = root / 'mixed.TXT'
                upper.write_text(cases[0]['text'], encoding='utf-8')
                invoke('decode', upper, plain)
                assert plain.read_bytes() == expected
                # Converting TXT through all binary encodings must keep the same roots.
                for encoding in ('big-endian', 'little-varint'):
                    intermediate = root / (encoding + '.nbt')
                    invoke('decode', upper, intermediate, fmt=encoding)
                    invoke('encode', intermediate, textfile)
                    invoke('decode', textfile, plain)
                    assert plain.read_bytes() == expected
    if args.artifact_dir and imported is None:
        args.artifact_dir.mkdir(parents=True, exist_ok=True)
        (args.artifact_dir / (args.backend + '-canonical.json')).write_text(json.dumps(canonical, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    mode = 'cross-language' if imported is not None else 'fixtures/atomicity'
    print(f'PASS MCBE-SNBT {args.backend} {mode}: {checked} cases, {calls} real process invocations')


if __name__ == '__main__':
    main()
