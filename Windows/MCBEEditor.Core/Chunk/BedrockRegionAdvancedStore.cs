using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public enum BedrockRegionStorageScope { Layer0, Layer1, Both }

public sealed record BedrockRegionBlockStateCriterion(string KeyContains, string? ValueContains);

public sealed record BedrockRegionBlockSearchCriteria(string? NameContains, IReadOnlyList<BedrockRegionBlockStateCriterion> StateCriteria)
{
    public bool IsEmpty => string.IsNullOrWhiteSpace(NameContains) && StateCriteria.Count == 0;

    public bool Matches(BedrockBlockState state)
    {
        if (!string.IsNullOrWhiteSpace(NameContains))
        {
            var nameNeedle = NameContains.Trim();
            var searchable = SearchName(state);
            if (!searchable.Contains(nameNeedle, StringComparison.OrdinalIgnoreCase)) return false;
        }

        if (StateCriteria.Count == 0) return true;
        var properties = StateProperties(state);
        foreach (var criterion in StateCriteria)
        {
            var keyNeedle = criterion.KeyContains.Trim();
            if (keyNeedle.Length == 0) continue;
            var matching = properties.Where(pair => pair.Key.Contains(keyNeedle, StringComparison.OrdinalIgnoreCase)).ToArray();
            if (matching.Length == 0) return false;
            var valueNeedle = criterion.ValueContains?.Trim();
            if (!string.IsNullOrEmpty(valueNeedle)
                && !matching.Any(pair => pair.Value.Contains(valueNeedle, StringComparison.OrdinalIgnoreCase))) return false;
        }
        return true;
    }

    private static string SearchName(BedrockBlockState state)
    {
        if (state.Nbt is not null) return state.Name;
        if (state.LegacyId is ushort id)
        {
            var identifier = BedrockLegacyBlockCatalog.IdentifierForNumericId(id);
            return identifier is null ? state.Name : identifier + " " + state.Name;
        }
        return state.Name;
    }

    private static IReadOnlyList<KeyValuePair<string, string>> StateProperties(BedrockBlockState state)
    {
        if (state.Nbt?.CompoundValue("states") is not NbtCompoundValue states) return [];
        return states.Tags.Select(tag => new KeyValuePair<string, string>(tag.Name, tag.Value.Summary)).ToArray();
    }
}

public sealed record BedrockRegionBlockReplacement(string? Name, IReadOnlyList<NbtNamedTag> StateAssignments, bool ReplaceAllStates = true)
{
    public bool IsEmpty => string.IsNullOrWhiteSpace(Name) && StateAssignments.Count == 0 && !ReplaceAllStates;

    public BedrockBlockState Apply(BedrockBlockState source)
    {
        var cleanName = string.IsNullOrWhiteSpace(Name) ? null : NormalizeName(Name!);
        if (source.Nbt is null)
        {
            if (StateAssignments.Count > 0)
                throw new NotSupportedException("旧版数字 ID 方块没有现代 states，不能写入 states 条目。");
            var id = source.LegacyId ?? 0;
            var data = source.LegacyData ?? 0;
            if (cleanName is not null)
                id = BedrockLegacyBlockCatalog.NumericIdForIdentifier(cleanName)
                    ?? throw new NotSupportedException($"目标方块没有可用于旧版存档的数字 ID：{cleanName}");
            if (ReplaceAllStates) data = 0;
            return new BedrockBlockState(null, id, data);
        }

        if (source.Nbt is not NbtCompoundValue compound)
            throw new InvalidDataException("方块 palette 根不是 Compound。");
        var rootTags = compound.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();

        if (cleanName is not null)
        {
            var nameIndex = rootTags.FindIndex(tag => tag.Name.Equals("name", StringComparison.OrdinalIgnoreCase));
            var tag = new NbtNamedTag(nameIndex >= 0 ? rootTags[nameIndex].Name : "name", new NbtStringValue(cleanName));
            if (nameIndex >= 0) rootTags[nameIndex] = tag; else rootTags.Add(tag);
        }

        if (ReplaceAllStates || StateAssignments.Count > 0)
        {
            var statesIndex = rootTags.FindIndex(tag => tag.Name.Equals("states", StringComparison.OrdinalIgnoreCase));
            var valIndex = rootTags.FindIndex(tag => tag.Name.Equals("val", StringComparison.OrdinalIgnoreCase));
            if (statesIndex >= 0 && valIndex >= 0)
                throw new InvalidDataException("旧式 palette 不能同时包含 val 与 states。");
            List<NbtNamedTag> stateTags;
            if (ReplaceAllStates)
            {
                stateTags = [];
            }
            else if (statesIndex >= 0 && rootTags[statesIndex].Value is NbtCompoundValue existingStates)
            {
                stateTags = existingStates.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
            }
            else if (valIndex >= 0 && rootTags[valIndex].Value.IntegerValue() is long rawVal && rawVal is >= 0 and <= 255
                     && BedrockLegacyBlockCatalog.NumericIdForIdentifier(source.Name) is ushort legacyId)
            {
                var normalized = BedrockLegacyBlockStateConverter.StateForNumeric(new BedrockBlockState(null, legacyId, (byte)rawVal));
                if (normalized.Nbt?.CompoundValue("states") is NbtCompoundValue normalizedStates)
                    stateTags = normalizedStates.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
                else
                    throw new NotSupportedException("该旧式 palette 的 val 无可靠 states 映射；请使用“替换全部 states”明确重置。");
            }
            else
            {
                stateTags = [];
            }

            foreach (var assignment in StateAssignments)
            {
                var index = stateTags.FindIndex(tag => tag.Name.Equals(assignment.Name, StringComparison.OrdinalIgnoreCase));
                var clone = new NbtNamedTag(assignment.Name, NbtDocumentTools.DeepClone(assignment.Value));
                if (index >= 0) stateTags[index] = clone; else stateTags.Add(clone);
            }

            if (valIndex >= 0) rootTags.RemoveAt(valIndex);
            statesIndex = rootTags.FindIndex(tag => tag.Name.Equals("states", StringComparison.OrdinalIgnoreCase));
            var statesTag = new NbtNamedTag(statesIndex >= 0 ? rootTags[statesIndex].Name : "states", new NbtCompoundValue(stateTags));
            if (statesIndex >= 0) rootTags[statesIndex] = statesTag; else rootTags.Add(statesTag);
        }

        return new BedrockBlockState(new NbtCompoundValue(rootTags), null, null);
    }

