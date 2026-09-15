using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Cli;

internal enum CliConversionFormat
{
    BigEndian,
    LittleEndian,
    LittleVarInt,
    Json,
    Mcstructure
}

internal sealed record CliConversionRequest(
    string InputPath,
    string OutputPath,
    CliConversionFormat Format,
    bool Overwrite);

internal static class CliFormatConverter
{
    public const string Usage = """
mcbe-cli --convert "输入.nbt|mcstructure|json" --to big-endian|little-endian|little-varint|json|mcstructure --output "输出文件" [--overwrite]

输入自动识别 JSON NBT、Big Endian、Little Endian、Little Endian VarInt、连续多根 NBT 与 GZip/Zlib 包装。
输出 binary NBT 均为未压缩；JSON 保留 NBT 类型；mcstructure 仅支持单根结构 NBT，并可自动将 Java structure NBT 转为 Bedrock mcstructure。
""";

    public static int Run(string[] args, TextWriter output)
    {
        var request = Parse(args);
        Execute(request, output);
        return 0;
    }

    internal static CliConversionRequest Parse(string[] args)
    {
        if (args.Length < 6 || !args[0].Equals("--convert", StringComparison.OrdinalIgnoreCase))
            throw new CliInputException("格式转换参数不完整。\n" + Usage);

        var input = args[1];
        if (input.StartsWith("--", StringComparison.Ordinal))
            throw new CliInputException("--convert 后必须直接提供输入文件路径。");

        string? formatText = null;
        string? output = null;
        var overwrite = false;
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (var i = 2; i < args.Length; i++)
        {
            var token = args[i];
            if (token.Equals("--overwrite", StringComparison.OrdinalIgnoreCase))
            {
                if (!seen.Add("--overwrite")) throw new CliInputException("--overwrite 不能重复。");
                overwrite = true;
                continue;
            }
            if (token.Equals("--to", StringComparison.OrdinalIgnoreCase) || token.Equals("--output", StringComparison.OrdinalIgnoreCase))
            {
                if (!seen.Add(token)) throw new CliInputException($"{token} 不能重复。");
                if (++i >= args.Length) throw new CliInputException($"{token} 缺少参数。");
                if (token.Equals("--to", StringComparison.OrdinalIgnoreCase)) formatText = args[i];
                else output = args[i];
                continue;
            }
            throw new CliInputException($"未知格式转换参数：{token}\n" + Usage);
        }

        if (string.IsNullOrWhiteSpace(formatText) || string.IsNullOrWhiteSpace(output))
            throw new CliInputException("格式转换必须同时指定 --to 和 --output。\n" + Usage);

        var format = formatText.ToLowerInvariant() switch
        {
            "big-endian" => CliConversionFormat.BigEndian,
            "little-endian" => CliConversionFormat.LittleEndian,
            "little-varint" => CliConversionFormat.LittleVarInt,
            "json" => CliConversionFormat.Json,
            "mcstructure" => CliConversionFormat.Mcstructure,
            _ => throw new CliInputException($"未知输出格式：{formatText}。支持 big-endian、little-endian、little-varint、json、mcstructure。")
        };
        return new CliConversionRequest(Path.GetFullPath(input), Path.GetFullPath(output), format, overwrite);
    }

    internal static void Execute(CliConversionRequest request, TextWriter output)
    {
        if (!File.Exists(request.InputPath)) throw new FileNotFoundException("找不到转换输入文件。", request.InputPath);
        if (Directory.Exists(request.OutputPath)) throw new InvalidDataException("转换输出路径必须指向文件。");
        var expectedExtension = request.Format switch
        {
            CliConversionFormat.Json => ".json",
            CliConversionFormat.Mcstructure => ".mcstructure",
            _ => ".nbt"
        };
        if (!Path.GetExtension(request.OutputPath).Equals(expectedExtension, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException($"输出扩展名必须与格式一致：{expectedExtension}");
        if (File.Exists(request.OutputPath) && !request.Overwrite)
            throw new InvalidDataException("转换输出文件已存在；显式使用 --overwrite 才会覆盖。");

        var decoded = StandaloneNbtFileCodec.Decode(File.ReadAllBytes(request.InputPath), request.InputPath);
        byte[] data;
        StructureImportResult? conversion = null;
        try
        {
            data = request.Format switch
            {
                CliConversionFormat.BigEndian => StandaloneNbtFileCodec.Encode(decoded.Documents, NbtEncoding.BigEndian),
                CliConversionFormat.LittleEndian => StandaloneNbtFileCodec.Encode(decoded.Documents, NbtEncoding.LittleEndian),
                CliConversionFormat.LittleVarInt => StandaloneNbtFileCodec.Encode(decoded.Documents, NbtEncoding.LittleEndianVarInt),
                CliConversionFormat.Json => StandaloneNbtFileCodec.EncodeJson(decoded.Documents),
                CliConversionFormat.Mcstructure => EncodeMcstructure(decoded.Documents, out conversion),
                _ => throw new InvalidDataException("未知转换格式。")
            };
        }
        catch (NotSupportedException exception)
        {
            throw new InvalidDataException(exception.Message, exception);
        }

        var parent = Path.GetDirectoryName(request.OutputPath) ?? throw new InvalidDataException("转换输出路径缺少父目录。");
        Directory.CreateDirectory(parent);
        var temporary = Path.Combine(parent, $".mcbe-convert-{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllBytes(temporary, data);
            File.Move(temporary, request.OutputPath, request.Overwrite);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }

        var target = request.Format switch
        {
            CliConversionFormat.BigEndian => "Big Endian NBT",
            CliConversionFormat.LittleEndian => "Little Endian NBT",
            CliConversionFormat.LittleVarInt => "Little Endian VarInt NBT",
            CliConversionFormat.Json => "JSON NBT",
            CliConversionFormat.Mcstructure => "Bedrock mcstructure",
            _ => request.Format.ToString()
        };
        var message = $"格式转换完成：{request.OutputPath}\n输入：{decoded.FormatDescription}\n输出：{target}；根标签={decoded.Documents.Count}";
        if (conversion?.ConvertedFromJava == true)
            message += $"\nJava → Bedrock：方块={conversion.PlacedBlockCount}，调色板={conversion.PaletteEntryCount}，兼容降级={conversion.LossyPaletteEntryCount}。";
        output.WriteLine(message);
    }

    private static byte[] EncodeMcstructure(IReadOnlyList<NbtDocument> documents, out StructureImportResult? result)
    {
        var converted = StandaloneNbtFileCodec.EncodeAsMcStructure(documents);
        result = converted.Result;
        return converted.Data;
    }
}
