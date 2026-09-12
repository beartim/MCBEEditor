using System.IO;
using System.Text;

namespace MCBEEditor.Desktop;

public sealed record SharedCommandFileLine(int LineNumber, string Text);

/// <summary>
/// Portable Windows command-file store. The folder is Commands beside MCBEEditor.exe.
/// ReadMe.txt is rewritten on every launch;
/// Command.txt is user-owned and is never created, modified or deleted.
/// </summary>
public static class SharedCommandFileStore
{
    public static string DirectoryPath => PortablePaths.CommandsPath;

    public static string CommandFilePath => Path.Combine(DirectoryPath, "Command.txt");
    public static string ReadMeFilePath => Path.Combine(DirectoryPath, "ReadMe.txt");
    public static bool CommandFileExists => File.Exists(CommandFilePath);

    public static void PrepareSharedDirectory()
    {
        Directory.CreateDirectory(DirectoryPath);
        File.WriteAllText(ReadMeFilePath, ReadMeText, new UTF8Encoding(false));
    }

    public static IReadOnlyList<SharedCommandFileLine> ReadCommandLines()
    {
        if (!CommandFileExists) return Array.Empty<SharedCommandFileLine>();
        var bytes = File.ReadAllBytes(CommandFilePath);
        string text;
        try
        {
            text = new UTF8Encoding(false, true).GetString(bytes);
        }
        catch (DecoderFallbackException ex)
        {
            throw new InvalidDataException("Commands/Command.txt 必须使用 UTF-8 文本格式。", ex);
        }
        return ParseCommandLines(text);
    }

    public static IReadOnlyList<SharedCommandFileLine> ParseCommandLines(string text)
    {
        if (text.StartsWith('\uFEFF')) text = text[1..];
        var normalized = text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
        var lines = normalized.Split('\n');
        var output = new List<SharedCommandFileLine>();
        for (var i = 0; i < lines.Length; i++)
        {
            var trimmed = lines[i].Trim();
            if (trimmed.Length > 0) output.Add(new SharedCommandFileLine(i + 1, trimmed));
        }
        return output;
    }

    private static string ReadMeText => ReadMeHeader + CommandHelpCatalog.AllUsageText + "\n";

    private const string ReadMeHeader = """
MCBEEditor Commands 文件夹说明

此目录用于在进入存档时批量执行 MCBEEditor 命令。

使用方法：
1. 在本目录中自行创建 Command.txt，文件必须为 UTF-8 文本。
2. Command.txt 每行只能写一条命令；空行会被忽略。
3. 命令与软件“命令”栏目中的输入格式完全相同，不需要也不能添加开头的 / 斜杠。
4. 进入存档时，只要检测到 Command.txt，MCBEEditor 会直接进入“命令”栏目；若其中存在非空命令，会询问是否执行。
5. 用户确认后，程序会先检查全部命令语法。只要任意一行存在语法错误，本次 Command.txt 中所有命令都不会执行。
6. 全部语法检查通过后，命令会从上到下逐行执行，并在“命令”栏目中即时显示每一条命令及其执行结果。
7. 批量命令执行期间不能离开“命令”栏目，也不能关闭当前存档；运行时错误只影响对应命令，后续命令仍会继续执行。
8. MCBEEditor 不会自动创建、修改或删除 Command.txt。

当前支持的全部命令（与本版本 help 输出一致）：

""";
}