    private static string NormalizeName(string value)
    {
        var clean = value.Trim().ToLowerInvariant();
        return clean.Contains(':') ? clean : "minecraft:" + clean;
    }
}

public sealed record BedrockRegionCoordinatedOperation(
    BedrockRegionBlockSearchCriteria? SearchLayer0,
    BedrockRegionBlockSearchCriteria? SearchLayer1,
    BedrockRegionStorageScope SearchScope,
    BedrockRegionBlockReplacement Layer0Replacement,
    bool ChangeLayer1,
    BedrockRegionBlockReplacement? Layer1Replacement)
{
    public bool Matches(BedrockBlockState layer0, BedrockBlockState layer1)
    {
        if (SearchLayer0 is not null && SearchLayer1 is not null)
            return SearchLayer0.Matches(layer0) && SearchLayer1.Matches(layer1);
        var single = SearchLayer0 ?? SearchLayer1;
        if (single is null) return false;
        return SearchScope switch
        {
            BedrockRegionStorageScope.Layer0 => single.Matches(layer0),
            BedrockRegionStorageScope.Layer1 => single.Matches(layer1),
            _ => single.Matches(layer0) || single.Matches(layer1)
        };
    }
}

public sealed record BedrockRegionBlockHit(int Dimension, int X, int Y, int Z, int StorageIndex, string Name, BedrockBlockState State)
{
    public string CoordinateText => $"({X}, {Y}, {Z})";
}

public sealed record BedrockRegionSearchResult(IReadOnlyList<BedrockRegionBlockHit> Hits, int ScannedSubChunks, bool Truncated);
public sealed record BedrockRegionReplaceResult(int MatchedPositions, int WrittenSubChunks, int SkippedSubChunks);
public sealed record BedrockRegionBiomeResult(int ChangedChunks, long ChangedCells, int SkippedChunks);
public sealed record BedrockRegionCopyResult(
    int WrittenSubChunks, long CopiedBlockStates, int CopiedRecords, long CopiedBiomeCells,
    int CopiedBlockEntities, long SkippedIncompatibleStates, bool UsedWholeChunkCopy,
    int TargetMinimumX, int TargetMinimumZ, int TargetMaximumX, int TargetMaximumZ, int TargetDimension);

public sealed class BedrockRegionAdvancedStore
{
    private readonly IWorldDatabase _database;
    private readonly BedrockChunkSubChunkAccess _access;
    public BedrockRegionAdvancedStore(IWorldDatabase database) { _database = database; _access = new BedrockChunkSubChunkAccess(database); }

    public BedrockRegionSearchResult Search(int dimension, int minX, int minZ, int maxX, int maxZ, string nameQuery, BedrockRegionStorageScope scope, int maximumHits = 10000)
    {
        var criteria = new BedrockRegionBlockSearchCriteria(string.IsNullOrWhiteSpace(nameQuery) ? null : nameQuery.Trim(), []);
        if (criteria.IsEmpty) throw new InvalidDataException("搜索方块 name 不能为空。");
        return Search(dimension, minX, minZ, maxX, maxZ, criteria, scope, maximumHits);
    }

    public BedrockRegionSearchResult Search(int dimension, int minX, int minZ, int maxX, int maxZ,
        BedrockRegionBlockSearchCriteria criteria, BedrockRegionStorageScope scope, int maximumHits = 10000)
    {
        NormalizeBounds(ref minX, ref minZ, ref maxX, ref maxZ);
        if (criteria.IsEmpty) throw new InvalidDataException("搜索条件不能为空。");
        if (maximumHits <= 0) throw new ArgumentOutOfRangeException(nameof(maximumHits));
        var hits = new List<BedrockRegionBlockHit>();
        var scanned = 0;
        foreach (var chunk in ChunkPositions(dimension, minX, minZ, maxX, maxZ))
        {
            var localMinX = Math.Max(0, minX - chunk.X * 16);
            var localMaxX = Math.Min(15, maxX - chunk.X * 16);
            var localMinZ = Math.Max(0, minZ - chunk.Z * 16);
            var localMaxZ = Math.Min(15, maxZ - chunk.Z * 16);
            foreach (var record in _access.Records(chunk))
            {
                scanned++;
                var storages = record.SubChunk.Storages;
                foreach (var storageIndex in StorageIndexes(scope))
                {
                    if (storageIndex >= storages.Count) continue;
                    var storage = storages[storageIndex];
                    for (var lx = localMinX; lx <= localMaxX; lx++)
                    for (var lz = localMinZ; lz <= localMaxZ; lz++)
                    for (var ly = 0; ly < 16; ly++)
                    {
                        var state = storage.BlockState(lx, ly, lz);
                        if (state is null || !criteria.Matches(state)) continue;
                        hits.Add(new BedrockRegionBlockHit(dimension, chunk.X * 16 + lx, record.YIndex * 16 + ly, chunk.Z * 16 + lz, storageIndex, state.Name, state));
                        if (hits.Count >= maximumHits) return new BedrockRegionSearchResult(hits, scanned, true);
                    }
                }
            }
        }
        return new BedrockRegionSearchResult(hits, scanned, false);
    }

