#!/usr/bin/env python3
"""Stage 03 dependency/contract wiring. Deliberately not a compiler or runtime test."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


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
    sources = set(read("CLI/iOS/sources.txt").splitlines())
    required = {"Sources/Command/WorldCommandExecutor.swift", "Sources/LevelDB/MojangLevelDB.swift",
                "Sources/World/WorldSession.swift", "Sources/World/MiniZipArchive.swift",
                "Sources/Chunk/BedrockBlockColumn.swift", "Sources/NBT/NBTTreeMutation.swift",
                "CLI/iOS/CliWorldWorkspace.swift", "CLI/iOS/CliWorldRunner.swift", "CLI/iOS/CliEntry.swift"}
    assert required <= sources
    declarations = {}
    for file in list((ROOT / "Sources").rglob("*.swift")) + list((ROOT / "CLI/iOS").glob("*.swift")):
        for name in re.findall(r"\b(?:struct|enum|class|protocol|typealias)\s+(\w+)", file.read_text(encoding="utf-8")):
            declarations.setdefault(name, set()).add(file.relative_to(ROOT).as_posix())
    for source in sources:
        text = read(source)
        if source == "Sources/World/WorldSession.swift":
            text = cli_session_source(text)
            assert "WorldStore" not in text and "ImportedWorld" not in text
            assert "func database()" in text and "func close()" in text
        assert not re.search(r"^import (UIKit|AppKit|SwiftUI)", text, re.M)
        for token in set(re.findall(r"\b[A-Z]\w*\b", text)):
            if token in declarations:
                assert declarations[token] & sources, f"missing declared type input {token}: {source} -> {declarations[token]}"
    print(f"PASS: {len(sources)} Swift input files; declared local type dependencies resolve under MCBE_CLI")
    assert "ChunkSurfaceRenderer" not in read("Sources/Command/WorldCommandExecutor.swift")
    assert "final class BedrockBlockReader" in read("Sources/Chunk/BedrockBlockColumn.swift")
    assert "try BedrockBlockReader(database: database).blockColumn" in read("Sources/Chunk/ChunkSurfaceRenderer.swift")
    assert "enum NBTTreeMutation" not in read("Sources/UI/NBTNode.swift")
    print("PASS: CLI and GUI share block data reads and NBT mutations without importing the map renderer")

    for backend, suffix in [("Windows", "cs"), ("iOS", "swift")]:
        options = read(f"CLI/{backend}/CliRunOptions.{suffix}")
        runner = read(f"CLI/{backend}/CliWorldRunner.{suffix}")
        for flag in ("--world", "--command", "--script", "--output", "--in-place", "--overwrite", "--keep-work", "--cache-dir"):
            assert flag in options, (backend, flag)
        assert "--in-place 与 --output 不能同时使用" in options
        assert "failures == 0" in runner and "130" in runner
        assert "未提交原位更新" in runner
    for file in ("CLI/Windows/CliWorldSession.cs", "CLI/iOS/CliWorldWorkspace.swift"):
        text = read(file)
        assert "原存档在本次处理期间发生变化" in text
        assert "原位提交及回滚失败" in text
    assert "ArchiveWorldPrefix" in read("Windows/MCBEEditor.Core/World/PortableWorldWorkspace.cs")
    assert "preserveAllFiles: true" in read("CLI/iOS/CliWorldWorkspace.swift")
    print("PASS: both backends expose explicit in-place/save-as, source-change checks, rollback reporting and archive layout preservation")

    build = read("CLI/Scripts/build-apple.sh")
    for dependency in ("CLI/Native/Apple/CMakeLists.txt", "Sources/Bridge/BTLevelDBBridge.mm",
                       "Sources/Bridge/BTCompressionBridge.mm", "Sources/MCBEEditor-Bridging-Header.h",
                       "CLI/iOS.Tests/NativeIntegration.swift", "Scripts/test_end_missing_subchunks.sh"):
        assert (ROOT / dependency).is_file()
    for required in ("-D MCBE_CLI", "-import-objc-header", "arm64-apple-ios13.0", "--target mcbe_cli_apple_bridge",
                     "NativeIntegration.swift", "test_end_missing_subchunks.sh", "vtool -show-build"):
        assert required in build, required
    assert "options.create_if_missing = false;" in read("Sources/Bridge/BTLevelDBBridge.mm")
    assert "0.8.0a8" in read("CLI/Scripts/bootstrap-apple-native.sh")
    assert "v1.3.1" in read("CLI/Scripts/bootstrap-apple-native.sh")
    print("PASS: native bridge, pinned dependencies, existing End regression and real native tests are wired into the Apple build")

    inventory = json.loads(read("CLI/Shared/command-inventory.json"))
    expected = {row["name"] for row in inventory["commands"]}
    for path in ("CLI/Windows.Tests/Program.cs", "CLI/iOS.Tests/NativeIntegration.swift"):
        tests = read(path)
        roots = set(re.findall(r'"([a-z]+) [^"\r\n]*"', tests)) | {"info"}
        assert expected <= roots, (path, expected - roots)
        for case in ("in-place-folder", "in-place-archive", "in-place-source-change", "output-race"):
            # Stage02 used the equivalent name export-race on Windows.
            assert case in tests or case == "output-race" and "export-race" in tests, (path, case)
    print("PASS: both native test programs include all 26 roots plus in-place, save-as, conflict and recovery cases")
    print("RESULT: source checks passed; C#/Swift/Objective-C++ compilation and runtime remain separate, unverified gates")


if __name__ == "__main__":
    main()
