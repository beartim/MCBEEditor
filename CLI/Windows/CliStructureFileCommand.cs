using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Cli;

internal sealed record CliStructureFileRequest(
    StructureTemplateStructureCommandRequest Core,
    string FilePath,
    bool Overwrite);

internal static class CliStructureFileCommand
{
    public const string Usage = "structure import 名称 --file \"路径.mcstructure|nbt|json\" [--overwrite]\n" +
        "structure export mcstructure|nbt|json 名称 --file \"输出路径\" [--overwrite]\n" +
        "非交互模式名称和 --file 均必填；交互模式可省略名称后按提示输入。";
    public static bool TryParse(string text, out CliStructureFileRequest? request)
    {
        request = null;
        var tokens = Tokenize(text);
        if (tokens.Count < 2 || !tokens[0].Equals("structure", StringComparison.OrdinalIgnoreCase)) return false;
        var action = tokens[1].ToLowerInvariant();
        if (action is not ("import" or "export")) return false;
        var fileIndex = tokens.FindIndex(token => token.Equals("--file", StringComparison.OrdinalIgnoreCase));
        if (fileIndex < 0) return false;
        if (fileIndex + 1 >= tokens.Count) throw new InvalidDataException("structure import/export 的 --file 缺少路径。");
        var overwrite = tokens.Any(token => token.Equals("--overwrite", StringComparison.OrdinalIgnoreCase));
        var allowedFlags = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "--file", "--overwrite" };
        for (var i = 2; i < tokens.Count; i++)
            if (tokens[i].StartsWith("--", StringComparison.Ordinal) && !allowedFlags.Contains(tokens[i]))
                throw new InvalidDataException($"未知 structure 文件参数：{tokens[i]}");
        if (tokens.Count(token => token.Equals("--file", StringComparison.OrdinalIgnoreCase)) != 1 ||
            tokens.Count(token => token.Equals("--overwrite", StringComparison.OrdinalIgnoreCase)) > 1)
            throw new InvalidDataException("structure 文件参数不能重复。");

        var coreTokens = new List<string>();
        for (var i = 0; i < tokens.Count; i++)
        {
            if (tokens[i].Equals("--file", StringComparison.OrdinalIgnoreCase)) { i++; continue; }
            if (tokens[i].Equals("--overwrite", StringComparison.OrdinalIgnoreCase)) continue;
            coreTokens.Add(tokens[i]);
        }
        var core = StructureTemplateCommandParser.Parse(string.Join(' ', coreTokens));
        request = new CliStructureFileRequest(core, Path.GetFullPath(tokens[fileIndex + 1]), overwrite);
        return true;
    }

    public static CliCommandResult Execute(CliStructureFileRequest request, WorldDocument document)
    {
        if (request.Core.Operation == StructureTemplateStructureOperationKind.Import)
        {
            var name = request.Core.Name ?? throw new CliInputException("非交互 structure import 必须指定结构名称；交互会话可省略后按提示输入。");
            if (!File.Exists(request.FilePath)) throw new FileNotFoundException("找不到结构文件。", request.FilePath);
            if (!new[] { ".mcstructure", ".nbt", ".json" }.Contains(Path.GetExtension(request.FilePath), StringComparer.OrdinalIgnoreCase))
                throw new InvalidDataException("structure import 仅支持 .mcstructure、.nbt 或 .json 文件。");
            var file = StandaloneNbtFileCodec.Decode(File.ReadAllBytes(request.FilePath), request.FilePath);
            if (file.Documents.Count != 1) throw new InvalidDataException("结构文件必须只包含一个 NBT 根标签。");
            using var database = document.OpenDatabase(readOnly: false);
            var store = new StructureNbtStore(database);
            name = StructureNbtStore.NormalizeName(name);
            var exists = store.Contains(name);
            if (exists && !request.Overwrite)
                throw new InvalidDataException($"已存在同名结构：{name}；显式使用 --overwrite 才会覆盖。");
            var result = store.SaveNew(file.Documents[0], name, overwrite: request.Overwrite);
            var message = $"structure import 完成：{name}";
            if (result.ConvertedFromJava)
                message += $"；Java → Bedrock，{result.PlacedBlockCount} 个方块，{result.LossyPaletteEntryCount} 个调色板条目发生兼容降级；不带入实体、水层及高级方块实体数据。";
            return CliCommandResult.Text(message, true);
        }
        if (request.Core.Operation == StructureTemplateStructureOperationKind.Export)
        {
            var name = request.Core.Name ?? throw new CliInputException("非交互 structure export 必须指定结构名称；交互会话可省略后按提示选择。");
            var format = request.Core.Format ?? throw new InvalidDataException("structure export 缺少格式。");
            var expected = "." + format.ToString().ToLowerInvariant();
            if (!Path.GetExtension(request.FilePath).Equals(expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException($"导出文件扩展名必须与格式一致：{expected}");
            if (Directory.Exists(request.FilePath)) throw new InvalidDataException("structure export 的 --file 必须指向文件。 ");
            if (File.Exists(request.FilePath) && !request.Overwrite)
                throw new InvalidDataException("导出文件已存在；显式使用 --overwrite 才会覆盖。");
            using var database = document.OpenDatabase(readOnly: true);
            var store = new StructureNbtStore(database);
            var key = StructureNbtStore.KeyForName(name);
            var record = store.Records().FirstOrDefault(item => item.Key.AsSpan().SequenceEqual(key))
                ?? throw new InvalidDataException($"不存在结构：{name}");
            var documentValue = record.Document ?? throw new InvalidDataException($"结构 NBT 无法解析：{record.DisplayName}");
            var data = StandaloneNbtFileCodec.EncodeStructure(documentValue, format);
            var parent = Path.GetDirectoryName(request.FilePath) ?? throw new InvalidDataException("导出路径缺少父目录。");
            Directory.CreateDirectory(parent);
            var temporary = Path.Combine(parent, $".mcbe-structure-{Guid.NewGuid():N}.tmp");
            try
            {
                File.WriteAllBytes(temporary, data);
                File.Move(temporary, request.FilePath, request.Overwrite);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
            return CliCommandResult.Text($"structure export 完成：{request.FilePath}");
        }
        throw new InvalidDataException("未知 structure 文件操作。");
    }

    private static List<string> Tokenize(string text)
    {
        var result = new List<string>();
        var current = new System.Text.StringBuilder();
        char? quote = null;
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
            if (char.IsWhiteSpace(c))
            {
                if (current.Length > 0) { result.Add(current.ToString()); current.Clear(); }
                continue;
            }
            current.Append(c);
        }
        if (quote.HasValue) throw new InvalidDataException("structure 文件路径引号未闭合。");
        if (current.Length > 0) result.Add(current.ToString());
        return result;
    }
}