    public BedrockRegionSearchResult SearchCoordinated(int dimension, int minX, int minZ, int maxX, int maxZ,
        BedrockRegionCoordinatedOperation operation, int maximumHits = 10000)
    {
        NormalizeBounds(ref minX, ref minZ, ref maxX, ref maxZ);
        if ((operation.SearchLayer0?.IsEmpty ?? true) && (operation.SearchLayer1?.IsEmpty ?? true))
            throw new InvalidDataException("至少填写层 0 或层 1 的搜索条件。");
        if (maximumHits <= 0) throw new ArgumentOutOfRangeException(nameof(maximumHits));

        var hits = new List<BedrockRegionBlockHit>();
        var scanned = 0;
        foreach (var chunk in ChunkPositions(dimension, minX, minZ, maxX, maxZ))
        {
            var localMinX = Math.Max(0, minX - chunk.X * 16);
            var localMaxX = Math.Min(15, maxX - chunk.X * 16);
            var localMinZ = Math.Max(0, minZ - chunk.Z * 16);
            var localMaxZ = Math.Min(15, maxZ - chunk.Z * 16);
            foreach (var record in _access.Records(chunk))
            {
                scanned++;
                var sub = record.SubChunk;
                var air = AirState(sub);
                var layer0 = sub.Storages.Count > 0 ? sub.Storages[0] : SubChunkStorage.AirFilled(air);
                var layer1 = sub.Storages.Count > 1 ? sub.Storages[1] : SubChunkStorage.AirFilled(air);
                for (var lx = localMinX; lx <= localMaxX; lx++)
                for (var lz = localMinZ; lz <= localMaxZ; lz++)
                for (var ly = 0; ly < 16; ly++)
                {
                    var state0 = layer0.BlockState(lx, ly, lz) ?? air;
                    var state1 = layer1.BlockState(lx, ly, lz) ?? air;
                    if (!operation.Matches(state0, state1)) continue;

                    var storageIndex = 0;
                    var state = state0;
                    if (operation.SearchLayer0 is null && operation.SearchLayer1 is not null)
                    {
                        storageIndex = operation.SearchScope == BedrockRegionStorageScope.Layer0 ? 0 :
                            operation.SearchScope == BedrockRegionStorageScope.Layer1 ? 1 :
                            operation.SearchLayer1.Matches(state0) ? 0 : 1;
                        state = storageIndex == 0 ? state0 : state1;
                    }
                    else if (operation.SearchLayer0 is not null && operation.SearchLayer1 is null)
                    {
                        storageIndex = operation.SearchScope == BedrockRegionStorageScope.Layer1 ? 1 :
                            operation.SearchScope == BedrockRegionStorageScope.Layer0 ? 0 :
                            operation.SearchLayer0.Matches(state0) ? 0 : 1;
                        state = storageIndex == 0 ? state0 : state1;
                    }

                    hits.Add(new BedrockRegionBlockHit(dimension, chunk.X * 16 + lx, record.YIndex * 16 + ly,
                        chunk.Z * 16 + lz, storageIndex, state.Name, state));
                    if (hits.Count >= maximumHits) return new BedrockRegionSearchResult(hits, scanned, true);
                }
            }
        }
        return new BedrockRegionSearchResult(hits, scanned, false);
    }

    /// <summary>
    /// iOS-parity coordinate-aware region replacement. Search conditions select one X/Y/Z cell;
    /// replacement is then applied to layer 0 and optionally layer 1 at that same coordinate.
    /// </summary>
    public BedrockRegionReplaceResult ReplaceCoordinated(int dimension, int minX, int minZ, int maxX, int maxZ, BedrockRegionCoordinatedOperation operation)
    {
        NormalizeBounds(ref minX, ref minZ, ref maxX, ref maxZ);
        if ((operation.SearchLayer0?.IsEmpty ?? true) && (operation.SearchLayer1?.IsEmpty ?? true))
            throw new InvalidDataException("至少填写层 0 或层 1 的搜索条件。");
        if (operation.Layer0Replacement.IsEmpty && !operation.ChangeLayer1)
            throw new InvalidDataException("替换内容为空。至少需要修改层 0 或层 1。");

        var written = 0;
        var matched = 0;
        var skipped = 0;
        var puts = new List<WorldDatabasePut>();
        foreach (var chunk in ChunkPositions(dimension, minX, minZ, maxX, maxZ))
        {
            var localMinX = Math.Max(0, minX - chunk.X * 16);
            var localMaxX = Math.Min(15, maxX - chunk.X * 16);
            var localMinZ = Math.Max(0, minZ - chunk.Z * 16);
            var localMaxZ = Math.Min(15, maxZ - chunk.Z * 16);
            var edits = new Dictionary<sbyte, BedrockSubChunk>();
            foreach (var record in _access.Records(chunk))
            {
                try
                {
                    var sub = record.SubChunk;
                    var air = AirState(sub);
                    var layer0 = sub.Storages.Count > 0 ? sub.Storages[0] : SubChunkStorage.AirFilled(air);
                    var layer1 = sub.Storages.Count > 1 ? sub.Storages[1] : SubChunkStorage.AirFilled(air);
                    var replace0 = new Dictionary<int, BedrockBlockState>();
                    var replace1 = new Dictionary<int, BedrockBlockState>();
                    var subChunkMatched = 0;
                    for (var lx = localMinX; lx <= localMaxX; lx++)
                    for (var lz = localMinZ; lz <= localMaxZ; lz++)
                    for (var ly = 0; ly < 16; ly++)
                    {
                        var state0 = layer0.BlockState(lx, ly, lz) ?? air;
                        var state1 = layer1.BlockState(lx, ly, lz) ?? air;
                        if (!operation.Matches(state0, state1)) continue;
                        var flat = (lx << 8) | (lz << 4) | ly;
                        if (!operation.Layer0Replacement.IsEmpty)
                            replace0[flat] = operation.Layer0Replacement.Apply(state0);
                        if (operation.ChangeLayer1)
                            replace1[flat] = operation.Layer1Replacement is null ? air : operation.Layer1Replacement.Apply(state1);
                        subChunkMatched++;
                    }
                    if (replace0.Count == 0 && replace1.Count == 0) continue;
                    matched += subChunkMatched;
                    var storages = sub.Storages.ToList();
                    while (storages.Count == 0) storages.Add(SubChunkStorage.AirFilled(air));
                    if (replace0.Count > 0) storages[0] = storages[0].ReplacingBlockStates(replace0);
                    if (replace1.Count > 0)
                    {
                        while (storages.Count <= 1) storages.Add(SubChunkStorage.AirFilled(air));
                        storages[1] = storages[1].ReplacingBlockStates(replace1);
                        if (storages.Count == 2 && storages[1].Palette.Count > 0 && storages[1].Indices.All(index => storages[1].Palette[index].IsAir))
                            storages.RemoveAt(1);
                    }
                    edits[record.YIndex] = sub with { Storages = storages };
                }
                catch (NotSupportedException) { skipped++; }
            }
            if (edits.Count > 0)
            {
                puts.AddRange(_access.PersistentPuts(chunk, edits));
                written += edits.Count;
            }
        }
        if (puts.Count == 0)
        {
            if (skipped > 0) throw new NotSupportedException($"区域内没有可写匹配；另有 {skipped} 个不支持的 SubChunk 被跳过。");
            throw new InvalidOperationException("区域内没有匹配搜索条件的方块。");
        }
        _database.ApplyBatch(Coalesce(puts), [], sync: true);
        return new BedrockRegionReplaceResult(matched, written, skipped);
    }

