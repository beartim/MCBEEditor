import Foundation

enum CliInteractiveShell {
    static func run(input: @escaping () -> String?, output: @escaping (String) -> Void, error: @escaping (String) -> Void,
                    cancelled: () -> Bool, terminalFeatures: Bool = false, commandsDirectory: URL? = nil) -> Int32 {
        let terminal = CliTerminal(input: input, output: output, error: error, terminalFeatures: terminalFeatures)
        var history = [String]()
        var workspace: CliWorldWorkspace?
        var paths: CliWorldPaths?
        var inPlace = false
        var dirty = false
        var batchExitStatus: Int32 = 0
        terminal.writeLine("MCBEEditor CLI 交互会话。输入 :help 查看会话命令。")
        defer {
            if let workspace = workspace {
                workspace.finish(preserve: dirty, notice: terminal.writeError)
            }
        }
        while !cancelled() {
            guard var line = terminal.readLine(prompt: workspace == nil ? "mcbe> " : "mcbe(world)> ", history: history) else {
                return dirty ? 1 : batchExitStatus
            }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            history.append(line)
            if line.hasPrefix(":") {
                do {
                    let meta = try tokenize(line)
                    guard let name = meta.first?.lowercased() else { continue }
                    switch name {
                    case ":help":
                        terminal.writeLine(":open \"世界路径\" [--in-place]\n:save [\"输出.mcworld\"] [--overwrite]\n:history\n:clear\n:quit [--discard]\n普通游戏命令直接输入；structure import/export 使用 --file 路径。")
                    case ":history":
                        guard meta.count == 1 else { terminal.writeError("用法：:history"); continue }
                        for (index, value) in history.enumerated() { terminal.writeLine(String(format: "%4d  %@", index + 1, value)) }
                    case ":clear":
                        guard meta.count == 1 else { terminal.writeError("用法：:clear"); continue }
                        terminal.clear()
                    case ":open":
                        if dirty { terminal.writeError("当前世界有未保存修改；请先 :save 或 :quit --discard 后重新进入会话。"); continue }
                        guard (2...3).contains(meta.count), meta.dropFirst(2).allSatisfy({ $0.lowercased() == "--in-place" }) else {
                            terminal.writeError("用法：:open \"世界路径\" [--in-place]"); continue
                        }
                        if let old = workspace { old.finish(preserve: false, notice: terminal.writeError) }
                        workspace = nil; paths = nil
                        inPlace = meta.dropFirst(2).contains { $0.lowercased() == "--in-place" }
                        let cache = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                            .appendingPathComponent("Library/Caches/MCBEEditorCLI/Worlds").path
                        let options = CliRunOptions(world: meta[1], commands: [], script: nil, output: nil,
                                                    cache: cache, overwrite: false, keepWork: false, inPlace: inPlace)
                        let newPaths = try CliWorldPaths.validate(options)
                        let newWorkspace = try CliWorldWorkspace.open(newPaths, inPlace: inPlace)
                        paths = newPaths; workspace = newWorkspace; dirty = false
                        terminal.writeLine("已打开工作副本：\(newWorkspace.worldRoot.path)")
                        runSharedCommandFileIfPresent(workspace: newWorkspace, terminal: terminal, history: history,
                            directory: commandsDirectory ?? CliSharedCommandStore.defaultDirectory,
                            dirty: &dirty, batchExitStatus: &batchExitStatus, cancelled: cancelled)
                    case ":save":
                        guard let workspace = workspace, let paths = paths else { terminal.writeError("尚未打开世界。先使用 :open。"); continue }
                        let overwrite = meta.dropFirst().contains { $0.lowercased() == "--overwrite" }
                        let values = meta.dropFirst().filter { $0.lowercased() != "--overwrite" }
                        if values.isEmpty {
                            guard inPlace else { terminal.writeError("当前不是原位会话；请使用 :save \"输出.mcworld\" [--overwrite]。"); continue }
                            if !dirty { terminal.writeLine("没有未保存修改。"); continue }
                            do {
                                try workspace.commitInPlace(notice: terminal.writeError)
                                dirty = false
                                terminal.writeLine("原位更新完成：\(paths.source.path)")
                            } catch { terminal.writeError("保存失败：\(error.localizedDescription)") }
                        } else if values.count == 1 {
                            do {
                                let destination = CliWorldPaths.canonical(values[0])
                                try validateSaveAs(destination, paths: paths, overwrite: overwrite)
                                try workspace.export(to: destination, overwrite: overwrite)
                                dirty = false
                                terminal.writeLine("导出完成：\(destination.path)")
                            } catch { terminal.writeError("保存失败：\(error.localizedDescription)") }
                        } else { terminal.writeError("用法：:save [\"输出.mcworld\"] [--overwrite]") }
                    case ":quit":
                        let discard = meta.dropFirst().contains { $0.lowercased() == "--discard" }
                        guard meta.count <= 2, meta.count == 1 || discard else { terminal.writeError("用法：:quit [--discard]"); continue }
                        if dirty && !discard { terminal.writeError("当前世界有未保存修改；先 :save，或使用 :quit --discard 放弃本会话修改。"); continue }
                        if discard { dirty = false }
                        return batchExitStatus
                    default:
                        terminal.writeError("未知会话命令。输入 :help 查看可用命令。")
                    }
                } catch { terminal.writeError(error.localizedDescription) }
                continue
            }

            guard let workspace = workspace else { terminal.writeError("尚未打开世界。先使用 :open \"世界路径\"。"); continue }
            guard let plan = CliCommandPlan.parse([CliCommandLine(lineNumber: 1, text: line)], forExecution: true, allowInteractiveStructureName: true, error: terminal.writeError),
                  let command = plan.commands.first else { continue }
            var structureFile = command.structureFile
            if let request = structureFile {
                switch request.operation {
                case .importFile(name: nil):
                    guard let name = promptStructureName(store: StructureNBTStore(session: workspace.session), listExisting: false,
                                                         terminal: terminal, history: history) else { continue }
                    structureFile = CliStructureFileRequest(operation: .importFile(name: name), file: request.file, overwrite: request.overwrite)
                case .exportFile(let format, name: nil):
                    guard let name = promptStructureName(store: StructureNBTStore(session: workspace.session), listExisting: true,
                                                         terminal: terminal, history: history) else { continue }
                    structureFile = CliStructureFileRequest(operation: .exportFile(format: format, name: name), file: request.file, overwrite: request.overwrite)
                default: break
                }
            }
            do {
                let result: WorldCommandExecutionResult
                defer { workspace.session.close() }
                if let request = structureFile { result = try CliStructureFileCommand.execute(request, session: workspace.session) }
                else { result = try WorldCommandExecutor(session: workspace.session).execute(command.command) }
                if result.outputLines.isEmpty {
                    result.message.components(separatedBy: "\n").forEach { terminal.writeLine(WorldCommandOutputLine(text: $0, style: .success)) }
                } else {
                    result.outputLines.forEach(terminal.writeLine)
                }
                if result.changedWorld { dirty = true }
            } catch {
                if plan.mayMutate { dirty = true }
                terminal.writeError("执行失败：\(error.localizedDescription)")
            }
        }
        return 130
    }

