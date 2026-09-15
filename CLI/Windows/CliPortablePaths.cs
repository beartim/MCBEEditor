namespace MCBEEditor.Cli;

/// <summary>
/// Resolves user-visible CLI directories independently from the managed payload location.
/// The stage05a native launcher extracts the self-contained payload below Cache and sets
/// these variables so Commands and world workspaces remain beside the outer mcbe-cli.exe.
/// </summary>
internal static class CliPortablePaths
{
    public static string RootDirectory => Resolve("MCBEEDITOR_PORTABLE_ROOT", AppContext.BaseDirectory);

    public static string CacheDirectory => Resolve(
        "MCBEEDITOR_CACHE_ROOT",
        Path.Combine(RootDirectory, "Cache"));

    public static string WorldCacheDirectory => Path.Combine(CacheDirectory, "Worlds");

    public static string CommandsDirectory => Path.Combine(RootDirectory, "Commands");

    private static string Resolve(string variable, string fallback)
    {
        var configured = Environment.GetEnvironmentVariable(variable);
        return Path.GetFullPath(string.IsNullOrWhiteSpace(configured) ? fallback : configured);
    }
}
