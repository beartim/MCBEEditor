using System.Buffers.Binary;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.LevelDB;

namespace MCBEEditor.Core.World;

public sealed record LevelDatFile(uint Version, NbtDocument Document);

public sealed class WorldDocument
{
    private readonly Action? _onMutation;

    public WorldDocument(string rootPath, Action? onMutation = null)
    {
        if (string.IsNullOrWhiteSpace(rootPath))
            throw new ArgumentException("世界目录不能为空", nameof(rootPath));
        RootPath = Path.GetFullPath(rootPath);
        _onMutation = onMutation;
    }

    public string RootPath { get; }
    public string LevelDatPath => Path.Combine(RootPath, "level.dat");
    public string DatabasePath => Path.Combine(RootPath, "db");

    public IWorldDatabase OpenDatabase(bool readOnly = true)
    {
        var database = new MojangLevelDb(DatabasePath, readOnly);
        return readOnly || _onMutation is null ? database : new MutationTrackingWorldDatabase(database, _onMutation);
    }

    public LevelDatFile ReadLevelDat()
    {
        var data = File.ReadAllBytes(LevelDatPath);
        if (data.Length < 8)
            throw new InvalidDataException("level.dat 少于 8 字节");

        var version = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(0, 4));
        var declaredLength = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(4, 4));
        if (declaredLength > int.MaxValue || 8L + declaredLength > data.LongLength)
            throw new InvalidDataException("level.dat 声明长度越界");

        var payload = data.AsSpan(8, (int)declaredLength);
        var document = BedrockNbtCodec.Decode(payload, NbtEncoding.LittleEndian);
        return new LevelDatFile(version, document);
    }

    public void WriteLevelDat(LevelDatFile file)
    {
        var payload = BedrockNbtCodec.Encode(file.Document, NbtEncoding.LittleEndian);
        var output = new byte[checked(8 + payload.Length)];
        BinaryPrimitives.WriteUInt32LittleEndian(output.AsSpan(0, 4), file.Version);
        BinaryPrimitives.WriteUInt32LittleEndian(output.AsSpan(4, 4), checked((uint)payload.Length));
        payload.CopyTo(output.AsSpan(8));
        AtomicFile.WriteAllBytes(LevelDatPath, output);
        _onMutation?.Invoke();
    }

    public static bool LooksLikeBedrockWorld(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path))
            return false;
        return File.Exists(Path.Combine(path, "level.dat"));
    }

    private sealed class MutationTrackingWorldDatabase : IWorldDatabase
    {
        private readonly IWorldDatabase _inner;
        private readonly Action _onMutation;

        public MutationTrackingWorldDatabase(IWorldDatabase inner, Action onMutation)
        {
            _inner = inner;
            _onMutation = onMutation;
        }

        public byte[]? Get(ReadOnlySpan<byte> key) => _inner.Get(key);

        public void Put(ReadOnlySpan<byte> key, ReadOnlySpan<byte> value, bool sync = true)
        {
            _inner.Put(key, value, sync);
            _onMutation();
        }

        public void Delete(ReadOnlySpan<byte> key, bool sync = true)
        {
            _inner.Delete(key, sync);
            _onMutation();
        }

        public void ApplyBatch(IEnumerable<WorldDatabasePut> puts, IEnumerable<byte[]> deletes, bool sync = true)
        {
            var putList = puts.ToArray();
            var deleteList = deletes.ToArray();
            _inner.ApplyBatch(putList, deleteList, sync);
            if (putList.Length > 0 || deleteList.Length > 0) _onMutation();
        }

        public IEnumerable<WorldDatabaseEntry> Entries(ReadOnlyMemory<byte>? prefix = null, bool includeValues = false, int limit = 0)
            => _inner.Entries(prefix, includeValues, limit);

        public void Dispose() => _inner.Dispose();
    }
}

internal static class AtomicFile
{
    public static void WriteAllBytes(string destination, byte[] data)
    {
        var fullDestination = Path.GetFullPath(destination);
        var parent = Path.GetDirectoryName(fullDestination) ?? throw new IOException("目标文件没有父目录");
        Directory.CreateDirectory(parent);
        var temporary = Path.Combine(parent, $".{Path.GetFileName(fullDestination)}.{Guid.NewGuid():N}.tmp");
        File.WriteAllBytes(temporary, data);

        try
        {
            if (File.Exists(fullDestination))
            {
                var backup = temporary + ".bak";
                try
                {
                    File.Replace(temporary, fullDestination, backup, ignoreMetadataErrors: true);
                    if (File.Exists(backup)) File.Delete(backup);
                }
                catch (PlatformNotSupportedException)
                {
                    File.Move(temporary, fullDestination, overwrite: true);
                }
            }
            else
            {
                File.Move(temporary, fullDestination);
            }
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }
}
