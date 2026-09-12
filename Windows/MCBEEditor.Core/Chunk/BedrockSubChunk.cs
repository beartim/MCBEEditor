using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.Chunk;

public sealed record BedrockBlockState(NbtValue? Nbt, ushort? LegacyId, byte? LegacyData)
{
    public const int DefaultPaletteVersion = 18_153_728;

    public string Name
    {
        get
        {
            if (Nbt is not null)
            {
                if (Nbt.CompoundValue("name") is NbtStringValue lower) return lower.Value;
                if (Nbt.CompoundValue("Name") is NbtStringValue upper) return upper.Value;
                return "minecraft:unknown";
            }
            return LegacyId is ushort id ? BedrockLegacyBlockCatalog.IdentifierForNumericId(id) ?? $"legacy:{id}:{LegacyData ?? 0}" : "minecraft:unknown";
        }
    }

    public bool IsAir => Name is "minecraft:air" or "minecraft:cave_air" or "minecraft:void_air" || LegacyId == 0;

    public int? PaletteVersion => Nbt?.CompoundValue("version")?.IntegerValue() is long lower && lower is >= int.MinValue and <= int.MaxValue
        ? (int)lower
        : Nbt?.CompoundValue("Version")?.IntegerValue() is long upper && upper is >= int.MinValue and <= int.MaxValue
            ? (int)upper
            : null;

    public static BedrockBlockState EditableAir(int? version = null)
        => new(new NbtCompoundValue([
            new NbtNamedTag("name", new NbtStringValue("minecraft:air")),
            new NbtNamedTag("states", new NbtCompoundValue([])),
            new NbtNamedTag("version", new NbtIntValue(version ?? DefaultPaletteVersion))
        ]), null, null);
}

/// <summary>The palette schema is independent of the SubChunk header version.</summary>
public sealed record BedrockPaletteFormat(bool UsesLegacyVal, int? Version)
{
    public static BedrockPaletteFormat? Detect(IEnumerable<BedrockBlockState> palette)
    {
        var states = palette.Where(state => state.Nbt is not null).ToArray();
        if (states.Length == 0) return null;
        var usesVal = states.Any(state => state.Nbt!.CompoundValue("val") is not null)
            && !states.Any(state => state.Nbt!.CompoundValue("states") is not null);
        return new(usesVal, states.Select(state => state.PaletteVersion).Max());
    }

    public BedrockBlockState Air
    {
        get
        {
            if (!UsesLegacyVal) return BedrockBlockState.EditableAir(Version);
            var tags = new List<NbtNamedTag>
            {
                new("name", new NbtStringValue("minecraft:air")),
                new("val", new NbtShortValue(0))
            };
            if (Version is int version) tags.Add(new("version", new NbtIntValue(version)));
            return new(new NbtCompoundValue(tags), null, null);
        }
    }
}

public enum SubChunkStoragePersistentKind
{
    Normal,
    EmptySentinel127
}

