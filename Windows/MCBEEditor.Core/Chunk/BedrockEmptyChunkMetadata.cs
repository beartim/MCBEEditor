using System.Buffers.Binary;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public sealed record BedrockEmptyChunkProfile(
    ChunkRecordType VersionRecordType,
    byte[] VersionValue,
    bool UsesLegacyTerrain,
    ChunkRecordType? TerrainRecordType,
    byte[]? TerrainValue)
{
    public static BedrockEmptyChunkProfile ModernDefault { get; } =
        new(ChunkRecordType.Version, [40], false, null, null);
}

public sealed record BedrockEmptyChunkRecord(byte[] Key, byte[] Value, ChunkRecordType RecordType);

public sealed record BedrockBlockFormat(byte SubChunkVersion, int BlockPaletteVersion, BedrockPaletteFormat? PaletteFormat = null)
{
    public bool IsLegacyNumeric => SubChunkVersion is 0 or 2 or 3 or 4 or 5 or 6 or 7;
    public BedrockBlockState Air => IsLegacyNumeric
        ? new BedrockBlockState(null, 0, 0)
        : (PaletteFormat ?? new BedrockPaletteFormat(false, BlockPaletteVersion)).Air;
}

/// <summary>
/// Selects the minimal generated-air metadata family already used by the world.
/// This mirrors the iOS BedrockEmptyChunk behavior needed by chunk empty.
/// </summary>
public static class BedrockEmptyChunkMetadata
{
    /// <summary>
    /// LegacyVersion describes chunk metadata, not the block encoding: it is
    /// also used with paletted v1/v8. Prefer actual records in the target chunk,
    /// then the same dimension, before using a default for a truly empty world.
    /// </summary>
    public static BedrockBlockFormat DetectBlockFormat(
        IWorldDatabase database, int? dimension, ChunkPosition? position = null,
        BedrockBlockFormat? fallback = null)
    {
        var counts = new Dictionary<byte, int>();
        int? paletteVersion = null;
        BedrockPaletteFormat? paletteFormat = null;
        var legacyTerrainCount = 0;
        var hasLegacyVersion = false;
        var hasModernVersion = false;
        var prefix = position is { } target ? BedrockChunkStore.CoordinatePrefix(target.X, target.Z) : null;
        foreach (var entry in database.Entries(prefix, includeValues: true))
        {
            if (entry.Value is not { } raw || !BedrockDbKey.TryParse(entry.Key, out var key)
                || (dimension.HasValue && key.Position.Dimension != dimension) || (position.HasValue && key.Position != position.Value)) continue;
            if (key.RecordType == ChunkRecordType.LegacyTerrain) legacyTerrainCount++;
            if (key.RecordType == ChunkRecordType.LegacyVersion) hasLegacyVersion = true;
            if (key.RecordType == ChunkRecordType.Version) hasModernVersion = true;
            if (key.RecordType != ChunkRecordType.SubChunk || key.SubChunkIndex is not sbyte y) continue;
            try
            {
                var decoded = BedrockSubChunk.Decode(raw, y);
                if (decoded.IsRawPreservedUnknownVersion) continue;
                counts[decoded.Version] = counts.GetValueOrDefault(decoded.Version) + 1;
                var observed = BedrockPaletteFormat.Detect(decoded.Storages
                    .Where(storage => storage.PersistentKind == SubChunkStoragePersistentKind.Normal).SelectMany(storage => storage.Palette));
                if (observed is not null && (paletteFormat is null || (paletteFormat.UsesLegacyVal && !observed.UsesLegacyVal)
                    || (paletteFormat.UsesLegacyVal == observed.UsesLegacyVal && (observed.Version ?? int.MinValue) > (paletteFormat.Version ?? int.MinValue))))
                    paletteFormat = observed;
                foreach (var storage in decoded.Storages.Where(storage => storage.PersistentKind == SubChunkStoragePersistentKind.Normal))
                foreach (var state in storage.Palette)
                    if (state.PaletteVersion is int version && (!paletteVersion.HasValue || version > paletteVersion.Value))
                        paletteVersion = version;
            }
            catch (Exception ex) when (ex is InvalidDataException or NotSupportedException or EndOfStreamException)
            {
                // A damaged or future record is not evidence of a writable format.
            }
        }
        var usesLegacyTerrain = legacyTerrainCount > 0 && !hasModernVersion
            && legacyTerrainCount * 8 >= counts.Values.Sum();
        if (position.HasValue && (counts.Count == 0 || (paletteFormat is null && !paletteVersion.HasValue)) && fallback is null)
            fallback = DetectBlockFormat(database, dimension);
        if (!position.HasValue && dimension.HasValue && counts.Count == 0 && legacyTerrainCount == 0
            && !hasLegacyVersion && !hasModernVersion)
            return DetectBlockFormat(database, null);
        var versionFallback = fallback?.SubChunkVersion ?? (hasLegacyVersion && !hasModernVersion ? (byte)7 : (byte)9);
        var selectedVersion = usesLegacyTerrain ? (byte)0 : counts.Count == 0 ? versionFallback
            : counts.OrderByDescending(pair => pair.Value).ThenByDescending(pair => pair.Key).First().Key;
        return new BedrockBlockFormat(selectedVersion, paletteVersion ?? fallback?.BlockPaletteVersion ?? BedrockBlockState.DefaultPaletteVersion,
            paletteFormat ?? fallback?.PaletteFormat);
    }

