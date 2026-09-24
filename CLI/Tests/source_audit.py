#!/usr/bin/env python3
"""Check inventory coverage and headless build inputs. This is not compilation."""
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


def read(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


def cli_session_source(source):
    active, output = [True], []
    for line in source.splitlines():
        directive = line.strip()
        if directive == "#if !MCBE_CLI":
            active.append(False)
        elif directive == "#if MCBE_CLI":
            active.append(True)
        elif directive == "#else":
            active[-1] = not active[-1]
        elif directive == "#endif":
            assert len(active) > 1
            active.pop()
        elif all(active):
            output.append(line)
    assert active == [True], "unbalanced session build conditions"
    return "\n".join(output)


def main():
    inventory = json.loads(read("CLI/Shared/command-inventory.json"))
    expected = [row["name"] for row in inventory["commands"]]
    swift = read("Sources/Command/WorldCommand.swift")
    windows = read("Windows/MCBEEditor.Desktop/CommandHelpCatalog.cs")
    swift_names = re.findall(r'"([a-z]+)"', re.search(r'commandNames[^=]*=\s*\[(.*?)\]', swift, re.S)[1])
    windows_names = re.findall(r'"([a-z]+)"', re.search(r'CommandOrder\s*=\s*\[(.*?)\]', windows, re.S)[1])
    assert len(expected) == len(set(expected)) == 26
    assert expected == swift_names == windows_names, "top-level command inventory drift"
    swift_help = dict((m[1], json.loads(m[2])) for m in re.finditer(
        r'^\s*"([a-z]+)": ("(?:[^"\\]|\\.)*")\s*,?$', swift, re.M))
    windows_help = dict((m[1], json.loads(m[2])) for m in re.finditer(
        r'^\s*\["([a-z]+)"\] = ("(?:[^"\\]|\\.)*")\s*,?$', windows, re.M))
    assert set(expected) == set(swift_help) == set(windows_help)
    for row in inventory["commands"]:
        assert row["gui_usage"] == swift_help[row["name"]] == windows_help[row["name"]], row["name"]
        assert row["coverage"], row["name"]
    print("PASS: 26 GUI names and both help catalogs match the saved inventory")

    router = read("CLI/Windows/CliCommandParser.cs")
    for name in {row["windows_parser"] for row in inventory["commands"]} - {"CliCommandParser"}:
        assert f"{name}.Parse(trimmed)" in router, f"parser not routed: {name}"
        source = read(f"Windows/MCBEEditor.Core/Chunk/{name.removesuffix('Parser')}.cs")
        if name != "ChunkCommandParser":
            detector = re.search(r'public static bool Is\w+Command\(string text\)(.*?)(?=public static)', source, re.S)[1]
            for row in inventory["commands"]:
                if row["windows_parser"] == name:
                    assert f'"{row["name"]}"' in detector, f"incorrect parser mapping: {row['name']}"
    print("PASS: all seven Windows parser families are wired to the original implementations")

    executor = read("CLI/Windows/CliWorldCommandExecutor.cs")
    for family in ("BlockCommand", "StorageBiomeCommand", "TargetingCommand", "EntityActionCommand"):
        names = re.findall(r"public sealed record (\w*CommandRequest)\b", read(f"Windows/MCBEEditor.Core/Chunk/{family}.cs"))
        assert names, family
        for name in names:
            assert name in executor, f"missing concrete command route: {name}"
    for name in ("EnvironmentCommandRequest", "StructureTemplateStructureCommandRequest", "ChunkCommandRequest", "HelpCliCommand"):
        assert name in executor, name
    print("PASS: concrete Windows command requests have executor routes")

    project = ROOT / "CLI/Windows/MCBEEditor.Cli.csproj"
    xml = ET.parse(project).getroot()
    assert xml.findtext("PropertyGroup/OutputType") == "Exe"
    assert xml.findtext("PropertyGroup/TargetFramework") == "net10.0"
    assert xml.find(".//UseWPF") is None
    includes = [e.attrib["Include"] for e in xml.findall(".//ProjectReference") + xml.findall(".//Compile")]
    assert len(includes) == 2
    for relative in includes:
        assert (project.parent / relative).resolve().is_file(), relative
    assert all("Desktop.csproj" not in value for value in includes)
    core = ROOT / "Windows/MCBEEditor.Core"
    for source in core.rglob("*.cs"):
        assert not re.search(r'^using (System\.Windows(?:;|\.)|MCBEEditor\.Desktop)', source.read_text(encoding="utf-8"), re.M), source
    print("PASS: Windows console project references Core and the strings-only help file; no WPF dependency")

    sources = read("CLI/iOS/sources.txt").splitlines()
    assert len(sources) == len(set(sources))
    assert "Sources/Command/WorldCommand.swift" in sources
    assert set((ROOT / "CLI/iOS").glob("*.swift")) <= {ROOT / path for path in sources}
    declarations = {}
    for file in list((ROOT / "Sources").rglob("*.swift")) + list((ROOT / "CLI/iOS").glob("*.swift")):
        for name in re.findall(r"\b(?:struct|enum|class|protocol|typealias)\s+(\w+)", file.read_text(encoding="utf-8")):
            declarations.setdefault(name, set()).add(file.relative_to(ROOT).as_posix())
    for relative in sources:
        content = read(relative)
        if relative == "Sources/World/WorldSession.swift":
            content = cli_session_source(content)
        for token in set(re.findall(r"\b[A-Z]\w*\b", content)):
            if token in declarations:
                assert declarations[token] & set(sources), f"missing Swift type input: {token} in {relative}"
        assert not re.search(r'^import (UIKit|AppKit|SwiftUI)', content, re.M), relative
        assert not relative.startswith("Sources/UI/"), relative
    for source in list((ROOT / "CLI/Windows").glob("*.cs")) + list((ROOT / "CLI/iOS").glob("*.swift")):
        assert not re.search(r'\b(MessageBox|OpenFileDialog|SaveFileDialog|UIApplication)\b', source.read_text(encoding="utf-8")), source
    print(f"PASS: {len(sources)} Swift build inputs exist and do not import a GUI framework")

    cases = json.loads(read("CLI/Shared/parser-cases.json"))
    assert not any("expected_by_backend" in row for row in cases), "fixtures must share one contract"
    assert len({row["id"] for row in cases}) == len(cases)
    valid_names = {row["command"].split()[0] for row in cases if row["valid"]}
    assert set(expected) <= valid_names
    fixture_text = "\n".join(row["command"] for row in cases)
    for required in ("weather query", "structure import", "structure export nbt", "experience percent", "kick @a"):
        assert required in fixture_text
    assert any(row["valid"] and row["command"].count("minecraft:stone NULL") == 255 for row in cases)
    assert any(not row["valid"] and row["command"].count("minecraft:stone NULL") == 256 for row in cases)
    print(f"PASS: {len(cases)} executable parser fixtures cover all commands and storage boundaries")
    print("RESULT: source audit passed; compiler and executable behavior remain separate validation gates")


if __name__ == "__main__":
    main()
