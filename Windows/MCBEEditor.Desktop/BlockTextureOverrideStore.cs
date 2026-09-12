using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace MCBEEditor.Desktop;

/// <summary>
/// Portable Windows texture override store rooted beside MCBEEditor.exe.
/// Colors.txt wins over PNG, and later duplicate text entries win.
/// </summary>
internal static class BlockTextureOverrideStore
{
    private static readonly object Gate = new();
    private static Dictionary<string, uint> _colors = new(StringComparer.Ordinal);

    public static string DirectoryPath => PortablePaths.TexturesPath;

    public static int Count
    {
        get { lock (Gate) return _colors.Count; }
    }

    public static void PrepareAndReload()
    {
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            File.WriteAllText(Path.Combine(DirectoryPath, "ReadMe.txt"), ReadMeText, new System.Text.UTF8Encoding(false));
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        Reload();
    }

    public static void Reload()
    {
        string[] pngFiles;
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            pngFiles = Directory.GetFiles(DirectoryPath, "*.png", SearchOption.TopDirectoryOnly);
        }
        catch (IOException)
        {
            // Optional user overrides must not make map rendering unavailable.
            return;
        }
        catch (UnauthorizedAccessException) { return; }

        var textColors = ParseColorsFile(Path.Combine(DirectoryPath, "Colors.txt"));
        var loaded = new Dictionary<string, uint>(textColors, StringComparer.Ordinal);
        foreach (var path in pngFiles.OrderBy(path => Path.GetFileName(path), StringComparer.OrdinalIgnoreCase))
        {
            var identifier = IdentifierFromPngStem(Path.GetFileNameWithoutExtension(path));
            if (identifier is null || textColors.ContainsKey(identifier)) continue;
            var color = AveragePngRgb(path);
            if (color.HasValue) loaded[identifier] = color.Value;
        }

