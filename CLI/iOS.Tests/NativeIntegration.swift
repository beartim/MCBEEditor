import Foundation
import Darwin

private struct EndFixture: Decodable {
    struct Entry: Decodable { let keyBase64: String; let valueBase64: String }
    let paletteVersion: Int32
    let v8Chunk: [Int32]
    let v1Chunk: [Int32]
    let emptyChunk: [Int32]
    let entries: [Entry]
}

@main
enum NativeIntegration {
    static var runs = 0
    static let manager = FileManager.default
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw CliError.file("Swift native integration: " + message) }
    }

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 2, manager.fileExists(atPath: args[0]), manager.fileExists(atPath: args[1]) else {
            MCBEEditorCli.writeError("Pass the native fixture tool and the original End fixture JSON. Missing native dependencies are not skipped.")
            exit(2)
        }
        let root = CliWorldPaths.canonical(manager.temporaryDirectory.appendingPathComponent("mcbe-cli-native-" + UUID().uuidString).path)
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? manager.removeItem(at: root) }
            try run(root, tool: args[0], fixturePath: args[1])
            print("PASS Swift CLI native integration: \(runs) invocation cases; real Mojang LevelDB, original End fixture, in-place and save-as persistence.")
        } catch { MCBEEditorCli.writeError(error.localizedDescription); exit(1) }
    }

    static func createWorld(_ root: URL, tool: String, fixture: EndFixture) throws -> URL {
        let source = root.appendingPathComponent("源世界", isDirectory: true)
        try manager.createDirectory(at: source, withIntermediateDirectories: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.currentDirectoryURL = source
        process.arguments = ["db"]
        try process.run()
        process.waitUntilExit()
        try expect(process.terminationStatus == 0, "native fixture tool failed")
        let session = WorldSession(rootURL: source, displayName: "CLI 测试")
        defer { session.close() }
        try session.document.writeLevelDat(LevelDatFile(version: 8, document: NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "LevelName", value: .string("CLI 原生测试")),
            NBTNamedTag(name: "StorageVersion", value: .int(8)),
            NBTNamedTag(name: "RandomSeed", value: .long(1_234_567)),
            NBTNamedTag(name: "Time", value: .long(100)),
            NBTNamedTag(name: "SpawnX", value: .int(0)), NBTNamedTag(name: "SpawnY", value: .int(65)),
            NBTNamedTag(name: "SpawnZ", value: .int(0)), NBTNamedTag(name: "GameType", value: .int(0))
        ]))))
        let database = try session.database()
        for entry in fixture.entries {
            try database.put(Data(base64Encoded: entry.valueBase64)!, for: Data(base64Encoded: entry.keyBase64)!)
        }
        var indices = Array(repeating: UInt16(0), count: 4096)
        for x in 0..<16 { for z in 0..<16 { indices[(x << 8) | (z << 4)] = 1 } }
        let floor = BedrockSubChunk(version: 8, yIndex: 4, storages: [SubChunkStorage(bitsPerBlock: 1,
            palette: [.editableAir(version: fixture.paletteVersion), CommandBlockStateSpec(name: "minecraft:stone", states: []).modernState(version: fixture.paletteVersion)],
            indices: indices)], trailingData: Data())
        try database.put(floor.encodePersistent(), for: BedrockDBKey.subChunk(x: 0, z: 0, dimension: 0, index: 4))
        let position = ChunkPosition(x: 0, z: 0, dimension: 0)
        for (type, data) in [(ChunkRecordType.legacyVersion, Data([19])), (.finalizedState, Data([2, 0, 0, 0])), (.data2D, Data(repeating: 0, count: 768))] {
            try database.put(data, for: BedrockDBKey(position: position, recordType: type, subChunkIndex: nil).encoded())
        }
        try database.put(BedrockNBTCodec.encode(player(1001), encoding: .littleEndian), for: Data("~local_player".utf8))
        try database.put(BedrockNBTCodec.encode(player(2002), encoding: .littleEndian), for: Data("player_server_2002".utf8))
        try database.put(Data([0, 128, 255, 1]), for: Data("cli_unknown_record".utf8))
        try Data([0, 1, 128, 255]).write(to: source.appendingPathComponent("untouched.bin"))
        try manager.createDirectory(at: source.appendingPathComponent(".mcbeeditor"), withIntermediateDirectories: false)
        try Data("editor-only".utf8).write(to: source.appendingPathComponent(".mcbeeditor/private.txt"))
        return source
    }

    static func player(_ id: Int64) -> NBTDocument {
        let inventory: [NBTValue] = (0..<36).map { slot in .compound([
            NBTNamedTag(name: "Name", value: .string("")), NBTNamedTag(name: "Count", value: .byte(0)), NBTNamedTag(name: "Slot", value: .byte(Int8(slot)))
        ]) }
        return NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "PlayerName", value: .string("CLI Player \(id)")), NBTNamedTag(name: "UniqueID", value: .long(id)),
            NBTNamedTag(name: "DimensionId", value: .int(0)), NBTNamedTag(name: "PlayerGameMode", value: .int(0)),
            NBTNamedTag(name: "Pos", value: .list(.float, [.float(0.5), .float(65), .float(0.5)])),
            NBTNamedTag(name: "PlayerLevel", value: .int(3)), NBTNamedTag(name: "PlayerLevelProgress", value: .float(0.5)),
            NBTNamedTag(name: "Inventory", value: .list(.compound, inventory)),
            NBTNamedTag(name: "Attributes", value: .list(.compound, [.compound([
                NBTNamedTag(name: "Name", value: .string("minecraft:health")), NBTNamedTag(name: "Current", value: .float(20))
            ])]))
        ]))
    }

    static func run(_ root: URL, tool: String, fixturePath: String) throws {
        let fixture = try JSONDecoder().decode(EndFixture.self, from: Data(contentsOf: URL(fileURLWithPath: fixturePath)))
        let source = try createWorld(root, tool: tool, fixture: fixture)
        let original = try CliFileSystem.stamp(source)
        struct Result { let output: String; let error: String; let cache: URL }
        func invoke(_ name: String, _ expected: Int32, _ options: [String], input: URL? = nil,
                    onOutput: ((String) -> Void)? = nil, cancelled: () -> Bool = { false }) throws -> Result {
            let cache = root.appendingPathComponent("Cache/" + name)
            var output = [String](), error = [String]()
            let exit = MCBEEditorCli.run(["--world", (input ?? source).path, "--cache-dir", cache.path] + options,
                output: { output.append($0); onOutput?($0) }, error: { error.append($0) }, cancelled: cancelled)
            try expect(exit == expected, "\(name) exit=\(exit) expected=\(expected)\n\(output.joined(separator: "\n"))\n\(error.joined(separator: "\n"))")
            try expect(try CliFileSystem.stamp(source) == original, name + " changed the input source")
            runs += 1
            return Result(output: output.joined(separator: "\n"), error: error.joined(separator: "\n"), cache: cache)
        }
        func invokeStandalone(_ name: String, _ expected: Int32, _ argv: [String]) throws -> Result {
            var output = [String](), error = [String]()
            let exit = MCBEEditorCli.run(argv, output: { output.append($0) }, error: { error.append($0) })
            try expect(exit == expected, "\(name) exit=\(exit) expected=\(expected)\n\(output.joined(separator: "\n"))\n\(error.joined(separator: "\n"))")
            try expect(try CliFileSystem.stamp(source) == original, name + " changed the input source")
            runs += 1
            return Result(output: output.joined(separator: "\n"), error: error.joined(separator: "\n"), cache: root)
        }
        func noWork(_ result: Result) throws {
            if manager.fileExists(atPath: result.cache.path) {
                try expect(try manager.contentsOfDirectory(atPath: result.cache.path).isEmpty, "successful session leaked its working copy")
            }
        }
        func recovery(_ result: Result) throws -> URL {
            let line = result.error.components(separatedBy: "\n").first { $0.hasPrefix("工作副本已保留：") }
            guard let line = line else { throw CliError.file("missing recovery path") }
            let path = URL(fileURLWithPath: String(line.dropFirst("工作副本已保留：".count)))
            try expect(manager.fileExists(atPath: path.path), "recovery directory missing")
            return path
        }
        let invalid = root.appendingPathComponent("语法错误.txt")
        try Data("\u{FEFF}time set 222\r\n\r\nweather nope\r\nunknown-command\r\n".utf8).write(to: invalid)
        let syntax = try invoke("syntax", 2, ["--script", invalid.path, "--in-place"])
        try expect(!manager.fileExists(atPath: syntax.cache.path) && syntax.error.contains("第 3 行") && syntax.error.contains("第 4 行"), "batch preflight or physical line numbers")
        try noWork(invoke("required-output", 2, ["--command", "time set 222"]))
        try noWork(invoke("unsupported-structure", 2, ["--command", "time set 222", "--command", "structure import cli:house", "--in-place"]))
        let query = try invoke("queries", 0, ["--command", "help weather", "--command", "info", "--command", "weather query", "--command", "chunk query", "--command", "structure query"])
        try expect(query.output.contains("doWeatherCycle=1") && query.output.contains("SubChunk v8") && query.output.contains("IsSlimeChunk=") && query.output.contains("Ticking="), "query formatting/defaults")
        try noWork(query)

        let commands = [
            "daylock 1", "time set 12345", "time query gametime", "weather thunder 12000 0.5 0",
            "tickingarea add circle overworld 0 0 0 home 1", "tickingarea list ALL",
            "setworldspawn 0 70 0", "spawnpoint @s overworld 0 70 0", "clearspawnpoint @s",
            "experience level @s 30", "experience percent @s 0.5", "experience query @s",
            "give @s Auto minecraft:diamond 3 NULL", "effect give @s strength 1000 255", "effect clear @s ALL", "clear @s",
            "summon minecraft:pig overworld 0.5 65 0.5 default", "kill minecraft:pig 0", "kick @a",
            "fill overworld 0 65 0 3 65 0 minecraft:stone NULL", "setblock overworld 1 65 0 minecraft:dirt NULL",
            "clone overworld 0 65 0 2 65 0 overworld 1 65 0", "fillbiome overworld 0 0 0 15 127 15 9",
            "setblock the_end 35 200 5 minecraft:diamond_block NULL", "storage set the_end 3 220 5 254 minecraft:stone NULL",
            "storage query the_end 3 220 5", "storage set the_end 3 240 5 2 minecraft:stone NULL",
            "storage delete the_end 3 240 5 2", "storage clear the_end 3 240 5 0",
            "structure save cli:house overworld 0 65 0 3 65 0", "structure query", "structure load cli:house overworld 0 70 0",
            "structure delete cli:house", "chunk empty nether 1 1", "chunk regenerate nether 1 1",
            "spread @s", "teleport @s overworld 2.0 64 3.0", "getblock the_end 35 200 5", "chunk query"
        ]
        let script = root.appendingPathComponent("命令 file.txt"), saved = root.appendingPathComponent("edited.mcworld")
        let scriptData = Data(("\u{FEFF}" + commands.joined(separator: "\r\n") + "\r\n").utf8)
        try scriptData.write(to: script)
        try noWork(invoke("all-families", 0, ["--script", script.path, "--output", saved.path]))
        try expect(try Data(contentsOf: script) == scriptData, "command script changed")

        let structureFolder = root.appendingPathComponent("structure files", isDirectory: true)
        try manager.createDirectory(at: structureFolder, withIntermediateDirectories: true)
        let structureFile = structureFolder.appendingPathComponent("house file.nbt")
        let structureWorld = root.appendingPathComponent("structure-export.mcworld")
        try noWork(invoke("structure-file-export", 0, [
            "--command", "structure save cli:file overworld 0 65 0 3 65 0",
            "--command", "structure export nbt cli:file --file \"\(structureFile.path)\"",
            "--output", structureWorld.path]))
        try expect(manager.fileExists(atPath: structureFile.path), "structure export did not create path-with-spaces file")

        let convertHelp = try invokeStandalone("convert-help", 0, ["--help", "convert"])
        try expect(convertHelp.output.contains("little-varint") && convertHelp.output.contains("mcstructure"), "convert help is incomplete")
        let littleFile = structureFolder.appendingPathComponent("house little.nbt")
        let varIntFile = structureFolder.appendingPathComponent("house varint.nbt")
        let jsonFile = structureFolder.appendingPathComponent("house.json")
        let mcstructureFile = structureFolder.appendingPathComponent("house.mcstructure")
        _ = try invokeStandalone("convert-little", 0, ["--convert", structureFile.path, "--to", "little-endian", "--output", littleFile.path])
        try expect(try StandaloneNBTFileCodec.decode(data: Data(contentsOf: littleFile), filename: littleFile.lastPathComponent).originalEncoding == .littleEndian, "little-endian conversion encoding")
        _ = try invokeStandalone("convert-varint", 0, ["--convert", littleFile.path, "--to", "little-varint", "--output", varIntFile.path])
        try expect(try StandaloneNBTFileCodec.decode(data: Data(contentsOf: varIntFile), filename: varIntFile.lastPathComponent).originalEncoding == .littleEndianVarInt, "little-varint conversion encoding")
        _ = try invokeStandalone("convert-json", 0, ["--convert", varIntFile.path, "--to", "json", "--output", jsonFile.path])
        try expect(try StandaloneNBTFileCodec.decode(data: Data(contentsOf: jsonFile), filename: jsonFile.lastPathComponent).originalWasJSON, "JSON conversion format")
        _ = try invokeStandalone("convert-mcstructure", 0, ["--convert", structureFile.path, "--to", "mcstructure", "--output", mcstructureFile.path])
        try expect(try StandaloneNBTFileCodec.decode(data: Data(contentsOf: mcstructureFile), filename: mcstructureFile.lastPathComponent).originalEncoding == .littleEndian, "mcstructure conversion encoding")
        _ = try invokeStandalone("convert-no-overwrite", 3, ["--convert", structureFile.path, "--to", "json", "--output", jsonFile.path])
        _ = try invokeStandalone("convert-overwrite", 0, ["--convert", structureFile.path, "--to", "json", "--output", jsonFile.path, "--overwrite"])
        let rootDocument = try StandaloneNBTFileCodec.decode(data: Data(contentsOf: structureFile), filename: structureFile.lastPathComponent).documents[0]
        let consecutiveFile = structureFolder.appendingPathComponent("two roots.nbt")
        try StandaloneNBTFileCodec.encode([rootDocument, rootDocument], encoding: .littleEndian).write(to: consecutiveFile)
        let consecutiveJson = structureFolder.appendingPathComponent("two roots.json")
        _ = try invokeStandalone("convert-consecutive-json", 0, ["--convert", consecutiveFile.path, "--to", "json", "--output", consecutiveJson.path])
        try expect(try StandaloneNBTFileCodec.decode(data: Data(contentsOf: consecutiveJson), filename: consecutiveJson.lastPathComponent).documents.count == 2, "consecutive NBT conversion lost roots")
        _ = try invokeStandalone("convert-consecutive-mcstructure", 3, ["--convert", consecutiveFile.path, "--to", "mcstructure", "--output", structureFolder.appendingPathComponent("invalid.mcstructure").path])
        let importedWorld = root.appendingPathComponent("structure-import.mcworld")
        try noWork(invoke("structure-file-import", 0, [
            "--command", "structure import cli:imported --file \"\(structureFile.path)\"",
            "--output", importedWorld.path]))
        let importPaths = CliWorldPaths(source: importedWorld, cache: root.appendingPathComponent("VerifyImport"), output: nil, isDirectory: false)
        let importWorkspace = try CliWorldWorkspace.open(importPaths, inPlace: false)
        do {
            defer { importWorkspace.finish(preserve: false, notice: { _ in }) }
            try expect(try StructureNBTStore(session: importWorkspace.session).containsStructure(named: "cli:imported"), "structure import was not persisted")
        }
        let missingName = try invoke("structure-file-missing-name", 2, [
            "--command", "time set 222",
            "--command", "structure import --file \"\(structureFile.path)\"",
            "--output", root.appendingPathComponent("missing-name.mcworld").path])
        try expect(!manager.fileExists(atPath: missingName.cache.path), "missing structure name did not fail during whole-batch preflight")
        let verifyPaths = CliWorldPaths(source: saved, cache: root.appendingPathComponent("Verify"), output: nil, isDirectory: false)
        let verified = try CliWorldWorkspace.open(verifyPaths, inPlace: false)
        do {
            defer { verified.finish(preserve: false, notice: { _ in }) }
            let time = try BedrockTimeStore.read(session: verified.session)
            try expect(time.time == 12345 && !time.automaticProgression, "time/daylock persistence")
            let reader = BedrockBlockReader(database: try verified.session.database())
            try expect(try reader.block(blockX: 2, y: 65, blockZ: 0, dimension: 0).layers[0].name == "minecraft:dirt", "overlapping clone snapshot")
            try expect(try reader.block(blockX: 0, y: 70, blockZ: 0, dimension: 0).name == "minecraft:stone", "structure load persistence")
            try expect(try reader.block(blockX: 35, y: 200, blockZ: 5, dimension: 2).name == "minecraft:diamond_block", "new End high chunk persistence")
            let raw = try verified.session.database().get(BedrockDBKey.subChunk(x: 0, z: 0, dimension: 2, index: 13))!
            let subchunk = try BedrockSubChunk.decode(raw, keyYIndex: 13)
            try expect(subchunk.version == 8 && subchunk.storages.count == 255 && subchunk.storages.allSatisfy { $0.bitsPerBlock >= 1 }, "v8 255-storage compatibility")
            try expect(subchunk.storages[254].blockState(x: 3, y: 12, z: 5)?.name == "minecraft:stone", "storage 254 persistence")
            try expect(try verified.session.database().get(Data("cli_unknown_record".utf8)) == Data([0, 128, 255, 1]), "unknown record persistence")
            let players = PlayerNBTStore(session: verified.session)
            let local = try players.localPlayerPosition()!
            try expect(abs(local.y - 65.62) < 0.001 && (try players.records()).count == 1, "player integer Y offset or kick persistence")
            try expect(!manager.fileExists(atPath: verified.worldRoot.appendingPathComponent(".mcbeeditor").path), "save-as leaked editor metadata")
        }
        let interactiveArchive = root.appendingPathComponent("interactive.mcworld")
        try manager.copyItem(at: saved, to: interactiveArchive)
        var interactiveLines = [
            ":open \"\(interactiveArchive.path)\" --in-place",
            "time set 1111", ":save", "time set 2222", ":save", ":quit"
        ]
        var interactiveIndex = 0
        var interactiveOutput = [String](), interactiveError = [String]()
        let interactiveExit = MCBEEditorCli.run(["--interactive"],
            output: { interactiveOutput.append($0) }, error: { interactiveError.append($0) },
            input: { defer { interactiveIndex += 1 }; return interactiveIndex < interactiveLines.count ? interactiveLines[interactiveIndex] : nil })
        try expect(interactiveExit == 0, "interactive session failed: \(interactiveError.joined(separator: "; "))")
        let interactivePaths = CliWorldPaths(source: interactiveArchive, cache: root.appendingPathComponent("VerifyInteractive"), output: nil, isDirectory: false)
        let interactiveWorkspace = try CliWorldWorkspace.open(interactivePaths, inPlace: false)
        do {
            defer { interactiveWorkspace.finish(preserve: false, notice: { _ in }) }
            try expect(try BedrockTimeStore.read(session: interactiveWorkspace.session).time == 2222, "second interactive in-place save failed or source stamp was not refreshed")
        }

        // Stage04c: callback/redirected sessions must stay plain text while :history/:clear remain usable.
        var plainLines = [":history", ":clear", ":quit"]
        var plainIndex = 0, plainOutput = [String](), plainError = [String]()
        let plainExit = MCBEEditorCli.run(["--interactive"], output: { plainOutput.append($0) }, error: { plainError.append($0) },
            input: { defer { plainIndex += 1 }; return plainIndex < plainLines.count ? plainLines[plainIndex] : nil }, terminalFeatures: false)
        try expect(plainExit == 0 && plainOutput.contains(where: { $0.contains(":history") })
            && !plainOutput.contains(where: { $0.contains("\u{001B}") }), "redirected interactive history/clear emitted ANSI or failed")
        try expect(plainError.isEmpty, "redirected interactive history/clear wrote unexpected stderr")

        // Stage04d: fixed ReadMe is editor-owned; Command.txt is user-owned and must survive preparation byte-for-byte.
        let commandsDirectory = root.appendingPathComponent("Commands", isDirectory: true)
        try manager.createDirectory(at: commandsDirectory, withIntermediateDirectories: true)
        let commandFile = CliSharedCommandStore.commandFile(in: commandsDirectory)
        try Data("time set 3333\nstructure load cli:missing overworld 0 64 0\ntime set 4444\n".utf8).write(to: commandFile)
        let commandBeforePrepare = try Data(contentsOf: commandFile)
        try CliSharedCommandStore.prepare(at: commandsDirectory)
        try expect(try Data(contentsOf: commandFile) == commandBeforePrepare, "preparing Commands changed Command.txt")
        let commandReadMe = try String(contentsOf: CliSharedCommandStore.readMeFile(in: commandsDirectory), encoding: .utf8)
        try expect(commandReadMe.contains("--script") && commandReadMe.contains(":clear")
            && commandReadMe.contains("structure export"), "fixed Commands ReadMe is incomplete")

        // Runtime failures continue later Command.txt lines. A user may save successful edits, but final session status remains failed.
        let commandBatchArchive = root.appendingPathComponent("command-batch.mcworld")
        try manager.copyItem(at: saved, to: commandBatchArchive)
        var batchLines = [":open \"\(commandBatchArchive.path)\" --in-place", "y", ":save", ":quit"]
        var batchIndex = 0, batchOutput = [String](), batchError = [String]()
        let batchExit = MCBEEditorCli.run(["--interactive"], output: { batchOutput.append($0) }, error: { batchError.append($0) },
            input: { defer { batchIndex += 1 }; return batchIndex < batchLines.count ? batchLines[batchIndex] : nil },
            terminalFeatures: false, commandsDirectory: commandsDirectory)
        try expect(batchExit == 1, "Command.txt runtime failure did not propagate final exit status")
        try expect(batchOutput.contains(where: { $0.contains("Command.txt 语法检查通过") })
            && batchOutput.contains(where: { $0.contains("time set 完成") }), "Command.txt runtime batch did not continue successful commands")
        try expect(batchError.contains(where: { $0.contains("第 2 行执行失败") })
            && batchError.contains(where: { $0.contains("其余命令已继续执行") }), "Command.txt runtime failure summary missing")
        let commandBatchPaths = CliWorldPaths(source: commandBatchArchive, cache: root.appendingPathComponent("VerifyCommandBatch"), output: nil, isDirectory: false)
        let commandBatchWorkspace = try CliWorldWorkspace.open(commandBatchPaths, inPlace: false)
        do {
            defer { commandBatchWorkspace.finish(preserve: false, notice: { _ in }) }
            try expect(try BedrockTimeStore.read(session: commandBatchWorkspace.session).time == 4444,
                       "Command.txt runtime failure stopped later command or partial save")
        }

        // Syntax errors reject the entire Command.txt before its first mutation.
        try Data("time set 5555\nweather nope\ntime set 6666\n".utf8).write(to: commandFile)
        let commandPreflightArchive = root.appendingPathComponent("command-preflight.mcworld")
        try manager.copyItem(at: saved, to: commandPreflightArchive)
        var preflightLines = [":open \"\(commandPreflightArchive.path)\" --in-place", "y", ":quit"]
        var preflightIndex = 0, preflightOutput = [String](), preflightError = [String]()
        let preflightExit = MCBEEditorCli.run(["--interactive"], output: { preflightOutput.append($0) }, error: { preflightError.append($0) },
            input: { defer { preflightIndex += 1 }; return preflightIndex < preflightLines.count ? preflightLines[preflightIndex] : nil },
            terminalFeatures: false, commandsDirectory: commandsDirectory)
        try expect(preflightExit == 2, "Command.txt preflight failure did not propagate exit status")
        try expect(preflightError.contains(where: { $0.contains("第 2 行") })
            && preflightError.contains(where: { $0.contains("本次没有执行任何命令") }), "Command.txt whole-batch preflight diagnostics missing")
        let commandPreflightPaths = CliWorldPaths(source: commandPreflightArchive, cache: root.appendingPathComponent("VerifyCommandPreflight"), output: nil, isDirectory: false)
        let commandPreflightWorkspace = try CliWorldWorkspace.open(commandPreflightPaths, inPlace: false)
        do {
            defer { commandPreflightWorkspace.finish(preserve: false, notice: { _ in }) }
            try expect(try BedrockTimeStore.read(session: commandPreflightWorkspace.session).time == 12345,
                       "Command.txt syntax failure executed an earlier command")
        }

        let savedBytes = try Data(contentsOf: saved)
        try noWork(invoke("archive-query", 0, ["--command", "weather query"], input: saved))
        try expect(try Data(contentsOf: saved) == savedBytes, "archive query modified input")

        let inplace = root.appendingPathComponent("原位文件夹", isDirectory: true)
        try CliFileSystem.copyWorld(source, to: inplace)
        try noWork(invoke("in-place-folder", 0, ["--command", "time set 6789", "--command", "setblock the_end 35 200 5 minecraft:diamond_block NULL", "--in-place"], input: inplace))
        let inplaceSession = WorldSession(rootURL: inplace, displayName: "in-place")
        try expect(try BedrockTimeStore.read(session: inplaceSession).time == 6789, "folder in-place time")
        try expect(try BedrockBlockReader(database: inplaceSession.database()).block(blockX: 35, y: 200, blockZ: 5, dimension: 2).name == "minecraft:diamond_block", "folder in-place LevelDB")
        inplaceSession.close()
        try expect(try String(contentsOf: inplace.appendingPathComponent(".mcbeeditor/private.txt"), encoding: .utf8) == "editor-only", "in-place unrelated files")
        let untouched = try CliFileSystem.stamp(inplace)
        let failed = try invoke("in-place-error", 1, ["--command", "time set 777", "--command", "structure load cli:missing overworld 0 64 0", "--in-place"], input: inplace)
        _ = try recovery(failed)
        try expect(try CliFileSystem.stamp(inplace) == untouched, "error batch wrote original folder")
        var changed = false
        let conflict = try invoke("in-place-source-change", 3, ["--command", "time set 888", "--in-place"], input: inplace, onOutput: { line in
            if !changed && line.hasPrefix("time set 完成") {
                try! Data("external".utf8).write(to: inplace.appendingPathComponent("external.txt")); changed = true
            }
        })
        _ = try recovery(conflict)
        try expect(try BedrockTimeStore.read(session: inplaceSession).time == 6789 && manager.fileExists(atPath: inplace.appendingPathComponent("external.txt").path), "external source change overwritten")

        let wrappedRoot = root.appendingPathComponent("Wrapped", isDirectory: true)
        try manager.createDirectory(at: wrappedRoot, withIntermediateDirectories: false)
        try CliFileSystem.copyWorld(source, to: wrappedRoot.appendingPathComponent("World"))
        try Data("outside-world".utf8).write(to: wrappedRoot.appendingPathComponent("outside.txt"))
        let wrapped = root.appendingPathComponent("in-place.mcworld")
        try MiniZipArchive.create(from: wrappedRoot, to: wrapped, preserveAllFiles: true)
        try noWork(invoke("in-place-archive", 0, ["--command", "time set 2468", "--in-place"], input: wrapped))
        let extracted = root.appendingPathComponent("Extracted")
        try MiniZipArchive.extract(archiveURL: wrapped, to: extracted)
        try expect(try String(contentsOf: extracted.appendingPathComponent("outside.txt"), encoding: .utf8) == "outside-world", "in-place archive outer files")
        try expect(manager.fileExists(atPath: extracted.appendingPathComponent("World/.mcbeeditor/private.txt").path), "in-place archive metadata/layout")
        let reopened = WorldSession(rootURL: extracted.appendingPathComponent("World"), displayName: "archive")
        try expect(try BedrockTimeStore.read(session: reopened).time == 2468, "archive in-place time")
        let beforeFailure = try Data(contentsOf: wrapped)
        _ = try invoke("in-place-archive-error", 1, ["--command", "time set 111", "--command", "structure load cli:missing overworld 0 64 0", "--in-place"], input: wrapped)
        try expect(try Data(contentsOf: wrapped) == beforeFailure, "failed batch wrote original archive")
        _ = try invoke("mode-conflict", 2, ["--command", "time set 1", "--in-place", "--output", saved.path])
        _ = try invoke("save-over-input", 2, ["--command", "weather query", "--output", saved.path, "--overwrite"], input: saved)
        _ = try invoke("no-overwrite", 2, ["--command", "weather query", "--output", saved.path])
        _ = try invoke("overwrite", 0, ["--command", "weather query", "--output", saved.path, "--overwrite"])

        let raced = root.appendingPathComponent("raced.mcworld")
        let race = try invoke("output-race", 3, ["--command", "time set 999", "--output", raced.path], onOutput: { line in
            if line.hasPrefix("time set 完成") { try! Data("external-content".utf8).write(to: raced) }
        })
        try expect(try String(contentsOf: raced, encoding: .utf8) == "external-content", "output race clobbered file")
        let restored = try recovery(race)
        _ = try invoke("recovery-export", 0, ["--command", "time query gametime", "--output", root.appendingPathComponent("recovered.mcworld").path], input: restored)
        let partial = try invoke("runtime-continue", 1, ["--command", "structure load cli:missing overworld 0 64 0", "--command", "time set 456", "--output", root.appendingPathComponent("partial.mcworld").path])
        try expect(partial.error.contains("第 1 行执行失败") && partial.output.contains("time set 完成"), "runtime error did not continue")
        _ = try recovery(partial)
        var cancelled = false
        let cancelledResult = try invoke("cancel", 130, ["--command", "time set 333", "--command", "time set 444", "--in-place"], input: inplace,
            onOutput: { if $0 == "> time set 333" { cancelled = true } }, cancelled: { cancelled })
        let cancelledCopy = WorldSession(rootURL: try recovery(cancelledResult), displayName: "cancelled")
        try expect(try BedrockTimeStore.read(session: cancelledCopy).time == 333 && BedrockTimeStore.read(session: inplaceSession).time == 6789, "cancellation command boundary or source commit")
        _ = try recovery(invoke("keep-work", 0, ["--command", "weather query", "--keep-work"]))

        // Native persistence for each original End terrain profile, beyond the memory regression.
        for coordinates in [fixture.v8Chunk, fixture.v1Chunk, fixture.emptyChunk] {
            let target = root.appendingPathComponent("End-\(coordinates[0])-\(coordinates[1])")
            try CliFileSystem.copyWorld(source, to: target)
            let x = Int64(coordinates[0]) * 16, z = Int64(coordinates[1]) * 16
            var arguments = ["--in-place"]
            for y in [160, 200, 255] { arguments += ["--command", "setblock the_end \(x) \(y) \(z) minecraft:diamond_block NULL"] }
            _ = try invoke("end-\(coordinates[0])-\(coordinates[1])", 0, arguments, input: target)
            let session = WorldSession(rootURL: target, displayName: "end")
            defer { session.close() }
            for y in [Int32(160), 200, 255] {
                let raw = try session.database().get(BedrockDBKey.subChunk(x: coordinates[0], z: coordinates[1], dimension: 2, index: Int8(y / 16)))!
                let written = try BedrockSubChunk.decode(raw, keyYIndex: Int8(y / 16))
                let expected: UInt8 = coordinates == fixture.v1Chunk ? 1 : 8
                try expect(written.version == expected && written.storages[0].blockState(x: 0, y: Int(y % 16), z: 0)?.name == "minecraft:diamond_block", "native End fixture high slice")
            }
        }
    }
}
