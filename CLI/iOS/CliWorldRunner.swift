import Foundation

enum CliWorldRunner {
    static func run(_ options: CliRunOptions, output: (String) -> Void, error: (String) -> Void,
                    cancelled: () -> Bool) throws -> Int32 {
        let lines = try options.script.map(CliCommandFile.read)
            ?? options.commands.enumerated().map { CliCommandLine(lineNumber: $0.offset + 1, text: $0.element) }
        guard let plan = CliCommandPlan.parse(lines, forExecution: true, error: error) else { return 2 }
        if plan.mayMutate && options.output == nil && !options.inPlace {
            throw CliError.input("本次命令包含存档修改，必须指定 --in-place 原位更新或 --output 新文件.mcworld 另存为。")
        }
        let paths = try CliWorldPaths.validate(options)
        if cancelled() { error("已取消。"); return 130 }
        let workspace = try CliWorldWorkspace.open(paths, inPlace: options.inPlace)
        var preserve = true
        defer { workspace.finish(preserve: preserve, notice: error) }
        error("工作副本：\(workspace.worldRoot.path)")
        let executor = WorldCommandExecutor(session: workspace.session)
        var failures = 0
        for command in plan.commands {
            if cancelled() { break }
            output("> " + command.line.text)
            do {
                let result: WorldCommandExecutionResult
                do {
                    defer { workspace.session.close() }
                    if let structureFile = command.structureFile {
                        result = try CliStructureFileCommand.execute(structureFile, session: workspace.session)
                    } else {
                        result = try executor.execute(command.command)
                    }
                }
                let rows = result.outputLines.isEmpty ? result.message.components(separatedBy: "\n") : result.outputLines.map(\.text)
                for row in rows { output(row) }
            } catch let failure {
                failures += 1
                error("第 \(command.line.lineNumber) 行执行失败：\(failure.localizedDescription)")
            }
        }
        if cancelled() {
            error("已在当前命令结束后取消；未导出或提交，工作副本保留。")
            return 130
        }
        if let destination = paths.output {
            try workspace.export(to: destination, overwrite: options.overwrite)
            output("导出完成：\(destination.path)")
            if failures > 0 { error("已导出发生错误后的当前工作副本；其中可能包含出错命令在报错前写入的数据。") }
        } else if options.inPlace && failures == 0 && plan.mayMutate {
            try workspace.commitInPlace(notice: error)
            output("原位更新完成：\(paths.source.path)")
        } else if options.inPlace && failures > 0 {
            error("存在执行错误，未提交原位更新；原存档未写回本次命令结果。")
        }
        output("执行完成：\(plan.commands.count) 条命令，失败 \(failures) 条。")
        preserve = options.keepWork || failures > 0
        return failures == 0 ? 0 : 1
    }
}
