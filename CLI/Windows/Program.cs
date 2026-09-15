using System.Text;
using MCBEEditor.Desktop;

namespace MCBEEditor.Cli;

internal static class Program
{
    private const string Version = "MCBEEditor CLI 0.6.0-stage06";
    private const string Usage = """
MCBEEditor CLI 0.6.0-stage06
Windows 命令执行、原位更新、另存为与 NBT/mcstructure 格式转换。

mcbe-cli --help [命令]
mcbe-cli --list-commands
mcbe-cli --version
mcbe-cli --interactive
mcbe-cli --convert 输入 --to 格式 --output 输出 [--overwrite]
mcbe-cli --check "完整命令"
mcbe-cli --check-file 路径
mcbe-cli --check-file -
mcbe-cli --world 路径 --command "完整命令" [--command "下一条命令"]
mcbe-cli --world 路径 --script 命令文件

存档执行选项：
--in-place             全部成功后原位更新输入文件夹或 mcworld。
--output 路径.mcworld  另存为；与 --in-place 互斥。修改必须选择其一。
--overwrite            允许替换已存在的输出文件，仍不允许覆盖输入。
--cache-dir 路径       工作副本目录，默认程序旁 Cache/Worlds。
--keep-work            执行成功后也保留工作副本。

--check-file 接受 UTF-8（可带 BOM），忽略空行并报告原始行号。
使用 - 从标准输入读取；会检查全部非空行，不执行命令。
预检只检查语法，不检查存档中的目标是否存在或能否执行。
--script 也支持 -。执行前整批预检，运行时出错后继续后续命令。
先在工作副本执行；原位模式仅全部成功后提交，失败保留副本。
structure import/export 使用 --file 路径；持续会话使用 --interactive。
独立 NBT/mcstructure 格式转换不需要 --world，也不会编辑 NBT 内容。
退出码：0 成功；1 执行失败；2 参数或预检错误；3 文件或编码错误；130 取消。
""";

    public static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        using var cancellation = new CancellationTokenSource();
        ConsoleCancelEventHandler handler = (_, e) => { e.Cancel = true; cancellation.Cancel(); };
        Console.CancelKeyPress += handler;
        try {
            CliSharedCommandStore.PrepareDefault(Console.Error);
            return Run(args, Console.Out, Console.Error, cancellation.Token, Console.In, terminalFeatures: true);
        }
        finally { Console.CancelKeyPress -= handler; }
    }

    internal static int Run(string[] args, TextWriter output, TextWriter error, CancellationToken cancellationToken = default, TextReader? input = null,
        bool terminalFeatures = false, string? commandsDirectory = null)
    {
        try
        {
            if (args.Length == 0) { output.WriteLine(Usage); return 0; }
            switch (args[0])
            {
                case "--help" when args.Length == 1:
                    output.WriteLine(Usage);
                    output.WriteLine();
                    output.WriteLine(CommandHelpCatalog.AllUsageText);
                    return 0;
                case "--help" when args.Length == 2:
                    if (args[1].Equals("convert", StringComparison.OrdinalIgnoreCase))
                    {
                        output.WriteLine(CliFormatConverter.Usage);
                        return 0;
                    }
                    if (CommandHelpCatalog.TryGetUsage(args[1], out var usage))
                    {
                        output.WriteLine(usage);
                        if (args[1].Equals("structure", StringComparison.OrdinalIgnoreCase))
                            output.WriteLine("\nCLI 文件接口：\n" + CliStructureFileCommand.Usage);
                        return 0;
                    }
                    error.WriteLine($"不存在的命令：{args[1]}");
                    return 2;
                case "--list-commands" when args.Length == 1:
                    output.WriteLine(string.Join("\n", CommandHelpCatalog.Names));
                    return 0;
                case "--version" when args.Length == 1:
                    output.WriteLine(Version);
                    return 0;
                case "--interactive" when args.Length == 1:
                    return CliInteractiveShell.Run(input ?? Console.In, output, error, cancellationToken, terminalFeatures, commandsDirectory);
                case "--check" when args.Length == 2:
                    return Check([new CliCommandLine(1, args[1])], output, error);
                case "--check-file" when args.Length == 2:
                    return Check(CliCommandFile.Read(args[1]), output, error);
                case "--convert":
                    return CliFormatConverter.Run(args, output);
                case "--world" or "--command" or "--script" or "--output" or "--cache-dir" or "--overwrite" or "--keep-work" or "--in-place":
                    return CliWorldRunner.Run(CliRunOptions.Parse(args), output, error, cancellationToken);
                default:
                    error.WriteLine("CLI 参数格式错误。\n" + Usage);
                    return 2;
            }
        }
        catch (CliInputException exception)
        {
            error.WriteLine(exception.Message);
            return 2;
        }
        catch (OperationCanceledException)
        {
            error.WriteLine("已取消。");
            return 130;
        }
        catch (Exception exception) when (exception is IOException or InvalidDataException or UnauthorizedAccessException or ArgumentException)
        {
            error.WriteLine(exception.Message);
            return 3;
        }
        catch (Exception exception)
        {
            error.WriteLine(exception.Message);
            return 1;
        }
    }

    private static int Check(IReadOnlyList<CliCommandLine> lines, TextWriter output, TextWriter error)
    {
        var plan = CliCommandPlan.Parse(lines, error, forExecution: false);
        if (plan is null) return 2;
        output.WriteLine($"语法预检通过：{lines.Count} 条命令，未执行任何命令。");
        return 0;
    }
}
