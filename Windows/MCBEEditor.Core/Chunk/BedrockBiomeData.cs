using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.Chunk;

public enum BedrockBiomeFormat
{
    Data3D,
    Data2D,
    Data2DLegacy
}

public sealed record BedrockBiomeLayer(int? BaseY, uint[] BiomeIds, bool IsAbsent)
{}

/// <summary>
/// Bedrock 0x2b/0x2d/0x2e biome payload codec ported from the iOS implementation.
/// Data3D uses X-Z-Y ordering inside each 16-high biome storage.
/// </summary>
public sealed class BedrockBiomeDocument
{
    private readonly byte[] _legacyAuxiliaryBytes;
    private readonly byte[] _trailingData;

    public BedrockBiomeDocument(
        BedrockBiomeFormat format,
        short[] heightMap,
        IReadOnlyList<BedrockBiomeLayer> layers,
        byte[]? legacyAuxiliaryBytes = null,
        byte[]? trailingData = null)
    {
        Format = format;
        HeightMap = heightMap.ToArray();
        Layers = layers.Select(layer => new BedrockBiomeLayer(layer.BaseY, layer.BiomeIds.ToArray(), layer.IsAbsent)).ToList();
        _legacyAuxiliaryBytes = legacyAuxiliaryBytes?.ToArray() ?? [];
        _trailingData = trailingData?.ToArray() ?? [];
    }

    public BedrockBiomeFormat Format { get; }
    public short[] HeightMap { get; }
    public List<BedrockBiomeLayer> Layers { get; }

    public static BedrockBiomeDocument Decode(ChunkRecordType recordType, ReadOnlySpan<byte> data)
    {
        var format = recordType switch
        {
            ChunkRecordType.Data3D => BedrockBiomeFormat.Data3D,
            ChunkRecordType.Data2D => BedrockBiomeFormat.Data2D,
            ChunkRecordType.Data2DLegacy => BedrockBiomeFormat.Data2DLegacy,
            _ => throw new NotSupportedException($"{recordType.DisplayName()} 不是可编辑的生物群系记录。")
        };
        if (data.Length < 512) throw new InvalidDataException($"{format} 少于 512 字节高度图。");

        var reader = new BinaryDataReader(data);
        var heights = new short[256];
        for (var index = 0; index < heights.Length; index++) heights[index] = reader.ReadInt16LE();

        switch (format)
        {
            case BedrockBiomeFormat.Data2D:
            {
                if (reader.Remaining < 256) throw new InvalidDataException("Data2D 缺少 256 个生物群系 ID。");
                var ids = new uint[256];
                for (var index = 0; index < ids.Length; index++) ids[index] = reader.ReadByte();
                return new BedrockBiomeDocument(format, heights,
                    [new BedrockBiomeLayer(null, ids, false)], trailingData: reader.ReadBytes(reader.Remaining));
            }
            case BedrockBiomeFormat.Data2DLegacy:
            {
                if (reader.Remaining < 1024) throw new InvalidDataException("Data2DLegacy 缺少 256×4 生物群系记录。");
                var ids = new uint[256];
                var auxiliary = new byte[256 * 3];
                for (var index = 0; index < 256; index++)
                {
                    ids[index] = reader.ReadByte();
                    var extra = reader.ReadBytes(3);
                    extra.CopyTo(auxiliary, index * 3);
                }
                return new BedrockBiomeDocument(format, heights,
                    [new BedrockBiomeLayer(null, ids, false)], auxiliary, reader.ReadBytes(reader.Remaining));
            }
            case BedrockBiomeFormat.Data3D:
            {
                var layers = new List<BedrockBiomeLayer>();
                var baseY = -64;
                while (!reader.IsAtEnd)
                {
                    var header = reader.ReadByte();
                    if (header == 0xff)
                    {
                        layers.Add(new BedrockBiomeLayer(baseY, new uint[4096], true));
                        baseY += 16;
                        continue;
                    }

                    var bits = header >> 1;
                    if (bits is not (0 or 1 or 2 or 3 or 4 or 5 or 6 or 8 or 16))
                        throw new NotSupportedException($"Data3D 生物群系位宽 {bits} 不受支持。");

                    var indices = new int[4096];
                    var palette = new List<uint>();
                    if (bits == 0)
                    {
                        palette.Add(reader.ReadUInt32LE());
                    }
                    else
                    {
                        var valuesPerWord = 32 / bits;
                        var wordCount = (4096 + valuesPerWord - 1) / valuesPerWord;
                        var mask = (1u << bits) - 1u;
                        var output = 0;
                        for (var wordIndex = 0; wordIndex < wordCount; wordIndex++)
                        {
                            var word = reader.ReadUInt32LE();
                            for (var slot = 0; slot < valuesPerWord && output < 4096; slot++)
                                indices[output++] = (int)((word >> (slot * bits)) & mask);
                        }
                        var paletteCount = reader.ReadInt32LE();
                        if (paletteCount <= 0 || paletteCount > 65_536)
                            throw new InvalidDataException($"Data3D 调色板长度无效：{paletteCount}。");
                        for (var index = 0; index < paletteCount; index++) palette.Add(reader.ReadUInt32LE());
                    }

                    var values = new uint[4096];
                    for (var index = 0; index < values.Length; index++)
                    {
                        var paletteIndex = indices[index];
                        if ((uint)paletteIndex >= (uint)palette.Count)
                            throw new InvalidDataException($"Data3D 生物群系索引 {paletteIndex} 超出调色板。");
                        values[index] = palette[paletteIndex];
                    }
                    layers.Add(new BedrockBiomeLayer(baseY, values, false));
                    baseY += 16;
                }
                MaterializeInheritedData3DLayers(layers);
                return new BedrockBiomeDocument(format, heights, layers);
            }
            default:
                throw new InvalidOperationException("未知生物群系格式。");
        }
    }

