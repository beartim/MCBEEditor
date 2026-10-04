using MCBEEditor.Core.Chunk;
using MCBEEditor.Desktop;

namespace MCBEEditor.Cli;

internal sealed record HelpCliCommand(string? Command);

/// <summary>Routes to the GUI's actual parsers, preserving their typed requests.</summary>
internal static class CliCommandParser
{
    public static object Parse(string text, Func<string, int>? dimensionResolver = null)
    {
        var trimmed = text.Trim();
        if (trimmed.StartsWith('/'))
            throw new InvalidDataException("命令不需要斜杠，请直接输入命令名称");
        var name = FirstToken(trimmed);
        if (name.Length == 0) throw new InvalidDataException("请输入命令");
        if (!CommandHelpCatalog.IsKnownCommand(name))
            throw new InvalidDataException($"不存在的命令：{name}。输入 help 查看全部命令。");
        try
        {
            if (CliStructureFileCommand.TryParse(trimmed, out var structureFile)) return structureFile!;
            if (name.Equals("help", StringComparison.OrdinalIgnoreCase))
            {
                var tokens = trimmed.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
                if (tokens.Length > 2) throw new InvalidDataException("参数格式错误。");
                if (tokens.Length == 2 && !CommandHelpCatalog.IsKnownCommand(tokens[1]))
                    throw new InvalidDataException($"不存在的命令：{tokens[1]}");
                return new HelpCliCommand(tokens.Length == 2 ? tokens[1] : null);
            }
            if (DimensionCommandParser.IsDimensionCommand(trimmed)) return DimensionCommandParser.Parse(trimmed);
            if (BlockCommandParser.IsBlockCommand(trimmed)) return BlockCommandParser.Parse(trimmed, dimensionResolver);
            if (StorageBiomeCommandParser.IsStorageBiomeCommand(trimmed)) return StorageBiomeCommandParser.Parse(trimmed, dimensionResolver);
            if (TargetingCommandParser.IsTargetingCommand(trimmed)) return TargetingCommandParser.Parse(trimmed, dimensionResolver);
            if (EntityActionCommandParser.IsEntityActionCommand(trimmed)) return EntityActionCommandParser.Parse(trimmed, dimensionResolver);
            if (EntityQueryCommandParser.IsEntityQueryCommand(trimmed)) return EntityQueryCommandParser.Parse(trimmed, dimensionResolver);
            if (EnvironmentCommandParser.IsEnvironmentCommand(trimmed)) return EnvironmentCommandParser.Parse(trimmed, dimensionResolver);
            if (StructureTemplateCommandParser.IsStructureTemplateCommand(trimmed)) return StructureTemplateCommandParser.Parse(trimmed, dimensionResolver);
            return ChunkCommandParser.Parse(trimmed, dimensionResolver);
        }
        catch (InvalidDataException error) when (error.Message.StartsWith("参数格式错误。", StringComparison.Ordinal))
        {
            CommandHelpCatalog.TryGetUsage(name, out var usage);
            throw new InvalidDataException("参数格式错误。\n" + usage, error);
        }
    }

    public static string FirstToken(string text)
    {
        var trimmed = text.TrimStart();
        var end = 0;
        while (end < trimmed.Length && !char.IsWhiteSpace(trimmed[end])) end++;
        return trimmed[..end];
    }
}
