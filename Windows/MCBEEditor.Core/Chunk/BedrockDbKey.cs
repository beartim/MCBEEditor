using System.Buffers.Binary;

namespace MCBEEditor.Core.Chunk;

public enum BedrockDimension : int
{
    Overworld = 0,
    Nether = 1,
    End = 2
}

public static class BedrockDimensionNames
{
    public static string DisplayName(int dimension) => dimension switch
    {
        0 => "主世界",
        1 => "下界",
        2 => "末地",
        _ => $"维度 {dimension}"
    };
}

public enum ChunkRecordType : byte
{
    Data3D = 0x2b,
    Version = 0x2c,
    Data2D = 0x2d,
    Data2DLegacy = 0x2e,
    SubChunk = 0x2f,
    LegacyTerrain = 0x30,
    BlockEntity = 0x31,
    Entity = 0x32,
    PendingTicks = 0x33,
    LegacyBlockExtraData = 0x34,
    BiomeState = 0x35,
    FinalizedState = 0x36,
    ConversionData = 0x37,
    BorderBlocks = 0x38,
    HardcodedSpawners = 0x39,
    RandomTicks = 0x3a,
    Checksums = 0x3b,
    GenerationSeed = 0x3c,
    GeneratedPreCavesAndCliffsBlending = 0x3d,
    BlendingBiomeHeight = 0x3e,
    MetadataHash = 0x3f,
    BlendingData = 0x40,
    ActorDigestVersion = 0x41,
    LegacyVersion = 0x76
}

public static class ChunkRecordTypeNames
{
    public static string DisplayName(this ChunkRecordType type) => type switch
    {
        ChunkRecordType.Data3D => "Data3D",
        ChunkRecordType.Version => "Version",
        ChunkRecordType.Data2D => "Data2D",
        ChunkRecordType.Data2DLegacy => "Data2DLegacy",
        ChunkRecordType.SubChunk => "SubChunk",
        ChunkRecordType.LegacyTerrain => "LegacyTerrain",
        ChunkRecordType.BlockEntity => "BlockEntity",
        ChunkRecordType.Entity => "Entity",
        ChunkRecordType.PendingTicks => "PendingTicks",
        ChunkRecordType.LegacyBlockExtraData => "LegacyBlockExtraData",
        ChunkRecordType.BiomeState => "BiomeState",
        ChunkRecordType.FinalizedState => "FinalizedState",
        ChunkRecordType.ConversionData => "ConversionData",
        ChunkRecordType.BorderBlocks => "BorderBlocks",
        ChunkRecordType.HardcodedSpawners => "HardcodedSpawners",
        ChunkRecordType.RandomTicks => "RandomTicks",
        ChunkRecordType.Checksums => "Checksums",
        ChunkRecordType.GenerationSeed => "GenerationSeed",
        ChunkRecordType.GeneratedPreCavesAndCliffsBlending => "GeneratedPreCavesAndCliffsBlending",
        ChunkRecordType.BlendingBiomeHeight => "BlendingBiomeHeight",
        ChunkRecordType.MetadataHash => "MetaDataHash",
        ChunkRecordType.BlendingData => "BlendingData",
        ChunkRecordType.ActorDigestVersion => "ActorDigestVersion",
        ChunkRecordType.LegacyVersion => "LegacyVersion",
        _ => $"0x{(byte)type:x2}"
    };
}

public readonly record struct ChunkPosition(int X, int Z, int Dimension)
{
    public string DimensionName => BedrockDimensionNames.DisplayName(Dimension);
    public string CoordinateText => $"({X}, {Z})";
    public override string ToString() => $"{DimensionName} {CoordinateText}";
}

public readonly record struct BedrockDbKey(ChunkPosition Position, ChunkRecordType RecordType, sbyte? SubChunkIndex)
{
    public static bool TryParse(ReadOnlySpan<byte> data, out BedrockDbKey key)
    {
        key = default;
        if (data.Length < 9) return false;
        var x = BinaryPrimitives.ReadInt32LittleEndian(data[..4]);
        var z = BinaryPrimitives.ReadInt32LittleEndian(data.Slice(4, 4));

        if (Enum.IsDefined(typeof(ChunkRecordType), data[8]))
        {
            var type = (ChunkRecordType)data[8];
            sbyte? sub = type == ChunkRecordType.SubChunk && data.Length >= 10 ? unchecked((sbyte)data[9]) : null;
            key = new BedrockDbKey(new ChunkPosition(x, z, 0), type, sub);
            return true;
        }

        if (data.Length < 13 || !Enum.IsDefined(typeof(ChunkRecordType), data[12]))
            return false;
        var dimension = BinaryPrimitives.ReadInt32LittleEndian(data.Slice(8, 4));
        var modernType = (ChunkRecordType)data[12];
        sbyte? modernSub = modernType == ChunkRecordType.SubChunk && data.Length >= 14 ? unchecked((sbyte)data[13]) : null;
        key = new BedrockDbKey(new ChunkPosition(x, z, dimension), modernType, modernSub);
        return true;
    }

    public byte[] Encode()
    {
        var length = 8 + (Position.Dimension == 0 ? 0 : 4) + 1 + (RecordType == ChunkRecordType.SubChunk && SubChunkIndex.HasValue ? 1 : 0);
        var output = new byte[length];
        BinaryPrimitives.WriteInt32LittleEndian(output.AsSpan(0, 4), Position.X);
        BinaryPrimitives.WriteInt32LittleEndian(output.AsSpan(4, 4), Position.Z);
        var offset = 8;
        if (Position.Dimension != 0)
        {
            BinaryPrimitives.WriteInt32LittleEndian(output.AsSpan(offset, 4), Position.Dimension);
            offset += 4;
        }
        output[offset++] = (byte)RecordType;
        if (RecordType == ChunkRecordType.SubChunk && SubChunkIndex.HasValue)
            output[offset] = unchecked((byte)SubChunkIndex.Value);
        return output;
    }

    public static byte[] SubChunk(int x, int z, int dimension, sbyte index)
        => new BedrockDbKey(new ChunkPosition(x, z, dimension), ChunkRecordType.SubChunk, index).Encode();

    public override string ToString()
    {
        var baseText = $"{Position.DimensionName} ({Position.X}, {Position.Z}) {RecordType.DisplayName()}";
        return SubChunkIndex is null ? baseText : $"{baseText} Y={SubChunkIndex.Value}";
    }
}

public static class BedrockRawChunkKey
{
    public static IReadOnlyList<byte[]> Prefixes(ChunkPosition position)
    {
        var modern = new byte[12];
        BinaryPrimitives.WriteInt32LittleEndian(modern.AsSpan(0, 4), position.X);
        BinaryPrimitives.WriteInt32LittleEndian(modern.AsSpan(4, 4), position.Z);
        BinaryPrimitives.WriteInt32LittleEndian(modern.AsSpan(8, 4), position.Dimension);
        if (position.Dimension != 0) return [modern];

        var legacy = new byte[8];
        BinaryPrimitives.WriteInt32LittleEndian(legacy.AsSpan(0, 4), position.X);
        BinaryPrimitives.WriteInt32LittleEndian(legacy.AsSpan(4, 4), position.Z);
        return [modern, legacy];
    }

    public static bool Matches(ReadOnlySpan<byte> key, ChunkPosition position)
    {
        foreach (var prefix in Prefixes(position))
        {
            if (key.Length > prefix.Length && key.Length <= prefix.Length + 3 && key.StartsWith(prefix))
                return true;
        }
        return false;
    }
}
