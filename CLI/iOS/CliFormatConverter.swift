import Foundation

enum CliConversionFormat: String {
    case bigEndian = "big-endian"
    case littleEndian = "little-endian"
    case littleVarInt = "little-varint"
    case json
    case mcstructure

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .mcstructure: return "mcstructure"
        default: return "nbt"
        }
    }

    var description: String {
        switch self {
        case .bigEndian: return "Big Endian NBT"
        case .littleEndian: return "Little Endian NBT"
        case .littleVarInt: return "Little Endian VarInt NBT"
        case .json: return "JSON NBT"
        case .mcstructure: return "Bedrock mcstructure"
        }
    }
}

struct CliConversionRequest {
    let input: URL
    let output: URL
    let format: CliConversionFormat
    let overwrite: Bool
}

enum CliFormatConverter {
    static let usage = """
mcbe-cli --convert "输入.nbt|mcstructure|json" --to big-endian|little-endian|little-varint|json|mcstructure --output "输出文件" [--overwrite]

输入自动识别 JSON NBT、Big Endian、Little Endian、Little Endian VarInt、连续多根 NBT 与 GZip/Zlib 包装。
输出 binary NBT 均为未压缩；JSON 保留 NBT 类型；mcstructure 仅支持单根结构 NBT，并可自动将 Java structure NBT 转为 Bedrock mcstructure。
"""

    static func run(_ arguments: [String], output write: (String) -> Void) throws -> Int32 {
        let request = try parse(arguments)
        try execute(request, output: write)
        return 0
    }

    static func parse(_ arguments: [String]) throws -> CliConversionRequest {
        guard arguments.count >= 6, arguments[0].lowercased() == "--convert" else {
            throw CliError.input("格式转换参数不完整。\n" + usage)
        }
        guard !arguments[1].hasPrefix("--") else {
            throw CliError.input("--convert 后必须直接提供输入文件路径。")
        }
        var formatText: String?
        var outputPath: String?
        var overwrite = false
        var seen = Set<String>()
        var index = 2
        while index < arguments.count {
            let token = arguments[index].lowercased()
            switch token {
            case "--overwrite":
                guard seen.insert(token).inserted else { throw CliError.input("--overwrite 不能重复。") }
                overwrite = true
                index += 1
            case "--to", "--output":
                guard seen.insert(token).inserted else { throw CliError.input("\(token) 不能重复。") }
                index += 1
                guard index < arguments.count else { throw CliError.input("\(token) 缺少参数。") }
                if token == "--to" { formatText = arguments[index] }
                else { outputPath = arguments[index] }
                index += 1
            default:
                throw CliError.input("未知格式转换参数：\(arguments[index])\n" + usage)
            }
        }
        guard let formatText, let outputPath else {
            throw CliError.input("格式转换必须同时指定 --to 和 --output。\n" + usage)
        }
        guard let format = CliConversionFormat(rawValue: formatText.lowercased()) else {
            throw CliError.input("未知输出格式：\(formatText)。支持 big-endian、little-endian、little-varint、json、mcstructure。")
        }
        return CliConversionRequest(
            input: CliWorldPaths.canonical(arguments[1]),
            output: CliWorldPaths.canonical(outputPath),
            format: format,
            overwrite: overwrite
        )
    }

    static func execute(_ request: CliConversionRequest, output write: (String) -> Void) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: request.input.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw CliError.file("找不到转换输入文件：\(request.input.path)")
        }
        if CliFileSystem.isDirectory(request.output) { throw CliError.file("转换输出路径必须指向文件。") }
        guard request.output.pathExtension.lowercased() == request.format.fileExtension else {
            throw CliError.file("输出扩展名必须与格式一致：.\(request.format.fileExtension)")
        }
        if manager.fileExists(atPath: request.output.path) && !request.overwrite {
            throw CliError.file("转换输出文件已存在；显式使用 --overwrite 才会覆盖。")
        }

        let decoded = try StandaloneNBTFileCodec.decode(data: Data(contentsOf: request.input), filename: request.input.lastPathComponent)
        let data: Data
        var structureResult: StructureImportResult?
        switch request.format {
        case .bigEndian:
            data = try StandaloneNBTFileCodec.encode(decoded.documents, encoding: .bigEndian)
        case .littleEndian:
            data = try StandaloneNBTFileCodec.encode(decoded.documents, encoding: .littleEndian)
        case .littleVarInt:
            data = try StandaloneNBTFileCodec.encode(decoded.documents, encoding: .littleEndianVarInt)
        case .json:
            data = try StandaloneNBTFileCodec.encodeJSON(decoded.documents)
        case .mcstructure:
            let converted = try StandaloneNBTFileCodec.encodeAsMCStructure(decoded.documents)
            data = converted.data
            structureResult = converted.result
        }

        let parent = request.output.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".mcbe-convert-\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        try CliFileSystem.publishFile(temporary, to: request.output, overwrite: request.overwrite)

        var message = "格式转换完成：\(request.output.path)\n输入：\(decoded.formatDescription)\n输出：\(request.format.description)；根标签=\(decoded.documents.count)"
        if let result = structureResult, result.convertedFromJava {
            message += "\nJava → Bedrock：方块=\(result.placedBlockCount)，调色板=\(result.paletteEntryCount)，兼容降级=\(result.lossyPaletteEntryCount)。"
        }
        write(message)
    }
}
