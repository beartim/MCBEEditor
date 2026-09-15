namespace MCBEEditor.Cli;

internal sealed class CliInputException(string message) : Exception(message) { }

internal sealed record CliRunOptions(
    string WorldPath, IReadOnlyList<string> Commands, string? ScriptPath,
    string? OutputPath, string CacheDirectory, bool Overwrite, bool KeepWork, bool InPlace)
{
    public static CliRunOptions Parse(string[] args)
    {
        string? world = null, script = null, output = null, cache = null;
        var commands = new List<string>();
        var flags = new HashSet<string>(StringComparer.Ordinal);
        bool overwrite = false, keepWork = false, inPlace = false;
        for (var i = 0; i < args.Length; i++)
        {
            var option = args[i];
            if (option != "--command" && !flags.Add(option))
                throw new CliInputException($"CLI 参数不能重复：{option}");
            string Value()
            {
                if (i + 1 >= args.Length || string.IsNullOrWhiteSpace(args[i + 1]) || args[i + 1].StartsWith("--", StringComparison.Ordinal))
                    throw new CliInputException($"CLI 参数缺少值：{option}");
                return args[++i];
            }
            switch (option)
            {
                case "--world": world = Value(); break;
                case "--command": commands.Add(Value()); break;
                case "--script": script = Value(); break;
                case "--output": output = Value(); break;
                case "--cache-dir": cache = Value(); break;
                case "--overwrite": overwrite = true; break;
                case "--keep-work": keepWork = true; break;
                case "--in-place": inPlace = true; break;
                default: throw new CliInputException($"未知 CLI 参数：{option}");
            }
        }
        if (world is null) throw new CliInputException("执行命令需要 --world 存档路径。");
        if (commands.Count == 0 && script is null)
            throw new CliInputException("需要 --command 或 --script；持续会话请使用 --interactive。");
        if (commands.Count > 0 && script is not null)
            throw new CliInputException("--command 与 --script 不能同时使用。");
        if (overwrite && output is null) throw new CliInputException("--overwrite 需要同时指定 --output。");
        if (inPlace && output is not null) throw new CliInputException("--in-place 与 --output 不能同时使用。");
        return new CliRunOptions(world, commands, script, output,
            cache ?? CliPortablePaths.WorldCacheDirectory, overwrite, keepWork, inPlace);
    }
}
