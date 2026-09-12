using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public sealed record BedrockBlockRecord(
    int X,
    int Y,
    int Z,
    int Dimension,
    bool Generated,
    IReadOnlyList<BedrockBlockState> Layers,
    byte? SubChunkVersion,
    BedrockSubChunkBackingKind? BackingKind)
{
    public int PreferredLayerIndex
    {
        get
        {
            for (var index = 0; index < Layers.Count; index++)
                if (!Layers[index].IsAir) return index;
            return 0;
        }
    }
}

public sealed record BedrockBlockWriteResult(BedrockBlockRecord Block, int PutCount, int DeleteCount);

public sealed record BedrockBlockMutationPlan(
    IReadOnlyList<WorldDatabasePut> Puts,
    IReadOnlyList<byte[]> Deletes,
    BedrockBlockRecord SourceBefore,
    BedrockBlockRecord TargetBefore,
    BedrockBlockRecord TargetAfter);

/// <summary>
/// coordinate-aware block editing layer. It preserves the world's
/// physical persistence family (normal SubChunk, LegacyTerrain and legacy
/// 0x34 extra layer) and only emits a single batch for each logical edit.
/// </summary>
public sealed class BedrockBlockStore
{
    private readonly IWorldDatabase _database;
    private readonly BedrockChunkSubChunkAccess _access;

    public BedrockBlockStore(IWorldDatabase database)
    {
        _database = database ?? throw new ArgumentNullException(nameof(database));
        _access = new BedrockChunkSubChunkAccess(database);
    }

    public BedrockBlockRecord ReadBlock(int dimension, int x, int y, int z)
    {
        var address = Address(dimension, x, y, z);
        var stored = _access.Record(address.Chunk, address.SubChunkY);
        if (stored is null)
            return new BedrockBlockRecord(x, y, z, dimension, false, [], null, null);
        var layers = stored.SubChunk.Storages
            .Select(storage => storage.BlockState(address.LocalX, address.LocalY, address.LocalZ)
                ?? AirForStorage(storage, stored.SubChunk.IsLegacyNumeric))
            .ToArray();
        return new BedrockBlockRecord(x, y, z, dimension, true, layers, stored.SubChunk.Version, stored.BackingKind);
    }

    public BedrockBlockWriteResult SaveModernState(int dimension, int x, int y, int z, int storageIndex, NbtDocument document)
    {
        var current = ReadBlock(dimension, x, y, z);
        var fallbackVersion = current.Layers.Select(layer => layer.PaletteVersion).FirstOrDefault(version => version.HasValue)
            ?? BedrockEmptyChunkMetadata.DetectBlockFormat(_database, dimension, Address(dimension, x, y, z).Chunk).BlockPaletteVersion;
        var replacement = NormalizeModernState(document, fallbackVersion);
        return SaveState(dimension, x, y, z, storageIndex, replacement);
    }

    public BedrockBlockWriteResult SaveLegacyState(int dimension, int x, int y, int z, int storageIndex, ushort legacyId, byte legacyData)
        => SaveState(dimension, x, y, z, storageIndex, new BedrockBlockState(null, legacyId, legacyData));

    public BedrockBlockRecord ReadBlockForEditing(int dimension, int x, int y, int z)
    {
        var block = ReadBlock(dimension, x, y, z);
        if (block.Generated) return block;
        var format = BedrockEmptyChunkMetadata.DetectBlockFormat(_database, dimension, Address(dimension, x, y, z).Chunk);
        // An editable air template is not proof that a SubChunk exists.
        return block with { Layers = [format.Air] };
    }

