#!/usr/bin/env python3
"""Run the same CLI contract against a real Swift or .NET executable."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend", choices=("windows", "swift"), required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    executable = args.command
    if executable and executable[0] == "--":
        executable = executable[1:]
    if not executable:
        parser.error("supply an executable after --")

    checks = 0

    def invoke(options, expected=0, data=None, label=""):
        nonlocal checks
        result = subprocess.run(executable + options, input=data, capture_output=True, timeout=30)
        stdout = result.stdout.decode("utf-8", errors="strict").replace("\r\n", "\n")
        stderr = result.stderr.decode("utf-8", errors="strict").replace("\r\n", "\n")
        if result.returncode != expected:
            raise AssertionError(
                f"{label or options}: exit {result.returncode}, expected {expected}\n"
                f"stdout={stdout}\nstderr={stderr}"
            )
        if expected == 0 and stderr:
            raise AssertionError(f"{label}: unexpected stderr: {stderr}")
        if expected != 0 and (not stderr or stdout):
            raise AssertionError(f"{label}: errors must be on stderr only: {stdout!r}, {stderr!r}")
        checks += 1
        return stdout, stderr

    inventory = json.loads((ROOT / "CLI/Shared/command-inventory.json").read_text(encoding="utf-8"))
    names = [row["name"] for row in inventory["commands"]]
    out, _ = invoke(["--list-commands"])
    assert out.splitlines() == names, "command list differs from the reviewed GUI inventory"
    out, _ = invoke(["--version"])
    version = {"windows": "MCBEEditor CLI 1.0.0", "swift": "MCBEEditor CLI 1.0.0"}
    assert out.strip() == version[args.backend]
    invoke([])
    invoke(["--help"])
    out, _ = invoke(["--help", "convert"])
    assert "little-varint" in out and "mcstructure" in out
    for name in names:
        out, _ = invoke(["--help", name])
        assert name in out, f"missing command help: {name}"
    invoke(["--help", "does-not-exist"], 2)
    for invalid in (["--check"], ["--check-file"], ["--unknown"], ["--version", "extra"]):
        invoke(invalid, 2)

    # A piped interactive session is not a terminal: meta history/clear work and ANSI must not leak.
    out, err = invoke(["--interactive"], data=b":history\n:clear\n:quit\n", label="redirected-interactive")
    assert ":history" in out and "\x1b" not in out and "\x1b" not in err

    cases = json.loads((ROOT / "CLI/Shared/parser-cases.json").read_text(encoding="utf-8"))
    for case in cases:
        valid = case.get("expected_by_backend", {}).get(args.backend, case["valid"])
        out, _ = invoke(["--check", case["command"]], 0 if valid else 2, label=case["id"])
        if valid:
            assert "1 条命令" in out and "未执行任何命令" in out

    with tempfile.TemporaryDirectory(prefix="mcbe-cli-smoke-") as temporary:
        directory = Path(temporary)
        path = directory / "命令 file.txt"
        payloads = (
            b"help\nweather query\n",
            b"\xef\xbb\xbfhelp\r\n\r\nweather query\r\n",
            b"help\rweather query",
        )
        for data in payloads:
            path.write_bytes(data)
            before = path.read_bytes()
            out, _ = invoke(["--check-file", str(path)])
            assert "2 条命令" in out
            assert path.read_bytes() == before, "preflight changed the source file"
            out, _ = invoke(["--check-file", "-"], data=data)
            assert "2 条命令" in out

        path.write_bytes(b"\xef\xbb\xbf\r\n \r\nhelp\r\n/clear\r\nunknown-command\r\n")
        _, err = invoke(["--check-file", str(path)], 2)
        assert "第 4 行" in err and "第 5 行" in err and "2 行有语法错误" in err
        for data in (b"", b"\xef\xbb\xbf\r\n\t\n"):
            path.write_bytes(data)
            out, _ = invoke(["--check-file", str(path)])
            assert "0 条命令" in out
        for data in (b"\xffhelp", b"help\xc3\x28", b"\xff\xfeh\x00e\x00l\x00p\x00"):
            path.write_bytes(data)
            invoke(["--check-file", str(path)], 3)
            invoke(["--check-file", "-"], 3, data=data)
        invoke(["--check-file", str(directory / "missing.txt")], 3)
        invoke(["--check-file", str(directory)], 3)

        # stage06 standalone converter: no world/session is involved.
        typed_json = directory / "typed input.json"
        typed_json.write_text(
            '{"format":"mcbeeditor-nbt-json","documents":[{"name":"","root":{"type":"compound","value":{"answer":{"type":"int","value":42},"name":{"type":"string","value":"cli"}}}}]}',
            encoding="utf-8",
        )
        little = directory / "typed little.nbt"
        varint = directory / "typed varint.nbt"
        big = directory / "typed big.nbt"
        roundtrip = directory / "typed roundtrip.json"
        invoke(["--convert", str(typed_json), "--to", "little-endian", "--output", str(little)])
        invoke(["--convert", str(little), "--to", "little-varint", "--output", str(varint)])
        invoke(["--convert", str(varint), "--to", "big-endian", "--output", str(big)])
        invoke(["--convert", str(big), "--to", "json", "--output", str(roundtrip)])
        assert little.exists() and varint.exists() and big.exists() and roundtrip.exists()
        invoke(["--convert", str(big), "--to", "json", "--output", str(roundtrip)], 3)
        invoke(["--convert", str(big), "--to", "json", "--output", str(roundtrip), "--overwrite"])

    print(f"PASS {args.backend}: {checks} process checks; {len(cases)} parser cases; 26 commands")


if __name__ == "__main__":
    main()
