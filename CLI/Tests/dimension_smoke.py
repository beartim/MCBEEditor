#!/usr/bin/env python3
"""Exercise dimension lifecycle on copies of the actual fixture and reopen exports."""
import argparse
import hashlib
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--world", type=Path, default=ROOT / "Tests/Fixtures/custom_dimensions.mcworld")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    executable = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not executable:
        parser.error("supply a real CLI executable after --")
    source = args.world.resolve()
    original = hashlib.sha256(source.read_bytes()).digest()
    calls = 0
    with tempfile.TemporaryDirectory(prefix="mcbe-dimension-") as temporary:
        root = Path(temporary)

        def invoke(world, commands=(), output=None, expected=0, script=None):
            nonlocal calls
            calls += 1
            argv = executable + ["--world", str(world), "--cache-dir", str(root / f"cache-{calls}")]
            if output:
                argv += ["--output", str(output)]
            if script:
                argv += ["--script", str(script)]
            for command in commands:
                argv += ["--command", command]
            result = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", timeout=90)
            if result.returncode != expected:
                raise AssertionError(f"{commands or script}: exit {result.returncode}, expected {expected}\n{result.stdout}\n{result.stderr}")
            assert hashlib.sha256(source.read_bytes()).digest() == original, "source archive changed"
            return result.stdout

        def dimensions(text):
            return {int(id): (name, int(chunks)) for name, id, chunks in re.findall(r"^(.+)=(-?\d+)，区块=(\d+)$", text, re.M)}

        initial = dimensions(invoke(source, ["dimension query"]))
        assert set(initial) == {0, 1000, 1001, 1002}, initial
        assert initial[1000] == ("wzn:bear", 0) and initial[1001][1] == 2
        empty = root / "empty.mcworld"
        cleared = dimensions(invoke(source, ["dimension empty wzn:cat", "dimension query"], empty))
        assert cleared[1001] == ("wzn:cat", 0)
        assert {k: v for k, v in cleared.items() if k != 1001} == {k: v for k, v in initial.items() if k != 1001}
        assert dimensions(invoke(empty, ["dimension query"])) == cleared
        purge = root / "purge.mcworld"
        purged = dimensions(invoke(source, ["dimension purge 1001", "dimension query"], purge))
        assert purged == {k: v for k, v in initial.items() if k != 1001}
        assert dimensions(invoke(purge, ["dimension query"])) == purged
        invoke(purge, ["getblock wzn:cat 0 64 0"], expected=2)
        restored = root / "restored.mcworld"
        result = dimensions(invoke(purge, ["dimension add wzn:cat 1001", "dimension add nether 1", "dimension add the_end 2", "dimension query"], restored))
        assert result[1001] == ("wzn:cat", 0) and result[1] == ("nether", 0) and result[2] == ("the_end", 0)
        assert dimensions(invoke(restored, ["dimension query"])) == result
        custom = root / "custom.mcworld"
        text = invoke(source, ["dimension add bear 1003", "setblock bear 0 64 0 minecraft:stone NULL", "getblock bear 0 64 0", "dimension query"], custom)
        assert "minecraft:stone" in text and dimensions(text)[1003] == ("bear", 1)
        assert "minecraft:stone" in invoke(custom, ["getblock bear 0 64 0"])
        for id in (43, 44, 47, 118, -2147483648, 2147483647):
            destination = root / f"collision-{id}.mcworld"
            name = f"collision_{id}"
            text = invoke(source, [f"dimension add {name} {id}", f"setblock {name} 0 64 0 minecraft:stone NULL", "dimension query"], destination)
            assert dimensions(text)[id] == (name, 1)
            assert "minecraft:stone" in invoke(destination, [f"getblock {id} 0 64 0"])
        rejected = root / "rejected.mcworld"
        for commands in [
            ["dimension add fresh 8000", "getblock fresh bad 0 0"],
            ["dimension add fresh 8000", "dimension add duplicate 8000"],
            ["dimension purge wzn:bear", "getblock wzn:bear 0 0 0"]
        ]:
            invoke(source, commands, rejected, expected=2)
            assert not rejected.exists()
        example = root / "example.mcworld"
        invoke(source, output=example, script=ROOT / "CLI/Examples/Dimension.txt")
        final = dimensions(invoke(example, ["dimension query"]))
        assert final == initial | {1004: ("wzn:demo", 0)}, final
    print(f"PASS dimension fixture smoke: {calls} real CLI invocations; lifecycle, names/IDs, vanilla recreation, byte collisions, example script, export/reopen and source integrity")


if __name__ == "__main__":
    main()
