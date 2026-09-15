using System.Security.Cryptography;
using System.Text;

namespace MCBEEditor.Cli;

// Detect source changes between import and an explicitly requested writeback.
internal static class CliSourceStamp
{
    public static string Capture(string path)
    {
        CliWorldPaths.RequireRegularPath(path);
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        if (File.Exists(path))
        {
            using var file = File.OpenRead(path);
            return Convert.ToHexString(SHA256.HashData(file));
        }
        if (!Directory.Exists(path)) throw new IOException("原位更新来源已不存在。");
        var pending = new Stack<string>();
        pending.Push(path);
        var entries = new List<string>();
        while (pending.Count > 0)
            foreach (var entry in Directory.EnumerateFileSystemEntries(pending.Pop()))
            {
                if ((File.GetAttributes(entry) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("原位更新来源包含链接。");
                entries.Add(entry);
                if (Directory.Exists(entry)) pending.Push(entry);
            }
        foreach (var entry in entries.OrderBy(p => Path.GetRelativePath(path, p), StringComparer.Ordinal))
        {
            bool directory = Directory.Exists(entry);
            var name = Encoding.UTF8.GetBytes((directory ? "D:" : "F:") + Path.GetRelativePath(path, entry).Replace('\\', '/') + "\0");
            hash.AppendData(name);
            if (!directory)
            {
                using var file = File.OpenRead(entry);
                hash.AppendData(SHA256.HashData(file));
            }
        }
        return Convert.ToHexString(hash.GetHashAndReset());
    }
}
