using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

/// <summary>
/// region transaction layer. A fill/setblock/clone operation collects
/// all affected SubChunks and BlockEntity records first, then commits exactly
/// one LevelDB WriteBatch. Source SubChunks and BlockEntities are snapshotted
/// before clone writes, so overlapping copies behave like memmove rather than
/// cascading already-written blocks.
/// </summary>
public sealed class BedrockRegionBlockStore
{
    public const long MaximumVolume = 67_108_864;

    private readonly IWorldDatabase _database;
    private readonly BedrockChunkSubChunkAccess _access;

    public BedrockRegionBlockStore(IWorldDatabase database)
    {
        _database = database ?? throw new ArgumentNullException(nameof(database));
        _access = new BedrockChunkSubChunkAccess(database);
    }

    public BedrockRegionMutationResult SetBlock(int dimension, BedrockBlockCoordinate position, IReadOnlyList<BedrockBlockStorageSpec> storages)
        => Fill(dimension, new BedrockBlockBox(position, position), storages);

    public BedrockRegionMutationResult Fill(int dimension, BedrockBlockBox region, IReadOnlyList<BedrockBlockStorageSpec> storages)
    {
        ValidateRegion(region);
        ValidateStorages(storages);
        var cache = new RegionEditCache(_database, _access, dimension);
        long changed = 0;

        foreach (var slice in EnumerateSlices(region))
        {
            var working = cache.GetForFill(slice.Chunk, slice.SubChunkY, storages);
            var before = working;
            var indices = FlatIndices(slice).ToArray();
            for (var layer = 0; layer < storages.Count; layer++)
            {
                if (working.IsLegacyNumeric && (storages.Count > 2 || !storages[layer].CanRemainLegacy(layer)))
                    throw new NotSupportedException("目标存档的旧版数字 ID 无法表示这些 states 或 storage 层数。");
                var paletteVersion = PaletteVersion(working);
                var replacement = working.IsLegacyNumeric ? storages[layer].LegacyState() : storages[layer].ModernState(paletteVersion);
                replacement = BedrockLegacyBlockStateConverter.ForPalette(replacement,
                    BedrockPaletteFormat.Detect(working.Storages.SelectMany(storage => storage.Palette)));
                var replacements = indices.ToDictionary(index => index, _ => replacement);
                working = working.ReplacingStorageBlocks(layer, replacements);
            }
            cache.Set(slice.Chunk, slice.SubChunkY, working);
            if (!ReferenceEquals(before, working)) changed += slice.Volume;
        }

        var blockEntityEdits = PlanRemoveBlockEntities(dimension, region);
        return Commit(cache, blockEntityEdits.Puts, blockEntityEdits.Deletes, changed, blockEntityEdits.Removed, 0);
    }

    public BedrockRegionMutationResult Clone(
        int sourceDimension,
        BedrockBlockBox source,
        int targetDimension,
        BedrockBlockCoordinate destination)
    {
        ValidateRegion(source);
        var target = source.TranslateTo(destination);
        ValidateRegion(target);

        var targetChunks = EnumerateChunks(targetDimension, target).ToHashSet();
        var sourceGenerationPuts = PlanMissingChunkMetadata(sourceDimension, source,
            sourceDimension == targetDimension ? targetChunks : null);
        var sourceSnapshot = SnapshotSubChunks(sourceDimension, source);
        var cache = new RegionEditCache(_database, _access, targetDimension);
        long changedPositions = 0;
        int deltaX, deltaY, deltaZ;
        checked
        {
            deltaX = destination.X - source.Minimum.X;
            deltaY = destination.Y - source.Minimum.Y;
            deltaZ = destination.Z - source.Minimum.Z;
        }

        // Process one destination SubChunk at a time. The complete source is
        // already frozen in sourceSnapshot, so this keeps clone overlap-safe
        // without retaining one Dictionary entry per copied block for the
        // whole region. Each target storage clones its 4096-index buffer only
        // once, regardless of how many cells in the slice are replaced.
        foreach (var slice in EnumerateSlices(target))
        {
            var working = cache.GetForClone(slice.Chunk, slice.SubChunkY);
            var byLayer = new Dictionary<int, Dictionary<int, BedrockBlockState>>();

            // Pass 2 adapts every source state against the now-stable target
            // family and builds at most 4096 replacements per storage.
            foreach (var cell in EnumerateCells(slice))
            {
                var sourceX = checked(cell.X - deltaX);
                var sourceY = checked(cell.Y - deltaY);
                var sourceZ = checked(cell.Z - deltaZ);
                var sourceStates = SnapshotLayers(sourceSnapshot, sourceDimension, sourceX, sourceY, sourceZ);
                var sourceCount = Math.Max(1, sourceStates.Count);
                var targetCount = Math.Max(1, working.Storages.Count);
                var layerCount = Math.Max(sourceCount, targetCount);
                if (layerCount > byte.MaxValue)
                    throw new NotSupportedException("clone 遇到超过 255 个 storage 的 SubChunk。");

                for (var layer = 0; layer < layerCount; layer++)
                {
                    var sourceState = layer < sourceStates.Count
                        ? sourceStates[layer]
                        : SourceAir(sourceStates, working, layer);
                    var adapted = AdaptState(sourceState, working, layer);
                    if (!byLayer.TryGetValue(layer, out var replacements))
                        byLayer[layer] = replacements = new Dictionary<int, BedrockBlockState>();
                    replacements[cell.FlatIndex] = adapted;
                }
            }

            foreach (var layer in byLayer.OrderBy(pair => pair.Key))
                working = working.ReplacingStorageBlocks(layer.Key, layer.Value);
            cache.Set(slice.Chunk, slice.SubChunkY, working);
            changedPositions += slice.Volume;
        }

        var blockEntities = PlanCloneBlockEntities(sourceDimension, source, targetDimension, target, destination);
        var extraPuts = sourceGenerationPuts.Concat(blockEntities.Puts).ToArray();
        return Commit(cache, extraPuts, blockEntities.Deletes, changedPositions, blockEntities.Removed, blockEntities.Copied);
    }

