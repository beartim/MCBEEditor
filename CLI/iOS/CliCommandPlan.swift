import Foundation

struct CliPlannedCommand {
    let line: CliCommandLine
    let command: ParsedWorldCommand
    let structureFile: CliStructureFileRequest?
}

struct CliCommandPlan {
    let commands: [CliPlannedCommand]
    var mayMutate: Bool { commands.contains { Self.mayMutate($0.command) } }

    static func parse(_ lines: [CliCommandLine], forExecution: Bool,
                      allowInteractiveStructureName: Bool = false,
                      dimensionContext: DimensionCommandContext? = nil,
                      error: (String) -> Void) -> CliCommandPlan? {
        var parsed = [CliPlannedCommand](), failures = 0
        let dimensions = dimensionContext ?? DimensionCommandContext()
        for line in lines {
            do {
                let parsedFile = try CliStructureFileCommand.parse(line.text, dimensionResolver: dimensions.resolve)
                let command = parsedFile.0
                if forExecution, let file = parsedFile.1, !allowInteractiveStructureName {
                    switch file.operation {
                    case .importFile(name: nil), .exportFile(_, name: nil):
                        throw CliError.input("非交互 structure import/export 必须指定结构名称；交互会话可省略后按提示输入。")
                    default: break
                    }
                }
                if forExecution, parsedFile.1 == nil, case .structure(let operation) = command {
                    switch operation {
                    case .importFile, .exportFile:
                        throw CliError.input("非交互 structure import/export 必须使用 --file 路径；例如 structure export nbt my:name --file \"/tmp/my file.nbt\"。")
                    default: break
                    }
                }
                try dimensions.apply(command)
                parsed.append(CliPlannedCommand(line: line, command: command, structureFile: parsedFile.1))
            } catch let failure {
                error("第 \(line.lineNumber) 行：\(failure.localizedDescription)")
                failures += 1
            }
        }
        guard failures == 0 else {
            error("预检失败：\(failures) 行有语法错误或当前不可执行，未执行任何命令。")
            return nil
        }
        return CliCommandPlan(commands: parsed)
    }

    private static func mayMutate(_ command: ParsedWorldCommand) -> Bool {
        switch command {
        case .help, .info, .dimensionQuery, .entity, .getBlock, .weatherQuery: return false
        case .chunk(.query), .storage(.query), .time(.query), .experience(.query),
             .structure(.query), .structure(.exportFile), .tickingArea(.list): return false
        case .dimensionPurge, .dimensionEmpty, .dimensionAdd, .clear, .clearSpawnPoint, .give, .kill, .kick, .summon, .summonNBT, .effect, .clone,
             .fill, .fillBiome, .setBlock, .chunk, .storage, .setWorldSpawn, .spawnPoint,
             .teleport, .spread, .dayLock, .weather, .time, .experience, .structure, .tickingArea:
            return true
        }
    }
}