    public BedrockBlockWriteResult SaveState(int dimension, int x, int y, int z, int storageIndex, BedrockBlockState replacement)
    {
        if (storageIndex < 0 || storageIndex >= byte.MaxValue) throw new ArgumentOutOfRangeException(nameof(storageIndex));
        var address = Address(dimension, x, y, z);
        var stored = _access.Record(address.Chunk, address.SubChunkY);
        BedrockSubChunk subChunk;
        var preferLegacyTerrainIfMissing = false;

        if (stored is not null)
        {
            if (stored.SubChunk.IsLegacyNumeric != (replacement.Nbt is null))
                throw new NotSupportedException(stored.SubChunk.IsLegacyNumeric
                    ? "旧版数字 ID SubChunk 不能直接写入现代 NBT 方块； 不会隐式升级整个区块。"
                    : "现代 SubChunk 不能直接写入旧版数字 ID 方块。");
            subChunk = stored.SubChunk;
        }
        else
        {
            var profile = BedrockEmptyChunkMetadata.DetectProfile(_database, dimension, preferLegacy: replacement.Nbt is null);
            var format = BedrockEmptyChunkMetadata.DetectBlockFormat(_database, dimension, address.Chunk);
            if (format.IsLegacyNumeric != (replacement.Nbt is null))
                throw new NotSupportedException("替换方块与目标存档的数字 ID/NBT 格式不同。");
            preferLegacyTerrainIfMissing = replacement.Nbt is null && profile.UsesLegacyTerrain && address.SubChunkY is >= 0 and <= 7;
            if (replacement.Nbt is not null && profile.UsesLegacyTerrain)
                throw new NotSupportedException("目标维度仍使用 LegacyTerrain；不能在不升级整个区块格式的情况下新建现代 NBT SubChunk。");
            if (replacement.Nbt is null)
            {
                if (storageIndex > 1) throw new NotSupportedException("旧版数字 ID 方块只支持 storage 0/1。");
                subChunk = BedrockSubChunk.EmptyLegacy(format.SubChunkVersion, address.SubChunkY);
                if (storageIndex == 1)
                    subChunk = subChunk with { Storages = [subChunk.Storages[0], SubChunkStorage.AirFilled(new BedrockBlockState(null, 0, 0))] };
            }
            else
            {
                if (format.IsLegacyNumeric)
                    throw new NotSupportedException("目标存档使用旧版数字 ID；不能新建现代 NBT SubChunk。");
                subChunk = new BedrockSubChunk(format.SubChunkVersion, address.SubChunkY,
                    [SubChunkStorage.AirFilled(format.Air)], []);
            }
        }

        replacement = BedrockLegacyBlockStateConverter.ForPalette(replacement,
            BedrockPaletteFormat.Detect(subChunk.Storages.SelectMany(storage => storage.Palette)));
        var updated = subChunk.ReplacingBlockState(address.LocalX, address.LocalY, address.LocalZ, storageIndex, replacement);
        var puts = new List<WorldDatabasePut>();
        puts.AddRange(_access.PersistentPuts(address.Chunk, new Dictionary<sbyte, BedrockSubChunk> { [address.SubChunkY] = updated }, preferLegacyTerrainIfMissing));
        puts = CoalescePuts(puts).ToList();
        _database.ApplyBatch(puts, Array.Empty<byte[]>(), sync: true);

        var persisted = ReadBlock(dimension, x, y, z);
        if (!persisted.Generated || persisted.Layers.Count <= storageIndex)
            throw new InvalidDataException("方块写入后未能从 LevelDB 读回。");
        return new BedrockBlockWriteResult(persisted, puts.Count, 0);
    }

    public BedrockBlockMutationPlan PlanMoveBlock(
        int sourceDimension, int sourceX, int sourceY, int sourceZ,
        int targetDimension, int targetX, int targetY, int targetZ)
        => PlanTransferBlock(sourceDimension, sourceX, sourceY, sourceZ, targetDimension, targetX, targetY, targetZ, clearSource: true);

