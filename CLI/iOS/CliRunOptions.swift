import Foundation

enum CliError: LocalizedError {
    case input(String)
    case file(String)
    var errorDescription: String? {
        switch self { case .input(let text), .file(let text): return text }
    }
}

struct CliRunOptions {
    let world: String
    let commands: [String]
    let script: String?
    let output: String?
    let cache: String
    let overwrite: Bool
    let keepWork: Bool
    let inPlace: Bool

    static func parse(_ arguments: [String]) throws -> CliRunOptions {
        var world: String?, script: String?, output: String?, cache: String?
        var commands = [String](), seen = Set<String>()
        var overwrite = false, keepWork = false, inPlace = false, index = 0
        while index < arguments.count {
            let option = arguments[index]
            if option != "--command" && !seen.insert(option).inserted {
                throw CliError.input("CLI 参数不能重复：\(option)")
            }
            func value() throws -> String {
                guard index + 1 < arguments.count,
                      !arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !arguments[index + 1].hasPrefix("--") else {
                    throw CliError.input("CLI 参数缺少值：\(option)")
                }
                index += 1
                return arguments[index]
            }
            switch option {
            case "--world": world = try value()
            case "--command": commands.append(try value())
            case "--script": script = try value()
            case "--output": output = try value()
            case "--cache-dir": cache = try value()
            case "--overwrite": overwrite = true
            case "--keep-work": keepWork = true
            case "--in-place": inPlace = true
            default: throw CliError.input("未知 CLI 参数：\(option)")
            }
            index += 1
        }
        guard let source = world else { throw CliError.input("执行命令需要 --world 存档路径。") }
        guard !commands.isEmpty || script != nil else {
            throw CliError.input("需要 --command 或 --script；持续会话请使用 --interactive。")
        }
        if !commands.isEmpty && script != nil { throw CliError.input("--command 与 --script 不能同时使用。") }
        if overwrite && output == nil { throw CliError.input("--overwrite 需要同时指定 --output。") }
        if inPlace && output != nil { throw CliError.input("--in-place 与 --output 不能同时使用。") }
        // A writable user cache works with both a terminal-installed deb and a host executable.
        let defaultCache = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Caches/MCBEEditorCLI/Worlds").path
        return CliRunOptions(world: source, commands: commands, script: script, output: output,
                             cache: cache ?? defaultCache, overwrite: overwrite, keepWork: keepWork, inPlace: inPlace)
    }
}