    private static func runSharedCommandFileIfPresent(workspace: CliWorldWorkspace, terminal: CliTerminal,
                                                      history: [String], directory: URL, dirty: inout Bool,
                                                      batchExitStatus: inout Int32, cancelled: () -> Bool) {
        guard CliSharedCommandStore.commandFileExists(in: directory) else { return }
        let lines: [CliCommandLine]
        do { lines = try CliSharedCommandStore.readCommandLines(in: directory) }
        catch {
            terminal.writeError("Command.txt 读取失败：\(error.localizedDescription)")
            batchExitStatus = max(batchExitStatus, 3)
            return
        }
        if lines.isEmpty {
            terminal.writeLine("Commands/Command.txt 存在，但没有非空命令。")
            return
        }
        let answer = terminal.readLine(prompt: "检测到 Commands/Command.txt，共 \(lines.count) 条非空命令。是否执行？[y/N] ", history: history)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard answer == "y" || answer == "yes" else {
            terminal.writeLine("Command.txt：用户取消执行。")
            return
        }
        var parseMessages = [String]()
        guard let plan = CliCommandPlan.parse(lines, forExecution: true, allowInteractiveStructureName: false,
                                              error: { parseMessages.append($0) }) else {
            parseMessages.forEach(terminal.writeError)
            terminal.writeError("Command.txt 语法检查失败；本次没有执行任何命令。")
            batchExitStatus = max(batchExitStatus, 2)
            return
        }
        terminal.writeLine("Command.txt 语法检查通过，开始执行 \(plan.commands.count) 条命令。")
        var failures = 0
        for planned in plan.commands {
            if cancelled() { break }
            terminal.writeLine("> \(planned.line.text)")
            do {
                let result: WorldCommandExecutionResult
                defer { workspace.session.close() }
                if let request = planned.structureFile {
                    result = try CliStructureFileCommand.execute(request, session: workspace.session)
                } else {
                    result = try WorldCommandExecutor(session: workspace.session).execute(planned.command)
                }
                if result.outputLines.isEmpty {
                    result.message.components(separatedBy: "\n").forEach {
                        terminal.writeLine(WorldCommandOutputLine(text: $0, style: .success))
                    }
                } else { result.outputLines.forEach(terminal.writeLine) }
                if result.changedWorld { dirty = true }
            } catch {
                failures += 1
                if plan.mayMutate { dirty = true }
                terminal.writeError("Command.txt 第 \(planned.line.lineNumber) 行执行失败：\(error.localizedDescription)")
            }
        }
        if failures == 0 && !cancelled() {
            terminal.writeLine("Command.txt 执行完成。")
        } else if failures > 0 {
            terminal.writeError("Command.txt 执行完成：\(failures) 条命令发生运行时错误，其余命令已继续执行。")
            batchExitStatus = max(batchExitStatus, 1)
        }
    }