public sealed record SubChunkStorage(
    int BitsPerBlock,
    IReadOnlyList<BedrockBlockState> Palette,
    ushort[] Indices,
    SubChunkStoragePersistentKind PersistentKind = SubChunkStoragePersistentKind.Normal)
{
    private static readonly int[] WritableBits = [0, 1, 2, 3, 4, 5, 6, 8, 16];

    public BedrockBlockState? BlockState(int x, int y, int z)
    {
        if ((uint)x >= 16 || (uint)y >= 16 || (uint)z >= 16) return null;
        var index = (x << 8) | (z << 4) | y;
        if ((uint)index >= (uint)Indices.Length) return null;
        var paletteIndex = Indices[index];
        return paletteIndex < Palette.Count ? Palette[paletteIndex] : null;
    }

    public SubChunkStorage ReplacingBlockState(int x, int y, int z, BedrockBlockState replacement)
    {
        if ((uint)x >= 16 || (uint)y >= 16 || (uint)z >= 16)
            throw new ArgumentOutOfRangeException(nameof(x), "方块局部坐标必须为 0…15。");
        if (Indices.Length != 4096 || Palette.Count == 0)
            throw new InvalidDataException("目标 storage 方块数据无效。");

        var targetLegacy = Palette.All(state => state.Nbt is null && state.LegacyId.HasValue);
        var targetModern = Palette.All(state => state.Nbt is not null);
        if (!targetLegacy && !targetModern)
            throw new InvalidDataException("目标 storage 混合了旧版数字 ID 与现代 NBT 方块。");
        if (targetLegacy && (replacement.Nbt is not null || replacement.LegacyId is null))
            throw new NotSupportedException("不能把现代 NBT 方块直接写入旧版数字 ID storage。");
        if (targetModern && replacement.Nbt is null)
            throw new NotSupportedException("不能把旧版数字 ID 方块直接写入现代 NBT storage。");

        var palette = PersistentKind == SubChunkStoragePersistentKind.EmptySentinel127
            ? new List<BedrockBlockState> { Palette[0] }
            : Palette.ToList();
        var indices = Indices.ToArray();
        var replacementIndex = FindEquivalentState(palette, replacement);
        if (replacementIndex < 0)
        {
            if (palette.Count >= ushort.MaxValue)
                throw new NotSupportedException("方块调色板条目过多，无法追加替换状态。");
            palette.Add(replacement);
            replacementIndex = palette.Count - 1;
        }

        indices[(x << 8) | (z << 4) | y] = checked((ushort)replacementIndex);
        var bits = BitsRequired(palette.Count, PersistentKind == SubChunkStoragePersistentKind.EmptySentinel127 ? 0 : BitsPerBlock);
        return new SubChunkStorage(bits, palette, indices, SubChunkStoragePersistentKind.Normal);
    }

    /// <summary>
    /// bulk editor. Applies many flat 0..4095 replacements while cloning
    /// the storage index buffer only once. This is the primitive used by fill
    /// and clone so region operations do not devolve into O(n * 4096) copies.
    /// </summary>
    public SubChunkStorage ReplacingBlockStates(IReadOnlyDictionary<int, BedrockBlockState> replacements)
    {
        if (replacements.Count == 0) return this;
        if (Indices.Length != 4096 || Palette.Count == 0)
            throw new InvalidDataException("目标 storage 方块数据无效。");

        var targetLegacy = Palette.All(state => state.Nbt is null && state.LegacyId.HasValue);
        var targetModern = Palette.All(state => state.Nbt is not null);
        if (!targetLegacy && !targetModern)
            throw new InvalidDataException("目标 storage 混合了旧版数字 ID 与现代 NBT 方块。");

        var palette = PersistentKind == SubChunkStoragePersistentKind.EmptySentinel127
            ? new List<BedrockBlockState> { Palette[0] }
            : Palette.ToList();
        var indices = Indices.ToArray();
        var paletteLookup = new Dictionary<string, ushort>(StringComparer.Ordinal);
        for (var index = 0; index < palette.Count; index++)
            paletteLookup[Convert.ToHexString(StateBytes(palette[index]))] = checked((ushort)index);

        foreach (var pair in replacements)
        {
            if ((uint)pair.Key >= 4096)
                throw new ArgumentOutOfRangeException(nameof(replacements), $"方块 flat index 超出 0…4095：{pair.Key}");
            var replacement = pair.Value;
            if (targetLegacy && (replacement.Nbt is not null || replacement.LegacyId is null))
                throw new NotSupportedException("不能把现代 NBT 方块直接写入旧版数字 ID storage。");
            if (targetModern && replacement.Nbt is null)
                throw new NotSupportedException("不能把旧版数字 ID 方块直接写入现代 NBT storage。");

            var signature = Convert.ToHexString(StateBytes(replacement));
            if (!paletteLookup.TryGetValue(signature, out var paletteIndex))
            {
                if (palette.Count >= ushort.MaxValue)
                    throw new NotSupportedException("方块调色板条目过多，无法追加替换状态。");
                paletteIndex = checked((ushort)palette.Count);
                palette.Add(replacement);
                paletteLookup[signature] = paletteIndex;
            }
            indices[pair.Key] = paletteIndex;
        }

        var bits = BitsRequired(palette.Count, PersistentKind == SubChunkStoragePersistentKind.EmptySentinel127 ? 0 : BitsPerBlock);
        return new SubChunkStorage(bits, palette, indices, SubChunkStoragePersistentKind.Normal);
    }

    public static SubChunkStorage AirFilled(BedrockBlockState air)
        => new(0, [air], new ushort[4096]);

    private static int FindEquivalentState(IReadOnlyList<BedrockBlockState> palette, BedrockBlockState state)
    {
        var target = StateBytes(state);
        for (var index = 0; index < palette.Count; index++)
            if (StateBytes(palette[index]).AsSpan().SequenceEqual(target)) return index;
        return -1;
    }

    private static byte[] StateBytes(BedrockBlockState state)
    {
        if (state.Nbt is not null)
            return BedrockNbtCodec.Encode(new NbtDocument(string.Empty, state.Nbt), NbtEncoding.LittleEndian);
        var output = new byte[4];
        output[0] = 0xff;
        output[1] = (byte)(state.LegacyId.GetValueOrDefault() & 0xff);
        output[2] = (byte)(state.LegacyId.GetValueOrDefault() >> 8);
        output[3] = state.LegacyData ?? 0;
        return output;
    }

    private static int BitsRequired(int paletteCount, int preferred)
    {
        if (paletteCount <= 0) throw new InvalidDataException("方块调色板不能为空。");
        var minimum = paletteCount <= 1 ? 0 : (int)Math.Ceiling(Math.Log2(paletteCount));
        foreach (var bits in WritableBits)
        {
            if (bits < minimum) continue;
            if (preferred > bits && WritableBits.Contains(preferred) && (preferred == 0 ? paletteCount <= 1 : paletteCount <= (1L << preferred)))
                return preferred;
            return bits;
        }
        throw new NotSupportedException("方块调色板超过 16 位索引容量。");
    }
}

