using System.Globalization;
using System.Text;

namespace MCBEEditor.Core.Nbt;

public static class NbtTagPath
{
    public const string Root = "/";

    public static int NextOccurrence(Dictionary<string, int> siblings, string name)
    {
        int occurrence = siblings.GetValueOrDefault(name);
        siblings[name] = occurrence + 1;
        return occurrence;
    }

    public static string AppendName(string parent, string name, int occurrence)
    {
        var path = new StringBuilder(parent);
        if (parent != Root) path.Append('/');
        if (name.Length == 0) path.Append(@"\e");
        foreach (var rune in name.EnumerateRunes())
        {
            switch (rune.Value)
            {
                case '/': case '[': case ']': case '#': case '\\':
                    path.Append('\\').Append((char)rune.Value);
                    break;
                case '\n': path.Append(@"\n"); break;
                case '\r': path.Append(@"\r"); break;
                case '\t': path.Append(@"\t"); break;
                default:
                    if (Rune.GetUnicodeCategory(rune) is UnicodeCategory.Control or UnicodeCategory.Format
                        or UnicodeCategory.LineSeparator or UnicodeCategory.ParagraphSeparator)
                        path.Append(@"\u{").Append(rune.Value.ToString("x", CultureInfo.InvariantCulture)).Append('}');
                    else
                        path.Append(rune.ToString());
                    break;
            }
        }
        if (occurrence > 0) path.Append('#').Append((occurrence + 1).ToString(CultureInfo.InvariantCulture));
        return path.ToString();
    }
}
