using System.Runtime.InteropServices;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.LevelDB;

/// <summary>
/// Managed owner for the native Mojang LevelDB bridge. The native side
/// registers both Bedrock zlib compression IDs and a decompression allocator,
/// matching the iOS implementation instead of relying on generic LevelDB.
/// </summary>
public sealed class MojangLevelDb : IWorldDatabase
{
    private IntPtr _database;
    private readonly bool _readOnly;

    public MojangLevelDb(string path, bool readOnly = true)
    {
        if (!Directory.Exists(path))
            throw new DirectoryNotFoundException($"LevelDB 目录不存在：{path}");

        _readOnly = readOnly;
        try
        {
            var result = NativeLevelDbMethods.Open(Path.GetFullPath(path), readOnly ? 1 : 0, out _database, out var error);
            ThrowIfFailed(result, error, "打开 LevelDB");
            if (_database == IntPtr.Zero)
                throw new IOException("LevelDB 原生层返回了空数据库句柄");
        }
        catch (DllNotFoundException ex)
        {
            throw new InvalidOperationException(
                "未找到 MCBEEditor.LevelDB.Native.dll。请先运行 Windows\\build.cmd 构建 原生 LevelDB 组件。", ex);
        }
        catch (BadImageFormatException ex)
        {
            throw new InvalidOperationException(
                "MCBEEditor.LevelDB.Native.dll 架构不匹配。Windows 版当前要求 x64。", ex);
        }
    }

    public byte[]? Get(ReadOnlySpan<byte> key)
    {
        EnsureOpen();
        var rawKey = key.ToArray();
        var result = NativeLevelDbMethods.Get(_database, rawKey, (nuint)rawKey.Length, out var pointer, out var length, out var error);
        if (result == 0)
        {
            FreeError(error);
            return null;
        }
        ThrowIfFailed(result < 0 ? result : 0, error, "读取 LevelDB 键");
        try
        {
            return CopyBytes(pointer, length);
        }
        finally
        {
            if (pointer != IntPtr.Zero) NativeLevelDbMethods.Free(pointer);
        }
    }

    public void Put(ReadOnlySpan<byte> key, ReadOnlySpan<byte> value, bool sync = true)
    {
        EnsureWritable();
        var rawKey = key.ToArray();
        var rawValue = value.ToArray();
        var result = NativeLevelDbMethods.Put(
            _database, rawKey, (nuint)rawKey.Length, rawValue, (nuint)rawValue.Length,
            sync ? 1 : 0, out var error);
        ThrowIfFailed(result, error, "写入 LevelDB 键");
    }

    public void Delete(ReadOnlySpan<byte> key, bool sync = true)
    {
        EnsureWritable();
        var rawKey = key.ToArray();
        var result = NativeLevelDbMethods.Delete(_database, rawKey, (nuint)rawKey.Length, sync ? 1 : 0, out var error);
        ThrowIfFailed(result, error, "删除 LevelDB 键");
    }

    public void ApplyBatch(IEnumerable<WorldDatabasePut> puts, IEnumerable<byte[]> deletes, bool sync = true)
    {
        EnsureWritable();
        ArgumentNullException.ThrowIfNull(puts);
        ArgumentNullException.ThrowIfNull(deletes);

        var batch = NativeLevelDbMethods.BatchCreate();
        if (batch == IntPtr.Zero)
            throw new IOException("无法创建 LevelDB WriteBatch");
        try
        {
            // Keep parity with iOS: deletes are queued before puts so an atomic
            // replacement can delete an old value and then write the new one.
            foreach (var key in deletes)
            {
                ArgumentNullException.ThrowIfNull(key);
                var result = NativeLevelDbMethods.BatchDelete(batch, key, (nuint)key.Length, out var error);
                ThrowIfFailed(result, error, "加入批量删除");
            }
            foreach (var put in puts)
            {
                ArgumentNullException.ThrowIfNull(put);
                var result = NativeLevelDbMethods.BatchPut(
                    batch, put.Key, (nuint)put.Key.Length, put.Value, (nuint)put.Value.Length, out var error);
                ThrowIfFailed(result, error, "加入批量写入");
            }
            var writeResult = NativeLevelDbMethods.WriteBatch(_database, batch, sync ? 1 : 0, out var writeError);
            ThrowIfFailed(writeResult, writeError, "提交 LevelDB WriteBatch");
        }
        finally
        {
            NativeLevelDbMethods.BatchDestroy(batch);
        }
    }