public sealed record BedrockSubChunk(
    byte Version,
    sbyte? YIndex,
    IReadOnlyList<SubChunkStorage> Storages,
    byte[] TrailingData,
    byte[]? RawPersistentData = null)
{
    private static readonly HashSet<int> AllowedBitsPerBlock = [0, 1, 2, 3, 4, 5, 6, 8, 16];

    public bool IsRawPreservedUnknownVersion => RawPersistentData is not null;
    public bool IsLegacyNumeric => Version is 0 or 2 or 3 or 4 or 5 or 6 or 7;

    public BedrockSubChunk ReplacingBlockState(int x, int y, int z, int storageIndex, BedrockBlockState replacement)
    {
        if (IsRawPreservedUnknownVersion)
            throw new NotSupportedException($"未知 SubChunk v{Version} 只能原样保留，不能编辑。");
        if (storageIndex < 0 || storageIndex >= byte.MaxValue) throw new ArgumentOutOfRangeException(nameof(storageIndex));
        if (IsLegacyNumeric && storageIndex is not (0 or 1))
            throw new NotSupportedException("旧版数字 ID SubChunk 只支持 storage 0/1；storage 1 由 0x34 LegacyBlockExtraData 持久化。");

        var storages = Storages.ToList();
        var legacy = IsLegacyNumeric;
        var fallbackVersion = storages.SelectMany(storage => storage.Palette).Select(state => state.PaletteVersion).FirstOrDefault(value => value.HasValue);
        var air = legacy
            ? new BedrockBlockState(null, 0, 0)
            : storages.SelectMany(storage => storage.Palette).FirstOrDefault(state => state.Nbt is not null && state.IsAir)
              ?? BedrockBlockState.EditableAir(fallbackVersion);
        while (storages.Count <= storageIndex) storages.Add(SubChunkStorage.AirFilled(air));
        storages[storageIndex] = storages[storageIndex].ReplacingBlockState(x, y, z, replacement);
        var version = Version == 1 && storages.Count > 1 ? (byte)8 : Version;
        return this with { Version = version, Storages = storages, RawPersistentData = null };
    }

    /// <summary>
    /// Applies a bulk replacement map to one physical storage. Missing storages
    /// are materialised as air; v1 is upgraded to v8 when storage 1+ is created.
    /// </summary>
    public BedrockSubChunk ReplacingStorageBlocks(int storageIndex, IReadOnlyDictionary<int, BedrockBlockState> replacements)
    {
        if (replacements.Count == 0) return this;
        if (IsRawPreservedUnknownVersion)
            throw new NotSupportedException($"未知 SubChunk v{Version} 只能原样保留，不能编辑。");
        if (storageIndex < 0 || storageIndex >= byte.MaxValue) throw new ArgumentOutOfRangeException(nameof(storageIndex));
        if (IsLegacyNumeric && storageIndex is not (0 or 1))
            throw new NotSupportedException("旧版数字 ID SubChunk 只支持 storage 0/1。");

        var storages = Storages.ToList();
        var legacy = IsLegacyNumeric;
        var fallbackVersion = storages.SelectMany(storage => storage.Palette).Select(state => state.PaletteVersion).FirstOrDefault(value => value.HasValue);
        var air = legacy
            ? new BedrockBlockState(null, 0, 0)
            : storages.SelectMany(storage => storage.Palette).FirstOrDefault(state => state.Nbt is not null && state.IsAir)
              ?? BedrockBlockState.EditableAir(fallbackVersion);
        while (storages.Count <= storageIndex) storages.Add(SubChunkStorage.AirFilled(air));
        storages[storageIndex] = storages[storageIndex].ReplacingBlockStates(replacements);
        var version = Version == 1 && storages.Count > 1 ? (byte)8 : Version;
        return this with { Version = version, Storages = storages, RawPersistentData = null };
    }

    public BedrockSubChunk ReplacingBlockLayers(int x, int y, int z, IReadOnlyList<BedrockBlockState> layers, bool clearExtraStorages = true)
    {
        if (layers.Count == 0) throw new InvalidDataException("至少需要一个方块 storage 状态。");
        var updated = this;
        for (var index = 0; index < layers.Count; index++)
            updated = updated.ReplacingBlockState(x, y, z, index, layers[index]);

        if (clearExtraStorages && updated.Storages.Count > layers.Count)
        {
            var legacy = updated.IsLegacyNumeric;
            var fallbackVersion = updated.Storages.SelectMany(storage => storage.Palette).Select(state => state.PaletteVersion).FirstOrDefault(value => value.HasValue);
            for (var index = layers.Count; index < updated.Storages.Count; index++)
            {
                var air = legacy
                    ? new BedrockBlockState(null, 0, 0)
                    : updated.Storages[index].Palette.FirstOrDefault(state => state.Nbt is not null && state.IsAir)
                      ?? BedrockBlockState.EditableAir(fallbackVersion);
                updated = updated.ReplacingBlockState(x, y, z, index, air);
            }
        }
        return updated;
    }

    public static BedrockSubChunk EmptyLegacy(byte version, sbyte? yIndex)
    {
        if (version is not (0 or 2 or 3 or 4 or 5 or 6 or 7))
            throw new NotSupportedException($"SubChunk v{version} 不是旧版数字 ID 格式");
        var air = new BedrockBlockState(null, 0, 0);
        return new BedrockSubChunk(
            version, yIndex,
            [new SubChunkStorage(8, [air], new ushort[4096])],
            new byte[4096]);
    }

    public static BedrockSubChunk Decode(ReadOnlySpan<byte> data, sbyte? keyYIndex = null)
    {
        if (data.IsEmpty) throw new InvalidDataException("SubChunk 数据为空");
        var reader = new BinaryDataReader(data);
        var version = reader.ReadByte();
        switch (version)
        {
            case 1:
            {
                var storage = DecodePalettedStorage(ref reader);
                return new BedrockSubChunk(version, keyYIndex, [storage], reader.ReadBytes(reader.Remaining));
            }
            case 8:
            {
                var count = reader.ReadByte();
                var storages = new List<SubChunkStorage>(count);
                for (var index = 0; index < count; index++) storages.Add(DecodePalettedStorage(ref reader));
                return new BedrockSubChunk(version, keyYIndex, storages, reader.ReadBytes(reader.Remaining));
            }
            case 9:
            {
                var count = reader.ReadByte();
                var y = unchecked((sbyte)reader.ReadByte());
                var storages = new List<SubChunkStorage>(count);
                for (var index = 0; index < count; index++) storages.Add(DecodePalettedStorage(ref reader));
                return new BedrockSubChunk(version, y, storages, reader.ReadBytes(reader.Remaining));
            }
            case 0:
            case 2:
            case 3:
            case 4:
            case 5:
            case 6:
            case 7:
                return DecodeLegacy(data, version, keyYIndex);
            default:
                return new BedrockSubChunk(version, keyYIndex, [], [], data.ToArray());
        }
    }

    public byte[] EncodePersistent()
    {
        if (RawPersistentData is not null) return RawPersistentData.ToArray();
        if (IsLegacyNumeric) return EncodeLegacyPersistent();
        if (Version is not (1 or 8 or 9))
            throw new NotSupportedException($"SubChunk v{Version} 暂不支持重新编码");
        if (Version == 1 && Storages.Count != 1)
            throw new InvalidDataException("SubChunk v1 必须恰好包含一个 storage");
        if (Storages.Count > byte.MaxValue)
            throw new InvalidDataException("SubChunk storage 数量超过 UInt8 上限");

        var writer = new BinaryDataWriter();
        writer.WriteByte(Version);
        if (Version is 8 or 9) writer.WriteByte((byte)Storages.Count);
        if (Version == 9) writer.WriteByte(unchecked((byte)(YIndex ?? 0)));
        // BPB=0 was added after the original v1/v8 readers. One-bit storage
        // works with every v1/v8 game, including completely empty layers.
        foreach (var storage in Storages)
            EncodeStorage(Version is 1 or 8 && storage.BitsPerBlock == 0
                ? storage with { BitsPerBlock = 1 } : storage, writer);
        writer.WriteBytes(TrailingData);
        return writer.ToArray();
    }

    private static SubChunkStorage DecodePalettedStorage(ref BinaryDataReader reader)
    {
        var header = reader.ReadByte();
        var bitsPerBlock = header >> 1;
        var isRuntimePalette = (header & 1) != 0;
        if (isRuntimePalette)
            throw new NotSupportedException("网络运行时调色板不能从世界数据库独立解析");

        if (bitsPerBlock == 127)
            return new SubChunkStorage(
                127, [BedrockBlockState.EditableAir()], new ushort[4096],
                SubChunkStoragePersistentKind.EmptySentinel127);

        if (!AllowedBitsPerBlock.Contains(bitsPerBlock))
            throw new InvalidDataException($"每方块位数无效：{bitsPerBlock}");

        var indices = new ushort[4096];
        if (bitsPerBlock == 0)
        {
            var document = BedrockNbtCodec.DecodeOne(reader.RemainingSpan, out var consumed, NbtEncoding.LittleEndian, 64);
            reader.Skip(consumed);
            if (document.Root.Type != NbtTagType.Compound)
                throw new InvalidDataException("方块状态不是 Compound");
            return new SubChunkStorage(0, [new BedrockBlockState(document.Root, null, null)], indices);
        }

        var entriesPerWord = 32 / bitsPerBlock;
        var wordCount = (4096 + entriesPerWord - 1) / entriesPerWord;
        var mask = (1u << bitsPerBlock) - 1u;
        var outputIndex = 0;
        for (var wordIndex = 0; wordIndex < wordCount; wordIndex++)
        {
            var word = reader.ReadUInt32LE();
            for (var slot = 0; slot < entriesPerWord && outputIndex < 4096; slot++)
            {
                var shift = slot * bitsPerBlock;
                indices[outputIndex++] = (ushort)((word >> shift) & mask);
            }
        }

        var paletteCount = reader.ReadInt32LE();
        if (paletteCount <= 0 || paletteCount > 65_536)
            throw new InvalidDataException($"调色板大小无效：{paletteCount}");
        var palette = new List<BedrockBlockState>(paletteCount);
        for (var index = 0; index < paletteCount; index++)
        {
            var document = BedrockNbtCodec.DecodeOne(reader.RemainingSpan, out var consumed, NbtEncoding.LittleEndian, 64);
            reader.Skip(consumed);
            if (document.Root.Type != NbtTagType.Compound)
                throw new InvalidDataException("方块状态不是 Compound");
            palette.Add(new BedrockBlockState(document.Root, null, null));
        }
        var max = indices.Max();
        if (max >= palette.Count)
            throw new InvalidDataException($"调色板索引越界：{max} >= {palette.Count}");
        return new SubChunkStorage(bitsPerBlock, palette, indices);
    }

    private static BedrockSubChunk DecodeLegacy(ReadOnlySpan<byte> data, byte version, sbyte? keyYIndex)
    {
        if (data.Length < 1 + 4096)
            throw new InvalidDataException("旧版 SubChunk 长度不足");
        var ids = data.Slice(1, 4096);
        var metadataStart = 1 + 4096;
        var hasMetadata = data.Length >= metadataStart + 2048;
        var metadata = hasMetadata ? data.Slice(metadataStart, 2048) : ReadOnlySpan<byte>.Empty;

        var paletteMap = new Dictionary<uint, ushort>();
        var palette = new List<BedrockBlockState>();
        var indices = new ushort[4096];
        for (var index = 0; index < 4096; index++)
        {
            var id = (ushort)ids[index];
            var packed = hasMetadata ? metadata[index / 2] : (byte)0;
            var meta = (byte)(index % 2 == 0 ? packed & 0x0f : packed >> 4);
            var paletteKey = ((uint)id << 8) | meta;
            if (!paletteMap.TryGetValue(paletteKey, out var paletteIndex))
            {
                if (palette.Count >= ushort.MaxValue)
                    throw new InvalidDataException("旧版 SubChunk 调色板过大");
                paletteIndex = (ushort)palette.Count;
                paletteMap[paletteKey] = paletteIndex;
                palette.Add(new BedrockBlockState(null, id, meta));
            }
            indices[index] = paletteIndex;
        }
        var consumed = hasMetadata ? metadataStart + 2048 : metadataStart;
        var trailing = consumed < data.Length ? data[consumed..].ToArray() : [];
        return new BedrockSubChunk(version, keyYIndex, [new SubChunkStorage(8, palette, indices)], trailing);
    }

    private byte[] EncodeLegacyPersistent()
    {
        if (Storages.Count != 1)
            throw new InvalidDataException("旧版 SubChunk 必须恰好包含一个 storage");
        var storage = Storages[0];
        if (storage.Indices.Length != 4096 || storage.Palette.Count == 0)
            throw new InvalidDataException("旧版 SubChunk 方块数据无效");

        var ids = new byte[4096];
        var metadata = new byte[2048];
        for (var blockIndex = 0; blockIndex < 4096; blockIndex++)
        {
            var paletteIndex = storage.Indices[blockIndex];
            if (paletteIndex >= storage.Palette.Count)
                throw new InvalidDataException("旧版 SubChunk 调色板索引越界");
            var state = storage.Palette[paletteIndex];
            if (state.LegacyId is not ushort legacyId || legacyId > byte.MaxValue)
                throw new InvalidDataException("旧版 SubChunk 调色板包含非数字 ID 方块");
            var legacyData = state.LegacyData ?? 0;
            if (legacyData > 15)
                throw new InvalidDataException("旧版方块 data 必须为 0…15");
            ids[blockIndex] = (byte)legacyId;
            var metadataIndex = blockIndex / 2;
            metadata[metadataIndex] = blockIndex % 2 == 0
                ? (byte)((metadata[metadataIndex] & 0xf0) | legacyData)
                : (byte)((metadata[metadataIndex] & 0x0f) | (legacyData << 4));
        }

        var output = new byte[1 + ids.Length + metadata.Length + TrailingData.Length];
        output[0] = Version;
        ids.CopyTo(output, 1);
        metadata.CopyTo(output, 1 + ids.Length);
        TrailingData.CopyTo(output, 1 + ids.Length + metadata.Length);
        return output;
    }

    private static void EncodeStorage(SubChunkStorage storage, BinaryDataWriter writer)
    {
        if (storage.PersistentKind == SubChunkStoragePersistentKind.EmptySentinel127)
        {
            if (storage.Indices.Length != 4096 || storage.Indices.Any(value => value != 0))
                throw new InvalidDataException("BPB=127 空 storage 被修改后必须转换为普通 storage");
            writer.WriteByte(254);
            return;
        }

        var bits = storage.BitsPerBlock;
        if (!AllowedBitsPerBlock.Contains(bits))
            throw new InvalidDataException($"不支持的每方块位数：{bits}");
        if (storage.Indices.Length != 4096)
            throw new InvalidDataException("storage 必须包含 4096 个方块索引");
        if (storage.Palette.Count == 0 || storage.Palette.Count > int.MaxValue)
            throw new InvalidDataException("方块调色板大小无效");
        var capacity = bits == 0 ? 1L : 1L << bits;
        if (storage.Palette.Count > capacity)
            throw new InvalidDataException($"调色板大小超过 {bits} 位索引容量");

        writer.WriteByte((byte)(bits << 1));
        if (bits == 0)
        {
            if (storage.Palette.Count != 1 || storage.Palette[0].Nbt is null)
                throw new InvalidDataException("0 位 storage 必须恰好包含一个现代方块状态");
            writer.WriteBytes(BedrockNbtCodec.Encode(new NbtDocument("", storage.Palette[0].Nbt!), NbtEncoding.LittleEndian));
            return;
        }

        var entriesPerWord = 32 / bits;
        var wordCount = (4096 + entriesPerWord - 1) / entriesPerWord;
        var mask = (1u << bits) - 1u;
        for (var wordIndex = 0; wordIndex < wordCount; wordIndex++)
        {
            uint word = 0;
            for (var slot = 0; slot < entriesPerWord; slot++)
            {
                var sourceIndex = wordIndex * entriesPerWord + slot;
                if (sourceIndex >= storage.Indices.Length) break;
                var paletteIndex = storage.Indices[sourceIndex];
                if (paletteIndex >= storage.Palette.Count)
                    throw new InvalidDataException($"方块调色板索引越界：{paletteIndex}");
                word |= ((uint)paletteIndex & mask) << (slot * bits);
            }
            writer.WriteUInt32LE(word);
        }

        writer.WriteInt32LE(storage.Palette.Count);
        foreach (var state in storage.Palette)
        {
            if (state.Nbt is null)
                throw new NotSupportedException("现代持久化调色板不能写入旧版数字 ID 方块");
            writer.WriteBytes(BedrockNbtCodec.Encode(new NbtDocument("", state.Nbt), NbtEncoding.LittleEndian));
        }
    }
}

