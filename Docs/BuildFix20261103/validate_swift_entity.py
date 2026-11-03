#!/usr/bin/env python3
"""Evaluate the actual Apple native-test entity assertions with production Swift.

Only the database/platform fixture comes from run_core_tests.sh. Parser,
executor, NBT codecs, native-test player documents and assertion bodies are
compiled from the selected source tree. This does not run the Apple SDK/bridge.
"""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
import tempfile


def member(source: str, name: str) -> str:
    start = source.index("    static func " + name + "(")
    brace = source.index("{", start)
    depth, cursor = 1, brace + 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]


def run(root: Path) -> None:
    compiler = shutil.which("swiftc")
    if not compiler:
        raise SystemExit("Swift compiler required")
    runner = (root / "Scripts/run_core_tests.sh").read_text()
    fixture = runner.split('cat > "$TMP/EffectCommandStubs.swift" <<\'SWIFT\'\n', 1)[1].split("\nSWIFT", 1)[0]
    command = runner[:runner.index('"$TMP/effect-command-tests"\n')].rsplit("\nswiftc -j 4 \\\n", 1)[1]
    sources = [root / path for path in re.findall(r'"\$ROOT/([^"]+)"', command)]
    native = (root / "CLI/iOS.Tests/NativeIntegration.swift").read_text()
    methods = [member(native, "expect"), member(native, "player")]
    if "    static func entityDocuments(" in native:
        methods.append(member(native, "entityDocuments"))
    query_start = native.index("        let queriedPlayers =") if "        let queriedPlayers =" in native else native.index('        try expect(query.output.contains("entity：')
    query_checks = native[query_start:native.index("        try noWork(query)", query_start)]
    family_start = native.index("        let queriedPigs =") if "        let queriedPigs =" in native else native.index('        try expect(allFamilies.output.contains("minecraft:pig=[")')
    family_checks = native[family_start:native.index("        try noWork(allFamilies)", family_start)]
    empty_start = native.find('        try expect(emptyEntities.output.contains(')
    empty_checks = "" if empty_start < 0 else native[empty_start:native.index("        try noWork(emptyEntities)", empty_start)]
    driver = r'''
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
enum NativeIntegration {
__METHODS__
    struct Result { let output: String }
    static func runContract() throws {
        let session = WorldSession()
        defer { try? FileManager.default.removeItem(at: session.document.rootURL) }
        try session.db.put(BedrockNBTCodec.encode(player(1001)), for: Data("~local_player".utf8))
        try session.db.put(BedrockNBTCodec.encode(player(2002)), for: Data("player_server_2002".utf8))
        let executor = WorldCommandExecutor(session: session)
        func invoke(_ command: String) throws -> Result {
            let result = try executor.execute(WorldCommandParser.parse(command))
            try expect(!result.changedWorld, "entity queries must stay read-only")
            return Result(output: result.message)
        }
        let before = session.db.values
        let query = try invoke("entity")
__QUERY_CHECKS__
        let emptyEntities = try invoke("entity minecraft:cow")
__EMPTY_CHECKS__
        try expect(session.db.values == before, "entity output validation changed database records")
        _ = try executor.execute(WorldCommandParser.parse("summon minecraft:pig overworld 0.5 65 0.5 default 9007199254740993"))
        _ = try executor.execute(WorldCommandParser.parse(#"summon 'String'"identifier"="minecraft:cow",'List''Float'"Pos"="0.0,64.0,0.0",'Long'"UniqueID"="12345678""#))
        let pig = try invoke("entity overworld 0.5 65 0.5 0.5 65 0.5")
        let cow = try invoke("entity overworld 0 64 0 0 64 0")
        let allFamilies = Result(output: pig.output + "\n" + cow.output)
__FAMILY_CHECKS__
    }
}
@main
enum Main {
    static func main() {
        do {
            try NativeIntegration.runContract()
            print("PASS: actual Swift native entity assertions with production parser/executor/codecs; two players, empty selector, exact Long, raw cow NBT and metadata (memory DB boundary)")
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
'''
    driver = driver.replace("__METHODS__", "\n".join(methods)).replace("__QUERY_CHECKS__", query_checks).replace("__EMPTY_CHECKS__", empty_checks).replace("__FAMILY_CHECKS__", family_checks)
    with tempfile.TemporaryDirectory(prefix="mcbe-native-entity-contract-") as directory:
        temp = Path(directory)
        (temp / "fixture.swift").write_text(fixture)
        (temp / "main.swift").write_text(driver)
        output = temp / "native-entity-contract"
        subprocess.run([compiler, "-j", "4", "-swift-version", "5", *map(str, sources), str(temp / "fixture.swift"), str(temp / "main.swift"), "-parse-as-library", "-o", str(output)], check=True)
        subprocess.run([str(output)], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    run(parser.parse_args().root.resolve())
