using System.IO.Compression;

namespace MCBEEditor.Cli;

internal static class CliInPlaceArchive
{
    public static void Write(string original, string worldRoot, string prefix, string destination)
    {
        using var source = ZipFile.OpenRead(original);
        using var stream = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        using var target = new ZipArchive(stream, ZipArchiveMode.Create);
        var worldName = NormalizeEntryName(prefix);
        // Keep the original container layout and all entries outside the chosen world.
        foreach (var entry in source.Entries)
        {
            var normalized = NormalizeEntryName(entry.FullName);
            if (worldName.Length == 0 || normalized.Equals(worldName, StringComparison.OrdinalIgnoreCase)
                || normalized.StartsWith(worldName + "/", StringComparison.OrdinalIgnoreCase)) continue;
            var copy = target.CreateEntry(entry.FullName, CompressionLevel.Optimal);
            copy.LastWriteTime = entry.LastWriteTime;
            copy.ExternalAttributes = entry.ExternalAttributes;
            using var input = entry.Open();
            using var output = copy.Open();
            input.CopyTo(output);
        }
        foreach (var path in Directory.EnumerateFileSystemEntries(worldRoot, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(worldRoot, path).Replace('\\', '/');
            if (relative.Equals("db/LOCK", StringComparison.OrdinalIgnoreCase)) continue;
            if (Directory.Exists(path)) target.CreateEntry(prefix + relative + "/");
            else target.CreateEntryFromFile(path, prefix + relative, CompressionLevel.Optimal);
        }
    }

    private static string NormalizeEntryName(string name)
    {
        // Extraction already validated containment using Path.GetFullPath. Match the
        // resulting path here too, so ./World/file and World/file are replaced together.
        // Unrelated entries retain their original names when copied to the new archive.
        var components = new List<string>();
        foreach (var component in name.Replace('\\', '/').Split('/', StringSplitOptions.RemoveEmptyEntries))
        {
            if (component == ".") continue;
            if (component == "..")
            {
                if (components.Count == 0) throw new InvalidDataException("世界压缩包包含越界路径，已拒绝原位更新。");
                components.RemoveAt(components.Count - 1);
            }
            else components.Add(component);
        }
        return string.Join("/", components);
    }
}