    public BedrockRegionReplaceResult ReplaceWholeStorage(int dimension, int minX, int minZ, int maxX, int maxZ,
        int storageIndex, string replacementName, bool includeCompletelyAirCells = false,
        IReadOnlyList<NbtNamedTag>? stateAssignments = null)
    {
        if (storageIndex is < 0 or > 1) throw new ArgumentOutOfRangeException(nameof(storageIndex));
        NormalizeBounds(ref minX, ref minZ, ref maxX, ref maxZ);
        if (string.IsNullOrWhiteSpace(replacementName)) throw new InvalidDataException("目标方块 name 不能为空。");
        var replacement = new BedrockRegionBlockReplacement(replacementName, stateAssignments ?? [], ReplaceAllStates: true);
        var written = 0;
        var affected = 0;
        var skipped = 0;
        var puts = new List<WorldDatabasePut>();
        foreach (var chunk in ChunkPositions(dimension, minX, minZ, maxX, maxZ))
        {
            var localMinX = Math.Max(0, minX - chunk.X * 16);
            var localMaxX = Math.Min(15, maxX - chunk.X * 16);
            var localMinZ = Math.Max(0, minZ - chunk.Z * 16);
            var localMaxZ = Math.Min(15, maxZ - chunk.Z * 16);
            var edits = new Dictionary<sbyte, BedrockSubChunk>();
            foreach (var record in _access.Records(chunk))
            {
                try
                {
                    var sub = record.SubChunk;
                    var air = AirState(sub);
                    var layer0 = sub.Storages.Count > 0 ? sub.Storages[0] : SubChunkStorage.AirFilled(air);
                    var layer1 = sub.Storages.Count > 1 ? sub.Storages[1] : SubChunkStorage.AirFilled(air);
                    var target = storageIndex == 0 ? layer0 : layer1;
                    var replacements = new Dictionary<int, BedrockBlockState>();
                    for (var lx = localMinX; lx <= localMaxX; lx++)
                    for (var lz = localMinZ; lz <= localMaxZ; lz++)
                    for (var ly = 0; ly < 16; ly++)
                    {
                        var state0 = layer0.BlockState(lx, ly, lz) ?? air;
                        var state1 = layer1.BlockState(lx, ly, lz) ?? air;
                        if (!includeCompletelyAirCells && state0.IsAir && state1.IsAir) continue;
                        var current = target.BlockState(lx, ly, lz) ?? air;
                        replacements[(lx << 8) | (lz << 4) | ly] = replacement.Apply(current);
                    }
                    if (replacements.Count == 0) continue;
                    var storages = sub.Storages.ToList();
                    while (storages.Count == 0) storages.Add(SubChunkStorage.AirFilled(air));
                    while (storages.Count <= storageIndex) storages.Add(SubChunkStorage.AirFilled(air));
                    storages[storageIndex] = storages[storageIndex].ReplacingBlockStates(replacements);
                    edits[record.YIndex] = sub with { Storages = storages };
                    affected += replacements.Count;
                }
                catch (NotSupportedException) { skipped++; }
            }
            if (edits.Count > 0)
            {
                puts.AddRange(_access.PersistentPuts(chunk, edits));
                written += edits.Count;
            }
        }
        if (puts.Count == 0)
        {
            if (skipped > 0) throw new NotSupportedException($"框选区域内没有可修改的 SubChunk；跳过 {skipped} 个不支持的 SubChunk。");
            throw new InvalidOperationException("框选区域内没有符合批量选择条件的方块。");
        }
        _database.ApplyBatch(Coalesce(puts), [], sync: true);
        return new BedrockRegionReplaceResult(affected, written, skipped);
    }

