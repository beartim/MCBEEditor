using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public enum BedrockSubChunkBackingKind
{
    SubChunk,
    LegacyTerrain
}

public sealed record BedrockStoredSubChunk(
    sbyte YIndex,
    BedrockSubChunk SubChunk,
    BedrockSubChunkBackingKind BackingKind,
    byte[] BackingKey);

/// <summary>
/// Coordinate-oriented access to normal 0x2F SubChunks, numeric 0x34 extra
/// layer storage and pre-Anvil 0x30 LegacyTerrain columns.
/// </summary>
public sealed class BedrockChunkSubChunkAccess
{
    private readonly IWorldDatabase _database;
    public BedrockChunkSubChunkAccess(IWorldDatabase database) => _database = database;

    public IReadOnlyList<BedrockStoredSubChunk> Records(ChunkPosition position)
    {
        var output = new List<BedrockStoredSubChunk>();
        var occupied = new HashSet<sbyte>();
        (byte[] Key, byte[] Value)? legacyTerrain = null;
        BedrockLegacyBlockExtraData? extra = null;
        byte? observedNumericVersion = null;

        foreach (var entry in _database.Entries(BedrockChunkStore.CoordinatePrefix(position.X, position.Z), includeValues: true))
        {
            if (entry.Value is null || !BedrockDbKey.TryParse(entry.Key, out var key) || key.Position != position) continue;
            if (key.RecordType == ChunkRecordType.SubChunk && key.SubChunkIndex is sbyte keyY)
            {
                var decoded = BedrockSubChunk.Decode(entry.Value, keyY);
                var logicalY = decoded.YIndex ?? keyY;
                if (decoded.IsLegacyNumeric) observedNumericVersion ??= decoded.Version;
                output.Add(new BedrockStoredSubChunk(logicalY, decoded, BedrockSubChunkBackingKind.SubChunk, entry.Key.ToArray()));
                occupied.Add(logicalY);
            }
            else if (key.RecordType == ChunkRecordType.LegacyTerrain)
            {
                legacyTerrain = (entry.Key.ToArray(), entry.Value.ToArray());
            }
            else if (key.RecordType == ChunkRecordType.LegacyBlockExtraData)
            {
                extra = BedrockLegacyBlockExtraData.Decode(entry.Value);
            }
        }

        if (extra is not null)
        {
            for (var index = 0; index < output.Count; index++)
            {
                var record = output[index];
                if (!record.SubChunk.IsLegacyNumeric || record.BackingKind != BedrockSubChunkBackingKind.SubChunk) continue;
                if (extra.Storage(record.YIndex) is not { } layer1) continue;
                var storages = record.SubChunk.Storages.ToList();
                if (storages.Count == 0) storages.Add(SubChunkStorage.AirFilled(new BedrockBlockState(null, 0, 0)));
                if (storages.Count == 1) storages.Add(layer1); else storages[1] = layer1;
                output[index] = record with { SubChunk = record.SubChunk with { Storages = storages } };
            }

            var fallbackVersion = observedNumericVersion ?? 0;
            foreach (var y in extra.Entries.Select(entry => entry.SubChunkY).Distinct().OrderBy(value => value))
            {
                if (occupied.Contains(y) || y is < 0 or > 15 || extra.Storage(y) is not { } layer1) continue;
                var baseSub = BedrockSubChunk.EmptyLegacy(fallbackVersion, y);
                var storages = baseSub.Storages.ToList();
                storages.Add(layer1);
                var key = BedrockDbKey.SubChunk(position.X, position.Z, position.Dimension, y);
                output.Add(new BedrockStoredSubChunk(y, baseSub with { Storages = storages }, BedrockSubChunkBackingKind.SubChunk, key));
                occupied.Add(y);
            }
        }

        if (legacyTerrain is { } terrainRecord)
        {
            var terrain = BedrockLegacyTerrain.Decode(terrainRecord.Value);
            for (sbyte y = 0; y < 8; y++)
            {
                if (occupied.Contains(y)) continue;
                output.Add(new BedrockStoredSubChunk(y, terrain.SubChunk(y), BedrockSubChunkBackingKind.LegacyTerrain, terrainRecord.Key));
            }
        }

        return output.OrderBy(record => record.YIndex)
            .ThenBy(record => record.BackingKind == BedrockSubChunkBackingKind.SubChunk ? 0 : 1)
            .ToArray();
    }