    private static func promptStructureName(store: StructureNBTStore, listExisting: Bool, terminal: CliTerminal,
                                            history: [String]) -> String? {
        if listExisting {
            do {
                let names = try store.records().map(\.displayName)
                guard !names.isEmpty else { terminal.writeError("没有已保存的结构。"); return nil }
                terminal.writeLine("可用结构：" + names.joined(separator: ", "))
            } catch { terminal.writeError(error.localizedDescription); return nil }
        }
        guard let name = terminal.readLine(prompt: "结构名称> ", history: history)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            terminal.writeError("已取消 structure 文件操作。"); return nil
        }
        return name
    }

    private static func validateSaveAs(_ destination: URL, paths: CliWorldPaths, overwrite: Bool) throws {
        guard destination.pathExtension.lowercased() == "mcworld" else { throw CliError.input("输出文件必须使用 .mcworld 扩展名。") }
        if CliWorldPaths.same(destination, paths.source) || (paths.isDirectory && CliWorldPaths.sameOrInside(destination, paths.source)) {
            throw CliError.input("另存为不能覆盖源世界；原位保存请在 :open 时使用 --in-place 后执行 :save。")
        }
        if FileManager.default.fileExists(atPath: destination.path) && !overwrite {
            throw CliError.input("输出文件已存在；使用 --overwrite 才会覆盖。")
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
            else if c.isWhitespace { if !current.isEmpty { result.append(current); current = "" } }
            else { current.append(c) }
            index = text.index(after: index)
        }
        guard quote == nil else { throw CliError.input("引号未闭合。") }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