    public BedrockRegionCopyResult CopyRegion(
        int sourceDimension, int minX, int minZ, int maxX, int maxZ,
        int targetDimension, int targetMinimumX, int targetMinimumZ)
    {
        NormalizeBounds(ref minX, ref minZ, ref maxX, ref maxZ);
        var width = (long)maxX - minX + 1;
        var depth = (long)maxZ - minZ + 1;
        var targetMaximumX64 = (long)targetMinimumX + width - 1;
        var targetMaximumZ64 = (long)targetMinimumZ + depth - 1;
        if (targetMaximumX64 is < int.MinValue or > int.MaxValue || targetMaximumZ64 is < int.MinValue or > int.MaxValue)
            throw new InvalidDataException("目标区域坐标超出 Int32 范围。");
        var targetMaximumX = (int)targetMaximumX64;
        var targetMaximumZ = (int)targetMaximumZ64;
        if (sourceDimension == targetDimension && minX == targetMinimumX && minZ == targetMinimumZ)
            throw new InvalidDataException("源区域与目标区域不能完全相同。");

        var sourceAligned = IsChunkAligned(minX, minZ, maxX, maxZ);
        var targetAligned = IsChunkAligned(targetMinimumX, targetMinimumZ, targetMaximumX, targetMaximumZ);
        var intersects = sourceDimension == targetDimension
            && minX <= targetMaximumX && maxX >= targetMinimumX
            && minZ <= targetMaximumZ && maxZ >= targetMinimumZ;
        if (sourceAligned && targetAligned && !intersects)
        {
            var sourceMinChunkX = BedrockSurfaceRegionRenderer.FloorDiv(minX, 16);
            var sourceMaxChunkX = BedrockSurfaceRegionRenderer.FloorDiv(maxX, 16);
            var sourceMinChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(minZ, 16);
            var sourceMaxChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(maxZ, 16);
            var targetMinChunkX = BedrockSurfaceRegionRenderer.FloorDiv(targetMinimumX, 16);
            var targetMinChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(targetMinimumZ, 16);
            var chunkCount = checked((long)(sourceMaxChunkX - sourceMinChunkX + 1) * (sourceMaxChunkZ - sourceMinChunkZ + 1));
            if (chunkCount > 1_000_000) throw new InvalidOperationException("区域涉及超过 1,000,000 个区块，拒绝整区块批量复制。");
            var copiedRecords = 0;
            var store = new BedrockChunkStore(_database);
            for (var z = sourceMinChunkZ; z <= sourceMaxChunkZ; z++)
            for (var x = sourceMinChunkX; x <= sourceMaxChunkX; x++)
            {
                var destination = new ChunkPosition(
                    checked(targetMinChunkX + (x - sourceMinChunkX)),
                    checked(targetMinChunkZ + (z - sourceMinChunkZ)), targetDimension);
                copiedRecords += store.CopyChunk(new ChunkPosition(x, z, sourceDimension), destination).CopiedRecordCount;
            }
            return new BedrockRegionCopyResult(0, 0, copiedRecords, 0, 0, 0, true,
                targetMinimumX, targetMinimumZ, targetMaximumX, targetMaximumZ, targetDimension);
        }

        var deltaX = (long)targetMinimumX - minX;
        var deltaZ = (long)targetMinimumZ - minZ;
        var targetEdits = new Dictionary<TargetSubChunkKey, Dictionary<int, Dictionary<int, BedrockBlockState>>>();

        // Snapshot every source SubChunk before any database write. This keeps overlapping
        // source/target regions deterministic instead of consuming already-written target data.
        var sourceRecords = new List<(ChunkPosition Chunk, BedrockStoredSubChunk Record, int MinX, int MaxX, int MinZ, int MaxZ)>();
        foreach (var chunk in ChunkPositions(sourceDimension, minX, minZ, maxX, maxZ))
        {
            var localMinX = Math.Max(0, minX - chunk.X * 16);
            var localMaxX = Math.Min(15, maxX - chunk.X * 16);
            var localMinZ = Math.Max(0, minZ - chunk.Z * 16);
            var localMaxZ = Math.Min(15, maxZ - chunk.Z * 16);
            foreach (var record in _access.Records(chunk))
                sourceRecords.Add((chunk, record, localMinX, localMaxX, localMinZ, localMaxZ));
        }

        foreach (var source in sourceRecords)
        {
            var decoded = source.Record.SubChunk;
            for (var localX = source.MinX; localX <= source.MaxX; localX++)
            {
                var absoluteX = checked(source.Chunk.X * 16 + localX);
                var targetAbsoluteX = checked((int)(absoluteX + deltaX));
                var targetChunkX = BedrockSurfaceRegionRenderer.FloorDiv(targetAbsoluteX, 16);
                var targetLocalX = targetAbsoluteX - targetChunkX * 16;
                for (var localZ = source.MinZ; localZ <= source.MaxZ; localZ++)
                {
                    var absoluteZ = checked(source.Chunk.Z * 16 + localZ);
                    var targetAbsoluteZ = checked((int)(absoluteZ + deltaZ));
                    var targetChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(targetAbsoluteZ, 16);
                    var targetLocalZ = targetAbsoluteZ - targetChunkZ * 16;
                    var targetKey = new TargetSubChunkKey(new ChunkPosition(targetChunkX, targetChunkZ, targetDimension), source.Record.YIndex);
                    if (!targetEdits.TryGetValue(targetKey, out var layers)) targetEdits[targetKey] = layers = new();
                    for (var localY = 0; localY < 16; localY++)
                    {
                        var flat = (targetLocalX << 8) | (targetLocalZ << 4) | localY;
                        for (var layer = 0; layer < Math.Min(2, decoded.Storages.Count); layer++)
                        {
                            var state = decoded.Storages[layer].BlockState(localX, localY, localZ);
                            if (state is null) continue;
                            if (!layers.TryGetValue(layer, out var values)) layers[layer] = values = new();
                            values[flat] = state;
                        }
                    }
                }
            }
        }

        var targetDimensionFormat = BedrockEmptyChunkMetadata.DetectBlockFormat(_database, targetDimension);
        var targetProfile = BedrockEmptyChunkMetadata.DetectProfile(_database, targetDimension);
        var editedByChunk = new Dictionary<ChunkPosition, Dictionary<sbyte, BedrockSubChunk>>();
        long copiedStates = 0;
        long skippedStates = 0;
        foreach (var pair in targetEdits)
        {
            var states = pair.Value.Values.SelectMany(values => values.Values).ToArray();
            if (states.Length == 0) continue;
            var sourceLegacy = states.All(state => state.Nbt is null && state.LegacyId.HasValue);
            var sourceModern = states.All(state => state.Nbt is not null);
            if (!sourceLegacy && !sourceModern) { skippedStates += states.Length; continue; }

            BedrockSubChunk target;
            var existing = _access.Record(pair.Key.Position, pair.Key.Y);
            if (existing is not null)
            {
                if (existing.SubChunk.IsLegacyNumeric != sourceLegacy) { skippedStates += states.Length; continue; }
                target = existing.SubChunk;
            }
            else
            {
                var format = BedrockEmptyChunkMetadata.DetectBlockFormat(_database, targetDimension, pair.Key.Position, targetDimensionFormat);
                if (format.IsLegacyNumeric != sourceLegacy) { skippedStates += states.Length; continue; }
                if (sourceLegacy)
                {
                    var version = format.SubChunkVersion is 0 or 2 or 3 or 4 or 5 or 6 or 7 ? format.SubChunkVersion : (byte)0;
                    target = BedrockSubChunk.EmptyLegacy(version, pair.Key.Y);
                }
                else
                {
                    var version = format.SubChunkVersion is 1 or 8 or 9 ? format.SubChunkVersion : (byte)9;
                    target = new BedrockSubChunk(version, pair.Key.Y,
                        [SubChunkStorage.AirFilled(format.Air)], []);
                }
            }

            try
            {
                foreach (var layer in pair.Value.OrderBy(item => item.Key))
                    target = target.ReplacingStorageBlocks(layer.Key, layer.Value);
            }
            catch (NotSupportedException)
            {
                skippedStates += states.Length;
                continue;
            }
            if (!editedByChunk.TryGetValue(pair.Key.Position, out var chunkEdits)) editedByChunk[pair.Key.Position] = chunkEdits = new();
            chunkEdits[pair.Key.Y] = target;
            copiedStates += states.Length;
        }

        var puts = new List<WorldDatabasePut>();
        var writtenSubChunks = 0;
        foreach (var pair in editedByChunk)
        {
            puts.AddRange(_access.PersistentPuts(pair.Key, pair.Value, preferLegacyTerrainIfMissing: targetProfile.UsesLegacyTerrain, metadataProfile: targetProfile));
            writtenSubChunks += pair.Value.Count;
        }

        var biome = CopyRegionBiomes(sourceDimension, minX, minZ, maxX, maxZ,
            targetDimension, targetMinimumX, targetMinimumZ);
        puts.AddRange(biome.Puts);
        var blockEntities = CopyRegionBlockEntities(sourceDimension, minX, minZ, maxX, maxZ,
            targetDimension, targetMinimumX, targetMinimumZ, targetMaximumX, targetMaximumZ);
        puts.AddRange(blockEntities.Puts);

        var coalesced = Coalesce(puts);
        if (coalesced.Count == 0 && blockEntities.Deletes.Count == 0)
            throw new NotSupportedException("源区域内没有可复制的兼容方块、生物群系或方块实体数据。");
        _database.ApplyBatch(coalesced, blockEntities.Deletes, sync: true);
        return new BedrockRegionCopyResult(writtenSubChunks, copiedStates, 0, biome.ChangedCells,
            blockEntities.CopiedCount, skippedStates, false,
            targetMinimumX, targetMinimumZ, targetMaximumX, targetMaximumZ, targetDimension);
    }