    public BedrockStoredSubChunk? Record(ChunkPosition position, sbyte yIndex)
    {
        var directKey = BedrockDbKey.SubChunk(position.X, position.Z, position.Dimension, yIndex);
        if (_database.Get(directKey) is { } directRaw)
        {
            var decoded = BedrockSubChunk.Decode(directRaw, yIndex);
            var logicalY = decoded.YIndex ?? yIndex;
            if (logicalY == yIndex)
            {
                if (decoded.IsLegacyNumeric && LegacyExtra(position) is { } extra && extra.Storage(logicalY) is { } layer1)
                {
                    var storages = decoded.Storages.ToList();
                    if (storages.Count == 0) storages.Add(SubChunkStorage.AirFilled(new BedrockBlockState(null, 0, 0)));
                    if (storages.Count == 1) storages.Add(layer1); else storages[1] = layer1;
                    decoded = decoded with { Storages = storages };
                }
                return new BedrockStoredSubChunk(logicalY, decoded, BedrockSubChunkBackingKind.SubChunk, directKey);
            }
        }

        if (yIndex is >= 0 and <= 7)
        {
            var legacyKey = new BedrockDbKey(position, ChunkRecordType.LegacyTerrain, null).Encode();
            if (_database.Get(legacyKey) is { } raw)
                return new BedrockStoredSubChunk(yIndex, BedrockLegacyTerrain.Decode(raw).SubChunk(yIndex), BedrockSubChunkBackingKind.LegacyTerrain, legacyKey);
        }

        return Records(position).FirstOrDefault(record => record.YIndex == yIndex);
    }

    public IReadOnlyList<WorldDatabasePut> PersistentPuts(
        ChunkPosition position,
        IReadOnlyDictionary<sbyte, BedrockSubChunk> edited,
        bool preferLegacyTerrainIfMissing = false,
        BedrockEmptyChunkProfile? metadataProfile = null)
    {
        if (edited.Count == 0) return [];
        var existing = Records(position);
        var byY = existing.GroupBy(record => record.YIndex).ToDictionary(group => group.Key, group => group.First());
        var legacyKey = new BedrockDbKey(position, ChunkRecordType.LegacyTerrain, null).Encode();
        var extraKey = new BedrockDbKey(position, ChunkRecordType.LegacyBlockExtraData, null).Encode();
        var hasLegacyTerrain = existing.Any(record => record.BackingKind == BedrockSubChunkBackingKind.LegacyTerrain);
        if (hasLegacyTerrain && edited.Keys.Any(y => y is < 0 or > 7))
            throw new NotSupportedException("LegacyTerrain 世界只保存 Y=0…127；不能直接创建其它 SubChunk。");

        if (existing.Count == 0 && preferLegacyTerrainIfMissing)
        {
            var raw = BedrockLegacyTerrain.EmptyPersistentData;
            var terrain = BedrockLegacyTerrain.Decode(raw);
            foreach (var pair in edited.OrderBy(pair => pair.Key)) ReplaceLegacyTerrainSubChunk(terrain, pair.Key, pair.Value);
            return [new WorldDatabasePut(legacyKey, terrain.EncodePersistent())];
        }

        BedrockLegacyTerrain? legacyTerrain = null;
        if (edited.Keys.Any(y => byY.TryGetValue(y, out var record) && record.BackingKind == BedrockSubChunkBackingKind.LegacyTerrain)
            && _database.Get(legacyKey) is { } legacyRaw)
            legacyTerrain = BedrockLegacyTerrain.Decode(legacyRaw);

        var extraRaw = _database.Get(extraKey);
        var extra = extraRaw is null ? new BedrockLegacyBlockExtraData() : BedrockLegacyBlockExtraData.Decode(extraRaw);
        var touchedExtra = false;
        var touchedLegacyTerrain = false;
        var puts = new List<WorldDatabasePut>();

        foreach (var pair in edited.OrderBy(pair => pair.Key))
        {
            var y = pair.Key;
            var subChunk = pair.Value;
            if (!subChunk.IsLegacyNumeric && !subChunk.IsRawPreservedUnknownVersion)
            {
                var paletteFormat = byY.TryGetValue(y, out var original)
                    ? BedrockPaletteFormat.Detect(original.SubChunk.Storages.SelectMany(storage => storage.Palette))
                    : BedrockPaletteFormat.Detect(existing.SelectMany(record => record.SubChunk.Storages).SelectMany(storage => storage.Palette))
                        ?? BedrockPaletteFormat.Detect(subChunk.Storages.SelectMany(storage => storage.Palette));
                if (paletteFormat?.UsesLegacyVal == true)
                    subChunk = subChunk with { Storages = subChunk.Storages.Select(storage => storage with
                    {
                        Palette = storage.Palette.Select(state => BedrockLegacyBlockStateConverter.ForPalette(state, paletteFormat)).ToArray()
                    }).ToArray() };
            }
            if (byY.TryGetValue(y, out var record))
            {
                if (record.BackingKind == BedrockSubChunkBackingKind.LegacyTerrain)
                {
                    legacyTerrain ??= _database.Get(legacyKey) is { } raw ? BedrockLegacyTerrain.Decode(raw) : throw new InvalidDataException("LegacyTerrain 写回时原记录不存在。");
                    ReplaceLegacyTerrainSubChunk(legacyTerrain, y, subChunk);
                    touchedLegacyTerrain = true;
                }
                else if (subChunk.IsLegacyNumeric)
                {
                    var primary = subChunk with { Storages = subChunk.Storages.Take(1).ToArray() };
                    puts.Add(new WorldDatabasePut(record.BackingKey.ToArray(), primary.EncodePersistent()));
                    extra.ReplaceStorage(y, subChunk.Storages.Count > 1 ? subChunk.Storages[1] : null);
                    touchedExtra = true;
                }
                else
                {
                    puts.Add(new WorldDatabasePut(record.BackingKey.ToArray(), subChunk.EncodePersistent()));
                    if (record.SubChunk.IsLegacyNumeric && y is >= 0 and <= 15)
                    {
                        extra.ReplaceStorage(y, null);
                        touchedExtra = true;
                    }
                }
            }
            else
            {
                var key = BedrockDbKey.SubChunk(position.X, position.Z, position.Dimension, y);
                if (subChunk.IsLegacyNumeric)
                {
                    var primary = subChunk with { Storages = subChunk.Storages.Take(1).ToArray() };
                    puts.Add(new WorldDatabasePut(key, primary.EncodePersistent()));
                    extra.ReplaceStorage(y, subChunk.Storages.Count > 1 ? subChunk.Storages[1] : null);
                    touchedExtra = true;
                }
                else
                {
                    puts.Add(new WorldDatabasePut(key, subChunk.EncodePersistent()));
                }
            }
        }

        if (touchedLegacyTerrain && legacyTerrain is not null)
            puts.Add(new WorldDatabasePut(legacyKey, legacyTerrain.EncodePersistent()));
        if (touchedExtra)
            puts.Add(new WorldDatabasePut(extraKey, extra.EncodePersistent()));
        if (!hasLegacyTerrain)
            puts.AddRange(BedrockEmptyChunkMetadata.MissingRecords(_database, position, metadataProfile));
        return puts;
    }