    public NbtDocument CaptureStructureDocument(int dimension, BedrockBlockBox region)
    {
        ValidateRegion(region);
        if (region.Volume > 16_777_216)
            throw new NotSupportedException("structure save 一次最多保存 16,777,216 个方块。");

        var sizeX = checked(region.Maximum.X - region.Minimum.X + 1);
        var sizeY = checked(region.Maximum.Y - region.Minimum.Y + 1);
        var sizeZ = checked(region.Maximum.Z - region.Minimum.Z + 1);
        var volume = checked(sizeX * sizeY * sizeZ);
        var primary = Enumerable.Repeat(-1, volume).ToArray();
        var secondary = Enumerable.Repeat(-1, volume).ToArray();
        var palette = new List<NbtValue>();
        var paletteLookup = new Dictionary<string, int>(StringComparer.Ordinal);
        var captureSubChunks = new Dictionary<SubChunkAddress, BedrockStoredSubChunk?>();
        var captureFormats = new Dictionary<ChunkPosition, BedrockBlockFormat>();

        IReadOnlyList<BedrockBlockState> CaptureLayers(int x, int y, int z)
        {
            var address = Address(dimension, x, y, z);
            var subKey = new SubChunkAddress(address.Chunk, address.SubChunkY);
            if (!captureSubChunks.TryGetValue(subKey, out var stored))
            {
                stored = _access.Record(address.Chunk, address.SubChunkY);
                captureSubChunks[subKey] = stored;
            }
            if (stored is null)
            {
                if (!captureFormats.TryGetValue(address.Chunk, out var format))
                    captureFormats[address.Chunk] = format = BedrockEmptyChunkMetadata.DetectBlockFormat(_database, dimension, address.Chunk);
                return [format.Air];
            }
            if (stored.SubChunk.IsRawPreservedUnknownVersion)
                throw new NotSupportedException($"structure save 源区域包含未知 SubChunk v{stored.SubChunk.Version}，无法确认其中方块内容。");
            if (stored.SubChunk.Storages.Count == 0)
                return [stored.SubChunk.IsLegacyNumeric ? new BedrockBlockState(null, 0, 0) : BedrockBlockState.EditableAir(PaletteVersion(stored.SubChunk))];
            return stored.SubChunk.Storages.Select(storage => storage.BlockState(address.LocalX, address.LocalY, address.LocalZ)
                ?? AirForStorage(storage, stored.SubChunk.IsLegacyNumeric)).ToArray();
        }

        int PaletteIndex(BedrockBlockState state)
        {
            var modern = state.Nbt is not null ? state : BedrockLegacyBlockStateConverter.StateForNumeric(state);
            if (modern.Nbt is null) throw new InvalidDataException("结构调色板方块缺少现代 NBT 状态。");
            var normalized = BedrockBlockStore.NormalizeModernState(new NbtDocument(string.Empty, modern.Nbt), modern.PaletteVersion);
            var nbt = normalized.Nbt ?? throw new InvalidDataException("结构调色板方块标准化后缺少 NBT。");
            var encoded = BedrockNbtCodec.Encode(new NbtDocument(string.Empty, nbt), NbtEncoding.LittleEndian);
            var key = Convert.ToHexString(encoded);
            if (paletteLookup.TryGetValue(key, out var existing)) return existing;
            if (palette.Count == int.MaxValue) throw new NotSupportedException("结构调色板条目过多。");
            var index = palette.Count;
            palette.Add(NbtDocumentTools.DeepClone(nbt));
            paletteLookup[key] = index;
            return index;
        }

        for (var x = region.Minimum.X; ; x++)
        {
            for (var y = region.Minimum.Y; ; y++)
            {
                for (var z = region.Minimum.Z; ; z++)
                {
                    var layers = CaptureLayers(x, y, z);
                    var first = layers.Count > 0 ? layers[0] : BedrockBlockState.EditableAir();
                    var second = layers.Count > 1 ? layers[1] : StructureAir(first);
                    var flat = checked((x - region.Minimum.X) * sizeY * sizeZ + (y - region.Minimum.Y) * sizeZ + (z - region.Minimum.Z));
                    primary[flat] = PaletteIndex(first);
                    secondary[flat] = PaletteIndex(second);
                    if (z == region.Maximum.Z) break;
                }
                if (y == region.Maximum.Y) break;
            }
            if (x == region.Maximum.X) break;
        }

        var positionTags = new List<NbtNamedTag>();
        foreach (var chunk in EnumerateChunks(dimension, region))
        {
            var key = new BedrockDbKey(chunk, ChunkRecordType.BlockEntity, null).Encode();
            var raw = _database.Get(key);
            if (raw is null) continue;
            foreach (var record in ConsecutiveNbtCodec.Decode(raw))
            {
                var pos = BedrockWorldObjectScanner.ExtractPosition(record.Document.Root, BedrockWorldObjectKind.BlockEntity);
                if (pos is null || !region.Contains(pos.BlockX, pos.BlockY, pos.BlockZ)) continue;
                var flat = checked((pos.BlockX - region.Minimum.X) * sizeY * sizeZ + (pos.BlockY - region.Minimum.Y) * sizeZ + (pos.BlockZ - region.Minimum.Z));
                positionTags.Add(new NbtNamedTag(flat.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    new NbtCompoundValue([new NbtNamedTag("block_entity_data", NbtDocumentTools.DeepClone(record.Document.Root))])));
            }
        }
        positionTags.Sort((lhs, rhs) => int.Parse(lhs.Name, System.Globalization.CultureInfo.InvariantCulture)
            .CompareTo(int.Parse(rhs.Name, System.Globalization.CultureInfo.InvariantCulture)));

        return new NbtDocument(string.Empty, new NbtCompoundValue([
            new NbtNamedTag("format_version", new NbtIntValue(1)),
            new NbtNamedTag("size", new NbtListValue(NbtTagType.Int, [
                new NbtIntValue(sizeX), new NbtIntValue(sizeY), new NbtIntValue(sizeZ)
            ])),
            new NbtNamedTag("structure_world_origin", new NbtListValue(NbtTagType.Int, [
                new NbtIntValue(region.Minimum.X), new NbtIntValue(region.Minimum.Y), new NbtIntValue(region.Minimum.Z)
            ])),
            new NbtNamedTag("structure", new NbtCompoundValue([
                new NbtNamedTag("block_indices", new NbtListValue(NbtTagType.List, [
                    new NbtListValue(NbtTagType.Int, primary.Select(value => (NbtValue)new NbtIntValue(value)).ToArray()),
                    new NbtListValue(NbtTagType.Int, secondary.Select(value => (NbtValue)new NbtIntValue(value)).ToArray())
                ])),
                new NbtNamedTag("entities", new NbtListValue(NbtTagType.End, [])),
                new NbtNamedTag("palette", new NbtCompoundValue([
                    new NbtNamedTag("default", new NbtCompoundValue([
                        new NbtNamedTag("block_palette", new NbtListValue(NbtTagType.Compound, palette)),
                        new NbtNamedTag("block_position_data", new NbtCompoundValue(positionTags))
                    ]))
                ]))
            ]))
        ]));
    }