    private (IReadOnlyList<WorldDatabasePut> Puts, long ChangedCells) CopyRegionBiomes(
        int sourceDimension, int minX, int minZ, int maxX, int maxZ,
        int targetDimension, int targetMinimumX, int targetMinimumZ)
    {
        var deltaX = (long)targetMinimumX - minX;
        var deltaZ = (long)targetMinimumZ - minZ;
        var targets = new Dictionary<ChunkPosition, TargetBiomeRecord>();
        long changedCells = 0;
        foreach (var sourceChunk in ChunkPositions(sourceDimension, minX, minZ, maxX, maxZ))
        {
            var sourceRecord = FindBiomeRecord(sourceChunk);
            if (sourceRecord is null) continue;
            var localMinX = Math.Max(0, minX - sourceChunk.X * 16);
            var localMaxX = Math.Min(15, maxX - sourceChunk.X * 16);
            var localMinZ = Math.Max(0, minZ - sourceChunk.Z * 16);
            var localMaxZ = Math.Min(15, maxZ - sourceChunk.Z * 16);
            for (var localX = localMinX; localX <= localMaxX; localX++)
            {
                var absoluteX = checked(sourceChunk.X * 16 + localX);
                var targetAbsoluteX = checked((int)(absoluteX + deltaX));
                var targetChunkX = BedrockSurfaceRegionRenderer.FloorDiv(targetAbsoluteX, 16);
                var targetLocalX = targetAbsoluteX - targetChunkX * 16;
                for (var localZ = localMinZ; localZ <= localMaxZ; localZ++)
                {
                    var absoluteZ = checked(sourceChunk.Z * 16 + localZ);
                    var targetAbsoluteZ = checked((int)(absoluteZ + deltaZ));
                    var targetChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(targetAbsoluteZ, 16);
                    var targetLocalZ = targetAbsoluteZ - targetChunkZ * 16;
                    var targetPosition = new ChunkPosition(targetChunkX, targetChunkZ, targetDimension);
                    if (!targets.TryGetValue(targetPosition, out var target))
                    {
                        var existing = FindBiomeRecord(targetPosition);
                        if (existing is not null)
                            target = new TargetBiomeRecord(existing.Value.Key, existing.Value.Document);
                        else
                        {
                            var blank = BedrockBiomeDocument.Decode(sourceRecord.Value.Type, sourceRecord.Value.Document.Encode());
                            for (var layerIndex = 0; layerIndex < blank.Layers.Count; layerIndex++)
                            {
                                var layer = blank.Layers[layerIndex];
                                if (!layer.IsAbsent)
                                    blank.Layers[layerIndex] = new BedrockBiomeLayer(layer.BaseY, new uint[layer.BiomeIds.Length], false);
                            }
                            var key = new BedrockDbKey(targetPosition, RecordType(blank.Format), null).Encode();
                            target = new TargetBiomeRecord(key, blank);
                        }
                    }
                    changedCells += CopyBiomeColumn(sourceRecord.Value.Document, localX, localZ, target.Document, targetLocalX, targetLocalZ);
                    targets[targetPosition] = target;
                }
            }
        }
        var puts = targets.Values.Select(target => new WorldDatabasePut(target.Key, target.Document.Encode())).ToArray();
        return (puts, changedCells);
    }

