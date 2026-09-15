namespace MCBEEditor.Cli;

internal sealed record CliWorldPaths(string Source, string Cache, string? Output)
{
    private static StringComparison Comparison => OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

    public static CliWorldPaths Validate(CliRunOptions options)
    {
        var source = Path.TrimEndingDirectorySeparator(Path.GetFullPath(options.WorldPath));
        var cache = Path.GetFullPath(options.CacheDirectory);
        var output = options.OutputPath is null ? null : Path.GetFullPath(options.OutputPath);
        RequireRegularPath(source);
        RequireRegularPath(cache);
        if (options.ScriptPath is not null && options.ScriptPath != "-") RequireRegularPath(options.ScriptPath);
        if (Directory.Exists(source))
        {
            if (SameOrInside(cache, source))
                throw new CliInputException("缓存目录不能等于源世界目录或位于其内部。");
        }
        else
        {
            if (!File.Exists(source)) throw new FileNotFoundException("找不到世界来源。", source);
            if (!new[] { ".mcworld", ".zip" }.Contains(Path.GetExtension(source), StringComparer.OrdinalIgnoreCase))
                throw new CliInputException("输入需要世界文件夹、.mcworld 或 ZIP 世界文件。");
        }
        if (options.InPlace)
        {
            if (!Directory.Exists(source) && !Path.GetExtension(source).Equals(".mcworld", StringComparison.OrdinalIgnoreCase))
                throw new CliInputException("原位更新支持世界文件夹或 .mcworld；ZIP 输入请用 --output 另存为。");
            if (Same(source, Path.GetPathRoot(source)!)) throw new CliInputException("不能原位替换文件系统根目录。");
            if (options.ScriptPath is not null && options.ScriptPath != "-" && Same(source, options.ScriptPath))
                throw new CliInputException("原位更新不能覆盖输入命令文件。");
        }
        if (output is not null)
        {
            RequireRegularPath(output);
            if (!Path.GetExtension(output).Equals(".mcworld", StringComparison.OrdinalIgnoreCase))
                throw new CliInputException("输出文件必须使用 .mcworld 扩展名。");
            if (Directory.Exists(output)) throw new CliInputException("输出路径指向文件夹，请指定 .mcworld 文件。");
            if (SameOrInside(output, cache)) throw new CliInputException("输出文件不能位于工作副本缓存目录内。");
            if (Same(output, source) || Directory.Exists(source) && SameOrInside(output, source))
                throw new CliInputException("输出必须另存到源世界之外，不能覆盖或写入源世界。");
            if (options.ScriptPath is not null && options.ScriptPath != "-" && Same(output, Path.GetFullPath(options.ScriptPath)))
                throw new CliInputException("输出不能覆盖输入命令文件。");
            if (File.Exists(output) && !options.Overwrite)
                throw new CliInputException("输出文件已存在；另选文件名或显式使用 --overwrite。");
        }
        return new CliWorldPaths(source, cache, output);
    }

    public static bool Same(string left, string right)
        => string.Equals(Path.GetFullPath(left).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
            Path.GetFullPath(right).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar), Comparison);

    public static bool SameOrInside(string candidate, string directory)
        => Same(candidate, directory) || Path.GetFullPath(candidate).StartsWith(
            Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar, Comparison);

    // Refuse aliases that could make an apparently separate output point into the input world.
    public static void RequireRegularPath(string path)
    {
        for (string? current = Path.GetFullPath(path); !string.IsNullOrEmpty(current); current = Path.GetDirectoryName(current))
        {
            FileAttributes attributes;
            try { attributes = File.GetAttributes(current); }
            catch (FileNotFoundException) { continue; }
            catch (DirectoryNotFoundException) { continue; }
            if ((attributes & FileAttributes.ReparsePoint) != 0)
                throw new CliInputException($"暂不支持符号链接或目录联接路径：{current}。请使用实际路径。");
        }
    }
}