/// <summary>
/// Pre-Anvil Pocket/Bedrock full-column terrain record (LevelChunkTag 0x30).
/// exposes it as eight virtual v0 SubChunks while preserving light,
/// height-map and biome/color bytes byte-for-byte.
/// </summary>
public sealed class BedrockLegacyTerrain
{
    public const int BlockIdCount = 32_768;
    public const int NibbleCount = 16_384;
    public const int HeightMapCount = 256;
    public const int BiomeColorCount = 1_024;
    public const int PersistentByteCount = 83_200;

    public required byte[] BlockIds { get; init; }
    public required byte[] DataValues { get; init; }
    public required byte[] SkyLight { get; init; }
    public required byte[] BlockLight { get; init; }
    public required byte[] HeightMap { get; init; }
    public required byte[] BiomeColors { get; init; }
    public required byte[] TrailingData { get; init; }

    public static byte[] EmptyPersistentData
    {
        get
        {
            var output = new byte[PersistentByteCount];
            Array.Fill(output, (byte)0xff, BlockIdCount + NibbleCount, NibbleCount);
            return output;
        }
    }

    public static BedrockLegacyTerrain Decode(ReadOnlySpan<byte> data)
    {
        if (data.Length < PersistentByteCount)
            throw new InvalidDataException($"LegacyTerrain 长度不足：{data.Length}，至少需要 {PersistentByteCount} 字节");
        var offset = 0;
        var blockIds = data.Slice(offset, BlockIdCount).ToArray(); offset += BlockIdCount;
        var dataValues = data.Slice(offset, NibbleCount).ToArray(); offset += NibbleCount;
        var skyLight = data.Slice(offset, NibbleCount).ToArray(); offset += NibbleCount;
        var blockLight = data.Slice(offset, NibbleCount).ToArray(); offset += NibbleCount;
        var heightMap = data.Slice(offset, HeightMapCount).ToArray(); offset += HeightMapCount;
        var biomeColors = data.Slice(offset, BiomeColorCount).ToArray(); offset += BiomeColorCount;
        return new BedrockLegacyTerrain
        {
            BlockIds = blockIds,
            DataValues = dataValues,
            SkyLight = skyLight,
            BlockLight = blockLight,
            HeightMap = heightMap,
            BiomeColors = biomeColors,
            TrailingData = offset < data.Length ? data[offset..].ToArray() : []
        };
    }