    public string LoadStructureDocument(NbtDocument document, int targetDimension, BedrockBlockCoordinate destination)
    {
        var parsed = ParseStructureDocument(document);
        int maxX, maxY, maxZ;
        try
        {
            maxX = checked(destination.X + parsed.SizeX - 1);
            maxY = checked(destination.Y + parsed.SizeY - 1);
            maxZ = checked(destination.Z + parsed.SizeZ - 1);
        }
        catch (OverflowException)
        {
            throw new InvalidDataException("structure load 目标坐标溢出。");
        }
        var target = new BedrockBlockBox(destination, new BedrockBlockCoordinate(maxX, maxY, maxZ));
        ValidateRegion(target);
        var cache = new RegionEditCache(_database, _access, targetDimension);
        var writtenCoordinates = new HashSet<BedrockBlockCoordinate>();
        long changedLayers = 0;

        foreach (var slice in EnumerateSlices(target))
        {
            if (!EnumerateCells(slice).Any(cell => parsed.StatesAt(StructureFlatIndex(destination, parsed, cell.X, cell.Y, cell.Z)).Any(state => state is not null))) continue;
            var working = cache.GetForClone(slice.Chunk, slice.SubChunkY);
            var byLayer = new Dictionary<int, Dictionary<int, BedrockBlockState>>();
            foreach (var cell in EnumerateCells(slice))
            {
                var flat = StructureFlatIndex(destination, parsed, cell.X, cell.Y, cell.Z);
                var states = parsed.StatesAt(flat);
                var wrote = states.Any(state => state is not null);
                for (var layer = 0; layer < states.Length; layer++)
                {
                    if (states[layer] is not { } state) continue;
                    var adapted = AdaptState(state, working, layer);
                    if (layer >= working.Storages.Count && adapted.IsAir) continue;
                    if (!byLayer.TryGetValue(layer, out var replacements)) byLayer[layer] = replacements = [];
                    replacements[cell.FlatIndex] = adapted;
                    changedLayers++;
                }
                if (wrote) writtenCoordinates.Add(new BedrockBlockCoordinate(cell.X, cell.Y, cell.Z));
            }
            foreach (var layer in byLayer.OrderBy(pair => pair.Key)) working = working.ReplacingStorageBlocks(layer.Key, layer.Value);
            cache.Set(slice.Chunk, slice.SubChunkY, working);
        }

        var blockEntities = PlanStructureBlockEntities(targetDimension, target, destination, parsed, writtenCoordinates);
        var result = Commit(cache, blockEntities.Puts, blockEntities.Deletes, writtenCoordinates.Count, blockEntities.Removed, blockEntities.Copied);
        return $"写入 {result.TouchedSubChunks} 个 SubChunk，修改 {changedLayers} 个图层方块，处理 {blockEntities.TouchedChunks} 个方块实体区块。";
    }

    private BlockEntityMutationWithChunks PlanStructureBlockEntities(int dimension, BedrockBlockBox target,
        BedrockBlockCoordinate destination, ParsedStructureDocument parsed, IReadOnlySet<BedrockBlockCoordinate> written)
    {
        var targetByChunk = new Dictionary<ChunkPosition, List<ConsecutiveNbtRecord>>();
        var targetEncoding = new Dictionary<ChunkPosition, NbtEncoding>();
        var originalKeys = new Dictionary<ChunkPosition, byte[]>();
        var originalHadValue = new HashSet<ChunkPosition>();
        var removed = 0;
        var touched = new HashSet<ChunkPosition>();
        foreach (var chunk in EnumerateChunks(dimension, target))
        {
            var key = new BedrockDbKey(chunk, ChunkRecordType.BlockEntity, null).Encode();
            originalKeys[chunk] = key;
            var raw = _database.Get(key);
            if (raw is not null) originalHadValue.Add(chunk);
            var records = raw is null ? [] : ConsecutiveNbtCodec.Decode(raw).ToList();
            if (records.Count > 0)
            {
                var encoding = records[0].Encoding;
                if (records.Any(record => record.Encoding != encoding))
                    throw new InvalidDataException("目标 BlockEntity 记录包含混合 NBT 编码，无法安全执行 structure load。");
                targetEncoding[chunk] = encoding;
            }
            var kept = new List<ConsecutiveNbtRecord>();
            foreach (var record in records)
            {
                var pos = BedrockWorldObjectScanner.ExtractPosition(record.Document.Root, BedrockWorldObjectKind.BlockEntity);
                var coordinate = pos is null ? (BedrockBlockCoordinate?)null : new BedrockBlockCoordinate(pos.BlockX, pos.BlockY, pos.BlockZ);
                if (coordinate.HasValue && written.Contains(coordinate.Value)) { removed++; touched.Add(chunk); }
                else kept.Add(record);
            }
            targetByChunk[chunk] = kept;
        }

        var copied = 0;
        foreach (var pair in parsed.BlockEntities)
        {
            var flat = pair.Key;
            if (flat < 0 || flat >= parsed.Volume) continue;
            var dx = flat / (parsed.SizeY * parsed.SizeZ);
            var rem = flat % (parsed.SizeY * parsed.SizeZ);
            var dy = rem / parsed.SizeZ;
            var dz = rem % parsed.SizeZ;
            var coordinate = new BedrockBlockCoordinate(checked(destination.X + dx), checked(destination.Y + dy), checked(destination.Z + dz));
            if (!written.Contains(coordinate)) continue;
            var chunk = new ChunkPosition(FloorDiv(coordinate.X, 16), FloorDiv(coordinate.Z, 16), dimension);
            if (!targetByChunk.TryGetValue(chunk, out var list)) targetByChunk[chunk] = list = [];
            var encoding = targetEncoding.TryGetValue(chunk, out var existing) ? existing : NbtEncoding.LittleEndian;
            targetEncoding[chunk] = encoding;
            var document = OffsetBlockEntity(pair.Value, coordinate.X, coordinate.Y, coordinate.Z, dimension);
            list.Add(new ConsecutiveNbtRecord(document, BedrockNbtCodec.Encode(document, encoding), encoding));
            copied++;
            touched.Add(chunk);
        }

        var puts = new List<WorldDatabasePut>();
        var deletes = new List<byte[]>();
        foreach (var pair in targetByChunk)
        {
            var key = originalKeys[pair.Key];
            if (pair.Value.Count == 0)
            {
                if (originalHadValue.Contains(pair.Key) && touched.Contains(pair.Key)) deletes.Add(key);
            }
            else if (touched.Contains(pair.Key)) puts.Add(new WorldDatabasePut(key, ConsecutiveNbtCodec.Encode(pair.Value)));
        }
        return new BlockEntityMutationWithChunks(puts, deletes, removed, copied, touched.Count);
    }

