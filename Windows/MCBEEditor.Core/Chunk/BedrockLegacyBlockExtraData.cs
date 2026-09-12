using System.Buffers.Binary;

namespace MCBEEditor.Core.Chunk;

public sealed record BedrockLegacyBlockExtraEntry(uint Location, byte BlockId, byte BlockData)
{
    public int X => (int)((Location >> 12) & 0x0f);
    public int Z => (int)((Location >> 8) & 0x0f);
    public int AbsoluteY => (int)(Location & 0xff);
    public sbyte SubChunkY => checked((sbyte)(AbsoluteY >> 4));
    public int LocalY => AbsoluteY & 0x0f;
    public int LinearIndex => (X << 8) | (Z << 4) | LocalY;

    public static uint PackLocation(int x, int absoluteY, int z)
    {
        if ((uint)x >= 16 || (uint)z >= 16 || (uint)absoluteY >= 256)
            throw new InvalidDataException("LegacyBlockExtraData 坐标超出旧格式范围。");
        return checked((uint)((x << 12) | (z << 8) | absoluteY));
    }
}

/// <summary>
/// Legacy secondary block layer stored in LevelChunkTag 0x34 beside numeric
/// v0/v2...v7 SubChunks. Unknown trailing bytes are preserved verbatim.
/// </summary>
public sealed class BedrockLegacyBlockExtraData
{
    public List<BedrockLegacyBlockExtraEntry> Entries { get; }
    public byte[] TrailingData { get; }

    public BedrockLegacyBlockExtraData(IEnumerable<BedrockLegacyBlockExtraEntry>? entries = null, byte[]? trailingData = null)
    {
        Entries = entries?.ToList() ?? [];
        TrailingData = trailingData?.ToArray() ?? [];
    }

    public static BedrockLegacyBlockExtraData Decode(ReadOnlySpan<byte> data)
    {
        if (data.Length < 4) throw new InvalidDataException("LegacyBlockExtraData 长度不足。");
        var count = BinaryPrimitives.ReadInt32LittleEndian(data[..4]);
        if (count < 0) throw new InvalidDataException("LegacyBlockExtraData 条目数量为负数。");
        var needed = checked(4 + count * 6);
        if (needed > data.Length) throw new InvalidDataException("LegacyBlockExtraData 条目数量超过剩余数据。");
        var entries = new List<BedrockLegacyBlockExtraEntry>(count);
        var offset = 4;
        for (var index = 0; index < count; index++)
        {
            var location = BinaryPrimitives.ReadUInt32LittleEndian(data.Slice(offset, 4));
            entries.Add(new BedrockLegacyBlockExtraEntry(location, data[offset + 4], data[offset + 5]));
            offset += 6;
        }
        return new BedrockLegacyBlockExtraData(entries, data[offset..].ToArray());
    }

    public byte[] EncodePersistent()
    {
        if (Entries.Count > int.MaxValue) throw new InvalidDataException("LegacyBlockExtraData 条目数量过多。");
        var output = new byte[checked(4 + Entries.Count * 6 + TrailingData.Length)];
        BinaryPrimitives.WriteInt32LittleEndian(output.AsSpan(0, 4), Entries.Count);
        var offset = 4;
        foreach (var entry in Entries)
        {
            BinaryPrimitives.WriteUInt32LittleEndian(output.AsSpan(offset, 4), entry.Location);
            output[offset + 4] = entry.BlockId;
            output[offset + 5] = entry.BlockData;
            offset += 6;
        }
        TrailingData.CopyTo(output, offset);
        return output;
    }

    public SubChunkStorage? Storage(sbyte subChunkY)
    {
        var matching = Entries.Where(entry => entry.SubChunkY == subChunkY).ToArray();
        if (matching.Length == 0) return null;
        var air = new BedrockBlockState(null, 0, 0);
        var palette = new List<BedrockBlockState> { air };
        var lookup = new Dictionary<ushort, ushort> { [0] = 0 };
        var indices = new ushort[4096];
        foreach (var entry in matching)
        {
            var pair = (ushort)((entry.BlockId << 8) | entry.BlockData);
            if (!lookup.TryGetValue(pair, out var paletteIndex))
            {
                paletteIndex = checked((ushort)palette.Count);
                lookup[pair] = paletteIndex;
                palette.Add(new BedrockBlockState(null, entry.BlockId, entry.BlockData));
            }
            indices[entry.LinearIndex] = paletteIndex;
        }
        return new SubChunkStorage(8, palette, indices);
    }

    public void ReplaceStorage(sbyte subChunkY, SubChunkStorage? storage)
    {
        if (subChunkY is < 0 or > 15)
            throw new NotSupportedException("LegacyBlockExtraData 只能表示 Y=0…255。");
        Entries.RemoveAll(entry => entry.SubChunkY == subChunkY);
        if (storage is null) return;
        if (storage.Indices.Length != 4096 || storage.Palette.Count == 0)
            throw new InvalidDataException("LegacyBlockExtraData layer 1 storage 无效。");

        var added = new List<BedrockLegacyBlockExtraEntry>();
        for (var x = 0; x < 16; x++)
        for (var z = 0; z < 16; z++)
        for (var localY = 0; localY < 16; localY++)
        {
            var index = (x << 8) | (z << 4) | localY;
            var paletteIndex = storage.Indices[index];
            if (paletteIndex >= storage.Palette.Count)
                throw new InvalidDataException("LegacyBlockExtraData 调色板索引越界。");
            var state = storage.Palette[paletteIndex];
            if (state.IsAir) continue;
            if (state.Nbt is not null || state.LegacyId is not ushort legacyId || legacyId > byte.MaxValue)
                throw new NotSupportedException("LegacyBlockExtraData 只能写入 0…255 数字 ID。");
            var absoluteY = subChunkY * 16 + localY;
            added.Add(new BedrockLegacyBlockExtraEntry(
                BedrockLegacyBlockExtraEntry.PackLocation(x, absoluteY, z),
                (byte)legacyId,
                state.LegacyData ?? 0));
        }
        added.Sort((a, b) => a.Location.CompareTo(b.Location));
        Entries.AddRange(added);
    }
}