    public byte[] Encode()
    {
        if (HeightMap.Length != 256) throw new InvalidDataException("生物群系高度图必须包含 256 项。");
        var writer = new BinaryDataWriter();
        foreach (var value in HeightMap) writer.WriteInt16LE(value);

        switch (Format)
        {
            case BedrockBiomeFormat.Data2D:
                if (Layers.Count != 1 || Layers[0].BiomeIds.Length != 256)
                    throw new InvalidDataException("Data2D 必须包含 256 个生物群系 ID。");
                foreach (var id in Layers[0].BiomeIds)
                {
                    if (id > byte.MaxValue) throw new InvalidDataException($"Data2D 生物群系 ID {id} 超出 UInt8。");
                    writer.WriteByte((byte)id);
                }
                writer.WriteBytes(_trailingData);
                break;

            case BedrockBiomeFormat.Data2DLegacy:
                if (Layers.Count != 1 || Layers[0].BiomeIds.Length != 256 || _legacyAuxiliaryBytes.Length != 256 * 3)
                    throw new InvalidDataException("Data2DLegacy 数据长度无效。");
                for (var index = 0; index < 256; index++)
                {
                    var id = Layers[0].BiomeIds[index];
                    if (id > byte.MaxValue) throw new InvalidDataException($"Data2DLegacy 生物群系 ID {id} 超出 UInt8。");
                    writer.WriteByte((byte)id);
                    writer.WriteBytes(_legacyAuxiliaryBytes.AsSpan(index * 3, 3));
                }
                writer.WriteBytes(_trailingData);
                break;

            case BedrockBiomeFormat.Data3D:
                foreach (var layer in Layers)
                {
                    if (layer.BiomeIds.Length != 4096)
                        throw new InvalidDataException("Data3D 每层必须包含 4096 个生物群系 ID。");
                    if (layer.IsAbsent)
                    {
                        writer.WriteByte(0xff);
                        continue;
                    }
                    EncodePalettedLayer(layer.BiomeIds, writer);
                }
                break;
        }
        return writer.ToArray();
    }

    public void FillLayer(int layerIndex, uint id)
    {
        if ((uint)layerIndex >= (uint)Layers.Count) throw new InvalidDataException("生物群系层越界。");
        var layer = Layers[layerIndex];
        Layers[layerIndex] = new BedrockBiomeLayer(layer.BaseY, Enumerable.Repeat(id, layer.BiomeIds.Length).ToArray(), false);
    }

    /// <summary>Sets every Data3D biome position, including inherited 0xff layers, to one ID.</summary>
    public void FillAllData3DLayers(uint id)
    {
        if (Format != BedrockBiomeFormat.Data3D)
            throw new NotSupportedException("整区块生物群系设置仅适用于 Data3D。");
        if (Layers.Count == 0) throw new InvalidDataException("Data3D 没有可编辑的生物群系层。");
        for (var index = 0; index < Layers.Count; index++)
        {
            var layer = Layers[index];
            if (layer.BiomeIds.Length != 4096) throw new InvalidDataException("Data3D 每层必须包含 4096 个生物群系 ID。");
            Layers[index] = new BedrockBiomeLayer(layer.BaseY, Enumerable.Repeat(id, 4096).ToArray(), false);
        }
    }