    public IEnumerable<WorldDatabaseEntry> Entries(ReadOnlyMemory<byte>? prefix = null, bool includeValues = false, int limit = 0)
    {
        EnsureOpen();
        if (limit < 0) throw new ArgumentOutOfRangeException(nameof(limit));

        var rawPrefix = prefix?.ToArray();
        var iterator = NativeLevelDbMethods.IteratorCreate(
            _database, rawPrefix, (nuint)(rawPrefix?.Length ?? 0), includeValues ? 1 : 0, out var error);
        if (iterator == IntPtr.Zero)
        {
            var message = ConsumeError(error) ?? "无法创建 LevelDB 迭代器";
            throw new IOException(message);
        }

        var output = new List<WorldDatabaseEntry>();
        try
        {
            while (NativeLevelDbMethods.IteratorValid(iterator) != 0 && (limit == 0 || output.Count < limit))
            {
                var keyPointer = NativeLevelDbMethods.IteratorKey(iterator, out var keyLength);
                var key = CopyBytes(keyPointer, keyLength);
                byte[]? value = null;
                if (includeValues)
                {
                    var valuePointer = NativeLevelDbMethods.IteratorValue(iterator, out var valueLength);
                    value = CopyBytes(valuePointer, valueLength);
                }
                output.Add(new WorldDatabaseEntry(key, value));
                NativeLevelDbMethods.IteratorNext(iterator);
            }

            var status = NativeLevelDbMethods.IteratorStatus(iterator, out var statusError);
            ThrowIfFailed(status, statusError, "遍历 LevelDB");
        }
        finally
        {
            NativeLevelDbMethods.IteratorDestroy(iterator);
        }
        return output;
    }

    public void Dispose()
    {
        if (_database == IntPtr.Zero) return;
        NativeLevelDbMethods.Close(_database);
        _database = IntPtr.Zero;
        GC.SuppressFinalize(this);
    }

    ~MojangLevelDb()
    {
        if (_database != IntPtr.Zero)
            NativeLevelDbMethods.Close(_database);
    }

    private void EnsureOpen()
    {
        if (_database == IntPtr.Zero)
            throw new ObjectDisposedException(nameof(MojangLevelDb));
    }

    private void EnsureWritable()
    {
        EnsureOpen();
        if (_readOnly)
            throw new InvalidOperationException("LevelDB 当前以只读模式打开");
    }

    private static byte[] CopyBytes(IntPtr pointer, nuint length)
    {
        if (length == 0) return Array.Empty<byte>();
        if (pointer == IntPtr.Zero) throw new IOException("原生 LevelDB 返回空数据指针");
        if (length > int.MaxValue) throw new IOException("LevelDB 值过大，超过 Windows 版单条记录限制");
        var result = new byte[(int)length];
        Marshal.Copy(pointer, result, 0, result.Length);
        return result;
    }

    private static void ThrowIfFailed(int result, IntPtr error, string operation)
    {
        if (result == 0)
        {
            FreeError(error);
            return;
        }
        var message = ConsumeError(error) ?? $"{operation}失败（native={result}）";
        throw new IOException($"{operation}：{message}");
    }

    private static void FreeError(IntPtr error)
    {
        if (error != IntPtr.Zero) NativeLevelDbMethods.Free(error);
    }

    private static string? ConsumeError(IntPtr error)
    {
        if (error == IntPtr.Zero) return null;
        try { return Marshal.PtrToStringUTF8(error); }
        finally { NativeLevelDbMethods.Free(error); }
    }
}
