namespace MCBEEditor.Cli;

internal static class CliWorldRunner
{
    public static int Run(CliRunOptions options, TextWriter output, TextWriter error, CancellationToken cancellationToken)
    {
        var lines = options.ScriptPath is not null ? CliCommandFile.Read(options.ScriptPath)
            : options.Commands.Select((text, index) => new CliCommandLine(index + 1, text)).ToArray();
        var plan = CliCommandPlan.Parse(lines, error, forExecution: true);
        if (plan is null) return 2;
        if (plan.MayMutate && options.OutputPath is null && !options.InPlace)
            throw new CliInputException("本次命令包含存档修改，必须指定 --in-place 原位更新或 --output 新文件.mcworld 另存为。");
        var paths = CliWorldPaths.Validate(options);
        cancellationToken.ThrowIfCancellationRequested();
        CliWorldSession? session = null;
        try
        {
            session = CliWorldSession.Open(paths, options.InPlace);
            error.WriteLine($"工作副本：{session.WorkingRoot}");
            var executor = new CliWorldCommandExecutor(session.Document);
            var failures = 0;
            foreach (var command in plan.Commands)
            {
                if (cancellationToken.IsCancellationRequested) break;
                output.WriteLine("> " + command.Text);
                output.Flush();
                try
                {
                    var result = executor.Execute(command.Request);
                    foreach (var line in result.Lines) output.WriteLine(line.Text);
                }
                catch (Exception exception) when (IsCommandFailure(exception))
                {
                    failures++;
                    error.WriteLine($"第 {command.LineNumber} 行执行失败：{exception.Message}");
                    if (exception.InnerException is DllNotFoundException or BadImageFormatException)
                        error.WriteLine("请运行 CLI/Scripts/build-windows.ps1 构建并复制 x64 原生 LevelDB 组件。");
                }
                output.Flush();
                error.Flush();
            }
            if (cancellationToken.IsCancellationRequested)
            {
                error.WriteLine("已在当前命令结束后取消；未导出或提交，工作副本保留。");
                return 130;
            }
            if (paths.Output is not null)
            {
                session.Export(paths.Output, options.Overwrite);
                output.WriteLine($"导出完成：{paths.Output}");
                if (failures > 0)
                    error.WriteLine("已导出发生错误后的当前工作副本；其中可能包含出错命令在报错前写入的数据。");
            }
            else if (options.InPlace && failures == 0 && plan.MayMutate)
            {
                session.CommitInPlace(error.WriteLine);
                output.WriteLine($"原位更新完成：{paths.Source}");
            }
            else if (options.InPlace && failures > 0)
                error.WriteLine("存在执行错误，未提交原位更新；原存档未写回本次命令结果。");
            output.WriteLine($"执行完成：{plan.Commands.Count} 条命令，失败 {failures} 条。");
            if (failures == 0) session.Complete(options.KeepWork);
            return failures == 0 ? 0 : 1;
        }
        finally
        {
            if (session is not null)
            {
                var workingRoot = session.WorkingRoot;
                session.Dispose();
                if (Directory.Exists(workingRoot))
                    error.WriteLine($"工作副本已保留：{workingRoot}\n可将此路径作为下一次 --world 的输入继续处理或重新导出。");
            }
        }
    }

    private static bool IsCommandFailure(Exception exception)
        => exception is IOException or InvalidDataException or InvalidOperationException or UnauthorizedAccessException
            or NotSupportedException or ArgumentException or OverflowException or FormatException;
}
