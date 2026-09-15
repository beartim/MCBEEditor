using MCBEEditor.Core.World;

namespace MCBEEditor.Cli;

internal sealed class CliWorldSession : IDisposable
{
    private readonly PortableWorldWorkspace _workspace;
    private bool _preserve = true;
    private bool _disposed;
    private string? _sourceStamp;
    public WorldDocument Document { get; }
    public string WorkingRoot => _workspace.WorkingRootPath;
    public bool HasChanges { get; private set; }

    private CliWorldSession(PortableWorldWorkspace workspace)
    {
        _workspace = workspace;
        Document = new WorldDocument(workspace.WorkingRootPath, () => HasChanges = true);
    }

    public static CliWorldSession Open(CliWorldPaths paths, bool inPlace = false)
    {
        var stamp = inPlace ? CliSourceStamp.Capture(paths.Source) : null;
        var workspace = PortableWorldWorkspace.Create(paths.Cache, paths.Source);
        try
        {
            var session = new CliWorldSession(workspace);
            _ = session.Document.ReadLevelDat();
            session._sourceStamp = stamp;
            if (inPlace) session.RequireUnchangedSource();
            return session;
        }
        catch
        {
            // No command has run yet. An invalid input does not leave a disposable copy behind.
            workspace.Dispose();
            throw;
        }
    }

    public void Export(string destination, bool overwrite)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        CliWorldPaths.RequireRegularPath(destination);
        if (CliWorldPaths.SameOrInside(destination, WorkingRoot))
            throw new InvalidOperationException("不能导出到工作副本内部。");
        var parent = Path.GetDirectoryName(destination) ?? throw new IOException("导出路径缺少父目录。");
        Directory.CreateDirectory(parent);
        var staging = Path.Combine(parent, $".mcbe-cli-{Guid.NewGuid():N}.mcworld");
        try
        {
            // The shared archive writer completes the ZIP before our final no-clobber/overwrite move.
            WorldArchiveService.ExportMcworld(Document, staging, temporaryDirectory: parent);
            File.Move(staging, destination, overwrite);
            HasChanges = false;
        }
        finally
        {
            if (File.Exists(staging)) File.Delete(staging);
        }
    }

    public void Complete(bool keepWork) => _preserve = keepWork || HasChanges;
    public void DiscardWork() { _preserve = false; HasChanges = false; }

    public void CommitInPlace(Action<string> notice)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_sourceStamp is null) throw new InvalidOperationException("当前会话未选择原位更新。");
        var source = _workspace.SourcePath;
        var parent = Path.GetDirectoryName(source)!;
        if (_workspace.SourceIsArchive)
        {
            var staging = Path.Combine(parent, $".mcbe-cli-{Guid.NewGuid():N}.mcworld");
            try
            {
                CliInPlaceArchive.Write(source, WorkingRoot, _workspace.ArchiveWorldPrefix, staging);
                RequireUnchangedSource();
                // Same-directory replacement: the original remains until the archive is complete.
                File.Move(staging, source, overwrite: true);
            }
            finally { if (File.Exists(staging)) File.Delete(staging); }
        }
        else
        {
            using var staged = PortableWorldWorkspace.Create(parent, WorkingRoot);
            RequireUnchangedSource();
            var backup = Path.Combine(parent, $".mcbe-cli-original-{Guid.NewGuid():N}");
            notice($"原位替换前的恢复目录：{backup}");
            Directory.Move(source, backup);
            try { Directory.Move(staged.WorkingRootPath, source); }
            catch (Exception publishError)
            {
                try { Directory.Move(backup, source); }
                catch (Exception rollbackError)
                {
                    throw new IOException($"原位提交及回滚失败；原世界保留在 {backup}；提交：{publishError.Message}；回滚：{rollbackError.Message}", rollbackError);
                }
                throw;
            }
            try { Directory.Delete(backup, recursive: true); }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            { notice($"原位更新已完成；旧世界清理失败，仍保留在 {backup}：{exception.Message}"); }
        }
        HasChanges = false;
        _sourceStamp = CliSourceStamp.Capture(_workspace.SourcePath);
    }

    private void RequireUnchangedSource()
    {
        if (_sourceStamp != CliSourceStamp.Capture(_workspace.SourcePath))
            throw new IOException("原存档在本次处理期间发生变化，已拒绝原位提交；可从保留的工作副本另存为。");
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        // On any failure the copy stays available. The CLI has no GUI launcher to recover it.
        if (!_preserve) _workspace.Dispose();
    }
}