    public byte[] EncodePersistent()
    {
        if (BlockIds.Length != BlockIdCount || DataValues.Length != NibbleCount ||
            SkyLight.Length != NibbleCount || BlockLight.Length != NibbleCount ||
            HeightMap.Length != HeightMapCount || BiomeColors.Length != BiomeColorCount)
            throw new InvalidDataException("LegacyTerrain 内部字段长度无效");
        using var stream = new MemoryStream(PersistentByteCount + TrailingData.Length);
        stream.Write(BlockIds);
        stream.Write(DataValues);
        stream.Write(SkyLight);
        stream.Write(BlockLight);
        stream.Write(HeightMap);
        stream.Write(BiomeColors);
        stream.Write(TrailingData);
        return stream.ToArray();
    }

    public uint? BiomeId(int localX, int localZ)
    {
        if ((uint)localX >= 16 || (uint)localZ >= 16) return null;
        var offset = (localZ * 16 + localX) * 4;
        return (uint)offset < (uint)BiomeColors.Length ? BiomeColors[offset] : null;
    }

    public short? Height(int localX, int localZ)
    {
        if ((uint)localX >= 16 || (uint)localZ >= 16) return null;
        var index = localZ * 16 + localX;
        return (uint)index < (uint)HeightMap.Length ? HeightMap[index] : null;
    }