    private BedrockBlockMutationPlan PlanTransferBlock(
        int sourceDimension, int sourceX, int sourceY, int sourceZ,
        int targetDimension, int targetX, int targetY, int targetZ,
        bool clearSource)
    {
        var sourceAddress = Address(sourceDimension, sourceX, sourceY, sourceZ);
        var targetAddress = Address(targetDimension, targetX, targetY, targetZ);
        if (sourceAddress == targetAddress)
            throw new InvalidOperationException("源方块与目标方块坐标相同。");

        var sourceStored = _access.Record(sourceAddress.Chunk, sourceAddress.SubChunkY)
            ?? throw new InvalidOperationException("方块实体源坐标没有可读取的 SubChunk/LegacyTerrain 方块，拒绝迁移。");
        if (sourceStored.SubChunk.Storages.Count == 0)
            throw new InvalidOperationException("方块实体源坐标所在 SubChunk 没有可迁移的 storage。");

        var sourceLayers = sourceStored.SubChunk.Storages
            .Select(storage => storage.BlockState(sourceAddress.LocalX, sourceAddress.LocalY, sourceAddress.LocalZ)
                ?? AirForStorage(storage, sourceStored.SubChunk.IsLegacyNumeric))
            .ToArray();
        var sourceBefore = new BedrockBlockRecord(sourceX, sourceY, sourceZ, sourceDimension, true, sourceLayers,
            sourceStored.SubChunk.Version, sourceStored.BackingKind);

        var targetStored = _access.Record(targetAddress.Chunk, targetAddress.SubChunkY);
        var targetBefore = targetStored is null
            ? new BedrockBlockRecord(targetX, targetY, targetZ, targetDimension, false, [], null, null)
            : new BedrockBlockRecord(targetX, targetY, targetZ, targetDimension, true,
                targetStored.SubChunk.Storages.Select(storage => storage.BlockState(targetAddress.LocalX, targetAddress.LocalY, targetAddress.LocalZ)
                    ?? AirForStorage(storage, targetStored.SubChunk.IsLegacyNumeric)).ToArray(),
                targetStored.SubChunk.Version, targetStored.BackingKind);

        if (targetStored is not null && targetStored.SubChunk.IsLegacyNumeric != sourceStored.SubChunk.IsLegacyNumeric)
            throw new NotSupportedException("源/目标 SubChunk 分别属于旧数字 ID 与现代 NBT 格式； 不做隐式整区块格式转换。");

        var targetSubChunk = targetStored?.SubChunk ?? CreateCompatibleEmptyTarget(sourceStored, targetAddress);
        if (targetSubChunk.IsLegacyNumeric && sourceLayers.Length > 2)
            throw new NotSupportedException("旧版数字 ID 目标最多支持 storage 0/1。");

        var edits = new Dictionary<ChunkPosition, Dictionary<sbyte, BedrockSubChunk>>();
        BedrockSubChunk getCurrent(BedrockBlockAddress address, BedrockSubChunk fallback)
        {
            if (edits.TryGetValue(address.Chunk, out var byY) && byY.TryGetValue(address.SubChunkY, out var existing)) return existing;
            return fallback;
        }
        void setCurrent(BedrockBlockAddress address, BedrockSubChunk value)
        {
            if (!edits.TryGetValue(address.Chunk, out var byY)) edits[address.Chunk] = byY = new Dictionary<sbyte, BedrockSubChunk>();
            byY[address.SubChunkY] = value;
        }

        var targetWorking = getCurrent(targetAddress, targetSubChunk)
            .ReplacingBlockLayers(targetAddress.LocalX, targetAddress.LocalY, targetAddress.LocalZ, sourceLayers, clearExtraStorages: true);
        setCurrent(targetAddress, targetWorking);

        if (clearSource)
        {
            var sourceWorking = getCurrent(sourceAddress, sourceStored.SubChunk);
            var sourceAir = sourceWorking.Storages.Select(storage => AirForStorage(storage, sourceWorking.IsLegacyNumeric)).ToArray();
            sourceWorking = sourceWorking.ReplacingBlockLayers(sourceAddress.LocalX, sourceAddress.LocalY, sourceAddress.LocalZ, sourceAir, clearExtraStorages: true);
            setCurrent(sourceAddress, sourceWorking);
        }

        var puts = new List<WorldDatabasePut>();
        foreach (var chunkEdit in edits)
        {
            var preferLegacyTerrain = sourceStored.BackingKind == BedrockSubChunkBackingKind.LegacyTerrain
                                      && chunkEdit.Key == targetAddress.Chunk
                                      && _access.Records(chunkEdit.Key).Count == 0;
            puts.AddRange(_access.PersistentPuts(chunkEdit.Key, chunkEdit.Value, preferLegacyTerrain));
        }

        var targetAfterLayers = targetWorking.Storages.Select(storage => storage.BlockState(targetAddress.LocalX, targetAddress.LocalY, targetAddress.LocalZ)
            ?? AirForStorage(storage, targetWorking.IsLegacyNumeric)).ToArray();
        var targetAfter = new BedrockBlockRecord(targetX, targetY, targetZ, targetDimension, true, targetAfterLayers,
            targetWorking.Version, targetStored?.BackingKind ?? sourceStored.BackingKind);
        return new BedrockBlockMutationPlan(CoalescePuts(puts), [], sourceBefore, targetBefore, targetAfter);
    }

