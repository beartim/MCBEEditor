import Foundation

struct MCBEEditorCli {
    static let version = "MCBEEditor CLI 1.0.0"
    private static let usage = """
MCBEEditor CLI 1.0.0
命令执行、原位更新、另存为与 NBT/mcstructure 格式转换。

mcbe-cli --help [命令]
mcbe-cli --list-commands
mcbe-cli --version
mcbe-cli --interactive
mcbe-cli --convert 输入 --to 格式 --output 输出 [--overwrite]
mcbe-cli --check "完整命令"
mcbe-cli --check-file 路径
mcbe-cli --check-file -
mcbe-cli --world 路径 --command "完整命令" [--command "下一条命令"]
mcbe-cli --world 路径 --script 命令文件

--in-place             全部成功后原位更新输入文件夹或 mcworld。
--output 路径.mcworld  另存为；与 --in-place 互斥。修改必须选择其一。
--overwrite            允许替换已存在的另存为输出文件。
--cache-dir 路径       默认 ~/Library/Caches/MCBEEditorCLI/Worlds。
--keep-work            执行成功后也保留工作副本。

--check-file/--script 接受 UTF-8（可带 BOM），忽略空行并报告原始行号。
使用 - 从标准输入读取；--check-file 会检查全部非空行，不执行命令。
预检只检查语法，不检查存档中的目标是否存在或能否执行。
执行前整批预检，运行时出错后继续后续命令。
先在工作副本执行；原位模式仅全部成功后提交，失败保留副本。
structure import/export 使用 --file 路径；持续会话使用 --interactive。
独立 NBT/mcstructure 格式转换不需要 --world，也不会编辑 NBT 内容。
退出码：0 成功；1 执行失败；2 参数或预检错误；3 文件或编码错误；130 取消。
"""

    static func writeOutput(_ message: String) { FileHandle.standardOutput.write(Data((message + "\n").utf8)) }
    static func writeError(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }

    static func run(_ arguments: [String], output: @escaping (String) -> Void = writeOutput,
                    error: @escaping (String) -> Void = writeError, cancelled: () -> Bool = { false },
                    input: @escaping () -> String? = { readLine() }, terminalFeatures: Bool = false, commandsDirectory: URL? = nil) -> Int32 {
        do {
            guard let option = arguments.first else { output(usage); return 0 }
            switch (option, arguments.count) {
            case ("--help", 1):
                output(usage); output(""); output(WorldCommandParser.helpText()); return 0
            case ("--help", 2):
                if arguments[1].lowercased() == "convert" { output(CliFormatConverter.usage); return 0 }
                guard WorldCommandParser.commandNames.contains(arguments[1]) else {
                    error("不存在的命令：\(arguments[1])"); return 2
                }
                output(WorldCommandParser.helpText(for: arguments[1]))
                if arguments[1] == "structure" { output("\nCLI 文件接口：\n" + CliStructureFileCommand.usage) }
                return 0
            case ("--list-commands", 1):
                output(WorldCommandParser.commandNames.joined(separator: "\n")); return 0
            case ("--version", 1): output(version); return 0
            case ("--interactive", 1):
                return CliInteractiveShell.run(input: input, output: output, error: error, cancelled: cancelled, terminalFeatures: terminalFeatures, commandsDirectory: commandsDirectory)
            case ("--check", 2):
                return check([CliCommandLine(lineNumber: 1, text: arguments[1])], output: output, error: error)
            case ("--check-file", 2):
                return check(try CliCommandFile.read(arguments[1]), output: output, error: error)
            case ("--convert", _):
                return try CliFormatConverter.run(arguments, output: output)
            case ("--world", _), ("--command", _), ("--script", _), ("--output", _),
                 ("--cache-dir", _), ("--overwrite", _), ("--keep-work", _), ("--in-place", _):
                return try CliWorldRunner.run(CliRunOptions.parse(arguments), output: output, error: error, cancelled: cancelled)
            default:
                error("CLI 参数格式错误。\n" + usage); return 2
            }
        } catch CliError.input(let message) {
            error(message); return 2
        } catch let failure {
            error(failure.localizedDescription); return 3
        }
    }

    private static func check(_ lines: [CliCommandLine], output: (String) -> Void, error: (String) -> Void) -> Int32 {
        guard CliCommandPlan.parse(lines, forExecution: false, error: error) != nil else { return 2 }
        output("语法预检通过：\(lines.count) 条命令，未执行任何命令。"); return 0
    }
}
