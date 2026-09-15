using System.Text;

namespace MCBEEditor.Cli;

internal sealed class CliTerminal
{
    private readonly TextReader _input;
    private readonly TextWriter _output;
    private readonly TextWriter _error;
    private readonly bool _interactiveKeys;
    public bool UseAnsi { get; }
    private readonly bool _useAnsiError;

    public CliTerminal(TextReader input, TextWriter output, TextWriter error, bool terminalFeatures)
    {
        _input = input;
        _output = output;
        _error = error;
        _interactiveKeys = terminalFeatures && !Console.IsInputRedirected && !Console.IsOutputRedirected
            && ReferenceEquals(input, Console.In) && ReferenceEquals(output, Console.Out);
        UseAnsi = terminalFeatures && !Console.IsOutputRedirected && ReferenceEquals(output, Console.Out);
        _useAnsiError = terminalFeatures && !Console.IsErrorRedirected && ReferenceEquals(error, Console.Error);
    }

    public string? ReadLine(string prompt, IReadOnlyList<string> history)
    {
        if (!_interactiveKeys)
        {
            _output.Write(prompt);
            _output.Flush();
            return _input.ReadLine();
        }
        return ReadConsoleLine(prompt, history);
    }

    public void WriteLine(string text) => _output.WriteLine(text);

    public void WriteLine(CliOutputLine line)
    {
        if (!UseAnsi) { _output.WriteLine(line.Text); return; }
        _output.WriteLine(Color(line.Kind) + line.Text + "\u001b[0m");
    }

    public void WriteError(string text)
    {
        if (!_useAnsiError) { _error.WriteLine(text); return; }
        _error.WriteLine("\u001b[31m" + text + "\u001b[0m");
    }

    public void Clear()
    {
        if (!UseAnsi) return;
        _output.Write("\u001b[2J\u001b[H");
        _output.Flush();
    }

    private string? ReadConsoleLine(string prompt, IReadOnlyList<string> history)
    {
        _output.Write(prompt);
        _output.Flush();
        var buffer = new StringBuilder();
        var cursor = 0;
        var historyIndex = history.Count;
        var draft = string.Empty;
        while (true)
        {
            var key = Console.ReadKey(intercept: true);
            if (key.Key == ConsoleKey.Enter)
            {
                _output.WriteLine();
                return buffer.ToString();
            }
            if (key.Key == ConsoleKey.D && key.Modifiers.HasFlag(ConsoleModifiers.Control) && buffer.Length == 0)
            {
                _output.WriteLine();
                return null;
            }
            switch (key.Key)
            {
                case ConsoleKey.UpArrow:
                    MoveHistoryArrowUp(history, ref historyIndex, ref draft, buffer, ref cursor);
                    Redraw(prompt, buffer, cursor);
                    break;
                case ConsoleKey.DownArrow:
                    MoveHistoryArrowDown(history, ref historyIndex, draft, buffer, ref cursor);
                    Redraw(prompt, buffer, cursor);
                    break;
                case ConsoleKey.LeftArrow:
                    if (cursor > 0) { cursor--; Redraw(prompt, buffer, cursor); }
                    break;
                case ConsoleKey.RightArrow:
                    if (cursor < buffer.Length) { cursor++; Redraw(prompt, buffer, cursor); }
                    break;
                case ConsoleKey.Home:
                    cursor = 0; Redraw(prompt, buffer, cursor); break;
                case ConsoleKey.End:
                    cursor = buffer.Length; Redraw(prompt, buffer, cursor); break;
                case ConsoleKey.Backspace:
                    if (cursor > 0) { buffer.Remove(cursor - 1, 1); cursor--; historyIndex = history.Count; Redraw(prompt, buffer, cursor); }
                    break;
                case ConsoleKey.Delete:
                    if (cursor < buffer.Length) { buffer.Remove(cursor, 1); historyIndex = history.Count; Redraw(prompt, buffer, cursor); }
                    break;
                default:
                    if (!char.IsControl(key.KeyChar))
                    {
                        buffer.Insert(cursor, key.KeyChar);
                        cursor++;
                        historyIndex = history.Count;
                        Redraw(prompt, buffer, cursor);
                    }
                    break;
            }
        }
    }

    private static void MoveHistoryArrowUp(IReadOnlyList<string> history, ref int index, ref string draft,
        StringBuilder buffer, ref int cursor)
    {
        if (history.Count == 0) return;
        if (index >= history.Count) { draft = buffer.ToString(); index = history.Count - 1; }
        else if (index > 0) index--;
        Replace(buffer, history[index], ref cursor);
    }

    private static void MoveHistoryArrowDown(IReadOnlyList<string> history, ref int index, string draft,
        StringBuilder buffer, ref int cursor)
    {
        if (history.Count == 0 || index >= history.Count) return;
        if (index < history.Count - 1) { index++; Replace(buffer, history[index], ref cursor); }
        else { index = history.Count; Replace(buffer, draft, ref cursor); }
    }

    private static void Replace(StringBuilder buffer, string value, ref int cursor)
    {
        buffer.Clear(); buffer.Append(value); cursor = buffer.Length;
    }

    private void Redraw(string prompt, StringBuilder buffer, int cursor)
    {
        if (UseAnsi)
        {
            _output.Write("\r\u001b[2K" + prompt + buffer);
            var tail = buffer.Length - cursor;
            if (tail > 0) _output.Write($"\u001b[{tail}D");
            _output.Flush();
            return;
        }
        // Interactive key mode is only enabled for a real console. The fallback
        // exists for terminals where ANSI was explicitly disabled.
        _output.Write("\r" + prompt + buffer + " ");
        _output.Flush();
    }

    private static string Color(CliOutputKind kind) => kind switch
    {
        CliOutputKind.LocalPlayer => "\u001b[33m",
        CliOutputKind.OnlinePlayer => "\u001b[34m",
        CliOutputKind.Entity => "\u001b[36m",
        CliOutputKind.Block => "\u001b[34m",
        CliOutputKind.BlockEntity => "\u001b[35m",
        CliOutputKind.Chunk => "\u001b[34m",
        _ => "\u001b[32m"
    };
}