    public static BedrockEmptyChunkProfile DetectProfile(
        IWorldDatabase database,
        int? dimension,
        bool preferLegacy = false)
    {
        ArgumentNullException.ThrowIfNull(database);

        byte[]? legacyVersion = null;
        byte[]? modernVersion = null;
        byte[]? data3D = null;
        byte[]? data2D = null;
        byte[]? data2DLegacy = null;
        var legacyTerrainCount = 0;
        var subChunkRecordCount = 0;

        foreach (var entry in database.Entries(includeValues: true))
        {
            if (!BedrockDbKey.TryParse(entry.Key, out var key) || (dimension.HasValue && key.Position.Dimension != dimension))
                continue;

            var value = entry.Value;
            if (value is { Length: 1 })
            {
                if (key.RecordType == ChunkRecordType.Version && modernVersion is null) modernVersion = value.ToArray();
                if (key.RecordType == ChunkRecordType.LegacyVersion && legacyVersion is null) legacyVersion = value.ToArray();
            }

            if (value is not null)
            {
                if (key.RecordType == ChunkRecordType.Data3D && data3D is null) data3D = value.ToArray();
                if (key.RecordType == ChunkRecordType.Data2D && data2D is null) data2D = value.ToArray();
                if (key.RecordType == ChunkRecordType.Data2DLegacy && data2DLegacy is null) data2DLegacy = value.ToArray();
            }

            if (key.RecordType == ChunkRecordType.LegacyTerrain) legacyTerrainCount++;
            if (key.RecordType == ChunkRecordType.SubChunk) subChunkRecordCount++;
        }

        if (dimension.HasValue && legacyVersion is null && modernVersion is null && legacyTerrainCount == 0 && subChunkRecordCount == 0)
            return DetectProfile(database, null, preferLegacy);

        // PE 0.9/0.10 worlds use LegacyTerrain without modern Version/SubChunk records.
        // Detect the persisted Bedrock format directly; do not repair editor-created hybrids.
        var usesLegacyTerrain = legacyTerrainCount > 0
            && modernVersion is null
            && subChunkRecordCount == 0;
        if (usesLegacyTerrain)
            return new BedrockEmptyChunkProfile(
                ChunkRecordType.LegacyVersion,
                legacyVersion?.ToArray() ?? [0],
                true,
                null,
                null);

        var legacyTerrainFamily = data2D is not null
            ? (Type: (ChunkRecordType?)ChunkRecordType.Data2D, Value: data2D)
            : data2DLegacy is not null
                ? (Type: (ChunkRecordType?)ChunkRecordType.Data2DLegacy, Value: data2DLegacy)
                : (Type: (ChunkRecordType?)null, Value: (byte[]?)null);

        if (preferLegacy && legacyVersion is not null)
            return new BedrockEmptyChunkProfile(
                ChunkRecordType.LegacyVersion,
                legacyVersion.ToArray(),
                false,
                legacyTerrainFamily.Type,
                legacyTerrainFamily.Value?.ToArray());

        if (modernVersion is not null)
            return new BedrockEmptyChunkProfile(
                ChunkRecordType.Version,
                modernVersion.ToArray(),
                false,
                data3D is null ? legacyTerrainFamily.Type : ChunkRecordType.Data3D,
                data3D?.ToArray() ?? legacyTerrainFamily.Value?.ToArray());

        if (legacyVersion is not null)
            return new BedrockEmptyChunkProfile(
                ChunkRecordType.LegacyVersion,
                legacyVersion.ToArray(),
                false,
                legacyTerrainFamily.Type,
                legacyTerrainFamily.Value?.ToArray());

        return new BedrockEmptyChunkProfile(
            ChunkRecordType.Version,
            [40],
            false,
            data3D is null ? null : ChunkRecordType.Data3D,
            data3D?.ToArray());
    }

