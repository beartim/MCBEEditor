#!/usr/bin/env python3
"""Real CLI regression for level.dat-only commands and batch commit semantics.

Dimension preflight requires a valid native database fixture. Database/terrain
behavior stays in the dedicated integration suites.
Run: python3 environment_smoke.py --fixture-tool /path/to/tool -- /path/to/mcbe-cli
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import zipfile
from smoke_support import configure_utf8_output, create_test_database, snapshot


def initial_level_dat():
    payload = b"\x0a\x00\x00\x03\x06\x00SpawnY" + struct.pack("<i", 64) + b"\x00"
    return struct.pack("<II", 8, len(payload)) + payload


def numeric_tags(data):
    """Read only the flat numeric fixture; independent of either product codec."""
    assert len(data) >= 12 and struct.unpack_from("<I", data, 4)[0] == len(data) - 8
    assert data[8] == 10
    offset = 11 + struct.unpack_from("<H", data, 9)[0]
    values = {}
    formats = {1: "b", 2: "h", 3: "i", 4: "q", 5: "f", 6: "d"}
    while data[offset] != 0:
        tag_type = data[offset]
        length = struct.unpack_from("<H", data, offset + 1)[0]
        offset += 3
        name = data[offset:offset + length].decode("utf-8")
        offset += length
        assert tag_type in formats, (name, tag_type)
        fmt = "<" + formats[tag_type]
        assert name not in values, name
        values[name] = (tag_type, struct.unpack_from(fmt, data, offset)[0])
        offset += struct.calcsize(fmt)
    assert offset + 1 == len(data)
    return values


def main():
    configure_utf8_output()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-tool", required=True, type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    executable = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not executable:
        parser.error("supply an executable after --")
    fixture_tool = args.fixture_tool.resolve(strict=True)
    count = 0
    with tempfile.TemporaryDirectory(prefix="mcbe-environment-") as temporary:
        root = Path(temporary)
        env = dict(os.environ, MCBEEDITOR_PORTABLE_ROOT=str(root / "Portable"),
                   MCBEEDITOR_CACHE_ROOT=str(root / "PortableCache"))

        def run(name, commands, expected, mode="query"):
            nonlocal count
            folder = root / name
            world = folder / "源世界 with spaces"
            create_test_database(world, fixture_tool)
            (world / "level.dat").write_bytes(initial_level_dat())
            (world / "db" / "fixture-sentinel.bin").write_bytes(b"preserve this unrelated file\x00\xff")
            before = snapshot(world)
            cache, destination = folder / "cache", folder / "result.mcworld"
            argv = executable + ["--world", str(world), "--cache-dir", str(cache)]
            for command in commands:
                argv += ["--command", command]
            if mode == "output":
                argv += ["--output", str(destination)]
            elif mode == "in-place":
                argv += ["--in-place"]
            result = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", timeout=30, env=env)
            assert result.returncode == expected, (name, result.returncode, result.stdout, result.stderr)
            if mode != "in-place" or expected != 0:
                assert snapshot(world) == before, name + ": source changed"
            assert (world / "db" / "fixture-sentinel.bin").read_bytes() == before["db/fixture-sentinel.bin"]
            saved = None
            if mode == "output" and expected in (0, 1):
                with zipfile.ZipFile(destination) as archive:
                    saved = numeric_tags(archive.read("level.dat"))
                    assert archive.read("db/fixture-sentinel.bin") == before["db/fixture-sentinel.bin"]
                    assert archive.read("db/CURRENT"), "export omitted the database manifest pointer"
            if mode == "in-place" and expected == 0:
                saved = numeric_tags((world / "level.dat").read_bytes())
            if expected == 2:
                assert not cache.exists() and not destination.exists(), name + ": preflight had side effects"
            if expected == 1:
                copies = list(cache.glob("*/World/level.dat"))
                assert len(copies) == 1, (name, copies)
                assert numeric_tags(copies[0].read_bytes())["Time"] == (4, 7)
            count += 1
            return result, saved

        result, _ = run("read-only", ["help WeAtHeR", "weather query", "time query gametime", "time query day"], 0)
        assert "doWeatherCycle=1" in result.stdout and "gametime=0" in result.stdout and "day=0" in result.stdout

        result, saved = run("negative-time-weather", [
            "daylock 1", "time set 24001", "time add -24002", "time query daytime", "time query day",
            "time floor noon", "time query gametime", "time ceil sunrise", "weather thunder 20 0.5 0", "daylock 0"
        ], 0, "output")
        assert "daytime=23999" in result.stdout and "day=-1" in result.stdout and "gametime=-18000" in result.stdout
        assert saved["Time"] == (4, 22201) and saved["dodaylightcycle"] == (1, 1)
        assert saved["rainLevel"] == (5, 0.5) and saved["lightningLevel"] == (5, 0.5)
        assert saved["rainTime"] == (3, 20) and saved["doWeatherCycle"] == (1, 0)

        overflow = ["time set 9223372036854775807", "time add 1", "time query gametime", "time set 7"]
        result, saved = run("runtime-error-save-as", overflow, 1, "output")
        assert "第 2 行执行失败" in result.stderr and "gametime=9223372036854775807" in result.stdout
        assert saved["Time"] == (4, 7)
        run("runtime-error-no-in-place-commit", overflow, 1, "in-place")
        _, saved = run("successful-in-place", ["time set 7", "daylock 1", "weather clear 1"], 0, "in-place")
        assert saved["Time"] == (4, 7) and saved["dodaylightcycle"] == (1, 0)
        assert saved["rainLevel"] == (5, 0.0) and saved["lightningLevel"] == (5, 0.0)
        assert saved["doWeatherCycle"] == (1, 1)
        run("syntax-rejects-entire-batch", ["time set 7", "weather rain 20 NaN 1", "time set 8"], 2, "in-place")
        run("unknown-help-rejects-entire-batch", ["time set 7", "help not_a_command"], 2, "output")
    print(f"PASS: {count} environment/batch scenarios; valid native database fixture")


if __name__ == "__main__":
    main()