    private static int CopyBiomeColumn(BedrockBiomeDocument source, int sourceX, int sourceZ,
        BedrockBiomeDocument target, int targetX, int targetZ)
    {
        var sourceHeightIndex = sourceZ * 16 + sourceX;
        var sourceY = (uint)sourceHeightIndex < (uint)source.HeightMap.Length ? source.HeightMap[sourceHeightIndex] : (short)64;
        var surfaceId = source.BiomeId(sourceX, sourceY, sourceZ)
            ?? source.Layers.FirstOrDefault(layer => !layer.IsAbsent)?.BiomeIds.FirstOrDefault() ?? 0;
        if (target.Format is BedrockBiomeFormat.Data2D or BedrockBiomeFormat.Data2DLegacy)
        {
            if (surfaceId > byte.MaxValue || target.Layers.Count == 0) return 0;
            var index = targetZ * 16 + targetX;
            var layer = target.Layers[0];
            if ((uint)index >= (uint)layer.BiomeIds.Length) return 0;
            var values = layer.BiomeIds.ToArray(); values[index] = surfaceId;
            target.Layers[0] = new BedrockBiomeLayer(layer.BaseY, values, false);
            return 1;
        }

        var count = 0;
        for (var layerIndex = 0; layerIndex < target.Layers.Count; layerIndex++)
        {
            var layer = target.Layers[layerIndex];
            if (layer.IsAbsent || layer.BaseY is not int baseY) continue;
            var values = layer.BiomeIds.ToArray();
            for (var localY = 0; localY < 16; localY++)
            {
                var id = source.BiomeId(sourceX, baseY + localY, sourceZ) ?? surfaceId;
                var index = targetX * 256 + targetZ * 16 + localY;
                if ((uint)index >= (uint)values.Length) continue;
                values[index] = id; count++;
            }
            target.Layers[layerIndex] = new BedrockBiomeLayer(baseY, values, false);
        }
        return count;
    }

    private (IReadOnlyList<WorldDatabasePut> Puts, IReadOnlyList<byte[]> Deletes, int CopiedCount) CopyRegionBlockEntities(
        int sourceDimension, int minX, int minZ, int maxX, int maxZ,
        int targetDimension, int targetMinimumX, int targetMinimumZ, int targetMaximumX, int targetMaximumZ)
    {
        var deltaX = (long)targetMinimumX - minX;
        var deltaZ = (long)targetMinimumZ - minZ;
        var copiedByChunk = new Dictionary<ChunkPosition, List<ConsecutiveNbtRecord>>();
        var copiedCount = 0;
        foreach (var chunk in ChunkPositions(sourceDimension, minX, minZ, maxX, maxZ))
        {
            var key = new BedrockDbKey(chunk, ChunkRecordType.BlockEntity, null).Encode();
            var raw = _database.Get(key);
            if (raw is null) continue;
            foreach (var record in ConsecutiveNbtCodec.Decode(raw))
            {
                if (!BedrockBlockEntityCoordinateTools.TryGetXZ(record.Document.Root, out var x, out var z)
                    || x < minX || x > maxX || z < minZ || z > maxZ) continue;
                var root = BedrockBlockEntityCoordinateTools.OffsetRoot(record.Document.Root, deltaX, deltaZ);
                var targetX = x + deltaX; var targetZ = z + deltaZ;
                var targetChunk = new ChunkPosition(
                    BedrockSurfaceRegionRenderer.FloorDiv(checked((int)targetX), 16),
                    BedrockSurfaceRegionRenderer.FloorDiv(checked((int)targetZ), 16), targetDimension);
                if (!copiedByChunk.TryGetValue(targetChunk, out var records)) copiedByChunk[targetChunk] = records = [];
                records.Add(record with { Document = record.Document with { Root = root }, RawData = [] });
                copiedCount++;
            }
        }

        var puts = new List<WorldDatabasePut>();
        var deletes = new List<byte[]>();
        foreach (var targetChunk in ChunkPositions(targetDimension, targetMinimumX, targetMinimumZ, targetMaximumX, targetMaximumZ))
        {
            var key = new BedrockDbKey(targetChunk, ChunkRecordType.BlockEntity, null).Encode();
            var existingRaw = _database.Get(key);
            var records = new List<ConsecutiveNbtRecord>();
            if (existingRaw is not null)
            {
                foreach (var record in ConsecutiveNbtCodec.Decode(existingRaw))
                {
                    if (BedrockBlockEntityCoordinateTools.TryGetXZ(record.Document.Root, out var x, out var z)
                        && x >= targetMinimumX && x <= targetMaximumX && z >= targetMinimumZ && z <= targetMaximumZ) continue;
                    records.Add(record);
                }
            }
            if (copiedByChunk.TryGetValue(targetChunk, out var copied)) records.AddRange(copied);
            if (records.Count == 0)
            {
                if (existingRaw is not null) deletes.Add(key);
            }
            else puts.Add(new WorldDatabasePut(key, ConsecutiveNbtCodec.Encode(records)));
        }
        return (puts, deletes, copiedCount);
    }

