using System.IO.Compression;

namespace MCBEEditor.Core.World;

/// <summary>
/// Creates a disposable writable world copy under the caller-provided cache directory.
/// The original folder/archive is never modified; all editor writes target WorkingRootPath.
/// </summary>
public sealed class PortableWorldWorkspace : IDisposable
{
    private bool _disposed;

    private PortableWorldWorkspace(string sourcePath, string sessionPath, string workingRootPath, bool sourceIsArchive, string archiveWorldPrefix = "")
    {
        SourcePath = sourcePath;
        SessionPath = sessionPath;
        WorkingRootPath = workingRootPath;
        SourceIsArchive = sourceIsArchive;
        ArchiveWorldPrefix = archiveWorldPrefix;
    }

    public string SourcePath { get; }
    public string SessionPath { get; }
    public string WorkingRootPath { get; }
    public bool SourceIsArchive { get; }
    public string ArchiveWorldPrefix { get; }

    public static PortableWorldWorkspace Create(string cacheRoot, string sourcePath)
    {
        if (string.IsNullOrWhiteSpace(cacheRoot)) throw new ArgumentException("缓存目录不能为空。", nameof(cacheRoot));
        if (string.IsNullOrWhiteSpace(sourcePath)) throw new ArgumentException("世界来源不能为空。", nameof(sourcePath));

        var source = Path.GetFullPath(sourcePath);
        var worldsRoot = Path.GetFullPath(cacheRoot);
        // Validate before creating even the cache root; rejected requests must not change the source.
        if (Directory.Exists(source)) RequireSeparateDestination(source, worldsRoot);
        Directory.CreateDirectory(worldsRoot);
        var session = Path.Combine(worldsRoot, Guid.NewGuid().ToString("N"));
        var working = Path.Combine(session, "World");
        Directory.CreateDirectory(session);

        try
        {
            if (Directory.Exists(source))
            {
                ValidateWorld(source);
                CopyDirectory(source, working);
                ValidateWorld(working);
                return new PortableWorldWorkspace(source, session, working, sourceIsArchive: false);
            }

            if (!File.Exists(source)) throw new FileNotFoundException("找不到世界来源。", source);
            var extension = Path.GetExtension(source);
            if (!extension.Equals(".mcworld", StringComparison.OrdinalIgnoreCase)
                && !extension.Equals(".zip", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("只支持 Bedrock 世界文件夹、.mcworld 或 ZIP 世界文件。");

            var staging = Path.Combine(session, "Extracted");
            Directory.CreateDirectory(staging);
            ExtractArchiveSafely(source, staging);
            var root = LocateWorldRoot(staging);
            ValidateWorld(root);
            var relativeRoot = Path.GetRelativePath(staging, root).Replace('\\', '/');
            var archivePrefix = relativeRoot == "." ? "" : relativeRoot + "/";
            if (PathsEqual(root, staging))
            {
                Directory.Move(staging, working);
            }
            else
            {
                Directory.Move(root, working);
                TryDeleteDirectory(staging);
            }
            ValidateWorld(working);
            return new PortableWorldWorkspace(source, session, working, sourceIsArchive: true, archiveWorldPrefix: archivePrefix);
        }
        catch
        {
            TryDeleteDirectory(session);
            throw;
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        TryDeleteDirectory(SessionPath);
    }

    public static string ValidateWorld(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) throw new InvalidDataException("世界目录不能为空。");
        var full = Path.GetFullPath(path);
        if (!File.Exists(Path.Combine(full, "level.dat"))) throw new InvalidDataException("所选世界缺少 level.dat。");
        if (!Directory.Exists(Path.Combine(full, "db"))) throw new InvalidDataException("所选世界缺少 db 文件夹。");
        return full;
    }

    private static string LocateWorldRoot(string staging)
    {
        if (File.Exists(Path.Combine(staging, "level.dat")) && Directory.Exists(Path.Combine(staging, "db"))) return staging;
        var candidates = Directory.EnumerateDirectories(staging, "*", SearchOption.AllDirectories)
            .Where(path => File.Exists(Path.Combine(path, "level.dat")) && Directory.Exists(Path.Combine(path, "db")))
            .OrderBy(path => path.Count(character => character == Path.DirectorySeparatorChar || character == Path.AltDirectorySeparatorChar))
            .ToArray();
        if (candidates.Length == 0) throw new InvalidDataException("压缩包中未找到 Bedrock 世界根目录。");
        var minimumDepth = candidates[0].Count(character => character == Path.DirectorySeparatorChar || character == Path.AltDirectorySeparatorChar);
        var shallowest = candidates.Where(path => path.Count(character => character == Path.DirectorySeparatorChar || character == Path.AltDirectorySeparatorChar) == minimumDepth).ToArray();
        return shallowest.Length == 1 ? shallowest[0] : throw new InvalidDataException("压缩包中找到多个世界根目录，无法确定要编辑的世界。");
    }

    private static void ExtractArchiveSafely(string archivePath, string destination)
    {
        var destinationRoot = Path.GetFullPath(destination).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
        using var archive = ZipFile.OpenRead(archivePath);
        foreach (var entry in archive.Entries)
        {
            var normalizedName = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
            var target = Path.GetFullPath(Path.Combine(destination, normalizedName));
            if (!target.StartsWith(destinationRoot, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("世界压缩包包含越界路径，已拒绝打开。");
            if (string.IsNullOrEmpty(entry.Name))
            {
                Directory.CreateDirectory(target);
                continue;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            entry.ExtractToFile(target, overwrite: true);
        }
    }

    private static void CopyDirectory(string source, string destination)
    {
        RequireSeparateDestination(source, destination);
        var sourceFull = Path.GetFullPath(source);
        var destinationFull = Path.GetFullPath(destination);
        Directory.CreateDirectory(destinationFull);
        var pending = new Stack<string>();
        pending.Push(sourceFull);
        while (pending.Count > 0)
        {
            var directory = pending.Pop();
            if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("世界目录包含符号链接或目录联接，请使用普通世界目录。");
            foreach (var entry in Directory.EnumerateFileSystemEntries(directory))
            {
                var attributes = File.GetAttributes(entry);
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidDataException("世界目录包含符号链接或目录联接，请使用普通世界目录。");
                var relative = Path.GetRelativePath(sourceFull, entry);
                var target = Path.Combine(destinationFull, relative);
                if ((attributes & FileAttributes.Directory) != 0)
                {
                    Directory.CreateDirectory(target);
                    pending.Push(entry);
                    continue;
                }
                if (relative.Replace('\\', '/').Equals("db/LOCK", StringComparison.OrdinalIgnoreCase)) continue;
                File.Copy(entry, target, overwrite: false);
                // Read-only inputs are valid; only the private copy becomes writable.
                if ((attributes & FileAttributes.ReadOnly) != 0)
                    File.SetAttributes(target, File.GetAttributes(target) & ~FileAttributes.ReadOnly);
            }
        }
    }

    private static void RequireSeparateDestination(string source, string destination)
    {
        var sourceRoot = Path.GetFullPath(source).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var target = Path.GetFullPath(destination).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (PathsEqual(destination, source) || target.StartsWith(sourceRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("缓存工作副本不能等于源世界目录或位于源世界目录内部。");
    }

    private static bool PathsEqual(string left, string right)
        => string.Equals(
            Path.GetFullPath(left).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
            Path.GetFullPath(right).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
            StringComparison.OrdinalIgnoreCase);

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (!Directory.Exists(path)) return;
            Directory.Delete(path, recursive: true);
        }
        catch
        {
            // Leave failed cleanup recoverable; callers can report a remaining session directory.
        }
    }
}
