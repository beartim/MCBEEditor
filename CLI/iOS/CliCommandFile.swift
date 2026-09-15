import Foundation

struct CliCommandLine {
    let lineNumber: Int
    let text: String
}

enum CliCommandFileError: LocalizedError {
    case invalidUTF8

    var errorDescription: String? { "命令文件必须使用 UTF-8 文本格式。" }
}

enum CliCommandFile {
    static func read(_ path: String) throws -> [CliCommandLine] {
        let bytes: Data
        if path == "-" {
            bytes = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        }
        guard var text = String(data: bytes, encoding: .utf8) else {
            throw CliCommandFileError.invalidUTF8
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let rows = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        return rows.enumerated().compactMap { index, row in
            let trimmed = row.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : CliCommandLine(lineNumber: index + 1, text: trimmed)
        }
    }
}
