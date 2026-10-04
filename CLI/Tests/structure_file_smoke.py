#!/usr/bin/env python3
"""Check structure file preflight before any working copy or world mutation.
Usage: python3 CLI/Tests/structure_file_smoke.py -- /path/to/mcbe-cli
"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
from environment_smoke import initial_level_dat


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command: parser.error("supply a real CLI executable after --")
    with tempfile.TemporaryDirectory(prefix="mcbe-structure-preflight-") as tmp:
        root = Path(tmp)
        source = root / "world"
        source.mkdir()
        original = initial_level_dat()
        (source / "level.dat").write_bytes(original)
        cache = root / "cache"
        sentinel = root / "existing.json"
        sentinel.write_bytes(b"keep original")
        input_file = root / "input.json"
        input_file.write_text("{}", encoding="utf-8")
        directory = root / "directory.json"
        directory.mkdir()
        parent_file = root / "parent"
        parent_file.write_bytes(b"parent remains a file")
        def export(path, overwrite=False):
            return f'structure export json audit:one --file "{path}"' + (" --overwrite" if overwrite else "")
        env = dict(os.environ, MCBEEDITOR_PORTABLE_ROOT=str(root / "portable"))
        calls = 0
        def invoke(commands=None, script=None, output=None):
            nonlocal calls
            options = ["--world", str(source), "--cache-dir", str(cache)]
            options += ["--output", str(output)] if output else ["--in-place"]
            if script: options += ["--script", str(script)]
            else:
                for line in ["time set 222"] + commands: options += ["--command", line]
            result = subprocess.run(command + options, env=env, capture_output=True, timeout=30)
            assert result.returncode == 2, (options, result.returncode, result.stdout, result.stderr)
            assert result.stderr and not result.stdout, "preflight must fail before command output"
            assert "结构" in result.stderr.decode("utf-8") or b"structure" in result.stderr, "unrelated argument error masked the test"
            assert not cache.exists(), "preflight created a working copy"
            assert (source / "level.dat").read_bytes() == original
            assert sentinel.read_bytes() == b"keep original"
            assert input_file.read_text(encoding="utf-8") == "{}"
            assert parent_file.read_bytes() == b"parent remains a file"
            calls += 1
        for path, overwrite in [(source / "output.json", True), (cache / "output.json", True), (sentinel, False), (directory, True), (parent_file / "output.json", True)]:
            invoke([export(path, overwrite)])
        repeated = root / "repeated.json"
        invoke([export(repeated), export(repeated)])
        assert not repeated.exists()
        invoke([export(input_file, True), f'structure import audit:other --file "{input_file}"'])
        world_output = root / "output.mcworld"
        invoke([export(world_output / "nested.json")], output=world_output)
        assert not world_output.exists()
        script = root / "commands.json"
        text = "time set 222\n" + export(script, True) + "\n"
        script.write_text(text, encoding="utf-8")
        invoke(script=script)
        assert script.read_text(encoding="utf-8") == text
        invoke(["structure export json audit:one --file --overwrite"])
        assert not (source / "output.json").exists()
        # TXT keeps the same preflight protections as the existing file formats.
        def export_txt(path, overwrite=False):
            return f'structure export txt audit:one --file "{path}"' + (" --overwrite" if overwrite else "")
        for path in (source / "output.txt", cache / "output.txt", parent_file / "output.txt"):
            invoke([export_txt(path, True)])
        text_sentinel = root / "existing.txt"
        text_sentinel.write_bytes(b"keep original text")
        invoke([export_txt(text_sentinel)])
        assert text_sentinel.read_bytes() == b"keep original text"
        txt_input = root / "input.txt"
        txt_input.write_text("{}", encoding="utf-8")
        invoke([export_txt(txt_input, True), f'structure import audit:other --file "{txt_input}"'])
        assert txt_input.read_text(encoding="utf-8") == "{}"
        txt_repeated = root / "repeated.txt"
        invoke([export_txt(txt_repeated), export_txt(txt_repeated)])
        assert not txt_repeated.exists()
    print(f"PASS structure file preflight: {calls} real CLI invocations")


if __name__ == "__main__": main()
