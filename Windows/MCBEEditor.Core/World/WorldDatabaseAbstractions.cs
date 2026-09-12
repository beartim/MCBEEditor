namespace MCBEEditor.Core.World;

/// <summary>
/// Database boundary shared by the Windows UI and Bedrock world code. The
/// production implementation uses the Mojang-compatible leveldb-mcpe native
/// bridge; tests can provide an in-memory implementation.
/// </summary>
public interface IWorldDatabase : IDisposable
{
    byte[]? Get(ReadOnlySpan<byte> key);
    void Put(ReadOnlySpan<byte> key, ReadOnlySpan<byte> value, bool sync = true);
    void Delete(ReadOnlySpan<byte> key, bool sync = true);
    void ApplyBatch(IEnumerable<WorldDatabasePut> puts, IEnumerable<byte[]> deletes, bool sync = true);
    IEnumerable<WorldDatabaseEntry> Entries(ReadOnlyMemory<byte>? prefix = null, bool includeValues = false, int limit = 0);
}

public sealed record WorldDatabaseEntry(byte[] Key, byte[]? Value);
public sealed record WorldDatabasePut(byte[] Key, byte[] Value);