    public static IReadOnlyList<BedrockEmptyChunkRecord> Records(
        ChunkPosition position,
        BedrockEmptyChunkProfile profile)
    {
        if (profile.UsesLegacyTerrain)
        {
            return [new BedrockEmptyChunkRecord(
                new BedrockDbKey(position, ChunkRecordType.LegacyTerrain, null).Encode(),
                BedrockLegacyTerrain.EmptyPersistentData,
                ChunkRecordType.LegacyTerrain)];
        }

        var finalized = new byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(finalized, 2);
        var records = new List<BedrockEmptyChunkRecord>
        {
            new(
                new BedrockDbKey(position, profile.VersionRecordType, null).Encode(),
                profile.VersionValue.ToArray(),
                profile.VersionRecordType),
            new(
                new BedrockDbKey(position, ChunkRecordType.FinalizedState, null).Encode(),
                finalized,
                ChunkRecordType.FinalizedState)
        };

        if (profile.TerrainRecordType is { } terrainType && profile.TerrainValue is { } terrainValue)
            records.Add(new BedrockEmptyChunkRecord(
                new BedrockDbKey(position, terrainType, null).Encode(),
                terrainValue.ToArray(),
                terrainType));

        return records;
    }

    public static IReadOnlyList<WorldDatabasePut> MissingRecords(IWorldDatabase database, ChunkPosition position, BedrockEmptyChunkProfile? metadataProfile = null)
    {
        byte[] Key(ChunkRecordType type) => new BedrockDbKey(position, type, null).Encode();
        if (database.Get(Key(ChunkRecordType.LegacyTerrain)) is not null) return [];
        var hasVersion = database.Get(Key(ChunkRecordType.Version)) is not null
            || database.Get(Key(ChunkRecordType.LegacyVersion)) is not null;
        var hasFinalized = database.Get(Key(ChunkRecordType.FinalizedState)) is not null;
        var hasBiome = database.Get(Key(ChunkRecordType.Data3D)) is not null
            || database.Get(Key(ChunkRecordType.Data2D)) is not null
            || database.Get(Key(ChunkRecordType.Data2DLegacy)) is not null;
        if (hasVersion && hasFinalized && hasBiome) return [];
        var profile = metadataProfile ?? DetectProfile(database, position.Dimension);
        if (profile.UsesLegacyTerrain) return [];
        return Records(position, profile).Where(record => record.RecordType switch
        {
            ChunkRecordType.Version or ChunkRecordType.LegacyVersion => !hasVersion,
            ChunkRecordType.FinalizedState => !hasFinalized,
            _ => !hasBiome
        }).Select(record => new WorldDatabasePut(record.Key, record.Value)).ToArray();
    }
}