    private (byte[] Key, ChunkRecordType Type, BedrockBiomeDocument Document)? FindBiomeRecord(ChunkPosition position)
    {
        (byte[] Key, ChunkRecordType Type, BedrockBiomeDocument Document)? fallback = null;
        foreach (var entry in _database.Entries(BedrockChunkStore.CoordinatePrefix(position.X, position.Z), includeValues: true))
        {
            if (entry.Value is null || !BedrockDbKey.TryParse(entry.Key, out var key) || key.Position != position) continue;
            if (key.RecordType is not (ChunkRecordType.Data3D or ChunkRecordType.Data2D or ChunkRecordType.Data2DLegacy)) continue;
            var current = (entry.Key.ToArray(), key.RecordType, BedrockBiomeDocument.Decode(key.RecordType, entry.Value));
            if (key.RecordType == ChunkRecordType.Data3D) return current;
            if (fallback is null || key.RecordType == ChunkRecordType.Data2D) fallback = current;
        }
        return fallback;
    }

    private static ChunkRecordType RecordType(BedrockBiomeFormat format) => format switch
    {
        BedrockBiomeFormat.Data3D => ChunkRecordType.Data3D,
        BedrockBiomeFormat.Data2D => ChunkRecordType.Data2D,
        _ => ChunkRecordType.Data2DLegacy
    };

    private static bool IsChunkAligned(int minX, int minZ, int maxX, int maxZ)
        => minX == BedrockSurfaceRegionRenderer.FloorDiv(minX, 16) * 16
           && minZ == BedrockSurfaceRegionRenderer.FloorDiv(minZ, 16) * 16
           && maxX == BedrockSurfaceRegionRenderer.FloorDiv(maxX, 16) * 16 + 15
           && maxZ == BedrockSurfaceRegionRenderer.FloorDiv(maxZ, 16) * 16 + 15;

    private sealed record TargetSubChunkKey(ChunkPosition Position, sbyte Y);
    private sealed record TargetBiomeRecord(byte[] Key, BedrockBiomeDocument Document);

    public BedrockRegionBiomeResult SetBiome(int dimension, int minX, int minZ, int maxX, int maxZ, uint biomeId)
    {
        NormalizeBounds(ref minX, ref minZ, ref maxX, ref maxZ);
        // The map region editor is horizontal: Data3D changes every explicitly stored vertical layer;
        // Data2D/Data2DLegacy naturally ignore Y.
        var (minimumY, maximumY) = dimension switch
        {
            1 => (0, 127),
            2 => (0, 255),
            _ => (-64, 319)
        };
        var box = new BedrockBlockBox(
            new BedrockBlockCoordinate(minX, minimumY, minZ),
            new BedrockBlockCoordinate(maxX, maximumY, maxZ));
        var result = new BedrockBiomeRegionStore(_database).FillBiome(dimension, box, biomeId);
        return new BedrockRegionBiomeResult(result.ChangedChunkCount, result.ChangedCellCount, result.SkippedChunkCount);
    }

    private static BedrockBlockState AirState(BedrockSubChunk sub)
    {
        if (sub.IsLegacyNumeric) return new BedrockBlockState(null, 0, 0);
        var existing = sub.Storages.SelectMany(storage => storage.Palette).FirstOrDefault(state => state.IsAir && state.Nbt is not null);
        var version = sub.Storages.SelectMany(storage => storage.Palette).Select(state => state.PaletteVersion).FirstOrDefault(value => value.HasValue);
        return existing ?? BedrockBlockState.EditableAir(version);
    }

    private static IEnumerable<int> StorageIndexes(BedrockRegionStorageScope scope) => scope switch
    {
        BedrockRegionStorageScope.Layer0 => [0],
        BedrockRegionStorageScope.Layer1 => [1],
        _ => [0, 1]
    };

    private static IEnumerable<ChunkPosition> ChunkPositions(int dimension, int minX, int minZ, int maxX, int maxZ)
    {
        var minChunkX = BedrockSurfaceRegionRenderer.FloorDiv(minX, 16);
        var maxChunkX = BedrockSurfaceRegionRenderer.FloorDiv(maxX, 16);
        var minChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(minZ, 16);
        var maxChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(maxZ, 16);
        for (var z = minChunkZ; z <= maxChunkZ; z++)
        for (var x = minChunkX; x <= maxChunkX; x++) yield return new ChunkPosition(x, z, dimension);
    }

    private static void NormalizeBounds(ref int minX, ref int minZ, ref int maxX, ref int maxZ)
    {
        if (minX > maxX) (minX, maxX) = (maxX, minX);
        if (minZ > maxZ) (minZ, maxZ) = (maxZ, minZ);
    }

    private static IReadOnlyList<WorldDatabasePut> Coalesce(IEnumerable<WorldDatabasePut> puts)
    {
        var map = new Dictionary<string, WorldDatabasePut>(StringComparer.Ordinal);
        foreach (var put in puts) map[Convert.ToHexString(put.Key)] = put;
        return map.Values.ToArray();
    }
}
