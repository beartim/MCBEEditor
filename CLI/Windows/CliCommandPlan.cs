namespace MCBEEditor.Cli;

internal sealed record CliPlannedCommand(int LineNumber, string Text, object Request);
internal sealed record CliCommandPlan(IReadOnlyList<CliPlannedCommand> Commands)
{
    public bool MayMutate => Commands.Any(command => CliCommandPolicy.MayMutate(command.Request));

    public static CliCommandPlan? Parse(IReadOnlyList<CliCommandLine> lines, TextWriter error, bool forExecution, bool allowInteractiveStructureName = false)
    {
        var parsed = new List<CliPlannedCommand>();
        var failures = 0;
        foreach (var line in lines)
        {
            try
            {
                var request = CliCommandParser.Parse(line.Text);
                if (forExecution && request is CliStructureFileRequest { Core.Name: null } && !allowInteractiveStructureName)
                    throw new CliInputException("非交互 structure import/export 必须指定结构名称；交互会话可省略后按提示输入。");
                if (forExecution) CliCommandPolicy.RequireExecutable(request);
                parsed.Add(new CliPlannedCommand(line.LineNumber, line.Text, request));
            }
            catch (Exception exception) when (exception is InvalidDataException or CliInputException)
            {
                error.WriteLine($"第 {line.LineNumber} 行：{exception.Message}");
                failures++;
            }
        }
        if (failures == 0) return new CliCommandPlan(parsed);
        error.WriteLine($"预检失败：{failures} 行有语法错误或当前不可执行，未执行任何命令。");
        return null;
    }
}