    private static int StructureFlatIndex(BedrockBlockCoordinate destination, ParsedStructureDocument parsed, int x, int y, int z)
        => checked((x - destination.X) * parsed.SizeY * parsed.SizeZ + (y - destination.Y) * parsed.SizeZ + (z - destination.Z));

    private static BedrockBlockState StructureAir(BedrockBlockState reference)
        => reference.Nbt is null ? new BedrockBlockState(null, 0, 0) : BedrockBlockState.EditableAir(reference.PaletteVersion);

    private static ParsedStructureDocument ParseStructureDocument(NbtDocument document)
    {
        if (document.Root is not NbtCompoundValue root) throw new InvalidDataException("结构 NBT 根必须是 Compound。");
        var size = IntegerVector(root.CompoundValue("size"));
        var structure = root.CompoundValue("structure") as NbtCompoundValue;
        var indices = structure?.CompoundValue("block_indices") as NbtListValue;
        var paletteDefault = structure?.CompoundValue("palette")?.CompoundValue("default") as NbtCompoundValue;
        var paletteValue = paletteDefault?.CompoundValue("block_palette") as NbtListValue;
        if (size is null || size.Count < 3 || size[0] <= 0 || size[1] <= 0 || size[2] <= 0
            || size.Any(value => value > int.MaxValue) || indices is null || indices.ElementType != NbtTagType.List
            || paletteValue is null || paletteValue.ElementType != NbtTagType.Compound)
            throw new InvalidDataException("结构缺少 size、structure.block_indices 或 default.block_palette。");
        var sizeX = checked((int)size[0]);
        var sizeY = checked((int)size[1]);
        var sizeZ = checked((int)size[2]);
        var volumeLong = checked((long)sizeX * sizeY * sizeZ);
        if (volumeLong > 16_777_216) throw new NotSupportedException("结构体积过大。");
        var volume = (int)volumeLong;

        var layers = new List<int[]>();
        foreach (var layer in indices.Values.Take(2))
        {
            if (layer is not NbtListValue { ElementType: NbtTagType.Int } values)
                throw new InvalidDataException("structure.block_indices 图层必须是 Int List。");
            var normalized = values.Values.Select(value => value is NbtIntValue number ? number.Value
                : throw new InvalidDataException("structure.block_indices 包含非 Int 值。")).Take(volume).ToList();
            while (normalized.Count < volume) normalized.Add(-1);
            layers.Add(normalized.ToArray());
        }
        while (layers.Count < 2) layers.Add(Enumerable.Repeat(-1, volume).ToArray());

        var palette = paletteValue.Values.Select(value =>
        {
            if (value is not NbtCompoundValue compound) throw new InvalidDataException("结构 block_palette 条目不是 Compound。");
            return new BedrockBlockState(NbtDocumentTools.DeepClone(compound), null, null);
        }).ToArray();
        if (palette.Length == 0) throw new InvalidDataException("结构调色板为空。");
        foreach (var layer in layers)
            foreach (var index in layer)
                if (index < -1 || index >= palette.Length) throw new InvalidDataException($"结构方块索引超出调色板范围：{index}");

        var entities = new Dictionary<int, NbtDocument>();
        if (paletteDefault?.CompoundValue("block_position_data") is NbtCompoundValue positions)
        {
            foreach (var tag in positions.Tags)
            {
                if (!int.TryParse(tag.Name, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var flat)
                    || flat < 0 || flat >= volume || tag.Value is not NbtCompoundValue entry
                    || entry.CompoundValue("block_entity_data") is not NbtCompoundValue entityRoot) continue;
                entities[flat] = new NbtDocument(string.Empty, NbtDocumentTools.DeepClone(entityRoot));
            }
        }
        return new ParsedStructureDocument(sizeX, sizeY, sizeZ, layers.ToArray(), palette, entities);
    }

    private static IReadOnlyList<long>? IntegerVector(NbtValue? value)
    {
        if (value is NbtIntArrayValue ints) return ints.Values.Select(number => (long)number).ToArray();
        if (value is NbtLongArrayValue longs) return longs.Values.ToArray();
        if (value is not NbtListValue list) return null;
        var result = new List<long>(list.Values.Count);
        foreach (var item in list.Values)
        {
            var number = item.IntegerValue();
            if (!number.HasValue) return null;
            result.Add(number.Value);
        }
        return result;
    }

    private sealed record ParsedStructureDocument(int SizeX, int SizeY, int SizeZ, int[][] Layers,
        BedrockBlockState[] Palette, IReadOnlyDictionary<int, NbtDocument> BlockEntities)
    {
        public int Volume => checked(SizeX * SizeY * SizeZ);
        public BedrockBlockState?[] StatesAt(int flat)
        {
            var result = new BedrockBlockState?[2];
            for (var layer = 0; layer < 2; layer++)
            {
                var raw = Layers[layer][flat];
                result[layer] = raw == -1 ? null : Palette[raw];
            }
            return result;
        }
    }

    private sealed record BlockEntityMutationWithChunks(IReadOnlyList<WorldDatabasePut> Puts, IReadOnlyList<byte[]> Deletes,
        int Removed, int Copied, int TouchedChunks);

    public string GetBlockText(int dimension, BedrockBlockCoordinate position)
    {
        var chunk = new ChunkPosition(FloorDiv(position.X, 16), FloorDiv(position.Z, 16), dimension);
        var block = new BedrockBlockStore(_database).ReadBlock(dimension, position.X, position.Y, position.Z);
        IReadOnlyList<BedrockBlockState>? layers = block.Generated ? block.Layers : null;
        if (layers is null)
        {
            var summary = new BedrockChunkStore(_database).SummaryAt(chunk);
            var chunkExists = summary.HasTerrain || summary.BiomeRecordType is not null || summary.HasBlockEntities
                || summary.HasLegacyEntities || summary.RecordCount > (summary.HasActorDigest ? 1 : 0);
            if (chunkExists)
            {
                var format = BedrockEmptyChunkMetadata.DetectBlockFormat(_database, dimension, chunk);
                layers = [format.Air];
            }
        }
        var blockText = layers is null
            ? "Block=NULL"
            : "Block=[" + string.Join(",", layers.Select((state, layer)
                => $"Storage{layer}=[{BlockCommandNbtOutputFormatter.BlockState(state)}]")) + "]";

        var beKey = new BedrockDbKey(chunk, ChunkRecordType.BlockEntity, null).Encode();
        var raw = _database.Get(beKey);
        string? blockEntityText = null;
        if (raw is not null)
        {
            foreach (var record in ConsecutiveNbtCodec.Decode(raw))
            {
                var pos = BedrockWorldObjectScanner.ExtractPosition(record.Document.Root, BedrockWorldObjectKind.BlockEntity);
                if (pos?.BlockX == position.X && pos.BlockY == position.Y && pos.BlockZ == position.Z)
                {
                    blockEntityText = "BlockEntity=[" + BlockCommandNbtOutputFormatter.Root(record.Document.Root) + "]";
                    break;
                }
            }
        }
        return blockText + Environment.NewLine + (blockEntityText ?? "BlockEntity=NULL");
    }

