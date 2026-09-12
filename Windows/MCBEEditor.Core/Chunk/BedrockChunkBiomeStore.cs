using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public sealed record BedrockChunkBiomeRecord(
    ChunkPosition Position,
    byte[] Key,
    ChunkRecordType RecordType,
    BedrockBiomeDocument Document,
    int RawValueSize)
{
    public string FormatText => Document.Format.ToString();
}

/// <summary>Structured single-chunk biome editor backend matching the iOS ChunkBiomeEditor.</summary>
public sealed class BedrockChunkBiomeStore
{
    private readonly IWorldDatabase _database;
    public BedrockChunkBiomeStore(IWorldDatabase database) => _database = database ?? throw new ArgumentNullException(nameof(database));

    public BedrockChunkBiomeRecord? Read(ChunkPosition position)
    {
        (byte[] Key, ChunkRecordType Type, byte[] Value)? fallback = null;
        foreach (var entry in _database.Entries(BedrockChunkStore.CoordinatePrefix(position.X, position.Z), includeValues: true))
        {
            if (entry.Value is null || !BedrockDbKey.TryParse(entry.Key, out var parsed) || parsed.Position != position) continue;
            if (parsed.RecordType is not (ChunkRecordType.Data3D or ChunkRecordType.Data2D or ChunkRecordType.Data2DLegacy)) continue;
            var current = (entry.Key.ToArray(), parsed.RecordType, entry.Value.ToArray());
            if (parsed.RecordType == ChunkRecordType.Data3D)
                return new BedrockChunkBiomeRecord(position, current.Item1, current.Item2, BedrockBiomeDocument.Decode(current.Item2, current.Item3), current.Item3.Length);
            if (fallback is null || parsed.RecordType == ChunkRecordType.Data2D) fallback = current;
        }
        if (fallback is null) return null;
        var value = fallback.Value;
        return new BedrockChunkBiomeRecord(position, value.Key, value.Type, BedrockBiomeDocument.Decode(value.Type, value.Value), value.Value.Length);
    }

    public int Save(BedrockChunkBiomeRecord record)
    {
        if (record.Document.Format != BedrockBiomeFormat.Data3D)
        {
            foreach (var layer in record.Document.Layers)
                if (layer.BiomeIds.Any(id => id > byte.MaxValue))
                    throw new InvalidDataException("Data2D/Data2DLegacy 生物群系 ID 必须为 0～255。");
        }
        var encoded = record.Document.Encode();
        _database.Put(record.Key, encoded, sync: true);
        return encoded.Length;
    }
}