    public BedrockSubChunk SubChunk(sbyte yIndex)
    {
        if (yIndex is < 0 or > 7)
            throw new InvalidDataException("LegacyTerrain 只包含 SubChunk Y=0…7");
        var paletteMap = new Dictionary<uint, ushort>();
        var palette = new List<BedrockBlockState>();
        var indices = new ushort[4096];
        for (var x = 0; x < 16; x++)
        for (var z = 0; z < 16; z++)
        for (var localY = 0; localY < 16; localY++)
        {
            var absoluteY = yIndex * 16 + localY;
            var sourceIndex = (x << 11) | (z << 7) | absoluteY;
            var id = (ushort)BlockIds[sourceIndex];
            var packed = DataValues[sourceIndex >> 1];
            var meta = (byte)((sourceIndex & 1) == 0 ? packed & 0x0f : packed >> 4);
            var key = ((uint)id << 8) | meta;
            if (!paletteMap.TryGetValue(key, out var paletteIndex))
            {
                paletteIndex = checked((ushort)palette.Count);
                paletteMap[key] = paletteIndex;
                palette.Add(new BedrockBlockState(null, id, meta));
            }
            indices[(x << 8) | (z << 4) | localY] = paletteIndex;
        }
        return new BedrockSubChunk(0, yIndex, [new SubChunkStorage(8, palette, indices)], []);
    }
}