    private BedrockRegionMutationResult Commit(
        RegionEditCache cache,
        IReadOnlyList<WorldDatabasePut> extraPuts,
        IReadOnlyList<byte[]> extraDeletes,
        long changed,
        int removedBlockEntities,
        int copiedBlockEntities)
    {
        var puts = cache.PersistentPuts().Concat(extraPuts).ToList();
        var deletes = extraDeletes.Select(key => key.ToArray()).ToList();
        var finalPuts = CoalescePuts(puts);
        var finalDeletes = DistinctKeys(deletes)
            .Where(key => !finalPuts.Any(put => put.Key.AsSpan().SequenceEqual(key)))
            .ToArray();
        if (finalPuts.Count == 0 && finalDeletes.Length == 0)
            throw new InvalidOperationException("区域内没有产生任何可写入变化。");
        _database.ApplyBatch(finalPuts, finalDeletes, sync: true);
        return new BedrockRegionMutationResult(changed, cache.EditedSubChunkCount, cache.EditedChunkCount,
            removedBlockEntities, copiedBlockEntities, finalPuts.Count, finalDeletes.Length);
    }

    private BlockEntityMutation PlanRemoveBlockEntities(int dimension, BedrockBlockBox region)
    {
        var puts = new List<WorldDatabasePut>();
        var deletes = new List<byte[]>();
        var removed = 0;
        foreach (var chunk in EnumerateChunks(dimension, region))
        {
            var key = new BedrockDbKey(chunk, ChunkRecordType.BlockEntity, null).Encode();
            var raw = _database.Get(key);
            if (raw is null) continue;
            var records = ConsecutiveNbtCodec.Decode(raw).ToList();
            var kept = new List<ConsecutiveNbtRecord>(records.Count);
            foreach (var record in records)
            {
                var pos = BedrockWorldObjectScanner.ExtractPosition(record.Document.Root, BedrockWorldObjectKind.BlockEntity);
                if (pos is not null && region.Contains(pos.BlockX, pos.BlockY, pos.BlockZ)) removed++;
                else kept.Add(record);
            }
            if (kept.Count == records.Count) continue;
            if (kept.Count == 0) deletes.Add(key); else puts.Add(new WorldDatabasePut(key, ConsecutiveNbtCodec.Encode(kept)));
        }
        return new BlockEntityMutation(puts, deletes, removed, 0);
    }

    private BlockEntityMutation PlanCloneBlockEntities(
        int sourceDimension,
        BedrockBlockBox source,
        int targetDimension,
        BedrockBlockBox target,
        BedrockBlockCoordinate destination)
    {
        var sourceRecords = new List<ConsecutiveNbtRecord>();
        var sourceCoordinates = new HashSet<BedrockBlockCoordinate>();
        foreach (var chunk in EnumerateChunks(sourceDimension, source))
        {
            var key = new BedrockDbKey(chunk, ChunkRecordType.BlockEntity, null).Encode();
            var raw = _database.Get(key);
            if (raw is null) continue;
            foreach (var record in ConsecutiveNbtCodec.Decode(raw))
            {
                var pos = BedrockWorldObjectScanner.ExtractPosition(record.Document.Root, BedrockWorldObjectKind.BlockEntity);
                if (pos is null || !source.Contains(pos.BlockX, pos.BlockY, pos.BlockZ)) continue;
                var coordinate = new BedrockBlockCoordinate(pos.BlockX, pos.BlockY, pos.BlockZ);
                if (!sourceCoordinates.Add(coordinate))
                    throw new InvalidDataException($"源区域在 {coordinate.X},{coordinate.Y},{coordinate.Z} 存在重复 BlockEntity，无法安全执行 clone。");
                sourceRecords.Add(record);
            }
        }

        var targetByChunk = new Dictionary<ChunkPosition, List<ConsecutiveNbtRecord>>();
        var targetEncoding = new Dictionary<ChunkPosition, NbtEncoding>();
        var originalKeys = new Dictionary<ChunkPosition, byte[]>();
        var originalHadValue = new HashSet<ChunkPosition>();
        var removed = 0;
        foreach (var chunk in EnumerateChunks(targetDimension, target))
        {
            var key = new BedrockDbKey(chunk, ChunkRecordType.BlockEntity, null).Encode();
            originalKeys[chunk] = key;
            var raw = _database.Get(key);
            if (raw is not null) originalHadValue.Add(chunk);
            var records = raw is null ? new List<ConsecutiveNbtRecord>() : ConsecutiveNbtCodec.Decode(raw).ToList();
            if (records.Count > 0)
            {
                var encoding = records[0].Encoding;
                if (records.Any(record => record.Encoding != encoding))
                    throw new InvalidDataException("目标 BlockEntity 记录包含混合 NBT 编码，无法安全执行 clone。");
                targetEncoding[chunk] = encoding;
            }
            var kept = new List<ConsecutiveNbtRecord>();
            foreach (var record in records)
            {
                var pos = BedrockWorldObjectScanner.ExtractPosition(record.Document.Root, BedrockWorldObjectKind.BlockEntity);
                if (pos is not null && target.Contains(pos.BlockX, pos.BlockY, pos.BlockZ)) removed++;
                else kept.Add(record);
            }
            targetByChunk[chunk] = kept;
        }

        var copied = 0;
        checked
        {
            var dx = destination.X - source.Minimum.X;
            var dy = destination.Y - source.Minimum.Y;
            var dz = destination.Z - source.Minimum.Z;
            foreach (var record in sourceRecords)
            {
                var pos = BedrockWorldObjectScanner.ExtractPosition(record.Document.Root, BedrockWorldObjectKind.BlockEntity)!;
                var x = pos.BlockX + dx;
                var y = pos.BlockY + dy;
                var z = pos.BlockZ + dz;
                var chunk = new ChunkPosition(FloorDiv(x, 16), FloorDiv(z, 16), targetDimension);
                if (!targetByChunk.TryGetValue(chunk, out var list)) targetByChunk[chunk] = list = [];
                var encoding = targetEncoding.TryGetValue(chunk, out var existingEncoding) ? existingEncoding : record.Encoding;
                targetEncoding[chunk] = encoding;
                var document = OffsetBlockEntity(record.Document, x, y, z, targetDimension);
                list.Add(new ConsecutiveNbtRecord(document, BedrockNbtCodec.Encode(document, encoding), encoding));
                copied++;
            }
        }

        var puts = new List<WorldDatabasePut>();
        var deletes = new List<byte[]>();
        foreach (var pair in targetByChunk)
        {
            var key = originalKeys.TryGetValue(pair.Key, out var original) ? original : new BedrockDbKey(pair.Key, ChunkRecordType.BlockEntity, null).Encode();
            if (pair.Value.Count == 0)
            {
                if (originalHadValue.Contains(pair.Key)) deletes.Add(key);
            }
            else puts.Add(new WorldDatabasePut(key, ConsecutiveNbtCodec.Encode(pair.Value)));
        }
        return new BlockEntityMutation(puts, deletes, removed, copied);
    }