        lock (Gate) _colors = loaded;
    }

    public static uint? ColorFor(string identifier)
    {
        var key = Normalize(identifier);
        lock (Gate) return _colors.TryGetValue(key, out var color) ? color : null;
    }

    internal static Dictionary<string, uint> ParseColorsText(string text)
    {
        if (text.Length > 0 && text[0] == '\uFEFF') text = text[1..];
        var result = new Dictionary<string, uint>(StringComparer.Ordinal);
        using var reader = new StringReader(text);
        while (reader.ReadLine() is { } line)
        {
            var trimmed = line.Trim();
            if (trimmed.Length == 0) continue;
            var fields = trimmed.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (fields.Length != 2) continue;
            if (!TryNormalizeIdentifier(fields[0], out var identifier)) continue;
            if (!TryParseRgb(fields[1], out var rgb)) continue;
            result[identifier] = rgb;
        }
        return result;
    }

    private static Dictionary<string, uint> ParseColorsFile(string path)
    {
        try
        {
            return File.Exists(path)
                ? ParseColorsText(File.ReadAllText(path, System.Text.Encoding.UTF8))
                : new Dictionary<string, uint>(StringComparer.Ordinal);
        }
        catch (IOException)
        {
            return new Dictionary<string, uint>(StringComparer.Ordinal);
        }
        catch (UnauthorizedAccessException)
        {
            return new Dictionary<string, uint>(StringComparer.Ordinal);
        }
    }

    private static string? IdentifierFromPngStem(string stem)
    {
        var trimmed = stem.Trim();
        if (trimmed.Length == 0 || trimmed.Contains(':')) return null;
        var underscore = trimmed.IndexOf('_');
        if (underscore <= 0 || underscore >= trimmed.Length - 1) return null;
        var candidate = trimmed[..underscore] + ":" + trimmed[(underscore + 1)..];
        return TryNormalizeIdentifier(candidate, out var identifier) ? identifier : null;
    }

    private static bool TryNormalizeIdentifier(string text, out string identifier)
    {
        identifier = string.Empty;
        var trimmed = Normalize(text);
        var colon = trimmed.IndexOf(':');
        if (colon <= 0 || colon != trimmed.LastIndexOf(':') || colon >= trimmed.Length - 1) return false;
        var ns = trimmed[..colon];
        var path = trimmed[(colon + 1)..];
        if (!ns.All(ch => (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch is '.' or '_' or '-')) return false;
        if (!path.All(ch => (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch is '.' or '_' or '-' or '/')) return false;
        identifier = trimmed;
        return true;
    }

    private static bool TryParseRgb(string text, out uint rgb)
    {
        rgb = 0;
        if (text.Length != 7 || text[0] != '#') return false;
        return uint.TryParse(text.AsSpan(1), System.Globalization.NumberStyles.HexNumber,
            System.Globalization.CultureInfo.InvariantCulture, out rgb);
    }

    private static string Normalize(string identifier) => identifier.Trim().ToLowerInvariant();

    private static uint? AveragePngRgb(string path)
    {
        try
        {
            int sourceWidth;
            int sourceHeight;
            using (var input = File.OpenRead(path))
            {
                var decoder = BitmapDecoder.Create(
                    input, BitmapCreateOptions.DelayCreation | BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.None);
                if (decoder.Frames.Count == 0) return null;
                sourceWidth = decoder.Frames[0].PixelWidth;
                sourceHeight = decoder.Frames[0].PixelHeight;
            }
            if (sourceWidth <= 0 || sourceHeight <= 0) return null;

            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.CreateOptions = BitmapCreateOptions.IgnoreColorProfile;
            if (Math.Max(sourceWidth, sourceHeight) > 64)
            {
                if (sourceWidth >= sourceHeight) image.DecodePixelWidth = 64;
                else image.DecodePixelHeight = 64;
            }
            image.UriSource = new Uri(Path.GetFullPath(path), UriKind.Absolute);
            image.EndInit();
            image.Freeze();

            BitmapSource source = image;
            if (source.PixelWidth <= 0 || source.PixelHeight <= 0) return null;
            var converted = new FormatConvertedBitmap(source, PixelFormats.Pbgra32, null, 0);
            converted.Freeze();
            var stride = converted.PixelWidth * 4;
            var pixels = new byte[stride * converted.PixelHeight];
            converted.CopyPixels(pixels, stride, 0);

            long red = 0, green = 0, blue = 0, alpha = 0;
            for (var offset = 0; offset < pixels.Length; offset += 4)
            {
                blue += pixels[offset];
                green += pixels[offset + 1];
                red += pixels[offset + 2];
                alpha += pixels[offset + 3];
            }
            if (alpha == 0) return null;
            var r = Math.Min(255L, (red * 255 + alpha / 2) / alpha);
            var g = Math.Min(255L, (green * 255 + alpha / 2) / alpha);
            var b = Math.Min(255L, (blue * 255 + alpha / 2) / alpha);
            return (uint)((r << 16) | (g << 8) | b);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or NotSupportedException or ArgumentException or FormatException or System.Runtime.InteropServices.COMException)
        {
            // A malformed optional PNG is ignored independently; valid overrides still load.
            return null;
        }
    }

    private const string ReadMeText = """
MCBEEditor Textures 文件夹说明

此目录用于覆盖地图中方块的默认显示颜色。

1. PNG 覆盖
文件名必须使用：命名空间_方块名.png。
程序只把文件名中的第一个下划线转换为冒号。
例如：
minecraft_bedrock.png -> minecraft:bedrock
minecraft_polished_blackstone.png -> minecraft:polished_blackstone
文件名中直接使用冒号的格式（如 minecraft:bedrock.png）不受支持。
PNG 的可见像素会被计算为一个代表颜色，用于覆盖该方块显示颜色。

2. Colors.txt 覆盖
Colors.txt 每行格式必须为：
minecraft:bedrock #808080
即：完整冒号格式方块 ID + 空格 + #RRGGBB 六位十六进制颜色。
一行只能包含一个条目。空行会忽略，格式错误的行会忽略。
同一方块出现多次时，以最后一个有效条目为准。

3. 优先级
Colors.txt 有效条目 > 对应 PNG > MCBEEditor 内置方块颜色。
如果 Colors.txt 中存在某方块的有效条目，则忽略该方块对应 PNG 的颜色。

修改 PNG 或 Colors.txt 后，在 MCBEEditor 中点击“重新加载纹理”或重新渲染地图即可刷新。

注意：本 ReadMe.txt 由 MCBEEditor 自动生成，并会在程序启动时恢复为默认内容。
""";
}
