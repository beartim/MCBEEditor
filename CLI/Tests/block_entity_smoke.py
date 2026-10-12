#!/usr/bin/env python3
"""Run fill/setblock entity modes through the actual CLI, export and reopen worlds."""
import argparse
import os
from pathlib import Path
import struct
import subprocess
import tempfile
from smoke_support import configure_utf8_output, create_test_database, snapshot


def template(identifier="Chest"):
    return (f"'Byte'\"Findable\"=\"0\",'List'''\"Items\"=\"\",'String'\"id\"=\"{identifier}\","
            "'Byte'\"isMovable\"=\"1\"")


def coordinates(x, y, z):
    return f",'Int'\"x\"=\"{x}\",'Int'\"y\"=\"{y}\",'Int'\"z\"=\"{z}\""


def tags(x, y, z, identifier="Chest"):
    return template(identifier) + coordinates(x, y, z)


def main():
    configure_utf8_output()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-tool", required=True, type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    executable = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not executable:
        parser.error("supply a CLI executable after --")
    calls = 0
    with tempfile.TemporaryDirectory(prefix="mcbe-block-entity-") as temporary:
        root = Path(temporary)
        source = root / "source world"
        create_test_database(source, args.fixture_tool.resolve())
        payload = b"\x0a\x00\x00\x03\x06\x00SpawnY" + struct.pack("<i", 64) + b"\x00"
        (source / "level.dat").write_bytes(struct.pack("<II", 8, len(payload)) + payload)
        original = snapshot(source)
        env = dict(os.environ, MCBEEDITOR_PORTABLE_ROOT=str(root / "portable"))

        def invoke(world, commands, output=None, expected=0):
            nonlocal calls
            calls += 1
            before = snapshot(world) if world.is_dir() else world.read_bytes()
            cache = root / f"cache-{calls}"
            argv = executable + ["--world", str(world), "--cache-dir", str(cache)]
            for command in commands:
                argv += ["--command", command]
            if output is not None:
                argv += ["--output", str(output)]
            result = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", timeout=60, env=env)
            assert result.returncode == expected, (commands, result.returncode, result.stdout, result.stderr)
            assert (snapshot(world) if world.is_dir() else world.read_bytes()) == before, "source changed"
            if expected == 2:
                assert not cache.exists() and (output is None or not output.exists()), "invalid template passed preflight"
            return result.stdout

        initial = root / "initial.mcworld"
        invoke(source, [
            "setblock overworld 0 64 0 minecraft:stone NULL minecraft:water NULL " + template(),
            "setblock overworld 1 64 0 minecraft:air NULL " + tags(-999, -999, -999, "arbitrary:peer"),
            "dimension add wzn:entity_test 1000",
            "fill wzn:entity_test 16 65 0 -1 64 -1 minecraft:stone NULL " + template("any:template")], initial)
        output = invoke(initial, ["getblock overworld 0 64 0", "getblock overworld 1 64 0"])
        assert "minecraft:stone" in output and "minecraft:water" in output and "arbitrary:peer" in output
        assert tags(0, 64, 0) in output, "user example did not round-trip through save/reopen"
        checks = [f"getblock 1000 {x} {y} {z}" for x in range(-1, 17) for y in (64, 65) for z in (-1, 0)]
        filled = invoke(initial, checks)
        assert filled.count("BlockEntity=[") == 72 and filled.count("any:template") == 72, "fill missed target entities"
        for x in range(-1, 17):
            for y in (64, 65):
                for z in (-1, 0):
                    assert tags(x, y, z, "any:template") in filled, "fill stored incorrect coordinates"

        preserved = root / "preserved.mcworld"
        invoke(initial, ["setblock overworld 0 64 0 minecraft:dirt NULL preserve",
                         "fill 1000 16 65 0 -1 64 -1 minecraft:dirt NULL preserve"], preserved)
        preserved_text = invoke(preserved, ["getblock overworld 0 64 0"] + checks)
        assert tags(0, 64, 0) in preserved_text and preserved_text.count("any:template") == 72
        empty = root / "empty.mcworld"
        invoke(preserved, ["setblock overworld 0 64 0 minecraft:dirt NULL empty",
                           "fill 1000 16 65 0 -1 64 -1 minecraft:dirt NULL empty"], empty)
        cleared = invoke(empty, ["getblock overworld 0 64 0", "getblock overworld 1 64 0"] + checks)
        assert cleared.count("BlockEntity=NULL") == 73 and "arbitrary:peer" in cleared
        replaced = root / "replaced.mcworld"
        invoke(initial, ["setblock overworld 0 64 0 minecraft:stone NULL " + tags(0, 64, 0, "different:entity")], replaced)
        replaced_text = invoke(replaced, ["getblock overworld 0 64 0", "getblock overworld 1 64 0"])
        assert tags(0, 64, 0, "different:entity") in replaced_text and "arbitrary:peer" in replaced_text
        ignored = root / "ignored-coordinates.mcworld"
        nested = ",'Compound'\"Nested\"=\"{'Int'\"x\"=\"999\",'String'\"y\"=\"keep\"}\""
        ignored_tags = ",'Float'\"X\"=\"0.75\",'String'\"Y\"=\"ignored\",'List'''\"z\"=\"\""
        invoke(initial, [
            "setblock overworld 137 64 -17 minecraft:stone NULL " + template("ignored:setblock") + nested + ignored_tags,
            "fill 1000 16 65 0 -1 64 -1 minecraft:dirt NULL " + tags(-999, -999, -999, "ignored:fill")], ignored)
        ignored_text = invoke(ignored, ["getblock overworld 137 64 -17"] + checks)
        assert template("ignored:setblock") + nested + coordinates(137, 64, -17) in ignored_text
        for x in range(-1, 17):
            for y in (64, 65):
                for z in (-1, 0):
                    assert tags(x, y, z, "ignored:fill") in ignored_text, "fill used supplied root coordinates"
        with_pos = root / "with-pos.mcworld"
        pos_tags = template("custom:with_pos") + ",'List''Float'\"Pos\"=\"1,64,0\""
        invoke(initial, ["setblock overworld 0 64 0 minecraft:stone NULL " + pos_tags,
                         "setblock overworld 0 64 0 minecraft:dirt NULL " + pos_tags], with_pos)
        assert pos_tags + coordinates(0, 64, 0) in invoke(with_pos, ["getblock overworld 0 64 0"])
        no_pos = root / "no-pos.mcworld"
        invoke(with_pos, ["setblock overworld 0 64 0 minecraft:stone NULL empty"], no_pos)
        assert "BlockEntity=NULL" in invoke(no_pos, ["getblock overworld 0 64 0"])
        for command in ["setblock overworld 0 64 0 minecraft:stone NULL",
                        "fill overworld 0 64 0 16 64 0 minecraft:stone NULL",
                        "setblock overworld 0 64 0 minecraft:stone NULL NULL",
                        "fill 1000 16 65 0 -1 64 -1 minecraft:stone NULL 'List'''\"Invalid\"=\"1\""]:
            invoke(initial, [command], root / f"invalid-{calls}.mcworld", expected=2)
        assert snapshot(source) == original
    print(f"Fill/setblock CLI block entities passed: {calls} processes, optional/ignored root coordinates, canonical Int positions, nested/Pos preservation, arbitrary IDs, all 72 cross-chunk positions, three modes, export/reopen and preflight rejection.")


if __name__ == "__main__":
    main()
