import Foundation

enum CliSharedCommandStore {
    static var defaultDirectory: URL {
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documents.appendingPathComponent("Commands", isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Documents/Commands", isDirectory: true)
    }

    static func commandFile(in directory: URL) -> URL {
        directory.appendingPathComponent("Command.txt", isDirectory: false)
    }

    static func readMeFile(in directory: URL) -> URL {
        directory.appendingPathComponent("ReadMe.txt", isDirectory: false)
    }

    static func prepareDefault(error: (String) -> Void) {
        do { try prepare(at: defaultDirectory) }
        catch { error("警告：无法准备 Commands 目录：\(error.localizedDescription)") }
    }

    static func prepare(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Command.txt remains user-owned. Only the fixed ReadMe is rewritten.
        try Data(readMeText.utf8).write(to: readMeFile(in: directory), options: .atomic)
    }

    static func commandFileExists(in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: commandFile(in: directory).path)
    }

    static func readCommandLines(in directory: URL) throws -> [CliCommandLine] {
        guard commandFileExists(in: directory) else { return [] }
        return try CliCommandFile.read(commandFile(in: directory).path)
    }

    private static let readMeText = """
MCBEEditor CLI Commands 文件夹说明

此目录用于保存可选的 Command.txt 批处理命令。

使用方法：
1. Command.txt 由用户自行创建，必须是 UTF-8 文本；MCBEEditor 不会自动创建、修改或删除它。
2. 每行一条命令；空行忽略，错误信息保留原始物理行号。
3. 交互会话 :open 世界后若检测到非空 Command.txt，会询问是否执行；拒绝不会修改世界。
4. 确认后先预检全部非空行；任一语法错误会拒绝整个批次，一条也不执行。
5. 预检全部通过后按文件顺序逐条执行并输出；某条发生运行时错误后仍继续后续命令，最终退出状态记录失败。
6. 无人值守/非交互执行不会弹出确认；请显式使用 --script "Commands/Command.txt"。
7. ReadMe.txt 是当前 CLI 的固定说明，每次程序启动都会重写本文件。
8. 游戏命令 clear 仍表示清除物品；终端清屏使用交互会话命令 :clear。

当前支持的全部游戏命令（与本版本 help 输出一致）：

\(WorldCommandParser.helpText())

CLI structure 文件接口：
\(CliStructureFileCommand.usage)
"""
}
