import Foundation

struct CliStructureFileRequest {
    let operation: CommandStructureOperation
    let file: URL
    let overwrite: Bool
}

enum CliStructureFileCommand {
    static let usage = """
structure import 名称 --file "路径.mcstructure|nbt|json" [--overwrite]
structure export mcstructure|nbt|json 名称 --file "输出路径" [--overwrite]
非交互模式名称和 --file 均必填；交互模式可省略名称后按提示输入。
"""
    static func parse(_ text: String) throws -> (ParsedWorldCommand, CliStructureFileRequest?) {
        let tokens = try tokenize(text)
        guard tokens.count >= 2, tokens[0].lowercased() == "structure",
              ["import", "export"].contains(tokens[1].lowercased()) else {
            return (try WorldCommandParser.parse(text), nil)
        }
        guard let fileIndex = tokens.firstIndex(where: { $0.lowercased() == "--file" }) else {
            return (try WorldCommandParser.parse(text), nil)
        }
        guard fileIndex + 1 < tokens.count else { throw CliError.input("structure import/export 的 --file 缺少路径。") }
        let fileFlags = tokens.filter { $0.lowercased() == "--file" }.count
        let overwriteFlags = tokens.filter { $0.lowercased() == "--overwrite" }.count
        guard fileFlags == 1, overwriteFlags <= 1 else { throw CliError.input("structure 文件参数不能重复。") }
        for token in tokens.dropFirst(2) where token.hasPrefix("--") && !["--file", "--overwrite"].contains(token.lowercased()) {
            throw CliError.input("未知 structure 文件参数：\(token)")
        }
        var coreTokens = [String]()
        var index = 0
        while index < tokens.count {
            if tokens[index].lowercased() == "--file" { index += 2; continue }
            if tokens[index].lowercased() == "--overwrite" { index += 1; continue }
            coreTokens.append(tokens[index]); index += 1
        }
        let command = try WorldCommandParser.parse(coreTokens.joined(separator: " "))
        guard case .structure(let operation) = command else { throw CliError.input("structure 文件操作解析失败。") }
        return (command, CliStructureFileRequest(operation: operation,
            file: CliWorldPaths.canonical(tokens[fileIndex + 1]), overwrite: overwriteFlags == 1))
    }

    static func execute(_ request: CliStructureFileRequest, session: WorldSession) throws -> WorldCommandExecutionResult {
        let manager = FileManager.default
        let store = StructureNBTStore(session: session)
        switch request.operation {
        case .importFile(let optionalName):
            guard let name = optionalName else { throw CliError.input("非交互 structure import 必须指定结构名称；交互会话可省略后按提示输入。") }
            guard manager.fileExists(atPath: request.file.path) else { throw CliError.file("找不到结构文件：\(request.file.path)") }
            guard ["mcstructure", "nbt", "json"].contains(request.file.pathExtension.lowercased()) else {
                throw CliError.file("structure import 仅支持 .mcstructure、.nbt 或 .json 文件。")
            }
            let file = try StandaloneNBTFileCodec.decode(data: Data(contentsOf: request.file), filename: request.file.lastPathComponent)
            guard file.documents.count == 1, let document = file.documents.first else {
                throw CliError.file("结构文件必须只包含一个 NBT 根标签。")
            }
            let normalized = store.normalizedStructureName(name)
            let exists = try store.containsStructure(named: normalized)
            if exists && !request.overwrite { throw CliError.file("已存在同名结构：\(normalized)；显式使用 --overwrite 才会覆盖。") }
            let result = try store.save(document: document, named: normalized, overwrite: request.overwrite)
            var message = "structure import 完成：\(normalized)"
            if result.convertedFromJava {
                message += "；Java → Bedrock，\(result.placedBlockCount) 个方块，\(result.lossyPaletteEntryCount) 个调色板条目发生兼容降级；不带入实体、水层及高级方块实体数据。"
            }
            return WorldCommandExecutionResult(message: message, changedWorld: true)
        case .exportFile(let format, let optionalName):
            guard let name = optionalName else { throw CliError.input("非交互 structure export 必须指定结构名称；交互会话可省略后按提示选择。") }
            guard request.file.pathExtension.lowercased() == format.rawValue else {
                throw CliError.file("导出文件扩展名必须与格式一致：.\(format.rawValue)")
            }
            if CliFileSystem.isDirectory(request.file) { throw CliError.file("structure export 的 --file 必须指向文件。") }
            if manager.fileExists(atPath: request.file.path) && !request.overwrite {
                throw CliError.file("导出文件已存在；显式使用 --overwrite 才会覆盖。")
            }
            guard let record = try store.record(named: name) else { throw CliError.file("不存在结构：\(name)") }
            guard let document = record.document else { throw CliError.file("结构 NBT 无法解析：\(record.displayName)") }
            let data = try StandaloneNBTFileCodec.encodeStructure(document, format: format)
            let parent = request.file.deletingLastPathComponent()
            try manager.createDirectory(at: parent, withIntermediateDirectories: true)
            let temporary = parent.appendingPathComponent(".mcbe-structure-\(UUID().uuidString).tmp")
            defer { try? manager.removeItem(at: temporary) }
            try data.write(to: temporary, options: .atomic)
            try CliFileSystem.publishFile(temporary, to: request.file, overwrite: request.overwrite)
            return WorldCommandExecutionResult(message: "structure export 完成：\(request.file.path)", changedWorld: false)
        default:
            throw CliError.input("--file 仅用于 structure import/export。")
        }
    }

    private static func tokenize(_ text: String) throws -> [String] {
        var result = [String](), current = "", quote: Character?
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            if let active = quote {
                if c == active { quote = nil }
                else if c == "\\" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == active { current.append(text[next]); index = next }
                    else { current.append(c) }
                } else { current.append(c) }
            } else if c == "\"" || c == "'" { quote = c }
            else if c.isWhitespace {
                if !current.isEmpty { result.append(current); current = "" }
            } else { current.append(c) }
            index = text.index(after: index)
        }
        guard quote == nil else { throw CliError.input("structure 文件路径引号未闭合。") }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