    private IReadOnlyList<WorldDatabasePut> PlanMissingChunkMetadata(
        int dimension,
        BedrockBlockBox region,
        IReadOnlySet<ChunkPosition>? exclude)
    {
        var profile = BedrockEmptyChunkMetadata.DetectProfile(_database, dimension);
        var puts = new List<WorldDatabasePut>();
        foreach (var chunk in EnumerateChunks(dimension, region))
        {
            if (exclude is not null && exclude.Contains(chunk)) continue;
            if (ChunkHasAnyRecord(chunk)) continue;
            puts.AddRange(BedrockEmptyChunkMetadata.Records(chunk, profile)
                .Select(record => new WorldDatabasePut(record.Key, record.Value)));
        }
        return puts;
    }

    private bool ChunkHasAnyRecord(ChunkPosition position)
    {
        foreach (var entry in _database.Entries(BedrockChunkStore.CoordinatePrefix(position.X, position.Z), includeValues: false))
        {
            if (BedrockDbKey.TryParse(entry.Key, out var key) && key.Position == position) return true;
        }
        return false;
    }

    private IReadOnlyDictionary<SubChunkAddress, BedrockStoredSubChunk?> SnapshotSubChunks(int dimension, BedrockBlockBox region)
    {
        var output = new Dictionary<SubChunkAddress, BedrockStoredSubChunk?>();
        foreach (var slice in EnumerateSlices(region))
        {
            var key = new SubChunkAddress(slice.Chunk with { Dimension = dimension }, slice.SubChunkY);
            if (!output.ContainsKey(key)) output[key] = _access.Record(key.Chunk, key.Y);
        }
        return output;
    }

    private static IReadOnlyList<BedrockBlockState> SnapshotLayers(
        IReadOnlyDictionary<SubChunkAddress, BedrockStoredSubChunk?> snapshot,
        int dimension,
        int x,
        int y,
        int z)
    {
        var address = Address(dimension, x, y, z);
        if (!snapshot.TryGetValue(new SubChunkAddress(address.Chunk, address.SubChunkY), out var stored) || stored is null)
            return [];
        if (stored.SubChunk.IsRawPreservedUnknownVersion)
            throw new NotSupportedException($"clone 源区域包含未知 SubChunk v{stored.SubChunk.Version}，无法确认其中方块内容，已拒绝按空气复制。");
        return stored.SubChunk.Storages.Select(storage => storage.BlockState(address.LocalX, address.LocalY, address.LocalZ)
            ?? AirForStorage(storage, stored.SubChunk.IsLegacyNumeric)).ToArray();
    }

    private static BedrockBlockState SourceAir(IReadOnlyList<BedrockBlockState> source, BedrockSubChunk target, int layer)
    {
        if (source.FirstOrDefault(state => state.Nbt is not null) is { } modern)
            return BedrockBlockState.EditableAir(modern.PaletteVersion);
        if (source.Any(state => state.Nbt is null && state.LegacyId.HasValue)) return new BedrockBlockState(null, 0, 0);
        if (target.IsLegacyNumeric) return new BedrockBlockState(null, 0, 0);
        var version = layer < target.Storages.Count
            ? target.Storages[layer].Palette.Select(state => state.PaletteVersion).FirstOrDefault(value => value.HasValue)
            : PaletteVersion(target);
        return BedrockBlockState.EditableAir(version);
    }

    private static BedrockBlockState AdaptState(BedrockBlockState source, BedrockSubChunk target, int layer)
    {
        if (target.IsLegacyNumeric)
        {
            if (layer > 1) throw new NotSupportedException("旧版数字 ID 只支持 storage 0/1。");
            if (source.Nbt is null) return source;
            if (source.IsAir) return new BedrockBlockState(null, 0, 0);
            if (BedrockLegacyBlockCatalog.NumericIdForIdentifier(source.Name) is ushort id
                && BedrockLegacyBlockStateConverter.NumericData(source) is byte data
                && (layer == 1 || data <= 15))
                return new BedrockBlockState(null, id, data);
            throw new NotSupportedException("clone 源方块无法由目标存档的旧版数字 ID 格式表示。");
        }
        var modern = source.Nbt is not null ? source : BedrockLegacyBlockStateConverter.StateForNumeric(source);
        return BedrockLegacyBlockStateConverter.ForPalette(modern,
            BedrockPaletteFormat.Detect(target.Storages.SelectMany(storage => storage.Palette)));
    }

    private static NbtDocument OffsetBlockEntity(NbtDocument source, int x, int y, int z, int dimension)
    {
        var root = SetTopLevel(source.Root, ["x", "X"], "x", new NbtIntValue(x));
        root = SetTopLevel(root, ["y", "Y"], "y", new NbtIntValue(y));
        root = SetTopLevel(root, ["z", "Z"], "z", new NbtIntValue(z));
        if (source.Root.CompoundValueIgnoreCase("DimensionId", "DimensionID", "dimensionId", "dimension", "Dimension") is not null)
            root = SetTopLevel(root, ["DimensionId", "DimensionID", "dimensionId", "dimension", "Dimension"], "DimensionId", new NbtIntValue(dimension));
        return new NbtDocument(source.RootName, root);
    }

