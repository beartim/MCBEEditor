using System.IO;

namespace MCBEEditor.Desktop;

/// <summary>
/// All Windows-side editor-owned paths are rooted beside the distributed MCBEEditor.exe.
/// The native launcher sets MCBEEDITOR_PORTABLE_ROOT before starting the managed payload;
/// development builds fall back to AppContext.BaseDirectory.
/// </summary>
internal static class PortablePaths
{
    public static string RootPath
    {
        get
        {
            var configured = Environment.GetEnvironmentVariable("MCBEEDITOR_PORTABLE_ROOT");
            var root = string.IsNullOrWhiteSpace(configured) ? AppContext.BaseDirectory : configured;
            return Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        }
    }

    public static string CachePath => Path.Combine(RootPath, "Cache");
    public static string WorldCachePath => Path.Combine(CachePath, "Worlds");
    public static string ExportCachePath => Path.Combine(CachePath, "Export");
    public static string TexturesPath => Path.Combine(RootPath, "Textures");
    public static string CommandsPath => Path.Combine(RootPath, "Commands");

    public static void PreparePersistentDirectories()
    {
        Directory.CreateDirectory(TexturesPath);
        Directory.CreateDirectory(CommandsPath);
        Directory.CreateDirectory(WorldCachePath);
        Directory.CreateDirectory(ExportCachePath);
        Environment.SetEnvironmentVariable("MCBEEDITOR_CACHE_ROOT", CachePath);
    }
}
