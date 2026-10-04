using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.World;

namespace MCBEEditor.Cli;

internal static class CliInteractiveShell
{
    public static int Run(TextReader input, TextWriter output, TextWriter error, CancellationToken cancellationToken,
        bool terminalFeatures = false, string? commandsDirectory = null)
    {
        var terminal = new CliTerminal(input, output, error, terminalFeatures);
        var history = new List<string>();
        CliWorldSession? session = null;
        CliWorldPaths? paths = null;
        bool inPlace = false, dirty = false, inPlacePending = false;
        var batchExitStatus = 0;
        try
        {
            terminal.WriteLine("MCBEEditor CLI 交互会话。输入 :help 查看会话命令。");
            while (!cancellationToken.IsCancellationRequested)
            {
                var line = terminal.ReadLine(session is null ? "mcbe> " : "mcbe(world)> ", history);
                if (cancellationToken.IsCancellationRequested) return 130;
                if (line is null) return dirty ? 1 : batchExitStatus;
                line = line.Trim();
                if (line.Length == 0) continue;
                history.Add(line);
                try
                {
                    if (line.StartsWith(':'))
                    {
                        var meta = Tokenize(line);
                        var name = meta[0].ToLowerInvariant();
                        if (name == ":help")
                        {
                            terminal.WriteLine(":open \"世界路径\" [--in-place]\n:save [\"输出.mcworld\"] [--overwrite]\n:history\n:clear\n:quit [--discard]\n普通游戏命令直接输入；structure import/export 使用 --file 路径。");
                            continue;
                        }
                        if (name == ":history")
                        {
                            if (meta.Count != 1) { terminal.WriteError("用法：:history"); continue; }
                            for (var i = 0; i < history.Count; i++) terminal.WriteLine($"{i + 1,4}  {history[i]}");
                            continue;
                        }
                        if (name == ":clear")
                        {
                            if (meta.Count != 1) { terminal.WriteError("用法：:clear"); continue; }
                            terminal.Clear();
                            continue;
                        }
                        if (name == ":open")
                        {
                            if (dirty) { terminal.WriteError("当前世界有未保存修改；请先 :save 或 :quit --discard 后重新进入会话。"); continue; }
                            if (meta.Count is < 2 or > 3 || meta.Skip(2).Any(x => !x.Equals("--in-place", StringComparison.OrdinalIgnoreCase)))
                            { terminal.WriteError("用法：:open \"世界路径\" [--in-place]"); continue; }
                            var nextInPlace = meta.Skip(2).Any(x => x.Equals("--in-place", StringComparison.OrdinalIgnoreCase));
                            var opts = new CliRunOptions(meta[1], [], null, null,
                                CliPortablePaths.WorldCacheDirectory, false, false, nextInPlace);
                            var nextPaths = CliWorldPaths.Validate(opts);
                            if (session is not null && CliWorldPaths.SameOrInside(nextPaths.Source, session.SessionRoot))
                                throw new CliInputException("不能将当前会话的临时副本重新作为来源打开；请先另存到缓存目录外。");
                            var nextSession = CliWorldSession.Open(nextPaths, nextInPlace);
                            // Keep the current world usable if validating/opening its replacement fails.
                            session?.DiscardWork(); session?.Dispose();
                            session = nextSession; paths = nextPaths; inPlace = nextInPlace;
                            dirty = false; inPlacePending = false;
                            terminal.WriteLine($"已打开工作副本：{session.WorkingRoot}");
                            RunSharedCommandFileIfPresent(session, nextPaths, terminal, history,
                                commandsDirectory ?? CliSharedCommandStore.DefaultDirectory, ref dirty, ref batchExitStatus, cancellationToken);
                            inPlacePending = dirty;
                            continue;
                        }
                        if (name == ":save")
                        {
                            if (session is null || paths is null) { terminal.WriteError("尚未打开世界。先使用 :open。"); continue; }
                            var overwrite = meta.Any(x => x.Equals("--overwrite", StringComparison.OrdinalIgnoreCase));
                            var values = meta.Skip(1).Where(x => !x.Equals("--overwrite", StringComparison.OrdinalIgnoreCase)).ToArray();
                            try
                            {
                                if (values.Length == 0)
                                {
                                    if (!inPlace) { terminal.WriteError("当前不是原位会话；请使用 :save \"输出.mcworld\" [--overwrite]。"); continue; }
                                    if (!inPlacePending) { terminal.WriteLine("没有未保存修改。"); continue; }
                                    session.CommitInPlace(terminal.WriteError);
                                    dirty = false; inPlacePending = false;
                                    terminal.WriteLine($"原位更新完成：{paths.Source}");
                                }
                                else if (values.Length == 1)
                                {
                                    var destination = Path.GetFullPath(values[0]);
                                    paths.ValidateSaveAs(destination, overwrite);
                                    session.Export(destination, overwrite);
                                    dirty = false;
                                    terminal.WriteLine($"导出完成：{destination}");
                                }
                                else terminal.WriteError("用法：:save [\"输出.mcworld\"] [--overwrite]");
                            }
                            catch (Exception ex) when (IsRecoverable(ex)) { terminal.WriteError("保存失败：" + ex.Message); }
                            continue;
                        }
                        if (name == ":quit")
                        {
                            var discard = meta.Skip(1).Any(x => x.Equals("--discard", StringComparison.OrdinalIgnoreCase));
                            if (meta.Count > 2 || (meta.Count == 2 && !discard)) { terminal.WriteError("用法：:quit [--discard]"); continue; }
                            if (dirty && !discard) { terminal.WriteError("当前世界有未保存修改；先 :save，或使用 :quit --discard 放弃本会话修改。"); continue; }
                            if (discard) dirty = false;
                            return batchExitStatus;
                        }
                        terminal.WriteError("未知会话命令.输入 :help 查看可用命令。");
                        continue;
                    }

                    if (session is null) { terminal.WriteError("尚未打开世界。先使用 :open \"世界路径\"。"); continue; }
                    using var parseErrors = new StringWriter();
                    CliCommandPlan? plan;
                    using (var database = session.Document.OpenDatabase(readOnly: true))
                        plan = CliCommandPlan.Parse([new CliCommandLine(1, line)], parseErrors, forExecution: true, allowInteractiveStructureName: true,
                            dimensionContext: MCBEEditor.Core.World.DimensionCommandContext.FromDatabase(database));
                    if (plan is null) { terminal.WriteError(parseErrors.ToString().TrimEnd()); continue; }
                    CliStructureFileCommand.ValidateFiles(plan.Commands.Select(command => command.Request).OfType<CliStructureFileRequest>(), paths!,
                        CliSharedCommandStore.CommandFilePath(commandsDirectory ?? CliSharedCommandStore.DefaultDirectory));
                    object? request = plan.Commands[0].Request;
                    request = PromptStructureNameIfNeeded(request, session, terminal, history);
                    if (cancellationToken.IsCancellationRequested) return 130;
                    if (request is null) continue;
                    var mutating = CliCommandPolicy.MayMutate(request);
                    try
                    {
                        var executor = new CliWorldCommandExecutor(session.Document);
                        var result = request is CliStructureFileRequest ? executor.Execute(request) : executor.Execute(line);
                        foreach (var row in result.Lines) terminal.WriteLine(row);
                        if (result.ChangedWorld) { dirty = true; inPlacePending = true; }
                    }
                    catch (Exception ex) when (IsRecoverable(ex))
                    {
                        if (mutating) { dirty = true; inPlacePending = true; }
                        terminal.WriteError("执行失败：" + ex.Message);
                    }
                }
                catch (Exception ex) when (IsRecoverable(ex)) { terminal.WriteError(ex.Message); }
            }
            return 130;
        }
        finally
        {
            if (session is not null)
            {
                if (!dirty) session.DiscardWork();
                var root = session.WorkingRoot;
                session.Dispose();
                if (Directory.Exists(root)) terminal.WriteError("工作副本已保留：" + root);
            }
        }
    }


