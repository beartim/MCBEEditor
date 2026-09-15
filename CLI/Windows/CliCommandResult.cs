using MCBEEditor.Core.Chunk;

namespace MCBEEditor.Cli;

internal enum CliOutputKind { Success, LocalPlayer, OnlinePlayer, Entity, Block, BlockEntity, Chunk }
internal sealed record CliOutputLine(string Text, CliOutputKind Kind);
internal sealed record CliCommandResult(bool ChangedWorld, IReadOnlyList<CliOutputLine> Lines)
{
    public static CliCommandResult Text(string text, bool changed = false, CliOutputKind kind = CliOutputKind.Success)
        => new(changed, text.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n')
            .Select(line => new CliOutputLine(line, kind)).ToArray());

    public static CliCommandResult FromCore(TargetingCommandExecutionResult result)
        => new(result.ChangedWorld, result.OutputLines.Select(line => new CliOutputLine(line.Text, line.Style switch
        {
            TargetingOutputStyle.Success => CliOutputKind.Success,
            TargetingOutputStyle.LocalPlayer => CliOutputKind.LocalPlayer,
            TargetingOutputStyle.OnlinePlayer => CliOutputKind.OnlinePlayer,
            TargetingOutputStyle.Entity => CliOutputKind.Entity,
            _ => throw new InvalidOperationException("未知命令输出类型。")
        })).ToArray());
}