    private static NbtValue SetTopLevel(NbtValue root, IReadOnlyList<string> names, string preferredName, NbtValue value)
    {
        if (root is not NbtCompoundValue compound) throw new InvalidDataException("BlockEntity NBT 根必须是 Compound。");
        var tags = compound.Tags.Select(tag => new NbtNamedTag(tag.Name, NbtDocumentTools.DeepClone(tag.Value))).ToList();
        var index = tags.FindIndex(tag => names.Any(name => string.Equals(tag.Name, name, StringComparison.OrdinalIgnoreCase)));
        var replacement = new NbtNamedTag(index >= 0 ? tags[index].Name : preferredName, NbtDocumentTools.DeepClone(value));
        if (index >= 0) tags[index] = replacement; else tags.Add(replacement);
        return new NbtCompoundValue(tags);
    }

    private static int? PaletteVersion(BedrockSubChunk subChunk)
        => subChunk.Storages.SelectMany(storage => storage.Palette).Select(state => state.PaletteVersion).FirstOrDefault(value => value.HasValue);

    private static BedrockBlockState AirForStorage(SubChunkStorage storage, bool legacy)
        => legacy ? new BedrockBlockState(null, 0, 0)
            : storage.Palette.FirstOrDefault(state => state.Nbt is not null && state.IsAir)
              ?? BedrockBlockState.EditableAir(storage.Palette.Select(state => state.PaletteVersion).FirstOrDefault(value => value.HasValue));

    private static void ValidateStorages(IReadOnlyList<BedrockBlockStorageSpec> storages)
    {
        if (storages.Count is < 1 or > byte.MaxValue) throw new InvalidDataException("fill/setblock 必须提供 1…255 个 storage。");
    }

    private static void ValidateRegion(BedrockBlockBox region)
    {
        long volume;
        try { volume = region.Volume; }
        catch (OverflowException) { throw new InvalidDataException("区域体积溢出。"); }
        if (volume <= 0 || volume > MaximumVolume)
            throw new NotSupportedException($"一次区域操作最多处理 {MaximumVolume:N0} 个方块；当前为 {volume:N0}。");
        _ = ToSubChunkY(region.Minimum.Y);
        _ = ToSubChunkY(region.Maximum.Y);
    }

    private static IEnumerable<RegionSlice> EnumerateSlices(BedrockBlockBox region)
    {
        var minChunkX = FloorDiv(region.Minimum.X, 16);
        var maxChunkX = FloorDiv(region.Maximum.X, 16);
        var minChunkZ = FloorDiv(region.Minimum.Z, 16);
        var maxChunkZ = FloorDiv(region.Maximum.Z, 16);
        var minSubY = ToSubChunkY(region.Minimum.Y);
        var maxSubY = ToSubChunkY(region.Maximum.Y);
        for (var chunkX = minChunkX; ; chunkX++)
        {
            for (var chunkZ = minChunkZ; ; chunkZ++)
            {
                for (var subY = (int)minSubY; subY <= maxSubY; subY++)
                {
                    var originX = chunkX * 16;
                    var originY = subY * 16;
                    var originZ = chunkZ * 16;
                    var minX = Math.Max(0, region.Minimum.X - originX);
                    var maxX = Math.Min(15, region.Maximum.X - originX);
                    var minY = Math.Max(0, region.Minimum.Y - originY);
                    var maxY = Math.Min(15, region.Maximum.Y - originY);
                    var minZ = Math.Max(0, region.Minimum.Z - originZ);
                    var maxZ = Math.Min(15, region.Maximum.Z - originZ);
                    if (minX <= maxX && minY <= maxY && minZ <= maxZ)
                        yield return new RegionSlice(new ChunkPosition(chunkX, chunkZ, 0), (sbyte)subY, minX, maxX, minY, maxY, minZ, maxZ);
                }
                if (chunkZ == maxChunkZ) break;
            }
            if (chunkX == maxChunkX) break;
        }
    }

    private static IEnumerable<RegionCell> EnumerateCells(RegionSlice slice)
    {
        var originX = checked(slice.Chunk.X * 16);
        var originY = checked((int)slice.SubChunkY * 16);
        var originZ = checked(slice.Chunk.Z * 16);
        for (var localX = slice.MinX; localX <= slice.MaxX; localX++)
        for (var localZ = slice.MinZ; localZ <= slice.MaxZ; localZ++)
        for (var localY = slice.MinY; localY <= slice.MaxY; localY++)
            yield return new RegionCell(
                originX + localX, originY + localY, originZ + localZ,
                (localX << 8) | (localZ << 4) | localY);
    }

    private static IEnumerable<int> FlatIndices(RegionSlice slice)
    {
        for (var x = slice.MinX; x <= slice.MaxX; x++)
        for (var z = slice.MinZ; z <= slice.MaxZ; z++)
        for (var y = slice.MinY; y <= slice.MaxY; y++)
            yield return (x << 8) | (z << 4) | y;
    }

    private static IEnumerable<ChunkPosition> EnumerateChunks(int dimension, BedrockBlockBox region)
    {
        var minX = FloorDiv(region.Minimum.X, 16);
        var maxX = FloorDiv(region.Maximum.X, 16);
        var minZ = FloorDiv(region.Minimum.Z, 16);
        var maxZ = FloorDiv(region.Maximum.Z, 16);
        for (var x = minX; ; x++)
        {
            for (var z = minZ; ; z++)
            {
                yield return new ChunkPosition(x, z, dimension);
                if (z == maxZ) break;
            }
            if (x == maxX) break;
        }
    }

    private static BedrockBlockAddress Address(int dimension, int x, int y, int z)
    {
        var chunkX = FloorDiv(x, 16);
        var chunkZ = FloorDiv(z, 16);
        var subY = ToSubChunkY(y);
        return new BedrockBlockAddress(new ChunkPosition(chunkX, chunkZ, dimension), subY,
            Mod(x, 16), Mod(y, 16), Mod(z, 16));
    }

    private static sbyte ToSubChunkY(int y)
    {
        var value = FloorDiv(y, 16);
        if (value < sbyte.MinValue || value > sbyte.MaxValue)
            throw new NotSupportedException($"Y={y} 超出 Bedrock SubChunk Int8 索引范围。");
        return (sbyte)value;
    }

    private static int FloorDiv(int value, int divisor)
    {
        var quotient = value / divisor;
        var remainder = value % divisor;
        return remainder < 0 ? quotient - 1 : quotient;
    }