    private static void RunSharedCommandFileIfPresent(CliWorldSession session, CliWorldPaths paths, CliTerminal terminal, IReadOnlyList<string> history,
        string directory, ref bool dirty, ref int batchExitStatus, CancellationToken cancellationToken)
    {
        if (!CliSharedCommandStore.CommandFileExists(directory)) return;
        IReadOnlyList<CliCommandLine> lines;
        try { lines = CliSharedCommandStore.ReadCommandLines(directory); }
        catch (Exception ex) when (IsRecoverable(ex))
        {
            terminal.WriteError("Command.txt 读取失败：" + ex.Message);
            batchExitStatus = Math.Max(batchExitStatus, 3);
            return;
        }
        if (lines.Count == 0)
        {
            terminal.WriteLine("Commands/Command.txt 存在，但没有非空命令。");
            return;
        }
        var answer = terminal.ReadLine($"检测到 Commands/Command.txt，共 {lines.Count} 条非空命令。是否执行？[y/N] ", history)?.Trim();
        if (!string.Equals(answer, "y", StringComparison.OrdinalIgnoreCase)
            && !string.Equals(answer, "yes", StringComparison.OrdinalIgnoreCase))
        {
            terminal.WriteLine("Command.txt：用户取消执行。");
            return;
        }

        using var parseErrors = new StringWriter();
        CliCommandPlan? plan;
        using (var database = session.Document.OpenDatabase(readOnly: true))
            plan = CliCommandPlan.Parse(lines, parseErrors, forExecution: true, allowInteractiveStructureName: false,
                dimensionContext: MCBEEditor.Core.World.DimensionCommandContext.FromDatabase(database));
        if (plan is null)
        {
            var details = parseErrors.ToString().TrimEnd();
            if (details.Length > 0) terminal.WriteError(details);
            terminal.WriteError("Command.txt 语法检查失败；本次没有执行任何命令。");
            batchExitStatus = Math.Max(batchExitStatus, 2);
            return;
        }
        try { CliStructureFileCommand.ValidateFiles(plan.Commands.Select(command => command.Request).OfType<CliStructureFileRequest>(), paths, CliSharedCommandStore.CommandFilePath(directory)); }
        catch (Exception ex) when (IsRecoverable(ex))
        {
            terminal.WriteError("Command.txt 文件预检失败：" + ex.Message);
            batchExitStatus = Math.Max(batchExitStatus, 2);
            return;
        }
        terminal.WriteLine($"Command.txt 语法检查通过，开始执行 {plan.Commands.Count} 条命令。");
        var executor = new CliWorldCommandExecutor(session.Document);
        var failures = 0;
        foreach (var command in plan.Commands)
        {
            if (cancellationToken.IsCancellationRequested) break;
            terminal.WriteLine($"> {command.Text}");
            var mutating = CliCommandPolicy.MayMutate(command.Request);
            try
            {
                var result = executor.Execute(command.Text);
                foreach (var row in result.Lines) terminal.WriteLine(row);
                if (result.ChangedWorld) dirty = true;
            }
            catch (Exception ex) when (IsRecoverable(ex))
            {
                failures++;
                if (mutating) dirty = true;
                terminal.WriteError($"Command.txt 第 {command.LineNumber} 行执行失败：{ex.Message}");
            }
        }
        if (failures == 0 && !cancellationToken.IsCancellationRequested)
            terminal.WriteLine("Command.txt 执行完成。");
        else if (failures > 0)
        {
            terminal.WriteError($"Command.txt 执行完成：{failures} 条命令发生运行时错误，其余命令已继续执行。");
            batchExitStatus = Math.Max(batchExitStatus, 1);
        }
    }

