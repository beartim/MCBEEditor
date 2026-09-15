using System.Text;

namespace MCBEEditor.Cli;

internal sealed record CliCommandLine(int LineNumber, string Text);

internal static class CliCommandFile
{
    public static IReadOnlyList<CliCommandLine> Read(string path)
    {
        byte[] bytes;
        if (path == "-")
        {
            using var buffer = new MemoryStream();
            Console.OpenStandardInput().CopyTo(buffer);
            bytes = buffer.ToArray();
        }
        else bytes = File.ReadAllBytes(path);

        string text;
        try { text = new UTF8Encoding(false, true).GetString(bytes); }
        catch (DecoderFallbackException error)
        {
            throw new InvalidDataException("命令文件必须使用 UTF-8 文本格式。", error);
        }
        if (text.StartsWith('\uFEFF')) text = text[1..];
        var rows = text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n').Split('\n');
        return rows.Select((row, index) => new CliCommandLine(index + 1, row.Trim()))
            .Where(row => row.Text.Length > 0).ToArray();
    }
}