    public static BedrockBlockState NormalizeModernState(NbtDocument document, int? fallbackVersion = null)
    {
        if (document.Root is not NbtCompoundValue compound)
            throw new InvalidDataException("方块状态 NBT 根必须是 Compound。");
        var tags = compound.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
        var nameIndex = tags.FindIndex(tag => string.Equals(tag.Name, "name", StringComparison.OrdinalIgnoreCase));
        if (nameIndex < 0 || tags[nameIndex].Value is not NbtStringValue name || string.IsNullOrWhiteSpace(name.Value))
            throw new InvalidDataException("现代方块状态必须包含非空 string name。");
        var states = tags.FindIndex(tag => string.Equals(tag.Name, "states", StringComparison.OrdinalIgnoreCase));
        var val = tags.FindIndex(tag => string.Equals(tag.Name, "val", StringComparison.OrdinalIgnoreCase));
        if (states >= 0 && val >= 0) throw new InvalidDataException("方块状态不能同时包含 states 与 val。");
        if (states < 0 && val < 0) tags.Add(new NbtNamedTag("states", new NbtCompoundValue([])));
        if (states >= 0 && tags[states].Value is not NbtCompoundValue)
            throw new InvalidDataException("方块 states 必须是 Compound。");

        var version = tags.FindIndex(tag => string.Equals(tag.Name, "version", StringComparison.OrdinalIgnoreCase));
        var versionValue = version >= 0 ? tags[version].Value.IntegerValue() : null;
        var selectedVersion = versionValue is >= int.MinValue and <= int.MaxValue
            ? (int)versionValue.Value
            : fallbackVersion ?? BedrockBlockState.DefaultPaletteVersion;
        if (version >= 0) tags[version] = new NbtNamedTag(tags[version].Name, new NbtIntValue(selectedVersion));
        else if (val < 0) tags.Add(new NbtNamedTag("version", new NbtIntValue(selectedVersion)));
        return new BedrockBlockState(new NbtCompoundValue(tags), null, null);
    }

    private BedrockSubChunk CreateCompatibleEmptyTarget(BedrockStoredSubChunk source, BedrockBlockAddress target)
    {
        var profile = BedrockEmptyChunkMetadata.DetectProfile(_database, target.Chunk.Dimension);
        var format = BedrockEmptyChunkMetadata.DetectBlockFormat(_database, target.Chunk.Dimension, target.Chunk);
        if (profile.UsesLegacyTerrain != (source.BackingKind == BedrockSubChunkBackingKind.LegacyTerrain))
            throw new NotSupportedException("源/目标使用不同的 LegacyTerrain/SubChunk 物理格式，无法直接移动方块。");
        if (format.IsLegacyNumeric != source.SubChunk.IsLegacyNumeric)
            throw new NotSupportedException("源/目标分别属于数字 ID 与现代 NBT 格式，无法直接移动方块。");
        if (profile.UsesLegacyTerrain && target.SubChunkY is < 0 or > 7)
            throw new NotSupportedException("LegacyTerrain 方块只能移动到 Y=0…127 范围。");
        if (format.IsLegacyNumeric) return BedrockSubChunk.EmptyLegacy(format.SubChunkVersion, target.SubChunkY);
        return new BedrockSubChunk(format.SubChunkVersion, target.SubChunkY,
            [SubChunkStorage.AirFilled(format.Air)], []);
    }

    private static BedrockBlockState AirForStorage(SubChunkStorage storage, bool legacy)
        => legacy
            ? new BedrockBlockState(null, 0, 0)
            : storage.Palette.FirstOrDefault(state => state.Nbt is not null && state.IsAir)
              ?? BedrockBlockState.EditableAir(storage.Palette.Select(state => state.PaletteVersion).FirstOrDefault(value => value.HasValue));

    private static BedrockBlockAddress Address(int dimension, int x, int y, int z)
    {
        var chunkX = FloorDiv(x, 16);
        var chunkZ = FloorDiv(z, 16);
        var subY = FloorDiv(y, 16);
        if (subY < sbyte.MinValue || subY > sbyte.MaxValue)
            throw new NotSupportedException("Y 坐标超出 Bedrock SubChunk Int8 索引范围。");
        return new BedrockBlockAddress(
            new ChunkPosition(chunkX, chunkZ, dimension), checked((sbyte)subY),
            x - chunkX * 16, y - subY * 16, z - chunkZ * 16);
    }

    private static int FloorDiv(int value, int divisor)
    {
        var quotient = value / divisor;
        var remainder = value % divisor;
        return remainder < 0 ? quotient - 1 : quotient;
    }

    private static IReadOnlyList<WorldDatabasePut> CoalescePuts(IEnumerable<WorldDatabasePut> puts)
        => puts.GroupBy(put => Convert.ToHexString(put.Key), StringComparer.Ordinal)
            .Select(group => group.Last()).ToArray();

    private readonly record struct BedrockBlockAddress(
        ChunkPosition Chunk,
        sbyte SubChunkY,
        int LocalX,
        int LocalY,
        int LocalZ);
}