    public uint? BiomeId(int localX, int y, int localZ)
    {
        if ((uint)localX >= 16 || (uint)localZ >= 16) return null;
        if (Format is BedrockBiomeFormat.Data2D or BedrockBiomeFormat.Data2DLegacy)
        {
            if (Layers.Count == 0) return null;
            var index = localZ * 16 + localX;
            return (uint)index < (uint)Layers[0].BiomeIds.Length ? Layers[0].BiomeIds[index] : null;
        }

        var layerIndex = Layers.FindIndex(layer => layer.BaseY is int baseY && y >= baseY && y <= baseY + 15);
        if (layerIndex < 0)
        {
            var candidates = Layers.Select((layer, index) => (layer, index))
                .Where(item => !item.layer.IsAbsent && item.layer.BaseY.HasValue)
                .OrderBy(item => Math.Abs(item.layer.BaseY!.Value - y))
                .ToArray();
            if (candidates.Length == 0) return null;
            layerIndex = candidates[0].index;
            y = Layers[layerIndex].BaseY ?? y;
        }
        var baseLayerY = Layers[layerIndex].BaseY ?? y;
        var localY = y - baseLayerY;
        if ((uint)localY >= 16) return null;
        var flat = localX * 256 + localZ * 16 + localY;
        return (uint)flat < (uint)Layers[layerIndex].BiomeIds.Length ? Layers[layerIndex].BiomeIds[flat] : null;
    }

    private static void MaterializeInheritedData3DLayers(List<BedrockBiomeLayer> layers)
    {
        uint[]? inheritedTopPlane = null;
        for (var layerIndex = 0; layerIndex < layers.Count; layerIndex++)
        {
            var layer = layers[layerIndex];
            if (layer.IsAbsent)
            {
                if (inheritedTopPlane is not { Length: 256 }) continue;
                var values = new uint[4096];
                for (var x = 0; x < 16; x++)
                for (var z = 0; z < 16; z++)
                {
                    var value = inheritedTopPlane[x * 16 + z];
                    var start = x * 256 + z * 16;
                    for (var localY = 0; localY < 16; localY++) values[start + localY] = value;
                }
                layers[layerIndex] = new BedrockBiomeLayer(layer.BaseY, values, true);
                continue;
            }

            if (layer.BiomeIds.Length != 4096)
            {
                inheritedTopPlane = null;
                continue;
            }
            var top = new uint[256];
            for (var x = 0; x < 16; x++)
            for (var z = 0; z < 16; z++)
                top[x * 16 + z] = layer.BiomeIds[x * 256 + z * 16 + 15];
            inheritedTopPlane = top;
        }
    }

    private static void EncodePalettedLayer(uint[] values, BinaryDataWriter writer)
    {
        var palette = new List<uint>();
        var lookup = new Dictionary<uint, int>();
        var indices = new int[values.Length];
        for (var index = 0; index < values.Length; index++)
        {
            var value = values[index];
            if (!lookup.TryGetValue(value, out var paletteIndex))
            {
                paletteIndex = palette.Count;
                if (paletteIndex >= 65_536) throw new NotSupportedException("Data3D 生物群系调色板超过 65536 项。");
                palette.Add(value);
                lookup[value] = paletteIndex;
            }
            indices[index] = paletteIndex;
        }

        var bits = palette.Count switch
        {
            <= 1 => 0,
            2 => 1,
            <= 4 => 2,
            <= 8 => 3,
            <= 16 => 4,
            <= 32 => 5,
            <= 64 => 6,
            <= 256 => 8,
            _ => 16
        };
        writer.WriteByte((byte)(bits << 1));
        if (bits == 0)
        {
            writer.WriteUInt32LE(palette.Count == 0 ? 0 : palette[0]);
            return;
        }

        var valuesPerWord = 32 / bits;
        var wordCount = (4096 + valuesPerWord - 1) / valuesPerWord;
        for (var wordIndex = 0; wordIndex < wordCount; wordIndex++)
        {
            uint word = 0;
            for (var slot = 0; slot < valuesPerWord; slot++)
            {
                var index = wordIndex * valuesPerWord + slot;
                if (index >= indices.Length) break;
                word |= (uint)indices[index] << (slot * bits);
            }
            writer.WriteUInt32LE(word);
        }
        writer.WriteInt32LE(palette.Count);
        foreach (var value in palette) writer.WriteUInt32LE(value);
    }
}