    private BedrockLegacyBlockExtraData? LegacyExtra(ChunkPosition position)
    {
        var key = new BedrockDbKey(position, ChunkRecordType.LegacyBlockExtraData, null).Encode();
        return _database.Get(key) is { } raw ? BedrockLegacyBlockExtraData.Decode(raw) : null;
    }

    private static void ReplaceLegacyTerrainSubChunk(BedrockLegacyTerrain terrain, sbyte yIndex, BedrockSubChunk subChunk)
    {
        if (yIndex is < 0 or > 7) throw new NotSupportedException("LegacyTerrain 只包含 SubChunk Y=0…7。");
        if (!subChunk.IsLegacyNumeric || subChunk.Storages.Count != 1)
            throw new NotSupportedException("LegacyTerrain 只能写入单层旧版数字 ID SubChunk。");
        var storage = subChunk.Storages[0];
        if (storage.Indices.Length != 4096 || storage.Palette.Count == 0)
            throw new InvalidDataException("LegacyTerrain 替换 storage 无效。");
        for (var x = 0; x < 16; x++)
        for (var z = 0; z < 16; z++)
        for (var localY = 0; localY < 16; localY++)
        {
            var blockIndex = (x << 8) | (z << 4) | localY;
            var paletteIndex = storage.Indices[blockIndex];
            if (paletteIndex >= storage.Palette.Count) throw new InvalidDataException("LegacyTerrain 调色板索引越界。");
            var state = storage.Palette[paletteIndex];
            if (state.Nbt is not null || state.LegacyId is not ushort legacyId || legacyId > byte.MaxValue)
                throw new NotSupportedException("LegacyTerrain 只能写入 0…255 数字 ID。");
            var absoluteY = yIndex * 16 + localY;
            var sourceIndex = (x << 11) | (z << 7) | absoluteY;
            terrain.BlockIds[sourceIndex] = (byte)legacyId;
            var packedIndex = sourceIndex >> 1;
            var data = (byte)((state.LegacyData ?? 0) & 0x0f);
            terrain.DataValues[packedIndex] = (sourceIndex & 1) == 0
                ? (byte)((terrain.DataValues[packedIndex] & 0xf0) | data)
                : (byte)((terrain.DataValues[packedIndex] & 0x0f) | (data << 4));
        }
    }
}