    private static int Mod(int value, int divisor)
    {
        var remainder = value % divisor;
        return remainder < 0 ? remainder + divisor : remainder;
    }

    private static IReadOnlyList<WorldDatabasePut> CoalescePuts(IEnumerable<WorldDatabasePut> puts)
        => puts.GroupBy(item => Convert.ToHexString(item.Key), StringComparer.Ordinal).Select(group => group.Last()).ToArray();

    private static IReadOnlyList<byte[]> DistinctKeys(IEnumerable<byte[]> keys)
        => keys.GroupBy(key => Convert.ToHexString(key), StringComparer.Ordinal).Select(group => group.First()).ToArray();

    private sealed record BlockEntityMutation(IReadOnlyList<WorldDatabasePut> Puts, IReadOnlyList<byte[]> Deletes, int Removed, int Copied);
    private readonly record struct SubChunkAddress(ChunkPosition Chunk, sbyte Y);
    private readonly record struct RegionSlice(ChunkPosition Chunk, sbyte SubChunkY, int MinX, int MaxX, int MinY, int MaxY, int MinZ, int MaxZ)
    {
        public long Volume => (long)(MaxX - MinX + 1) * (MaxY - MinY + 1) * (MaxZ - MinZ + 1);
    }

    private readonly record struct RegionCell(int X, int Y, int Z, int FlatIndex);

    private readonly record struct BedrockBlockAddress(ChunkPosition Chunk, sbyte SubChunkY, int LocalX, int LocalY, int LocalZ)
    {
        public int FlatIndex => (LocalX << 8) | (LocalZ << 4) | LocalY;
    }

    private sealed class RegionEditCache
    {
        private readonly IWorldDatabase _database;
        private readonly BedrockChunkSubChunkAccess _access;
        private readonly int _dimension;
        private readonly BedrockEmptyChunkProfile _profile;
        private BedrockBlockFormat? _dimensionBlockFormat;
        private readonly Dictionary<ChunkPosition, BedrockBlockFormat> _blockFormats = new();
        private readonly Dictionary<SubChunkAddress, BedrockStoredSubChunk?> _original = [];
        private readonly Dictionary<SubChunkAddress, BedrockSubChunk> _current = [];

        public RegionEditCache(IWorldDatabase database, BedrockChunkSubChunkAccess access, int dimension)
        {
            _database = database; _access = access; _dimension = dimension;
            _profile = BedrockEmptyChunkMetadata.DetectProfile(database, dimension);
        }

        public int EditedSubChunkCount => _current.Count;
        public int EditedChunkCount => _current.Keys.Select(key => key.Chunk).Distinct().Count();


        public BedrockSubChunk GetForFill(ChunkPosition chunk, sbyte y, IReadOnlyList<BedrockBlockStorageSpec> specs)
        {
            chunk = chunk with { Dimension = _dimension };
            var key = new SubChunkAddress(chunk, y);
            if (_current.TryGetValue(key, out var cached)) return cached;
            EnsureOriginal(key);
            if (_original[key] is { } stored) return _current[key] = stored.SubChunk;

            var canLegacy = specs.Count <= 2 && specs.Select((spec, index) => spec.CanRemainLegacy(index)).All(value => value);
            if (_profile.UsesLegacyTerrain)
            {
                if (!canLegacy || y is < 0 or > 7) throw new NotSupportedException("LegacyTerrain 目标只能写入 Y=0…127 的旧版数字 ID 方块。");
                return _current[key] = BedrockSubChunk.EmptyLegacy(0, y);
            }
            var format = BlockFormat(chunk);
            if (format.IsLegacyNumeric)
            {
                if (!canLegacy) throw new NotSupportedException("目标存档使用旧版数字 ID，无法表示这些 states 或 storage 层数。");
                return _current[key] = BedrockSubChunk.EmptyLegacy(format.SubChunkVersion, y);
            }
            return _current[key] = new BedrockSubChunk(format.SubChunkVersion, y,
                [SubChunkStorage.AirFilled(format.Air)], []);
        }

        public BedrockSubChunk GetForClone(ChunkPosition chunk, sbyte y)
        {
            chunk = chunk with { Dimension = _dimension };
            var key = new SubChunkAddress(chunk, y);
            if (_current.TryGetValue(key, out var cached)) return cached;
            EnsureOriginal(key);
            if (_original[key] is { } stored) return _current[key] = stored.SubChunk;

            var format = BlockFormat(chunk);
            if (_profile.UsesLegacyTerrain)
            {
                if (y is < 0 or > 7) throw new NotSupportedException("clone 目标维度使用 LegacyTerrain，无法创建现代目标 SubChunk。");
                return _current[key] = BedrockSubChunk.EmptyLegacy(0, y);
            }
            if (format.IsLegacyNumeric)
                return _current[key] = BedrockSubChunk.EmptyLegacy(format.SubChunkVersion, y);
            return _current[key] = new BedrockSubChunk(format.SubChunkVersion, y,
                [SubChunkStorage.AirFilled(format.Air)], []);
        }

        private BedrockBlockFormat BlockFormat(ChunkPosition chunk)
        {
            if (_blockFormats.TryGetValue(chunk, out var format)) return format;
            _dimensionBlockFormat ??= BedrockEmptyChunkMetadata.DetectBlockFormat(_database, _dimension);
            return _blockFormats[chunk] = BedrockEmptyChunkMetadata.DetectBlockFormat(
                _database, _dimension, chunk, _dimensionBlockFormat);
        }

        public void Set(ChunkPosition chunk, sbyte y, BedrockSubChunk value)
        {
            chunk = chunk with { Dimension = _dimension };
            var key = new SubChunkAddress(chunk, y);
            EnsureOriginal(key);
            _current[key] = value;
        }

        public IReadOnlyList<WorldDatabasePut> PersistentPuts()
        {
            var puts = new List<WorldDatabasePut>();
            foreach (var group in _current.GroupBy(pair => pair.Key.Chunk))
            {
                var edits = group.ToDictionary(pair => pair.Key.Y, pair => pair.Value);
                var preferLegacyTerrain = _profile.UsesLegacyTerrain && group.All(pair => _original[pair.Key] is null);
                puts.AddRange(_access.PersistentPuts(group.Key, edits, preferLegacyTerrain, _profile));
            }
            return puts;
        }

        private void EnsureOriginal(SubChunkAddress key)
        {
            if (!_original.ContainsKey(key)) _original[key] = _access.Record(key.Chunk, key.Y);
        }


    }
}