    private static object? PromptStructureNameIfNeeded(object request, CliWorldSession session, CliTerminal terminal,
        IReadOnlyList<string> history)
    {
        if (request is not CliStructureFileRequest file || file.Core.Name is not null) return request;
        if (file.Core.Operation == StructureTemplateStructureOperationKind.Export)
        {
            using var db = session.Document.OpenDatabase(readOnly: true);
            var names = new StructureNbtStore(db).Records().Select(x => x.DisplayName).ToArray();
            if (names.Length == 0) { terminal.WriteError("没有已保存的结构。"); return null; }
            terminal.WriteLine("可用结构：" + string.Join(", ", names));
        }
        var name = terminal.ReadLine("结构名称> ", history)?.Trim();
        if (string.IsNullOrWhiteSpace(name)) { terminal.WriteError("已取消 structure 文件操作。"); return null; }
        return file with { Core = file.Core with { Name = name } };
    }

    private static bool IsRecoverable(Exception ex) => ex is IOException or InvalidDataException or InvalidOperationException
        or UnauthorizedAccessException or NotSupportedException or ArgumentException or OverflowException or FormatException or CliInputException;

    internal static List<string> Tokenize(string text)
    {
        var result = new List<string>(); var current = new System.Text.StringBuilder(); char? quote = null;
        for (var i = 0; i < text.Length; i++)
        {
            var c = text[i];
            if (quote.HasValue)
            {
                if (c == quote.Value) { quote = null; continue; }
                if (c == '\\' && i + 1 < text.Length && text[i + 1] == quote.Value) { current.Append(text[++i]); continue; }
                current.Append(c); continue;
            }
            if (c is '\'' or '"') { quote = c; continue; }
            if (char.IsWhiteSpace(c)) { if (current.Length > 0) { result.Add(current.ToString()); current.Clear(); } continue; }
            current.Append(c);
        }
        if (quote.HasValue) throw new InvalidDataException("引号未闭合。");
        if (current.Length > 0) result.Add(current.ToString());
        return result;
    }
}
